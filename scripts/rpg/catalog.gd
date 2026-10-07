# 独立 RPG JSON 目录：先整批校验，再发布深复制查询，失败不保留半加载数据。
class_name RpgCatalog
extends RefCounted

const Refinements = preload("res://scripts/rpg/character_refinements.gd")
const Forms = preload("res://scripts/rpg/dual_form.gd")
const KINDS := ["classes", "skills", "statuses", "enemies", "items", "equipment", "encounters"]
const CLASS_IDS := ["guard", "swordsman", "ranger", "mage", "healer", "controller"]
const STAT_KEYS := ["hp", "mp", "atk", "matk", "def", "mdef", "spd"]
const ELEMENTS := ["neutral", "fire", "ice", "lightning", "spirit"]
const CLOCKS := ["target_slot", "round_snapshot", "next_owner_slot"]
const TARGETS := ["self", "other_ally", "single_ally", "all_allies", "single_enemy", "all_enemies", "fallen_ally"]
const EFFECTS := ["damage", "apply_status", "consume_status", "interrupt", "shield", "heal", "cleanse", "restore_hp", "restore_mp", "revive", "charge"]

var rules_version: String = ""
var _definitions: Dictionary = {}

func load_all(root_path: String = "res://data/rpg") -> Array[String]:
	_definitions.clear()
	rules_version = ""
	var errors: Array[String] = []
	var candidate: Dictionary = {}
	var version := ""
	for kind in KINDS:
		candidate[kind] = {}
		var path := root_path.path_join(kind + ".json")
		if not FileAccess.file_exists(path):
			errors.append("缺少数据文件：" + path)
			continue
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK:
			errors.append("JSON 解析失败：%s:%d %s" % [path, json.get_error_line(), json.get_error_message()])
			continue
		var document = json.data
		if not document is Dictionary or document.get("schema_version") != 1 or not document.get("rules_version") is String or not document.get("definitions") is Array:
			errors.append("数据结构／版本非法：" + kind)
			continue
		if version.is_empty():
			version = document.rules_version
		if version.is_empty() or document.rules_version != version:
			errors.append("规则版本不一致：" + kind)
		for raw in document.definitions:
			if not raw is Dictionary or not raw.get("id") is String or raw.id.is_empty():
				errors.append("定义缺少有效 ID：" + kind)
				continue
			if candidate[kind].has(raw.id):
				errors.append("重复 ID：%s/%s" % [kind, raw.id])
				continue
			candidate[kind][raw.id] = _integerize(raw)
	# 后六章新增敌人与遭遇独立导出，避免旧XLSX重导覆盖主线扩展。
	if root_path == "res://data/rpg":
		for kind in ["enemies", "encounters"]:
			var extra_path := root_path.path_join("saga_" + kind + ".json")
			if not FileAccess.file_exists(extra_path): continue
			var extra = JSON.parse_string(FileAccess.get_file_as_string(extra_path))
			if not extra is Dictionary or extra.get("schema_version") != 1 or extra.get("rules_version") != version or not extra.get("definitions") is Array:
				errors.append("后续数据结构/版本非法：" + kind)
				continue
			for raw in extra.definitions:
				if not raw is Dictionary or not raw.get("id") is String or raw.id.is_empty() or candidate[kind].has(raw.id):
					errors.append("后续定义缺少ID或与原定义冲突：" + kind)
					continue
				candidate[kind][raw.id] = _integerize(raw)
	_validate_catalog(candidate, errors)
	if errors.is_empty(): _load_refinements(root_path, version, candidate, errors)
	if errors.is_empty():
		_definitions = candidate
		rules_version = version
	return errors

func get_definition(kind: String, id: String) -> Dictionary:
	return _definitions.get(kind, {}).get(id, {}).duplicate(true)

func get_ids(kind: String) -> Array[String]:
	var ids: Array[String] = []
	for id in _definitions.get(kind, {}):
		ids.append(id)
	ids.sort()
	return ids

