class_name GameMap
extends RefCounted

var cols: int
var rows: int
var grid_offset_x: int = 0
var grid_offset_y: int = 0
var tile_w: int = 128
var tile_h: int = 64
var bg_image: String = ""

# Multi-layer storage
var _ground: Array = []        # 2D array of terrain type strings
var _effects: Array = []       # 2D array of effect arrays [{type, duration}, ...]
var _objects: Array = []       # 2D array of object id strings or null
var _collision: Array = []     # 2D array of bool
var _removed_tags: Dictionary = {} # pos -> tag dictionary removed by rules

var _occupants: Dictionary = {} # pos -> unit_id

# Data definitions (loaded from JSON)
var terrains_data: Dictionary = {}
var effects_data: Dictionary = {}
var objects_data: Dictionary = {}

# Legacy v1 support
var terrain_effects: Dictionary = {}
var _is_v1: bool = false

func _init(map_data: Dictionary, p_terrains_data: Dictionary = {}, p_effects_data: Dictionary = {}, p_objects_data: Dictionary = {}) -> void:
	cols = int(map_data.get("cols", 8))
	rows = int(map_data.get("rows", 8))
	grid_offset_x = int(map_data.get("gridOffsetX", 0))
	grid_offset_y = int(map_data.get("gridOffsetY", 0))
	tile_w = int(map_data.get("tileW", 128))
	tile_h = int(map_data.get("tileH", 64))
	bg_image = str(map_data.get("bgImage", ""))
	terrains_data = p_terrains_data
	effects_data = p_effects_data
	objects_data = p_objects_data

	var version = int(map_data.get("version", 1))
	if version >= 2 and map_data.has("layers"):
		_init_v2(map_data)
	else:
		_init_v1(map_data)

func _init_v2(map_data: Dictionary) -> void:
	var layers = map_data.layers
	_ground = layers.get("ground", []).duplicate(true)
	_objects = layers.get("objects", []).duplicate(true)
	_collision = layers.get("collision", []).duplicate(true)
	var effects_raw = layers.get("effects", [])
	# Convert raw effects to runtime format
	_effects = []
	for row in range(rows):
		var effect_row = []
		for col in range(cols):
			var cell_effects = []
			if row < effects_raw.size() and col < effects_raw[row].size():
				for eff in effects_raw[row][col]:
					cell_effects.append({"type": eff, "duration": _get_default_duration(eff)})
			effect_row.append(cell_effects)
		_effects.append(effect_row)
	# Preserve authored collision data when the map provides a full v2 layer.
	if not _has_complete_collision_layer():
		_derive_collision()

func _init_v1(map_data: Dictionary) -> void:
	_is_v1 = true
	var old_terrain = map_data.get("terrain", [])
	_ground = []
	_effects = []
	_objects = []
	_collision = []
	for row in range(rows):
		var ground_row = []
		var effect_row = []
		var object_row = []
		var collision_row = []
		for col in range(cols):
			var t = old_terrain[row][col] if row < old_terrain.size() and col < old_terrain[row].size() else "wall"
			ground_row.append(t)
			effect_row.append([])
			object_row.append(null)
			var tdef = terrains_data.get(t, {})
			var tags = tdef.get("tags", [])
			collision_row.append(tdef.get("move_cost", 1) >= 99 or tags.has("blocking"))
		_ground.append(ground_row)
		_effects.append(effect_row)
		_objects.append(object_row)
		_collision.append(collision_row)

func _derive_collision() -> void:
	_collision = []
	for row in range(rows):
		var crow = []
		for col in range(cols):
			var t = _ground[row][col]
			var tdef = terrains_data.get(t, {})
			var tags = tdef.get("tags", [])
			crow.append(tdef.get("move_cost", 1) >= 99 or tags.has("blocking"))
		_collision.append(crow)

func _has_complete_collision_layer() -> bool:
	if _collision.size() != rows:
		return false
	for row in range(rows):
		if not (_collision[row] is Array) or _collision[row].size() != cols:
			return false
	return true

func _get_default_duration(effect_type: String) -> int:
	var def = effects_data.get(effect_type, {})
	return int(def.get("duration", 1))

func load_terrain_effects(effects: Dictionary) -> void:
	terrain_effects = effects

# --- Bounds / Neighbors ---

func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < cols and pos.y >= 0 and pos.y < rows

func get_neighbors(pos: Vector2i) -> Array:
	var dirs = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var result = []
	for d in dirs:
		var np = pos + d
		if in_bounds(np):
			result.append(np)
	return result

# --- Ground layer ---

