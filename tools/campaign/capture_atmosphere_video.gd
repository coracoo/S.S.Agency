# 固定30Hz离线视觉短片，所有位移仍由正式控制器/碰撞产生；不用于目标电脑性能结论。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
var output := ""
var frame_index := 0
var route_report: Array[Dictionary] = []
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or OS.get_environment("ACT_ONE_OUTPUT").is_empty(): quit(2);return
	output=OS.get_environment("ACT_ONE_OUTPUT");DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	Engine.physics_ticks_per_second=30
	_run.call_deferred()
func _run() -> void:
	root.content_scale_size=Vector2i(1920,1080);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.size=Vector2i(1280,720)
	var session:=Session.new()
	if not session.start_new(true).ok or not (await session.prepare_assets()).ok:quit(1);return
	var stage:Node3D=load(Catalog.scene_path(1)).instantiate();root.add_child(stage)
	for frame in 8:await physics_frame
	stage._generation+=1
	if is_instance_valid(stage._dialogue):stage._dialogue.abort();stage._dialogue.queue_free()
	stage._dialogue=null;stage._arrival_checked=true;stage._resume_explore()
	var world:Dictionary=stage.export_world();world.position=[12.5,2.89,0.0]
	var restored:Dictionary=stage.restore_world(world)
	if not restored.ok or restored.used_fallback:quit(1);return
	stage.camera_rig.follow(stage.player,10)
	var failed:=false
	for point in [Vector2(14,3),Vector2(20,3),Vector2(20,-6),Vector2(24,-6)]:
		var reached:=false
		for tick in range(900):
			var direction:Vector2=point-Vector2(stage.player.position.x,stage.player.position.z)
			if direction.length()<.18:reached=true;break
			stage.player.set_move_input(direction.normalized())
			await physics_frame
			await RenderingServer.frame_post_draw
			if root.get_texture().get_image().save_jpg(output.path_join("frames/frame_%05d.jpg"%frame_index),.95)!=OK:failed=true;break
			frame_index+=1
		stage.player.set_move_input(Vector2.ZERO)
		route_report.append({"target":[point.x,point.y],"reached":reached,"position":[stage.player.position.x,stage.player.position.y,stage.player.position.z]})
		if not reached:failed=true;break
	var file:=FileAccess.open(output.path_join("video-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"status":"fail" if failed else "pass","source":"固定30Hz离线画面；合法场景恢复起点后由正式控制器/碰撞行走；不是实时性能或完整人工通关证明","fps":30,"frames":frame_index,"route":route_report,"renderer":RenderingServer.get_video_adapter_name()},"\t"));file.close()
	stage.free();session.close();print("ATMOSPHERE_VIDEO:",frame_index," frames ","fail" if failed else "pass");quit(1 if failed else 0)
