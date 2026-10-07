# 正式第一夜舞台与控制器的候选身体实拍。只跳过开场对白、替换演员定义，不改地图/规则。
extends SceneTree
const Session=preload("res://scripts/campaign/chapter_session.gd")
const Catalog=preload("res://scripts/campaign/chapter_catalog.gd")
const Definition=preload("res://scripts/characters/pixel_character_definition.gd")
class CaptureStage extends "res://scripts/campaign/chapter_stage.gd":
	# 连deferred入口一起屏蔽，避免夹具取消对白后旧调用又锁住真实控制器。
	func _start_checkpoint_dialogue()->void:_arrival_checked=true
var output:=""
var stage:Node3D
var session:RefCounted
var rows:Array[Dictionary]=[]
var label:Label
var clock:=0.0
var phase:="idle"
var start_usec:=0
var background_only:=false
func _initialize()->void:
	output=OS.get_environment("WORLD_REVISION_OUTPUT")
	background_only=OS.get_environment("WORLD_REVISION_BACKGROUND_ONLY")=="1"
	if OS.get_environment("RPG_TEST_ISOLATED")!="1" or output.is_empty():quit(2);return
	if DisplayServer.get_name()=="headless":printerr("WORLD_CAPTURE_REJECTED: 需要实际原生窗口");quit(2);return
	_run.call_deferred()
