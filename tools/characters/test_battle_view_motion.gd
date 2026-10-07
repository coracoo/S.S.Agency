# 真实BattleView/Engine/Backdrop联合合同；测试开关只验证替换管线，不批准程序图集美术。
extends SceneTree
# 旧几何FX仅保留在明确历史管线夹具，生产BattleView已使用独立imagegen后端。
const LegacyEffects = preload("res://scripts/rpg/ui/battle_effects.gd")
const F = preload("res://tools/rpg/fixtures.gd")
const Battle = preload("res://scripts/rpg/battle_engine.gd")
const Actions = preload("res://tools/characters/test_expanded_actions.gd")
class FixtureView extends "res://scripts/rpg/ui/battle_view.gd":
	var definition: Dictionary = {}
	func _hd_enabled() -> bool: return true
	func _actor_definition(_actor: Dictionary) -> Dictionary: return definition
	func _build() -> void:
		super._build()
		_world_backdrop = WorldBackdrop.new(); _canvas.add_child(_world_backdrop); _canvas.move_child(_world_backdrop,0)
		_world_backdrop.configure({"night":1,"position":[-4.5,.03,.45]},false)
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",message)
func _make(side: String, mage: bool = false) -> FixtureView:
	var fixture := Actions.new(); var definition := fixture.definition(); fixture.free()
	var identity := "homura" if mage else "rinne"
	definition.manifest.merge({"identity_id":identity,"form_id":"mage" if mage else "rinne","portrait_source_manifest":"res://assets/chars/pixel/%s/high_detail_complete/manifest.json" % ("homura_mage" if mage else "rinne")})
	definition.frames.add_animation("battle_dash"); definition.frames.set_animation_speed("battle_dash",1000)
	for frame in 4: definition.frames.add_frame("battle_dash",definition.frames.get_frame_texture("run",frame),50)
	definition.manifest.anims.battle_dash={"frames":["a","b","c","d"],"durations_ms":[50,50,50,50],"clean_body":true,"qa_approved":true}
	var actor := F.actor("mage" if mage else "swordsman","p_actor")
	actor["identity_id"]=identity; actor["form_id"]="mage" if mage else "rinne"; actor.stats.spd=100; actor.stats.mp=999; actor.mp=999
	var actors := {"p_actor":actor}
	for index in (3 if mage else 1):
		var enemy := F.enemy("hound","e_%d" % index); enemy.stats.hp=5000; enemy.hp=5000
		actors[enemy.actor_id]=enemy
	var engine := Battle.new(); var started: Dictionary = engine.start({"actors":actors,"inventory":{}},51)
	check(started.started,"真实模型建立战斗："+str(started.get("reasons",[])))
	engine.advance(false)
	var view := FixtureView.new(); view.definition=definition; view.engine=engine; view._config.near_side=side; root.add_child(view)
	check(not view._skill_effects_ready,"正式默认不启用被否决的程序图集")
	view._fx_layer.free(); view._fx_layer=LegacyEffects.new(); view._canvas.add_child(view._fx_layer)
	view._skill_effects_ready=true
	return view
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	create_timer(20).timeout.connect(func(): printerr("FAIL: 联合门禁未结束"); quit(1))
	for side in ["left","right"]: await _test_command(side,false)
	await _test_command("right",true)
	_test_context_edge_cases()
	print("BATTLE_VIEW_MOTION: %d assertions, %d failures" % [checks,failures])
	quit(1 if failures else 0)
