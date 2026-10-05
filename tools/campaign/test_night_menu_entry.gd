# 在真实夜巡场景验证菜单入口、输入路由与保存失败；只从隔离 Python 入口运行。
extends SceneTree
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
const Campaign = preload("res://scripts/rpg/campaign.gd")
const Session = preload("res://scripts/campaign/chapter_session.gd")
const SaveBase = preload("res://scripts/rpg/save_store.gd")
class FaultStore extends SaveBase:
	var fail_write := false
	var write_attempts := 0
	func _replace_file(temporary: String, destination: String) -> Error:
		write_attempts += 1
		return ERR_FILE_CANT_WRITE if fail_write else super._replace_file(temporary, destination)
var failures: Array[String] = []
var assertions := 0
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1":
		printerr("FAIL: 菜单检查必须先验证隔离 user 目录")
		quit(2)
		return
	_run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		printerr("FAIL: ", message)
func _frames(count: int = 3) -> void:
	for index in range(count): await physics_frame
func _escape() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event)
	await _frames()
	event = InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.keycode = KEY_ESCAPE
	root.push_input(event)
	await _frames()
func _button(node: Node, text: String) -> Button:
	if node is Button and node.text.contains(text): return node
	for child in node.get_children():
		var found := _button(child, text)
		if found != null: return found
	return null
func _silence_intro(stage: Node) -> void:
	stage._generation += 1
	if is_instance_valid(stage._dialogue):
		stage._dialogue.abort()
		stage._dialogue.queue_free()
	stage._dialogue = null
	stage._arrival_checked = true
	stage._resume_explore()
func _run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var store := FaultStore.new()
	var session := Session.new(Campaign.new(null, store, Chapters.SAVE_PATH))
	check(session.start_new(true).ok, "隔离正式会话可建立")
	var assets: Dictionary = await session.prepare_assets()
	check(assets.ok, "正式人物资源可加载")
	if not assets.ok:
		session.close()
		_finish()
		return
	var stage: Node3D = load(Chapters.scene_path(1)).instantiate()
	root.add_child(stage)
	await _frames(5)
	check(stage.ready_for_play, "真实第一夜场景已就绪")
	if stage.ready_for_play:
		_silence_intro(stage)
		await _frames()
		await _flows(stage, session, store)
	stage.free()
	session.close()
	await _frames()
	_finish()
func _finish() -> void:
	print("NIGHT_MENU_ENTRY_ASSERTIONS:", assertions, " FAILURES:", failures.size())
	quit(0 if failures.is_empty() else 1)
