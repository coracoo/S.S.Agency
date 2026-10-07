# 正式装配页真实会话回归；只由核验 user:// 的 Python 入口运行。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Party = preload("res://scripts/campaign/party_panel.gd")
const Presenter = preload("res://scripts/rpg/ui/battle_presenter.gd")
const LoadoutPanel = preload("res://scripts/campaign/loadout_panel.gd")
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
	# 排版检查不写档；模型回归仍只使用下方的真实正式会话。
	var layout := LoadoutPanel.new()
	root.add_child(layout)
	layout._build()
	await process_frame
	for child in layout.get_children():
		if not child is Button: continue
		var style: StyleBox = child.get_theme_stylebox("normal")
		var line_height: float = child.get_theme_font("font").get_height(child.get_theme_font_size("font_size"))
		check(line_height + style.content_margin_top + style.content_margin_bottom <= child.size.y, "装配按钮有完整可读行高：" + child.text)
	layout.free()
	var session := Session.new()
	check(session.start_new(true).ok, "正式新档建立")
	var before: Dictionary = session.campaign.safe_snapshot()
	check(before.get("schema_version") == 3 and before.roster.p_guard.has("build"), "正式新档使用真实无等级构筑模型")
	if not failures.is_empty():
		session.close()
		_finish()
		return
	var panel = Party.new()
	root.add_child(panel)
	panel.open(session, "menu")
	await process_frame
	check(not panel._menu_cards[0].name.text.contains("Lv") and panel._menu_cards[0].name.text.contains("速度"), "菜单显示速度而非等级")
	panel.show_page("party")
	check(not panel._hud.branch_apply.visible, "正式角色不显示旧等级分支操作")
	panel.select_actor("p_guard")
	panel.show_page("loadout")
	check(panel.current_page == "loadout", "正式整备可进入装配页")
	if panel.current_page != "loadout":
		panel.free(); session.close(); _finish(); return
	var editor = panel._loadout
	check(editor.is_visible_in_tree() and editor.get_viewport().gui_get_focus_owner() != null, "装配页有键盘初始焦点")
	editor._slots.passive[0].grab_focus()
	await _key(KEY_ENTER)
	check(editor.selected_type == "passive", "键盘确认可以选中被动槽")
	editor._cards.light_step.grab_focus()
	await _key(KEY_ENTER)
	check(editor.draft.passive == ["light_step"], "选择被动只改草稿")
	check(session.campaign.safe_snapshot() == before, "预览不写玩家模型")
	check(editor.preview.stats.spd == before.roster.p_guard.stats.spd + 3 and editor.preview.stats.def == before.roster.p_guard.stats.def - 2, "被动预览展示真实速度与防御取舍")
	editor.cancel_changes()
	check(editor.draft.passive.is_empty() and session.campaign.safe_snapshot() == before, "取消恢复已保存配装且不写档")
	editor.select_slot("passive", 0)
	editor.select_card("light_step")
	check(editor.apply_changes().ok, "确认装配调用正式模型保存")
	var applied: Dictionary = session.campaign.safe_snapshot()
	check(applied.roster.p_guard.build.passive == ["light_step"] and applied.cards == before.cards, "应用被动保留收藏数量")
	check(applied.roster.p_guard.stats.spd == before.roster.p_guard.stats.spd + 3, "保存属性与预览一致")
	editor.select_slot("active", 0)
	editor.select_card("firebolt")
	check(not editor.preview.ok and editor._apply.disabled and not editor._reason.text.is_empty(), "武器不兼容显示原因并禁止应用")
	check(not editor.apply_changes().ok and session.campaign.safe_snapshot() == applied, "非法草稿不能写档")
	editor.cancel_changes()
	editor.select_slot("active", 1)
	editor.select_card("sweep")
	check(not editor.preview.ok and editor._capacity.text.contains("11/10") and editor._apply.disabled, "跨身份合法武器仍受主动容量上限限制")
	editor.cancel_changes()
	editor.select_slot("active", 0)
	editor.select_card("heavy_slash")
	check(editor.preview.ok and editor.apply_changes().ok, "刀盾可准备其他身份的刃系技能")
	check(session.campaign.safe_snapshot().roster.p_guard.skill_ids[0] == "heavy_slash", "跨身份主动进入真实当前技能列表")
	editor.select_slot("passive", 1)
	editor.select_card("steady_breath")
	panel.show_page("loadout")
	check(editor.draft.passive == ["light_step", "steady_breath"], "重复点击当前装配页不会丢失草稿")
	panel.select_actor("p_swordsman")
	check(editor.draft.passive.is_empty(), "切换队员不把前一人的未应用草稿带过去")
	editor.select_slot("passive", 0)
	editor.select_card("light_step")
	check(editor.apply_changes().ok and session.campaign.safe_snapshot().cards == before.cards, "同一收藏可供两名队员准备且不消耗")
	panel.select_actor("p_guard")
	panel.show_page("equipment")
	panel.select_equipment("weapon", "")
	check(panel._hud.equipment_apply.disabled and panel.equipment_preview().is_empty(), "非法卸武器没有伪造属性且禁用确认")
	check(panel._hud.equipment_note.text.contains("技能"), "武器冲突提示先调整技能")
	panel.select_actor("p_mage")
	panel.show_page("loadout")
	var mage_before: Dictionary = session.campaign.safe_snapshot().roster.p_mage
	editor.select_group("mage")
	check(session.campaign.safe_snapshot().roster.p_mage.form_id == mage_before.form_id, "查看备用形态配置不会实际切形")
	check(panel._hud.form.disabled, "尚未解锁法师形态时不能实际切形")
	var guide := Presenter.character_guide(mage_before, panel._catalog)
	check(not guide.contains("L3") and not guide.contains("L6") and not guide.contains("L9"), "正式身份专长无未来等级副本")
	var guard: Dictionary = session.campaign.safe_snapshot().roster.p_guard.duplicate(true)
	guard.build.active.default = []
	guard.skill_ids = []
	check(not Presenter.character_guide(guard, panel._catalog).is_empty(), "未装备专长技能仍可安全查看身份说明")
	var state := {"actors": {guard.actor_id: guard}, "active_actor_id": guard.actor_id}
	var projected := Presenter.present(state, panel._catalog)
	check(not projected.actors[0].has("level") and projected.actors[0].spd == guard.stats.spd, "正式战斗行只投影速度而不读取level")
	for resolution in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(1180, 812)]:
		root.size = resolution
		await process_frame
		check(root.get_visible_rect().encloses(editor._apply.get_global_rect()) and root.get_visible_rect().encloses(editor._cancel.get_global_rect()), "装配确认与取消在画布内：" + str(resolution))
	var resumed := Session.new()
	check(resumed.resume().ok, "装配后正式续档成功")
	check(resumed.campaign.safe_snapshot().roster.p_guard.build.passive == ["light_step"], "续档保留已应用配装")
	resumed.close()
	panel.free()
	session.close()
	_finish()

func _finish() -> void:
	print("LOADOUT_MENU: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.pressed = false
	root.push_input(event, true)
	await process_frame