func _test_command(side: String,mage: bool) -> void:
	var view := _make(side,mage)
	var before: Dictionary=view.engine.snapshot()
	var result: Dictionary=view.engine.submit({"command_id":"joint_"+side+str(mage),"expected_revision":before.revision,"actor_id":"p_actor","kind":"skill","ability_id":"flame_wave" if mage else "heavy_slash","target_ids":[] if mage else ["e_0"]})
	check(result.accepted,"真实技能提交一次")
	var committed: Dictionary=view.engine.snapshot(); var immutable: Array=result.events.duplicate(true)
	var source: Node2D=view._actors.p_actor.sprite; var home:=source.position
	var observations := {"started":0,"hits":0,"cast":0,"impact_targets":{},"at_start":Vector2.ZERO,"action":{},"event":{}}
	view._hd_player.action_started.connect(func(_event,timing):
		observations.action=_event.duplicate(true)
		observations.started+=1; observations.at_start=source.position
		var bursts: Array=view._fx_layer._bursts
		observations.cast=bursts.size()
		check(not bursts.is_empty(),"action_started已经在真实当前位置启动管线")
		for burst in bursts:
			check(float(burst.duration)<=float(timing.native_impact_seconds)+.001,"FX不重复加已完成的接近时长")
			check(burst.source.distance_to(view._world_backdrop.actor_effect_center("p_actor"))<.01,"FX起点来自当前3D身体")
		check(view._actors.e_0.hpbar.value==before.actors.e_0.hp,"起手时HP仍保持命中前值"))
	view._hd_player.event_presented.connect(func(event):
		if event.type=="damage":
			observations.event=event.duplicate(true)
			observations.hits+=1
			check(view._actors[event.target_id].hpbar.value==event.payload.absorption.hp_after,"实际事件回调同刻更新HP")
			for burst in view._fx_layer._bursts:
				if burst.phase=="impact": observations.impact_targets[str(burst.target)]=true)
	view.processing=true; view._consume_events(result.events,before); view._render()
	var movement_frames:=0
	for frame in 180:
		await process_frame
		if source.position.distance_to(home)>1:
			movement_frames+=1
			check(view._actors.p_actor.ring.position==source.position,"近战每帧光圈跟随脚点")
			check(view._actors.p_actor.target.position.is_equal_approx(source.position-Vector2(110,source.get_meta("content_height"))),"点选热区同步当前身体")
		if not view._hd_player.is_busy():break
	check(observations.started==1 and observations.hits==(3 if mage else 1),"每命令只起手一次并呈现实际目标数")
	check(observations.cast==(4 if mage else 1),"全体投射物按实际三个承伤者启动")
	check(movement_frames==0 if mage else movement_frames>3,"法师原地施法，近战有连续位移")
	check(source.position==home,"完整收招后精确归位")
	check(observations.impact_targets.size()==(3 if mage else 1),"命中跟随每个实际目标，不复用单目标中心")
	check(result.events==immutable and view.engine.snapshot()==committed,"视图上下文不污染引擎事件、资源或RNG")
	var final_hp: float=view._actors.e_0.hpbar.value
	view._consume_events(result.events,before); view._render()
	check(view._actors.e_0.hpbar.value==final_hp,"重复旧事件不把HUD倒回命中前")
	view._hd_player.cancel()
	view._on_action_started(observations.action,{"native_impact_seconds":.2})
	view._on_event_presented(observations.event)
	check(view._fx_layer.active_count()==0,"队列直接取消后拒绝迟到的动作和命中回调")
	view._cancel_presentation()
	check(view._fx_layer.active_count()==0 and view._fx_layer.texture_memory_bytes()==0,"取消释放全部FX与纹理")
	for record in view._world_backdrop.actor_entries.values():check(record.trail.active_count()==0,"取消清理所有演员残影")
	view.free()

func _test_context_edge_cases() -> void:
	var view := _make("right",true)
	var before: Dictionary = view.engine.snapshot()
	var events := [
		{"sequence":999,"type":"command_accepted","actor_id":"p_actor","payload":{"command":{"command_id":"edge","kind":"skill","ability_id":"firebolt","target_ids":["e_0"]}}},
		{"sequence":1000,"type":"effect_ignored","actor_id":"p_actor","target_id":"e_0","payload":{"reason":"immune"}},
		{"sequence":1001,"type":"periodic_damage","actor_id":"p_actor","target_id":"e_1","payload":{"damage":5}},
		{"sequence":1002,"type":"saga_reflected","actor_id":"e_0","target_id":"p_actor","payload":{"damage":5}}
	]
	view._annotate_effect_context(events,before)
	view._on_action_started(events[0],{"native_impact_seconds":.2})
	check(view._fx_layer.active_count()==2,"目标被忽略前只出现起手/飞行")
	view._on_event_presented(events[1])
	check(view._fx_layer.active_count()==0,"ignored事件收走在途效果，不制造成功冲击")
	view._on_event_presented(events[2])
	check(view._fx_layer._bursts.back().atlas=="burn_brand" and events[2]._effect_context.is_empty(),"周期燃烧不会继承上一个技能的效果")
	view._on_event_presented(events[3])
	var reflected: Dictionary = view._fx_layer._bursts.back()
	check(reflected.atlas=="firebolt" and reflected.source==view._world_backdrop.actor_effect_center("e_0") and reflected.target==view._world_backdrop.actor_effect_center("p_actor"),"真实反射方向使用反射者与承伤者的3D中心")
	check(events[3].type=="saga_reflected" and view.engine.snapshot()==before,"反射仅适配视觉副本，不写回事件类型或模型")
	var card: Control = view._actors.e_0.card
	var previous := card.position
	card.position = view._world_backdrop.actor_screen_bounds("p_actor").position
	var overlaps: Array = view.presentation_obstructions()
	check(overlaps.any(func(item):return item.actor_id=="p_actor" and item.card_actor_id=="e_0") and card.visible and view._actors.e_0.hp.visible,"真实身体/卡片交集被门禁报告，HP仍可见")
	card.position=previous
	view._cancel_presentation()
	view._on_event_presented(events[2])
	check(view._fx_layer.active_count()==0,"无技能上下文的周期事件在取消后也拒绝迟到回调")
	view.free()
