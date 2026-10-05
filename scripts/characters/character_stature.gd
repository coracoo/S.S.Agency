# 正式高清人物统一物理身高。只缩放原PNG，不裁图、不重画、不逐帧fit。
class_name CharacterStature
extends RefCounted
const CONFIG_PATH := "res://data/characters/stature.json"
static var _document: Dictionary = {}
static func _config() -> Dictionary:
	if _document.is_empty():
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if value is Dictionary and value.get("schema_version") == 1: _document = value
	return _document
static func height_cm(identity_id: String) -> float:
	return float(_config().get("identities", {}).get(identity_id, {}).get("height_cm", 0))
static func _profile(definition: Dictionary) -> Dictionary:
	var manifest: Dictionary = definition.get("manifest", {})
	var identity: String = manifest.get("identity_id", "")
	var form: String = manifest.get("form_id", "")
	var key := "homura_" + form if identity == "homura" else identity
	var profile: Dictionary = _config().get("forms", {}).get(key, {})
	# 旧低细节预览仍沿用原清单；不能把高清像素坐标套到别的画布。
	if profile.is_empty() or str(manifest.get("dir", "")) != str(profile.reference_frame).get_base_dir() + "/": return {}
	return profile
static func body_reference_pixels(definition: Dictionary) -> float:
	var profile := _profile(definition)
	if not profile.is_empty(): return float(profile.ground_y_px) - float(profile.crown_px[1])
	return float(definition.get("manifest", {}).get("canvas", {}).get("content_height_px", 0))
static func body_anchor(definition: Dictionary) -> Vector2:
	var canvas: Dictionary = definition.get("manifest", {}).get("canvas", {})
	var anchor: Array = canvas.get("anchor", [0, 0])
	var profile := _profile(definition)
	return Vector2(float(anchor[0]), float(profile.ground_y_px) if not profile.is_empty() else float(anchor[1]))
static func world_pixel_size(definition: Dictionary) -> float:
	var profile := _profile(definition)
	var canvas: Dictionary = definition.get("manifest", {}).get("canvas", {})
	var metres := height_cm(profile.identity_id) / 100.0 if not profile.is_empty() else float(canvas.get("height_m", 0))
	return metres / body_reference_pixels(definition) if body_reference_pixels(definition) > 0 else 0.0
static func battle_pixels_per_metre() -> float:
	return float(_config().get("battle", {}).get("pixels_per_metre", 190))
static func battle_ground_y() -> float:
	return float(_config().get("battle", {}).get("ground_y", 680))
static func battle_body_height(identity_id: String) -> float:
	return height_cm(identity_id) / 100.0 * battle_pixels_per_metre()
