# 属性以五级标准装为基准：先减标准装备，再加实际装备，不随机成长。
class_name RpgActorFactory
extends RefCounted

const Catalog = preload("res://scripts/rpg/catalog.gd")
const STAT_KEYS := ["hp", "mp", "atk", "matk", "def", "mdef", "spd"]
const STANDARD := {"weapon": "standard_weapon", "armor": "standard_armor", "accessory": "standard_accessory"}
var _catalog: RefCounted

func _init(catalog: RefCounted = null) -> void:
	_catalog = catalog
	if _catalog == null:
		_catalog = Catalog.new()
		_catalog.load_all()

func stats_for(class_id: String, level: int, equipment: Dictionary) -> Dictionary:
	if level < 1 or level > 10 or not _valid_equipment(equipment):
		return {}
	var definition: Dictionary = _catalog.get_definition("classes", class_id)
	if definition.is_empty():
		return {}
	var stats: Dictionary = {}
	for key in STAT_KEYS:
		stats[key] = int(definition.base_stats[key]) + (level - 5) * int(definition.growth[key])
	for slot in STANDARD:
		var standard: Dictionary = _catalog.get_definition("equipment", STANDARD[slot])
		for key in standard.stats:
			stats[key] -= int(standard.stats[key])
		if equipment.has(slot) and not equipment[slot].is_empty():
			var actual: Dictionary = _catalog.get_definition("equipment", equipment[slot])
			for key in actual.stats:
				stats[key] += int(actual.stats[key])
	for key in STAT_KEYS:
		stats[key] = maxi(1 if key == "hp" else 0, stats[key])
	return stats

func create(class_id: String, actor_id: String, level: int, equipment: Dictionary) -> Dictionary:
	if actor_id.is_empty():
		return {}
	var stats := stats_for(class_id, level, equipment)
	if stats.is_empty():
		return {}
	var definition: Dictionary = _catalog.get_definition("classes", class_id)
	return {
		"actor_id": actor_id, "side": "player", "class_id": class_id, "level": level,
		"stats": stats, "hp": stats.hp, "mp": stats.mp,
		"equipment": equipment.duplicate(true), "skill_ids": definition.skill_ids.duplicate(),
		"branch": {}, "slot_count": 0, "opportunity_count": 0,
		"statuses": [], "shield": {}, "cooldown_until": {}, "revived_round": -1,
		"intent": {}, "boss": {}, "weaknesses": [], "resistances": []
	}

func unlocked_skill_ids(class_id: String, level: int) -> Array[String]:
	var result: Array[String] = []
	if level < 1 or level > 10:
		return result
	var definition: Dictionary = _catalog.get_definition("classes", class_id)
	for id in definition.get("skill_ids", []):
		var skill: Dictionary = _catalog.get_definition("skills", id)
		if skill.unlock_level <= level:
			result.append(id)
	return result

func _valid_equipment(equipment: Dictionary) -> bool:
	for slot in equipment:
		if not STANDARD.has(slot) or not equipment[slot] is String:
			return false
		if equipment[slot].is_empty():
			continue
		var definition: Dictionary = _catalog.get_definition("equipment", equipment[slot])
		if definition.is_empty() or definition.slot != slot:
			return false
	return not _catalog.get_definition("equipment", "standard_weapon").is_empty()
