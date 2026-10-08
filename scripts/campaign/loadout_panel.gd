# 装配只编辑草稿；预览、合法性和保存始终委托正式 Campaign。
class_name ChapterLoadoutPanel
extends Control
signal applied
const Rules = preload("res://scripts/rpg/loadout_rules.gd")
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
const Art = preload("res://scripts/campaign/presentation/night_menu_art.gd")
const Presenter = preload("res://scripts/rpg/ui/battle_presenter.gd")
const TAG_NAMES := {"blade": "刃", "shield": "盾", "bow": "弓", "focus": "法器", "bell": "铃", "sigil": "符"}
const STAT_NAMES := {"hp": "生命", "mp": "灵力", "atk": "攻击", "matk": "术攻", "def": "防御", "mdef": "术防", "spd": "速度"}
var campaign: RefCounted
var actor_id := ""
var draft: Dictionary = {}
var draft_equipment: Dictionary = {}
var preview: Dictionary = {}
var group := "default"
var selected_type := "active"
var selected_index := 0
var last_error := ""
var locked := false
var _saved: Dictionary = {}
var _slots: Dictionary = {}
var _groups: Dictionary = {}
var _cards: Dictionary = {}
var _list: VBoxContainer
var _title: Label
var _capacity: Label
var _stats: Label
var _reason: RichTextLabel
var _apply: Button
var _cancel: Button
var _clear: Button
var _weapon: OptionButton
var _built := false

func open(model: RefCounted, id: String) -> void:
	campaign = model
	if not _built: _build()
	actor_id = id
	_saved = campaign.safe_snapshot().roster.get(actor_id, {}).duplicate(true)
	draft = _saved.get("build", {}).duplicate(true)
	draft_equipment = _saved.get("equipment", {}).duplicate(true)
	group = str(_saved.get("form_id", "sword")) if draft.get("active", {}).has("sword") else "default"
	selected_type = "active"
	selected_index = 0
	last_error = ""
	_refresh()

func _build() -> void:
	_built = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Art.panel(self, Rect2(0, 0, 912, 582), true)
	_title = Kit.label(self, "技能装配", Rect2(18, 10, 430, 34), 24)
	_groups.sword = _button(self, "剑式配置", Rect2(468, 8, 196, 42), select_group.bind("sword"))
	_groups.mage = _button(self, "法式配置", Rect2(684, 8, 208, 42), select_group.bind("mage"))
	_capacity = Kit.label(self, "", Rect2(18, 51, 876, 51), 18)
	_capacity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_weapon = OptionButton.new()
	_weapon.name="DraftWeapon"
	_weapon.position=Vector2(18,104); _weapon.size=Vector2(418,32)
	_weapon.add_theme_font_override("font",Kit.font)
	_weapon.add_theme_font_size_override("font_size",18)
	for state in ["normal","hover","pressed","disabled","focus"]:
		var style:StyleBox=Kit.tokens.button_style(state,false).duplicate()
		style.content_margin_top=3; style.content_margin_bottom=3
		style.content_margin_left=12; style.content_margin_right=28
		_weapon.add_theme_stylebox_override(state,style)
	_weapon.tooltip_text="武器与技能一起编辑，应用时一次保存；可先改武器再修正不兼容卡片。"
	_weapon.item_selected.connect(_select_weapon)
	add_child(_weapon)
	Kit.label(self, "已收藏 · 可供多人准备，不消耗", Rect2(464, 108, 424, 28), 19)
	for type in ["active", "passive"]:
		_slots[type] = []
		for index in (4 if type == "active" else 2):
			var y := 140 + index * 44 if type == "active" else 326
			var x := 18 if type == "active" else 18 + index * 211
			var width := 418 if type == "active" else 207
			_slots[type].append(_button(self, "", Rect2(x, y, width, 42), select_slot.bind(type, index)))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(464, 140)
	scroll.size = Vector2(426, 228)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	_stats = Kit.label(self, "", Rect2(18, 378, 876, 58), 18)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason = Kit.scroll_text(self, Rect2(18, 441, 876, 61), 19)
	_reason.focus_mode=Control.FOCUS_ALL
	_reason.gui_input.connect(_scroll_detail)
	_clear = _button(self, "卸下所选卡", Rect2(18, 514, 232, 50), clear_slot)
	_cancel = _button(self, "取消改动", Rect2(464, 514, 198, 50), cancel_changes)
	_apply = _button(self, "应用装配", Rect2(678, 514, 212, 50), apply_changes, true)

