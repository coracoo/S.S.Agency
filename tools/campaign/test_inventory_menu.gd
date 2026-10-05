# 夜巡菜单的真实控件与模型往返；必须从隔离入口运行。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Party = preload("res://scripts/campaign/party_panel.gd")
var failures: Array[String] = []
var assertions := 0
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); printerr("FAIL: ", message)
func _run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var session := Session.new()
	check(session.start_new(true).ok, "隔离正式新档可建立")
	var panel = Party.new()
	root.add_child(panel)
	panel.open(session)
	_text_alignment(panel)
	for id in panel._rows:
		check(panel._rows[id].has("hpbar") and panel._rows[id].has("mpbar"), "生图HP/MP条用于每个队员：" + id)
	check(panel.has_method("show_page"), "有队伍、行囊、武具三个独立页面")
	check(panel.has_method("select_item"), "选择道具不直接消费")
	check(panel.has_method("select_equipment"), "选择装备候选不直接提交")
	check(panel.has_method("confirm_item"), "明确确认道具及目标")
	check(panel.has_method("confirm_equipment"), "比较属性后明确确认装备")
	if failures.is_empty():
		await _flows(panel, session)
		await _mouse_keyboard(panel, session)
	panel.free()
	session.close()
	print("INVENTORY_MENU_ASSERTIONS:", assertions, " FAILURES:", failures.size())
	quit(0 if failures.is_empty() else 1)
func _flows(panel, session) -> void:
	var before: Dictionary = session.campaign.safe_snapshot()
	panel.show_page("inventory")
	panel.select_item("healing_potion")
	panel.select_actor("p_guard")
	check(session.campaign.safe_snapshot() == before, "翻页、选道具与选目标均不写档")
	check(panel._hud.item_use.disabled, "满血目标禁用治疗确认")
	check(not panel.confirm_item().ok and session.campaign.safe_snapshot() == before, "重复无效确认不消耗")
	panel.show_page("equipment")
	panel.select_equipment("armor", "")
	check(session.campaign.safe_snapshot() == before, "装备预览不写档")
	check(panel.equipment_preview().hp == before.roster.p_guard.stats.hp - 20, "属性预览来自实际装备模型")
	check(panel.confirm_equipment().ok, "卸下护甲保存成功")
	panel.select_equipment("armor", "standard_armor")
	check(panel.confirm_equipment().ok, "重新装备护甲成功且不免费恢复HP")
	panel.show_page("inventory")
	panel.select_item("healing_potion")
	check(not panel._hud.item_use.disabled, "受伤目标可使用治疗药")
	check(panel.confirm_item().ok, "实际使用道具成功")
	var after: Dictionary = session.campaign.safe_snapshot()
	check(after.inventory.healing_potion == before.inventory.healing_potion - 1, "一次确认只消费一份")
	check(panel._hud.item_use.disabled and not panel.confirm_item().ok, "治疗满后连续确认受保护")
	check(panel._hud.item_description.text.contains("80"), "道具详情显示效果")
	panel.select_item("revival_potion")
	check(panel._hud.item_use.disabled, "复苏药不可用于存活目标")
	panel.select_item("cleansing_powder")
	check(panel._hud.item_use.disabled, "没有可净化状态时禁用")
	for page in ["party", "inventory", "equipment", "party"]:
		panel.show_page(page)
		check(panel.current_page == page and panel._pages[page].visible, "反复切页：" + page)
		for key in panel._pages: check(panel._pages[key].visible == (key == page), "只有一页可交互")
	var resumed := Session.new()
	check(resumed.resume().ok, "保存后重新载入成功")
	check(resumed.campaign.safe_snapshot().inventory == after.inventory and resumed.campaign.safe_snapshot().roster.p_guard == after.roster.p_guard, "装备、HP、库存保存一致")
	resumed.close()
	for resolution in [Vector2i(1920,1080), Vector2i(1280,720), Vector2i(1180,812)]:
		root.size = resolution
		await process_frame
		for page in ["party", "inventory", "equipment"]:
			panel.show_page(page)
			await process_frame
			check(root.get_visible_rect().encloses(panel._hud.close.get_global_rect()), "返回始终在画布内")
			for child in panel._pages[page].get_children():
				if child is Button: check(root.get_visible_rect().encloses(child.get_global_rect()), "页面按钮不越界")

