# 夜巡菜单只使用批准后的生图分层素材；文字与命中区由Godot保持清晰。
class_name NightMenuArt
extends RefCounted
const Png = preload("res://scripts/ui/png_loader.gd")
const ROOT := "res://assets/ui/night_menu/"
static var textures: Dictionary = {}
static func texture(id: String) -> Texture2D:
	if not textures.has(id):
		var original: Texture2D = Png.load_texture(ROOT + id + ".png")
		if original == null: return null
		# 生图原片保留高分辨率；在内存规范化九宫格边框尺寸，不重新绘制素材。
		var image := original.get_image()
		if id.begins_with("gauge_"):
			image.resize(512, 40, Image.INTERPOLATE_LANCZOS)
		elif id.begins_with("button"):
			image.resize(480, 72, Image.INTERPOLATE_LANCZOS)
		elif id in ["inset", "focus"]:
			image.resize(roundi(image.get_width() / 4.0), roundi(image.get_height() / 4.0), Image.INTERPOLATE_LANCZOS)
		elif id == "panel":
			image.resize(roundi(image.get_width() / 2.0), roundi(image.get_height() / 2.0), Image.INTERPOLATE_LANCZOS)
		textures[id] = ImageTexture.create_from_image(image)
	return textures[id]
static func style(id: String, margin: float = 24.0, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var value := StyleBoxTexture.new()
	value.texture = texture(id)
	value.texture_margin_left = margin
	value.texture_margin_top = 14 if id.begins_with("button") else margin
	value.texture_margin_right = margin
	value.texture_margin_bottom = 14 if id.begins_with("button") else margin
	value.modulate_color = tint
	if id == "focus": value.draw_center = false
	value.set_content_margin_all(12)
	return value
static func panel(parent: Node, rect: Rect2, inset: bool = false) -> Panel:
	var node := Panel.new()
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_stylebox_override("panel", style("inset" if inset else "panel", 12 if inset else 30))
	parent.add_child(node)
	return node
static func button(parent: Node, text: String, rect: Rect2, action: Callable = Callable(), primary: bool = false) -> Button:
	var node := Button.new()
	node.position = rect.position
	node.size = rect.size
	node.custom_minimum_size.y = 72
	node.text = text
	node.alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.clip_text = true
	node.add_theme_font_override("font", load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf"))
	node.add_theme_font_size_override("font_size", 23)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		node.add_theme_color_override(key, Color("f8edd5"))
	node.add_theme_color_override("font_disabled_color", Color("b6b6aa"))
	node.add_theme_constant_override("outline_size", 2)
	node.add_theme_color_override("font_outline_color", Color("111919"))
	var base := "button_primary" if primary else "button"
	node.add_theme_stylebox_override("normal", style(base))
	node.add_theme_stylebox_override("hover", style(base, 24, Color(1.2,1.16,1.08)))
	node.add_theme_stylebox_override("pressed", style("button_selected", 24, Color(0.88,0.88,0.88)))
	node.add_theme_stylebox_override("disabled", style("button_disabled"))
	node.add_theme_stylebox_override("focus", style("focus", 12))
	center_text(node)
	node.set_meta("art_primary", primary)
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if action.is_valid(): node.pressed.connect(action)
	parent.add_child(node)
	return node
static func selected(node: Button, value: bool) -> void:
	node.set_meta("ui_selected", value)
	var base := "button_selected" if value else ("button_primary" if node.get_meta("art_primary", false) else "button")
	node.add_theme_stylebox_override("normal", style(base))
	node.add_theme_stylebox_override("hover", style(base, 24, Color(1.15,1.12,1.05)))
	_apply_text_padding(node)
# 文字在自己的可读区域居中；图标、血蓝条和数值继续各用独立列。
static func center_text(node: Button, left: float = 24.0, right: float = 24.0, vertical: float = 20.0) -> void:
	node.alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.set_meta("art_text_padding", Vector3(left, right, vertical))
	_apply_text_padding(node)
# 文字左对齐（图标在左、名称随后），与 center_text 同一套内边距语义。
static func left_text(node: Button, left: float = 24.0, right: float = 24.0, vertical: float = 20.0) -> void:
	node.alignment = HORIZONTAL_ALIGNMENT_LEFT
	node.set_meta("art_text_padding", Vector3(left, right, vertical))
	_apply_text_padding(node)
static func _apply_text_padding(node: Button) -> void:
	var padding: Vector3 = node.get_meta("art_text_padding", Vector3(24, 24, 20))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var value: StyleBox = node.get_theme_stylebox(state).duplicate()
		value.content_margin_left = padding.x
		value.content_margin_right = padding.y
		value.content_margin_top = padding.z
		value.content_margin_bottom = padding.z
		node.add_theme_stylebox_override(state, value)

static func icon(parent: Node, id: String, rect: Rect2) -> TextureRect:
	var node := TextureRect.new()
	node.position = rect.position
	node.size = rect.size
	node.texture = texture(id)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

static func gauge(parent: Node, id: String, rect: Rect2) -> TextureProgressBar:
	var node := TextureProgressBar.new()
	node.position = rect.position
	node.nine_patch_stretch = true
	node.stretch_margin_left = 6
	node.stretch_margin_right = 6
	node.stretch_margin_top = 3
	node.stretch_margin_bottom = 3
	node.texture_under = texture("gauge_track")
	node.texture_progress = texture("gauge_" + id)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.size = rect.size
	parent.add_child(node)
	return node
