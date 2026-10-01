# 仅保存战外完整快照；同目录临时文件校验后原子替换，错误时保留原档。
class_name RpgSaveStore
extends RefCounted

const Catalog = preload("res://scripts/rpg/catalog.gd")
const State = preload("res://scripts/rpg/battle_state.gd")
const Factory = preload("res://scripts/rpg/actor_factory.gd")
const DEFAULT_PATH := "user://rpg_v1/slot_01.json"
const SAFE_PHASES := ["preparation", "exploration", "rest"]
var last_error := ""
var _catalog: RefCounted

func _init(catalog: RefCounted = null) -> void:
	_catalog = catalog
	if _catalog == null:
		_catalog = Catalog.new()
		_catalog.load_all()

func load_safe(path: String = DEFAULT_PATH) -> Dictionary:
	if not _allowed_path(path): return _failure("存档路径必须位于user://rpg_v1且不能经过链接")
	if not FileAccess.file_exists(path): return _failure("找不到安全存档", ERR_FILE_NOT_FOUND)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _failure("无法读取安全存档", FileAccess.get_open_error())
	var contents := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF: return _failure("读取安全存档失败", read_error)
	return _decode(contents)

func write_safe(snapshot: Dictionary, path: String = DEFAULT_PATH) -> Error:
	last_error = ""
	if not _allowed_path(path): return _write_error("禁止写入rpg_v1之外或经过链接的路径", ERR_FILE_BAD_PATH)
	var errors := validate(snapshot)
	if not errors.is_empty(): return _write_error("；".join(errors), ERR_INVALID_DATA)
	# 不把未知schema、损坏或不兼容规则的原档当成空槽；也不擅自备份/删除它。
	if FileAccess.file_exists(path):
		var old := load_safe(path)
		if not old.ok: return _write_error("原档不可覆盖：" + old.error, ERR_INVALID_DATA)
	if DirAccess.dir_exists_absolute(path): return _write_error("存档目标是目录", ERR_FILE_CANT_WRITE)
	var directory := path.get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK: return _write_error("无法建立存档目录", error)
	var temporary := path + ".tmp-" + Crypto.new().generate_random_bytes(12).hex_encode()
	var text := JSON.stringify(snapshot, "", true, true)
	error = _write_temporary(temporary, text)
	if error == OK:
		var check := load_safe(temporary)
		if not check.ok or FileAccess.get_file_as_string(temporary) != text:
			error = ERR_FILE_CORRUPT
	if error == OK: error = _replace_file(temporary, path)
	if error != OK:
		if FileAccess.file_exists(temporary): DirAccess.remove_absolute(temporary)
		return _write_error("安全存档提交失败，原档保持不变", error)
	return OK

