class_name GameState
extends RefCounted

signal turn_start(who: String)
signal turn_end(who: String)
signal unit_moved(unit_id: String, from: Vector2i, to: Vector2i)
signal unit_damaged(unit_id: String, damage: int)
signal unit_healed(unit_id: String, amount: int)
signal unit_died(unit_id: String)
signal hand_changed()
signal energy_changed(current: int, max_val: int)
signal card_played(unit_id: String, card_id: String, targets: Array)
signal battle_won()
signal battle_lost()

var map: GameMap
var bg_image_path: String = ""
var all_units: Array = []
var players: Array = []  # Array of {unit, deck, hand}
var enemies: Array = []  # Array of Unit
var balance: Dictionary = {}

var current_turn: String = "player"
var turn_count: int = 0
var team_ap: int = 0
var max_ap: int = 10
var selected_unit: Unit = null
var selected_card_index: int = -1
var selected_inventory_index: int = -1
var inventory_target_tiles: Array = []
var spirit_density: int = 0
var player_spawn_defs: Array = []
var enemy_spawn_defs: Array = []
var noise_events: Array = []
var skipped_unit_ids: Dictionary = {}

func _init() -> void:
	balance = JsonLoader.load_file("res://data/balance.json")
	if balance == null:
		balance = {}
	max_ap = int(balance.get("maxAp", 10))
	var maps_data = JsonLoader.load_file("res://data/maps.json")
	var map_defs = maps_data.get("maps", []) if maps_data is Dictionary else []
	if not (map_defs is Array) or map_defs.is_empty():
		push_error("Failed to load maps data")
		return
	var map_def = map_defs[0]
	# Load terrain system data
	var terrains_data = _load_json_safe("res://data/terrains.json")
	var effects_data = _load_json_safe("res://data/effects.json")
	var objects_data = _load_json_safe("res://data/objects.json")
	map = GameMap.new(map_def, terrains_data, effects_data, objects_data)
	# Legacy terrain effects fallback
	map.load_terrain_effects(balance.get("terrainEffects", {}))
	spirit_density = int(map_def.get("initialSpiritDensity", 0))
	bg_image_path = map_def.get("bgImage", "")
	var spawn_points = map_def.get("spawn_points", {})
	player_spawn_defs = _parse_spawn_defs(spawn_points.get("players", []), ["rinne", "mint", "homura", "zhongkui"])
	enemy_spawn_defs = _parse_spawn_defs(spawn_points.get("enemies", []), ["paper_effigy", "paper_effigy", "jiangshi", "red_lady"])

func _load_json_safe(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing JSON file: " + path)
		return {}
	var data = JsonLoader.load_file(path)
	return data if data is Dictionary else {}

func _parse_spawn_defs(entries: Array, default_templates: Array) -> Array:
	var result = []
	for i in range(entries.size()):
		var entry = entries[i]
		var template = default_templates[i % default_templates.size()] if not default_templates.is_empty() else ""
		var pos = Vector2i.ZERO
		if entry is Dictionary:
			template = entry.get("template", template)
			var raw_pos = entry.get("pos", [0, 0])
			pos = Vector2i(int(raw_pos[0]), int(raw_pos[1]))
		elif entry is Array and entry.size() >= 2:
			pos = Vector2i(int(entry[0]), int(entry[1]))
		else:
			continue
		result.append({"template": template, "pos": pos})
	return result

func init_battle(player_spawns: Array, enemy_spawns: Array) -> void:
	for spawn in player_spawns:
		var unit = UnitFactory.create(spawn.template, spawn.pos)
		if unit == null:
			continue
		all_units.append(unit)
		var deck = Deck.new(UnitFactory.get_starting_deck(spawn.template))
		var inv = Inventory.new()
		for item_def in UnitFactory.get_starting_items(spawn.template):
			if item_def is Dictionary:
				var card_id = str(item_def.get("card", ""))
				var object_id = str(item_def.get("object", ""))
				var uses = int(item_def.get("uses", 1))
				if card_id != "":
					inv.add_card_item(card_id, uses)
				elif object_id != "":
					inv.add_item(object_id, item_def.get("consumable", true), uses)
		players.append({
			"unit": unit,
			"deck": deck,
			"hand": Hand.new(int(balance.get("maxHandSize", 10))),
			"inventory_ref": inv
		})
		map.set_occupant(spawn.pos, unit.id)

	for spawn in enemy_spawns:
		var unit = UnitFactory.create(spawn.template, spawn.pos)
		if unit == null:
			continue
		all_units.append(unit)
		enemies.append(unit)
		map.set_occupant(spawn.pos, unit.id)

func get_player_for_unit(uid: String) -> Dictionary:
	for p in players:
		if p.unit.id == uid:
			return p
	return {}

func get_unit_by_id(uid: String) -> Unit:
	for u in all_units:
		if u.id == uid:
			return u
	return null

func get_alive_units(faction: String = "") -> Array:
	var result = []
	for u in all_units:
		if u.is_alive and (faction == "" or u.faction == faction):
			result.append(u)
	return result

func mark_unit_skipped(unit_id: String) -> void:
	skipped_unit_ids[unit_id] = true

func clear_skipped_units() -> void:
	skipped_unit_ids.clear()

func is_unit_skipped(unit_id: String) -> bool:
	return skipped_unit_ids.get(unit_id, false)

func can_spend_ap(cost: int) -> bool:
	return cost >= 0 and current_turn == "player" and team_ap >= cost

func spend_ap(cost: int) -> bool:
	if not can_spend_ap(cost):
		return false
	team_ap -= cost
	emit_signal("energy_changed", team_ap, max_ap)
	return true

func set_ap(value: int) -> void:
	team_ap = clampi(value, 0, max_ap)
	emit_signal("energy_changed", team_ap, max_ap)

func modify_spirit_density(delta: int) -> void:
	spirit_density = clampi(spirit_density + delta, 0, 10)

func add_noise(pos: Vector2i, volume: int, source_id: String = "", source_type: String = "", noise_map: Dictionary = {}, duration: int = 1) -> void:
	noise_events.append({
		"pos": pos,
		"volume": volume,
		"source_id": source_id,
		"source_type": source_type,
		"noise_map": noise_map,
		"duration": maxi(1, duration),
		"turn": turn_count
	})
	if noise_events.size() > 8:
		noise_events.pop_front()

func clear_old_noise() -> void:
	for i in range(noise_events.size() - 1, -1, -1):
		var event_turn = int(noise_events[i].get("turn", turn_count))
		var duration = int(noise_events[i].get("duration", 1))
		if maxi(0, turn_count - event_turn) >= duration:
			noise_events.remove_at(i)

func is_battle_over() -> String:
	var alive_enemies = 0
	var alive_players = 0
	for e in enemies:
		if e.is_alive:
			alive_enemies += 1
	for p in players:
		if p.unit.is_alive:
			alive_players += 1
	if alive_enemies == 0:
		return "won"
	if alive_players == 0:
		return "lost"
	return ""
