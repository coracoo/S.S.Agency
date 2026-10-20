extends Control
## 仅展示命令纸叶；层级导航与提交由BattleView负责。

const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
const PAPER := Color("F3EFE5")
const INK := Color("252B29")
const SEAL := Color("A64234")
const MUTED := Color("545952")
const LEAF_PADDING := 12.0
const TEXT_GAP := 4.0
const LEAF_GAP := 12.0

signal command_requested(kind: String, ability_id: String)
signal page_requested(page: String)
signal back_requested
signal confirm_requested

var skill_buttons: Array[Button] = []
var basic_buttons: Dictionary = {}
var confirm_button: Button
var back_button: Button

var _built := false
var _docked := false
var _model: Dictionary = {}
var _page := "commands"
var _pages: Dictionary = {}
var _header: Label
var _header_paper: Panel
var _skills_entry: Button
var _skill_scroll: ScrollContainer
var _skill_content: Control
var _item_scroll: ScrollContainer
var _item_content: Control
var _item_buttons: Array[Button] = []
var _target_line: Label
var _target_paper: Panel
var _focus_keys: Dictionary = {}

static func size_for_page(page: String, docked: bool) -> Vector2:
	Kit.init()
	var header := _line_height(24) + 16.0
	var command := _line_height(30) + 24.0
	var leaf := _line_height(27) + _line_height(24) * 2.0 + LEAF_PADDING * 2.0 + TEXT_GAP * 2.0
	if docked:
		if page == "items": return Vector2(940, 360)
		if page == "target": return Vector2(1872, header + 8.0 + command)
		if page == "commands": return Vector2(1872, header + 8.0 + command)
		return Vector2(1872, header + 8.0 + leaf)
	if page == "commands": return Vector2(480, header + 8.0 + command * 3.0 + 20.0)
	if page == "target": return Vector2(740, header + 8.0 + command)
	if page == "skills": return Vector2(400, 560)
	return Vector2(480, 560)

static func _line_height(font_size: int) -> float:
	return ceilf(Kit.font.get_height(font_size)) + 4.0

## present之后调用；完整原因所需高度可能高于静态停靠基线。
func required_size_for_page(page: String, docked: bool) -> Vector2:
	_ensure_built()
	var required := size_for_page(page, docked)
	if page == "target" and not docked:
		# 目标名称/真实费用保持单行完整，宽度增加时由避让器选择安全位置。
		required.x = clampf(ceilf(Kit.font.get_string_size(_target_line.text,HORIZONTAL_ALIGNMENT_LEFT,-1,24).x) + 284.0,740.0,1872.0)
	if page == "commands" and not docked:
		var count := 1
		for button in basic_buttons.values():
			if button.visible: count += 1
		var rows := ceili(count / 2.0)
		required.y = _header_height() + 8.0 + (_line_height(30) + 24.0) * rows + 10.0 * (rows - 1)
	if page == "skills":
		var width := (required.x - LEAF_GAP * 3.0) / 4.0 if docked else required.x - 14.0
		var height := 0.0
		var count := 0
		for button in skill_buttons:
			if not button.visible: continue
			var leaf_height := _leaf_height(button, width)
			height = maxf(height, leaf_height) if docked else height + leaf_height
			count += 1
		if docked:
			required.y = maxf(required.y, _header_height() + 8.0 + height)
		else:
			# 不夹断内容高度；超过可用区域时，由placement选择安全停靠形态。
			required.y = _header_height() + 8.0 + height + maxf(0, count - 1) * 10.0 + _line_height(24) + 24.0
	return required

func _ready() -> void:
	_ensure_built()
	visibility_changed.connect(_sync_focus_modes)
	resized.connect(_layout)
	_layout()
	_sync_focus_modes()

