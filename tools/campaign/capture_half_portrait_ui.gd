# 仅用于对话构图验收：正式场景与对白层，不写主线；文字明确是检查标签。
extends "res://tools/campaign/capture_act_one_walk.gd"
const Portraits = preload("res://scripts/characters/identity_portraits.gd")
const Overlay = preload("res://scripts/ui/dialogue_overlay.gd")
func _run() -> void:
	root.size = Vector2i(1920,1080)
	var session := Session.new()
	if not session.start_new(true).ok or not (await session.prepare_assets()).ok: quit(1); return
	var stage: Node3D = load(Catalog.scene_path(1)).instantiate();root.add_child(stage)
	for frame in 8: await physics_frame
	stage._generation += 1
	if is_instance_valid(stage._dialogue):stage._dialogue.abort();stage._dialogue.queue_free()
	stage._dialogue=null;stage._arrival_checked=true;stage._resume_explore()
	var world:Dictionary=stage.export_world();world.position=[14.0,2.89,0.0]
	if not stage.restore_world(world).ok:quit(1);return
	for binding in [["rinne","","凛音"],["mint","","薄荷"],["guard","","岑照"],["homura","sword","焰华·剑"],["homura","mage","焰华·术"],["healer","","苏合"],["controller","","清明"],["sayo","","小夜"]]:
		var portrait:Dictionary
		if binding[0]=="sayo":portrait=stage._dialogue_portrait("sayo")
		else:
			var definition:Dictionary=Portraits.load_idle_definition(binding[0],binding[1])
			portrait=Portraits.from_definition(definition,binding[0],"portrait")
		if not portrait.get("ok",false):printerr("HALF_UI_FAILED:",binding);quit(1);return
		var dialog:=Overlay.new(stage._theme)
		dialog.portrait_provider=func(_speaker:String)->Dictionary:return portrait
		stage.add_child(dialog)
		dialog.play({"qa":{"speaker":binding[0],"name":binding[2],"text":"半身立绘构图检查：使用当前正式素材与对白层。","side":"left","next":""}},"qa")
		var reveal:=InputEventAction.new();reveal.action="ui_accept";reveal.pressed=true
		dialog._unhandled_input(reveal)
		for frame in 18:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(binding[0]+"_"+binding[1]+"_半身UI检查.png"))
		dialog.abort();dialog.free()
	print("HALF_UI_CAPTURE:8 current forms incl Sayo")
	stage.free();session.close();quit()
