# 烟墨/灰绿/暗朱的共用UI工具与固定3D镜头，只有表现职责。
class_name RpgUiKit
extends RefCounted
const ThemeData = preload("res://scripts/ui/theme.gd")
const Png = preload("res://scripts/ui/png_loader.gd")
static var tokens: RefCounted
static var font: Font

static func init() -> void:
	if tokens == null: tokens = ThemeData.load_theme()
	if font == null: font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")

static func color(id: String) -> Color:
	init()
	return tokens.color(id)

static func panel(parent: Node, rect: Rect2, paper: bool = false) -> Panel:
	init()
	var node := Panel.new()
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBox
	if paper:
		style = tokens.washi_panel().duplicate()
		style.set_content_margin_all(18)
	else:
		style = tokens.surface_style()
	node.add_theme_stylebox_override("panel", style)
	parent.add_child(node)
	return node

static func box(background: Color, border: Color) -> StyleBoxFlat:
	var value := StyleBoxFlat.new()
	value.bg_color = background
	value.border_color = border
	value.set_border_width_all(2)
	value.set_corner_radius_all(4)
	value.set_content_margin_all(10)
	return value

static func label(parent: Node, text: String, rect: Rect2, font_size: int = 26, dark: bool = false) -> Label:
	init()
	var node := Label.new()
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_override("font", font)
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color("ink_900" if dark else "ui_text"))
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

# 状态/数值保持卡片内边界，多状态可滚动且悬停仍显示全文。
static func scroll_text(parent: Node, rect: Rect2, font_size: int = 23) -> RichTextLabel:
	init()
	var node := RichTextLabel.new()
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_override("normal_font", font)
	node.add_theme_font_size_override("normal_font_size", font_size)
	node.add_theme_color_override("default_color", color("ui_text"))
	node.scroll_active = true
	node.clip_contents = true
	parent.add_child(node)
	return node

