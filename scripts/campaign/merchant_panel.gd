# 商店只展示模型货架并提交购买请求；余额、全局库存与交易记录只能由正式存档事务修改。
extends Control
signal closed
signal purchased

const Merchant = preload("res://scripts/campaign/merchant_catalog.gd")
const Loadouts = preload("res://scripts/rpg/loadout_rules.gd")
const Art = preload("res://scripts/campaign/presentation/night_menu_art.gd")
const STAT_NAMES := {"hp":"生命", "mp":"灵力", "atk":"攻击", "matk":"术攻", "def":"防御", "mdef":"术防", "spd":"速度"}
const TAG_NAMES := {"blade":"刃", "shield":"盾", "bow":"弓", "focus":"法器", "bell":"铃", "sigil":"符"}

var campaign: RefCounted
var world: Dictionary = {}
var offers: Array = []
var selected_id := ""
var last_error := ""
var _input_armed := false
var _busy := false
var _built := false
var _balance: Label
var _offer_list: VBoxContainer
var _detail: RichTextLabel
var _status: Label
var _quantity: SpinBox
var _buy: Button
var _close: Button
var _buttons: Array[Button] = []

func open(model: RefCounted, location: Dictionary) -> void:
	campaign = model
	world = location.duplicate(true)
	if not _built: _build()
	_input_armed = false
	last_error = ""
	_refresh()
	set_process(true)

func _build() -> void:
	_built = true
	name = "MerchantPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = _theme()
	var shade := ColorRect.new()
	shade.color = Color(.015,.022,.032,.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var safe := MarginContainer.new()
	safe.name = "SafeMargins"
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: safe.add_theme_constant_override("margin_"+edge,32)
	add_child(safe)
	var frame := PanelContainer.new()
	frame.name = "ShopFrame"
	frame.add_theme_stylebox_override("panel", Art.style("panel",30))
	safe.add_child(frame)
	var margin := MarginContainer.new()
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,24)
	frame.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",16)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var heading := _label("神秘商人 · 行囊",32)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	_balance = _label("",25)
	_balance.name = "Balance"
	header.add_child(_balance)
	var note := _label("沿途同一份存货 · 交易后保存 · 装备与卡牌需在整备中配置",20)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	var content := HBoxContainer.new()
	content.name = "ShopContent"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",24)
	column.add_child(content)
	var list_scroll := ScrollContainer.new()
	list_scroll.name = "OfferScroll"
	list_scroll.custom_minimum_size.x = 260
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_stretch_ratio = .8
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.follow_focus = true
	content.add_child(list_scroll)
	_offer_list = VBoxContainer.new()
	_offer_list.name = "OfferList"
	_offer_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_offer_list.add_theme_constant_override("separation",10)
	list_scroll.add_child(_offer_list)
	var info := VBoxContainer.new()
	info.name = "SelectedOffer"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_stretch_ratio = 1.2
	info.add_theme_constant_override("separation",12)
	content.add_child(info)
	_detail = RichTextLabel.new()
	_detail.name = "OfferDescription"
	_detail.bbcode_enabled = false
	_detail.scroll_active = true
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_detail)
	var order := HBoxContainer.new()
	order.name = "QuantityRow"
	order.add_theme_constant_override("separation",16)
	info.add_child(order)
	order.add_child(_label("购买数量",22))
	_quantity = SpinBox.new()
	_quantity.name = "Quantity"
	_quantity.min_value = 1
	_quantity.max_value = 1
	_quantity.step = 1
	_quantity.custom_minimum_size = Vector2(150,48)
	_quantity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quantity.value_changed.connect(_quantity_changed)
	order.add_child(_quantity)
	_buy = _button("购买并保存",_buy_selected)
	_buy.name = "BuySelected"
	info.add_child(_buy)
	_status = _label("",21)
	_status.name = "TransactionStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 56
	column.add_child(_status)
	_close = _button("收好行囊 · 返回行走 [Esc]",request_close)
	_close.name = "CloseMerchant"
	column.add_child(_close)

func _theme() -> Theme:
	var result := Theme.new()
	result.default_font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
	result.default_font_size = 22
	for type in ["Label","RichTextLabel","Button","LineEdit"]:
		result.set_color("default_color" if type == "RichTextLabel" else "font_color",type,Color("f4e7cc"))
	for state in ["normal","hover","pressed","disabled","focus"]:
		result.set_stylebox(state,"Button",Art.style({"normal":"button","hover":"button_selected","pressed":"button_selected","disabled":"button_disabled","focus":"focus"}[state],12))
	result.set_color("font_disabled_color","Button",Color("a49d8c"))
	return result

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",font_size)
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 56
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(action)
	return button

