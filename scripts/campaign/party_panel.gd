# 正式探索的六选三整备；所有实际资源修改只委托Campaign原子保存。
class_name ChapterPartyPanel
extends CanvasLayer
signal closed
signal menu_action(action: String)
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Factory = preload("res://scripts/rpg/actor_factory.gd")
const Presenter = preload("res://scripts/rpg/ui/battle_presenter.gd")
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
const Art = preload("res://scripts/campaign/presentation/night_menu_art.gd")
const Resolver = preload("res://scripts/rpg/effect_resolver.gd")
const CLASSES: Array[String] = ["swordsman", "ranger", "guard", "mage", "healer", "controller"]
const ITEM_CATEGORIES := {"all": "全部", "heal": "恢复", "support": "辅助"}
var session: RefCounted
var campaign: RefCounted
var last_error := ""
var draft_party: Array[String] = []
var detail_actor_id := "p_swordsman"
var preview_branch_id := ""
var busy := false
var _catalog := Catalog.new()
var _root: Control
var _canvas: Control
var _hud: Dictionary = {}
var _rows: Dictionary = {}
var _skills: Array[Label] = []
var _branches: Dictionary = {}
var _equipment: Dictionary = {}
var _items: Dictionary = {}
var _items_tabs: Dictionary = {}
var _item_list: Control
var current_page := "party"
var selected_item_id := "healing_potion"
var selected_category := "all"
var selected_slot := "weapon"
var selected_equipment_id := "standard_weapon"
var _pages: Dictionary = {}
var _tabs: Dictionary = {}
var _roster_panel: Control
var _gear_list: Control
var _gear_options: Dictionary = {}
var _generation := 0
var _closing := false

func _init() -> void:
	layer = 20
	_catalog.load_all()
func open(value: RefCounted, page: String = "party") -> void:
	current_page = page if page in ["menu", "party", "inventory", "equipment"] else "party"
	session = value
	campaign = session.campaign if session != null else null
	if campaign == null: last_error = "没有正式主线会话"
	else:
		var state: Dictionary = campaign.safe_snapshot()
		draft_party.assign(state.get("party", []))
		if not draft_party.is_empty(): detail_actor_id = draft_party[0]
		preview_branch_id = _detail().get("branch", {}).get("id", "")
	var first_open := _root == null
	if first_open: _build()
	_render()
	if first_open: show_page(current_page)
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	# 只轻微压暗真实探索场景；面板本身使用生图的实色底，保证文字对比。
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.025, 0.28)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	_canvas = Control.new()
	_canvas.size = Vector2(1920, 1080)
	_root.add_child(_canvas)
	Art.panel(_canvas, Rect2(288, 130, 1344, 820))
	_hud.heading = Kit.label(_canvas, "夜巡整备", Rect2(322, 167, 335, 72), 34)
	_hud.heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	for index in 3:
		var page: String = ["party", "inventory", "equipment"][index]
		_tabs[page] = Art.button(_canvas, ["队伍", "行囊", "武具"][index], Rect2(716 + index * 188, 167, 178, 72), show_page.bind(page))
	_hud.close = Art.button(_canvas, "返回探索", Rect2(1392, 167, 204, 72), close_panel)
	_hud.count = Kit.muted(Kit.label(_canvas, "", Rect2(322, 243, 1280, 35), 21))
	for page in ["menu", "party", "inventory", "equipment"]:
		var node := Control.new()
		node.name = "Page_" + page
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas.add_child(node)
		_pages[page] = node
	_roster_panel = Control.new()
	_roster_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_roster_panel)
	Art.panel(_roster_panel, Rect2(318, 277, 356, 582), true)
	_hud.roster_title = Kit.label(_roster_panel, "使用目标", Rect2(338, 288, 320, 38), 25)
	_hud.roster_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for index in CLASSES.size():
		var actor_id := "p_" + CLASSES[index]
		var y := 327 + index * 86
		var row := Art.button(_roster_panel, "", Rect2(334, y, 324, 84), select_actor.bind(actor_id))
		Art.center_text(row, 12, 228)
		row.add_theme_font_size_override("font_size", 20)
		_rows[actor_id] = {"detail": row, "toggle": Art.button(_pages.party, "", Rect2(700, y + 6, 196, 72), toggle_member.bind(actor_id))}
		row.add_theme_font_size_override("font_size", 22)
		Kit.label(_roster_panel, "HP", Rect2(435, y + 20, 32, 25), 18)
		Kit.label(_roster_panel, "MP", Rect2(435, y + 40, 32, 25), 18)
		_rows[actor_id].hpbar = Art.gauge(_roster_panel, "hp", Rect2(469, y + 25, 80, 14))
		_rows[actor_id].mpbar = Art.gauge(_roster_panel, "mp", Rect2(469, y + 45, 80, 14))
		_rows[actor_id].hp = Kit.label(_roster_panel, "", Rect2(557, y + 20, 90, 25), 18)
		_rows[actor_id].mp = Kit.label(_roster_panel, "", Rect2(557, y + 40, 90, 25), 18)
	_build_party()
	_build_inventory()
	_build_equipment()
	_build_menu()
	_hud.back = Art.button(_canvas, "返回菜单 [Esc]", Rect2(1392, 862, 204, 68), back)
	_hud.back.add_theme_font_size_override("font_size", 19)
	_hud.back.custom_minimum_size.y = 68
	_hud.back.size.y = 68
	_hud.error = Kit.label(_canvas, "", Rect2(324, 870, 1040, 42), 20)
	_hud.error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if is_inside_tree():
		get_viewport().size_changed.connect(_resize)
		_resize()
