# 标题屏:蒸汽朋克+国风道教风格,与战斗 HUD 同一套素材语言
# 背景整幅 title_bg(暗化保可读)+ 八卦徽章 + 大字标题 + 九图菜单按钮
extends Node2D

const TITLE_BG := "res://assets/ui/steampunk/title_bg.png"
const TITLE_EMBLEM := "res://assets/ui/steampunk/title_emblem.png"
const MENU_BUTTON := "res://assets/ui/steampunk/ui_menu_button.png"
const FONT_BOLD := "res://assets/fonts/Alibaba-PuHuiTi-Bold.ttf"
const FONT_REGULAR := "res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf"

# 与战斗 HUD 一致的色板(符黄/暗金/玄黑)
const COLOR_TALISMAN := Color(0.93, 0.78, 0.42, 1.0)
const COLOR_GOLD_BRIGHT := Color(1.0, 0.88, 0.55, 1.0)
const COLOR_TEXT_WARM := Color(0.88, 0.85, 0.82, 1.0)
const COLOR_TEXT_MUTED := Color(0.72, 0.66, 0.55, 1.0)
const COLOR_OUTLINE := Color(0.10, 0.05, 0.02, 1.0)

var _ui_root: Control
var _emblem: TextureRect
var _title: Label
var _subtitle: Label
var _enter_btn: Button
var _click_label: Label
var _elapsed := 0.0


func _ready() -> void:
	# 预加载卡牌/单位/状态数据(进入战斗前必须)
	Card.load_cards()
	UnitFactory.load_templates()
	StatusEffectManager.load_defs()
	_build_title_ui()
	get_viewport().size_changed.connect(_layout_title_screen)
	_layout_title_screen()


func _build_title_ui() -> void:
	_ui_root = Control.new()
	_ui_root.name = "TitleUI"
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui_root)

	# 背景整幅,轻微暗化保证前景可读
	var bg := TextureRect.new()
	bg.name = "Background"
	bg.texture = load(TITLE_BG)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = Color(0.88, 0.86, 0.84, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(bg)
	# 全局压暗罩
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.24)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(dim)

	# 八卦徽章
	_emblem = TextureRect.new()
	_emblem.texture = load(TITLE_EMBLEM)
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_emblem.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_emblem)

	# 主标题:符黄大字 + 玄黑描边阴影
	_title = Label.new()
	_title.text = "封灵事务所"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", load(FONT_BOLD))
	_title.add_theme_font_size_override("font_size", 96)
	_title.add_theme_color_override("font_color", COLOR_TALISMAN)
	_title.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	_title.add_theme_constant_override("outline_size", 10)
	_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	_title.add_theme_constant_override("shadow_offset_x", 4)
	_title.add_theme_constant_override("shadow_offset_y", 4)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_title)

	# 副标题
	_subtitle = Label.new()
	_subtitle.text = "S.S.Agency · 港式民俗规则模拟器"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_override("font", load(FONT_REGULAR))
	_subtitle.add_theme_font_size_override("font_size", 22)
	_subtitle.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	_subtitle.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_subtitle.add_theme_constant_override("outline_size", 4)
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_subtitle)

	# 进入按钮:九图黄铜按钮贴图
	_enter_btn = Button.new()
	_enter_btn.text = "进 入 事 务 所"
	_enter_btn.add_theme_font_override("font", load(FONT_BOLD))
	_enter_btn.add_theme_font_size_override("font_size", 28)
	_enter_btn.add_theme_color_override("font_color", COLOR_TEXT_WARM)
	_enter_btn.add_theme_color_override("font_hover_color", COLOR_GOLD_BRIGHT)
	_enter_btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.96, 0.78))
	_enter_btn.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	_enter_btn.add_theme_constant_override("outline_size", 6)
	_enter_btn.add_theme_stylebox_override("normal", _make_menu_button_style(Color(1.0, 1.0, 1.0, 0.96)))
	_enter_btn.add_theme_stylebox_override("hover", _make_menu_button_style(Color(1.15, 1.10, 1.0, 1.0)))
	_enter_btn.add_theme_stylebox_override("pressed", _make_menu_button_style(Color(0.85, 0.82, 0.78, 1.0)))
	_enter_btn.add_theme_stylebox_override("focus", _make_menu_button_style(Color(1.0, 1.0, 1.0, 0.0)))
	_enter_btn.pressed.connect(start_battle)
	_ui_root.add_child(_enter_btn)

	# 底部提示(呼吸闪烁)
	_click_label = Label.new()
	_click_label.text = "- 点击任意处继续 -"
	_click_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_click_label.add_theme_font_override("font", load(FONT_REGULAR))
	_click_label.add_theme_font_size_override("font_size", 16)
	_click_label.add_theme_color_override("font_color", Color(0.80, 0.74, 0.62, 1.0))
	_click_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_click_label)


# 菜单按钮九图样式:ui_menu_button 512x125,两端饰件约 110px,上下边条约 22px
func _make_menu_button_style(modulate: Color) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(MENU_BUTTON)
	style.texture_margin_left = 110
	style.texture_margin_top = 22
	style.texture_margin_right = 110
	style.texture_margin_bottom = 22
	style.modulate_color = modulate
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _layout_title_screen() -> void:
	var view_size := get_viewport_rect().size
	_ui_root.size = view_size
	for child in _ui_root.get_children():
		if child is TextureRect and child.name == "Background":
			child.size = view_size
		elif child is ColorRect:
			child.size = view_size
	var cx := view_size.x * 0.5
	# 徽章:顶部 8% 起,占高约 22%
	var emblem_size := view_size.y * 0.24
	_emblem.position = Vector2(cx - emblem_size * 0.5, view_size.y * 0.07)
	_emblem.size = Vector2(emblem_size, emblem_size)
	# 主标题:徽章下方
	_title.position = Vector2(cx - 400.0, view_size.y * 0.07 + emblem_size + 8.0)
	_title.size = Vector2(800, 120)
	# 副标题
	_subtitle.position = Vector2(cx - 300.0, _title.position.y + 118.0)
	_subtitle.size = Vector2(600, 32)
	# 进入按钮:屏幕 68% 高度
	_enter_btn.position = Vector2(cx - 170.0, view_size.y * 0.68)
	_enter_btn.size = Vector2(340, 96)
	# 底部提示
	_click_label.position = Vector2(cx - 200.0, view_size.y * 0.90)
	_click_label.size = Vector2(400, 26)


func _process(delta: float) -> void:
	_elapsed += delta
	if _click_label != null:
		_click_label.modulate.a = 0.70 + 0.30 * sin(_elapsed * 2.2)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		start_battle()


func start_battle() -> void:
	var battle = load("res://scenes/battle.tscn").instantiate()
	get_tree().root.add_child(battle)
	get_tree().current_scene = battle
	queue_free()