func _button(parent: Node, text: String, rect: Rect2, action: Callable, primary: bool = false) -> Button:
	var button := Art.button(parent, text, rect, action, primary)
	button.custom_minimum_size.y = rect.size.y
	Art.center_text(button, 12, 12, 8)
	button.add_theme_font_size_override("font_size", 18)
	button.size = rect.size
	return button

func has_changes() -> bool:
	return draft != _saved.get("build", {}) or draft_equipment != _saved.get("equipment", {})

func set_locked(value: bool) -> void:
	locked = value
	if _built and campaign != null: _refresh()

func focus_first() -> void:
	if _slots.has("active"): _slots.active[0].grab_focus()

func select_group(value: String) -> void:
	if locked or not draft.get("active", {}).has(value): return
	# 此按钮只选择要编辑的主动组；解锁与实际切形仍由队伍页负责。
	group = value
	selected_type = "active"
	selected_index = 0
	last_error = ""
	_refresh()
	_slots.active[0].grab_focus()

func select_slot(type: String, index: int) -> void:
	if locked or type not in ["active", "passive"] or index < 0 or index >= (4 if type == "active" else 2): return
	selected_type = type
	selected_index = index
	last_error = ""
	_refresh()
	_slots[type][index].grab_focus()

func _selected_cards() -> Array:
	return draft.get("active", {}).get(group, []) if selected_type == "active" else draft.get("passive", [])

func select_card(id: String) -> void:
	if locked or campaign == null: return
	var definition := Rules.card(id)
	if definition.get("type") != selected_type or int(campaign.safe_snapshot().get("cards", {}).get(id, 0)) < 1: return
	var cards := _selected_cards().duplicate()
	if cards.has(id) and cards.find(id) != selected_index:
		last_error = "同一主动组或被动组不能重复准备同一张卡。"
		_refresh()
		return
	if selected_index < cards.size(): cards[selected_index] = id
	else:
		# 存档卡组保持紧凑数组；跨过空位选卡时落在首个可用空位。
		selected_index = cards.size()
		cards.append(id)
	if selected_type == "active": draft.active[group] = cards
	else: draft.passive = cards
	last_error = ""
	_refresh()
	if _cards.has(id): _cards[id].grab_focus()

func clear_slot() -> void:
	if locked: return
	var cards := _selected_cards().duplicate()
	if selected_index < cards.size(): cards.remove_at(selected_index)
	if selected_type == "active": draft.active[group] = cards
	else: draft.passive = cards
	last_error = ""
	_refresh()
	_slots[selected_type][selected_index].grab_focus()

func cancel_changes() -> void:
	if campaign == null: return
	_saved = campaign.safe_snapshot().roster.get(actor_id, {}).duplicate(true)
	draft = _saved.get("build", {}).duplicate(true)
	draft_equipment = _saved.get("equipment", {}).duplicate(true)
	last_error = "已取消未应用的改动。"
	_refresh()
	if is_visible_in_tree(): _slots[selected_type][selected_index].grab_focus()

func apply_changes() -> Dictionary:
	if campaign == null or locked: return {"ok": false, "error": "当前不能整备"}
	var checked: Dictionary = campaign.preview_loadout(actor_id, draft, draft_equipment)
	if not checked.get("ok", false):
		last_error = _errors(checked)
		_refresh()
		return checked
	var result: Dictionary = campaign.set_loadout(actor_id, draft, draft_equipment)
	last_error = str(result.get("error", ""))
	if result.get("ok", false):
		_saved = campaign.safe_snapshot().roster[actor_id].duplicate(true)
		draft = _saved.build.duplicate(true)
		draft_equipment = _saved.equipment.duplicate(true)
		last_error = "武器与技能已一起保存；收藏卡不会消耗。"
		applied.emit()
	_refresh()
	if is_visible_in_tree(): _slots[selected_type][selected_index].grab_focus()
	return result

