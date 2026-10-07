# 只读回收册：仅接受正式快照与目录，不持有Campaign，不提供领取、售卖、消耗或剧情写入接口。
extends Control
const Recovery = preload("res://scripts/campaign/recovery_catalog.gd")
const Art = preload("res://scripts/campaign/presentation/night_menu_art.gd")
const CHAPTER_NAMES := {1:"五夜寺域",2:"无眠街",3:"逆水渡",4:"镜中双影",5:"借命灯",6:"百夜无更",7:"天明之前"}

var entries: Array = []
var selected_id := ""
var _catalog: RefCounted
var _list: VBoxContainer
var _detail: RichTextLabel
var _count: Label
var _empty: Label
var _buttons: Dictionary = {}
var _built := false

func open(saved: Dictionary, catalog: RefCounted) -> void:
	_catalog = catalog
	if not _built: _build()
	entries = Recovery.earned(saved,catalog)
	_buttons.clear()
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if not entries.any(func(entry): return str(entry.id) == selected_id):
		selected_id = str(entries[0].id) if not entries.is_empty() else ""
	_count.text = "已收录 %d 种 · 首次胜利后留存" % entries.size()
	_empty.visible = entries.is_empty()
	for entry in entries:
		var button := Button.new()
		button.name = "Record_" + str(entry.id)
		button.text = str(entry.name) + "\n" + _enemy_name(entry)
		button.custom_minimum_size.y = 82
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_ALL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size",22)
		button.pressed.connect(select_record.bind(str(entry.id)))
		_list.add_child(button)
		_buttons[str(entry.id)] = button
	_render_detail()
	var ordered: Array = _buttons.values()
	for index in ordered.size():
		if index > 0: ordered[index].focus_neighbor_top = ordered[index].get_path_to(ordered[index-1])
		if index+1 < ordered.size(): ordered[index].focus_neighbor_bottom = ordered[index].get_path_to(ordered[index+1])

func _build() -> void:
	_built = true
	name = "RecoveryBook"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Theme.new()
	theme.default_font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
	theme.default_font_size = 22
	theme.set_color("font_color","Label",Color("f2e5ca"))
	theme.set_color("default_color","RichTextLabel",Color("f2e5ca"))
	for state in ["normal","hover","pressed","disabled","focus"]:
		theme.set_stylebox(state,"Button",Art.style({"normal":"button","hover":"button_selected","pressed":"button_selected","disabled":"button_disabled","focus":"focus"}[state],12))
	var frame := PanelContainer.new()
	frame.name = "RecordFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_stylebox_override("panel",Art.style("inset",12))
	add_child(frame)
	var margin := MarginContainer.new()
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,18)
	frame.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	margin.add_child(column)
	_count = Label.new()
	_count.name = "RecordCount"
	_count.add_theme_font_size_override("font_size",24)
	column.add_child(_count)
	var content := HBoxContainer.new()
	content.name = "RecordContent"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",24)
	column.add_child(content)
	var scroll := ScrollContainer.new()
	scroll.name = "RecordListScroll"
	scroll.custom_minimum_size.x = 346
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	content.add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "RecordList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation",10)
	scroll.add_child(_list)
	_empty = Label.new()
	_empty.name = "EmptyBook"
	_empty.text = "册页暂空\n\n只有已确认的真实胜利\n才会留下首次回收记录。"
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty.custom_minimum_size.x = 240
	content.add_child(_empty)
	_detail = RichTextLabel.new()
	_detail.name = "RecordDetail"
	_detail.bbcode_enabled = false
	_detail.scroll_active = true
	_detail.selection_enabled = true
	_detail.focus_mode = Control.FOCUS_ALL
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_detail)

func select_record(id: String) -> void:
	if not _buttons.has(id): return
	selected_id = id
	_render_detail()
	_detail.scroll_to_line(0)

func focus_first() -> bool:
	if _buttons.has(selected_id):
		_buttons[selected_id].grab_focus()
		return true
	return false

func _selected() -> Dictionary:
	for entry in entries:
		if str(entry.id) == selected_id: return entry
	return {}

func _enemy_name(entry: Dictionary) -> String:
	return str(_catalog.get_definition("enemies",str(entry.get("enemy_id",""))).get("name","未知敌种"))

func _render_detail() -> void:
	var entry := _selected()
	for id in _buttons:
		_buttons[id].add_theme_stylebox_override("normal",Art.style("button_selected" if id == selected_id else "button",12))
	_detail.visible = not entry.is_empty()
	if entry.is_empty():
		_detail.text = ""
		return
	var encounter_name := str(entry.get("encounter_name",""))
	if encounter_name.is_empty(): encounter_name = str(_catalog.get_definition("encounters",str(entry.encounter_id)).get("name","已确认的遭遇"))
	var chapter := int(entry.get("chapter",0))
	# verified_scope保留内部战斗ID用于审计；玩家页仅呈现真实敌名、遭遇名与可读留记。
	var player_note := "%s退治后留存，后续调查对照随实际进度开放。" % _enemy_name(entry)
	var lines: Array[String] = [str(entry.name),"来源敌种："+_enemy_name(entry),"首收地点：第%d章 · %s" % [chapter,str(CHAPTER_NAMES.get(chapter,"行旅"))],"首次遭遇："+encounter_name,"留存数量：%d" % int(entry.get("quantity",1)),"","回收摘要",str(entry.summary),"","战后留记",player_note,"","调查对照"]
	var links: Array = entry.get("links",[])
	if links.is_empty(): lines.append("目前没有关联的调查记录。")
	for link in links:
		# 即使上游误带标题/正文，也绝不渲染未解锁的内容、场次ID或tooltip。
		if not bool(link.get("unlocked",false)):
			lines.append("后续调查尚未完成，对照内容暂未开放。")
			continue
		lines.append(str(link.get("label","调查记录")))
		lines.append(str(link.get("text","")))
		lines.append("")
	lines.append("永久回收记录 · 可随时回看")
	_detail.text = "\n".join(lines)
