# 隔离的新游戏真实控制器步行证据；只跳过对话播放，不改角色位置或伪造逐帧动画。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
var output := ""
var frames: Array[Dictionary] = []
var route_report: Array[Dictionary] = []
var began := 0
var last_capture := 0
var failed := false
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or OS.get_environment("ACT_ONE_OUTPUT").is_empty(): quit(2); return
	output = OS.get_environment("ACT_ONE_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output.path_join("walk_frames"))
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var session := Session.new()
	if not session.start_new(true).ok or not (await session.prepare_assets()).ok: quit(1); return
	var stage: Node3D = load(Catalog.scene_path(1)).instantiate()
	root.add_child(stage)
	for frame in 8: await physics_frame
	if not stage.ready_for_play: printerr("CAPTURE_FAIL:舞台未就绪:", stage.last_error); quit(1); return
	stage._generation += 1
	if is_instance_valid(stage._dialogue): stage._dialogue.abort(); stage._dialogue.queue_free()
	stage._dialogue = null
	stage._arrival_checked = true
	stage._resume_explore()
	var route: Array[Dictionary] = [
		{"name": "山路起点", "point": Vector2(-4.3, 0.35)},
		{"name": "水钵旁参道", "point": Vector2(-1.2, 0.35)},
		{"name": "登山石阶", "point": Vector2(4.0, 0.0)},
		{"name": "山门平台", "point": Vector2(8.65, 0.0)},
		{"name": "山门外新庭院", "point": Vector2(12.5, 0.0)},
		{"name": "庭院中心", "point": Vector2(20.0, 3.8)},
		{"name": "庭院纵深", "point": Vector2(20.0, -2.0)},
	]
	if OS.get_environment("ACT_ONE_FULL_ROUTE") == "1":
		route.append_array([
			{"name": "回廊入口", "point": Vector2(20.3, -6.0)},
			{"name": "回廊穿行", "point": Vector2(29.0, -6.0)},
			{"name": "中庭", "point": Vector2(34.0, -6.0)},
			{"name": "镜殿侧径", "point": Vector2(34.0, -12.0)},
			{"name": "镜殿檐下", "point": Vector2(42.0, -12.0)},
			{"name": "本殿前庭", "point": Vector2(52.0, -6.0)},
			{"name": "本殿入口", "point": Vector2(60.0, -4.0)},
			{"name": "返回中庭", "point": Vector2(52.0, -4.0)},
			{"name": "纸棺侧径", "point": Vector2(52.0, 5.0)},
			{"name": "纸棺庭", "point": Vector2(43.0, 5.0)},
			{"name": "回到前庭", "point": Vector2(21.0, 5.0)},
			{"name": "返往山门", "point": Vector2(12.5, 0.0)},
			{"name": "原路下山", "point": Vector2(-4.3, 0.35)},
		])
	began = Time.get_ticks_usec()
	await _shot(stage, "00_上山路起点")
	for index in range(route.size()):
		var entry: Dictionary = route[index]
		var reached := await _walk_to(stage, entry.point)
		route_report.append({"name": entry.name, "target": [entry.point.x, entry.point.y], "actual": [stage.player.position.x, stage.player.position.y, stage.player.position.z], "reached": reached, "seconds": float(Time.get_ticks_usec() - began) / 1000000.0})
		print("ACT_ONE_WALK:", JSON.stringify(route_report[-1]))
		await _shot(stage, "%02d_%s" % [index + 1, entry.name])
		if not reached: failed = true; break
	stage.player.set_move_input(Vector2.ZERO)
	stage._open_map()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("寺域总览.png"))
	stage._resume_explore()
	var report := {"status": "fail" if failed else "pass", "source": "新游戏正式stage；仅采集夹具跳过开场对白，全部位移由真实控制器、速度和碰撞产生", "scene_instance": stage.get_instance_id(), "geometry_instance": stage._geometry.get_instance_id(), "map_layout": stage.export_world().get("map_layout"), "renderer": RenderingServer.get_video_adapter_name(), "route": route_report, "frames": frames, "camera": stage.camera_rig.snapshot()}
	var file := FileAccess.open(output.path_join("walk-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	stage.free(); session.close()
	quit(1 if failed else 0)
func _walk_to(stage: Node3D, destination: Vector2) -> bool:
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < 45000000:
		var current := Vector2(stage.player.position.x, stage.player.position.z)
		var delta := destination - current
		if delta.length() < 0.22:
			stage.player.set_move_input(Vector2.ZERO)
			return true
		if stage.player.position.y < -0.3: return false
		stage.player.set_move_input(delta.normalized())
		await physics_frame
		if Time.get_ticks_usec() - last_capture > 120000:
			await RenderingServer.frame_post_draw
			last_capture = Time.get_ticks_usec()
			var filename := output.path_join("walk_frames/frame_%05d.jpg" % frames.size())
			if root.get_texture().get_image().save_jpg(filename, 0.92) != OK: return false
			frames.append({"file": filename, "seconds": float(last_capture - began) / 1000000.0, "position": [stage.player.position.x, stage.player.position.y, stage.player.position.z]})
	stage.player.set_move_input(Vector2.ZERO)
	return false
func _shot(stage: Node3D, name: String) -> void:
	stage.camera_rig.follow(stage.player, 10)
	for frame in 2: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
	stage._ui_layer.hide()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + "_无界面.png"))
	stage._ui_layer.show()
