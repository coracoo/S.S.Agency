# 六人持久队伍与三人战斗隔离；所有战外操作先写完整安全档，再公布结果。
class_name RpgCampaign
extends RefCounted

const Catalog = preload("res://scripts/rpg/catalog.gd")
const Factory = preload("res://scripts/rpg/actor_factory.gd")
const State = preload("res://scripts/rpg/battle_state.gd")
const Store = preload("res://scripts/rpg/save_store.gd")
const Resolver = preload("res://scripts/rpg/effect_resolver.gd")
var _catalog: RefCounted
var _store: RefCounted
var _path: String
var _safe: Dictionary = {}
var _mode := ""
var last_error := ""

func _init(catalog: RefCounted = null, store: RefCounted = null, path: String = Store.DEFAULT_PATH) -> void:
	_catalog = catalog
	if _catalog == null:
		_catalog = Catalog.new()
		_catalog.load_all()
	_store = store if store != null else Store.new(_catalog)
	_path = path

func new_run(class_ids: Array[String], level: int = 5) -> Dictionary:
	if class_ids.size() != 3 or level < 1 or level > 10: return _fail("新局需要三个不同职业与1–10级")
	var party: Array[String] = []
	for id in class_ids:
		if not Catalog.CLASS_IDS.has(id) or party.has("p_" + id): return _fail("出战职业未知或重复")
		party.append("p_" + id)
	var factory := Factory.new(_catalog)
	var roster: Dictionary = {}
	for id in Catalog.CLASS_IDS: roster["p_" + id] = factory.create(id, "p_" + id, level, Factory.STANDARD)
	var inventory: Dictionary = {}
	for item in _catalog.get_all("items"): inventory[item.id] = item.initial_stock
	var candidate := {"schema_version": 1, "rules_version": _catalog.rules_version, "run_id": Crypto.new().generate_random_bytes(16).hex_encode(), "phase": "preparation", "level": level, "xp": 0, "roster": roster, "party": party, "inventory": inventory, "world": {}, "applied_battle_ids": [], "battle_counter": 0, "next_encounter_id": "slice_1", "pending_battle": {}, "return_scene": ""}
	return _commit(candidate, true)

func load_run() -> Dictionary:
	var loaded: Dictionary = _store.load_safe(_path)
	if not loaded.ok: return _fail(loaded.error)
	_safe = loaded.snapshot.duplicate(true)
	_mode = _safe.phase
	last_error = ""
	return _ok()

func snapshot() -> Dictionary:
	var result := safe_snapshot()
	if not result.is_empty(): result.phase = _mode
	return result

func safe_snapshot() -> Dictionary:
	return _safe.duplicate(true)

# 可选补丁只由场景路由提供；不携带Node、旧奖励或自创剧情。
func begin_battle(encounter_id: String, world: Dictionary, story_patch: Dictionary = {}) -> Dictionary:
	if not _outside(): return _fail("当前不在可进战的安全状态")
	var definition: Dictionary = _catalog.get_definition("encounters", encounter_id)
	if definition.is_empty(): return _fail("未知遭遇：" + encounter_id)
	var world_errors := Store.validate_world(world)
	world_errors.append_array(Store.validate_story_patch(story_patch, world))
	if not world_errors.is_empty(): return _fail("；".join(world_errors))
	var alive := false
	for id in _safe.party: alive = alive or _safe.roster[id].hp > 0
	if not alive: return _fail("出战三人全部倒地，请先复苏或休息")
	var candidate := safe_snapshot()
	candidate.world = world.duplicate(true)
	candidate["return_scene"] = ""
	candidate.battle_counter += 1
	var battle_id: String = candidate.run_id + ":" + str(candidate.battle_counter)
	candidate.pending_battle = {"battle_id": battle_id, "encounter_id": encounter_id, "seed": int(battle_id.hash()), "xp": definition.xp, "story_patch": story_patch.duplicate(true)}
	var committed := _commit(candidate)
	if not committed.ok: return committed
	_mode = "battle"
	return _battle_setup()

func retry_battle() -> Dictionary:
	if _safe.is_empty() or _safe.pending_battle.is_empty(): return _fail("没有战前快照可重试")
	# _safe从未被战斗写入；同一ID、种子、资源、世界，不能重掷或补给。
	_mode = "battle"
	last_error = ""
	return _battle_setup()

