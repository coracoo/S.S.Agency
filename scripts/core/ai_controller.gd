class_name AIController
extends RefCounted

var map: GameMap
var all_units: Array

func _init(gmap: GameMap, units: Array) -> void:
	map = gmap
	all_units = units

func dispose() -> void:
	pass

func generate_turn_plan(enemies: Array, context: Dictionary = {}) -> Dictionary:
	var players: Array = context.get("players", [])
	var plans = []
	for enemy in enemies:
		if enemy == null or not enemy.is_alive:
			continue
		var plan = generate_enemy_plan(enemy, context)
		plans.append(plan)
	return {
		"turn": int(context.get("turn", 0)),
		"phase": "intent",
		"plans": plans,
		"players": players,
	}

func generate_enemy_plan(enemy: Unit, context: Dictionary = {}) -> Dictionary:
	var players: Array = context.get("players", [])
	var actions = []
	_update_ai_state(enemy, context)
	var behavior = _get_behavior(enemy)
	var reason = "default"
	var plan_state = enemy.ai_state

	if enemy.ai_state == "fear":
		var fear_pos = _find_nearest_tagged_cell(enemy, enemy.ai_profile.get("fearTags", []), int(enemy.ai_profile.get("fearRange", 3)))
		var escape_pos = _move_away_from_pos(enemy, fear_pos) if fear_pos != Vector2i(-1, -1) else null
		if escape_pos != null:
			var escape_path = Pathfinding.find_path(map, enemy.position, escape_pos)
			if escape_path.size() >= 2:
				actions.append(_make_move_action(enemy, enemy.position, escape_pos, escape_path, "fear"))
		reason = "fear_source" if fear_pos != Vector2i(-1, -1) else "fear"
		return _make_enemy_plan(enemy, plan_state, behavior, reason, actions)

	if enemy.ai_state == "search" and enemy.search_target != Vector2i(-1, -1):
		var search_pos = _move_toward_pos(enemy, enemy.search_target, enemy.move_range)
		if search_pos != null:
			var search_path = Pathfinding.find_path(map, enemy.position, search_pos)
			if search_path.size() >= 2:
				actions.append(_make_move_action(enemy, enemy.position, search_pos, search_path, "search"))
		enemy.search_turns -= 1
		if enemy.search_turns <= 0 or enemy.position == enemy.search_target:
			enemy.ai_state = enemy.ai_profile.get("defaultState", "patrol")
		reason = "noise"
		return _make_enemy_plan(enemy, plan_state, behavior, reason, actions)

	var target = _find_target(enemy, players, behavior)
	if target == null:
		return _make_enemy_plan(enemy, plan_state, behavior, "no_target", actions)

	var move_target = _find_move_target(enemy, target, behavior)
	var attack_from = enemy.position
	if move_target != null:
		var move_path = Pathfinding.find_path(map, enemy.position, move_target)
		if move_path.size() >= 2:
			actions.append(_make_move_action(enemy, enemy.position, move_target, move_path, "move"))
			attack_from = move_target

	var attack_target = _find_attack_target_from_pos(enemy, players, behavior, attack_from)
	if attack_target != null:
		actions.append(_make_attack_action(enemy, attack_from, attack_target, behavior))
		plan_state = "attack" if attack_from == enemy.position else "chase"
		enemy.ai_state = plan_state
	else:
		plan_state = "chase"
		enemy.ai_state = plan_state
	reason = "target_visible"
	return _make_enemy_plan(enemy, plan_state, behavior, reason, actions)

func generate_intents(turn_plan: Dictionary) -> Array:
	var intents = []
	for plan in turn_plan.get("plans", []):
		for action in plan.get("actions", []):
			var kind = action.get("type", "")
			if kind == "move":
				intents.append({
					"type": "move",
					"unit_id": plan.get("unit_id", ""),
					"from": action.get("from", Vector2i(-1, -1)),
					"to": action.get("to", Vector2i(-1, -1)),
					"path": action.get("path", []),
					"intent_style": action.get("intent_style", "move"),
					"state": plan.get("state", ""),
				})
			elif kind == "attack":
				intents.append({
					"type": "attack",
					"unit_id": plan.get("unit_id", ""),
					"from": action.get("from", Vector2i(-1, -1)),
					"to": action.get("to", Vector2i(-1, -1)),
					"target_id": action.get("target_id", ""),
					"behavior": action.get("attack_kind", plan.get("behavior", "melee")),
					"state": plan.get("state", ""),
				})
	return intents