func _build_party() -> void:
	var page: Control = _pages.party
	Art.panel(page, Rect2(914, 277, 686, 582), true)
	_hud.title = Kit.label(page, "", Rect2(940, 294, 638, 39), 26)
	_hud.title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.stats = Kit.label(page, "", Rect2(940, 343, 638, 70), 20)
	for index in 4: _skills.append(Kit.label(page, "", Rect2(940, 439 + index * 42, 638, 39), 19))
	for index in 3:
		var branch: String = ["", "economy", "power"][index]
		_branches[branch] = Art.button(page, "", Rect2(940 + index * 150, 610, 142, 72), preview_branch.bind(branch))
		_branches[branch].add_theme_font_size_override("font_size", 20)
	_hud.branch_apply = Art.button(page, "应用分支", Rect2(1398, 610, 178, 72), apply_branch)
	_hud.branch_apply.add_theme_font_size_override("font_size", 20)
	_hud.branch_preview = Kit.scroll_text(page, Rect2(942, 694, 630, 62), 20)
	_hud.form = Art.button(page, "", Rect2(940, 768, 290, 72), toggle_form)
	_hud.form.add_theme_font_size_override("font_size", 20)
	_hud.apply = Art.button(page, "保存三人编队", Rect2(1250, 768, 326, 72), apply_party, true)
func _build_inventory() -> void:
	var page: Control = _pages.inventory
	# 顶排分类页签 + 左侧随身道具总览列表 + 右侧效果与目标预览，与武具页同一套交互。
	for index in 3:
		var category: String = ["all", "heal", "support"][index]
		_items_tabs[category] = Art.button(page, ITEM_CATEGORIES[category], Rect2(688 + index * 308, 282, 288, 68), select_category.bind(category))
		_items_tabs[category].add_theme_font_size_override("font_size", 20)
	Art.panel(page, Rect2(688, 362, 380, 498), true)
	Kit.label(page, "随身道具 · 点选预览后使用", Rect2(704, 372, 348, 32), 22).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(704, 412)
	scroll.size = Vector2(348, 434)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_item_list = VBoxContainer.new()
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_list.add_theme_constant_override("separation", 0)
	scroll.add_child(_item_list)
	Art.panel(page, Rect2(1080, 362, 520, 498), true)
	_hud.item_title = Kit.label(page, "", Rect2(1100, 376, 480, 40), 26)
	_hud.item_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.item_icon = Art.icon(page, "healing_potion", Rect2(1100, 428, 96, 96))
	_hud.item_description = Kit.label(page, "", Rect2(1210, 428, 370, 104), 20)
	_hud.item_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.item_target = Kit.label(page, "", Rect2(1100, 556, 480, 118), 24)
	_hud.item_reason = Kit.label(page, "", Rect2(1100, 682, 480, 66), 19)
	_hud.item_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.item_use = Art.button(page, "使用道具", Rect2(1100, 758, 480, 72), confirm_item, true)