func _flows(stage: Node3D, session: RefCounted, store: RefCounted) -> void:
	check(stage._hud.pause.text == "菜单 [Esc]", "探索 HUD 明示菜单入口")
	await _escape()
	check(is_instance_valid(stage._party_panel), "Esc 直接打开绘制菜单而非旧暂停框")
	if not is_instance_valid(stage._party_panel): return
	var panel: CanvasLayer = stage._party_panel
	check(panel.current_page == "menu", "Esc 首屏是夜巡菜单")
	check(stage._mode == "party" and not stage.controls_enabled, "面板活动时锁住探索并保持 party 模式")
	check(not is_instance_valid(stage._modal), "菜单不叠加旧暂停模态")
	check(_button(panel._pages.menu, "行囊") != null and _button(panel._pages.menu, "武具") != null, "菜单明示行囊与武具入口")
	var panel_id := panel.get_instance_id()
	stage._open_pause()
	check(stage._party_panel.get_instance_id() == panel_id, "重复打开不会创建第二层面板")
	var page_labels := {"party": "队伍", "inventory": "行囊", "equipment": "武具"}
	for page in page_labels:
		var entry := _button(panel._pages.menu, page_labels[page])
		check(entry != null and entry.is_visible_in_tree(), "子页在菜单中有可见入口：" + page)
		if entry == null: return
		entry.pressed.emit()
		await _frames()
		check(panel.current_page == page, "实际进入子页面：" + page)
		await _escape()
		check(is_instance_valid(stage._party_panel) and panel.current_page == "menu", "子页面 Esc 只返回菜单：" + page)
		check(stage._mode == "party" and not stage.controls_enabled, "返回菜单后不会穿透恢复移动：" + page)
	var world_before: Dictionary = stage.export_world()
	var disk_before := FileAccess.get_file_as_string(Chapters.SAVE_PATH)
	var geometry_id: int = stage._geometry.get_instance_id()
	var depth_before: bool = stage.hd2d_experiment
	var attempts_before: int = store.write_attempts
	panel.busy = true
	for action in ["save", "depth", "title"]: stage._party_menu_action(action)
	check(store.write_attempts == attempts_before and stage.hd2d_experiment == depth_before and stage._party_panel == panel, "人物加载时菜单保存、景深与离场均被阻断")
	panel.busy = false
	stage._transition_busy = true
	for action in ["save", "depth", "title"]: stage._party_menu_action(action)
	check(store.write_attempts == attempts_before and stage.hd2d_experiment == depth_before and stage._party_panel == panel, "转场时菜单保存、景深与离场均被阻断")
	stage._transition_busy = false
	_button(panel, "景深").pressed.emit()
	check(stage.hd2d_experiment != depth_before and stage._party_panel == panel and panel.current_page == "menu", "切换景深保留当前菜单")
	_button(panel, "景深").pressed.emit()
	check(stage.hd2d_experiment == depth_before and stage._geometry.get_instance_id() == geometry_id, "景深可逆且不重建连续地图")
	check(stage.export_world() == world_before and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == disk_before, "景深切换不改世界或存档")
	var saved_party: Array = session.campaign.safe_snapshot().party.duplicate()
	panel.show_page("party")
	panel.toggle_member(saved_party[-1])
	var pending_party: Array = panel.draft_party.duplicate()
	check(pending_party != saved_party, "真实编队操作产生未提交草稿")
	panel.show_page("menu")
	_button(panel, "保存当前位置").pressed.emit()
	check(stage._party_panel == panel and stage._mode == "party" and not stage.controls_enabled, "保存成功仍留菜单")
	check(panel.last_error == "当前位置已保存。", "位置保存不谎称未提交编队已保存")
	check(session.campaign.safe_snapshot().party == saved_party and panel.draft_party == pending_party, "保存位置不提交或丢弃编队草稿")
	check(JSON.parse_string(FileAccess.get_file_as_string(Chapters.SAVE_PATH)).party == saved_party, "原编队仍保留在真实存档")
	disk_before = FileAccess.get_file_as_string(Chapters.SAVE_PATH)
	var model_before: Dictionary = session.campaign.safe_snapshot()
	store.fail_write = true
	_button(panel, "保存当前位置").pressed.emit()
	check(stage._party_panel == panel and stage._mode == "party" and not stage.controls_enabled, "保存失败留菜单且不恢复探索")
	check(not panel.last_error.is_empty() and not is_instance_valid(stage._modal), "保存失败直接显示在面板，不被遮挡")
	check(session.campaign.safe_snapshot() == model_before and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == disk_before, "保存失败保留模型和原档")
	store.fail_write = false
	_button(panel, "保存当前位置").pressed.emit()
	check(panel.last_error.contains("已保存"), "保存失败可在原菜单重试")
	_button(panel, "返回标题").pressed.emit()
	await _frames()
	check(stage._mode == "title" and is_instance_valid(stage._modal), "返回标题先显示原保存确认")
	check(not is_instance_valid(stage._party_panel), "标题确认前移除会吞输入的菜单覆盖层")
	var cancel := _button(stage._modal, "继续夜巡")
	check(cancel != null, "标题确认可取消")
	if cancel == null: return
	stage._confirm_armed = true
	cancel.pressed.emit()
	await _frames()
	check(is_instance_valid(stage._party_panel), "取消标题确认重回菜单")
	if not is_instance_valid(stage._party_panel): return
	panel = stage._party_panel
	check(panel.current_page == "menu" and stage._mode == "party" and not stage.controls_enabled, "取消后保持菜单输入锁")
	check(panel.draft_party == pending_party, "取消标题确认保留尚未提交的编队草稿")
	check(session.campaign.safe_snapshot().party == saved_party and JSON.parse_string(FileAccess.get_file_as_string(Chapters.SAVE_PATH)).party == saved_party, "取消标题确认不会顺带提交编队草稿")
	panel.show_page("party")
	for actor_id in panel.draft_party.duplicate(): panel.toggle_member(actor_id)
	check(panel.draft_party.is_empty(), "全部取消出战形成待完成的空编队草稿")
	panel.show_page("menu")
	_button(panel, "返回标题").pressed.emit()
	store.fail_write = true
	stage._confirm_armed = true
	_button(stage._modal, "继续夜巡").pressed.emit()
	await _frames()
	check(stage._mode == "error" and not is_instance_valid(stage._party_panel), "取消后重开菜单的保存失败仍被阻断")
	store.fail_write = false
	stage._confirm_armed = true
	stage._modal_buttons[0].pressed.emit()
	await _frames()
	check(is_instance_valid(stage._party_panel), "取消后的入口保存失败可以重试")
	if not is_instance_valid(stage._party_panel): return
	panel = stage._party_panel
	check(panel.draft_party.is_empty(), "空编队草稿经标题取消与保存失败重试仍保留")
	check(session.campaign.safe_snapshot().party == saved_party and JSON.parse_string(FileAccess.get_file_as_string(Chapters.SAVE_PATH)).party == saved_party, "空草稿与重试均不提交真实编队")
	var position_before: Vector3 = stage.player.position
	Input.action_press("approach_right")
	await _escape()
	check(not is_instance_valid(stage._party_panel) and stage._mode == "explore" and stage.controls_enabled, "菜单 Esc 关闭并恢复探索")
	await _frames(4)
	check(stage.player.position.distance_to(position_before) < 0.01, "关闭菜单时按住方向键不会穿透移动")
	Input.action_release("approach_right")
	await _frames()
	stage._hud.pause.pressed.emit()
	await _frames()
	check(is_instance_valid(stage._party_panel) and stage._party_panel.current_page == "menu", "HUD 按钮同样直达菜单")
	check(stage._party_panel.draft_party == saved_party, "真正关闭菜单后再次打开不恢复已放弃的草稿")
	await _escape()
	for mode in ["dialogue", "battle", "ritual", "title"]:
		stage._mode = mode
		stage.set_controls_enabled(false)
		stage._open_pause()
		check(not is_instance_valid(stage._party_panel) and stage._mode == mode, "锁定操作不能打开菜单：" + mode)
	stage._resume_explore()
	store.fail_write = true
	stage._open_party("equipment")
	check(stage._mode == "error" and not stage.controls_enabled and not is_instance_valid(stage._party_panel), "进入整备前保存失败阻止菜单")
	check(FileAccess.get_file_as_string(Chapters.SAVE_PATH) == disk_before, "入口失败不破坏原档")
	store.fail_write = false
	if stage._modal_buttons.is_empty(): return
	stage._confirm_armed = true
	stage._modal_buttons[0].pressed.emit()
	await _frames()
	check(is_instance_valid(stage._party_panel) and stage._party_panel.current_page == "equipment", "入口重试保留指定子页")
	if is_instance_valid(stage._party_panel):
		await stage._party_panel.close_panel()
		await _frames()
	check(stage._mode == "explore" and stage.controls_enabled, "显式关闭子页也能恢复探索")