func plan_turn(enemies: Array, players: Array) -> Array:
	var turn_plan = generate_turn_plan(enemies, {"players": players})
	return flatten_plan_actions(turn_plan)

func flatten_plan_actions(turn_plan: Dictionary) -> Array:
	var actions = []
	for plan in turn_plan.get("plans", []):
		var unit_id = str(plan.get("unit_id", ""))
		for action in plan.get("actions", []):
			if action.get("type", "") == "move":
				actions.append({
					"type": "move",
					"unit_id": unit_id,
					"target_pos": action.get("to", Vector2i(-1, -1)),
					"path": action.get("path", []),
					"intent_style": action.get("intent_style", "move"),
				})
			elif action.get("type", "") == "attack":
				actions.append({
					"type": "attack",
					"unit_id": unit_id,
					"target_id": action.get("target_id", ""),
					"target_pos": action.get("to", Vector2i(-1, -1)),
					"attack_kind": action.get("attack_kind", plan.get("behavior", "melee")),
				})
	return actions

func _make_enemy_plan(enemy: Unit, plan_state: String, behavior: String, reason: String, actions: Array) -> Dictionary:
	return {
		"unit_id": enemy.id,
		"template_id": enemy.template_id,
		"state": plan_state,
		"behavior": behavior,
		"reason": reason,
		"actions": actions,
	}

func _make_move_action(enemy: Unit, from_pos: Vector2i, to_pos: Vector2i, path: Array, intent_style: String) -> Dictionary:
	return {
		"type": "move",
		"unit_id": enemy.id,
		"from": from_pos,
		"to": to_pos,
		"path": path,
		"intent_style": intent_style,
	}

func _make_attack_action(enemy: Unit, from_pos: Vector2i, target: Unit, behavior: String) -> Dictionary:
	return {
		"type": "attack",
		"unit_id": enemy.id,
		"from": from_pos,
		"to": target.position,
		"target_id": target.id,
		"attack_kind": behavior,
	}

func _update_ai_state(enemy: Unit, context: Dictionary = {}) -> void:
	var fear_tags = enemy.ai_profile.get("fearTags", [])
	var fear_range = int(enemy.ai_profile.get("fearRange", 0))
	if fear_range > 0 and not fear_tags.is_empty():
		if _find_nearest_tagged_cell(enemy, fear_tags, fear_range) != Vector2i(-1, -1):
			enemy.ai_state = "fear"
			return
	for noise in context.get("noise_events", []):
		var pos: Vector2i = noise.get("pos", Vector2i(-1, -1))
		var volume = int(noise.get("volume", 0))
		var hearing = int(enemy.ai_profile.get("noiseHearing", 0))
		var noise_map: Dictionary = noise.get("noise_map", {})
		var propagated_value = int(noise_map.get(enemy.position, 0))
		var heard_by_map = propagated_value > 0 and propagated_value <= volume and propagated_value + hearing >= volume
		var heard_by_fallback = pos != Vector2i(-1, -1) and _manhattan(enemy.position, pos) <= mini(volume, hearing)
		if hearing > 0 and (heard_by_map or heard_by_fallback):
			enemy.ai_state = "search"
			enemy.search_target = pos
			enemy.search_turns = 2
			return
	if enemy.ai_state == "fear":
		enemy.ai_state = enemy.ai_profile.get("defaultState", "patrol")

func _get_behavior(enemy: Unit) -> String:
	var configured = enemy.ai_profile.get("behavior", "")
	if configured != "":
		return configured
	var tid = enemy.template_id
	if tid.find("archer") >= 0:
		return "ranged"
	if tid.find("knight") >= 0:
		return "tank"
	if tid.find("mage") >= 0:
		return "mage"
	return "melee"

func _find_target(enemy: Unit, players: Array, behavior: String) -> Unit:
	var alive = []
	for p in players:
		if p.is_alive:
			alive.append(p)
	if alive.is_empty():
		return null

	if behavior == "mage":
		var best = alive[0]
		for p in alive:
			if p.current_hp < best.current_hp:
				best = p
		return best
	return _find_nearest(enemy, alive)