func _build_equipment() -> void:
	var page: Control = _pages.equipment
	# 顶排槽位页签 + 左侧持有装备总览列表 + 右侧属性变化预览与确认。
	for index in 3:
		var slot: String = ["weapon", "armor", "accessory"][index]
		_equipment[slot] = Art.button(page, "", Rect2(688 + index * 308, 282, 288, 68), select_slot.bind(slot))
		_equipment[slot].add_theme_font_size_override("font_size", 20)
		Art.center_text(_equipment[slot], 86, 20)
		Art.icon(page, slot, Rect2(712 + index * 308, 302, 28, 28))
	Art.panel(page, Rect2(688, 362, 380, 498), true)
	Kit.label(page, "持有装备 · 点选预览后确认", Rect2(704, 372, 348, 32), 22).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gear_list = Control.new()
	_gear_list.position = Vector2(704, 412)
	_gear_list.size = Vector2(348, 434)
	page.add_child(_gear_list)
	Art.panel(page, Rect2(1080, 362, 520, 498), true)
	_hud.equipment_title = Kit.label(page, "", Rect2(1100, 376, 480, 40), 26)
	_hud.equipment_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.equipment_description = Kit.label(page, "", Rect2(1100, 420, 480, 34), 19)
	_hud.equipment_stats = Kit.label(page, "", Rect2(1110, 462, 460, 276), 22)
	_hud.equipment_note = Kit.label(page, "", Rect2(1100, 744, 480, 48), 18)
	_hud.equipment_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.equipment_apply = Art.button(page, "确认更换", Rect2(1100, 798, 480, 56), confirm_equipment, true)
func _build_menu() -> void:
	var page: Control = _pages.menu
	Art.panel(page, Rect2(324, 280, 620, 578), true)
	Kit.label(page, "今夜同行", Rect2(358, 305, 540, 44), 28).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.menu_summary = Kit.label(page, "", Rect2(360, 378, 540, 330), 25)
	Kit.muted(Kit.label(page, "WASD 行走  ·  E 调查  ·  M 地图", Rect2(358, 781, 554, 40), 20))
	var actions := [["行囊 · 使用道具", "inventory"], ["武具 · 查看与更换", "equipment"], ["队伍 · 编队与形态", "party"]]
	for index in actions.size():
		Art.button(page, actions[index][0], Rect2(982, 298 + index * 81, 576, 66), show_page.bind(actions[index][1]))
	_hud.rest = Art.button(page, "休息 · 全员恢复", Rect2(982, 541, 576, 60), rest_party)
	_hud.save = Art.button(page, "保存当前位置", Rect2(982, 622, 280, 72), _emit_menu.bind("save"))
	_hud.depth = Art.button(page, "景深", Rect2(1278, 622, 280, 72), _emit_menu.bind("depth"))
	Art.button(page, "返回标题", Rect2(982, 703, 576, 72), _emit_menu.bind("title"))
	Art.button(page, "继续探索", Rect2(982, 784, 576, 72), close_panel, true)
func show_page(page: String) -> void:
	if busy or not _pages.has(page): return
	current_page = page
	last_error = ""
	_render()
	if page == "inventory":
		var focus_item: Button = _items.get(selected_item_id)
		if focus_item != null: focus_item.grab_focus()
		else: _hud.close.grab_focus()
	elif page == "equipment": _equipment[selected_slot].grab_focus()
	elif page == "party" and _rows.has(detail_actor_id): _rows[detail_actor_id].detail.grab_focus()
	else: _hud.close.grab_focus()
func back() -> void:
	if current_page == "menu": close_panel()
	else: show_page("menu")
func update_menu(depth: bool) -> void:
	_hud.depth.text = "景深：开" if depth else "景深：关"
func set_notice(message: String) -> void:
	last_error = message
	_render()
