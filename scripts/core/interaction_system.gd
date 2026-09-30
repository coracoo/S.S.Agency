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
	# 凛音「重心稳」:可推重物(tags 含 heavy),且推动距离 +1
	var strong_push = unit.has_trait("heavy_push")
	var obj_tags: Array = odef.get("tags", [])
	if "heavy" in obj_tags and not strong_push:
		return false
	# 落点:从最远推动距离往回找第一格可落点(途经格必须可走、无单位、无物体)
	var max_dist = 2 if strong_push else 1
	var dest = Vector2i(-1, -1)
	for d in range(max_dist, 0, -1):
		var cand = target_pos + direction * d
		if not _game_state.map.in_bounds(cand):
			continue
		if not _game_state.map.is_walkable(cand):
			continue
		if _game_state.map.is_occupied(cand):
			continue
		if _game_state.map.get_object(cand.x, cand.y) != "":
			continue
		# 途经格(目标格与落点之间)也必须无阻挡
		var blocked = false
		for step in range(1, d):
			var mid = target_pos + direction * step
			if not _game_state.map.is_walkable(mid) or _game_state.map.is_occupied(mid) or _game_state.map.get_object(mid.x, mid.y) != "":
				blocked = true
				break
		if blocked:
			continue
		dest = cand
		break
	if dest == Vector2i(-1, -1):
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

func pull(unit: Unit, direction: Vector2i) -> bool:
	# 拉(GDD):将相邻物体拉到角色位置,角色后退 1 格,消耗 1 AP。pushable 即可拉
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
	# 角色后退 1 格的目的地必须可走、无单位、无物体
	var back = unit.position - direction
	if not _game_state.map.in_bounds(back):
		return false
	if not _game_state.map.is_walkable(back):
		return false
	if _game_state.map.is_occupied(back):
		return false
	if _game_state.map.get_object(back.x, back.y) != "":
		return false
	if not _game_state.spend_ap(1):
		return false
	var unit_from = unit.position
	# 物体移到角色原位,角色后退
	_game_state.map.set_object(target_pos.x, target_pos.y, null)
	_game_state.map.set_object(unit_from.x, unit_from.y, obj_id)
	_game_state.map.set_occupant(unit_from, null)
	unit.move_to(back)
	_game_state.map.set_occupant(back, unit.id)
	EventBus.emit("object:pulled", {
		"map": _game_state.map,
		"object_id": obj_id,
		"from": target_pos,
		"to": unit_from,
		"puller_id": unit.id,
		"unit_from": unit_from,
		"unit_to": back,
	})
	# 物体落点(角色原位)触发地形规则
	EventBus.emit("effect:added", {"map": _game_state.map, "pos": unit_from})
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
	# 焰华「火焰亲和」:点燃(ignite)不耗 AP
	var ignite_free = action == "ignite" and unit.has_trait("fire_affinity")
	if not ignite_free and not _game_state.spend_ap(1):
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
