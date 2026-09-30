class_name TileMapV2
extends RefCounted
## 图块地图逻辑层 v2 —— 支持 64×64 及以上大地图
##
## 职责：
##   - 加载 map JSON（ground 字符行 + objects 物件表）
##   - 逻辑查询：is_walkable（含门/敌人占位阻挡）、tile_at、物件查询
##   - 构建 Godot TileMap 渲染节点（运行时从 atlas 建 TileSet，NEAREST 像素风）
##
## 地图玩法由 explore_scene 驱动（移动/互动/拾取/遇敌/传送），本类只管数据与查询。

const TILE := 32

var map_id: String = ""
var width: int = 0
var height: int = 0
var ground: Array = []  # Array of String（字符行）
var legend: Dictionary = {}  # 字符 → 图块名
var objects: Array = []  # 原始物件列表
var player_start := Vector2i.ZERO

# 物件索引（运行时状态）
var _by_tile: Dictionary = {}  # Vector2i → object dict（多个物件同格时后写覆盖，生成器保证不重叠）
var doors: Dictionary = {}  # Vector2i → door object（requires_flag）
var portal: Dictionary = {}  # Vector2i → portal object


func load_map(path: String) -> bool:
	var data = JsonLoader.load_file(path)
	if not (data is Dictionary) or not data.has("ground"):
		push_error("TileMapV2: map load failed " + path)
		return false
	map_id = str(data.get("id", ""))
	width = int(data.get("width", 0))
	height = int(data.get("height", 0))
	ground = data.get("ground", [])
	legend = data.get("legend", {})
	objects = data.get("objects", [])
	var ps = data.get("player_start", [1, 1])
	player_start = Vector2i(int(ps[0]), int(ps[1]))

	# 建物件索引
	_by_tile.clear()
	doors.clear()
	portal.clear()
	for obj in objects:
		if not (obj is Dictionary):
			continue
		var t = obj.get("tile", [0, 0])
		var key = Vector2i(int(t[0]), int(t[1]))
		_by_tile[key] = obj
		match str(obj.get("type", "")):
			"door":
				doors[key] = obj
			"portal":
				portal[key] = obj
	return width > 0 and height > 0 and ground.size() == height


func char_at(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= width or y >= height or y >= ground.size():
		return "#"
	var row = ground[y]
	if x >= row.length():
		return "#"
	return row[x]


func tile_name_at(x: int, y: int) -> String:
	return str(legend.get(char_at(x, y), "wall"))


## 门是否已解锁（由 NarrativeState 旗标决定）
func is_door_open(x: int, y: int) -> bool:
	var key = Vector2i(x, y)
	if not doors.has(key):
		return true
	var req = str(doors[key].get("requires_flag", ""))
	return req.is_empty() or NarrativeState.has_flag(req)


## 该格是否被未击败的敌人占据
func is_enemy_at(x: int, y: int) -> bool:
	var key = Vector2i(x, y)
	if not _by_tile.has(key):
		return false
	var obj = _by_tile[key]
	if str(obj.get("type", "")) != "enemy":
		return false
	var flag = str(obj.get("on_defeat_flag", ""))
	return flag.is_empty() or not NarrativeState.has_flag(flag)


## 核心查询：能否走入该格（地图玩法的基础规则）
## 阻挡：墙/虚空/坑 | 未解锁的门 | 存活敌人
func is_walkable(x: int, y: int) -> bool:
	var t = tile_name_at(x, y)
	if t == "wall" or t == "void" or t == "pit":
		return false
	if not is_door_open(x, y):
		return false
	if is_enemy_at(x, y):
		return false
	return true


func get_object_at(x: int, y: int) -> Dictionary:
	return _by_tile.get(Vector2i(x, y), {})


func remove_object(obj_id: String) -> void:
	for i in range(objects.size()):
		if str(objects[i].get("id", "")) == obj_id:
			var t = objects[i].get("tile", [0, 0])
			objects.remove_at(i)
			_by_tile.erase(Vector2i(int(t[0]), int(t[1])))
			return


## 敌人被击败：从索引移除（旗标由调用方写入 NarrativeState）
func defeat_enemy_at(x: int, y: int) -> String:
	var obj = get_object_at(x, y)
	if obj.is_empty() or str(obj.get("type", "")) != "enemy":
		return ""
	var flag = str(obj.get("on_defeat_flag", ""))
	remove_object(str(obj.get("id", "")))
	return flag


# ===== 渲染 =====

## 构建并返回 TileMap 节点（由 explore_scene add_child）
func build_tilemap_node() -> TileMap:
	var atlas_path = AssetRegistry.get_tileset_atlas_path()
	if atlas_path.is_empty() or not ResourceLoader.exists(atlas_path):
		push_error("TileMapV2: tileset atlas missing " + atlas_path)
		return null
	var tex: Texture2D = load(atlas_path)

	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(TILE, TILE)
	# 为每个图块名注册 atlas tile
	for tile_name in legend.values():
		var coords := AssetRegistry.get_tile_atlas_coords(tile_name)
		if not src.has_tile(coords):
			src.create_tile(coords)

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)

	var tm := TileMap.new()
	tm.name = "TileMapV2"
	tm.tile_set = ts
	tm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tm.z_index = 0

	# 填格子（Godot 4.6 set_cell 签名：layer, coords, source_id, atlas_coords）
	for y in range(height):
		var row: String = ground[y]
		for x in range(min(row.length(), width)):
			var tile_name = str(legend.get(row[x], "wall"))
			var coords := AssetRegistry.get_tile_atlas_coords(tile_name)
			tm.set_cell(0, Vector2i(x, y), 0, coords)
	return tm


# ===== 坐标换算 =====

func tile_to_world_center(x: int, y: int) -> Vector2:
	return Vector2(x * TILE + TILE * 0.5, y * TILE + TILE * 0.5)


func tile_to_world_feet(x: int, y: int) -> Vector2:
	return Vector2(x * TILE + TILE * 0.5, (y + 1) * TILE)


func world_to_tile(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / TILE)), int(floor(world_pos.y / TILE)))


func map_pixel_size() -> Vector2:
	return Vector2(width * TILE, height * TILE)
