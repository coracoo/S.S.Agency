class_name TerrainSystem
extends RefCounted

var _rules: Array = []
var _effects_data: Dictionary = {}
var _objects_data: Dictionary = {}
var _processing: bool = false
var _pending_effect_events: Array = []
var _in_spread_tick: bool = false

func _init(rules_data: Dictionary, effects_data: Dictionary, objects_data: Dictionary) -> void:
	_effects_data = effects_data
	_objects_data = objects_data
	_rules = rules_data.get("rules", [])
	_setup_event_listeners()

func _setup_event_listeners() -> void:
	EventBus.on("effect:added", _on_effect_added)
	EventBus.on("object:pushed_over", _on_object_pushed_over)

func _on_effect_added(data: Dictionary) -> void:
	if _processing:
		_pending_effect_events.append(data)
		return
	_processing = true
	_process_effect_added(data)
	while not _pending_effect_events.is_empty():
		_process_effect_added(_pending_effect_events.pop_front())
	_processing = false

func _process_effect_added(data: Dictionary) -> void:
	var map: GameMap = data.get("map", null)
	var pos: Vector2i = data.get("pos", Vector2i(-1, -1))
	if map != null and map.in_bounds(pos):
		_run_rules(map, pos)
		for n in map.get_neighbors(pos):
			_run_rules(map, n)

func _on_object_pushed_over(data: Dictionary) -> void:
	var map: GameMap = data.get("map", null)
	var pos: Vector2i = data.get("pos", Vector2i(-1, -1))
	var obj_id = data.get("object_id", "")
	if map == null or not map.in_bounds(pos):
		return
	var odef = _objects_data.get(obj_id, {})
	var spill = odef.get("push_over_spill", null)
	if spill != null and spill != "":
		# Add effect at the pushed position
		map.add_effect(pos.x, pos.y, spill)
		# Rice spreads to all neighbors (4-directional)
		if spill == "rice":
			for n in map.get_neighbors(pos):
				map.add_effect(n.x, n.y, spill)
		EventBus.emit("effect:added", {"map": map, "pos": pos})

func _run_rules(map: GameMap, pos: Vector2i) -> void:
	if not map.in_bounds(pos):
		return
	for rule in _rules:
		var cell_tags = map.get_tags(pos.x, pos.y)
		# Also check object tags at this position
		var obj_id = map.get_object(pos.x, pos.y)
		if obj_id != "":
			var odef = _objects_data.get(obj_id, {})
			for tag in odef.get("tags", []):
				cell_tags[tag] = true
		var trigger = rule.get("trigger", {})
		var source_tags = trigger.get("source_tags", [])
		var target_tags = trigger.get("target_tags", [])

		var source_ok = true
		for tag in source_tags:
			if not cell_tags.get(tag, false):
				source_ok = false
				break
		if not source_ok:
			continue

		if target_tags.size() > 0:
			var cell_has_target = false
			for tag in target_tags:
				if cell_tags.get(tag, false):
					cell_has_target = true
					break
			if cell_has_target:
				if _conditions_met(rule.get("conditions", []), map, pos):
						_apply_results(rule.get("results", []), map, pos, rule)
			for n in map.get_neighbors(pos):
				var n_tags = map.get_tags(n.x, n.y)
				# Include object tags at neighbor
				var n_obj_id = map.get_object(n.x, n.y)
				if n_obj_id != "":
					var n_odef = _objects_data.get(n_obj_id, {})
					for tag in n_odef.get("tags", []):
						n_tags[tag] = true
				var has_target = false
				for tag in target_tags:
					if n_tags.get(tag, false):
						has_target = true
						break
				if has_target and _conditions_met(rule.get("conditions", []), map, n):
						_apply_results(rule.get("results", []), map, n, rule)
		else:
			if _conditions_met(rule.get("conditions", []), map, pos):
				_apply_results(rule.get("results", []), map, pos, rule)

func _conditions_met(conditions: Array, map: GameMap, pos: Vector2i) -> bool:
	for condition in conditions:
		match condition.get("type", ""):
			"has_unit":
				if map.get_occupant_id(pos) == "":
					return false
			"has_object":
				if map.get_object(pos.x, pos.y) == "":
					return false
			"has_tag":
				if not map.has_tag(pos.x, pos.y, condition.get("tag", "")):
					return false
	return true