func _refresh() -> void:
	if campaign == null or draft.is_empty(): return
	preview = campaign.preview_loadout(actor_id, draft, draft_equipment)
	var editable: bool = not locked and campaign.can_prepare()
	_refresh_weapon(editable)
	_title.text = "技能装配 · " + ("法式" if group == "mage" else "剑式" if group == "sword" else "当前配置")
	for value in _groups:
		_groups[value].visible = draft.active.has(value)
		_groups[value].disabled = not editable
		Art.selected(_groups[value], group == value)
		_groups[value].tooltip_text = "编辑备用主动组，不切换当前形态；两形态共享装备与被动。"
	var active: Array = draft.active.get(group, [])
	var active_used := 0
	for id in active: active_used += int(Rules.card(id).get("capacity_cost", 0))
	var caps: Dictionary = preview.get("capacity", {})
	var weapon_tags: Array = preview.get("weapon_tags", [])
	_capacity.text = "主动 %d/4 · 容量 %d/%d　被动 %d/2 · 容量 %d/%d\n武器标签：%s" % [active.size(), active_used, caps.get("active_max", 10), draft.passive.size(), caps.get("passive_used", 0), caps.get("passive_max", 4), "无（未装备武器）" if weapon_tags.is_empty() else tag_text(weapon_tags)]
	for type in _slots:
		var cards: Array = active if type == "active" else draft.passive
		for index in _slots[type].size():
			var button: Button = _slots[type][index]
			var definition: Dictionary = Rules.card(cards[index]) if index < cards.size() else {}
			button.text = "%s%d · %s" % ["主动" if type == "active" else "被动", index + 1, "空位" if definition.is_empty() else "%s [%d]" % [definition.name, definition.capacity_cost]]
			if type=="active" and not definition.is_empty():
				var detail:Dictionary=campaign.preview_loadout_skill(actor_id,draft,str(definition.id),group,draft_equipment)
				if detail.get("ok",false):button.text="%d. %s · MP%d · 容量%d" % [index+1,definition.name,detail.skill.mp_cost,definition.capacity_cost]
			button.tooltip_text = _card_detail(definition)
			button.disabled = not editable
			Art.selected(button, type == selected_type and index == selected_index)
	_rebuild_collection(editable)
	var lines: Array[String] = []
	# 非法草稿不显示可应用的属性结果；原因与容量仍可查看和修正。
	if preview.get("ok", false):
		for key in STAT_NAMES:
			var before: int = _saved.stats.get(key, 0)
			var after: int = preview.stats.get(key, before)
			lines.append("%s %d→%d%s" % [STAT_NAMES[key], before, after, " (%+d)" % (after - before) if before != after else ""])
		_stats.text = "　".join(lines)
	else: _stats.text = "当前草稿尚不能应用；请按下方原因调整卡片。"
	var messages: Array[String] = []
	if not preview.get("ok", false): messages.append(_errors(preview))
	if not last_error.is_empty() and not messages.has(last_error): messages.append(last_error)
	var selected := _selected_cards()
	if selected_index < selected.size(): messages.append(_card_detail(Rules.card(selected[selected_index])))
	if messages.is_empty(): messages.append("先选武器与卡位，再从收藏选卡。武器与技能一起应用；属性来自装备与共享被动。")
	_reason.text = "\n".join(messages)
	if not editable: _reason.text = "当前地点不能修改装配。"
	_reason.tooltip_text = _reason.text
	_apply.disabled = not editable or not preview.get("ok", false) or not has_changes()
	_cancel.disabled = locked or not has_changes()
	_clear.disabled = not editable or selected_index >= _selected_cards().size()
	_wire_focus()

func _rebuild_collection(editable: bool) -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_cards.clear()
	var owned: Dictionary = campaign.safe_snapshot().get("cards", {})
	var selected := _selected_cards()
	for definition in Rules.all_cards():
		if definition.type != selected_type or int(owned.get(definition.id, 0)) < 1: continue
		var caption := "%s%s · 容量%d · %s" % ["✓ " if selected.has(definition.id) else "", definition.name, definition.capacity_cost, tag_text(definition.weapon_tags)]
		var button := _button(_list, caption, Rect2(0, 0, 402, 42), select_card.bind(definition.id))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not editable
		button.tooltip_text = _card_detail(definition)
		_cards[definition.id] = button
		Art.selected(button, selected.has(definition.id))