func _find_move_target(enemy: Unit, target: Unit, behavior: String) -> Variant:
	var dist = _manhattan(enemy.position, target.position)

	if behavior == "ranged":
		if dist >= 3 and dist <= 4:
			return null
		if dist > 4:
			return _move_toward(enemy, target, maxi(1, dist - 3))
		return _move_away(enemy, target)

	if behavior == "mage":
		if dist >= 2 and dist <= 3:
			return null
		if dist > 3:
			return _move_toward(enemy, target, maxi(1, dist - 2))
		return _move_away(enemy, target)

	if dist <= 1:
		return null
	return _move_toward(enemy, target, enemy.move_range)

func _find_attack_target_from_pos(enemy: Unit, players: Array, behavior: String, from_pos: Vector2i) -> Unit:
	var targets = []
	var range_limit = _attack_range_for_behavior(behavior)
	for player in players:
		if player == null or not player.is_alive:
			continue
		if behavior == "ranged" or behavior == "mage":
			if _manhattan(player.position, from_pos) <= range_limit:
				targets.append(player)
		elif _manhattan(player.position, from_pos) <= 1:
			targets.append(player)
	if targets.is_empty():
		return null
	var best = targets[0]
	for target in targets:
		if target.current_hp < best.current_hp:
			best = target
	return best

func _attack_range_for_behavior(behavior: String) -> int:
	if behavior == "ranged":
		return 4
	if behavior == "mage":
		return 3
	return 1

func _move_toward(enemy: Unit, target: Unit, max_steps: int) -> Variant:
	return _move_toward_pos(enemy, target.position, max_steps, target)

func _move_toward_pos(enemy: Unit, target_pos: Vector2i, max_steps: int, target_unit: Unit = null) -> Variant:
	max_steps = mini(max_steps, enemy.move_range)
	var reachable = Pathfinding.get_reachable_tiles(map, enemy.position, max_steps)
	if reachable.is_empty():
		return null
	var best_pos = null
	var best_score = -9999.0
	for pos in reachable:
		var score = -float(_manhattan(pos, target_pos))
		var dist = _manhattan(pos, target_pos)
		if target_unit != null and dist <= 1:
			var atk_dir = target_unit.position - pos
			var card_dir := Vector2i.ZERO
			if absi(atk_dir.x) >= absi(atk_dir.y):
				card_dir = Vector2i.RIGHT if atk_dir.x > 0 else Vector2i.LEFT
			else:
				card_dir = Vector2i.DOWN if atk_dir.y > 0 else Vector2i.UP
			if card_dir == -target_unit.facing:
				score += 5.0
			elif card_dir != target_unit.facing:
				score += 3.0
		if score > best_score:
			best_score = score
			best_pos = pos
	var current_score = -float(_manhattan(enemy.position, target_pos))
	if best_score <= current_score:
		return null
	return best_pos

func _move_away(enemy: Unit, threat: Unit) -> Variant:
	return _move_away_from_pos(enemy, threat.position)

func _move_away_from_pos(enemy: Unit, threat_pos: Vector2i) -> Variant:
	var reachable = Pathfinding.get_reachable_tiles(map, enemy.position, enemy.move_range)
	if reachable.is_empty():
		return null
	var best_pos = null
	var best_dist = 0
	for pos in reachable:
		var d = _manhattan(pos, threat_pos)
		if d > best_dist:
			best_dist = d
			best_pos = pos
	var current_dist = _manhattan(enemy.position, threat_pos)
	if best_dist <= current_dist:
		return null
	return best_pos

func _find_nearest_tagged_cell(enemy: Unit, tags: Array, max_range: int) -> Vector2i:
	for dist in range(0, max_range + 1):
		for dy in range(-dist, dist + 1):
			var max_dx = dist - absi(dy)
			for dx in [-max_dx, max_dx]:
				var pos = enemy.position + Vector2i(dx, dy)
				if not map.in_bounds(pos):
					continue
				for tag in tags:
					if map.has_tag(pos.x, pos.y, tag):
						return pos
	return Vector2i(-1, -1)

func _find_nearest(unit: Unit, targets: Array) -> Unit:
	var best = null
	var best_dist = 9999
	for t in targets:
		if not t.is_alive:
			continue
		var d = _manhattan(unit.position, t.position)
		if d < best_dist:
			best_dist = d
			best = t
	return best

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _update_facing(unit: Unit, target_pos: Vector2i) -> void:
	var diff = target_pos - unit.position
	if diff == Vector2i.ZERO:
		return
	if absi(diff.x) >= absi(diff.y):
		unit.facing = Vector2i.RIGHT if diff.x > 0 else Vector2i.LEFT
	else:
		unit.facing = Vector2i.DOWN if diff.y > 0 else Vector2i.UP
