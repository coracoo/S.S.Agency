class_name CardResolver
extends RefCounted

static func get_valid_targets(card: Dictionary, caster: Unit, map: GameMap, all_units: Array) -> Array:
	var pos = caster.position
	var targets = []
	var target_type = card.get("targetType", "self")

	match target_type:
		"self":
			targets.append(pos)
		"adjacent_enemy":
			for n in map.get_neighbors(pos):
				var occ = map.get_occupant_id(n)
				if occ != "":
					var u = _find_unit(all_units, occ)
					if u and u.faction != caster.faction and u.is_alive:
						targets.append(n)
		"enemy_in_range":
			var range_val = card.get("range", 1)
			for u in all_units:
				if not u.is_alive or u.faction == caster.faction:
					continue
				var d = absi(u.position.x - pos.x) + absi(u.position.y - pos.y)
				if d <= range_val:
					targets.append(u.position)
		"enemy_or_object_in_range":
			var range_val = card.get("range", 1)
			# Add enemies in range
			for u in all_units:
				if not u.is_alive or u.faction == caster.faction:
					continue
				var d = absi(u.position.x - pos.x) + absi(u.position.y - pos.y)
				if d <= range_val:
					targets.append(u.position)
			# Also add tiles with targetable objects (for terrain effects)
			for row in range(map.rows):
				for col in range(map.cols):
					var np = Vector2i(col, row)
					var d = absi(np.x - pos.x) + absi(np.y - pos.y)
					if d > range_val:
						continue
					var occ = map.get_occupant_id(np)
					if occ != "":
						continue
					if _can_target_tile_with_card(card, map, np):
						targets.append(np)
		"ally":
			var range_val = card.get("range", 99)
			for u in all_units:
				if not u.is_alive or u.id == caster.id or u.faction != caster.faction:
					continue
				var d = absi(u.position.x - pos.x) + absi(u.position.y - pos.y)
				if d <= range_val:
					targets.append(u.position)
		"direction":
			var max_dist = 2
			var mt = card.get("effects", []).map(func(e): return e.get("maxDistance", 0))
			if mt.size() > 0:
				max_dist = mt.max()
			if card.get("range", 0) > 0:
				max_dist = card.get("range", max_dist)
			var dirs = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
			for dir in dirs:
				for d in range(1, max_dist + 1):
					var np = pos + dir * d
					if map.in_bounds(np) and map.is_walkable(np) and not map.is_occupied(np):
						targets.append(np)
					else:
						break
		"adjacent_empty":
			for n in map.get_neighbors(pos):
				if map.is_walkable(n) and not map.is_occupied(n):
					targets.append(n)
				elif _can_target_object_with_terrain_effect(card, map, n):
					targets.append(n)
		"area_3x3":
			var range_val = card.get("range", 3)
			for u in all_units:
				if not u.is_alive or u.faction == caster.faction:
					continue
				var d = absi(u.position.x - pos.x) + absi(u.position.y - pos.y)
				if d <= range_val:
					targets.append(u.position)
				# Also add tiles with targetable objects
			for dr in range(-range_val, range_val + 1):
				for dc in range(-range_val, range_val + 1):
					var np = pos + Vector2i(dc, dr)
					if map.in_bounds(np) and not targets.has(np):
						if _can_target_tile_with_card(card, map, np):
							targets.append(np)
		"tile_in_range":
			var range_val = card.get("range", 3)
			for row in range(map.rows):
				for col in range(map.cols):
					var np = Vector2i(col, row)
					var d = absi(np.x - pos.x) + absi(np.y - pos.y)
					if d <= range_val:
						targets.append(np)
		"enemy_or_tile_in_range":
			var range_val = card.get("range", 3)
			for row in range(map.rows):
				for col in range(map.cols):
					var np = Vector2i(col, row)
					var d = absi(np.x - pos.x) + absi(np.y - pos.y)
					if d > range_val:
						continue
					var occ = map.get_occupant_id(np)
					if occ == "":
						if map.is_walkable(np):
							targets.append(np)
					else:
						var u = _find_unit(all_units, occ)
						if u and u.faction != caster.faction and u.is_alive:
							targets.append(np)

	return targets

static func _can_target_object_with_terrain_effect(card: Dictionary, map: GameMap, pos: Vector2i) -> bool:
	if map.get_object(pos.x, pos.y) == "":
		return false
	for eff in card.get("effects", []):
		if eff.get("type", "") == "add_terrain_effect" and eff.get("effect", "") == "fire":
			return map.has_tag(pos.x, pos.y, "flammable") or map.has_tag(pos.x, pos.y, "explosive")
	return false

