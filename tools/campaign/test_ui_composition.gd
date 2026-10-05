# 第三轮验收：界面退后、信息按需出现；真实主线与战斗，不改模型规则。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
const View = preload("res://scripts/rpg/ui/battle_view.gd")
var failures: Array[String] = []
var assertions := 0
func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.pressed = false; root.push_input(event, true)
	await process_frame
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func check(value: bool, text: String) -> void:
	assertions += 1
	if not value: failures.append(text); printerr("FAIL: ", text)
func _run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var session := Session.new()
	check(session.start_new(true).ok, "真实隔离主线")
	check((await session.prepare_assets()).ok, "真实人物资产会话")
	var stage: Node3D = load(Chapters.scene_path(1)).instantiate()
	root.add_child(stage)
	for frame in 8: await physics_frame
	stage._generation += 1
	if is_instance_valid(stage._dialogue): stage._dialogue.abort(); stage._dialogue.queue_free()
	stage._dialogue = null; stage._arrival_checked = true; stage._resume_explore()
	var visible_buttons: Array = []
	for node in stage._ui_layer.get_child(0).get_children():
		if node is Button and node.is_visible_in_tree(): visible_buttons.append(node)
	check(visible_buttons.size() == 2, "探索仅地图与暂停两个入口")
	stage._mode = "npc"; stage._refresh_hud()
	check(not stage._ui_layer.visible, "对白期间顶HUD与导航提示整层退场")
	stage._mode = "explore"; stage.set_controls_enabled(true)
	stage._process(12.0)
	check(not stage._hud.prompt.text.contains("WASD"), "教学结束后没有常驻移动说明")
	stage._open_pause()
	await process_frame
	var menu: CanvasLayer = stage._party_panel
	var menu_buttons: Array[Button] = []
	var labels: Array[String] = []
	for candidate in menu.find_children("*", "Button", true, false):
		if candidate.is_visible_in_tree() and not candidate.disabled:
			menu_buttons.append(candidate); labels.append(candidate.text)
	check(labels.any(func(text): return text.contains("景深")) and labels.has("返回标题"), "景深与返回标题已收进夜巡菜单且可达")
	for key in [KEY_TAB, KEY_DOWN, KEY_UP, KEY_RIGHT, KEY_LEFT]:
		for step in range(menu_buttons.size() + 1):
			await _key(key)
			check(root.gui_get_focus_owner() in menu_buttons, "夜巡菜单键盘焦点留在可见操作内")
	for window_size in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.size = window_size; await process_frame
		for button in menu_buttons:
			check(root.get_visible_rect().encloses(button.get_global_rect()), "夜巡菜单操作在画布内")
	stage.free()
	for event in ["dialogue:a1", "dialogue:r1", "dialogue:h1"]: check(session.commit_event(session.campaign.safe_snapshot().world, event).ok, "登记既有战前剧情")
	check(session.begin_encounter(session.campaign.safe_snapshot().world, "basin_reflection").ok, "正式遭遇入口")
	var view := View.new(); view.router = session.router
	root.add_child(view)
	for frame in 3: await process_frame
	for row in view._actors.values():
		check(not row.status.text.contains("盾 0") and not row.status.text.contains("无状态"), "没有盾0/无状态占位信息")
		if row.status.text.is_empty():
			check(not row.status.visible, "空状态控件隐藏")
			var visible_bottom: float = row.hpbar.position.y + row.hpbar.size.y
			if row.mp.visible: visible_bottom = maxf(visible_bottom, row.mp.position.y + row.mp.size.y)
			if row.mpbar != null: visible_bottom = maxf(visible_bottom, row.mpbar.position.y + row.mpbar.size.y)
			check(row.card.size.y <= visible_bottom + 28.0, "空状态卡片仅保留生图内框底部留白，不保留状态占位高度")
		if row.intent != null:
			check(row.intent.get_line_count() <= 1, "敌目标只保留简明意图")
			check(row.intent.tooltip_text.contains("预计伤害"), "完整敌意图仍可悬停查阅")
	check(view._hud.queue.get_line_count() == 1 and not view._hud.queue.text.contains("当前·") and not view._hud.queue.text.contains("已行·"), "轮序为单行简名序列")
	check(view._preview_panel.position.y >= 590, "完整预览位于操作区，不遮敌人头部")
	for panel in view._canvas.get_children():
		if panel is Panel and panel.visible:
			check(not (panel.size.x > 1800 and panel.size.y > 200), "底部不再常驻整幅空操作台")
	for button in view._skill_buttons:
		check(button.size == Vector2(336, 132), "批准的双行生图技能卡保留真实内框留白")
		if not button.disabled: check(button.text.split("\n").size() <= 2, "技能摘要最多两行，不侵入装饰边框")
		check(button.tooltip_text.contains("MP") and not button.tooltip_text.is_empty(), "完整技能效果仍可查")
	view._skill_buttons[0].pressed.emit()
	check(view._preview_panel.visible and not view._hud.preview.text.is_empty(), "选中技能后呈现完整详情与预览")
	var target_options: Dictionary = view.command_options(view.pending_command.kind, view.pending_command.ability_id)
	check(not target_options.get("targets", []).is_empty(), "真实首个技能需要选择单体目标")
	if not target_options.get("targets", []).is_empty():
		view.select_target(str(target_options.targets[0]))
		check(view.current_preview().legal and not view._hud.confirm.disabled, "真实单体目标选择后模型预览合法并启用确认")
		check(view._hud.prompt.text.contains("目标已选，可确认") and not view._hud.prompt.text.contains("点击目标"), "单体目标合法选中后提示确认，不继续要求点选")
	for window_size in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.size = window_size; await process_frame
		var buttons: Array = view._skill_buttons.duplicate()
		buttons.append_array(view._basic_buttons.values()); buttons.append_array([view._hud.confirm, view._hud.cancel])
		for button in buttons:
			if not button.is_visible_in_tree(): continue
			check(root.get_visible_rect().encloses(button.get_global_rect()), "战斗操作按钮在可见画布内")
			check(not view._preview_panel.get_global_rect().intersects(button.get_global_rect()), "详情区不覆盖操作热区")
	view.cancel_command()
	view._basic_pressed("item"); await process_frame
	check(view._items.visible, "道具入口可达")
	var pending_before: Dictionary = view.pending_command.duplicate(true)
	var first_target: Button = view._actors.values()[0].target
	check(first_target.focus_mode == Control.FOCUS_NONE, "道具弹层禁用后层目标焦点")
	var click := InputEventMouseButton.new()
	click.position = view._basic_buttons.attack_physical.get_global_rect().get_center()
	click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	root.push_input(click, true)
	click.pressed = false; root.push_input(click, true)
	await process_frame
	check(view._items.visible and view.pending_command == pending_before, "道具遮罩实际拦截后层普攻鼠标点击")
	for step in range(8):
		await _key(KEY_TAB)
		check(view._items.is_ancestor_of(root.gui_get_focus_owner()), "道具Tab不穿透弹层")
	await _key(KEY_ESCAPE)
	check(not view._items.visible and view.pending_command == pending_before, "Esc只关闭道具层，不改模型选择")
	view._toggle_log(); await process_frame
	check(view._log_panel.visible and root.gui_get_focus_owner() != null and view._log_panel.is_ancestor_of(root.gui_get_focus_owner()), "日志可打开并取得内部焦点")
	var state_before: Dictionary = view.engine.snapshot()
	view.select_command("attack_physical")
	check(view.pending_command.is_empty() and view.engine.snapshot() == state_before, "日志模式拒绝后层命令，不改变模型")
	await _key(KEY_ESCAPE)
	check(not view._log_panel.visible, "Esc关闭日志")
	view.free(); session.close()
	print("UI_COMPOSITION:", assertions, " assertions, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
