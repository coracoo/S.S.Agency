# 试玩入口与暂停契约只在已核验的临时 user:// 中执行。
extends RefCounted
const F = preload("res://tools/rpg/fixtures.gd")
const Session = preload("res://scripts/exploration_3d/approach_session.gd")
const Store = preload("res://scripts/rpg/save_store.gd")
const World = preload("res://scripts/exploration_3d/world_snapshot.gd")
const A = preload("res://tools/rpg/approach_fixtures.gd")
const ThemeData = preload("res://scripts/ui/theme.gd")
const Title = preload("res://scripts/scenes/title_scene.gd")

class ControlledSession extends Session:
	var fail_assets := false
	var prepare_count := 0
	func prepare_assets() -> Dictionary:
		prepare_count += 1
		var tree := Engine.get_main_loop() as SceneTree
		await tree.process_frame
		return {"ok": not fail_assets, "error": "测试资源加载失败" if fail_assets else ""}

class ReadFailStore extends Store:
	func load_safe(_path: String = Store.DEFAULT_PATH) -> Dictionary:
		return {"ok": false, "error": "无法读取安全存档", "code": ERR_FILE_CANT_READ}

class NavigationMenu extends "res://scripts/exploration_3d/trial_menu.gd":
	var navigation_paths: Array[String] = []
	var navigation_error := false
	var detach_on_navigation := false
	var input_was_handled := false
	func _navigate_to(path: String) -> Dictionary:
		navigation_paths.append(path)
		if is_inside_tree(): input_was_handled = get_viewport().is_input_handled()
		if navigation_error: return {"ok": false, "error": "测试场景重建失败"}
		if detach_on_navigation and is_inside_tree(): get_parent().remove_child(self)
		return {"ok": true, "error": "", "next_scene": path}

static func run() -> Array[String]:
	var failures: Array[String] = []
	for path in ["res://scripts/exploration_3d/trial_menu.gd", "res://scripts/exploration_3d/pause_panel.gd", "res://scenes/exploration_3d/trial_menu.tscn"]:
		F.expect(FileAccess.file_exists(path), "缺少参道菜单界面：" + path, failures)
	_test_title(failures)
	if not failures.is_empty(): return failures
	var Menu = load("res://scripts/exploration_3d/trial_menu.gd")
	var Pause = load("res://scripts/exploration_3d/pause_panel.gd")
	await _test_menu_scene(failures)
	await _test_new_and_overwrite(Menu, failures)
	await _test_unreadable_saves(Menu, failures)
	await _test_loading_retry(Menu, failures)
	await _test_cancellation(Menu, failures)
	await _test_real_menu_controls(failures)
	await _test_complete_continue(Menu, failures)
	await _test_pending_continue(Menu, failures)
	await _test_pause(Pause, failures)
	await _test_pause_input_exit(Pause, failures)
	await _test_stage_pause(failures)
	return failures

