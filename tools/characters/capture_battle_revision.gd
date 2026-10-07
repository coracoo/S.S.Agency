# 原生窗口中的真实BattleView/Engine/Backdrop。定时指令夹具不是人工通关或实时30fps证明。
extends SceneTree
const F = preload("res://tools/rpg/fixtures.gd")
const Battle = preload("res://scripts/rpg/battle_engine.gd")
const Definition = preload("res://scripts/characters/pixel_character_definition.gd")
const CapturePngCache = preload("res://scripts/ui/png_loader.gd")
class CaptureView extends "res://scripts/rpg/ui/battle_view.gd":
	var definition: Dictionary
	func _hd_enabled() -> bool: return true
	func _actor_definition(_actor: Dictionary) -> Dictionary: return definition
	func _build() -> void:
		super._build()
		# 无会话夹具的super会创建2D后备背景；替换为真实3D层，避免它盖住3D演员。
		for child in _canvas.get_children():
			if child == _danger_layer: break
			child.free()
		_world_backdrop = WorldBackdrop.new(); _canvas.add_child(_world_backdrop); _canvas.move_child(_world_backdrop,0)
		_world_backdrop.configure({"night":1,"position":[-4.5,.03,.45]},false)
class CaptureOverlay extends Label:
	var capture: SceneTree
	func _process(_delta: float) -> void: capture.call("_update_capture_overlay")