func _emit_menu(action: String) -> void:
	if not busy: menu_action.emit(action)
func _ready() -> void:
	if _root != null:
		if not get_viewport().size_changed.is_connected(_resize): get_viewport().size_changed.connect(_resize)
		_resize()
func _resize() -> void:
	var available := get_viewport().get_visible_rect().size
	var factor := minf(available.x / 1920.0, available.y / 1080.0)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (available - Vector2(1920, 1080) * factor) / 2.0
func _detail() -> Dictionary:
	return campaign.safe_snapshot().get("roster", {}).get(detail_actor_id, {}) if campaign != null else {}
func select_actor(actor_id: String) -> void:
	if busy or campaign == null or not campaign.safe_snapshot().roster.has(actor_id): return
	detail_actor_id = actor_id
	preview_branch_id = _detail().branch.get("id", "")
	selected_equipment_id = _detail().equipment.get(selected_slot, "")
	_render()
func toggle_member(actor_id: String) -> void:
	if busy or campaign == null or not campaign.can_prepare() or not campaign.safe_snapshot().roster.has(actor_id): return
	if draft_party.has(actor_id): draft_party.erase(actor_id)
	elif draft_party.size() < 3: draft_party.append(actor_id)
	_render()
func apply_party() -> Dictionary:
	if busy: return _failure("人物资源正在加载")
	if draft_party.size() != 3 or draft_party[0] == draft_party[1] or draft_party[0] == draft_party[2] or draft_party[1] == draft_party[2]: return _failure("请选择三名不同队员")
	var result: Dictionary = campaign.set_party(draft_party)
	last_error = result.get("error", "")
	if result.ok: await _prepare_selected()
	_render()
	return result
func toggle_form() -> Dictionary:
	if busy or _detail().get("identity_id") != "homura": return _failure("仅焰华有双形态")
	var target := "sword" if _detail().form_id == "mage" else "mage"
	var result: Dictionary = campaign.set_form(detail_actor_id, target)
	last_error = result.get("error", "")
	if result.ok: await _prepare_selected()
	_render()
	return result
func preview_branch(branch: String) -> void:
	if busy: return
	preview_branch_id = "duration" if branch == "economy" and _detail().get("class_id") == "ranger" else branch
	_render()
func apply_branch() -> Dictionary:
	if busy or campaign == null: return _failure("整备操作暂不可用，请等待人物加载")
	return _show_response(campaign.set_branch(detail_actor_id, preview_branch_id))
func toggle_equipment(slot: String) -> Dictionary:
	if busy or campaign == null: return _failure("整备操作暂不可用，请等待人物加载")
	var actor := _detail()
	return _show_response(campaign.equip(detail_actor_id, slot, Factory.STANDARD[slot] if actor.equipment.get(slot, "").is_empty() else ""))
func use_item(item_id: String) -> Dictionary:
	if busy or campaign == null: return _failure("整备操作暂不可用，请等待人物加载")
	return _show_response(campaign.use_item_outside(item_id, detail_actor_id))
func rest_party() -> Dictionary:
	if busy or campaign == null: return _failure("整备操作暂不可用，请等待人物加载")
	return _show_response(campaign.rest())
func _show_response(result: Dictionary) -> Dictionary:
	last_error = result.get("error", "")
	_render()
	return result
func _failure(message: String) -> Dictionary:
	return _show_response({"ok": false, "error": message})
func _prepare_selected() -> bool:
	busy = true
	_generation += 1
	var generation := _generation
	_render()
	var result: Dictionary = await session.prepare_assets()
	if generation != _generation or not is_instance_valid(_root): return false
	busy = false
	last_error = result.get("error", "")
	return result.get("ok", false)
func close_panel() -> void:
	if busy or _closing: return
	_closing = true
	# 关闭前重新确认当前已保存三人对应的资源，加载失败留在整备可重试。
	if session != null and not await _prepare_selected():
		_closing = false
		_render()
		return
	closed.emit()
	queue_free()
