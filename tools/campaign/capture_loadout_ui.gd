# 隔离正式会话的装配菜单 GPU 证据；隐藏根窗口，避免占用人工验收窗口。
extends SceneTree
const Session=preload("res://scripts/campaign/chapter_session.gd")
const Party=preload("res://scripts/campaign/party_panel.gd")
var output:=""
var viewport:SubViewport
var failures:Array[String]=[]
func _initialize()->void:
	output=OS.get_environment("ACT_ONE_OUTPUT")
	if OS.get_environment("RPG_TEST_ISOLATED")!="1" or output.is_empty() or DisplayServer.get_name()=="headless":quit(2);return
	_run.call_deferred()
func _run()->void:
	root.position=Vector2i(-32000,-32000)
	viewport=SubViewport.new();viewport.size=Vector2i(1920,1080)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background:=ColorRect.new();background.color=Color("19232a");background.size=Vector2(2400,1600);viewport.add_child(background)
	var session:=Session.new()
	if not session.start_new(true).ok:quit(1);return
	var panel:=Party.new();viewport.add_child(panel);panel.open(session,"loadout");panel.select_actor("p_guard")
	await _capture("01-default-1920.png")
	panel._loadout.select_slot("active",0);panel._loadout.select_card("heavy_slash")
	panel._loadout.select_slot("passive",0);panel._loadout.select_card("light_step")
	await _capture("02-cross-class-preview-1920.png")
	panel._loadout.select_slot("active",0);panel._loadout.select_card("firebolt")
	await _capture("03-invalid-weapon-1920.png")
	panel._loadout.cancel_changes();panel.select_actor("p_mage")
	await _capture("04-homura-two-groups-1920.png")
	viewport.size=Vector2i(1280,720)
	await _capture("05-loadout-1280.png")
	viewport.size=Vector2i(1180,812)
	await _capture("06-loadout-1180.png")
	panel.free();session.close();viewport.free()
	for failure in failures:printerr("FAIL:",failure)
	print("LOADOUT_GPU_CAPTURE:6 images, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
func _capture(filename:String)->void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var picture:=viewport.get_texture().get_image()
	if picture==null or picture.is_empty() or picture.save_png(output.path_join(filename))!=OK:failures.append(filename)