func get_all(kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in get_ids(kind):
		result.append(get_definition(kind, id))
	return result

# 新重放绑定实际数据内容；战役存档不携带此指纹，也不因此失去读档兼容。
func mechanics_fingerprint() -> String:
	return JSON.stringify(_definitions, "", true, true).sha256_text()

# 四卡和基础表不变；分支先派生，身份专精后派生，调用者总是拿到深复制。
func skill_for(actor: Dictionary, skill_id: String) -> Dictionary:
	var skill := get_definition("skills", skill_id)
	var own: Array = get_definition("classes", Forms.active_class(actor)).get("skill_ids", [])
	if skill.is_empty() or not own.has(skill_id): return {}
	var branch: Dictionary = actor.get("branch", {})
	if int(actor.get("level", 1)) >= 6 and branch.size() == 1 and branch.get("id") is String:
		var tier := "9" if int(actor.level) >= 9 else "6"
		var overrides: Dictionary = skill.get("branches", {}).get(branch.id, {}).get(tier, {})
		for field in overrides:
			if field == "mp_cost": skill.mp_cost = overrides[field]
			else:
				for effect in skill.effects:
					if effect.has(field): effect[field] = overrides[field]
	var refinement := refinement_for(actor)
	if refinement.get("skill_id") == skill_id and int(actor.get("level", 1)) >= int(refinement.unlock_level):
		skill = Refinements.apply(skill, refinement)
	for technique in refinement.get("techniques", []):
		if technique.skill_id == skill_id and int(actor.get("level", 1)) >= int(technique.unlock_level):
			skill = Refinements.apply_technique(skill, technique)
	return skill

func refinement_for(actor: Dictionary) -> Dictionary:
	return Refinements.for_actor(actor, _definitions.get("refinements", {}))

# 单独JSON不会被旧XLSX重导覆盖；坏扩展与坏基础表同样整批失败关闭。
func _load_refinements(root_path: String, version: String, candidate: Dictionary, errors: Array[String]) -> void:
	candidate["refinements"] = {}
	var path := root_path.path_join("character_refinements.json")
	if not FileAccess.file_exists(path):
		if root_path == "res://data/rpg": errors.append("缺少七形态个人专精数据")
		return
	var document = _integerize(JSON.parse_string(FileAccess.get_file_as_string(path)))
	if not document is Dictionary or document.get("schema_version") != 1 or document.get("rules_version") != version or not document.get("definitions") is Array:
		errors.append("个人专精数据结构/版本非法")
		return
	for row in document.definitions:
		if not row is Dictionary or not row.get("id") is String or candidate.refinements.has(row.id):
			errors.append("个人专精ID非法/重复")
			continue
		candidate.refinements[row.id] = row
	if candidate.refinements.size() != 7: errors.append("个人专精必须覆盖七形态")
	for id in candidate.refinements:
		var row: Dictionary = candidate.refinements[id]
		var count := errors.size()
		var fields := ["id", "identity_id", "active_class_id", "skill_id", "name", "summary", "tactic", "unlock_level", "mp_cost_add", "cooldown_add", "damage_condition", "extra_effects", "techniques"]
		if row.size() != fields.size(): errors.append(id + " 个人专精字段不完整/未知")
		for field in row:
			if not fields.has(field): errors.append(id + " 未知个人专精字段：" + field)
		for field in ["name", "summary", "tactic"]:
			if not row.get(field) is String or row.get(field, "").is_empty(): errors.append(id + " 缺个人专精说明：" + field)
		if not Refinements.BINDINGS.has(id) or [row.get("identity_id"), row.get("active_class_id"), row.get("skill_id")] != Refinements.BINDINGS.get(id, []): errors.append(id + " 身份/形态/技能归属不符")
		if row.get("unlock_level") != 3: errors.append(id + " 个人专精仅L3开放")
		for field in ["mp_cost_add", "cooldown_add"]:
			if not _nonnegative_int(row.get(field)): errors.append(id + " 专精费用/CD增量非法")
		var condition = row.get("damage_condition")
		if not condition is Dictionary:
			errors.append(id + " 专精条件必须为字典")
		elif not condition.is_empty():
			if condition.size() != 2 or not candidate.statuses.has(condition.get("status_id")) or not _number(condition.get("coefficient_add")): errors.append(id + " 专精条件状态/增量非法")
		if not row.get("extra_effects") is Array:
			errors.append(id + " 专精附加效果必须为数组")
		elif not row.extra_effects.is_empty():
			_validate_effects(row.extra_effects, id, candidate, errors)
			for effect in row.extra_effects:
				if not effect is Dictionary or not effect.get("type") in ["apply_status", "shield"]: errors.append(id + " 专精只复用状态/护盾附加效果")
		if errors.size() != count or not candidate.skills.has(row.get("skill_id")): continue
		var base: Dictionary = candidate.skills[row.skill_id]
		if not condition.is_empty() and not base.effects.any(func(effect): return effect.type == "damage" and not effect.has("condition")): errors.append(id + " 专精条件需无原条件的伤害效果")
		_validate_ability(Refinements.apply(base, row), candidate, errors)
		_validate_techniques(row, candidate, errors)

static func _validate_techniques(row: Dictionary, data: Dictionary, errors: Array[String]) -> void:
	var label: String = row.id
	if not row.get("techniques") is Array or row.techniques.size() != 2:
		errors.append(label + " 必须定义L4/L5两项技法")
		return
	var owned: Array = data.classes[row.active_class_id].skill_ids
	var seen := [row.skill_id]
	for index in row.techniques.size():
		var technique = row.techniques[index]
		var fields := ["skill_id", "unlock_level", "name", "summary", "mp_cost_add", "cooldown_add", "extra_effects"]
		if not technique is Dictionary:
			errors.append(label + " 技法必须为字典")
			continue
		var count := errors.size()
		if technique.size() != fields.size(): errors.append(label + " 技法字段不完整/未知")
		for field in technique:
			if not fields.has(field): errors.append(label + " 未知技法字段：" + field)
		if not technique.get("skill_id") in owned or technique.get("skill_id") in seen: errors.append(label + " 技法技能不属本形态或重复")
		seen.append(technique.get("skill_id"))
		if technique.get("unlock_level") != index + 4: errors.append(label + " 技法须按L4/L5开放")
		for field in ["name", "summary"]:
			if not technique.get(field) is String or technique.get(field, "").is_empty(): errors.append(label + " 技法缺少说明")
		for field in ["mp_cost_add", "cooldown_add"]:
			if not _nonnegative_int(technique.get(field)): errors.append(label + " 技法费用/CD非法")
		_validate_effects(technique.get("extra_effects"), label, data, errors)
		if errors.size() == count:
			_validate_ability(Refinements.apply_technique(data.skills[technique.skill_id], technique), data, errors)

static func _integerize(value):
	# Godot JSON 数字均为浮点；仅整值转换，绝不把 1.5 费用静默截断。
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_integerize(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[key] = _integerize(value[key])
		return result
	return value

static func _nonnegative_int(value) -> bool:
	return value is int and value >= 0

static func _number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0

static func _stats(value, label: String, errors: Array[String], sparse: bool = false) -> void:
	if not value is Dictionary:
		errors.append(label + " 属性必须是字典")
		return
	if not sparse and value.size() != STAT_KEYS.size():
		errors.append(label + " 必须包含七项属性")
	for key in value:
		if not STAT_KEYS.has(key) or not _nonnegative_int(value[key]):
			errors.append(label + " 非法属性：" + str(key))
	if not sparse:
		for key in STAT_KEYS:
			if not value.has(key):
				errors.append(label + " 缺属性：" + key)

static func _validate_catalog(data: Dictionary, errors: Array[String]) -> void:
	if data.classes.size() != 6 or data.skills.size() != 24:
		errors.append("固定六职业与 24 技能数量不符")
	for id in CLASS_IDS:
		if not data.classes.has(id):
			errors.append("缺固定职业：" + id)
	var owned: Dictionary = {}
	for id in data.classes:
		var row: Dictionary = data.classes[id]
		_stats(row.get("base_stats"), id, errors)
		if row.get("base_stats") is Dictionary and row.base_stats.get("hp", 0) is int and row.base_stats.get("hp", 0) < 1:
			errors.append(id + " 最大 HP 至少为 1")
		_stats(row.get("growth"), id + " 成长", errors)
		if not row.get("default_attack") in ["physical", "magic"]:
			errors.append(id + " 默认普攻类型非法")
		var skill_ids = row.get("skill_ids")
		if not skill_ids is Array or skill_ids.size() != 4:
			errors.append(id + " 必须有四个固定技能")
			continue
		for index in range(skill_ids.size()):
			var skill_id = skill_ids[index]
			if not skill_id is String or not data.skills.has(skill_id):
				errors.append(id + " 缺技能引用：" + str(skill_id))
				continue
			if owned.has(skill_id):
				errors.append("重复职业技能：" + skill_id)
			owned[skill_id] = id
			if data.skills[skill_id].get("unlock_level") != [1, 1, 2, 3][index]:
				errors.append(skill_id + " 解锁等级与固定卡位不符")
	for id in data.statuses:
		var row: Dictionary = data.statuses[id]
		if not CLOCKS.has(row.get("clock")) or not row.get("dispellable") is bool or not row.get("negative") is bool or not row.get("kind") is String:
			errors.append(id + " 状态定义／时钟非法")
	data.abilities = data.skills.duplicate(true)
	for id in data.enemies:
		var row: Dictionary = data.enemies[id]
		_stats(row.get("base_stats"), id, errors)
		if row.get("base_stats") is Dictionary and row.base_stats.get("hp", 0) is int and row.base_stats.get("hp", 0) < 1:
			errors.append(id + " 最大 HP 至少为 1")
		if not row.get("default_attack") in ["physical", "magic"] or not row.get("target_policy") in ["lowest_hp_ratio", "highest_hp", "highest_atk", "boss_cycle"]:
			errors.append(id + " 敌人普攻／目标策略非法")
		for key in ["weaknesses", "resistances"]:
			if not row.get(key) is Array:
				errors.append(id + " 元素表非法")
				continue
			for element in row[key]:
				if not ELEMENTS.has(element) or element == "neutral":
					errors.append(id + " 元素非法：" + str(element))
		if not row.get("abilities") is Array:
			errors.append(id + " 敌人技能表非法")
			continue
		for ability in row.abilities:
			if not ability is Dictionary or not ability.get("id") is String or ability.id.is_empty():
				errors.append(id + " 敌人技能 ID 非法")
				continue
			if data.abilities.has(ability.id):
				errors.append("重复技能 ID：" + ability.id)
			data.abilities[ability.id] = ability
	for id in data.enemies:
		var row: Dictionary = data.enemies[id]
		if not row.get("boss") is Dictionary:
			errors.append(id + " Boss 配置非法")
		elif not row.boss.is_empty():
			var cycle = row.boss.get("cycle")
			if not cycle is Array or cycle.size() != 6:
				errors.append(id + " Boss 必须为六步循环")
			else:
				var own_ids: Array = []
				for ability in row.get("abilities", []):
					if ability is Dictionary:
						own_ids.append(ability.get("id"))
				for ability_id in cycle:
					if not own_ids.has(ability_id):
						errors.append(id + " Boss 循环缺技能引用")
			for field in ["phase_threshold", "phase_damage_bonus", "stagger_magnitude"]:
				if not _number(row.boss.get(field)) or row.boss[field] > 1:
					errors.append(id + " Boss 阶段数值非法")
			for field in ["phase_spd_bonus", "reaction_opportunities"]:
				if not _nonnegative_int(row.boss.get(field)):
					errors.append(id + " Boss 阶段计数非法")
	for id in data.abilities:
		_validate_ability(data.abilities[id], data, errors)
	for id in data.equipment:
		var row: Dictionary = data.equipment[id]
		if not row.get("slot") in ["weapon", "armor", "accessory"]:
			errors.append(id + " 装备槽非法")
		_stats(row.get("stats"), id, errors, true)
	for id in ["standard_weapon", "standard_armor", "standard_accessory"]:
		if not data.equipment.has(id):
			errors.append("缺标准装备：" + id)
	for id in data.items:
		var row: Dictionary = data.items[id]
		if not _nonnegative_int(row.get("initial_stock")) or not row.get("target_rule") in ["single_ally", "fallen_ally"]:
			errors.append(id + " 道具目标／库存非法")
		_validate_effects(row.get("effects"), id, data, errors)
	for id in data.encounters:
		var row: Dictionary = data.encounters[id]
		if not row.get("level") is int or row.level < 1 or row.level > 10 or not _nonnegative_int(row.get("xp")):
			errors.append(id + " 遭遇等级／经验非法")
		if not row.get("enemy_ids") is Array or row.enemy_ids.is_empty():
			errors.append(id + " 遭遇敌人表非法")
		else:
			for enemy_id in row.enemy_ids:
				if not data.enemies.has(enemy_id):
					errors.append(id + " 缺敌人引用：" + str(enemy_id))
		if not row.get("next_id") is String or (not row.next_id.is_empty() and not data.encounters.has(row.next_id)) or not row.get("rest_after") is bool:
			errors.append(id + " 后续遭遇／休息非法")
		for route_kind in ["scene_routes", "ritual_routes"]:
			if not row.get(route_kind, []) is Array:
				errors.append(id + " 场景路由必须为数组")
				continue
			for route in row.get(route_kind, []):
				if not route is Dictionary:
					errors.append(id + " 路由必须为字典")
					continue
				for field in ["source_scene", "battle_scene"]:
					if not route.get(field) is String or not route.get(field, "").begins_with("res://scenes/") or not route.get(field, "").ends_with(".tscn"): errors.append(id + " 路由场景路径非法")
				if not route.get("clue_id", "") is String: errors.append(id + " 路由线索 ID 非法")
				if route.get("source_scene") == "res://scenes/exploration_3d/approach.tscn":
					var expected := {"patch_version": 2, "encounter_id": "approach_basin", "event_flags": {"basin_cleared": true}, "resolved": {"basin_reflection": true}}
					if id != "approach_basin" or route_kind != "scene_routes" or route.get("clue_id") != "basin_reflection" or route.get("battle_scene") != "res://scenes/rpg/battle.tscn" or route.get("story_patch") != expected: errors.append(id + " 参道路由与补丁归属不符")
				elif route.has("story_patch"):
					errors.append(id + " 旧路由不能携带新剧情补丁")
		if row.has("loot"):
			if not row.loot is Dictionary or row.loot.is_empty():
				errors.append(id + " 战利品必须是包含装备/道具的非空字典")
			else:
				for kind in ["gear", "items"]:
					var rewards: Dictionary = row.loot.get(kind, {})
					if not rewards is Dictionary:
						errors.append(id + " 战利品" + kind + "必须是字典")
						continue
					for reward_id in rewards:
						var table: String = "equipment" if kind == "gear" else "items"
						if not reward_id is String or reward_id.is_empty() or not data[table].has(reward_id):
							errors.append(id + " 战利品引用未定义：" + str(reward_id))
						elif not _nonnegative_int(rewards[reward_id]) or rewards[reward_id] < 1:
							errors.append(id + " 战利品数量非法：" + str(reward_id))
				for key in row.loot:
					if not key in ["gear", "items"]: errors.append(id + " 战利品只允许装备/道具两类")

static func _validate_ability(row: Dictionary, data: Dictionary, errors: Array[String]) -> void:
	var id: String = row.id
	if not _nonnegative_int(row.get("mp_cost")) or not _nonnegative_int(row.get("cooldown")):
		errors.append(id + " MP／CD 必须为非负整数")
	if not row.get("unlock_level") is int or row.unlock_level < 1 or row.unlock_level > 10:
		errors.append(id + " 解锁等级非法")
	if not TARGETS.has(row.get("target_rule")) or not ELEMENTS.has(row.get("element")) or not row.get("damage_type") in ["physical", "magic", "none"] or not row.get("single_direct") is bool:
		errors.append(id + " 目标／元素／类型／单体标志非法")
	_validate_effects(row.get("effects"), id, data, errors)
	_validate_branches(row.get("branches", {}), id, errors)
	if row.has("condition"):
		if not row.condition is Dictionary or row.condition.size() != 1 or not _number(row.condition.get("self_hp_ratio_at_most")) or row.condition.get("self_hp_ratio_at_most", 2) > 1:
			errors.append(id + " 敌人技能条件非法")
	if not row.get("effects") is Array:
		return
	var has_damage := false
	for effect in row.effects:
		if not effect is Dictionary or effect.get("type") != "damage":
			continue
		has_damage = true
		var single: bool = row.get("target_rule") == "single_enemy"
		if row.get("single_direct") != single or effect.get("single_direct") != single or row.get("element") != effect.get("element") or row.get("damage_type") != effect.get("damage_type"):
			errors.append(id + " 伤害效果与技能元数据不一致")
	if not has_damage and (row.get("single_direct") != false or row.get("damage_type") != "none"):
		errors.append(id + " 非伤害技能不能标记 single_direct")

static func _validate_effects(effects, label: String, data: Dictionary, errors: Array[String]) -> void:
	if not effects is Array or effects.is_empty():
		errors.append(label + " 效果必须为非空有序数组")
		return
	var source_feedback_count := 0
	for effect in effects:
		if not effect is Dictionary or not EFFECTS.has(effect.get("type")):
			errors.append(label + " 未知效果")
			continue
		var type: String = effect.type
		if effect.has("recipient"):
			if effect.recipient != "source" or type != "restore_mp": errors.append(label + " 施法者回馈仅允许一次MP回复")
			source_feedback_count += 1
			if source_feedback_count > 1: errors.append(label + " 同一技能最多一项施法者回馈")
		if effect.has("requires"):
			var requirement = effect.requires
			if not requirement is Dictionary or requirement.size() != 1:
				errors.append(label + " 技法条件必须是单项字典")
			else:
				var key: String = str(requirement.keys()[0])
				if key in ["target_status", "source_status"]:
					if not requirement[key] is String or not data.statuses.has(requirement[key]): errors.append(label + " 技法条件状态非法")
				elif key in ["source_has_shield", "target_cleansed"]:
					if requirement[key] != true or not requirement[key] is bool: errors.append(label + " 技法条件布尔值非法")
				else: errors.append(label + " 未登记技法条件")
			if type not in ["apply_status", "consume_status", "heal", "restore_mp"]: errors.append(label + " 条件不能修饰此效果")
		if type == "restore_mp" and effect.has("recipient") and (not effect.has("requires") or int(effect.get("fixed", 0)) not in [1, 2, 3]): errors.append(label + " 回馈须有条件且限1至3MP")
		if type == "damage":
			if not _number(effect.get("coefficient")) or not effect.get("damage_type") in ["physical", "magic"] or not ELEMENTS.has(effect.get("element")) or not effect.get("single_direct") is bool or not effect.get("can_crit") is bool:
				errors.append(label + " 伤害效果非法")
		if type in ["apply_status", "consume_status"]:
			if not effect.get("status_id") is String or not data.statuses.has(effect.status_id):
				errors.append(label + " 缺状态引用")
		if type == "apply_status":
			if not _number(effect.get("magnitude")) or not effect.get("duration") is int or effect.duration < 1 or not CLOCKS.has(effect.get("clock")):
				errors.append(label + " 状态幅度／时钟／时长非法")
			elif data.statuses.has(effect.get("status_id")) and effect.clock != data.statuses[effect.status_id].clock:
				errors.append(label + " 状态时钟与目录不符")
		if type in ["heal", "shield"]:
			if not _number(effect.get("fixed")) or not _number(effect.get("coefficient")) or not STAT_KEYS.has(effect.get("stat")):
				errors.append(label + " 治疗／护盾数值非法")
		if type == "shield" and (not effect.get("duration") is int or effect.duration < 1 or effect.get("clock") != "target_slot"):
			errors.append(label + " 护盾时钟／时长非法")
		if type in ["restore_hp", "restore_mp"] and not _nonnegative_int(effect.get("fixed")):
			errors.append(label + " 道具恢复量非法")
		if type == "revive" and (not _number(effect.get("fraction")) or effect.fraction > 1 or not effect.get("preserve_mp") is bool):
			errors.append(label + " 复苏效果非法")
		if type == "charge" and (not data.abilities.has(effect.get("release_id")) or not effect.get("interruptible") is bool):
			errors.append(label + " 蓄力释放引用非法")
		# 条件与覆盖系数为完整组合；禁止下游猜测缺失字段的默认值。
		if effect.has("condition"):
			if type != "damage" or not effect.condition in ["target_has_status", "target_no_slot_this_round"]:
				errors.append(label + " 条件效果非法")
			if not _number(effect.get("conditional_coefficient")):
				errors.append(label + " 条件伤害缺少合法系数")
			if effect.condition == "target_has_status" and (not effect.get("status_id") is String or not data.statuses.has(effect.get("status_id"))):
				errors.append(label + " 条件伤害缺少合法状态引用")
		elif effect.has("conditional_coefficient"):
			errors.append(label + " 条件伤害系数缺少条件")
		if effect.has("status_id") and not data.statuses.has(effect.status_id):
			errors.append(label + " 条件状态引用非法")


static func _validate_branches(branches, label: String, errors: Array[String]) -> void:
	if not branches is Dictionary:
		errors.append(label + " 分支必须为字典")
		return
	for branch in branches:
		if not branch in ["economy", "power", "duration"] or not branches[branch] is Dictionary:
			errors.append(label + " 分支类型非法")
			continue
		for level in branches[branch]:
			var values = branches[branch][level]
			if not level in ["6", "9"] or not values is Dictionary or values.is_empty():
				errors.append(label + " 分支等级／数值非法")
				continue
			for field in values:
				if not field in ["mp_cost", "magnitude", "coefficient", "duration", "conditional_coefficient", "fixed"] or not _number(values[field]):
					errors.append(label + " 分支数值非法：" + str(field))
				elif field == "duration" and values[field] < 1:
					errors.append(label + " 分支持续时间至少为1")
				elif field in ["mp_cost", "duration", "fixed"] and not values[field] is int:
					errors.append(label + " 分支整数项非法")