static func _can_target_tile_with_card(card: Dictionary, map: GameMap, pos: Vector2i) -> bool:
	# Check if card has terrain effect
	var has_terrain_effect = false
	var terrain_effect_type = ""
	for eff in card.get("effects", []):
		if eff.get("type", "") == "add_terrain_effect":
			has_terrain_effect = true
			terrain_effect_type = eff.get("effect", "")
			break
	if not has_terrain_effect:
		return false
	# Empty walkable tile — can target
	if not map.is_occupied(pos) and map.is_walkable(pos):
		return true
	# Check if tile has targetable object
	var obj = map.get_object(pos.x, pos.y)
	if obj == "":
		return false
	# For fire terrain effect, can target flammable/explosive objects
	if terrain_effect_type == "fire":
		return map.has_tag(pos.x, pos.y, "flammable") or map.has_tag(pos.x, pos.y, "explosive")
	return false

static func play_card(card: Dictionary, caster: Unit, target_pos: Vector2i, map: GameMap, all_units: Array, game_state: GameState = null) -> Dictionary:
	var killed = []
	var moved_unit = null
	var drawn_count = 0
	var pulled_target = null
	var gained_ap = 0

	# Check for adjacent_all pattern — hit ALL adjacent enemies
	var is_adjacent_all = false
	for eff in card.get("effects", []):
		if eff.get("pattern", "") == "adjacent_all":
			is_adjacent_all = true
			break

	if is_adjacent_all:
		var ctx_all = {
			"caster_stats": caster.stats,
			"target_stats": {},
			"caster_pos": caster.position,
			"target_pos": target_pos,
			"target_dodge": 0,
			"target_defense_modifier": 1.0,
		}
		var all_effects = []
		var affected_units = []
		for neighbor in map.get_neighbors(caster.position):
			var occ = map.get_occupant_id(neighbor)
			if occ == "":
				continue
			var u = _find_unit(all_units, occ)
			if u == null or u.faction == caster.faction or not u.is_alive:
				continue
			ctx_all.target_stats = u.stats
			ctx_all.target_dodge = map.get_terrain_dodge(u.position)
			ctx_all.target_defense_modifier = u.get_defense_modifier(caster.position)
			var fx = CardEffectParser.resolve_effects(card.get("effects", []), ctx_all)
			for result in fx:
				if result.get("damage", 0) > 0:
					var dmg_type = result.get("damage_type", "physical")
					u.take_damage(result.damage, dmg_type, caster.position)
					affected_units.append({"unit_id": u.id, "damage": result.damage})
					if not u.is_alive:
						map.set_occupant(u.position, null)
						killed.append(u.id)
				if result.get("status_id", "") != "":
					StatusEffectManager.apply_status(u, result.status_id, result.get("status_duration", 1))
				if result.get("type") == "push_unit":
					_push_unit(caster, u, result.get("distance", 1), map, killed)
				if result.get("type") == "pull":
					_pull_unit(caster, u, result.get("distance", 1), map, killed)
				if result.get("type") == "lifesteal":
					_lifesteal(caster, fx)
			all_effects.append_array(fx)
		return {
			"success": true,
			"effects": all_effects,
			"targets": map.get_neighbors(caster.position),
			"killed": killed,
			"moved_unit": null,
			"drawn_count": 0,
			"gained_ap": 0,
			"affected_units": affected_units,
		}

	# Check for area_3x3 spell — hit ALL enemies in area around target
	if card.get("targetType", "") == "area_3x3":
		var area_size = card.get("areaSize", 1)
		var area_targets = []
		for dr in range(-area_size, area_size + 1):
			for dc in range(-area_size, area_size + 1):
				var np = target_pos + Vector2i(dc, dr)
				if map.in_bounds(np):
					area_targets.append(np)
		var all_area_effects = []
		var affected_units = []
		# First pass: handle all tiles (units + terrain effects)
		for tile in area_targets:
			var occ = map.get_occupant_id(tile)
			var is_enemy_unit = false
			if occ != "":
				var u = _find_unit(all_units, occ)
				if u != null and u.faction != caster.faction and u.is_alive:
					is_enemy_unit = true
					var ctx_a = {
						"caster_stats": caster.stats,
						"target_stats": u.stats,
						"caster_pos": caster.position,
						"target_pos": tile,
						"target_dodge": map.get_terrain_dodge(u.position),
						"target_defense_modifier": u.get_defense_modifier(caster.position),
					}
					var fx = CardEffectParser.resolve_effects(card.get("effects", []), ctx_a)
					for result in fx:
						if result.get("damage", 0) > 0:
							var dmg_type = result.get("damage_type", "physical")
							u.take_damage(result.damage, dmg_type, caster.position)
							affected_units.append({"unit_id": u.id, "damage": result.damage})
							if not u.is_alive:
								map.set_occupant(u.position, null)
								killed.append(u.id)
						if result.get("status_id", "") != "":
							StatusEffectManager.apply_status(u, result.status_id, result.get("status_duration", 1))
						# Handle terrain effects in area
						if result.get("type") == "add_terrain_effect":
							var eff = result.get("effect", "fire")
							map.add_effect(tile.x, tile.y, eff)
							_emit_event("effect:added", {"map": map, "pos": tile, "effect": eff})
					all_area_effects.append_array(fx)
			if not is_enemy_unit:
				# Empty tile — still check for terrain effects
				var ctx_empty = {"caster_stats": caster.stats, "target_stats": {}, "caster_pos": caster.position, "target_pos": tile, "target_dodge": 0, "target_defense_modifier": 1.0}
				var fx = CardEffectParser.resolve_effects(card.get("effects", []), ctx_empty)
				for result in fx:
					if result.get("type") == "add_terrain_effect":
						var eff = result.get("effect", "fire")
						map.add_effect(tile.x, tile.y, eff)
						_emit_event("effect:added", {"map": map, "pos": tile, "effect": eff})
				all_area_effects.append_array(fx)
		return {
			"success": true,
			"effects": all_area_effects,
			"targets": area_targets,
			"killed": killed,
			"moved_unit": null,
			"drawn_count": 0,
			"gained_ap": 0,
			"affected_units": affected_units,
		}

	var target_unit = _find_unit_at(all_units, target_pos)
	var affected_units = []

	var ctx = {
		"caster_stats": caster.stats,
		"target_stats": target_unit.stats if target_unit else {},
		"caster_pos": caster.position,
		"target_pos": target_pos,
		"target_dodge": map.get_terrain_dodge(target_pos) if target_unit else 0,
		"target_defense_modifier": target_unit.get_defense_modifier(caster.position) if target_unit else 1.0,
	}

	var effects = CardEffectParser.resolve_effects(card.get("effects", []), ctx)
	var was_dodged = false
	for result in effects:
		if result.get("dodged", false):
			was_dodged = true
		if result.get("damage", 0) > 0 and target_unit:
			var dmg_type = result.get("damage_type", "physical")
			target_unit.take_damage(result.damage, dmg_type, caster.position)
			affected_units.append({"unit_id": target_unit.id, "damage": result.damage})
			if not target_unit.is_alive:
				map.set_occupant(target_unit.position, null)
				killed.append(target_unit.id)
		if result.get("heal_amount", 0) > 0 and target_unit:
			target_unit.heal(result.heal_amount)
		if result.get("shield_amount", 0) > 0:
			var shield_target = target_unit if target_unit and card.get("targetType", "") == "ally" else caster
			shield_target.add_shield(result.shield_amount)
		if result.get("moved", false):
			if target_pos != caster.position and (not map.is_walkable(target_pos) or map.is_occupied(target_pos)):
				return {"success": false}
			var from = caster.position
			map.set_occupant(from, null)
			caster.move_to(target_pos)
			map.set_occupant(target_pos, caster.id)
			moved_unit = {"unit_id": caster.id, "from": from, "to": target_pos}
		if result.get("status_id", "") != "":
			if target_unit:
				StatusEffectManager.apply_status(target_unit, result.status_id, result.get("status_duration", 1))
			elif card.get("targetType", "") == "self":
				StatusEffectManager.apply_status(caster, result.status_id, result.get("status_duration", 1))
		if result.get("type") == "lifesteal" and target_unit:
			var dmg_dealt = 0
			for r in effects:
				if r.get("damage", 0) > 0:
					dmg_dealt = r.damage
					break
			if dmg_dealt > 0:
				var heal_amt = maxi(1, int(dmg_dealt * result.get("ratio", 0.3)))
				var healed = caster.heal(heal_amt)
				if game_state and healed > 0:
					game_state.emit_signal("unit_healed", caster.id, healed)
		if result.get("type") == "pull" and target_unit:
			var pull_from = target_unit.position
			var pull_dist = result.get("distance", 1)
			var dir = caster.position - target_unit.position
			for _i in range(pull_dist):
				if dir.x == 0 and dir.y == 0:
					break
				var step = Vector2i(signi(dir.x), 0) if absi(dir.x) >= absi(dir.y) else Vector2i(0, signi(dir.y))
				var next_pos = target_unit.position + step
				if map.in_bounds(next_pos) and map.has_tag(next_pos.x, next_pos.y, "lethal"):
					map.set_occupant(target_unit.position, null)
					target_unit.take_damage(target_unit.current_hp)
					if not target_unit.is_alive and not killed.has(target_unit.id):
						killed.append(target_unit.id)
					break
				if map.in_bounds(next_pos) and map.is_walkable(next_pos) and not map.is_occupied(next_pos):
					map.set_occupant(target_unit.position, null)
					target_unit.move_to(next_pos, step)
					map.set_occupant(next_pos, target_unit.id)
					dir = caster.position - target_unit.position
				else:
					break
			if target_unit.position != pull_from:
				pulled_target = {"unit_id": target_unit.id, "from": pull_from, "to": target_unit.position}
		if result.get("type") == "retreat":
			var ret_from = caster.position
			var ret_dir = caster.position - target_pos
			if ret_dir.x != 0 or ret_dir.y != 0:
				var ret_step = Vector2i(signi(ret_dir.x), 0) if absi(ret_dir.x) >= absi(ret_dir.y) else Vector2i(0, signi(ret_dir.y))
				for _i in range(result.get("distance", 2)):
					var ret_next = caster.position + ret_step
					if map.in_bounds(ret_next) and map.is_walkable(ret_next) and not map.is_occupied(ret_next):
						map.set_occupant(caster.position, null)
						caster.move_to(ret_next, ret_step)
						map.set_occupant(ret_next, caster.id)
					else:
						break
				if moved_unit == null:
						moved_unit = {"unit_id": caster.id, "from": ret_from, "to": caster.position}
		if result.get("drawn_cards", 0) > 0:
			drawn_count = result.drawn_cards
		if result.get("gained_energy", 0) > 0:
			gained_ap = result.gained_energy
		if result.get("type") == "add_terrain_effect":
			var eff = result.get("effect", "fire")
			map.add_effect(target_pos.x, target_pos.y, eff)
			_emit_event("effect:added", {"map": map, "pos": target_pos, "effect": eff})
		if result.get("type") == "create_noise":
			_emit_event("noise:created", {
				"map": map,
				"pos": target_pos,
				"volume": int(result.get("volume", 3)),
				"duration": int(result.get("duration", 1)),
				"source_id": caster.id,
				"source_type": result.get("source_type", "card")
			})
		if result.get("type") == "push_unit" and target_unit and target_unit.is_alive:
			var push_dist = result.get("distance", 1)
			var push_dir = target_unit.position - caster.position
			if push_dir.x != 0 or push_dir.y != 0:
				var step = Vector2i(signi(push_dir.x), 0) if absi(push_dir.x) >= absi(push_dir.y) else Vector2i(0, signi(push_dir.y))
				for _i in range(push_dist):
					var next_pos = target_unit.position + step
					if not map.in_bounds(next_pos):
						break
					# Pushed into lethal terrain = instant death
					if map.has_tag(next_pos.x, next_pos.y, "lethal"):
						map.set_occupant(target_unit.position, null)
						target_unit.take_damage(target_unit.current_hp)
						if not target_unit.is_alive and not killed.has(target_unit.id):
							killed.append(target_unit.id)
						break
					if map.is_walkable(next_pos) and not map.is_occupied(next_pos):
						map.set_occupant(target_unit.position, null)
						target_unit.move_to(next_pos, step)
						map.set_occupant(next_pos, target_unit.id)
					else:
						break

	# Execute draw_cards and gain_energy via game_state
	if game_state and drawn_count > 0:
		var player = game_state.get_player_for_unit(caster.id)
		if not player.is_empty():
			var drawn = player.deck.draw(drawn_count)
			var overflow = player.hand.add_cards(drawn)
			if not overflow.is_empty():
				player.deck.discard_many(overflow)
	if game_state and gained_ap > 0:
		game_state.set_ap(game_state.team_ap + gained_ap)

	return {
		"success": true,
		"effects": effects,
		"targets": [target_pos],
		"killed": killed,
		"moved_unit": moved_unit,
		"pulled_target": pulled_target,
		"drawn_count": drawn_count,
		"gained_ap": gained_ap,
		"dodged": was_dodged,
		"affected_units": affected_units,
	}

static func _find_unit(all_units: Array, uid: String) -> Unit:
	for u in all_units:
		if u.id == uid:
			return u
	return null

static func _find_unit_at(all_units: Array, pos: Vector2i) -> Unit:
	for u in all_units:
		if u.position == pos and u.is_alive:
			return u
	return null

static func _emit_event(event_name: String, data: Dictionary) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var bus = tree.root.get_node_or_null("/root/EventBus")
	if bus != null:
		bus.emit(event_name, data)
