# 战术说明弹层沿用战斗模态栈，内部以容器布局；没有战斗状态写入入口。
extends PanelContainer
signal close_requested
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
var _body: RichTextLabel
var _close: Button

func _ready() -> void:
	Kit.init()
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel",Kit.tokens.surface_style())
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,28)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",18)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "战术一览"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font",Kit.font)
	title.add_theme_font_size_override("font_size",30)
	header.add_child(title)
	_close = Kit.button(header,"返回战斗 · T / Esc",Rect2(0,0,280,62),func(): close_requested.emit())
	_close.custom_minimum_size=Vector2(280,62)
	_body=RichTextLabel.new()
	_body.bbcode_enabled=false
	_body.selection_enabled=true
	_body.focus_mode=Control.FOCUS_ALL
	_body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_body.add_theme_font_override("normal_font",Kit.font)
	_body.add_theme_font_size_override("normal_font_size",23)
	_body.add_theme_color_override("default_color",Kit.color("ui_text"))
	_body.add_theme_constant_override("line_separation",7)
	column.add_child(_body)
	_close.focus_next=_body.get_path()
	_body.focus_next=_close.get_path()
	_close.focus_previous=_body.get_path()
	_body.focus_previous=_close.get_path()
	_body.gui_input.connect(_scroll_keys)

func present(text: String) -> void:
	_body.text=text
	_body.scroll_to_line(0)
	show()

func _scroll_keys(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed: return
	var bar := _body.get_v_scroll_bar()
	match event.keycode:
		KEY_DOWN: bar.value+=42
		KEY_UP: bar.value-=42
		KEY_PAGEDOWN: bar.value+=bar.page*.85
		KEY_PAGEUP: bar.value-=bar.page*.85
		KEY_HOME: bar.value=bar.min_value
		KEY_END: bar.value=bar.max_value
		_: return
	accept_event()