static func _test_title(failures: Array[String]) -> void:
	var title := Title.new()
	title._theme = ThemeData.load_theme()
	title._hud = CanvasLayer.new()
	title.add_child(title._hud)
	title._build_menu()
	var labels: Array[String] = []
	for child in title._hud.get_children():
		if child is Button: labels.append(child.text)
	F.expect(labels.has("参道篇试玩") and labels.has("回合制 RPG 试作") and labels.has("继续退治") and labels.has("新的委托"), "标题新旧三个玩法入口共存", failures)
	if OS.get_environment("RPG_TEST_LEGACY_CONTRACTS") == "1":
		F.expect(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/v3/title.tscn", "历史契约：默认主场景未替换", failures)
	else:
		F.expect(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/campaign/title.tscn", "正式默认入口为统一五夜主线；旧标题仅作兼容复现", failures)
	title.free()

static func _test_new_and_overwrite(Menu, failures: Array[String]) -> void:
	var path := "user://rpg_v1/tests/menu_new.json"
	var session := ControlledSession.new(null, path)
	var menu = Menu.new()
	menu.bind(session)
	var missing: Dictionary = await menu.continue_trial()
	F.expect(not missing.ok and not menu.last_error.is_empty() and not FileAccess.file_exists(path), "无档继续显示错误，不能偷偷新开", failures)
	var first: Dictionary = await menu.start_new(false)
	F.expect(first.ok and first.next_scene == "res://scenes/exploration_3d/approach.tscn" and Session.current == session, "明确新开完成资源加载后才进入探索", failures)
	var before := FileAccess.get_file_as_string(path)
	var run_id: String = session.campaign.safe_snapshot().run_id
	var replace: Dictionary = await menu.start_new(false)
	F.expect(not replace.ok and replace.get("needs_confirmation", false) and menu.confirmation_pending, "已有试玩必须再次确认覆盖", failures)
	menu.cancel_overwrite()
	F.expect(not menu.confirmation_pending and FileAccess.get_file_as_string(path) == before, "取消覆盖保持存档逐字节不变", failures)
	var accidental: Dictionary = await menu.start_new(true)
	F.expect(not accidental.ok and FileAccess.get_file_as_string(path) == before, "没有当前确认上下文不能通过确认按钮覆盖", failures)
	await menu.start_new(false)
	var replaced: Dictionary = await menu.start_new(true)
	F.expect(replaced.ok and session.campaign.safe_snapshot().run_id != run_id, "仅二次明确确认替换新局", failures)
	menu.free()
	session.close()

static func _test_unreadable_saves(Menu, failures: Array[String]) -> void:
	var source := "user://rpg_v1/tests/menu_new.json"
	var valid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
	valid.schema_version = 99
	var samples := {"corrupt": "{broken", "future": JSON.stringify(valid), "read": FileAccess.get_file_as_string(source)}
	for kind in samples:
		var path := "user://rpg_v1/tests/menu_%s.json" % kind
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(samples[kind])
		file.close()
		var session := ControlledSession.new(ReadFailStore.new() if kind == "read" else null, path)
		var menu = Menu.new()
		menu.bind(session)
		var result: Dictionary = await menu.continue_trial()
		F.expect(not result.ok and not menu.last_error.is_empty(), kind + " 继续错误可见", failures)
		result = await menu.start_new(false)
		F.expect(not result.ok and not result.get("needs_confirmation", false) and FileAccess.get_file_as_string(path) == samples[kind], kind + " 错误不得转为覆盖确认或改写原档", failures)
		menu.free()
		session.close()

static func _test_loading_retry(Menu, failures: Array[String]) -> void:
	var path := "user://rpg_v1/tests/menu_retry.json"
	var session := ControlledSession.new(null, path)
	session.fail_assets = true
	var menu = Menu.new()
	menu.bind(session)
	var result: Dictionary = await menu.start_new(false)
	var safe: Dictionary = session.campaign.safe_snapshot()
	var before := FileAccess.get_file_as_string(path)
	F.expect(not result.ok and menu.retry_available and not menu.busy and menu.last_error.contains("资源"), "资源失败解锁重试和退出，但不假装进入", failures)
	session.fail_assets = false
	result = await menu.retry_loading()
	F.expect(result.ok and session.prepare_count == 2 and session.campaign.safe_snapshot() == safe and FileAccess.get_file_as_string(path) == before, "重试加载沿用已提交新局，不重复新开或写档", failures)
	menu.free()
	session.close()

static func _test_cancellation(Menu, failures: Array[String]) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var session := ControlledSession.new(null, "user://rpg_v1/tests/menu_cancel.json")
	var menu = Menu.new()
	menu.bind(session)
	menu.start_new(false)
	F.expect(menu.busy, "等待资源期间按钮锁定", failures)
	var snapshot: Dictionary = session.campaign.safe_snapshot()
	var duplicate: Dictionary = await menu.start_new(false)
	F.expect(not duplicate.ok and session.prepare_count == 1 and session.campaign.safe_snapshot() == snapshot, "加载期间重复点击不重入会话", failures)
	menu.cancel_loading()
	await tree.process_frame
	F.expect(not menu.busy and Session.current == null and not menu.retry_available, "取消加载关闭会话，迟到完成不能恢复导航", failures)
	menu.free()

static func _test_pause(Pause, failures: Array[String]) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var panel = Pause.new()
	tree.root.add_child(panel)
	var events: Array[String] = []
	panel.save_requested.connect(func(): events.append("save"))
	panel.title_requested.connect(func(): events.append("title"))
	panel.closed.connect(func(): events.append("closed"))
	panel.open(true)
	panel.request_title()
	F.expect(panel.confirmation_pending and not events.has("title"), "未保存位置退出先说明损失并确认", failures)
	panel.cancel_leave()
	F.expect(panel.visible and not panel.confirmation_pending and not events.has("closed"), "取消退出仍停在暂停菜单", failures)
	panel.request_save()
	panel.request_save()
	F.expect(events.count("save") == 1 and panel.busy, "保存等待期间只能提交一次", failures)
	panel.show_save_result({"ok": false, "error": "测试磁盘写入失败"})
	F.expect(panel.visible and not panel.busy and panel.last_error.contains("失败"), "保存失败保持暂停并给出可重试错误", failures)
	panel.request_save()
	panel.show_save_result({"ok": true, "error": ""})
	F.expect(events.count("save") == 2 and not panel.has_unsaved_position, "重试成功才清除未保存标记", failures)
	panel.close()
	F.expect(events.count("closed") == 1 and not panel.visible, "返回游戏只发一次关闭并供Stage恢复输入", failures)
	panel.open(true)
	panel.request_title()
	panel.confirm_leave()
	panel.confirm_leave()
	F.expect(events.count("title") == 1, "确认返回标题不能重复触发", failures)
	panel.open(false)
	panel.request_title()
	panel.show_error("测试标题场景加载失败")
	F.expect(not panel.busy and not panel._hud.resume.disabled and not panel._hud.title.disabled, "标题离场失败恢复暂停按钮，避免永久锁死", failures)
	panel.close()
	F.expect(events.count("closed") == 2, "离场失败仍可返回游戏", failures)
	panel.free()
	await tree.process_frame

static func _test_real_menu_controls(failures: Array[String]) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var session := ControlledSession.new(null, "user://rpg_v1/tests/menu_controls.json")
	session.fail_assets = true
	var menu := NavigationMenu.new()
	menu.bind(session)
	tree.root.add_child(menu)
	menu._hud.new.pressed.emit()
	F.expect(menu._hud.new.disabled and not menu._hud.back.disabled, "加载锁住新开和继续，但仍可取消", failures)
	for frame in range(2): await tree.process_frame
	F.expect(menu._hud.retry.visible and not menu._hud.new.visible and menu._hud.status.text.contains("资源加载失败") and menu.navigation_paths.is_empty(), "实际加载错误界面可见，失败不换场景", failures)
	var before := FileAccess.get_file_as_string("user://rpg_v1/tests/menu_controls.json")
	session.fail_assets = false
	menu.navigation_error = true
	await menu.retry_loading()
	F.expect(menu.retry_available and menu._hud.status.text.contains("重建失败") and FileAccess.get_file_as_string("user://rpg_v1/tests/menu_controls.json") == before, "场景重建失败仍能重试，安全档保持原样", failures)
	menu.navigation_error = false
	await menu.retry_loading()
	F.expect(not menu.retry_available and menu.navigation_paths.size() == 2 and menu.navigation_paths.back() == "res://scenes/exploration_3d/approach.tscn", "资源和场景重试完成同一目标导航", failures)
	menu.detach_on_navigation = true
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	menu._unhandled_key_input(escape)
	F.expect(menu.input_was_handled and not menu.is_inside_tree() and Session.current == null, "Esc先消费输入再离场，不能访问已移除的Viewport", failures)
	menu.free()

static func _test_complete_continue(Menu, failures: Array[String]) -> void:
	var path := "user://rpg_v1/tests/menu_complete.json"
	var session := ControlledSession.new(null, path)
	F.expect(session.start_new(false).ok, "完成档夹具明确新开", failures)
	var saved: Dictionary = session.campaign.safe_snapshot()
	saved.world.event_flags = {"approach_entered": true, "basin_observed": true, "basin_inspected": true, "basin_cleared": true, "approach_complete": true}
	saved.world.dlg_fired = {"a1": true, "h1": true}
	saved.world.resolved = {"basin_reflection": true}
	F.expect(Store.new().write_safe(saved, path) == OK, "完成档夹具通过真实校验", failures)
	session.close()
	var menu = Menu.new()
	var resumed := ControlledSession.new(null, path)
	menu.bind(resumed)
	var before := FileAccess.get_file_as_string(path)
	var result: Dictionary = await menu.continue_trial()
	F.expect(result.ok and result.next_scene == "res://scenes/exploration_3d/approach.tscn" and resumed.campaign.safe_snapshot().world.event_flags.has("approach_complete") and FileAccess.get_file_as_string(path) == before, "完成后继续仍回同地图，原完成进度保留", failures)
	menu.free()
	resumed.close()

static func _test_pause_input_exit(Pause, failures: Array[String]) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var panel = Pause.new()
	tree.root.add_child(panel)
	panel.open(false)
	await tree.process_frame
	var handled: Array[bool] = []
	panel.closed.connect(func():
		handled.append(panel.get_viewport().is_input_handled())
		tree.root.remove_child(panel))
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	panel._unhandled_key_input(escape)
	F.expect(handled == [true] and not panel.is_inside_tree(), "暂停Esc在closed回调前消费输入，父节点可安全离场", failures)
	panel.free()

static func _test_pending_continue(Menu, failures: Array[String]) -> void:
	var path := "user://rpg_v1/tests/menu_pending.json"
	var original := Session.new(null, path)
	F.expect(original.start_new(false).ok, "待战继续夹具新开成功", failures)
	for event_id in ["approach_entered", "basin_observed", "basin_inspected"]:
		F.expect(original.commit_event(original.campaign.safe_snapshot().world, event_id).ok, "待战继续提交真实前置", failures)
	var started: Dictionary = original.begin_encounter(original.campaign.safe_snapshot().world)
	F.expect(started.ok, "待战继续建立同一战前快照", failures)
	if not started.ok:
		original.close()
		return
	var saved: Dictionary = original.campaign.safe_snapshot()
	var before := FileAccess.get_file_as_string(path)
	original.close()
	var resumed := ControlledSession.new(null, path)
	resumed.fail_assets = true
	var menu = Menu.new()
	menu.bind(resumed)
	var failed: Dictionary = await menu.continue_trial()
	F.expect(not failed.ok and menu.retry_available and resumed.router.engine == null and resumed.campaign.safe_snapshot() == saved, "继续待战先加载，资源失败不能开始半场战斗或改写安全档", failures)
	resumed.fail_assets = false
	var continued: Dictionary = await menu.retry_loading()
	F.expect(continued.ok and continued.pending_battle and continued.next_scene == "res://scenes/rpg/battle.tscn" and resumed.router._setup.battle_id == started.battle_id and resumed.router._setup.seed == started.seed and resumed.router._setup.setup == started.setup and FileAccess.get_file_as_string(path) == before, "待战加载重试保留ID、seed、队员与库存并进入同一战斗", failures)
	menu.free()
	resumed.close()

static func _test_menu_scene(failures: Array[String]) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var packed: PackedScene = load("res://scenes/exploration_3d/trial_menu.tscn")
	F.expect(packed != null, "标题入口场景可实际载入", failures)
	if packed == null: return
	var menu = packed.instantiate()
	tree.root.add_child(menu)
	await tree.process_frame
	F.expect(menu._hud.new.text == "新开试玩" and menu._hud.continue_button.text == "继续试玩" and menu._hud.back.text == "返回标题" and not menu._hud.confirm.visible and not menu._hud.retry.visible, "真实菜单场景默认三个独立入口且无确认遮挡", failures)
	F.expect(menu.session.campaign.safe_snapshot().is_empty() and Session.current == null, "只进入菜单不暗中新开或激活会话", failures)
	menu.free()

static func _test_stage_pause(failures: Array[String]) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var path := "user://rpg_v1/tests/menu_stage_pause.json"
	var store := A.FailingStore.new()
	var session := Session.new(store, path)
	F.expect(session.start_new(false).ok, "真实暂停夹具新开", failures)
	F.expect(session.commit_event(session.campaign.safe_snapshot().world, "approach_entered").ok, "真实暂停夹具已完成入场对白", failures)
	F.expect((await session.prepare_assets()).ok, "真实暂停预加载三名试玩人物", failures)
	var stage = load("res://scenes/exploration_3d/approach.tscn").instantiate()
	tree.root.add_child(stage)
	for frame in range(30):
		await tree.physics_frame
		await tree.process_frame
		if stage.ready_for_play: break
	F.expect(stage.ready_for_play and stage.flow != null and stage.flow.mode == &"explore" and stage.controls_enabled, "真实场景恢复后可探索", failures)
	if not stage.ready_for_play or stage.flow == null:
		stage.free()
		session.close()
		return
	var start: Vector3 = stage.player.position
	stage.player.set_move_input(Vector2(1, 0))
	for frame in range(12): await tree.physics_frame
	stage.player.set_move_input(Vector2.ZERO)
	F.expect(stage.player.position.distance_to(start) > 0.1, "暂停测试先实际移动产生未保存位置", failures)
	await _escape_key(true)
	await _escape_key(false)
	var panel = stage._pause_panel
	F.expect(panel.visible and panel.has_unsaved_position and stage.flow.mode == &"pause" and not stage.controls_enabled, "真实Esc打开暂停并关掉移动", failures)
	var stopped: Vector3 = stage.player.position
	stage.player.set_move_input(Vector2(1, 0))
	for frame in range(3): await tree.physics_frame
	F.expect(Vector2(stage.player.position.x - stopped.x, stage.player.position.z - stopped.z).length() < 0.001, "暂停面板期间移动意图无法穿透", failures)
	var before := FileAccess.get_file_as_string(path)
	store.fail = true
	panel._hud.save.pressed.emit()
	F.expect(panel.visible and not panel.busy and panel.last_error.contains("失败") and stage.flow.mode == &"pause" and FileAccess.get_file_as_string(path) == before, "真实暂停写失败保留菜单和原档并允许重试", failures)
	panel._hud.title.pressed.emit()
	F.expect(panel.confirmation_pending and stage.flow.mode == &"pause", "真实未保存退出先打开确认", failures)
	await _escape_key(true)
	F.expect(panel.visible and not panel.confirmation_pending and stage.flow.mode == &"pause" and not stage.controls_enabled and Session.current == session, "确认层Esc只取消退出，不能关闭暂停或开放移动", failures)
	await _escape_key(false)
	store.fail = false
	panel._hud.save.pressed.emit()
	var transported_world: Dictionary = World.normalize(JSON.parse_string(JSON.stringify(stage.export_world(), "", true, true)))
	F.expect(panel.visible and not panel.has_unsaved_position and panel.last_error.is_empty() and session.campaign.safe_snapshot().world == transported_world and FileAccess.get_file_as_string(path) != before, "真实暂停重试保存成功才公布已保存位置", failures)
	panel.close()
	stage._open_pause()
	F.expect(not panel.has_unsaved_position, "保存后未移动立即再暂停，不因JSON数值运输误差谎报未保存", failures)
	for frame in range(2): await tree.process_frame
	await _escape_key(true)
	F.expect(not panel.visible and stage.flow.mode == &"explore" and stage.controls_enabled, "暂停Esc关闭面板并恢复同一探索输入", failures)
	await _escape_key(false)
	var resumed: Vector3 = stage.player.position
	stage.player.set_move_input(Vector2(1, 0))
	for frame in range(6): await tree.physics_frame
	F.expect(stage.player.position.distance_to(resumed) > 0.04, "暂停返回后实际角色可继续移动", failures)
	stage.queue_free()
	await tree.process_frame
	session.close()

static func _escape_key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	# 输入与节点处理在帧边界交接，等待下一轮节点处理完成再断言。
	for frame in range(2): await (Engine.get_main_loop() as SceneTree).process_frame
