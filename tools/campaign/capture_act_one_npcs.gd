# 连续地图NPC实拍：先由正式控制器从参道走到老梁，再实际打开/关闭原对白层。
extends "res://tools/campaign/capture_act_one_walk.gd"
func _run() -> void:
	root.size = Vector2i(1920,1080)
	var session := Session.new()
	if not session.start_new(true).ok or not (await session.prepare_assets()).ok: quit(1); return
	var stage: Node3D = load(Catalog.scene_path(1)).instantiate()
	root.add_child(stage)
	for frame in 8: await physics_frame
	if not stage.ready_for_play: quit(1); return
	stage._generation += 1
	if is_instance_valid(stage._dialogue): stage._dialogue.abort(); stage._dialogue.queue_free()
	stage._dialogue = null; stage._arrival_checked = true; stage._resume_explore()
	began = Time.get_ticks_usec()
	for point in [Vector2(-4.3,.35),Vector2(8.65,0),Vector2(12.5,0),Vector2(14.4,1.7)]:
		if not await _walk_to(stage,point): printerr("NPC_CAPTURE_WALK_BLOCK:",point);quit(1);return
	await _shot(stage,"01_山门守山人实景")
	var npc: Dictionary = {}
	for target in stage.config.interactions:
		if target.kind == "npc" and target.id == "npc:liang": npc = target
	if npc.is_empty(): printerr("NPC_CAPTURE_MISSING:liang");quit(1);return
	stage._confirm_armed = true
	if not stage.request_interaction(str(npc.id)): printerr("NPC_CAPTURE_OPEN_FAILED");quit(1);return
	var reveal := InputEventAction.new();reveal.action="approach_interact";reveal.pressed=true
	stage._dialogue._unhandled_input(reveal)
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("02_与老梁实际交谈.png"))
	var report := {"npc":npc.id,"body":npc.body,"mode":stage._mode,"controls_enabled":stage.controls_enabled,"position":[stage.player.position.x,stage.player.position.y,stage.player.position.z],"visible_npcs":stage.config.interactions.filter(func(t):return t.kind=="npc").map(func(t):return t.id),"party":session.campaign.safe_snapshot().party,"world":stage.export_world(),"source":"正式stage从山路真实控制器走到NPC；只有开场对白由夹具跳过，NPC通过实际交谈入口和原对白层打开"}
	var file := FileAccess.open(output.path_join("npc-capture-report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	stage._dialogue.abort()
	for frame in 2: await physics_frame
	await _shot(stage,"03_结束交谈继续探索")
	for point in [Vector2(19.5,1.5),Vector2(20.4,-1.8)]:
		if not await _walk_to(stage,point): break
	await _shot(stage,"04_前庭扫庭人实景")
	for target in stage.config.interactions:
		if target.id == "npc:acheng":
			stage._confirm_armed=true
			if stage.request_interaction(target.id):
				stage._dialogue._unhandled_input(reveal)
				for frame in 3: await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join("05_与阿诚实际交谈.png"))
	stage.free();session.close();quit()