func _ensure_built() -> void:
	if _built: return
	_built = true
	Kit.init()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for page in ["commands", "skills", "items", "target"]:
		var panel := Control.new()
		panel.name = page.capitalize()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel)
		_pages[page] = panel
	_header_paper = _paper_panel(self)
	_header = _label(24)
	_header.clip_text = true
	_header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_header)
	_skills_entry = _button("技能", "skills", 30)
	_pages.commands.add_child(_skills_entry)
	_skills_entry.pressed.connect(_request_page.bind("skills", _skills_entry))
	for kind in ["attack_physical", "attack_magic", "defend", "item"]:
		var names := {"attack_physical": "物理普攻", "attack_magic": "术法普攻", "defend": "防御", "item": "道具"}
		var button := _button(names[kind], kind, 30)
		_pages.commands.add_child(button)
		basic_buttons[kind] = button
		if kind == "item": button.pressed.connect(_request_page.bind("items", button))
		else: button.pressed.connect(_request_command.bind(kind, button))
	_skill_scroll = _scroll(_pages.skills)
	_skill_content = _content(_skill_scroll)
	for index in 4:
		var button := _leaf("skill:", 27)
		button.name = "Skill%d" % index
		_skill_content.add_child(button)
		skill_buttons.append(button)
		button.pressed.connect(_request_command.bind("skill", button))
	_item_scroll = _scroll(_pages.items)
	_item_content = _content(_item_scroll)
	# 正式库存七项；只构建一次，后续复用。
	for index in 7:
		var button := _leaf("item:", 27)
		button.name = "Item%d" % index
		_item_content.add_child(button)
		_item_buttons.append(button)
		button.pressed.connect(_request_command.bind("item", button))
	_target_paper = _paper_panel(_pages.target)
	_target_line = _label(24)
	_target_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pages.target.add_child(_target_line)
	confirm_button = _button("确认", "confirm", 30)
	confirm_button.add_theme_stylebox_override("normal", _paper_style(SEAL))
	_pages.target.add_child(confirm_button)
	confirm_button.pressed.connect(_request_confirm)
	back_button = _button("返回", "back", 24)
	add_child(back_button)
	back_button.pressed.connect(_request_back)
	_focus_keys = {"skills": _skills_entry, "confirm": confirm_button, "back": back_button}
	for kind in basic_buttons: _focus_keys[kind] = basic_buttons[kind]

func present(model: Dictionary) -> void:
	_ensure_built()
	_model = model.duplicate(true)
	_page = str(_model.get("page", "commands"))
	if not _pages.has(_page): _page = "commands"
	for page in _pages: _pages[page].visible = page == _page
	var headings := {"commands": "行动", "skills": "技能", "items": "道具", "target": "目标"}
	_header.text = "%s  /  %s" % [str(_model.get("actor_name", "")), headings[_page]]
	_header.tooltip_text = str(_model.get("prompt", ""))
	var basics: Array = _model.get("basics", [])
	for kind in basic_buttons:
		basic_buttons[kind].visible = kind in basics
		basic_buttons[kind].disabled = false
	_focus_keys = {"skills": _skills_entry, "confirm": confirm_button, "back": back_button}
	for kind in basic_buttons: _focus_keys[kind] = basic_buttons[kind]
	var skills: Array = _model.get("skills", [])
	for index in skill_buttons.size():
		var button := skill_buttons[index]
		var entry: Dictionary = skills[index] if index < skills.size() else {}
		button.visible = not entry.is_empty()
		button.disabled = not bool(entry.get("legal", false))
		var id := str(entry.get("id", ""))
		button.set_meta("ability_id", id)
		button.set_meta("command_key", "skill:" + id)
		_focus_keys["skill:" + id] = button
		var resource_text := "MP %s" % str(entry.get("mp_cost", 0))
		var cd := str(entry.get("cd_text", ""))
		if not cd.is_empty(): resource_text += "  ·  " + cd
		var detail := " · ".join(_strings([entry.get("summary", ""), entry.get("target_label", "")]))
		_set_leaf(button, str(entry.get("name", "")), resource_text, detail, _reason_text(entry))
		button.tooltip_text += "\n" + str(entry.get("full_summary", ""))
	var items: Array = _model.get("items", [])
	for index in _item_buttons.size():
		var button := _item_buttons[index]
		var entry: Dictionary = items[index] if index < items.size() else {}
		button.visible = not entry.is_empty()
		button.disabled = not bool(entry.get("legal", false))
		var id := str(entry.get("id", ""))
		button.set_meta("ability_id", id)
		button.set_meta("command_key", "item:" + id)
		_focus_keys["item:" + id] = button
		_set_leaf(button, str(entry.get("name", "")), "持有 %s" % str(entry.get("count", 0)), "", _reason_text(entry))
	var target_parts := _strings([_model.get("selected_label", ""), _model.get("cost_text", ""), _model.get("target_text", "")])
	_target_line.text = "  ·  ".join(target_parts)
	if _target_line.text.is_empty(): _target_line.text = str(_model.get("prompt", "选择目标后确认"))
	_target_line.tooltip_text = _target_line.text + "\n" + str(_model.get("prompt", ""))
	confirm_button.disabled = not bool(_model.get("confirm_legal", false))
	back_button.visible = _page != "commands"
	_layout()
	_sync_focus_modes()

