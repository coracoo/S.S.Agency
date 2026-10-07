# 真Engine→BattleView→HdEventPlayer异步队列→物理图层，不直接调用动作回调。
extends SceneTree
const F=preload("res://tools/rpg/fixtures.gd")
const H=preload("res://tools/rpg/test_engine.gd")
const Battle=preload("res://scripts/rpg/battle_engine.gd")
const Catalog=preload("res://scripts/rpg/catalog.gd")
const Forms=preload("res://scripts/rpg/dual_form.gd")
const Status=preload("res://scripts/rpg/status_rules.gd")
const Definition=preload("res://scripts/characters/pixel_character_definition.gd")
const Policy=preload("res://scripts/rpg/ui/physical_skill_visual_event_policy.gd")
class Fixture extends "res://scripts/rpg/ui/battle_view.gd":
	var definitions:Dictionary={}
	func _hd_enabled()->bool:return true
	func _actor_definition(actor:Dictionary)->Dictionary:
		var identity:=str(actor.get("identity_id",""))
		return definitions.get("homura_"+str(actor.get("form_id","sword")) if identity=="homura" else identity,{})
	func _build()->void:
		_config["backdrop_scene"]="" # 夹具只创建下面的正式寺域，避免先造一套无用旧预览视口。
		super._build()
		# 独立Engine夹具会走旧fallback背景；换成正式寺域时必须移除原不透明背景层。
		while _canvas.get_child(0)!=_danger_layer:_canvas.get_child(0).free()
		_world_backdrop=WorldBackdrop.new();_canvas.add_child(_world_backdrop);_canvas.move_child(_world_backdrop,0)
		_world_backdrop.configure({"night":1,"position":[-4.5,.03,.45]},false)
var checks:=0
var failures:=0
var graphical_output:=""
var scene_host:Node
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:
	graphical_output=OS.get_environment("ACT_ONE_OUTPUT")
	if not graphical_output.is_empty():root.position=Vector2i(-32000,-32000);root.hide()
	_run.call_deferred()
func _run()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	scene_host=root
	if not graphical_output.is_empty():
		var viewport:=SubViewport.new();viewport.size=Vector2i(1920,1080);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		root.add_child(viewport);scene_host=viewport
	var definitions:Dictionary={}
	for form in ["rinne","homura_sword","guard","mint","healer"]:
		definitions[form]=Definition.load_definition("res://assets/chars/pixel/%s/video_actions/manifest.json"%form,"battle")
		check(definitions[form].get("ok",false),"实际人物图集可加载："+form)
	for form in Policy.SKILLS:
		for skill in Policy.SKILLS[form]:
			await _case(form,skill,definitions)
	definitions.clear()
	if scene_host!=root:
		scene_host.queue_free();scene_host=null
		# 图形后端在渲染帧尾释放RID；销毁离屏树后再退出，避免把待释放纹理报成泄漏。
		for frame in 4:await process_frame
	print("PHYSICAL_BATTLE_VIEW: %d assertions, %d failures"%[checks,failures])
	quit(1 if failures else 0)
func _case(form:String,skill:String,definitions:Dictionary)->void:
	var catalog:=Catalog.new();catalog.load_all()
	var classes:={"rinne":"swordsman","homura_sword":"mage","guard":"guard","mint":"ranger"}
	var source:=F.actor(classes[form],"p_mage" if form=="homura_sword" else "source")
	source["identity_id"]="homura" if form=="homura_sword" else form
	if form=="homura_sword":Forms.initialize(source,catalog)
	var foe:=F.enemy("hound","target");foe.hp=3000;foe.stats.hp=3000
	var second:=F.enemy("hound","second");second.hp=3000;second.stats.hp=3000
	var ally:=F.actor("healer","ally");ally["identity_id"]="healer"
	if skill in ["heavy_slash","sweep"]:Status.apply(foe,F.status("armor_break",.25,3,"prior"))
	if skill=="hunt":Status.apply(foe,F.status("mark",.2,3,source.actor_id))
	var engine=H._selection(Battle,source,[foe,second,ally])
	var view:=Fixture.new();view.definitions=definitions;view.engine=engine;scene_host.add_child(view)
	check(view._skill_effects_ready and not view._fx_layer.preview_pending_art,form+"/"+skill+" 使用正式生产开关而非预览")
	for frame in 4:await process_frame
	var targets:Array=[] if skill in ["sweep","battle_spirit","iron_wall","smoke_screen"] else ["ally" if skill=="cover" else "target"]
	var before:Dictionary=engine.snapshot()
	var result:Dictionary=engine.submit(H._command(engine,"skill",skill,targets))
	check(result.accepted,form+"/"+skill+" 真实提交")
	if not result.accepted:view.free();return
	var immutable:Array=result.events.duplicate(true)
	var committed:Dictionary=engine.snapshot()
	var observed:={"started":0,"impact":0,"visible":false}
	view._hd_player.action_started.connect(func(event,timing):
		observed.started+=1
		check(event.get("_effect_context",{}).get("precast_evidence",{}).get("revision")==before.revision,form+"/"+skill+" 异步队列保留出招前证据")
		check(view._fx_layer.action_count()==1,form+"/"+skill+" 真action_started已登记物理动作"))
	view._hd_player.event_presented.connect(func(event):
		if event.type in ["damage","status_applied","shield_applied"]:
			observed.impact+=1
			var layers:Array=view._fx_layer.layer_snapshot()
			observed.visible=observed.visible or layers.any(func(layer):return layer.cue=="impact" and layer.frame>=1))
	view.processing=true;view._consume_events(result.events,before);view._render()
	var captured:=false
	for frame in 600:
		await process_frame
		if not graphical_output.is_empty() and observed.visible and not captured:
			RenderingServer.force_draw(false)
			var image:Image=scene_host.get_texture().get_image()
			check(image!=null and not image.is_empty(),form+"/"+skill+" 实际生产BattleView有GPU画面")
			if image!=null and not image.is_empty():
				image.save_png(graphical_output.path_join(form+"-"+skill+".png"));captured=true
		if not view._hd_player.is_busy():break
	if not graphical_output.is_empty():check(captured,form+"/"+skill+" 已捕获真实命中/增益时刻")
	check(not view._hd_player.is_busy(),form+"/"+skill+" 真队列自然结束")
	check(observed.started==1 and observed.impact>0 and observed.visible,form+"/"+skill+" 自然命中/增益时可采样对应PNG")
	check(engine.snapshot()==committed and result.events==immutable,form+"/"+skill+" 表现不改权威结果")
	check(view._fx_layer.layer_snapshot().all(func(layer):return layer.lifetime!="action"),form+"/"+skill+" E后不留瞬态")
	view._cancel_presentation()
	check(view._fx_layer.active_count()==0 and view._fx_layer.texture_memory_bytes()==0,form+"/"+skill+" 取消释放持续层与图集")
	view.free()
	await process_frame
