# 批准生图分层菜单的真实Godot渲染；测试夹具仅调整整备，不代替人工全章通关。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
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
	var stage = load(Catalog.scene_path(1)).instantiate()
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
	world.position = [12.5, 2.89, 0.0]
	if not stage.restore_world(world).ok: quit(1); return
	stage._open_pause()
	var panel = stage._party_panel
	if panel == null: quit(1); return
	panel.select_actor("p_swordsman")
	panel.toggle_equipment("armor")
	panel.toggle_equipment("armor")
	if OS.get_environment("MENU_MANUAL") == "1":
		root.size = Vector2i(1280,720)
		panel.show_page("inventory")
		print("MENU_MANUAL_READY")
		return
	for size in [Vector2i(1920,1080), Vector2i(1280,720), Vector2i(1180,812)]:
		root.size = size
		for page in ["menu", "inventory", "equipment", "party"]:
			panel.show_page(page)
			if page == "equipment": panel.select_equipment("armor", "")
			for frame in 6: await process_frame
			await RenderingServer.frame_post_draw
			var filename := "%s_%dx%d.png" % [page, size.x, size.y]
			if root.get_texture().get_image().save_png(output.path_join(filename)) != OK: quit(1); return
	print("MENU_CAPTURE: 12 screenshots")
	stage.free()
	session.close()
	quit(0)