func set_placement(rect: Rect2, docked: bool) -> void:
	_ensure_built()
	_docked = docked
	position = rect.position
	size = rect.size
	_layout()

func focus_key(key: String) -> void:
	_ensure_built()
	var requested: Control = _focus_keys.get(key)
	if requested != null and requested in enabled_controls():
		requested.grab_focus()
		if requested.get_parent() == _skill_content: _skill_scroll.ensure_control_visible(requested)
		if requested.get_parent() == _item_content: _item_scroll.ensure_control_visible(requested)

func enabled_controls() -> Array[Control]:
	var result: Array[Control] = []
	if not _built or not is_visible_in_tree(): return result
	for button in _all_buttons():
		if button.is_visible_in_tree() and not button.disabled: result.append(button)
	return result

func _all_buttons() -> Array[Button]:
	var result: Array[Button] = [_skills_entry]
	for kind in ["attack_physical", "attack_magic", "defend", "item"]: result.append(basic_buttons[kind])
	result.append_array(skill_buttons)
	result.append_array(_item_buttons)
	result.append(confirm_button)
	result.append(back_button)
	return result

func _sync_focus_modes() -> void:
	if not _built: return
	var enabled := enabled_controls()
	for button in _all_buttons():
		if button not in enabled:
			if button.has_focus(): button.release_focus()
			button.focus_mode = Control.FOCUS_NONE
		else:
			button.focus_mode = Control.FOCUS_ALL
	for index in enabled.size():
		var button := enabled[index]
		var previous := enabled[(index - 1 + enabled.size()) % enabled.size()]
		var following := enabled[(index + 1) % enabled.size()]
		button.focus_previous = button.get_path_to(previous)
		button.focus_next = button.get_path_to(following)

func _request_page(page: String, button: Button) -> void:
	if _can_press(button): page_requested.emit(page)

func _request_command(kind: String, button: Button) -> void:
	if _can_press(button): command_requested.emit(kind, str(button.get_meta("ability_id", "")))

func _request_confirm() -> void:
	if _can_press(confirm_button): confirm_requested.emit()

func _request_back() -> void:
	if _can_press(back_button): back_requested.emit()

func _can_press(button: Button) -> bool:
	return button.is_visible_in_tree() and not button.disabled