func apply_result(result: Dictionary) -> Dictionary:
	if _safe.is_empty(): return _fail("尚未建立队伍")
	if not result.get("battle_id") is String or result.battle_id.is_empty(): return _fail("战果缺少battle_id")
	if _safe.applied_battle_ids.has(result.battle_id): return _ok(true)
	# 读取持久提交记录，避免加载同一战前档的另一实例再次公布奖励/剧情。
	var durable: Dictionary = _store.load_safe(_path)
	if not durable.ok: return _fail("无法核验已提交战果：" + durable.error)
	if durable.snapshot.run_id != _safe.run_id: return _fail("存档已切换新局，请重新读取")
	if durable.snapshot.applied_battle_ids.has(result.battle_id):
		_safe = durable.snapshot.duplicate(true)
		_mode = _safe.phase
		return _ok(true)
	if durable.snapshot != _safe: return _fail("安全进度已更新，请重新读取后重试")
	if _safe.pending_battle.is_empty() or result.battle_id != _safe.pending_battle.battle_id or not _mode in ["battle", "defeat"]: return _fail("战果不属于当前战斗")
	var errors := _result_errors(result)
	if not errors.is_empty(): return _fail("；".join(errors))
	if result.outcome == "defeat":
		_mode = "defeat"
		return _ok()
	var candidate := safe_snapshot()
	for actor in result.roster:
		# 战果只有出战者。保留替补及同schema扩展，不能按三人重建六人名单。
		var persisted: Dictionary = candidate.roster[actor.actor_id]
		persisted.hp = actor.hp
		persisted.mp = actor.mp
		_clear_battle_state(persisted)
	candidate.inventory = result.inventory.duplicate(true)
	_add_xp(candidate, result.xp)
	var patch: Dictionary = candidate.pending_battle.story_patch
	if patch.has("resolved"): candidate.world.resolved.merge(patch.resolved, true)
	candidate["return_scene"] = patch.get("next_scene", candidate.world.get("scene_path", "res://scenes/rpg/launcher.tscn"))
	var encounter: Dictionary = _catalog.get_definition("encounters", candidate.pending_battle.encounter_id)
	candidate.next_encounter_id = encounter.next_id
	candidate.phase = "rest" if encounter.rest_after else "exploration"
	candidate.applied_battle_ids.append(result.battle_id)
	candidate.pending_battle = {}
	var committed := _commit(candidate)
	if committed.ok:
		committed.story_patch = patch.duplicate(true)
		committed.world = _safe.world.duplicate(true)
	return committed

# 探索菜单仅保存当前世界；不推进剧情、治疗或改变战外阶段。
func save_exploration(world: Dictionary) -> Dictionary:
	if not _outside(): return _fail("当前不能打开探索整备")
	var errors := Store.validate_world(world)
	if world.is_empty() or not errors.is_empty(): return _fail("探索整备缺少有效世界")
	var candidate := safe_snapshot()
	candidate.world = world.duplicate(true)
	candidate.return_scene = world.scene_path
	return _commit(candidate)

# 视图读取模型权限，不能将安全战外用药误绑到休息点。
func can_use_outside_items() -> bool:
	return _outside()

func can_prepare() -> bool:
	return _preparing()

# 仪式沿用原玩法与入场线索语义，只把进出场世界放入隔离安全档。
func begin_ritual(world: Dictionary) -> Dictionary:
	if not _outside(): return _fail("当前不能进入仪式")
	var errors := Store.validate_world(world)
	if world.is_empty() or not errors.is_empty(): return _fail("仪式缺少有效探索世界")
	var candidate := safe_snapshot()
	candidate.world = world.duplicate(true)
	candidate["return_scene"] = world.scene_path
	var committed := _commit(candidate)
	if committed.ok:
		_mode = "ritual"
		committed["world"] = _safe.world.duplicate(true)
	return committed

func finish_ritual() -> Dictionary:
	if _mode != "ritual": return _fail("没有当前仪式上下文")
	# 返场也走统一版本/写失败边界；失败留在仪式，允许再次点击返回。
	var committed := _commit(safe_snapshot())
	if committed.ok: committed["world"] = _safe.world.duplicate(true)
	return committed

func rest() -> Dictionary:
	if not _preparing(): return _fail("只能在战前准备或明确休息点休息")
	var candidate := safe_snapshot()
	for actor in candidate.roster.values():
		_clear_battle_state(actor)
		actor.hp = actor.stats.hp
		actor.mp = actor.stats.mp
	return _commit(candidate)