var output := ""
var form := ""
var side := ""
var cancel_case := false
var cancel_phase := "approach"
var cancel_applied := false
var view: CaptureView
var clock := 0.0
var started_usec := 0
var frames: Array[Dictionary] = []
var events: Array[Dictionary] = []
var warnings: Array[String] = []
var title: Label
var native_start := -1.0
var impact_time := -1.0
var submitted_at := 0.0
var current_label := "待机"
var approach_recorded := false
var home_foot := Vector2.ZERO
func _initialize() -> void:
	output = OS.get_environment("BATTLE_REVISION_OUTPUT")
	form = OS.get_environment("BATTLE_REVISION_FORM")
	side = OS.get_environment("BATTLE_REVISION_SIDE")
	cancel_case = OS.get_environment("BATTLE_REVISION_CANCEL") == "1"
	cancel_phase = OS.get_environment("BATTLE_REVISION_CANCEL_PHASE")
	if cancel_phase.is_empty(): cancel_phase="approach"
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or output.is_empty(): quit(2); return
	if DisplayServer.get_name() == "headless": printerr("CAPTURE_REJECTED: 需要真实图形窗口"); quit(2); return
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1920,1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.title = "逢魔退治帖 · 当前战斗实拍 · " + form + " " + side
	var manifest_path := OS.get_environment("BATTLE_REVISION_MANIFEST")
	if manifest_path.is_empty(): manifest_path="res://assets/chars/pixel/%s/video_actions/manifest.json" % form
	var definition := Definition.load_definition(manifest_path,"battle")
	if not definition.get("ok",false): printerr("CAPTURE_ASSET_FAIL:",definition); quit(1); return
	var class_id := "guard" if form == "guard" else ("mage" if form == "homura_mage" else "swordsman")
	var source := F.actor(class_id,"p_source")
	source["identity_id"] = "homura" if form.begins_with("homura_") else form
	source["form_id"] = form.trim_prefix("homura_") if form.begins_with("homura_") else form
	# 只固定先行动的顺序与目标存活空间；攻击/防御/技能规则及伤害数值不改。
	source.stats.spd = 999
	var enemy := F.enemy("hound","e_target"); enemy.stats.hp = 5000; enemy.hp = 5000
	var engine := Battle.new()
	var initialized := engine.start({"actors":{"p_source":source,"e_target":enemy},"inventory":{"healing_potion":2}},771)
	if not initialized.started: printerr("CAPTURE_MODEL_FAIL:",initialized); quit(1); return
	engine.advance(false)
	view = CaptureView.new(); view.definition = definition; view.engine = engine; view._config.near_side = side
	root.add_child(view)
	if view._hd_failed: printerr("CAPTURE_VIEW_FAIL:",view.last_error); quit(1); return
	if OS.get_environment("BATTLE_REVISION_IMAGEGEN_PREVIEW")=="1":
		view._fx_layer.preview_pending_art=true;view._skill_effects_ready=true
	view._actors.p_source.sprite.allow_unapproved_melee_preview = OS.get_environment("BATTLE_REVISION_ALLOW_UNAPPROVED_DASH")=="1"
	title = CaptureOverlay.new(); title.capture = self; title.process_priority = 1000
	title.position = Vector2(28,0); title.size = Vector2(1880,30)
	title.add_theme_font_override("font",load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf"))
	title.add_theme_font_size_override("font_size",20)
	title.add_theme_color_override("font_outline_color",Color.BLACK); title.add_theme_constant_override("outline_size",5)
	view._canvas.add_child(title)
	view._hd_player._frame_tick.connect(func(delta): clock += delta)
	view._hd_player.action_started.connect(_action_started)
	view._hd_player.event_presented.connect(_event_presented)
	view._actors.p_source.sprite.visual_warning.connect(func(message): warnings.append(message))
	view._actors.p_source.sprite.animator.action_finished.connect(func(): events.append({"type":"native_action_finished","simulation_seconds":clock,"pose":_source_pose()}))
	var home: Vector2 = view._actors.p_source.sprite.position
	home_foot = home
	var body_home: Vector3 = view._world_backdrop.actor_entries.p_source.body.position
	started_usec = Time.get_ticks_usec()
	for frame in 12: await _frame()
	var before: Dictionary = engine.snapshot()
	var command := {"command_id":"capture_"+form+"_"+side,"expected_revision":before.revision,"actor_id":"p_source","kind":"skill" if form=="homura_mage" else "attack_physical","ability_id":"firebolt" if form=="homura_mage" else "","target_ids":["e_target"]}
	var result: Dictionary = engine.submit(command)
	if not result.accepted: printerr("CAPTURE_COMMAND_FAIL:",result); quit(1); return
	var committed := engine.snapshot()
	var original_events: Array = result.events.duplicate(true)
	submitted_at = clock
	events.append({"type":"command_accepted","simulation_seconds":clock,"wall_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,"command":command.duplicate(true),"pose":_source_pose()})
	var actor_can_approach: bool = view._actors.p_source.sprite.supports_melee_approach()
	current_label = "原地施法" if form=="homura_mage" else ("原地攻击（dash待QA，正式安全门）" if not actor_can_approach else ("连续原生battle_dash接近" if definition.frames.has_animation("battle_dash") else "诊断：缺battle_dash，首帧临时滑移"))
	view._display_actor_id = "p_source"
	view.processing = true; view._consume_events(result.events,before); view._render()
	for frame in 180:
		await _frame()
		var phase := str(view._actors.p_source.sprite._melee.get("phase",""))
		if cancel_case and not cancel_applied and ((cancel_phase=="approach" and frame==2) or (cancel_phase=="return" and phase=="return" and float(view._actors.p_source.sprite._melee.get("elapsed",0))>=.1)):
			events.append({"type":"presentation_cancelled","simulation_seconds":clock,"phase":phase,"pose":_source_pose()})
			cancel_applied=true
			view._cancel_presentation(); current_label = "表现取消后精确归位；模型已提交且不重复结算"
		if not view._hd_player.is_busy(): break
	view.processing = false; view._render()
	for frame in 12: await _frame()
	var actor: Node2D = view._actors.p_source.sprite
	var body: Sprite3D = view._world_backdrop.actor_entries.p_source.body
	var report := {"kind":"native_graphical_battle_fixture","form":form,"side":side,"cancel_case":cancel_case,"display_server":DisplayServer.get_name(),"renderer":RenderingServer.get_video_adapter_name(),"rendering_method":RenderingServer.get_current_rendering_method(),"engine":Engine.get_version_info().string,"recording_fps":30,"fixed_step":true,"not_realtime_fps":true,"wall_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,"captured_frames":frames.size(),"model_unchanged_by_presentation":engine.snapshot()==committed,"events_unchanged":result.events==original_events,"returned_home":actor.position.is_equal_approx(home),"returned_world_home":body.position.is_equal_approx(body_home),"caster_stationary":frames.all(func(frame):return Vector2(frame.foot[0],frame.foot[1]).is_equal_approx(home)) if form=="homura_mage" else null,"native_attack_frames":definition.frames.get_frame_count("attack"),"native_attack_ms":definition.manifest.anims.attack.durations_ms.reduce(func(total,value):return total+value,0.0),"native_impact_ms":definition.manifest.anims.attack.get("impact_ms"),"battle_dash_available":definition.frames.has_animation("battle_dash"),"fallback_pose":bool(actor.get_meta("melee_dash_interim_fallback",false)),"procedural_effects_enabled":false,"imagegen_effects_preview":view._skill_effects_ready,"submitted_at":submitted_at,"action_started_at":native_start,"damage_presented_at":impact_time,"warnings":warnings,"events":events,"frames":frames,"fixture_note":"注册视频图集、真实BattleView/Backdrop/Engine；只固定速度顺序与目标HP容量，不改攻防或结算。固定步长导出不是实测30fps。当前无多帧dash的接近只属明确降级。"}
	report["imagegen_missing_art"] = view._fx_layer.missing_art()
	report["cancel_phase"] = cancel_phase
	report["cancel_applied"] = cancel_applied
	report["dash_qa_approved"] = actor.has_approved_melee_dash()
	report["unapproved_dash_diagnostic"] = actor.allow_unapproved_melee_preview
	var file := FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("BATTLE_REVISION_CAPTURE:",form,"/",side," frames=",frames.size()," home=",report.returned_world_home," model=",report.model_unchanged_by_presentation)
	var cleanup := {"png_cache_before":_png_cache_inventory(),"texture_bytes_before":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)}
	view.free(); view = null; definition.clear()
	# 仅录制夹具的有界退出对照：不改生产PNG缓存策略。
	CapturePngCache.clear_cache()
	cleanup["png_cache_after_clear"] = _png_cache_inventory()
	# 等待渲染后端处理节点/视口资源释放，不能在同一帧直接终止进程。
	for frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	cleanup["texture_bytes_after_three_draws"] = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
	var cleanup_file := FileAccess.open(output.path_join("cleanup.json"),FileAccess.WRITE)
	cleanup_file.store_string(JSON.stringify(cleanup,"\t")); cleanup_file.close()
	quit(0)
func _png_cache_inventory() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for path in CapturePngCache._cache:
		var texture: Texture2D = CapturePngCache._cache[path]
		var image := texture.get_image()
		entries.append({"path":path,"width":texture.get_width(),"height":texture.get_height(),"mipmaps":image.has_mipmaps(),"image_bytes":image.get_data_size()})
	return entries
func _action_started(event: Dictionary,timing: Dictionary) -> void:
	native_start = clock
	current_label = "原生动作开始；等待真实命中"
	events.append({"type":"action_started","simulation_seconds":clock,"wall_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,"command_id":event.payload.command.command_id,"timing":timing.duplicate(true),"pose":_source_pose(),"approach_window_start_from_signal_duration":clock-float(timing.approach_seconds)})
func _event_presented(event: Dictionary) -> void:
	if event.type == "damage": impact_time = clock; current_label = "真实命中 / 收招与返回"
	events.append({"type":event.type,"simulation_seconds":clock,"wall_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,"source":event.get("actor_id",""),"target":event.get("target_id",""),"payload":event.get("payload",{}).duplicate(true),"hud_source_mp":view._actors.p_source.mpbar.value,"hud_target_hp":view._actors.e_target.hpbar.value,"pose":_source_pose()})
func _capture_attachment() -> Dictionary:
	var point: Dictionary = view._world_backdrop.actor_action_attachment("p_source")
	if not point.ok: return point
	return {"ok":true,"frame_key":point.frame_key,"profile":point.profile,"logical_point":[point.logical_point.x,point.logical_point.y],"position":[point.position.x,point.position.y],"world_point":[point.world_point.x,point.world_point.y,point.world_point.z]}
func _source_pose() -> Dictionary:
	var actor: Node2D = view._actors.p_source.sprite
	var body: Sprite3D = view._world_backdrop.actor_entries.p_source.body
	return {"foot":[actor.position.x,actor.position.y],"world_foot":[body.position.x,body.position.y,body.position.z],"billboard":_billboard_frame(),"material_matches_body":body.material_override.get_shader_parameter("art_texture")==body.texture}
func _billboard_frame() -> Dictionary:
	var actor: Node2D = view._actors.p_source.sprite
	var body: Sprite3D = view._world_backdrop.actor_entries.p_source.body
	var id := int(body.get_meta("logical_frame_texture_id",0))
	var source_frames: SpriteFrames = actor.animator.sprite.sprite_frames
	var preferred := str(actor.animator.sprite.animation)
	var animations: Array = [preferred]
	for animation in source_frames.get_animation_names():
		if str(animation)!=preferred: animations.append(str(animation))
	for animation in animations:
		for frame in source_frames.get_frame_count(animation):
			if source_frames.get_frame_texture(animation,frame).get_instance_id()==id:
				var names: Array = actor._definition.manifest.anims.get(animation,{}).get("frames",[])
				return {"animation":animation,"index":frame,"frame_key":names[frame] if frame<names.size() else "","logical_texture_id":id,"flip_h":body.flip_h,"pixel_size":body.pixel_size}
	return {"animation":"unknown","index":-1,"frame_key":"","logical_texture_id":id}
func _update_capture_overlay() -> void:
	if not is_instance_valid(view) or not view._actors.has("p_source"): return
	var actual := _billboard_frame()
	var actor: Node2D = view._actors.p_source.sprite
	var label := ("未QA诊断 " if actor.allow_unapproved_melee_preview and not actor.has_approved_melee_dash() else "")+form
	title.text = "%s  %s  |  %.3fs  实绘 %s #%03d  |  %s  |  固定步长30fps导出，非实时性能" % [label,"右→左" if side=="right" else "左→右",clock,actual.animation,actual.index,current_label]
func _frame() -> void:
	await process_frame
	var actor: Node2D = view._actors.p_source.sprite
	var sprite: AnimatedSprite2D = actor.animator.sprite
	await RenderingServer.frame_post_draw
	var record: Dictionary = view._world_backdrop.actor_entries.p_source
	var image := root.get_texture().get_image()
	var path := output.path_join("frame_%05d.jpg" % frames.size())
	if image.is_empty() or image.save_jpg(path,.94) != OK: printerr("CAPTURE_FRAME_FAIL:",path); quit(1); return
	var foot: Vector2 = actor.position
	var world: Vector3 = record.body.position
	var overlaps := view.presentation_obstructions()
	if not approach_recorded and actor._melee.get("phase","")=="approach" and not foot.is_equal_approx(home_foot):
		approach_recorded = true
		events.append({"type":"first_visible_approach","simulation_seconds":clock,"wall_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,"pose":_source_pose(),"capture_index":frames.size()})
	frames.append({"index":frames.size(),"simulation_seconds":clock,"wall_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,"animation":str(sprite.animation),"source_frame":sprite.frame,"source_frame_duration":sprite.sprite_frames.get_frame_duration(sprite.animation,sprite.frame)/sprite.sprite_frames.get_animation_speed(sprite.animation),"billboard":_billboard_frame(),"overlay_text":title.text,"foot":[foot.x,foot.y],"world_foot":[world.x,world.y,world.z],"source_mp":view._actors.p_source.mpbar.value,"cast_attachment":_capture_attachment(),"target_hp":view._actors.e_target.hpbar.value,"model_target_hp":view.engine.snapshot().actors.e_target.hp,"melee_phase":str(actor._melee.get("phase","home")),"card_overlap_count":overlaps.size(),"ghost_count":record.trail.active_count(),"presentation_busy":view._hd_player.is_busy(),"source_action_locked":actor.is_action_busy(),"imagegen_active":view._fx_layer.active_count(),"imagegen_texture_bytes":view._fx_layer.texture_memory_bytes(),"imagegen_drawn":view._fx_layer.draw_snapshot(),"visible_latest_log":view._hud.latest.text})
