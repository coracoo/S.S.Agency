# UI实拍：正式界面与真实主题状态；坐标夹具只用于构图，不作为步行全通证据。
extends SceneTree
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
const Party = preload("res://scripts/campaign/party_panel.gd")
const View = preload("res://scripts/rpg/ui/battle_view.gd")
var output := ""
var captures: Array[Dictionary] = []
var capture_failed := false
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or OS.get_environment("ACT_ONE_OUTPUT").is_empty(): quit(2); return
	output = OS.get_environment("ACT_ONE_OUTPUT")
	_run.call_deferred()
func _run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var title: Node3D = load("res://scenes/campaign/title.tscn").instantiate()
	root.add_child(title)
	await _shots("01_标题")
	title.free()
	var session := Session.new()
	if not session.start_new(true).ok or not (await session.prepare_assets()).ok: quit(1); return
	var stage: Node3D = load(Catalog.scene_path(1)).instantiate()
	root.add_child(stage)
	for frame in 8: await physics_frame
	if not stage.ready_for_play: quit(1); return
	stage._generation += 1
	if is_instance_valid(stage._dialogue): stage._dialogue.abort(); stage._dialogue.queue_free()
	stage._dialogue = null; stage._arrival_checked = true; stage._resume_explore()
	var world: Dictionary = stage.export_world()
	world.position = [12.5, 2.89, 0.0]
	if not stage.restore_world(world).ok: quit(1); return
	await _shots("02_探索HUD")
	for target in stage.config.interactions:
		if target.id == "npc:liang":
			world = stage.export_world()
			world.position = target.position.duplicate()
			if not stage.restore_world(world).ok: quit(1); return
			stage._confirm_armed = true
			if not stage.request_interaction(str(target.id)): quit(1); return
			stage._dialogue._typing = false
			await _shots("03_老梁对白")
			stage._dialogue.abort()
			for frame in 3: await physics_frame
			break
	stage._confirm_armed = true
	stage._open_map()
	await _shots("04_寺域地图")
	stage._resume_explore()
	var party := Party.new()
	stage.add_child(party)
	party.open(session)
	await _shots("05_队伍整备")
	party.free()
	stage.free()
	for event in ["dialogue:a1", "dialogue:r1", "dialogue:h1"]:
		if not session.commit_event(session.campaign.safe_snapshot().world, event).ok: quit(1); return
	if not session.begin_encounter(session.campaign.safe_snapshot().world, "basin_reflection").ok: quit(1); return
	var battle := View.new()
	battle.router = session.router
	root.add_child(battle)
	await _shots("06_正式战斗")
	battle.free(); session.close()
	await _capture_states()
	if capture_failed: quit(1); return
	var file := FileAccess.open(output.path_join("ui-capture-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"status": "pass", "source": "正式标题/探索/实际NPC对白/地图/编队/战斗UI；位置恢复夹具不充当步行验收", "captures": captures}, "\t")); file.close()
	print("UI_POLISH_CAPTURE:", captures.size(), " screenshots")
	quit()
func _shots(name: String) -> void:
	for resolution in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.size = resolution
		for frame in 6: await process_frame
		await RenderingServer.frame_post_draw
		var screenshot := root.get_texture().get_image()
		var filename := name + "_%dx%d.png" % [resolution.x, resolution.y]
		if screenshot.save_png(output.path_join(filename)) != OK: quit(1); return
		captures.append({"name": filename, "width": screenshot.get_width(), "height": screenshot.get_height()})
func _capture_states() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var canvas := Control.new()
	canvas.size = Vector2(1920, 1080)
	layer.add_child(canvas)
	var shade := ColorRect.new()
	shade.color = Kit.color("ui_ink")
	shade.size = canvas.size
	canvas.add_child(shade)
	Kit.label(canvas, "按钮反馈 · 真实控件状态", Rect2(180, 150, 1560, 70), 44)
	Kit.muted(Kit.label(canvas, "暗朱只用于主要行动；灰绿表示已选择；键盘焦点保留独立外环。", Rect2(180, 246, 1560, 60), 26))
	var buttons: Array[Button] = []
	var state_labels: Array[Label] = []
	for index in 5:
		var x := 180 + index * 318
		state_labels.append(Kit.muted(Kit.label(canvas, ["常态", "悬停", "待按压", "不可用", "键盘焦点"][index], Rect2(x, 386, 280, 44), 24)))
		buttons.append(Kit.button(canvas, "返回探索", Rect2(x, 446, 282, 76)))
	buttons[3].disabled = true
	buttons[4].grab_focus()
	Kit.button(canvas, "开始新游戏", Rect2(180, 630, 440, 76), Callable(), true)
	var selected := Kit.button(canvas, "✓ 出战中", Rect2(676, 630, 440, 76))
	Kit.set_selected(selected, true)
	for resolution in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.size = resolution
		for frame in 6: await process_frame
		state_labels[1].text = "悬停"
		state_labels[4].text = "键盘焦点"
		state_labels[2].text = "待按压"
		buttons[4].grab_focus()
		var motion := InputEventMouseMotion.new()
		motion.position = buttons[1].get_global_rect().get_center()
		root.push_input(motion, true)
		for frame in 3: await process_frame
		if buttons[1].get_draw_mode() != BaseButton.DRAW_HOVER:
			printerr("UI_CAPTURE_FAILED:hover was ", buttons[1].get_draw_mode()); capture_failed = true; return
		await _state_shot("07_常态悬停禁用焦点", resolution, buttons)
		motion = InputEventMouseMotion.new()
		motion.position = buttons[2].get_global_rect().get_center()
		root.push_input(motion, true)
		var press := InputEventMouseButton.new()
		press.position = motion.position
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		root.push_input(press, true)
		state_labels[4].text = "焦点随点击移动"
		state_labels[1].text = "已移出（常态）"
		state_labels[2].text = "鼠标按住"
		for frame in 3: await process_frame
		if buttons[2].get_draw_mode() not in [BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED]:
			printerr("UI_CAPTURE_FAILED:pressed was ", buttons[2].get_draw_mode()); capture_failed = true; return
		await _state_shot("08_真实鼠标按住", resolution, buttons)
		press.pressed = false
		root.push_input(press, true)
	layer.free()
func _state_shot(name: String, resolution: Vector2i, buttons: Array[Button]) -> void:
	await RenderingServer.frame_post_draw
	var filename := name + "_%dx%d.png" % [resolution.x, resolution.y]
	var screenshot := root.get_texture().get_image()
	screenshot.save_png(output.path_join(filename))
	captures.append({"name": filename, "width": screenshot.get_width(), "height": screenshot.get_height(), "draw_modes": buttons.map(func(button): return button.get_draw_mode()), "focus": buttons[4].has_focus()})
