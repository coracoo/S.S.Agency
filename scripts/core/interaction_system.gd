class_name InteractionSystem
extends RefCounted

var _game_state: GameState
var _objects_data: Dictionary

func _init(game_state: GameState, objects_data: Dictionary) -> void:
	_game_state = game_state
	_objects_data = objects_data

func push(unit: Unit, direction: Vector2i) -> bool:
	if direction == Vector2i.ZERO or absi(direction.x) + absi(direction.y) != 1:
		return false
	var target_pos = unit.position + direction
	if not _game_state.map.in_bounds(target_pos):
		return false
	var obj_id = _game_state.map.get_object(target_pos.x, target_pos.y)
	if obj_id == "":
		return false
	var odef = _objects_data.get(obj_id, {})
	if not odef.get("pushable", false):
		return false
	# Check destination
	var dest = target_pos + direction
	if not _game_state.map.in_bounds(dest):
		return false
	if not _game_state.map.is_walkable(dest):
		return false
	if _game_state.map.is_occupied(dest):
		return false
	if not _game_state.spend_ap(1):
		return false
	# Move object
	_game_state.map.set_object(target_pos.x, target_pos.y, null)
	_game_state.map.set_object(dest.x, dest.y, obj_id)
	# Update collision — old position no longer blocked, new position may be
	EventBus.emit("object:pushed", {
		"map": _game_state.map,
		"object_id": obj_id,
		"from": target_pos,
		"to": dest,
		"pusher_id": unit.id
	})
	# Check if object lands on effect-triggering terrain
	EventBus.emit("effect:added", {"map": _game_state.map, "pos": dest})
	return true

func push_over(unit: Unit, target_pos: Vector2i) -> bool:
	if not _game_state.map.in_bounds(target_pos):
		return false
	if not _is_adjacent(unit.position, target_pos):
		return false
	var obj_id = _game_state.map.get_object(target_pos.x, target_pos.y)
	if obj_id == "":
		return false
	var odef = _objects_data.get(obj_id, {})
	if not odef.get("push_over", false):
		return false
	if not _game_state.spend_ap(1):
		return false
	# Remove object and trigger spill
	_game_state.map.set_object(target_pos.x, target_pos.y, null)
	EventBus.emit("object:pushed_over", {
		"map": _game_state.map,
		"object_id": obj_id,
		"pos": target_pos,
		"unit_id": unit.id
	})
	return true


func pickup(unit: Unit, target_pos: Vector2i) -> bool:
	if not _game_state.map.in_bounds(target_pos):
		return false
	if not _is_adjacent(unit.position, target_pos):
		return false
	var obj_id = _game_state.map.get_object(target_pos.x, target_pos.y)
	if obj_id == "":
		return false
	var odef = _objects_data.get(obj_id, {})
	if not odef.get("pushable", false):
		return false
	if not _game_state.spend_ap(1):
		return false
	_game_state.map.set_object(target_pos.x, target_pos.y, null)
	EventBus.emit("inventory:item_picked_up", {
		"unit_id": unit.id,
		"object_id": obj_id,
		"pos": target_pos
	})
	return true

func place_from_inventory(unit: Unit, object_id: String, target_pos: Vector2i) -> bool:
	if not _game_state.map.in_bounds(target_pos):
		return false
	if not _is_adjacent(unit.position, target_pos):
		return false
	if not _game_state.map.is_walkable(target_pos):
		return false
	if _game_state.map.is_occupied(target_pos):
		return false
	if _game_state.map.get_object(target_pos.x, target_pos.y) != "":
		return false
	if not _game_state.spend_ap(1):
		return false
	_game_state.map.set_object(target_pos.x, target_pos.y, object_id)
	EventBus.emit("inventory:item_placed", {
		"unit_id": unit.id,
		"object_id": object_id,
		"pos": target_pos
	})
	return true

func interact(unit: Unit, target_pos: Vector2i, action: String) -> bool:
	if not _game_state.map.in_bounds(target_pos):
		return false
	if not _is_adjacent(unit.position, target_pos):
		return false
	var obj_id = _game_state.map.get_object(target_pos.x, target_pos.y)
	if obj_id == "":
		return false
	var odef = _objects_data.get(obj_id, {})
	var available_actions = odef.get("interact", [])
	if not action in available_actions:
		return false
	if action == "close":
		if _game_state.map.is_occupied(target_pos):
			return false
		if _game_state.map.get_object(target_pos.x, target_pos.y) != obj_id:
			return false
	if not _game_state.spend_ap(1):
		return false
	match action:
		"ring":
			EventBus.emit("object:bell_rung", {
				"map": _game_state.map,
				"pos": target_pos,
				"volume": int(odef.get("noise_volume", 3)),
				"unit_id": unit.id
			})
		"open":
			_game_state.map.set_object(target_pos.x, target_pos.y, null)
			if obj_id == "coffin":
				EventBus.emit("coffin:opened", {
					"map": _game_state.map,
					"pos": target_pos,
					"unit_id": unit.id
				})
			else:
				EventBus.emit("object:door_opened", {
					"map": _game_state.map,
					"pos": target_pos,
					"unit_id": unit.id
				})
		"close":
			_game_state.map.set_object(target_pos.x, target_pos.y, obj_id)
			EventBus.emit("object:door_closed", {
				"map": _game_state.map,
				"pos": target_pos,
				"unit_id": unit.id
			})
		"ignite":
			_game_state.map.add_effect(target_pos.x, target_pos.y, "fire")
			EventBus.emit("effect:added", {
				"map": _game_state.map,
				"pos": target_pos,
				"unit_id": unit.id
			})
		_:
			return false
	return true

func can_reach(unit: Unit, target_pos: Vector2i) -> bool:
	return _is_adjacent(unit.position, target_pos)

func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1
