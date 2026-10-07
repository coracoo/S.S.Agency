# 正式七章的固定威胁与明确奖励；不依赖目录/战斗脚本，不按玩家成长缩放。
class_name RpgStrategyEncounters
extends RefCounted

const DATA_PATH := "res://data/rpg/strategy_encounters.json"
const STAT_KEYS := ["hp", "mp", "atk", "matk", "def", "mdef", "spd"]
static var _profiles: Dictionary = {}

static func definition(encounter_id: String) -> Dictionary:
	return _data().get(encounter_id, {}).duplicate(true)

static func rewards(encounter_id: String) -> Dictionary:
	return definition(encounter_id).get("rewards", {}).duplicate(true)

static func enemy_actor(encounter_id: String, enemy_id: String, actor_id: String, catalog: RefCounted) -> Dictionary:
	if actor_id.is_empty() or catalog == null or not catalog.has_method("get_definition"): return {}
	var profile := definition(encounter_id)
	if profile.is_empty() or not profile.enemy_ids.has(enemy_id): return {}
	var enemy: Dictionary = catalog.get_definition("enemies", enemy_id)
	if enemy.is_empty() or not enemy.get("abilities") is Array or not enemy.get("weaknesses") is Array or not enemy.get("resistances") is Array: return {}
	var skills: Array[String] = []
	for ability in enemy.abilities:
		if not ability is Dictionary or not ability.get("id") is String or ability.id.is_empty(): return {}
		if skills.has(ability.id) or catalog.get_definition("abilities", ability.id).is_empty(): return {}
		skills.append(ability.id)
	var stats: Dictionary = profile.enemy_stats[enemy_id].duplicate(true)
	return {
		"actor_id": actor_id, "side": "enemy", "class_id": enemy_id,
		"threat_version": 1, "threat_profile": encounter_id,
		"stats": stats, "hp": stats.hp, "mp": stats.mp,
		"equipment": {}, "skill_ids": skills, "branch": {},
		"slot_count": 0, "opportunity_count": 0, "statuses": [], "shield": {},
		"cooldown_until": {}, "revived_round": -1, "intent": {}, "boss": {},
		"weaknesses": enemy.weaknesses.duplicate(), "resistances": enemy.resistances.duplicate()
	}

static func validate_actor(actor: Dictionary, catalog: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	if not actor.get("threat_version") is int or actor.threat_version != 1: errors.append("敌方威胁版本非法")
	for key in ["level", "xp"]:
		if actor.has(key): errors.append("固定威胁敌人不得含有" + key)
	if actor.get("side") != "enemy": errors.append("固定威胁只能用于敌方")
	for field in ["actor_id", "class_id", "threat_profile"]:
		if not actor.get(field) is String or actor.get(field, "").is_empty(): errors.append("敌方威胁字符串字段非法：" + field)
	if not errors.is_empty(): return errors
	var profile := definition(actor.threat_profile)
	if profile.is_empty(): return ["敌方威胁遭遇未登记"]
	if not profile.enemy_ids.has(actor.class_id): return ["敌种不属于此固定遭遇"]
	var expected := enemy_actor(actor.threat_profile, actor.class_id, actor.actor_id, catalog)
	if expected.is_empty(): return ["固定威胁缺少真实敌种或技能目录"]
	# 守关者在真实轮首提交第二阶段时永久加速一次；仅该阶段改动允许偏离初始表。
	# 待转换状态仍用初始速度，完整Boss运行态结构继续交给BattleState检查。
	if _entered_gatekeeper_phase_two(actor):
		var enemy: Dictionary = catalog.get_definition("enemies", "gatekeeper")
		var boss_definition = enemy.get("boss")
		if not boss_definition is Dictionary or not boss_definition.get("phase_spd_bonus") is int or boss_definition.phase_spd_bonus < 0:
			return ["守关者阶段速度配置非法"]
		expected.stats.spd += boss_definition.phase_spd_bonus
	var stats = actor.get("stats")
	if not stats is Dictionary or stats != expected.stats:
		errors.append("敌方属性与固定威胁不符")
	elif stats is Dictionary:
		for key in STAT_KEYS:
			if not stats.get(key) is int: errors.append("敌方固定属性必须为整数：" + key)
	for field in ["skill_ids", "weaknesses", "resistances"]:
		if not actor.get(field) is Array or actor[field] != expected[field]: errors.append("敌方固有配置与目录不符：" + field)
	for field in ["equipment", "branch"]:
		if not actor.get(field) is Dictionary or not actor[field].is_empty(): errors.append("固定威胁不得追加装备或分支：" + field)
	# HP/MP、状态、行动时钟和Boss阶段会随战斗变化；这里只校验资源边界。
	# 状态及行动时钟的完整结构由战斗快照校验器统一负责。
	for key in ["hp", "mp"]:
		if not actor.get(key) is int or actor[key] < 0 or actor[key] > expected.stats[key]: errors.append("敌方当前资源超出固定上限：" + key)
	return errors

static func _entered_gatekeeper_phase_two(actor: Dictionary) -> bool:
	if actor.get("class_id") != "gatekeeper" or not actor.get("boss") is Dictionary: return false
	var boss: Dictionary = actor.boss
	return boss.get("phase") is int and boss.phase == 2 and boss.get("pending_phase") is int and boss.pending_phase == 0 and boss.get("pending_phase_round") is int and boss.pending_phase_round == -1

static func _data() -> Dictionary:
	if not _profiles.is_empty(): return _profiles
	if not FileAccess.file_exists(DATA_PATH): return {}
	var document: Variant = _integerize(JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)))
	if not document is Dictionary or document.get("schema_version") != 1 or document.get("rules_version") != "strategy-threat-1" or not document.get("definitions") is Array: return {}
	var profiles: Dictionary = {}
	for row in document.definitions:
		if not row is Dictionary or row.size() != 7 or not row.has_all(["id", "name", "chapter", "enemy_ids", "enemy_stats", "rewards", "notes"]): return {}
		for field in ["id", "name", "notes"]:
			if not row[field] is String or row[field].is_empty(): return {}
		if profiles.has(row.id) or not row.chapter is int or row.chapter < 1 or row.chapter > 7: return {}
		if not row.enemy_ids is Array or row.enemy_ids.is_empty() or not row.enemy_stats is Dictionary: return {}
		var unique: Dictionary = {}
		for id in row.enemy_ids:
			if not id is String or id.is_empty(): return {}
			unique[id] = true
			var stats = row.enemy_stats.get(id)
			if not stats is Dictionary or stats.size() != STAT_KEYS.size(): return {}
			for key in STAT_KEYS:
				if not stats.get(key) is int or stats[key] < (1 if key == "hp" else 0): return {}
		if unique.size() != row.enemy_stats.size(): return {}
		if not row.rewards is Dictionary or row.rewards.size() != 4 or not row.rewards.has_all(["coins", "gear", "items", "cards"]): return {}
		if not row.rewards.coins is int or row.rewards.coins < 0: return {}
		for kind in ["gear", "items", "cards"]:
			if not row.rewards[kind] is Dictionary: return {}
			for id in row.rewards[kind]:
				if not id is String or id.is_empty() or not row.rewards[kind][id] is int or row.rewards[kind][id] < 1: return {}
		profiles[row.id] = row
	_profiles = profiles
	return _profiles

static func _integerize(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floor(value): return int(value)
	if value is Array:
		var result: Array = []
		for item in value: result.append(_integerize(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[key] = _integerize(value[key])
		return result
	return value
