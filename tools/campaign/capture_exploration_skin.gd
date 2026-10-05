# 真实探索HUD/总览/确认/错误的隔离图形采集；夹具不声称人工通关。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
var output := ""
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or OS.get_environment("ACT_ONE_OUTPUT").is_empty(): quit(2); return
	output = OS.get_environment("ACT_ONE_OUTPUT")
	_run.call_deferred()
func _run() -> void:
	root.content_scale_size = Vector2i(1920,1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var session := Session.new()
	if not session.start_new(true).ok or not (await session.prepare_assets()).ok: quit(1); return
	var stage = load(Chapters.scene_path(1)).instantiate()
	root.add_child(stage)
	current_scene = stage
	for frame in 12: await physics_frame
	if not stage.ready_for_play: quit(1); return
	stage._generation += 1
	if is_instance_valid(stage._dialogue): stage._dialogue.abort(); stage._dialogue.queue_free()
	stage._dialogue = null
	stage._arrival_checked = true
	stage._resume_explore()
	var world: Dictionary = stage.export_world()
	world.position = [12.5,2.89,0.0]
	if not stage.restore_world(world).ok: quit(1); return
	for resolution in [Vector2i(1920,1080),Vector2i(1280,720),Vector2i(1180,812)]:
		root.size = resolution
		stage._resume_explore()
		await _shot("exploration_hud",resolution)
		stage._open_map()
		await _shot("world_map",resolution)
		stage._resume_explore()
		stage.begin_operation("clue")
		var clue: Dictionary = Chapters.clue(4,"mirror_in_coffin")
		stage._show_modal(str(clue.name),str(clue.hint) + "\n\n" + str(clue.resolve_text),[{"text":"进入战斗","call":Callable()},{"text":"暂不应战","call":Callable()}])
		await _shot("clue_confirmation",resolution)
		stage._show_error("存档未能写入。当前位置与队伍仍保留在最近一次成功保存的状态，请重试。",Callable())
		await _shot("save_error",resolution)
	stage.free()
	session.close()
	print("EXPLORATION_SKIN_CAPTURE:12")
	quit()
func _shot(label: String,resolution: Vector2i) -> void:
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	var path := output.path_join(label + "_%dx%d.png" % [resolution.x,resolution.y])
	if root.get_texture().get_image().save_png(path) != OK: quit(1)
