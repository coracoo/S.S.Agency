# 新敌方静态立绘的原图与图集登记；原六敌资源继续用于原遭遇。
extends RefCounted
const PATH := "res://assets/chars/enemies/saga/asset_manifest.json"
const PNG = preload("res://scripts/ui/png_loader.gd")
static var _data: Dictionary = {}
static var _cache: Dictionary = {}
static func data() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(PATH):
		var decoded = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if decoded is Dictionary and decoded.get("schema_version") == 1 and decoded.get("enemies") is Dictionary: _data = decoded
	return _data
static func definition(enemy_id: String) -> Dictionary:
	if _cache.has(enemy_id): return _cache[enemy_id].duplicate(true)
	var entry: Dictionary = data().get("enemies", {}).get(enemy_id, {})
	if entry.is_empty(): return {}
	var path: String = str(entry.get("sheet", ""))
	if not path.begins_with("res://assets/chars/enemies/saga/") or not path.ends_with(".png"): return {"ok":false,"error":"敌方原图路径未登记：" + enemy_id}
	var texture: Texture2D = PNG.load_texture(path)
	if texture == null: return {"ok":false,"error":"敌方原图无法读取：" + enemy_id}
	var checked := validate_record(entry, texture.get_size())
	if not checked.is_empty(): return {"ok":false,"error":"；".join(checked)}
	var result := {"ok":true, "sheet":path, "speaker":str(entry.get("speaker", enemy_id)), "facing":str(entry.facing), "geometry":{"region":entry.region.duplicate(), "anchor":entry.anchor.duplicate(), "content_height_px":float(entry.content_height_px)}}
	_cache[enemy_id] = result
	return result.duplicate(true)
static func validate_record(entry: Dictionary, size: Vector2) -> Array[String]:
	var region = entry.get("region")
	var anchor = entry.get("anchor")
	if not region is Array or region.size() != 4 or not anchor is Array or anchor.size() != 2: return ["敌方图集取景/脚点格式非法"]
	for value in region:
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floorf(float(value)): return ["敌方取景必须为有限整数像素"]
	for value in anchor:
		if not (value is int or value is float) or not is_finite(float(value)): return ["敌方脚点必须为有限数值"]
	if region[2] <= 0 or region[3] <= 0 or not Rect2(Vector2.ZERO, size).encloses(Rect2(region[0],region[1],region[2],region[3])): return ["敌方取景超出原图"]
	if anchor[0] < 0 or anchor[0] > region[2] or anchor[1] <= 0 or anchor[1] > region[3]: return ["敌方局部脚点越界"]
	var height = entry.get("content_height_px")
	if not (height is int or height is float) or not is_finite(float(height)) or height <= 0 or height > region[3]: return ["敌方主体身高非法"]
	if not entry.get("facing") in ["left", "right"]: return ["敌方朝向未登记"]
	return []
