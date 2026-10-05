# 同源探索/战斗定点实拍；合法恢复位置用于构图，不声称人工步行触发。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
const Battle = preload("res://scripts/rpg/ui/battle_view.gd")
var output := ""
var captures:Array[String]=[]
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or OS.get_environment("ACT_ONE_OUTPUT").is_empty(): quit(2); return
	output = OS.get_environment("ACT_ONE_OUTPUT")
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1920,1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var points:Array=[{"id":"forecourt","position":[19.0,2.89,2.6]}, {"id":"corridor","position":[25.0,2.89,-6.6]}]
	if OS.get_environment("BATTLE_WORLD_ALL_REGIONS")=="1":
		points.append_array([
			{"id":"approach","position":[-4.5,.03,.45]},
			{"id":"procession","position":[43.0,2.89,4.0]},
			{"id":"mirror","position":[43.0,2.89,-12.7]},
			{"id":"honden","position":[61.0,2.89,-4.8]},
			{"id":"central_court","position":[34.8,2.89,-4.8]},
			{"id":"north_walk","position":[34.8,2.89,-11.8]},
			{"id":"south_walk","position":[33.0,2.89,4.0]},
		])
	for entry in points:
		var only:=OS.get_environment("BATTLE_WORLD_REGION_ONLY")
		if not only.is_empty() and not str(entry.id) in only.split(","):continue
		var session := Session.new()
		if not session.start_new(true).ok or not (await session.prepare_assets()).ok: quit(1);return
		var stage: Node3D = load(Chapters.scene_path(1)).instantiate();root.add_child(stage)
		for frame in 8:await physics_frame
		stage._generation += 1
		if is_instance_valid(stage._dialogue):stage._dialogue.abort();stage._dialogue.queue_free()
		stage._dialogue=null;stage._arrival_checked=true;stage._resume_explore()
		var world: Dictionary=stage.export_world();world.position=entry.position.duplicate()
		var restored:Dictionary=stage.restore_world(world)
		if not restored.ok or restored.used_fallback:printerr("CAPTURE_RESTORE:",entry.id,restored);quit(1);return
		stage.camera_rig.follow(stage.player,10)
		for frame in 8:await physics_frame
		stage._tutorial_remaining=0.0;stage._refresh_hud()
		await _shot(entry.id+"_explore")
		stage.set_hd2d_experiment(false)
		await _shot(entry.id+"_explore_depth_off")
		stage.set_hd2d_experiment(true)
		world=stage.export_world()
		for event in ["dialogue:a1","dialogue:r1","dialogue:h1"]:
			var committed:Dictionary=session.commit_event(world,event)
			if not committed.ok:printerr("CAPTURE_COMMIT:",committed);quit(1);return
			world=session.campaign.safe_snapshot().world.duplicate(true)
		stage.free()
		var started:Dictionary=session.begin_encounter(world,"basin_reflection")
		if not started.ok:printerr("CAPTURE_ENCOUNTER:",started);quit(1);return
		var battle:=Battle.new();battle.router=session.router;root.add_child(battle)
		for frame in 8:await process_frame
		var remaining:=120
		while battle.processing and remaining>0:
			await process_frame;remaining-=1
		await _shot(entry.id+"_battle")
		if not entry.id in ["forecourt","corridor"]:
			battle.free();session.close();continue
		battle._skill_buttons[0].pressed.emit()
		var options:Dictionary=battle.command_options("skill",battle.pending_command.get("ability_id",""))
		if not options.get("targets",[]).is_empty():battle.select_target(options.targets[0])
		if not battle.current_preview().legal:printerr("CAPTURE_PREVIEW: no legal target");quit(1);return
		await _shot(entry.id+"_battle_select")
		battle.cancel_command();battle._basic_pressed("item")
		await _shot(entry.id+"_battle_items")
		battle._close_popup();battle._toggle_log()
		await _shot(entry.id+"_battle_log")
		battle.free();session.close()
	var report:=FileAccess.open(output.path_join("capture-report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"status":"pass","source":"合法恢复位置的正式探索/独立同源3D战斗与真实合法技能目标；非人工步行通关","captures":captures},"\t"));report.close()
	print("BATTLE_WORLD_CAPTURE:",captures.size()," screenshots; restored legal composition fixture")
	quit()
func _shot(label:String)->void:
	for frame in 6:await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output.path_join(label+".png"))!=OK:quit(1)
	captures.append(label+".png")