static func button(parent: Node, text: String, rect: Rect2, callback: Callable = Callable(), primary: bool = false) -> Button:
	init()
	var node := Button.new()
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_override("font", font)
	node.add_theme_font_size_override("font_size", 24)
	node.add_theme_color_override("font_color", color("ui_text"))
	node.add_theme_color_override("font_hover_color", color("ui_text"))
	node.add_theme_color_override("font_pressed_color", color("ui_text"))
	node.add_theme_color_override("font_focus_color", color("ui_text"))
	node.add_theme_color_override("font_disabled_color", color("ui_disabled_text"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		node.add_theme_stylebox_override(state, tokens.button_style(state, primary))
	node.set_meta("ui_primary", primary)
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if callback.is_valid(): node.pressed.connect(callback)
	parent.add_child(node)
	return node

# 选择是表现状态，不使用toggle_mode改变原输入/提交机制。
static func set_selected(node: Button, selected: bool) -> void:
	if node.get_meta("ui_selected", false) == selected: return
	node.set_meta("ui_selected", selected)
	var style: StyleBoxFlat = tokens.button_style("normal", node.get_meta("ui_primary", false))
	if selected:
		style.bg_color = color("ui_selected")
		style.border_color = color("ui_selected_line")
		style.border_width_left = 3
	node.add_theme_stylebox_override("normal", style)

static func quiet_button(node: Button) -> void:
	var style: StyleBoxFlat = tokens.button_style("normal")
	style.bg_color = Color(color("ui_ink"), 0.94)
	style.set_border_width_all(0)
	node.add_theme_stylebox_override("normal", style)
	node.add_theme_color_override("font_color", color("ui_muted"))


static func muted(node: Label) -> Label:
	node.add_theme_color_override("font_color", color("ui_muted"))
	return node

static func image(parent: Node, path: String, rect: Rect2) -> TextureRect:
	var node := TextureRect.new()
	node.position = rect.position
	node.size = rect.size
	node.texture = Png.load_texture(path)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

static func bar(parent: Node, rect: Rect2, tint: Color) -> ProgressBar:
	var node := ProgressBar.new()
	node.position = rect.position
	node.show_percentage = false
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 血条不可复用按钮的内容边距，否则Godot会把细条撑成厚块并压住数值。
	var background := StyleBoxFlat.new()
	background.bg_color = color("ui_pressed")
	background.set_content_margin_all(0)
	background.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = tint
	fill.set_content_margin_all(0)
	fill.set_corner_radius_all(2)
	node.add_theme_stylebox_override("background", background)
	node.add_theme_stylebox_override("fill", fill)
	parent.add_child(node)
	node.size = rect.size
	return node

static func config_for_night(config: Dictionary, night: int) -> Dictionary:
	var value := config.duplicate(true)
	var background: String = value.get("night_backgrounds", {}).get(str(night), "")
	if not background.is_empty():
		value.fallback_background = background
		# 正式各夜使用各自已保留背景，不能让参道预览盖住第二至五夜。
		value.backdrop_scene = ""
	return value

static func backdrop(parent: Node, config: Dictionary) -> void:
	image(parent, config.fallback_background, Rect2(0, 0, 1920, 1080))
	# 复用检查场景的3D模型/灯光，但移除检查输入与HUD；没有探索脚本。
	if str(config.get("backdrop_scene", "")).is_empty() or not ResourceLoader.exists(config.backdrop_scene): return
	var packed: PackedScene = load(config.backdrop_scene)
	if packed == null: return
	var world: Node3D = packed.instantiate()
	world.set_script(null)
	for path in ["PreviewHUD", "CharacterReference"]:
		var child := world.get_node_or_null(path)
		if child != null: child.free()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	parent.add_child(viewport)
	viewport.add_child(world)
	var camera: Camera3D = world.get_node("Cameras/Hero")
	var aim: Array = config.get("camera_target", [0.6, 0.8, 0.0])
	camera.look_at(Vector3(aim[0], aim[1], aim[2]))
	camera.current = true
	var screen := TextureRect.new()
	screen.texture = viewport.get_texture()
	screen.size = Vector2(1920, 1080)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(screen)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.035, 0.07, 0.24)
	shade.size = Vector2(1920, 1080)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(shade)

static func actor_sprite(parent: Node, art: String, height: float, flip: bool, geometry: Dictionary = {}) -> Node2D:
	var root := Node2D.new()
	parent.add_child(root)
	if art == "rinne":
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/chars/rinne_25d/animation_manifest.json"))
		var frames := SpriteFrames.new()
		frames.remove_animation("default")
		for anim in ["idle", "attack"]:
			frames.add_animation(anim)
			frames.set_animation_speed(anim, 1.0)
			var definition: Dictionary = manifest.anims[anim]
			frames.set_animation_loop(anim, anim == "idle")
			var names: Array = definition.frames.duplicate()
			var times: Array = definition.durations_ms.duplicate()
			if anim == "idle" and definition.get("pingpong", false):
				for index in range(names.size() - 2, 0, -1):
					names.append(definition.frames[index])
					times.append(definition.durations_ms[index])
			for index in range(names.size()): frames.add_frame(anim, Png.load_texture("res://assets/chars/rinne_25d/frames/" + names[index] + ".png"), float(times[index]) / 1000.0)
		var sprite := AnimatedSprite2D.new()
		sprite.name = "Animated"
		sprite.sprite_frames = frames
		# 脚点[288,358]、内容高298，禁止按画布384缩放。
		var canvas: Dictionary = manifest.canvas
		sprite.offset = Vector2(float(canvas.w) / 2.0 - float(canvas.anchor[0]), float(canvas.h) / 2.0 - float(canvas.anchor[1]))
		sprite.scale = Vector2.ONE * height / float(canvas.content_height_px)
		sprite.flip_h = flip
		root.add_child(sprite)
		sprite.animation_finished.connect(func(): sprite.play("idle"))
		sprite.play("idle")
	else:
		var sprite := Sprite2D.new()
		var texture: Texture2D = Png.load_texture("res://assets/chars/hakuyo_idle.png" if art == "mint" else art)
		if texture != null:
			if art == "mint":
				# 归一透明画布留白；区域包含完整不透明主体，不修改源图。
				var atlas := AtlasTexture.new()
				atlas.atlas = texture
				atlas.region = Rect2(210, 0, 620, 1536)
				texture = atlas
			sprite.texture = texture
			sprite.set_meta("source_path", "res://assets/chars/hakuyo_idle.png" if art == "mint" else art)
			if geometry.is_empty():
				sprite.scale = Vector2.ONE * height / float(texture.get_height())
				sprite.offset.y = -float(texture.get_height()) / 2.0
			else:
				var anchor: Array = geometry.anchor
				sprite.scale = Vector2.ONE * height / float(geometry.content_height_px)
				sprite.set_meta("source_anchor", Vector2(anchor[0], anchor[1]))
				sprite.set_meta("canvas_size", texture.get_size())
				var anchor_x: float = texture.get_width() - anchor[0] if flip else anchor[0]
				sprite.offset = texture.get_size() / 2.0 - Vector2(anchor_x, anchor[1])
				sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			sprite.flip_h = flip
		root.add_child(sprite)
	return root

static func flip_for(source_facing: String, toward_right: bool) -> bool:
	return (source_facing == "left" and toward_right) or (source_facing == "right" and not toward_right)

static func face_actor(actor: Node2D, toward_right: bool) -> void:
	var flipped := flip_for(actor.get_meta("source_facing", "right"), toward_right)
	actor.set_meta("facing_right", toward_right)
	for child in actor.get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			child.flip_h = flipped
			if child.has_meta("source_anchor"):
				var anchor: Vector2 = child.get_meta("source_anchor")
				var canvas: Vector2 = child.get_meta("canvas_size")
				child.offset = canvas / 2.0 - Vector2(canvas.x - anchor.x if flipped else anchor.x, anchor.y)