func get_terrain(col: int, row: int) -> String:
	if not in_bounds(Vector2i(col, row)):
		return "wall"
	return _ground[row][col]

func get_terrain_dodge(pos: Vector2i) -> int:
	if not in_bounds(pos):
		return 0
	# v1 fallback
	if _is_v1 and not terrain_effects.is_empty():
		var t = _ground[pos.y][pos.x]
		var entry = terrain_effects.get(t, {})
		return int(entry.get("dodge", 0))
	# v2: check terrain data for dodge
	var t = _ground[pos.y][pos.x]
	var tdef = terrains_data.get(t, {})
	return int(tdef.get("dodge", 0))

func get_move_cost(pos: Vector2i) -> int:
	if not in_bounds(pos):
		return 99
	var t = _ground[pos.y][pos.x]
	var tdef = terrains_data.get(t, {})
	return int(tdef.get("move_cost", 1))

# --- Collision / Walkability ---

func is_walkable(pos: Vector2i) -> bool:
	if not in_bounds(pos):
		return false
	if _collision[pos.y][pos.x]:
		return false
	# Check if object blocks
	var obj = _objects[pos.y][pos.x]
	if obj != null:
		var odef = objects_data.get(obj, {})
		if odef.get("tags", []).has("blocking"):
			return false
	return true

# --- Occupants ---

func is_occupied(pos: Vector2i) -> bool:
	return _occupants.has(pos)

func get_occupant_id(pos: Vector2i) -> String:
	return _occupants.get(pos, "")

func set_occupant(pos: Vector2i, unit_id: Variant) -> void:
	if unit_id == null or unit_id == "":
		_occupants.erase(pos)
	else:
		_occupants[pos] = unit_id

# --- Effects layer ---

func get_effects(col: int, row: int) -> Array:
	if not in_bounds(Vector2i(col, row)):
		return []
	return _effects[row][col]

func add_effect(col: int, row: int, effect_type: String, duration_override: int = -1) -> void:
	if not in_bounds(Vector2i(col, row)):
		return
	var duration = duration_override if duration_override > 0 else _get_default_duration(effect_type)
	# Don't duplicate same effect type
	for eff in _effects[row][col]:
		if eff.type == effect_type:
			eff.duration = duration
			return
	_effects[row][col].append({"type": effect_type, "duration": duration})

func remove_effect(col: int, row: int, effect_type: String) -> void:
	if not in_bounds(Vector2i(col, row)):
		return
	var cell = _effects[row][col]
	for i in range(cell.size() - 1, -1, -1):
		if cell[i].type == effect_type:
			cell.remove_at(i)

func tick_effects() -> Array:
	var expired = []
	for row in range(rows):
		for col in range(cols):
			var cell = _effects[row][col]
			for i in range(cell.size() - 1, -1, -1):
				cell[i].duration -= 1
				if cell[i].duration <= 0:
					expired.append({"type": cell[i].type, "col": col, "row": row})
					cell.remove_at(i)
	return expired

# --- Objects layer ---

func get_object(col: int, row: int) -> String:
	if not in_bounds(Vector2i(col, row)):
		return ""
	var obj = _objects[row][col]
	return obj if obj != null else ""

func set_object(col: int, row: int, object_id: Variant) -> void:
	if not in_bounds(Vector2i(col, row)):
		return
	_objects[row][col] = object_id

# --- Tag system ---

func get_tags(col: int, row: int) -> Dictionary:
	var tags = {}
	if not in_bounds(Vector2i(col, row)):
		return tags
	# Terrain tags
	var t = _ground[row][col]
	var tdef = terrains_data.get(t, {})
	for tag in tdef.get("tags", []):
		tags[tag] = true
	# Effect tags
	for eff in _effects[row][col]:
		var edef = effects_data.get(eff.type, {})
		for tag in edef.get("tags", []):
			tags[tag] = true
	# Object tags
	var obj = _objects[row][col]
	if obj != null:
		var odef = objects_data.get(obj, {})
		for tag in odef.get("tags", []):
			tags[tag] = true
	for tag in _removed_tags.get(Vector2i(col, row), {}):
		tags.erase(tag)
	return tags

func has_tag(col: int, row: int, tag: String) -> bool:
	if not in_bounds(Vector2i(col, row)):
		return false
	return get_tags(col, row).get(tag, false)

func remove_tag(col: int, row: int, tag: String) -> void:
	if not in_bounds(Vector2i(col, row)) or tag == "":
		return
	var key = Vector2i(col, row)
	if not _removed_tags.has(key):
		_removed_tags[key] = {}
	_removed_tags[key][tag] = true
