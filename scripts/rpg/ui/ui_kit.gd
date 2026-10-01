# 和纸/墨色工具与固定3D镜头，只有表现职责。
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
		style = box(Color(color("ink_900"), 0.91), Color(color("gold_500"), 0.5))
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
	node.add_theme_color_override("font_color", color("ink_900" if dark else "paper_100"))
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
	node.add_theme_color_override("default_color", color("paper_100"))
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
	node.add_theme_font_size_override("font_size", 26)
	node.add_theme_color_override("font_color", color("paper_100"))
	node.add_theme_color_override("font_disabled_color", Color(color("paper_300"), 0.6))
	node.add_theme_stylebox_override("normal", box(Color(color("vermilion_500") if primary else color("ink_900"), 0.92), color("gold_500")))
	node.add_theme_stylebox_override("hover", box(Color(color("gold_500"), 0.32), color("paper_100")))
	node.add_theme_stylebox_override("pressed", box(Color(color("vermilion_500"), 0.65), color("paper_100")))
	node.add_theme_stylebox_override("disabled", box(Color(color("ink_900"), 0.7), Color(color("paper_300"), 0.3)))
	if callback.is_valid(): node.pressed.connect(callback)
	parent.add_child(node)
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
	node.size = rect.size
	node.show_percentage = false
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_stylebox_override("background", box(Color(0.04, 0.04, 0.05, 0.8), Color(tint, 0.4)))
	node.add_theme_stylebox_override("fill", box(tint, tint))
	parent.add_child(node)
	return node

static func backdrop(parent: Node, config: Dictionary) -> void:
	image(parent, config.fallback_background, Rect2(0, 0, 1920, 1080))
	# 复用检查场景的3D模型/灯光，但移除检查输入与HUD；没有探索脚本。
	if not ResourceLoader.exists(config.backdrop_scene): return
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

static func actor_sprite(parent: Node, art: String, height: float, flip: bool) -> Node2D:
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
			sprite.scale = Vector2.ONE * height / float(texture.get_height())
			sprite.offset.y = -float(texture.get_height()) / 2.0
			sprite.flip_h = flip
		root.add_child(sprite)
	return root

static func flip_for(source_facing: String, toward_right: bool) -> bool:
	return (source_facing == "left" and toward_right) or (source_facing == "right" and not toward_right)

static func face_actor(actor: Node2D, toward_right: bool) -> void:
	var flipped := flip_for(actor.get_meta("source_facing", "right"), toward_right)
	actor.set_meta("facing_right", toward_right)
	for child in actor.get_children():
		if child is Sprite2D or child is AnimatedSprite2D: child.flip_h = flipped
