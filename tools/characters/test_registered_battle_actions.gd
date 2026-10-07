# 七个正式图集通过真实Engine/View/3D桥的攻招、倒地末帧和道具复苏；不是像素美术验收。
extends SceneTree
const F=preload("res://tools/rpg/fixtures.gd")
const Battle=preload("res://scripts/rpg/battle_engine.gd")
const Definition=preload("res://scripts/characters/pixel_character_definition.gd")
const Fixture=preload("res://tools/characters/test_imagegen_battle_view.gd").Fixture
const FORMS:={"rinne":"swordsman","guard":"guard","homura_sword":"swordsman","homura_mage":"mage","healer":"healer","controller":"controller","mint":"ranger"}
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:_run.call_deferred()
func _run()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	for form in FORMS:await _case(form)
	print("REGISTERED_BATTLE_ACTIONS: %d assertions, %d failures"%[checks,failures]);quit(1 if failures else 0)
func _case(form:String)->void:
	var actors:Dictionary={}
	for id in ["source","helper"]:
		var actor:=F.actor(FORMS[form],id)
		actor["identity_id"]="homura" if form.begins_with("homura_") else form
		actor["form_id"]=form.trim_prefix("homura_") if form.begins_with("homura_") else form
		actor.stats.spd=10 if id=="source" else 1
		if id=="source":actor.hp=1
		actors[id]=actor
	var enemy:=F.enemy("hound","enemy");enemy.stats.hp=5000;enemy.hp=5000;enemy.stats.atk=100;enemy.stats.spd=300;actors["enemy"]=enemy
	var engine:=Battle.new();var initialized:=engine.start({"actors":actors,"inventory":{"revival_potion":2}},71)
	check(initialized.started,form+"真实引擎初始化："+str(initialized.get("reasons",[])))
	if not initialized.started:return
	engine.advance(false)
	var view:=Fixture.new();view.definition=Definition.load_definition("res://assets/chars/pixel/%s/video_actions/manifest.json"%form,"battle");view.engine=engine;root.add_child(view)
	check(not view._hd_failed,form+"正式battle图集装配")
	if view._hd_failed:view.free();return
	var source:Node2D=view._actors.source.sprite;var body:Sprite3D=view._world_backdrop.actor_entries.source.body
	var results:Array[String]=[]
	view._hd_player.event_presented.connect(func(event):
		if event.type in ["damage","actor_defeated","revived"]:results.append(event.type))
	var before:=engine.snapshot();var command:={"command_id":form+"-lethal","expected_revision":before.revision,"actor_id":"enemy","kind":"attack_physical","ability_id":"","target_ids":["source"]}
	var result:=engine.submit(command);check(result.accepted,form+"真实敌方致死合法")
	if not result.accepted:view.free();return
	var committed:=engine.snapshot();var original:Array=result.events.duplicate(true)
	view._display_actor_id="enemy";view._consume_events(result.events,before);view._render()
	await _drain(view,form)
	check(results==["damage","actor_defeated"] and source.is_downed(),form+"伤害与KO各一次")
	check(source.animator.sprite.animation==&"down" and source.animator.sprite.frame==view.definition.frames.get_frame_count(&"down")-1 and not source.animator.sprite.is_playing(),form+"个人down真正末帧保持")
	check(body.get_meta("logical_frame_texture_id")==view.definition.frames.get_frame_texture(&"down",view.definition.frames.get_frame_count(&"down")-1).get_instance_id(),form+"实际billboard持down末帧")
	check(engine.snapshot()==committed and result.events==original,form+"致死表现不改规则数组")
	before=engine.snapshot();view._consume_events(engine.advance(false),before);await _drain(view,form)
	before=engine.snapshot();command={"command_id":form+"-revive","expected_revision":before.revision,"actor_id":before.active_actor_id,"kind":"item","ability_id":"revival_potion","target_ids":["source"]}
	result=engine.submit(command);check(result.accepted,form+"真实存活队友使用复苏药")
	if not result.accepted:view.free();return
	committed=engine.snapshot();original=result.events.duplicate(true)
	var timing:={"clock":0.0,"start":-1.0,"impact":0.0,"revive":-1.0,"item_visible":false,"recover_visible":false}
	view._hd_player._frame_tick.connect(func(delta):timing.clock+=delta)
	view._hd_player.action_started.connect(func(event,info):
		if event.payload.command.command_id==form+"-revive":timing.start=timing.clock;timing.impact=info.native_impact_seconds)
	view._hd_player.event_presented.connect(func(event):
		if event.type=="revived":timing.revive=timing.clock;timing.item_visible=view._actors.helper.sprite.animator.sprite.animation==&"item")
	view._display_actor_id=before.active_actor_id;view._consume_events(result.events,before);view._render()
	check(view._actors.source.hpbar.value==0 and source.is_downed(),form+"item M之前保持0HP/倒地")
	for frame in 300:
		await process_frame
		if body.get_meta("rendered_action","")=="recover":timing.recover_visible=true
		if not view._hd_player.is_busy():break
	check(not view._hd_player.is_busy(),form+"复苏队列完整结束")
	check(timing.item_visible and timing.recover_visible,form+"真实item来源与recover目标均实际绘制")
	check(absf(float(timing.revive)-float(timing.start)-float(timing.impact))<.05,form+"复苏跟自身原生item标记")
	check(not source.is_downed() and view._actors.source.hpbar.value==committed.actors.source.hp,form+"复苏恢复个人可用状态与真实HP")
	check(engine.snapshot()==committed and result.events==original and committed.inventory.revival_potion==1,form+"道具消费一次且呈现不改模型")
	# 敌方下一轮仅防御，让复苏角色的真实下一行动进入攻击；不跳改状态机。
	for step in 3:
		before=engine.snapshot();view._consume_events(engine.advance(false),before);await _drain(view,form)
		before=engine.snapshot()
		if before.active_actor_id=="source":break
		command={"command_id":form+"-skip-"+str(step),"expected_revision":before.revision,"actor_id":before.active_actor_id,"kind":"defend","ability_id":"","target_ids":[]}
		result=engine.submit(command)
		if not result.accepted:break
		view._consume_events(result.events,before);await _drain(view,form)
	before=engine.snapshot();check(before.active_actor_id=="source",form+"复苏者按真实队列获得下一行动")
	if before.active_actor_id=="source":
		command={"command_id":form+"-attack","expected_revision":before.revision,"actor_id":"source","kind":"attack_physical","ability_id":"","target_ids":["enemy"]}
		result=engine.submit(command);check(result.accepted,form+"正式攻击接纳")
		if result.accepted:
			committed=engine.snapshot();original=result.events.duplicate(true)
			var home:Vector2=source.position;var attack:={"visible":false,"hits":0}
			view._hd_player.event_presented.connect(func(event):
				if event.type=="damage" and event.actor_id=="source":attack.hits+=1)
			view._display_actor_id="source";view._consume_events(result.events,before);view._render()
			for frame in 360:
				await process_frame
				if body.get_meta("rendered_action","")=="attack":attack.visible=true
				if not view._hd_player.is_busy():break
			check(attack.visible and attack.hits==1 and not view._hd_player.is_busy(),form+"实际attack图/一次M命中/完整E")
			check(source.position.is_equal_approx(home) and engine.snapshot()==committed and result.events==original,form+"收招回home且不改规则/原序")
	view.free()
func _drain(view:Node,form:String)->void:
	for frame in 360:
		if not view._hd_player.is_busy():break
		await process_frame
	check(not view._hd_player.is_busy(),form+"呈现队列有界结束")
