# 八技能真实Engine→BattleView→清单事件层；无头测试不替代原生像素验收。
extends SceneTree
const F=preload("res://tools/rpg/fixtures.gd")
const Battle=preload("res://scripts/rpg/battle_engine.gd")
const Definition=preload("res://scripts/characters/pixel_character_definition.gd")
class Fixture extends "res://scripts/rpg/ui/battle_view.gd":
	var definitions:Dictionary
	func _hd_enabled()->bool:return true
	func _actor_definition(actor:Dictionary)->Dictionary:return definitions.get(str(actor.get("identity_id","")),{})
	func _build()->void:
		super._build()
		_world_backdrop=WorldBackdrop.new();_canvas.add_child(_world_backdrop);_canvas.move_child(_world_backdrop,0)
		_world_backdrop.configure({"night":1,"position":[-4.5,.03,.45]},false)
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:_run.call_deferred()
func _run()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	var definitions:={}
	for form in ["healer","controller","guard"]:
		definitions[form]=Definition.load_definition("res://assets/chars/pixel/%s/video_actions/manifest.json"%form,"battle")
	for ability in ["heal","group_heal","cleanse","holy_shield","weaken","slow","seal","magic_break"]:
		await _case(ability,definitions,false)
	await _case("cleanse",definitions,true)
	definitions.clear()
	print("CASTER_EVENT_BRIDGE: %d assertions, %d failures"%[checks,failures]);quit(1 if failures else 0)
func _case(ability:String,definitions:Dictionary,empty_cleanse:bool)->void:
	var healer:=ability in ["heal","group_heal","cleanse","holy_shield"]
	var form:="healer" if healer else "controller"
	var source:=F.actor(form,"source");source["identity_id"]=form;source["form_id"]=form;source.stats.spd=999;source.hp=60
	var target:=F.enemy("saga_borrowed_voice" if ability=="seal" else "hound","target");target.stats.hp=5000;target.hp=5000
	var ally:=F.actor("guard","ally");ally["identity_id"]="guard";ally["form_id"]="guard";ally.hp=40
	if ability=="cleanse" and not empty_cleanse:ally.statuses=[F.status("weaken",.2,3,"target")]
	if ability=="seal":target.statuses=[F.status("magic_break",.25,3,"source")]
	var engine:=Battle.new();engine.set_policy(load("res://scripts/rpg/enemy_policy.gd").new())
	check(engine.start({"actors":{"source":source,"target":target,"ally":ally},"inventory":{}},771).started,ability+" 初始化")
	engine.advance(false)
	var view:=Fixture.new();view.definitions=definitions;view.engine=engine;root.add_child(view)
	check(not view._hd_failed,ability+" 注册角色与实际3D层加载")
	view._fx_layer.preview_pending_art=true;view._skill_effects_ready=true
	var before:=engine.snapshot()
	var targets:Array=[] if ability in ["group_heal","slow"] else ["ally" if healer else "target"]
	var result:Dictionary=engine.submit({"command_id":"bridge_"+ability+str(empty_cleanse),"expected_revision":before.revision,"actor_id":"source","kind":"skill","ability_id":ability,"target_ids":targets})
	check(result.accepted,ability+" 真实指令接纳")
	if not result.accepted:view.free();return
	var committed:=engine.snapshot();var immutable:Array=result.events.duplicate(true)
	var phases:={};var seen:Array=[];var effect_times:Array=[]
	var start_frame:=Engine.get_process_frames()
	view._hd_player.event_presented.connect(func(event):
		seen.append(int(event.sequence))
		for layer in view._fx_layer.layer_snapshot():phases[str(layer.phase)]=true
		if event.type in ["healed","damage","status_applied","shield_applied","status_removed","charge_interrupted","mp_restored"]:effect_times.append(Engine.get_process_frames()-start_frame)
		if event.type=="healed":check(view._actors[event.target_id].hpbar.value==event.payload.after,ability+" HP与真实治疗事件一致")
		if event.type=="damage":check(view._actors[event.target_id].hpbar.value==event.payload.absorption.hp_after,ability+" HP与真实伤害事件一致"))
	view.processing=true;view._consume_events(result.events,before);view._render()
	for frame in 240:
		await process_frame
		if not view._hd_player.is_busy():break
	check(not view._hd_player.is_busy(),ability+" 完整动作结束后解锁")
	check(engine.snapshot()==committed and result.events==immutable,ability+" 模型/RNG/权威数组原样")
	check(view._fx_layer.missing_art().is_empty(),ability+" 不借通用图且登记层无遗漏："+str(view._fx_layer.missing_art()))
	var expected:Dictionary={"heal":["heal_impact","guard_life_shield"],"group_heal":["heal_impact"],"cleanse":[] if empty_cleanse else ["cleanse_removal","rejuvenation_heal"],"holy_shield":["holy_shield_edge","awake_clarity"],"weaken":["weaken_apply","weaken_status"],"slow":["slow_apply_sustain"],"seal":["stun_apply_sustain","charge_interrupt","mp_refund"],"magic_break":["damage_recovery","magic_break_status"]}
	for phase in expected[ability]:check(phases.has(phase),ability+" 真实事件对应独立层 "+phase+"，实际："+str(phases.keys()))
	if empty_cleanse:check(phases.is_empty(),"无可净化状态时不伪造净化/条件治疗")
	if ability=="group_heal":check(effect_times.size()==2 and effect_times[0]==effect_times[1],"群疗两个真实目标同M，不逐个等待受益动作")
	var current:Array=view._fx_layer.layer_snapshot()
	check(current.all(func(layer):return layer.lifetime!="action"),ability+" E后仅保留真实持续层")
	view._cancel_presentation()
	check(view._fx_layer.active_count()==0 and view._fx_layer.texture_memory_bytes()==0,ability+" 换代取消释放全部层与图页")
	view.free();await process_frame
