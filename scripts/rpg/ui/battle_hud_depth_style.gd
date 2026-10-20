extends RefCounted
## 紧凑HUD凹槽量条与清晰数值描边。
## Preload this script; no scene ownership, signals, or per-frame processing.

const _GAUGE_META := &"_hud_depth_v4_gauge_signature"
const _CACHE_LIMIT := 64
static var _texture_cache: Dictionary = {}


static func style_gauge(gauge: TextureProgressBar, rect: Rect2, tint: Color) -> void:
	if not is_instance_valid(gauge):
		return
	# Includes the one-pixel lower/right shadow. Keep the original centre line.
	var width := maxi(6, roundi(rect.size.x))
	var height := clampi(roundi(rect.size.y), 8, 10)
	var signature := "%dx%d:%s" % [width, height, tint.to_html(true)]
	if gauge.get_meta(_GAUGE_META, "") != signature:
		var textures: Array[Texture2D] = _gauge_textures(signature, width, height, tint)
		gauge.texture_under = textures[0]
		gauge.texture_progress = textures[1]
		gauge.texture_over = textures[2]
		# Tint is baked into the fill so the border/track stay dark at any value.
		gauge.tint_under = Color.WHITE
		gauge.tint_progress = Color.WHITE
		gauge.tint_over = Color.WHITE
		gauge.nine_patch_stretch = false
		gauge.texture_progress_offset = Vector2.ZERO
		gauge.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gauge.set_meta(_GAUGE_META, signature)
	# Geometry can move even when the shared texture signature stays the same.
	gauge.position = rect.position + Vector2(0.0, (rect.size.y - float(height)) * 0.5)
	gauge.size = Vector2(width, height)
	# Range.value/max_value/min_value/step and fill_mode are deliberately untouched.


static func style_number(label: Label, transient: bool = false) -> void:
	if not is_instance_valid(label):
		return
	# Keep the caller's font, size and semantic colour (damage/heal/HP/MP).
	# Apply after plain-label styling, which otherwise replaces outline settings.
	label.add_theme_color_override("font_outline_color", Color(0.025, 0.035, 0.04, 0.97))
	label.add_theme_color_override("font_shadow_color", Color(0.015, 0.025, 0.03, 0.78 if transient else 0.68))
	label.add_theme_constant_override("outline_size", 2 if transient else 1)
	label.add_theme_constant_override("shadow_offset_x", 2 if transient else 1)
	label.add_theme_constant_override("shadow_offset_y", 2 if transient else 1)
	label.add_theme_constant_override("shadow_outline_size", 1 if transient else 0)


static func _gauge_textures(signature: String, width: int, height: int, tint: Color) -> Array[Texture2D]:
	if _texture_cache.has(signature):
		return _texture_cache[signature]
	# Bound resize/colour experiments. Existing gauges retain their own textures.
	if _texture_cache.size() >= _CACHE_LIMIT:
		_texture_cache.clear()
	var under := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var fill := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var over := Image.create(width, height, false, Image.FORMAT_RGBA8)
	under.fill(Color.TRANSPARENT)
	fill.fill(Color.TRANSPARENT)
	over.fill(Color.TRANSPARENT)

	# The frame uses all but the final row/column; its shadow sits down/right.
	var frame_width := width - 1
	var frame_height := height - 1
	under.fill_rect(Rect2i(1, 1, frame_width, frame_height), Color(0.015, 0.022, 0.026, 0.52))
	under.fill_rect(Rect2i(0, 0, frame_width, frame_height), Color(0.035, 0.046, 0.052, 0.96))
	var track := Color(0.075, 0.095, 0.102, 0.94).lerp(Color(tint.r, tint.g, tint.b, 0.94), 0.08)
	under.fill_rect(Rect2i(1, 1, frame_width - 2, frame_height - 2), track)
	under.fill_rect(Rect2i(1, 1, frame_width - 2, 1), Color(0.025, 0.035, 0.04, 0.93))

	# Short vertical bands make a soft upper edge and a restrained lower bevel.
	# No white stripe or broad specular reflection: the material stays matte.
	var inner_height := frame_height - 2
	for row in inner_height:
		var row_color := tint
		if row == 0:
			row_color = tint.darkened(0.23)
		elif row == 1:
			row_color = tint.lightened(0.16)
		else:
			var lower_fraction := float(row - 2) / float(maxi(1, inner_height - 3))
			row_color = tint.darkened(lerpf(0.015, 0.22, lower_fraction))
		fill.fill_rect(Rect2i(1, row + 1, frame_width - 2, 1), row_color)

	# This unfilled ring remains crisp at both zero and full gauge values.
	var rim := Color(0.025, 0.033, 0.037, 0.98)
	over.fill_rect(Rect2i(0, 0, frame_width, 1), rim)
	over.fill_rect(Rect2i(0, frame_height - 1, frame_width, 1), rim)
	over.fill_rect(Rect2i(0, 1, 1, frame_height - 2), rim)
	over.fill_rect(Rect2i(frame_width - 1, 1, 1, frame_height - 2), rim)
	over.fill_rect(Rect2i(1, 0, frame_width - 2, 1), Color(0.24, 0.28, 0.28, 0.58))

	var textures: Array[Texture2D] = [
		ImageTexture.create_from_image(under),
		ImageTexture.create_from_image(fill),
		ImageTexture.create_from_image(over),
	]
	_texture_cache[signature] = textures
	return textures