func use_item_outside(item_id: String, target_id: String) -> Dictionary:
	if not _outside() or not _safe.roster.has(target_id): return _fail("当前无法对该角色使用战外道具")
	var item: Dictionary = _catalog.get_definition("items", item_id)
	if item.is_empty() or _safe.inventory.get(item_id, 0) < 1: return _fail("道具未知或库存不足")
	var target: Dictionary = _safe.roster[target_id]
	if (item.target_rule == "fallen_ally") != (target.hp == 0): return _fail("道具不能用于当前存活/倒地目标")
	var candidate := safe_snapshot()
	var before: Dictionary = candidate.roster[target_id].duplicate(true)
	var state := {"actors": candidate.roster, "round": 0}
	var command := {"actor_id": target_id, "kind": "item", "ability_id": item_id, "target_ids": [target_id]}
	Resolver.resolve(state, command, _catalog, null)
	if before == candidate.roster[target_id]: return _fail("该道具没有有效作用")
	_clear_battle_state(candidate.roster[target_id])
	candidate.inventory[item_id] -= 1
	return _commit(candidate)

func set_party(actor_ids: Array[String]) -> Dictionary:
	if not _preparing() or actor_ids.size() != 3: return _fail("准备/休息点需选择三名不同队员")
	var seen: Dictionary = {}
	for id in actor_ids:
		if not _safe.roster.has(id) or seen.has(id): return _fail("出战角色未知或重复")
		seen[id] = true
	var candidate := safe_snapshot()
	candidate.party = actor_ids.duplicate()
	return _commit(candidate)

func equip(actor_id: String, slot: String, item_id: String) -> Dictionary:
	if not _preparing() or not _safe.roster.has(actor_id) or not Factory.STANDARD.has(slot): return _fail("当前不能更换该装备槽")
	var definition: Dictionary = _catalog.get_definition("equipment", item_id)
	if not item_id.is_empty() and (definition.is_empty() or definition.slot != slot): return _fail("装备ID未知或槽位不符")
	var candidate := safe_snapshot()
	var actor: Dictionary = candidate.roster[actor_id]
	actor.equipment[slot] = item_id
	actor.stats = Factory.new(_catalog).stats_for(actor.class_id, actor.level, actor.equipment)
	actor.hp = mini(actor.hp, actor.stats.hp)
	actor.mp = mini(actor.mp, actor.stats.mp)
	return _commit(candidate)

func set_branch(actor_id: String, branch_id: String) -> Dictionary:
	if not _preparing() or not _safe.roster.has(actor_id): return _fail("只在准备/休息点更换分支")
	var actor: Dictionary = _safe.roster[actor_id]
	if not branch_id.is_empty() and (actor.level < 6 or not Store.new(_catalog).branch_ids(actor.class_id).has(branch_id)): return _fail("分支尚未解锁或未定义")
	var candidate := safe_snapshot()
	candidate.roster[actor_id].branch = {} if branch_id.is_empty() else {"id": branch_id}
	return _commit(candidate)

func _battle_setup() -> Dictionary:
	var pending: Dictionary = _safe.pending_battle
	var encounter: Dictionary = _catalog.get_definition("encounters", pending.encounter_id)
	var actors: Dictionary = {}
	for id in _safe.party:
		actors[id] = _safe.roster[id].duplicate(true)
		_clear_battle_state(actors[id])
	for index in range(encounter.enemy_ids.size()):
		var enemy_id: String = encounter.enemy_ids[index]
		var id := "e_%02d_%s" % [index + 1, enemy_id]
		actors[id] = _enemy(enemy_id, id, encounter.level)
	return {"ok": true, "error": "", "setup": {"actors": actors, "inventory": _safe.inventory.duplicate(true)}, "seed": pending.seed, "battle_id": pending.battle_id, "encounter_id": pending.encounter_id, "xp": pending.xp, "story_patch": pending.story_patch.duplicate(true), "world": _safe.world.duplicate(true)}

func _enemy(enemy_id: String, id: String, level: int) -> Dictionary:
	var definition: Dictionary = _catalog.get_definition("enemies", enemy_id)
	var stats: Dictionary = definition.base_stats.duplicate(true)
	for key in Factory.STAT_KEYS:
		stats[key] = maxi(1 if key == "hp" else 0, int(stats[key]) + level - 5) if key == "spd" else maxi(1 if key == "hp" else 0, roundi(float(stats[key]) * (1.0 + 0.1 * (level - 5))))
	var skill_ids: Array[String] = []
	for ability in definition.abilities: skill_ids.append(ability.id)
	return {"actor_id": id, "side": "enemy", "class_id": enemy_id, "level": level, "stats": stats, "hp": stats.hp, "mp": stats.mp, "equipment": {}, "skill_ids": skill_ids, "branch": {}, "slot_count": 0, "opportunity_count": 0, "statuses": [], "shield": {}, "cooldown_until": {}, "revived_round": -1, "intent": {}, "boss": {}, "weaknesses": definition.weaknesses.duplicate(), "resistances": definition.resistances.duplicate()}

