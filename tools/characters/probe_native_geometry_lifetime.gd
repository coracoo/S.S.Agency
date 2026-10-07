# 实际Compatibility窗口，只建同一寺域几何；无人物/战斗UI。退出错误原样留日志。
extends SceneTree
const Geometry = preload("res://scripts/campaign/act_one_geometry.gd")
var output := ""
func _initialize()->void:
	output=OS.get_environment("GEOMETRY_PROBE_OUTPUT")
	if OS.get_environment("RPG_TEST_ISOLATED")!="1" or output.is_empty() or DisplayServer.get_name()=="headless":quit(2);return
	_run.call_deferred()
func _draws(count:int)->void:
	for i in count:
		await process_frame
		await RenderingServer.frame_post_draw
func _bytes()->int:return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
func _run()->void:
	root.size=Vector2i(640,360);root.title="逢魔退治帖 · 仅几何纹理生命周期对照"
	await _draws(3)
	var report:Dictionary={"kind":"native_geometry_only","display_server":DisplayServer.get_name(),"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_video_adapter_name(),"before_bytes":_bytes(),"cycles":[],"actors":0,"battle_ui":false}
	for index in 4:
		var world:=Geometry.build({});root.add_child(world)
		var camera:=Camera3D.new();world.add_child(camera);camera.current=true
		camera.position=Vector3(-4.5,7.13,11.45);camera.look_at(Vector3(-4.5,.93,.45));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=5
		await _draws(4)
		var live:=_bytes()
		if index==0:root.get_texture().get_image().save_png(output.path_join("geometry_native.png"))
		world.free()
		await _draws(4)
		report.cycles.append({"index":index,"live_bytes":live,"freed_bytes":_bytes()})
	var file:=FileAccess.open(output.path_join("geometry.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("GEOMETRY_ONLY_NATIVE_CAPTURE:",JSON.stringify(report))
	quit(0)
