class_name NoiseSystem
extends RefCounted

var _state: GameState
var _current_noise_map: Dictionary = {}

func _init(game_state: GameState) -> void:
	_state = game_state
	EventBus.on("noise:created", _on_noise_created)
	EventBus.on("object:bell_rung", _on_bell_rung)
	EventBus.on("object:pushed", _on_object_pushed)
	EventBus.on("object:pushed_over", _on_object_pushed_over)
	EventBus.on("effect:barrel_explode", _on_barrel_explode)
	EventBus.on("effect:ignite_oil", _on_oil_ignited)

func dispose() -> void:
	EventBus.off("noise:created", _on_noise_created)
	EventBus.off("object:bell_rung", _on_bell_rung)
	EventBus.off("object:pushed", _on_object_pushed)
	EventBus.off("object:pushed_over", _on_object_pushed_over)
	EventBus.off("effect:barrel_explode", _on_barrel_explode)
	EventBus.off("effect:ignite_oil", _on_oil_ignited)

func create_noise(pos: Vector2i, volume: int, source_id: String = "", source_type: String = "", duration: int = 1) -> Dictionary:
	if _state == null or _state.map == null or not _state.map.in_bounds(pos):
		return {}
	volume = maxi(0, volume)
	if volume <= 0:
		return {}
	var noise_map = propagate(pos, volume)
	_current_noise_map = noise_map
	_state.add_noise(pos, volume, source_id, source_type, noise_map, duration)
	var event = {
		"origin": pos,
		"pos": pos,
		"volume": volume,
		"source_id": source_id,
		"source_type": source_type,
		"noise_map": noise_map,
		"duration": maxi(1, duration),
		"turn": _state.turn_count,
	}
	EventBus.emit("noise:propagated", event)
	return event

func propagate(origin: Vector2i, volume: int) -> Dictionary:
	var result = {}
	if _state == null or _state.map == null or not _state.map.in_bounds(origin):
		return result
	var queue = [{"pos": origin, "value": volume}]
	result[origin] = volume
	while not queue.is_empty():
		var current = queue.pop_front()
		var current_pos: Vector2i = current.get("pos", origin)
		var current_value = int(current.get("value", 0))
		for neighbor in _state.map.get_neighbors(current_pos):
			var decay = 1
			if _state.map.has_tag(neighbor.x, neighbor.y, "blocking"):
				decay += 2
			var next_value = current_value - decay
			if next_value <= 0:
				continue
			if next_value <= int(result.get(neighbor, 0)):
				continue
			result[neighbor] = next_value
			queue.append({"pos": neighbor, "value": next_value})
	return result

func get_noise_at(pos: Vector2i) -> int:
	return int(_current_noise_map.get(pos, 0))

func get_recent_events(max_age_turns: int = 1) -> Array:
	if _state == null:
		return []
	var result = []
	for event in _state.noise_events:
		var age = maxi(0, _state.turn_count - int(event.get("turn", _state.turn_count)))
		var duration = int(event.get("duration", max_age_turns))
		if age < duration:
			result.append(event)
	return result

func clear_old_noise(current_turn: int) -> void:
	if _state == null:
		return
	_state.clear_old_noise()
	if _state.noise_events.is_empty():
		_current_noise_map = {}

func _on_noise_created(data: Dictionary) -> void:
	create_noise(
		data.get("pos", Vector2i(-1, -1)),
		int(data.get("volume", 0)),
		data.get("source_id", ""),
		data.get("source_type", "custom"),
		int(data.get("duration", 1))
	)

func _on_bell_rung(data: Dictionary) -> void:
	create_noise(
		data.get("pos", Vector2i(-1, -1)),
		int(data.get("volume", 4)),
		data.get("unit_id", ""),
		"bell",
		int(data.get("duration", 2))
	)

func _on_object_pushed(data: Dictionary) -> void:
	create_noise(
		data.get("to", Vector2i(-1, -1)),
		2,
		data.get("pusher_id", ""),
		"push",
		1
	)

func _on_object_pushed_over(data: Dictionary) -> void:
	create_noise(
		data.get("pos", Vector2i(-1, -1)),
		3,
		data.get("unit_id", ""),
		"push_over",
		1
	)

func _on_barrel_explode(data: Dictionary) -> void:
	create_noise(
		data.get("pos", Vector2i(-1, -1)),
		7,
		"",
		"explosion",
		1
	)

func _on_oil_ignited(data: Dictionary) -> void:
	create_noise(
		data.get("pos", Vector2i(-1, -1)),
		5,
		"",
		"oil_ignite",
		1
	)
