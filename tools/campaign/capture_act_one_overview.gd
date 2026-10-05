# 真实引擎全景机位：仅拉远相机与关闭距离可见性裁剪，不改变地图几何或角色比例。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or OS.get_environment("ACT_ONE_OUTPUT").is_empty(): quit(2); return
	_run.call_deferred()
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
	stage._dialogue = null
	stage._arrival_checked = true
	stage.set_controls_enabled(false)
	stage.set_process(false)
	stage._ui_layer.hide()
	stage.set_hd2d_experiment(false)
	for entry in stage._geometry._chunks: entry.node.show()
	var camera: Camera3D = stage.camera_rig.camera
	camera.size = 45
	var target := Vector3(28.5,2.0,-3.5)
	camera.global_position = target + Vector3(0,58,66)
	camera.look_at(target)
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("ACT_ONE_OUTPUT")
	var code := root.get_texture().get_image().save_png(output.path_join("第一幕_全寺域引擎实景总览.png"))
	var meta := {"note":"实际同一寺域场景拉远总览，非正常游玩相机；仅开启所有美术分块和关闭景深以查看布局，未移动几何或缩放人物", "camera": {"position":[camera.global_position.x,camera.global_position.y,camera.global_position.z],"target":[target.x,target.y,target.z],"orthographic_size":camera.size},"geometry_instance":stage._geometry.get_instance_id(),"renderer":RenderingServer.get_video_adapter_name()}
	var file := FileAccess.open(output.path_join("overview-metadata.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(meta,"\t"));file.close()
	stage.free();session.close()
	quit(0 if code == OK else 1)