func _run()->void:
	root.size=Vector2i(1280,720);root.content_scale_size=Vector2i(1920,1080)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS;root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	root.title="逢魔退治帖 · 新Mage世界动作实拍"
	session=Session.new()
	if not session.start_new(true).ok or not (await session.prepare_assets()).ok:quit(1);return
	stage=load(Catalog.scene_path(1)).instantiate();stage.set_script(CaptureStage);root.add_child(stage)
	for tick in 120:
		await physics_frame
		if stage.ready_for_play:break
	if not stage.ready_for_play:printerr("WORLD_CAPTURE_FAIL:",stage.last_error);quit(1);return
	stage._generation+=1
	if is_instance_valid(stage._dialogue):stage._dialogue.abort();stage._dialogue.free()
	stage._dialogue=null;stage._arrival_checked=true;stage._resume_explore()
	var definition:=Definition.load_definition(OS.get_environment("WORLD_REVISION_MANIFEST"),"world")
	if not definition.get("ok",false) or not stage.player.apply_definition("homura_mage",definition):printerr("WORLD_CAPTURE_ASSET_FAIL");quit(1);return
	stage.player.set_move_input(Vector2.ZERO);stage.player.set_run_input(false)
	# 先由真实控制器走到参道中线，避免长跑样本撞上路旁石钵。
	for tick in 180:
		var desired:=Vector2(-4.3,.35)-Vector2(stage.player.position.x,stage.player.position.z)
		if desired.length()<.12:break
		stage.player.set_move_input(desired.normalized());await physics_frame
	stage.player.set_move_input(Vector2.ZERO)
	stage.camera_rig.follow(stage.player,10)
	label=Label.new();label.position=Vector2(24,2);label.add_theme_font_override("font",load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf"));label.add_theme_font_size_override("font_size",20);label.add_theme_color_override("font_outline_color",Color.BLACK);label.add_theme_constant_override("outline_size",5);stage._ui_layer.add_child(label)
	start_usec=Time.get_ticks_usec()
	if not background_only:
		await _segment("idle_5_seconds",Vector2.ZERO,false,150)
		await _segment("walk_right",Vector2.RIGHT,false,15)
		await _segment("run_right",Vector2.RIGHT,true,36)
		await _segment("stop_right",Vector2.ZERO,false,12)
		await _segment("run_left",Vector2.LEFT,true,36)
		await _segment("stop_left",Vector2.ZERO,false,18)
	# 顺路走回石钵段取原场景，不瞬移或更改地图。此段不计动作视频时间。
	stage.player.set_run_input(false)
	for tick in 240:
		var desired:=Vector2(-1.2,.55)-Vector2(stage.player.position.x,stage.player.position.z)
		if desired.length()<.18:break
		stage.player.set_move_input(desired.normalized());await physics_frame
	stage.player.set_move_input(Vector2.ZERO)
	stage.camera_rig.follow(stage.player,10)
	for tick in 3:await process_frame
	# 正式舞台每帧刷新HUD可见性；只在最后取景暂停该刷新，不改生产HUD逻辑。
	stage.set_process(false)
	stage._ui_layer.hide();stage._modal_layer.hide();stage.player.hide()
	if is_instance_valid(stage._party_panel):stage._party_panel.hide()
	if is_instance_valid(stage._npc_layer):stage._npc_layer.hide()
	if is_instance_valid(stage._story_markers):stage._story_markers.hide()
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.save_png(output.path_join("night1_basin_background.png"))
	var background:={"scene":Catalog.scene_path(1),"night":1,"player_position":_v3(stage.player.position),"camera_position":_v3(stage.camera_rig.camera.global_position),"camera_rotation":_v3(stage.camera_rig.camera.global_rotation),"camera_size":stage.camera_rig.camera.size,"camera_state":stage.camera_rig.snapshot(),"utc":Time.get_datetime_string_from_system(true),"file":"night1_basin_background.png","sha256":FileAccess.get_sha256(output.path_join("night1_basin_background.png")),"no_ui":true,"no_character":true}
	var report:={"kind":"native_graphical_world_fixture","fixed_step":true,"recording_fps":30,"not_realtime_fps":true,"engine":Engine.get_version_info().string,"display_server":DisplayServer.get_name(),"renderer":RenderingServer.get_video_adapter_name(),"wall_seconds":float(Time.get_ticks_usec()-start_usec)/1000000.0,"source_note":"真实第一夜stage、碰撞和player_controller；夹具只替换候选身体并跳过开场对白，位移均由控制器速度产生。","frames":rows,"background":background}
	var semantics:={"all_rendered_frames_match":rows.all(func(row):return row.rendered_texture_matches),"run_right_plays_run":rows.filter(func(row):return row.phase=="run_right").all(func(row):return row.animation=="run"),"run_left_plays_run":rows.filter(func(row):return row.phase=="run_left").all(func(row):return row.animation=="run"),"controls_enabled":rows.all(func(row):return row.controls_enabled),"moved_from_start":rows.any(func(row):return absf(row.world_foot[0]-rows[0].world_foot[0])>1.0)}
	if background_only:
		report["kind"]="native_graphical_background_fixture";semantics={"ui_hidden":not stage._ui_layer.visible,"actor_hidden":not stage.player.visible}
	report["semantic_checks"]=semantics;report["semantic_passed"]=semantics.values().all(func(value):return value)
	var file:=FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("WORLD_REVISION_CAPTURE: frames=",rows.size()," background=",background.sha256)
	stage.free();session.close();definition.clear()
	for tick in 3:await process_frame;await RenderingServer.frame_post_draw
	quit(0 if report.semantic_passed else 1)
func _segment(name:String,axis:Vector2,run:bool,count:int)->void:
	phase=name;stage.player.set_move_input(axis);stage.player.set_run_input(run)
	for tick in count:await _frame()
func _frame()->void:
	await process_frame
	if not stage.controls_enabled or stage._mode!="explore":printerr("WORLD_CAPTURE_FAIL: 夹具探索控制被意外锁定");quit(1);return
	clock+=1.0/30.0
	var actor:Node3D=stage.player;var sprite:AnimatedSprite2D=actor.animator.sprite
	label.text="新Mage世界 | %.3fs | %s / %s #%02d | 固定步长30fps记录，非实时性能"%[clock,phase,sprite.animation,sprite.frame]
	await RenderingServer.frame_post_draw
	var expected:Texture2D=sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame)
	var actual_id:int=actor.billboard.get_meta("logical_frame_texture_id",0)
	var names:Array=actor.animator.definition.manifest.anims[sprite.animation].frames
	var row:={"index":rows.size(),"simulation_seconds":clock,"phase":phase,"animation":str(sprite.animation),"source_frame":sprite.frame,"frame_key":names[sprite.frame],"rendered_texture_matches":actual_id==expected.get_instance_id(),"world_foot":_v3(actor.global_position),"body_world_foot":_v3(actor.billboard.global_position),"velocity":_v3(actor.velocity),"on_floor":actor.is_on_floor(),"facing":actor.facing,"flip_h":actor.billboard.flip_h,"pixel_size":actor.billboard.pixel_size,"body_offset":[actor.billboard.offset.x,actor.billboard.offset.y],"action_locked":actor.animator.is_action_locked(),"camera":stage.camera_rig.snapshot()}
	row["controls_enabled"]=stage.controls_enabled
	if actor.scene_integration!=null:
		row["contact_mode"]=actor.scene_integration.contact_mode;row["grounded_count"]=actor.scene_integration.grounded_count
		row["ground_shadows"]=actor.scene_integration._shadows.filter(func(shadow):return shadow.visible).map(func(shadow):return _v3(shadow.global_position))
		row["material_matches_body"]=actor.billboard.material_override.get_shader_parameter("art_texture")==actor.billboard.texture
	root.get_texture().get_image().save_jpg(output.path_join("frame_%05d.jpg"%rows.size()),.94);rows.append(row)
func _v3(value:Vector3)->Array:return [value.x,value.y,value.z]