func _render() -> void:
	if _root == null: return
	for page in _pages: _pages[page].visible = page == current_page
	_roster_panel.visible = current_page != "menu"
	for page in _tabs:
		Art.selected(_tabs[page], page == current_page)
		_tabs[page].disabled = busy
	_hud.back.visible = current_page != "menu"
	_hud.close.disabled = busy
	_hud.back.disabled = busy
	_hud.heading.text = "夜巡菜单" if current_page == "menu" else "夜巡整备"
	var actor := _detail()
	if actor.is_empty():
		_hud.error.text = last_error
		return
	var state: Dictionary = campaign.safe_snapshot()
	var editable: bool = not busy and campaign.can_prepare()
	_hud.count.text = "出战 %d / 3　·　队伍 / 道具 / 装备变更成功后自动保存" % draft_party.size()
	_hud.apply.disabled = not editable or draft_party.size() != 3 or draft_party == state.party
	_hud.rest.disabled = not editable
	_hud.save.disabled = busy
	_hud.depth.disabled = busy
	_hud.roster_title.text = "使用目标" if current_page == "inventory" else "查看队员"
	for id in _rows:
		var row: Dictionary = _rows[id]
		var entry: Dictionary = state.roster[id]
		row.detail.text = actor_name(entry)
		row.hpbar.max_value = entry.stats.hp
		row.hpbar.value = entry.hp
		row.mpbar.max_value = maxi(1, entry.stats.mp)
		row.mpbar.value = entry.mp
		row.hp.text = "%d/%d" % [entry.hp, entry.stats.hp]
		row.mp.text = "%d/%d" % [entry.mp, entry.stats.mp]
		row.detail.disabled = busy
		row.detail.tooltip_text = item_reason(selected_item_id, id) if current_page == "inventory" else actor_name(entry)
		Art.selected(row.detail, id == detail_actor_id)
		row.toggle.text = "✓ 出战" if draft_party.has(id) else "+ 加入"
		Art.selected(row.toggle, draft_party.has(id))
		row.toggle.disabled = not editable or (not draft_party.has(id) and draft_party.size() >= 3)
	_hud.title.text = "%s · L%d · %s" % [actor_name(actor), actor.level, _catalog.get_definition("classes", actor.get("active_class_id", actor.class_id)).name]
	_hud.stats.text = "HP %d/%d　MP %d/%d\n攻击 %d　术攻 %d　防御 %d　术防 %d　速度 %d" % [actor.hp, actor.stats.hp, actor.mp, actor.stats.mp, actor.stats.atk, actor.stats.matk, actor.stats.def, actor.stats.mdef, actor.stats.spd]
	_hud.form.visible = actor.identity_id == "homura"
	var mage_unlocked: bool = actor.get("unlocked_forms", [actor.form_id]).has("mage")
	_hud.form.disabled = not editable or not mage_unlocked
	_hud.form.text = ("切换剑士形态" if actor.form_id == "mage" else "切换法师形态") if mage_unlocked else "法师形态未解锁"
	_hud.form.tooltip_text = "第一夜胜利解锁；切换共享HP、MP、状态、装备，不免费恢复"
	for index in 4:
		var skill: Dictionary = _catalog.skill_for(actor, actor.skill_ids[index])
		var line := "%s%s　MP%d · CD%d　%s" % ["L%d锁定 · " % skill.unlock_level if actor.level < skill.unlock_level else "", skill.name, skill.mp_cost, skill.cooldown, Presenter.ability_summary(skill, {}, _catalog)]
		_skills[index].text = line
		_skills[index].text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_skills[index].tooltip_text = line
	for id in _branches:
		var actual: String = "duration" if id == "economy" and actor.class_id == "ranger" else id
		_branches[id].text = {"": "无分支", "economy": "节约", "duration": "持续", "power": "强度"}[actual]
		_branches[id].disabled = busy
		Art.selected(_branches[id], actual == preview_branch_id)
	_hud.branch_apply.disabled = not editable or (actor.level < 6 and not preview_branch_id.is_empty()) or preview_branch_id == actor.branch.get("id", "")
	_hud.branch_preview.text = Presenter.branch_preview(actor, preview_branch_id, _catalog)
	_render_inventory(state)
	_render_equipment(actor, editable)
	var summary := ""
	for id in state.party:
		var entry: Dictionary = state.roster[id]
		summary += "%s　Lv.%d\nHP %d/%d　MP %d/%d\n\n" % [actor_name(entry), entry.level, entry.hp, entry.stats.hp, entry.mp, entry.stats.mp]
	_hud.menu_summary.text = summary
	_hud.error.text = "正在加载当前三人资源…" if busy else last_error
	if not busy and draft_party != state.party:
		_hud.error.text = "编队草稿未保存：请在队伍页确认；离开会放弃草稿。" + last_error