# 单独边界便于故障注入；生产实现不会先删除目标文件。
func _write_temporary(path: String, contents: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(contents)
	file.flush()
	var error := file.get_error()
	file.close()
	return error

func _replace_file(temporary: String, destination: String) -> Error:
	return DirAccess.rename_absolute(temporary, destination)

func _decode(contents: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(contents) != OK or not json.data is Dictionary: return _failure("存档JSON损坏", ERR_FILE_CORRUPT)
	var normalized := normalize(json.data)
	var errors := validate(normalized)
	if not errors.is_empty(): return _failure("；".join(errors), ERR_INVALID_DATA)
	last_error = ""
	return {"ok": true, "snapshot": normalized, "error": "", "code": OK}

func normalize(value: Dictionary) -> Dictionary:
	var saved := value.duplicate(true)
	State._int_fields(saved, ["schema_version", "level", "xp", "battle_counter"])
	var normalized := State.normalize_snapshot({"actors": saved.get("roster", {}), "inventory": saved.get("inventory", {})})
	if saved.has("roster"): saved.roster = normalized.actors
	if saved.has("inventory"): saved.inventory = normalized.inventory
	if saved.get("world") is Dictionary:
		State._int_fields(saved.world, ["facing", "spirit", "party_index"])
	if saved.get("pending_battle") is Dictionary:
		State._int_fields(saved.pending_battle, ["seed", "xp"])
	return saved

func validate(saved: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not State._plain(saved): return ["存档只允许有限JSON值"]
	if not saved.get("schema_version") is int or saved.get("schema_version") != 1: errors.append("未知存档schema_version，保留文件原样")
	if not saved.get("rules_version") is String or saved.get("rules_version") != _catalog.rules_version: errors.append("存档规则版本不兼容")
	if not SAFE_PHASES.has(saved.get("phase")): errors.append("只允许战外安全状态保存，战斗或过场不可存档")
	if not saved.get("run_id") is String or saved.get("run_id", "").is_empty(): errors.append("缺少运行ID")
	if not saved.get("level") is int or saved.level < 1 or saved.level > 10: errors.append("队伍等级非法")
	if not State._natural(saved.get("xp")): errors.append("经验非法")
	elif saved.get("level") is int and ((saved.level == 10 and saved.xp != 0) or saved.xp >= saved.level * 100): errors.append("经验与等级阈值不符")
	if not State._natural(saved.get("battle_counter")): errors.append("战斗计数非法")
	if not saved.get("next_encounter_id") is String or (not saved.get("next_encounter_id", "").is_empty() and _catalog.get_definition("encounters", saved.next_encounter_id).is_empty()): errors.append("后续遭遇引用非法")
	if saved.has("return_scene") and (not saved.return_scene is String or (not saved.return_scene.is_empty() and (not saved.return_scene.begins_with("res://scenes/") or not saved.return_scene.ends_with(".tscn")))): errors.append("已提交返回场景非法")
	if not saved.get("roster") is Dictionary or not saved.get("inventory") is Dictionary:
		errors.append("缺少六人名单或库存")
		return errors
	if not errors.is_empty(): return errors
	var roster: Dictionary = saved.roster
	if roster.size() != 6: errors.append("必须保留完整六人名单")
	var factory := Factory.new(_catalog)
	for class_id in Catalog.CLASS_IDS:
		var id := "p_" + str(class_id)
		if not roster.get(id) is Dictionary:
			errors.append("缺少固定角色：" + id)
			continue
		var actor: Dictionary = roster[id]
		var shape_errors := _actor_shape(actor)
		if not shape_errors.is_empty():
			errors.append_array(shape_errors)
			continue
		if actor.get("class_id") != class_id or actor.get("side") != "player" or actor.get("level") != saved.get("level"): errors.append("固定职业/共享等级不符：" + id)
		if actor.get("equipment") is Dictionary and actor.get("level") is int:
			if actor.get("stats") != factory.stats_for(class_id, actor.level, actor.equipment): errors.append("角色属性与职业/等级/装备不符：" + id)
		if not _valid_branch(actor): errors.append("技能分支引用/解锁非法：" + id)
		for field in ["statuses", "shield", "cooldown_until", "intent", "boss"]:
			var value = actor.get(field)
			if not (value is Array or value is Dictionary) or not value.is_empty(): errors.append("安全档不能遗留战斗临时状态：" + id + "/" + field)
	if not errors.is_empty(): return errors
	var battle := {"schema_version": 1, "rules_version": saved.get("rules_version"), "revision": 0, "seed": 0, "rng_state": "0", "round": 0, "phase": "preparation", "queue": [], "queue_index": 0, "active_actor_id": "", "actors": roster, "inventory": saved.inventory, "outcome": "", "accepted_commands": {}}
	errors.append_array(State.validate(battle))
	for item_id in _catalog.get_ids("items"):
		if not saved.inventory.has(item_id): errors.append("库存缺少固定道具：" + item_id)
	var party = saved.get("party")
	if not party is Array or party.size() != 3:
		errors.append("编队必须三人")
	else:
		var seen: Dictionary = {}
		for id in party:
			if not id is String or not roster.has(id) or seen.has(id): errors.append("编队引用缺失/重复")
			seen[id] = true
	errors.append_array(validate_world(saved.get("world")))
	var applied = saved.get("applied_battle_ids")
	if not applied is Array:
		errors.append("缺少已提交战斗ID")
	else:
		var seen: Dictionary = {}
		for id in applied:
			if not id is String or id.is_empty() or seen.has(id): errors.append("已提交战斗ID非法/重复")
			seen[id] = true
	var pending = saved.get("pending_battle")
	if not pending is Dictionary:
		errors.append("缺少战前上下文")
	elif not pending.is_empty():
		var definition: Dictionary = _catalog.get_definition("encounters", str(pending.get("encounter_id", "")))
		if definition.is_empty() or not pending.get("battle_id") is String or pending.get("battle_id", "").is_empty() or not pending.get("seed") is int: errors.append("战前遭遇/战斗ID/种子非法")
		if not pending.get("xp") is int or pending.get("xp") != definition.get("xp"): errors.append("战前经验与遭遇冲突")
		if pending.get("battle_id") is String and applied is Array and applied.has(pending.battle_id): errors.append("已交付战果不能仍待处理")
		if saved.get("world") is Dictionary: errors.append_array(validate_story_patch(pending.get("story_patch"), saved.world))
	return errors

static func _actor_shape(actor: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for field in ["actor_id", "side", "class_id"]:
		if not actor.get(field) is String: errors.append("角色字符串字段错误：" + field)
	for field in ["level", "hp", "mp", "slot_count", "opportunity_count", "revived_round"]:
		if not actor.get(field) is int: errors.append("角色整数字段错误：" + field)
	for field in ["stats", "equipment", "branch", "shield", "cooldown_until", "intent", "boss"]:
		if not actor.get(field) is Dictionary: errors.append("角色字典字段错误：" + field)
	for field in ["skill_ids", "statuses"]:
		if not actor.get(field) is Array: errors.append("角色数组字段错误：" + field)
	return errors

func _valid_branch(actor: Dictionary) -> bool:
	var branch = actor.get("branch")
	if not branch is Dictionary: return false
	if branch.is_empty(): return true
	if branch.size() != 1 or not actor.get("level") is int or actor.level < 6 or not branch.get("id") is String: return false
	return branch_ids(str(actor.get("class_id", ""))).has(branch.id)

# 分支数值来源是固定技能目录；游侠的duration/power分别定义在标记与猎杀。
func branch_ids(class_id: String) -> Array[String]:
	var ids: Array[String] = []
	var definition: Dictionary = _catalog.get_definition("classes", class_id)
	for skill_id in definition.get("skill_ids", []):
		var skill: Dictionary = _catalog.get_definition("skills", skill_id)
		for branch_id in skill.get("branches", {}):
			if not ids.has(branch_id): ids.append(branch_id)
	ids.sort()
	return ids

static func validate_world(world) -> Array[String]:
	var errors: Array[String] = []
	if not world is Dictionary or not State._plain(world): return ["世界状态必须为纯JSON字典"]
	if world.is_empty(): return errors # 独立切片尚未进入旧舞台。
	if not world.get("scene_path") is String or not world.get("scene_path", "").begins_with("res://scenes/") or not world.get("scene_path", "").ends_with(".tscn"): errors.append("世界场景路径非法")
	if not (world.get("player_x") is int or world.get("player_x") is float) or not is_finite(float(world.get("player_x", NAN))): errors.append("玩家位置非法")
	if not world.get("facing") is int or not world.get("facing") in [-1, 1]: errors.append("玩家朝向非法")
	for field in ["spirit", "party_index"]:
		if not State._natural(world.get(field)): errors.append("世界计数非法：" + field)
	if not world.get("exit_prompted") is bool: errors.append("出口提示标记非法")
	for field in ["resolved", "dlg_fired"]:
		if not world.get(field) is Dictionary:
			errors.append("世界标记字典缺失：" + field)
			continue
		for id in world[field]:
			if not id is String or id.is_empty() or not world[field][id] is bool or world[field][id] != true: errors.append("世界标记非法：" + field)
	return errors

static func validate_story_patch(patch, world: Dictionary) -> Array[String]:
	if not patch is Dictionary: return ["剧情补丁必须为字典"]
	for key in patch:
		if not key in ["resolved", "next_scene"]: return ["剧情补丁仅支持现有线索及场景出口"]
	if patch.has("resolved"):
		if world.is_empty() or not patch.resolved is Dictionary: return ["线索补丁缺少世界"]
		for id in patch.resolved:
			if not id is String or id.is_empty() or not patch.resolved[id] is bool or patch.resolved[id] != true: return ["线索补丁非法"]
	if patch.has("next_scene") and (not patch.next_scene is String or not patch.next_scene.begins_with("res://scenes/") or not patch.next_scene.ends_with(".tscn")): return ["出口场景非法"]
	return []

func _allowed_path(path: String) -> bool:
	if not path.begins_with("user://rpg_v1/") or path.ends_with("/") or path.contains("\\"): return false
	var relative := path.trim_prefix("user://")
	var current := "user://"
	for part in relative.split("/"):
		if part.is_empty() or part in [".", ".."]: return false
		var directory := DirAccess.open(current)
		if directory != null and directory.is_link(part): return false
		current = current.path_join(part)
	return true

func _failure(message: String, code: Error = ERR_INVALID_DATA) -> Dictionary:
	last_error = message
	return {"ok": false, "snapshot": {}, "error": message, "code": code}

func _write_error(message: String, code: Error) -> Error:
	last_error = message
	return code