func _apply_results(results: Array, map: GameMap, pos: Vector2i, rule: Dictionary = {}) -> void:
	if _in_spread_tick and bool(rule.get("skip_in_spread", false)):
		return
	for result in results:
		var type = result.get("type", "")
		match type:
			"add_effect":
				var eff = result.get("effect", "")
				if eff != "":
					_add_effect_for_current_phase(map, pos, eff)
			"add_effect_neighbors":
				var neighbor_eff = result.get("effect", "")
				if neighbor_eff != "":
					for n in map.get_neighbors(pos):
						if not map.has_tag(n.x, n.y, "blocking"):
							_add_effect_for_current_phase(map, n, neighbor_eff)
			"remove_effect":
				map.remove_effect(pos.x, pos.y, result.get("effect", ""))
			"remove_tag":
				map.remove_tag(pos.x, pos.y, result.get("tag", ""))
			"remove_object":
				map.set_object(pos.x, pos.y, null)
			"damage_unit":
				var uid = map.get_occupant_id(pos)
				if uid != "":
					var dmg = 0
					if result.get("value_source", "") == "effect":
						var value_field = result.get("value_field", "damage")
						for eff in map.get_effects(pos.x, pos.y):
							var edef = _effects_data.get(eff.type, {})
							if int(edef.get(value_field, 0)) > 0:
								dmg = int(edef.get(value_field, 0))
								break
					else:
						dmg = int(result.get("value", 0))
					if dmg > 0:
						EventBus.emit("unit:terrain_damage", {"unit_id": uid, "damage": dmg, "pos": pos})
			"emit_event":
				EventBus.emit(result.get("event", ""), {"map": map, "pos": pos})

func _duration_for_new_spread_effect(effect_type: String) -> int:
	var base_duration = int(_effects_data.get(effect_type, {}).get("duration", 1))
	if _in_spread_tick and base_duration <= 1:
		return base_duration + 1
	return base_duration

func _add_effect_for_current_phase(map: GameMap, pos: Vector2i, effect_type: String) -> void:
	if _in_spread_tick:
		for existing in map.get_effects(pos.x, pos.y):
			if existing.type == effect_type:
				return
	map.add_effect(pos.x, pos.y, effect_type, _duration_for_new_spread_effect(effect_type))

func process_spread(map: GameMap) -> void:
	var spreads = []
	var effect_positions = []
	for row in range(map.rows):
		for col in range(map.cols):
			var effects = map.get_effects(col, row)
			if effects.is_empty():
				continue
			var pos = Vector2i(col, row)
			effect_positions.append(pos)
			for eff in effects:
				var edef = _effects_data.get(eff.type, {})
				var spread_count = int(edef.get("spread_per_turn", 0))
				if spread_count <= 0:
					continue
				var spread_tags = edef.get("spread_tags", [])
				if spread_tags.is_empty():
					continue
				# Find valid neighbors to spread to
				var neighbors = map.get_neighbors(pos)
				neighbors.shuffle()
				var spread_done = 0
				for n in neighbors:
					if spread_done >= spread_count:
						break
					if map.has_tag(n.x, n.y, "burning"):
						continue
					if map.has_tag(n.x, n.y, "blocking"):
						continue
					var can_spread = false
					for stag in spread_tags:
						if map.has_tag(n.x, n.y, stag):
							can_spread = true
							break
					if can_spread:
						spreads.append({"col": n.x, "row": n.y, "effect": eff.type})
						spread_done += 1

	_processing = true
	_in_spread_tick = true
	# Track new positions so we can run rules on them too
	var newly_added_positions = []
	for s in spreads:
		map.add_effect(s.col, s.row, s.effect, _duration_for_new_spread_effect(s.effect))
		var spread_pos = Vector2i(s.col, s.row)
		if not effect_positions.has(spread_pos) and not newly_added_positions.has(spread_pos):
			newly_added_positions.append(spread_pos)
	# Run rules on original effect cells
	for pos_s in effect_positions:
		_run_rules(map, pos_s)
	# Also run rules on newly spread positions
	for pos_n in newly_added_positions:
		_run_rules(map, pos_n)
	# Collect ALL positions with effects (original + newly spread)
	var all_effect_positions = effect_positions.duplicate()
	for nap in newly_added_positions:
		if not all_effect_positions.has(nap):
			all_effect_positions.append(nap)
	# Apply damage to units in ALL effect cells
	for pos_d in all_effect_positions:
		var uid_d = map.get_occupant_id(pos_d)
		if uid_d == "":
			continue
		for eff_d in map.get_effects(pos_d.x, pos_d.y):
			var edef_d = _effects_data.get(eff_d.type, {})
			var dmg_d = int(edef_d.get("damage", 0))
			if dmg_d > 0:
				EventBus.emit("unit:terrain_damage", {"unit_id": uid_d, "damage": dmg_d, "pos": pos_d})
	_in_spread_tick = false
	_processing = false