func _wire_focus() -> void:
	var order: Array[Control] = []
	if not _weapon.disabled:order.append(_weapon)
	for value in _groups:
		if _groups[value].visible and not _groups[value].disabled: order.append(_groups[value])
	for type in ["active", "passive"]:
		for button in _slots[type]:
			if not button.disabled: order.append(button)
	for button in _cards.values():
		if not button.disabled: order.append(button)
	order.append(_reason)
	for button in [_clear, _cancel, _apply]:
		if not button.disabled: order.append(button)
	if order.is_empty(): return
	for index in order.size():
		var previous := order[index].get_path_to(order[(index - 1 + order.size()) % order.size()])
		var next := order[index].get_path_to(order[(index + 1) % order.size()])
		order[index].focus_previous = previous
		order[index].focus_next = next
		order[index].focus_neighbor_top = previous
		order[index].focus_neighbor_bottom = next
		order[index].focus_neighbor_left = previous
		order[index].focus_neighbor_right = next

static func tag_text(tags: Array) -> String:
	var labels: Array[String] = []
	for tag in tags: labels.append(TAG_NAMES.get(tag, str(tag)))
	return "不限武器" if labels.is_empty() else " / ".join(labels)

func _refresh_weapon(editable: bool) -> void:
	_weapon.clear()
	_weapon.add_item("武器 · 未装备")
	_weapon.set_item_metadata(0,"")
	var selected := 0
	var saved:Dictionary=campaign.safe_snapshot()
	for id in campaign._catalog.get_ids("equipment"):
		var equipment:Dictionary=campaign._catalog.get_definition("equipment",id)
		if equipment.get("slot")!="weapon" or int(saved.gear.get(id,0))<1:continue
		_weapon.add_item("武器 · "+str(equipment.name))
		var index:=_weapon.item_count-1
		_weapon.set_item_metadata(index,id)
		if id==str(draft_equipment.get("weapon","")):selected=index
	_weapon.select(selected)
	_weapon.disabled=not editable

func _select_weapon(index: int) -> void:
	if locked or campaign==null or not campaign.can_prepare():return
	draft_equipment.weapon=str(_weapon.get_item_metadata(index))
	last_error="武器仍是草稿。调整卡片后应用，生命和灵力不会补满。"
	_refresh()
	_weapon.grab_focus()

func _card_detail(definition: Dictionary) -> String:
	if definition.is_empty(): return "选择这个空位后，从收藏选择卡片。"
	var heading := "%s · 容量%d · 武器 %s" % [definition.name, definition.capacity_cost, tag_text(definition.weapon_tags)]
	if definition.type!="active" or campaign==null:return heading+"\n"+str(definition.summary)
	var proposed:Dictionary=draft.duplicate(true)
	var cards:Array=proposed.active.get(group,[]).duplicate()
	if not cards.has(definition.id):
		if selected_type=="active" and selected_index<cards.size():cards[selected_index]=definition.id
		elif cards.size()<4:cards.append(definition.id)
		else:return heading+"\n请先选一个主动卡位，再查看替换后的效果。"
	proposed.active[group]=cards
	var detail:Dictionary=campaign.preview_loadout_skill(actor_id,proposed,str(definition.id),group,draft_equipment)
	var skill:Dictionary=detail.get("skill",{})
	if skill.is_empty():return heading+"\n"+str(detail.get("error","技能未登记"))
	var label := "装配后预览" if detail.get("ok",false) else "基础说明 · 当前配置不可应用"
	var text := "%s\n%s · MP%d · CD%d\n%s" % [heading,label,int(skill.mp_cost),int(skill.cooldown),Presenter.ability_summary(skill,{},campaign._catalog)]
	if detail.get("form_locked",false):text+="\n此为备用配置；该形态尚未解锁。"
	if selected_type=="active" and cards.has(definition.id) and draft.active.get(group,[]).has(definition.id) and cards.find(definition.id)!=selected_index:
		text+="\n已在另一卡位准备；若要移到所选位置，先卸下原卡位。"
	if not detail.get("ok",false):text+="\n"+str(detail.get("error",""))
	return text

func _scroll_detail(event:InputEvent)->void:
	if not event is InputEventKey or not event.pressed:return
	var bar:=_reason.get_v_scroll_bar()
	match event.keycode:
		KEY_DOWN:bar.value+=30
		KEY_UP:bar.value-=30
		KEY_PAGEDOWN:bar.value+=bar.page
		KEY_PAGEUP:bar.value-=bar.page
		KEY_HOME:bar.value=bar.min_value
		KEY_END:bar.value=bar.max_value
		_:return
	accept_event()

static func _errors(value: Dictionary) -> String:
	var errors: Array = value.get("errors", [])
	return "；".join(errors) if not errors.is_empty() else str(value.get("error", "装配非法"))
