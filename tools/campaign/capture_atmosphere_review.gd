# 视觉定点夹具：用正式舞台/镜头/存档落点，在同机位切换月影对照；不冒充连续步行。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
var output := ""
var shots: Array[Dictionary] = []
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or OS.get_environment("ACT_ONE_OUTPUT").is_empty(): quit(2); return
	output = OS.get_environment("ACT_ONE_OUTPUT")
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1920,1080)
	var session := Session.new()
	if not session.start_new(true).ok or not (await session.prepare_assets()).ok: quit(1); return
	var stage: Node3D = load(Catalog.scene_path(1)).instantiate(); root.add_child(stage)
	for frame in 8: await physics_frame
	if not stage.ready_for_play: printerr("ATMOSPHERE_CAPTURE_FAIL:",stage.last_error); quit(1); return
	stage._generation += 1
	if is_instance_valid(stage._dialogue): stage._dialogue.abort(); stage._dialogue.queue_free()
	stage._dialogue = null; stage._arrival_checked = true; stage._resume_explore()
	var points := [
		{"name":"01_参道冷暖基准","position":[-1.2,.03,.35]},
		{"name":"02_山门前庭","position":[12.5,2.89,0.0]},
		{"name":"03_庭院中心","position":[20.0,2.89,3.8]},
		{"name":"04_回廊入口","position":[20.3,2.89,-6.0]},
	]
	if OS.get_environment("ATMOSPHERE_ALL_REGIONS") == "1":
		points.append_array([
			{"name":"05_中庭","position":[34.0,2.89,-6.0]},
			{"name":"06_镜殿","position":[42.0,2.89,-12.0]},
			{"name":"07_本殿","position":[60.0,2.89,-4.0]},
			{"name":"08_纸棺庭","position":[43.0,2.89,5.0]},
		])
	for entry in points:
		if OS.get_environment("ATMOSPHERE_SHADOW_SCAN") == "1" and not entry.name in ["02_山门前庭","04_回廊入口"]: continue
		var world: Dictionary = stage.export_world(); world.position = entry.position.duplicate()
		var restored: Dictionary = stage.restore_world(world)
		if not restored.ok or restored.used_fallback: printerr("ATMOSPHERE_CAPTURE_FAIL:落点",entry.name,restored); stage.free();session.close();quit(1);return
		stage.camera_rig.follow(stage.player,10)
		for frame in 12: await physics_frame
		stage._geometry.update_visibility(stage.player.position,1.0,stage.camera_rig.camera)
		if OS.get_environment("ATMOSPHERE_SHADOW_SCAN") == "1":
			var scan_key := stage._geometry.get_node("ActOneMoonKey") as DirectionalLight3D
			for scan in [[.10,.65],[.25,.65],[.50,.65],[.25,1.0],[.25,2.0]]:
				scan_key.shadow_bias = scan[0]; scan_key.shadow_normal_bias = scan[1]
				await _shot(stage,entry.name+"_bias%.2f_normal%.2f"%[scan[0],scan[1]])
			continue
		await _shot(stage,entry.name)
		stage._ui_layer.hide(); await _shot(stage,entry.name+"_无界面"); stage._ui_layer.show()
		if OS.get_environment("ATMOSPHERE_SHADOW_AB") == "1":
			var key := stage._geometry.get_node("ActOneMoonKey") as DirectionalLight3D
			var configured := key.shadow_enabled
			key.shadow_enabled = false; await _shot(stage,entry.name+"_月影关闭")
			key.shadow_enabled = configured
		if OS.get_environment("ATMOSPHERE_CHARACTER_AB") == "1":
			stage.player.enable_scene_integration()
			await _shot(stage,entry.name+"_已有逐脚接地融合")
			stage.player.disable_scene_integration()
		if OS.get_environment("ATMOSPHERE_REVERSE_CULL_AB") == "1":
			var cull_key := stage._geometry.get_node("ActOneMoonKey") as DirectionalLight3D
			cull_key.shadow_reverse_cull_face = true
			await _shot(stage,entry.name+"_阴影反向剔面")
			cull_key.shadow_reverse_cull_face = false
	stage._open_map(); await _shot(stage,"09_寺域总览")
	var file := FileAccess.open(output.path_join("atmosphere-review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"source":"正式舞台定点视觉夹具；通过合法restore_world定位，非连续步行或人工通关","renderer":RenderingServer.get_video_adapter_name(),"shots":shots},"\t"));file.close()
	stage.free();session.close();print("ATMOSPHERE_REVIEW_CAPTURE:",shots.size());quit()
func _shot(stage: Node3D, shot_name: String) -> void:
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	var path := output.path_join(shot_name+".png")
	if root.get_texture().get_image().save_png(path) != OK: printerr("ATMOSPHERE_CAPTURE_FAIL:写图",path);quit(1);return
	shots.append({"file":path,"position":[stage.player.position.x,stage.player.position.y,stage.player.position.z],"camera":stage.camera_rig.snapshot(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)})
	print("ATMOSPHERE_SHOT:",path)