func _layout() -> void:
	if not _built: return
	for panel in _pages.values(): panel.size = size
	var header_height := _header_height()
	var content_top := header_height + 8.0
	var footer_height := _line_height(24) + 16.0
	var header_width := minf(maxf(1, size.x - 116), Kit.font.get_string_size(_header.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 24)
	_header_paper.position = Vector2.ZERO
	_header_paper.size = Vector2(header_width, header_height)
	_header.position = Vector2(12, 8)
	_header.size = Vector2(maxf(1, header_width - 24), _line_height(24))
	back_button.position = Vector2(size.x - 108, 0) if _docked else Vector2(size.x - 108, size.y - footer_height)
	back_button.size = Vector2(108, footer_height)
	var commands: Array[Button] = [_skills_entry]
	for kind in ["attack_physical", "attack_magic", "defend", "item"]:
		if basic_buttons[kind].visible: commands.append(basic_buttons[kind])
	for index in commands.size():
		var button := commands[index]
		if _docked:
			var width := (size.x - 12 * (commands.size() - 1)) / commands.size()
			button.position = Vector2(index * (width + 12), content_top)
			button.size = Vector2(width, maxf(_line_height(30) + 24.0, size.y - content_top))
		else:
			var height := _line_height(30) + 24.0
			var width := (size.x - 12.0) / 2.0
			button.position = Vector2((index % 2) * (width + 12.0), content_top + floori(index / 2.0) * (height + 10.0))
			button.size = Vector2(width, height)
	_skill_scroll.position = Vector2.ZERO if _docked else Vector2(0, content_top)
	_skill_scroll.size = size if _docked else Vector2(size.x, maxf(1, size.y - content_top - footer_height - 8.0))
	var cursor := 0.0
	var card_width := (size.x - 36) / 4.0 if _docked else maxf(1, size.x - 14)
	var dock_height := maxf(1, size.y - content_top)
	for button in skill_buttons:
		if button.visible: dock_height = maxf(dock_height, _leaf_height(button, card_width))
	var content_height := content_top + dock_height
	for index in skill_buttons.size():
		var button := skill_buttons[index]
		var height := dock_height if _docked else _leaf_height(button, card_width)
		button.position = Vector2(index * (card_width + 12), content_top) if _docked else Vector2(0, cursor)
		button.size = Vector2(card_width, height)
		_layout_leaf(button)
		if not _docked and button.visible: cursor += height + 10
	if not _docked: content_height = maxf(0, cursor - 10)
	_skill_content.custom_minimum_size = Vector2(maxf(1, size.x - (0 if _docked else 14)), content_height)
	_skill_content.size = _skill_content.custom_minimum_size
	_item_scroll.position = Vector2(0, content_top)
	_item_scroll.size = Vector2(size.x, maxf(1, size.y - content_top - (0.0 if _docked else footer_height + 8.0)))
	var item_width := maxf(1, (size.x - 24) / 2)
	var item_y := 0.0
	for row in 4:
		var height := 0.0
		for column in 2:
			var index := row * 2 + column
			if index < _item_buttons.size(): height = maxf(height, _leaf_height(_item_buttons[index], item_width))
		for column in 2:
			var index := row * 2 + column
			if index >= _item_buttons.size(): continue
			var button := _item_buttons[index]
			button.position = Vector2(column * (item_width + 10), item_y)
			button.size = Vector2(item_width, height)
			_layout_leaf(button)
		item_y += height + 10
	_item_content.custom_minimum_size = Vector2(maxf(1, size.x - 14), item_y - 10)
	_item_content.size = _item_content.custom_minimum_size
	var target_height := _line_height(30) + 24.0
	_target_line.position = Vector2(12, content_top + 12.0)
	_target_line.size = Vector2(maxf(1, size.x - 260), _line_height(24))
	_target_paper.position = Vector2(0, content_top)
	_target_paper.size = Vector2(maxf(1, size.x - 248), target_height)
	confirm_button.position = Vector2(size.x - 236, content_top)
	confirm_button.size = Vector2(118, target_height)
	if _page == "target":
		back_button.position = Vector2(size.x - 108, content_top)
		back_button.size = Vector2(108, target_height)

func _header_height() -> float:
	return _line_height(24) + 16.0

func _leaf_height(button: Button, width: float) -> float:
	var title: Label = button.get_node("Title")
	var resource: Label = button.get_node("Resource")
	var detail: Label = button.get_node("Detail")
	var reason: Label = button.get_node("Reason")
	var inner := maxf(1, width - LEAF_PADDING * 2.0)
	var title_height := _wrapped_height(title.text, inner, 27)
	var resource_height := _wrapped_height(resource.text, inner, 24)
	var body := reason.text if not reason.text.is_empty() else detail.text
	var body_height := _wrapped_height(body, inner, 24) if not body.is_empty() else 0.0
	return LEAF_PADDING * 2.0 + title_height + resource_height + TEXT_GAP + (body_height + TEXT_GAP if body_height > 0.0 else 0.0)

func _layout_leaf(button: Button) -> void:
	var title: Label = button.get_node("Title")
	var resource: Label = button.get_node("Resource")
	var detail: Label = button.get_node("Detail")
	var reason: Label = button.get_node("Reason")
	var inner := maxf(1, button.size.x - LEAF_PADDING * 2.0)
	var title_height := _wrapped_height(title.text, inner, 27)
	var resource_height := _wrapped_height(resource.text, inner, 24)
	title.position = Vector2(LEAF_PADDING, LEAF_PADDING)
	title.custom_minimum_size = Vector2(0, title_height)
	title.size = Vector2(inner, title_height)
	resource.position = Vector2(LEAF_PADDING, LEAF_PADDING + title_height + TEXT_GAP)
	resource.custom_minimum_size = Vector2(0, resource_height)
	resource.size = Vector2(inner, resource_height)
	var body_y := resource.position.y + resource_height + TEXT_GAP
	detail.visible = reason.text.is_empty() and not detail.text.is_empty()
	reason.visible = not reason.text.is_empty()
	for label in [detail, reason]:
		var height := _wrapped_height(label.text, inner, 24)
		label.position = Vector2(LEAF_PADDING, body_y)
		label.custom_minimum_size = Vector2(0, height)
		label.size = Vector2(inner, height)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		label.clip_text = false
	title.clip_text = false

func _wrapped_height(value: String, width: float, font_size: int) -> float:
	var flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var measured := Kit.font.get_multiline_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, maxf(1, width), font_size, -1, flags)
	return maxf(_line_height(font_size), ceilf(measured.y) + 4.0)