func actor_name(actor: Dictionary) -> String:
	return Presenter.presentation_name(actor, _catalog.get_definition("classes", actor.class_id))
func select_item(item_id: String) -> void:
	if busy or not _items.has(item_id): return
	selected_item_id = item_id
	last_error = ""
	_render()
func select_category(category: String) -> void:
	if busy or not ITEM_CATEGORIES.has(category): return
	selected_category = category
	last_error = ""
	_render()
static func _item_category(item: Dictionary) -> String:
	for effect in item.get("effects", []):
		if str(effect.get("type", "")) in ["shield", "cleanse"]: return "support"
	return "heal"
static func _item_effect_summary(item: Dictionary) -> String:
	var parts: Array[String] = []
	for effect in item.get("effects", []):
		match str(effect.get("type", "")):
			"restore_hp": parts.append("HP+%d" % int(effect.get("fixed", 0)))
			"restore_mp": parts.append("MP+%d" % int(effect.get("fixed", 0)))
			"heal": parts.append("治疗%d" % int(effect.get("fixed", 0)))
			"revive": parts.append("复苏%d%%" % roundi(float(effect.get("fraction", 0)) * 100))
			"cleanse": parts.append("净化")
			"shield": parts.append("护盾%d·%d回合" % [int(effect.get("fixed", 0)), int(effect.get("duration", 0))])
	return " ".join(parts)
func item_reason(item_id: String, target_id: String) -> String:
	if busy: return "请等待人物资源加载"
	if campaign == null or not campaign.can_use_outside_items(): return "当前无法使用战外道具"
	var state: Dictionary = campaign.safe_snapshot()
	var item: Dictionary = _catalog.get_definition("items", item_id)
	if item.is_empty() or not state.roster.has(target_id): return "请选择道具与队员"
	if state.inventory.get(item_id, 0) <= 0: return "道具已用尽"
	var actor: Dictionary = state.roster[target_id]
	if item.target_rule == "fallen_ally" and actor.hp > 0: return "只能用于倒地队员"
	if item.target_rule != "fallen_ally" and actor.hp <= 0: return "请先复苏该队员"
	var after := _item_result(item_id, target_id)
	if after == actor:
		if item_id == "healing_potion": return "HP已满，无需使用"
		if item_id in ["mana_potion", "energy_tea"]: return "MP已满，无需使用"
		if item_id == "cleansing_powder": return "没有可净化的负面状态"
		return "该道具没有有效作用"
	return ""
func _item_result(item_id: String, target_id: String) -> Dictionary:
	var state: Dictionary = campaign.safe_snapshot()
	var simulation := {"actors": state.roster, "round": 0}
	Resolver.resolve(simulation, {"actor_id": target_id, "kind": "item", "ability_id": item_id, "target_ids": [target_id]}, _catalog, null)
	return simulation.actors[target_id]
func _item_description(item: Dictionary) -> String:
	var lines: Array[String] = []
	for effect in item.effects:
		match effect.type:
			"restore_hp": lines.append("恢复 HP %d" % effect.fixed)
			"restore_mp": lines.append("恢复 MP %d" % effect.fixed)
			"heal": lines.append("治疗 HP %d" % int(effect.get("fixed", 0)))
			"revive": lines.append("复苏倒地队员\n恢复 %d%% HP" % roundi(effect.fraction * 100))
			"cleanse": lines.append("清除可净化的\n负面状态")
			"shield": lines.append("获得护盾 %d\n持续 %d 回合" % [int(effect.get("fixed", 0)), int(effect.get("duration", 0))])
	return "\n".join(lines)