func _result_errors(result: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not State._plain(result): return ["战果只能包含JSON值"]
	if not result.get("outcome") in ["victory", "defeat"]: return ["战果胜负非法"]
	if not result.get("xp") is int or result.xp != (_safe.pending_battle.xp if result.outcome == "victory" else 0): errors.append("战果经验与遭遇不符")
	if not result.get("story_patch") is Dictionary or result.story_patch != (_safe.pending_battle.story_patch if result.outcome == "victory" else {}): errors.append("战果剧情补丁与进战承诺不符")
	if not result.get("replay") is Dictionary: errors.append("战果缺少重放字典")
	if not result.get("roster") is Array or result.roster.size() != 3: return ["战果必须包含恰好三名出战者"]
	var seen: Dictionary = {}
	var alive := false
	for actor in result.roster:
		if not actor is Dictionary or not actor.get("actor_id") is String or not _safe.party.has(actor.get("actor_id")) or seen.has(actor.get("actor_id")):
			errors.append("战果角色未知/非出战者/重复")
			continue
		seen[actor.actor_id] = true
		var original: Dictionary = _safe.roster[actor.actor_id]
		for field in ["actor_id", "side", "class_id", "level", "stats", "equipment", "skill_ids", "branch"]:
			if typeof(actor.get(field)) != typeof(original[field]) or actor.get(field) != original[field]: errors.append("战果不能改写角色设定：" + field)
		for field in ["hp", "mp"]:
			if not State._natural(actor.get(field)) or actor[field] > original.stats[field]: errors.append("战果资源越界：" + field)
		if State._natural(actor.get("hp")) and actor.hp > 0: alive = true
	if alive != (result.outcome == "victory"): errors.append("胜负与出战者存活情况冲突")
	if not result.get("inventory") is Dictionary:
		errors.append("战果缺少库存")
	else:
		if result.inventory.size() != _safe.inventory.size(): errors.append("战果库存类型集合不能变化")
		for id in result.inventory:
			if not _safe.inventory.has(id) or not State._natural(result.inventory[id]) or result.inventory[id] > _safe.inventory.get(id, 0): errors.append("战果库存非法或未经定义的物品奖励")
	return errors

static func _clear_battle_state(actor: Dictionary) -> void:
	actor.statuses = []
	for field in ["shield", "cooldown_until", "intent", "boss"]: actor[field] = {}
	for field in ["slot_count", "opportunity_count", "last_slot_round", "status_generation"]: actor[field] = 0
	actor.revived_round = -1

func _add_xp(candidate: Dictionary, amount: int) -> void:
	if candidate.level == 10: return
	candidate.xp += amount
	while candidate.level < 10 and candidate.xp >= 100 * candidate.level:
		candidate.xp -= 100 * candidate.level
		candidate.level += 1
	if candidate.level == 10: candidate.xp = 0
	var factory := Factory.new(_catalog)
	for actor in candidate.roster.values():
		actor.level = candidate.level
		actor.stats = factory.stats_for(actor.class_id, actor.level, actor.equipment)
		actor.hp = mini(actor.hp, actor.stats.hp)
		actor.mp = mini(actor.mp, actor.stats.mp)

func _outside() -> bool:
	return not _safe.is_empty() and _mode in Store.SAFE_PHASES and _safe.pending_battle.is_empty()

func _preparing() -> bool:
	return _outside() and _mode in ["preparation", "rest"] and _safe.pending_battle.is_empty()

func _commit(candidate: Dictionary, explicit_new_run: bool = false) -> Dictionary:
	# 所有普通修改共享同一版本前置条件，不能用陈旧准备/休息态撤销已交付ID。
	# 当前Godot主线程同步调用在核验与write间不让出执行；不承诺多进程互斥。
	if not explicit_new_run:
		if _safe.is_empty(): return _fail("普通修改缺少已读取的安全基线")
		var durable: Dictionary = _store.load_safe(_path)
		if not durable.ok: return _fail("无法核验安全基线：" + durable.error)
		if durable.snapshot != _safe: return _fail("安全进度已更新，请重新读取后重试")
	var error: Error = _store.write_safe(candidate, _path)
	if error != OK: return _fail("安全存档写入失败（%d），原进度和战果未改动" % error)
	# 与磁盘同一次JSON运输规范化，保留扩展且便于后续冲突核验。
	_safe = Store.new(_catalog).normalize(JSON.parse_string(JSON.stringify(candidate, "", true, true)))
	_mode = _safe.phase
	last_error = ""
	return _ok()

func _ok(already_applied: bool = false) -> Dictionary:
	return {"ok": true, "already_applied": already_applied, "error": "", "story_patch": {}}

func _fail(message: String) -> Dictionary:
	last_error = message
	return {"ok": false, "already_applied": false, "error": message, "story_patch": {}}
