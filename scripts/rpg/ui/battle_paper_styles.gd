extends RefCounted
## 和纸源PNG只读；Atlas裁切像素副本仅覆盖逻辑尺寸，不重采样、不保存新像素。

const TARGET_BORDER := 12.0
const SOURCES := {
	"leaf": {
		"path": "res://assets/ui/battle_washi_20261020/leaf-candidate.png",
		"declared_source_dimensions": Vector2i(2048, 768),
		"region": Rect2(40, 84, 1968, 592),
		"requested_source_borders": Vector2i(46, 37),
		"override": Vector2i(512, 192),
	},
	"summary": {
		"path": "res://assets/ui/battle_washi_20261020/summary-candidate.png",
		"declared_source_dimensions": Vector2i(2172, 724),
		"region": Rect2(24, 202, 2124, 316),
		"requested_source_borders": Vector2i(33, 40),
		"override": Vector2i(768, 96),
	},
}

static var _textures: Dictionary = {}
static var _source_dimensions: Dictionary = {}

static func style(kind: String = "leaf") -> StyleBoxTexture:
	var result := StyleBoxTexture.new()
	result.texture = _texture(kind)
	if result.texture == null: return null
	result.set_texture_margin_all(TARGET_BORDER)
	result.set_content_margin_all(TARGET_BORDER)
	return result

static func _texture(kind: String) -> Texture2D:
	if _textures.has(kind): return _textures[kind]
	if not SOURCES.has(kind):
		push_error("Unknown candidate paper kind: " + kind)
		return null
	var spec: Dictionary = SOURCES[kind]
	var source := Image.load_from_file(spec.path)
	if source == null or source.is_empty():
		push_error("Cannot read candidate paper: " + str(spec.path))
		return null
	_source_dimensions[kind] = Vector2i(source.get_width(), source.get_height())
	var atlas := AtlasTexture.new()
	atlas.atlas = ImageTexture.create_from_image(source)
	atlas.region = spec.region
	# Atlas只取得原裁切区的像素副本，源PNG保持原样。
	var copy: Image = atlas.get_image()
	if copy == null or copy.is_empty():
		push_error("Cannot extract candidate paper region: " + kind)
		return null
	var normalized := ImageTexture.create_from_image(copy)
	# 仅覆盖纹理逻辑尺寸；不调用Image.resize或保存派生位图。
	normalized.set_size_override(spec.override)
	_textures[kind] = normalized
	return normalized

static func metadata() -> Dictionary:
	var result := {}
	for kind in ["leaf", "summary"]:
		var spec: Dictionary = SOURCES[kind]
		var texture := _texture(kind)
		var region: Rect2 = spec.region
		var logical_size: Vector2i = spec.override
		result[kind] = {
			"source_path": spec.path,
			"source_sha256": FileAccess.get_sha256(spec.path),
			"source_dimensions": _source_dimensions.get(kind, Vector2i.ZERO),
			"declared_source_dimensions": spec.declared_source_dimensions,
			"region": region,
			"requested_source_borders": spec.requested_source_borders,
			"override": logical_size,
			"actual_mapped_source_cut": Vector2(TARGET_BORDER * region.size.x / logical_size.x, TARGET_BORDER * region.size.y / logical_size.y),
			"border_axes": "left/right=x; top/bottom=y",
			"declared_target_border": TARGET_BORDER,
			"declared_content_margin": TARGET_BORDER,
			"derived_memory_copy": true,
			"no_source_change": true,
			"no_resample": true,
			"loaded": texture != null,
		}
	return result

static func focus_style() -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = Color.TRANSPARENT
	result.border_color = Color("A64234")
	result.set_border_width_all(3)
	result.set_expand_margin_all(2.0)
	return result
