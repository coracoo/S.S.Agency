class_name CardView
extends Button
## 手牌卡牌视图 v2（改用 Button 派生，确保点击 100% 响应）
##
## 之前用 PanelContainer + _gui_input 的方案，子节点 mouse_filter 干扰导致点击不响应。
## 改用 Button：Godot Button 天然支持 pressed 信号，不会有 mouse_filter 坑。
## 卡面内容通过 add_child 加到 Button 内部。

signal clicked(index: int)

var _index: int = -1
var _card_def: Dictionary
var _selected: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(160, 220)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 9-slice 按钮三态主题（JSON 驱动）
	UIThemeFactoryV2.apply_button(self)
	# 用 pressed 信号（Button 原生）
	pressed.connect(_on_pressed)
	_build_layout()


func _build_layout() -> void:
	# 清掉默认文字（我们要用自定义内容）
	text = ""
	# 加一个 VBox 显示卡牌信息（覆盖在 Button 上）
	var vb = VBoxContainer.new()
	vb.name = "VBox"
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 4)
	add_child(vb)

	var cost_label = Label.new()
	cost_label.name = "CostLabel"
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_label.add_theme_font_size_override("font_size", 22)
	cost_label.add_theme_color_override("font_color", Color(0.76, 0.23, 0.23))
	vb.add_child(cost_label)

	var name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.721569, 0.52549, 0.043137, 1))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(name_label)

	var desc_label = RichTextLabel.new()
	desc_label.name = "DescLabel"
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_label.custom_minimum_size = Vector2(0, 100)
	desc_label.add_theme_font_size_override("normal_font_size", 13)
	desc_label.bbcode_enabled = true
	desc_label.fit_content = true
	vb.add_child(desc_label)

	# 保存引用到 metadata，_refresh 时取出来更新
	set_meta("cost_label", cost_label)
	set_meta("name_label", name_label)
	set_meta("desc_label", desc_label)


func setup(card_def: Dictionary, index: int = -1, selected: bool = false) -> void:
	_card_def = card_def
	_index = index
	_selected = selected
	call_deferred("_refresh")


func _refresh() -> void:
	if _card_def.is_empty():
		return
	# 子节点还没创建（_ready 未执行），推迟
	if not has_meta("cost_label"):
		call_deferred("_refresh")
		return
	var cost_label = get_meta("cost_label", null)
	var name_label = get_meta("name_label", null)
	var desc_label = get_meta("desc_label", null)
	if cost_label:
		cost_label.text = "● %d" % int(_card_def.get("cost", 0))
	if name_label:
		name_label.text = _card_def.get("name", "")
	if desc_label:
		desc_label.text = _card_def.get("description", "")
	modulate = Color(1.2, 1.2, 1.0) if _selected else Color.WHITE


func _on_pressed() -> void:
	DebugLog.info("CARD: pressed index=" + str(_index) + " card=" + str(_card_def.get("id", "")))
	clicked.emit(_index)


## 测试用：直接 emit clicked 信号（绕过鼠标，验证逻辑链路）
func emit_clicked_test() -> void:
	DebugLog.info("CARD_TEST: emit clicked idx=" + str(_index) + " card=" + str(_card_def.get("id", "")))
	clicked.emit(_index)