func _process(_delta: float) -> void:
	# 只等待松键，不逐帧读取余额或改货架；避免开窗的E/确认键变成第一笔购买。
	if not _input_armed and not Input.is_action_pressed("approach_interact") and not Input.is_action_pressed("ui_accept") and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_input_armed = true
		_refresh_actions()
		if get_viewport().gui_get_focus_owner() == null:
			if not _buttons.is_empty(): _buttons[0].grab_focus()
			else: _close.grab_focus()
		set_process(false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo: return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("approach_pause"):
		get_viewport().set_input_as_handled()
		request_close()

func request_close() -> void:
	if _busy: return
	_input_armed = false
	closed.emit()

func _refresh() -> void:
	var saved: Dictionary = campaign.safe_snapshot()
	offers = Merchant.offers(saved,campaign._catalog)
	_balance.text = "银钱 %d 文" % int(saved.get("saga",{}).get("coins",0))
	_buttons.clear()
	for child in _offer_list.get_children():
		_offer_list.remove_child(child)
		child.queue_free()
	if not offers.any(func(offer): return str(offer.id) == selected_id): selected_id = str(offers[0].id) if not offers.is_empty() else ""
	for offer in offers:
		var stock_text := "余 %d 件" % int(offer.stock) if bool(offer.unlocked) else "尚未开放"
		var button := _button("%s\n%d 文 · %s" % [str(offer.name),int(offer.price),stock_text],_select.bind(str(offer.id)))
		button.name = "Offer_" + str(offer.id)
		button.custom_minimum_size.y = 82
		button.tooltip_text = str(offer.description)
		_offer_list.add_child(button)
		_buttons.append(button)
	_refresh_detail()
	_wire_focus()

func _select(id: String) -> void:
	if not _input_armed or _busy: return
	selected_id = id
	last_error = ""
	_quantity.set_value_no_signal(1)
	_refresh_detail()

func _selected() -> Dictionary:
	for offer in offers:
		if str(offer.id) == selected_id: return offer
	return {}

func _refresh_detail() -> void:
	var offer := _selected()
	if offer.is_empty():
		_detail.text = "行囊中暂无可展示的商品。"
		_refresh_actions()
		return
	var saved: Dictionary = campaign.safe_snapshot()
	var kind := str(offer.kind)
	var held := int(saved.get("gear" if kind == "gear" else "cards",{}).get(str(offer.item_id),0))
	var lines: Array[String] = [str(offer.name),"装备" if kind == "gear" else "技能卡",str(offer.description),"", "单价 %d 文 · 现有 %d · 本周目剩余 %d" % [int(offer.price),held,int(offer.stock)]]
	if kind == "gear":
		var definition: Dictionary = campaign._catalog.get_definition("equipment",str(offer.item_id))
		lines.append("装备部位：" + str({"weapon":"武器","armor":"护甲","accessory":"饰品"}.get(definition.get("slot",""),"")))
		var stats: Dictionary = definition.get("stats",{})
		for stat in STAT_NAMES:
			if stats.has(stat): lines.append("%s %+d" % [STAT_NAMES[stat],int(stats[stat])])
	else:
		var card := Loadouts.card(str(offer.item_id))
		lines.append("主动卡" if card.get("type") == "active" else "被动卡")
		lines.append("容量消耗 %d" % int(card.get("capacity_cost",0)))
		lines.append(str(card.get("summary","")))
		var tags: Array[String] = []
		for tag in card.get("weapon_tags",[]): tags.append(str(TAG_NAMES.get(tag,tag)))
		lines.append("武器条件：" + ("任意" if tags.is_empty() else " / ".join(tags)))
	_detail.text = "\n".join(lines)
	_quantity.max_value = maxi(1,int(offer.stock))
	_quantity.value = minf(_quantity.value,_quantity.max_value)
	_refresh_actions()

func _quantity_changed(_value: float) -> void:
	if _built: _refresh_actions()

func _refresh_actions() -> void:
	if not _built: return
	var offer := _selected()
	var reason := ""
	var total := 0
	if offer.is_empty(): reason = "暂无商品"
	elif not Merchant.presence(campaign.safe_snapshot()): reason = "此时无法与商人交易。"
	elif not bool(offer.unlocked): reason = "这批货品尚未开放。"
	elif int(offer.stock) <= 0: reason = "本周目已售罄。"
	else:
		total = int(offer.price)*int(_quantity.value)
		var coins := int(campaign.safe_snapshot().get("saga",{}).get("coins",0))
		if coins < total: reason = "银钱不足，还需 %d 文。" % (total-coins)
	_buy.text = "购买 %d 件 · %d 文" % [int(_quantity.value),total] if total > 0 else "暂不可购买"
	_buy.disabled = _busy or not _input_armed or not reason.is_empty()
	_quantity.editable = not _busy and not offer.is_empty() and bool(offer.get("unlocked",false)) and int(offer.get("stock",0)) > 0
	_close.disabled = _busy
	for button in _buttons: button.disabled = _busy or not _input_armed
	_status.text = last_error if not last_error.is_empty() else reason
	_status.modulate = Color("ffc9a6") if not last_error.is_empty() or not reason.is_empty() else Color("d7dfca")

func _wire_focus() -> void:
	var controls: Array[Control] = []
	controls.append_array(_buttons)
	controls.append(_quantity.get_line_edit())
	controls.append(_buy)
	controls.append(_close)
	for index in controls.size():
		controls[index].focus_next = controls[index].get_path_to(controls[(index+1)%controls.size()])
		controls[index].focus_previous = controls[index].get_path_to(controls[(index-1+controls.size())%controls.size()])

func _buy_selected() -> void:
	if not _input_armed or _busy or _buy.disabled: return
	_busy = true
	_input_armed = false
	_refresh_actions()
	var result: Dictionary = campaign.buy_merchant_item(world,selected_id,int(_quantity.value))
	_busy = false
	if result.get("ok",false):
		world = campaign.safe_snapshot().world.duplicate(true)
		last_error = "交易已保存。物品已收入行囊。"
		purchased.emit()
	else: last_error = str(result.get("error","交易未能保存，请稍后重试。"))
	_refresh()
	set_process(true)
