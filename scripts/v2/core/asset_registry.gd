class_name AssetRegistry
extends RefCounted
## 资产注册表 v2 —— 素材切割"投入系统"的运行时端
##
## 读取 tools/build_asset_pipeline.py 产出的 data/v2/asset_manifest.json，
## 所有资产通过 manifest 的 key 引用（如 "tiles/wall"、"ui9/panel_main"），
## 告别硬编码路径。get_texture 自动加载并缓存。

static var _manifest: Dictionary = {}
static var _loaded: bool = false
static var _texture_cache: Dictionary = {}

const MANIFEST_PATH := "res://data/v2/asset_manifest.json"


static func load_manifest(force: bool = false) -> Dictionary:
	if _loaded and not force:
		return _manifest
	_loaded = true
	_manifest.clear()
	var data = JsonLoader.load_file(MANIFEST_PATH)
	if not (data is Dictionary):
		push_error("AssetRegistry: manifest not found " + MANIFEST_PATH)
		return _manifest
	_manifest = data
	return _manifest


## 通过扁平 key 取资源路径："tiles/wall" → manifest["tiles"]["wall"]
static func get_path(key: String) -> String:
	load_manifest()
	var parts = key.split("/", false, 1)
	if parts.size() != 2:
		push_error("AssetRegistry: bad key " + key)
		return ""
	var section = _manifest.get(parts[0], {})
	if not (section is Dictionary):
		return ""
	return str(section.get(parts[1], ""))


static func has(key: String) -> bool:
	return not get_path(key).is_empty()


static func get_texture(key: String) -> Texture2D:
	if _texture_cache.has(key):
		return _texture_cache[key]
	var p = get_path(key)
	if p.is_empty() or not ResourceLoader.exists(p):
		return null
	var tex = load(p)
	if tex is Texture2D:
		_texture_cache[key] = tex
	return tex


## 取图块集 atlas 坐标（地图 legend 字符 → 图集格子）
static func get_tile_atlas_coords(tile_name: String) -> Vector2i:
	load_manifest()
	var coords = _manifest.get("tile_atlas_coords", {}).get(tile_name, [0, 0])
	return Vector2i(int(coords[0]), int(coords[1]))


static func get_tileset_atlas_path() -> String:
	load_manifest()
	return str(_manifest.get("tileset_atlas", ""))