func _render_inventory(state: Dictionary) -> void:
	for category in _items_tabs:
		_items_tabs[category].disabled = busy
		Art.selected(_items_tabs[category], category == selected_category)
	# 分类总览：catalog 全部道具一行一件（名称 ×数量 效果摘要），点选即预览，×0 置灰。
	for child in _item_list.get_children(): child.queue_free()
	_items = {}
	var index := 0
	for item in _catalog.get_all("items"):
		if selected_category != "all" and _item_category(item) != selected_category: continue
		var count: int = state.inventory.get(item.id, 0)
		var label := "%s　×%d　%s" % [item.name, count, _item_effect_summary(item)]
		var button := Art.button(_item_list, label, Rect2(0, 0, 348, 64), select_item.bind(item.id))
		button.add_theme_font_size_override("font_size", 17)
		button.disabled = busy or count <= 0
		Art.selected(button, item.id == selected_item_id)
		_items[item.id] = button
		index += 1
	var item: Dictionary = _catalog.get_definition("items", selected_item_id)
	var actor: Dictionary = state.roster[detail_actor_id]
	var reason := item_reason(selected_item_id, detail_actor_id)
	_hud.item_title.text = item.name
	_hud.item_icon.texture = Art.texture(selected_item_id)
	_hud.item_description.text = _item_description(item)
	var result: Dictionary = _item_result(selected_item_id, detail_actor_id) if reason.is_empty() else actor
	var changes: Array[String] = []
	if result.hp != actor.hp: changes.append("HP　%d → %d" % [actor.hp, result.hp])
	if result.mp != actor.mp: changes.append("MP　%d → %d" % [actor.mp, result.mp])
	var status_delta: int = result.statuses.size() - actor.statuses.size()
	if status_delta > 0: changes.append("获得增益状态　%d 项" % status_delta)
	elif status_delta < 0: changes.append("移除负面状态　%d 项" % -status_delta)
	var count: int = state.inventory.get(selected_item_id, 0)
	_hud.item_target.text = "使用目标：%s\n\n%s\n数量　%d → %d" % [actor_name(actor), ("\n".join(changes) if not changes.is_empty() else "无变化"), count, count - 1 if reason.is_empty() else count]
	_hud.item_reason.text = "确认后对所选队员使用 1 份，并自动保存。" if reason.is_empty() else reason
	_hud.item_use.disabled = not reason.is_empty()
	_hud.item_use.text = "使用于「%s」" % actor_name(actor)
func confirm_item() -> Dictionary:
	var reason := item_reason(selected_item_id, detail_actor_id)
	if not reason.is_empty(): return _failure(reason)
	var result := use_item(selected_item_id)
	if result.ok: set_notice("已对%s使用%s，库存与状态已保存。" % [actor_name(_detail()), _catalog.get_definition("items", selected_item_id).name])
	return result
func select_slot(slot: String) -> void:
	if busy or not Factory.STANDARD.has(slot): return
	selected_slot = slot
	selected_equipment_id = _detail().equipment.get(slot, "")
	last_error = ""
	_render()
func select_standard_equipment() -> void:
	select_equipment(selected_slot, Factory.STANDARD[selected_slot])

const GEAR_STAT_LABELS := {"hp": "生命", "mp": "灵力", "atk": "攻击", "matk": "术攻", "def": "防御", "mdef": "术防", "spd": "速度"}

static func gear_stat_summary(stats: Dictionary) -> String:
	var parts: Array[String] = []
	for key in Factory.STAT_KEYS:
		if int(stats.get(key, 0)) != 0: parts.append("%s %+d" % [GEAR_STAT_LABELS.get(key, key), int(stats[key])])
	return " ".join(parts)

func select_equipment(slot: String, equipment_id: String) -> void:
	if busy: return
	if slot.is_empty(): slot = selected_slot
	if not Factory.STANDARD.has(slot): return
	if not equipment_id.is_empty() and _catalog.get_definition("equipment", equipment_id).get("slot", "") != slot: return
	selected_slot = slot
	selected_equipment_id = equipment_id
	last_error = ""
	_render()
