# 正式schema3会话与真实异步BattleView，覆盖跨身份动画、武器标签及当前轮序。
extends SceneTree
const Session=preload("res://scripts/campaign/chapter_session.gd")
const View=preload("res://scripts/rpg/ui/battle_view.gd")
const H=preload("res://tools/rpg/test_engine.gd")
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:_run.call_deferred()
func _run()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	await _case("p_guard","heavy_slash","rinne")
	await _case("p_mage","holy_shield","healer")
	print("LOADOUT_BATTLE: %d assertions, %d failures"%[checks,failures]);quit(1 if failures else 0)
func _case(actor_id:String,skill:String,visual:String)->void:
	var session:=Session.new()
	check(session.start_new(true,["guard","mage","healer"]).ok,"正式无等级队伍建立")
	var draft:Dictionary=session.campaign.safe_snapshot().roster[actor_id].build.duplicate(true)
	draft.active["sword" if actor_id=="p_mage" else "default"]=[skill]
	check(session.campaign.set_loadout(actor_id,draft).ok,"跨职业技能实际装备："+skill)
	for id in ["dialogue:a1","dialogue:r1","dialogue:h1"]:session.commit_event(session.campaign.safe_snapshot().world,id)
	var started:Dictionary=session.begin_encounter(session.campaign.safe_snapshot().world,"basin_reflection")
	check(started.ok,"当前版本遭遇可进入")
	var engine:RefCounted=session.router.create_engine()
	var errors:Array[String]=[];H._next_actor(engine,actor_id,errors)
	check(errors.is_empty(),"真实速度队列抵达当前演员")
	var view:=View.new();view.router=session.router;view.engine=engine;root.add_child(view)
	for frame in 600:
		await process_frame
		if not view._asset_loading and view._actors.size()>0 and not view._hd_player.is_busy():break
	check(not view._asset_loading and view._actors.size()>0,"正式战斗异步资源就绪")
	var before:Dictionary=engine.snapshot()
	var target:="p_guard" if skill=="holy_shield" else "e_01_hound"
	var result:Dictionary=engine.submit(H._command(engine,"skill",skill,[target]))
	check(result.accepted,"跨职业实际命令接受："+skill)
	if result.accepted:
		var observed:={"started":0,"visible":false}
		view._hd_player.action_started.connect(func(event,_timing):
			observed.started+=1
			check(event._effect_context.form==visual,"特效选择合法视觉家族而不冒充演员身份")
			check(view._fx_layer.action_count()==1,"正式跨职业动作启动真实图集"))
		view._hd_player.event_presented.connect(func(event):
			if event.type in ["damage","shield_applied"]:
				observed.visible=observed.visible or view._fx_layer.active_count()>0)
		view.processing=true;view._display_actor_id=actor_id;view._consume_events(result.events,before);view._render()
		for frame in 600:
			await process_frame
			if not view._hd_player.is_busy():break
		check(observed.started==1 and observed.visible,"真实队列命中/施加时有跨职业画面")
		check(view._fx_layer.missing_art().is_empty(),"跨职业没有错误形态或伪造附件点缺图")
		check(engine.snapshot().actors[actor_id].identity_id==before.actors[actor_id].identity_id,"借用技能画面不改变人物身份")
	view.free();session.close();await process_frame
