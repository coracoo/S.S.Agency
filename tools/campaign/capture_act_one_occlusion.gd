# 只针对纸棺侧径已复现遮挡点的实走复验：同场景向左通过再原路返回。
extends "res://tools/campaign/capture_act_one_walk.gd"
func _run() -> void:
	root.size = Vector2i(1920,1080)
	var session := Session.new()
	if not session.start_new(true).ok or not (await session.prepare_assets()).ok: quit(1); return
	var stage: Node3D = load(Catalog.scene_path(1)).instantiate();root.add_child(stage)
	for frame in 6: await physics_frame
	if not stage.ready_for_play:quit(1);return
	stage._generation += 1
	if is_instance_valid(stage._dialogue):stage._dialogue.abort();stage._dialogue.queue_free()
	stage._dialogue=null;stage._arrival_checked=true;stage._resume_explore()
	var world: Dictionary=stage.export_world();world.position=[52.0,2.89,5.0]
	var restore: Dictionary=stage.restore_world(world)
	if not restore.ok or restore.used_fallback:printerr("OCCLUSION_START_NOT_REACHABLE");quit(1);return
	began=Time.get_ticks_usec()
	for index in range(5):
		var point: Vector2 = [Vector2(52,5),Vector2(49.19,4.86),Vector2(46,5),Vector2(49.19,4.86),Vector2(52,5)][index]
		if not await _walk_to(stage,point):failed=true;break
		await _shot(stage,"%02d_侧径遮挡往返"%index)
	var file:=FileAccess.open(output.path_join("occlusion-walk-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"status":"fail" if failed else "pass","source":"仅起点通过正式restore置到侧径，全部往返位移由真实角色控制器驱动；验证已发现x49.19,z4.86的遮挡，不伪称从开场全图无剪辑", "frames":frames},"\t"));file.close()
	stage.free();session.close();quit(1 if failed else 0)