func _set_leaf(button: Button, title: String, resource: String, detail: String, reason: String) -> void:
	var title_label: Label = button.get_node("Title")
	var resource_label: Label = button.get_node("Resource")
	var detail_label: Label = button.get_node("Detail")
	var reason_label: Label = button.get_node("Reason")
	title_label.text = title
	resource_label.text = resource
	detail_label.text = detail
	reason_label.text = reason
	button.tooltip_text = "\n".join(_strings([title, resource, detail, reason]))
	button.accessibility_name = title + " " + resource + " " + reason

func _reason_text(entry: Dictionary) -> String:
	return " · ".join(_strings(entry.get("reasons", [])))

func _strings(values: Array) -> PackedStringArray:
	var result := PackedStringArray()
	for value in values:
		var text := str(value)
		if not text.is_empty(): result.append(text)
	return result

func _scroll(parent: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.focus_mode = Control.FOCUS_NONE
	parent.add_child(scroll)
	return scroll

func _content(parent: Control) -> Control:
	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(content)
	return content

func _leaf(key: String, font_size: int) -> Button:
	var button := _button("", key, font_size)
	for name in ["Title", "Resource", "Detail", "Reason"]:
		var label := _label(font_size if name == "Title" else 24)
		label.name = name
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if name == "Reason": label.add_theme_color_override("font_color", SEAL)
		button.add_child(label)
	return button

func _label(font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", Kit.font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	# 与Font的多行度量使用同一行距，避免继承主题额外增高。
	label.add_theme_constant_override("line_spacing", 0)
	label.add_theme_constant_override("outline_size", 0)
	return label

func _paper_panel(parent: Control) -> Panel:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _paper_style(INK))
	parent.add_child(panel)
	return panel

func _button(text: String, key: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.set_meta("command_key", key)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", Kit.font)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_stylebox_override("normal", _paper_style(INK))
	button.add_theme_stylebox_override("hover", _paper_style(SEAL, PAPER.lightened(0.04)))
	button.add_theme_stylebox_override("pressed", _paper_style(SEAL, PAPER.darkened(0.06)))
	button.add_theme_stylebox_override("disabled", _paper_style(MUTED, PAPER.darkened(0.035)))
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = SEAL
	focus.set_border_width_all(3)
	focus.set_expand_margin_all(2)
	button.add_theme_stylebox_override("focus", focus)
	return button

func _paper_style(edge: Color, paper: Color = PAPER) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = paper
	style.border_color = edge
	style.border_width_left = 3
	style.border_width_bottom = 1
	style.corner_radius_top_left = 2
	style.corner_radius_bottom_right = 7
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.shadow_color = Color(0.08, 0.10, 0.09, 0.22)
	style.shadow_size = 3
	style.shadow_offset = Vector2(2, 3)
	return style
