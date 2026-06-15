class_name StatusEffectManager
extends RefCounted

static var _defs: Dictionary = {}

static func load_defs() -> void:
	var data = JsonLoader.load_file("res://data/statuses.json")
	if data == null or not data is Dictionary:
		_defs = {}
		return
	_defs = data.get("statuses", {})
	if _defs == null:
		_defs = {}

static func get_status_def(sid: String) -> Dictionary:
	if _defs == null or _defs.is_empty():
		load_defs()
	return _defs.get(sid, {})

static func apply_status(unit: Unit, status_id: String, duration: int, value: int = 0) -> void:
	var def = get_status_def(status_id)
	if def.is_empty():
		return
	duration = mini(duration, int(def.get("maxDuration", duration)))
	var existing = null
	for s in unit.status_effects:
		if s.status_id == status_id:
			existing = s
			break
	if existing:
		if def.get("stackable", false):
			existing.duration = maxi(existing.duration, duration)
			if value > 0:
				existing.value = existing.get("value", 0) + value
		else:
			existing.duration = maxi(existing.duration, duration)
	else:
		var entry = {"status_id": status_id, "duration": duration}
		if value > 0:
			entry["value"] = value
		unit.status_effects.append(entry)

static func tick_statuses(units: Array, timing: String) -> Array:
	var results = []
	for unit in units:
		if not unit.is_alive:
			continue
		var to_remove = []
		for i in range(unit.status_effects.size()):
			var active = unit.status_effects[i]
			var def = get_status_def(active.status_id)
			if def.is_empty() or def.get("tickTiming", "") != timing:
				continue
			var tick = {"unit_id": unit.id, "status_id": active.status_id}
			var effect_type = def.get("effectType", "none")
			if effect_type == "damage":
				var dmg = active.get("value", 0)
				if dmg == 0:
					dmg = def.get("valuePerTick", 0)
				var damage_type = def.get("damageType", "physical")
				unit.take_damage(dmg, damage_type)
				tick.damage = dmg
			elif effect_type == "skip_turn":
				tick.skipped_turn = true
			active.duration -= 1
			if active.duration <= 0:
				tick.expired = true
				to_remove.append(i)
			results.append(tick)
		to_remove.reverse()
		for i in to_remove:
			unit.status_effects.remove_at(i)
	return results