func _click(button: Button) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = motion.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.pressed = false
	root.push_input(event, true)
	await process_frame
func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.pressed = false
	root.push_input(event, true)
	await process_frame
func _mouse_keyboard(panel, session) -> void:
	root.size = Vector2i(1920,1080)
	await process_frame
	panel.toggle_member("p_guard")
	panel.set_notice("当前位置已保存。")
	check(panel._hud.error.text.contains("编队") and panel._hud.error.text.contains("未保存"), "位置保存通知不能遮掉未保存编队提醒")
	panel.toggle_member("p_guard")
	panel.show_page("menu")
	await _click(panel._tabs.equipment)
	check(panel.current_page == "equipment", "真实鼠标点击切换武具页")
	await _click(panel._rows.p_guard.detail)
	await _click(panel._equipment.armor)
	await _click(panel._hud.equip_empty)
	var before: Dictionary = session.campaign.safe_snapshot()
	check(panel.detail_actor_id == "p_guard" and panel.selected_slot == "armor" and panel.selected_equipment_id.is_empty(), "真实鼠标选择角色、槽位与候选")
	check(session.campaign.safe_snapshot() == before, "鼠标预览不写档")
	await _click(panel._hud.equipment_apply)
	check(session.campaign.safe_snapshot().roster.p_guard.equipment.armor == "", "真实鼠标确认卸下")
	await _click(panel._hud.equip_standard)
	await _click(panel._hud.equipment_apply)
	check(session.campaign.safe_snapshot().roster.p_guard.equipment.armor == "standard_armor", "真实鼠标确认装回")
	await _click(panel._tabs.inventory)
	await _click(panel._items.healing_potion)
	var quantity: int = session.campaign.safe_snapshot().inventory.healing_potion
	await _click(panel._hud.item_use)
	check(session.campaign.safe_snapshot().inventory.healing_potion == quantity - 1, "真实鼠标治疗一次只扣一份")
	await _click(panel._hud.item_use)
	check(session.campaign.safe_snapshot().inventory.healing_potion == quantity - 1, "真实鼠标重复点击禁用治疗不扣库存")
	panel._items.healing_potion.grab_focus()
	await _key(KEY_TAB)
	var focused := root.gui_get_focus_owner()
	check(focused != null and focused.is_visible_in_tree() and focused != panel._items.healing_potion, "Tab只进入当前可见交互控件")
	await _key(KEY_ESCAPE)
	check(panel.current_page == "menu", "真实Esc从行囊返回菜单，不写档")
	await _click(panel._tabs.inventory)
	await _click(panel._hud.back)
	check(panel.current_page == "menu", "真实鼠标返回菜单")

func _text_alignment(panel) -> void:
	check(panel._hud.back.get_combined_minimum_size().y >= 52, "窄按钮保持足够厚度，文字不压住生图内边框")
	for id in panel._rows:
		var button: Button = panel._rows[id].detail
		check(button.alignment == HORIZONTAL_ALIGNMENT_CENTER, "队员姓名在独立姓名列中居中：" + id)
		var style: StyleBox = button.get_theme_stylebox("normal")
		var center: float = button.position.x + (style.get_content_margin(SIDE_LEFT) + button.size.x - style.get_content_margin(SIDE_RIGHT)) / 2.0
		check(center >= 380 and center <= 400, "姓名列中心与HP列保留间隔")
		check(panel._rows[id].hp.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT, "HP数值保持一致左对齐")
	for button in panel._items.values() + panel._equipment.values():
		check(button.alignment == HORIZONTAL_ALIGNMENT_CENTER, "道具与装备文字居中，不贴右侧边框")
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var style: StyleBox = button.get_theme_stylebox(state)
			check(style.get_content_margin(SIDE_LEFT) >= 82, "居中文字避开图标：" + state)
			check(style.get_content_margin(SIDE_TOP) == style.get_content_margin(SIDE_BOTTOM) and style.get_content_margin(SIDE_TOP) <= 8, "按钮上下内边距均衡：" + state)
	for button in panel._tabs.values(): check(button.alignment == HORIZONTAL_ALIGNMENT_CENTER, "页签文字保持中心对齐")