func equipment_preview() -> Dictionary:
	var actor := _detail()
	var equipment: Dictionary = actor.equipment.duplicate(true)
	equipment[selected_slot] = selected_equipment_id
	return Factory.new(_catalog).stats_for(actor.class_id, actor.level, equipment)
func _render_equipment(actor: Dictionary, editable: bool) -> void:
	var names := {"weapon": "武器", "armor": "护甲", "accessory": "饰品"}
	for slot in _equipment:
		var id: String = actor.equipment.get(slot, "")
		_equipment[slot].text = "%s · %s" % [names[slot], "未装备" if id.is_empty() else _catalog.get_definition("equipment", id).name]
		_equipment[slot].disabled = busy
		Art.selected(_equipment[slot], slot == selected_slot)
	# 持有装备总览：当前槽位全部持有装备一行一件，点选即预览，卸下作为最后一行。
	for child in _gear_list.get_children(): child.queue_free()
	_gear_options = {}
	var rows: Array[Dictionary] = []
	var owned_gear: Dictionary = campaign.safe_snapshot().get("gear", {})
	for gear_id in owned_gear:
		if int(owned_gear.get(gear_id, 0)) < 1: continue
		var definition: Dictionary = _catalog.get_definition("equipment", gear_id)
		if definition.is_empty() or definition.slot != selected_slot: continue
		var equipped_now: bool = actor.equipment.get(selected_slot, "") == gear_id
		rows.append({"id": gear_id, "sort": definition.name, "label": ("✓ " if equipped_now else "") + "%s　%s" % [definition.name, gear_stat_summary(definition.get("stats", {}))]})
	rows.sort_custom(func(a, b): return str(a.sort) < str(b.sort))
	rows.append({"id": "", "sort": "￿", "label": "（卸下此槽装备）"})
	for index in rows.size():
		var row: Dictionary = rows[index]
		var button := Art.button(_gear_list, row.label, Rect2(0, index * 72, 348, 64), select_equipment.bind(selected_slot, row.id))
		button.add_theme_font_size_override("font_size", 17)
		button.disabled = busy
		Art.selected(button, row.id == selected_equipment_id)
		_gear_options[row.id] = button
	_hud.equip_standard = _gear_options.get(Factory.STANDARD[selected_slot])
	_hud.equip_empty = _gear_options.get("")
	_hud.equipment_title.text = "%s · %s" % [actor_name(actor), names[selected_slot]]
	_hud.equipment_description.text = "预览：" + ("卸下装备" if selected_equipment_id.is_empty() else _catalog.get_definition("equipment", selected_equipment_id).name)
	var preview := equipment_preview()
	var labels := {"hp": "生命上限", "mp": "灵力上限", "atk": "攻击", "matk": "术攻", "def": "防御", "mdef": "术防", "spd": "速度"}
	var lines: Array[String] = []
	for key in Factory.STAT_KEYS:
		var delta: int = preview[key] - actor.stats[key]
		lines.append("%s　%d → %d　%s" % [labels[key], actor.stats[key], preview[key], ("%+d" % delta) if delta != 0 else "—"])
	_hud.equipment_stats.text = "\n".join(lines)
	var same: bool = actor.equipment.get(selected_slot, "") == selected_equipment_id
	_hud.equipment_note.text = "当前已是此配装" if same else "更换自动保存；上限降低会截短当前HP/MP，装回不会免费恢复。"
	if not editable: _hud.equipment_note.text = "当前地点不能更换装备"
	_hud.equipment_apply.disabled = not editable or same
	_hud.equipment_apply.text = "确认卸下" if selected_equipment_id.is_empty() else "确认装备"
func confirm_equipment() -> Dictionary:
	if busy or campaign == null: return _failure("当前无法更换装备")
	if _detail().equipment.get(selected_slot, "") == selected_equipment_id: return _failure("当前已是此配装")
	var result: Dictionary = campaign.equip(detail_actor_id, selected_slot, selected_equipment_id)
	_show_response(result)
	if result.ok: set_notice("%s的装备与属性已保存。" % actor_name(_detail()))
	return result
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		back()
func _exit_tree() -> void:
	_generation += 1
