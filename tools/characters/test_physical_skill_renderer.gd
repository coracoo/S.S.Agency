# 真实Engine事务到物理技能图层，先核验隔离user://再运行。
extends SceneTree
const F = preload("res://tools/rpg/fixtures.gd")
const H = preload("res://tools/rpg/test_engine.gd")
const Battle = preload("res://scripts/rpg/battle_engine.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Forms = preload("res://scripts/rpg/dual_form.gd")
const Status = preload("res://scripts/rpg/status_rules.gd")
const Policy = preload("res://scripts/rpg/ui/physical_skill_visual_event_policy.gd")
const Effects = preload("res://scripts/rpg/ui/imagegen_battle_effects.gd")
const View = preload("res://scripts/rpg/ui/battle_view.gd")
const EnemyProfiles = preload("res://scripts/rpg/ui/enemy_presentation_profiles.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	for form in Policy.SKILLS:
		for skill in Policy.SKILLS[form]: _test_variant(form, skill)
	_test_simultaneous_forms()
	_test_battle_view_bridge()
	_test_context_rejection_and_cover()
	_test_enemy_effect_bridge()
	_test_rejected_finish_and_coherence()
	_test_redirected_enemy_visual_targets()
	print("PHYSICAL_SKILL_RENDERER: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func _cast(form: String, skill: String, enemy_kind: String = "hound") -> Dictionary:
	var catalog := Catalog.new(); catalog.load_all()
	var classes := {"rinne":"swordsman", "homura_sword":"mage", "guard":"guard", "mint":"ranger"}
	var source := F.actor(classes[form], "p_mage" if form == "homura_sword" else "source")
	source["identity_id"] = "homura" if form == "homura_sword" else form
	if form == "homura_sword": Forms.initialize(source, catalog)
	var enemy := F.enemy(enemy_kind, "enemy"); enemy.hp = 3000; enemy.stats.hp = 3000
	var other := F.enemy("hound", "other"); other.hp = 3000; other.stats.hp = 3000
	if skill == "cover": other = F.actor("healer", "ally")
	if skill in ["heavy_slash", "sweep"]: Status.apply(enemy, F.status("armor_break", .25, 3, "prior"))
	if skill == "hunt": Status.apply(enemy, F.status("mark", .20, 3, source.actor_id))
	var engine = H._selection(Battle, source, [enemy, other])
	var targets: Array = [] if skill in ["sweep", "battle_spirit", "iron_wall", "smoke_screen"] else [other.actor_id if skill == "cover" else enemy.actor_id]
	var before: Dictionary = engine.snapshot()
	var result: Dictionary = engine.submit(H._command(engine, "skill", skill, targets, form + "_" + skill))
	var context := Policy.context_from_result(before, catalog.skill_for(before.actors[source.actor_id], skill), result)
	context["impact_delay"] = .4; context["action_duration"] = 1.2; context["launch_seconds"] = .18
	return {"engine":engine,"before":before,"result":result,"context":context}
func _positions(cast: Dictionary) -> Dictionary:
	var result := {}
	for id in cast.before.actors: result[id] = Vector2(850, 360) if id == cast.context.source_id else Vector2(300 if id == "enemy" else 480, 370)
	return result
func _open(cast: Dictionary, fx, battle: String) -> bool:
	var context: Dictionary = cast.context
	var positions := _positions(cast)
	fx.update_positions(positions)
	fx.update_ground_positions(positions)
	return fx.present_action(context, context.form, positions[context.source_id], positions, battle)
func _test_variant(form: String, skill: String) -> void:
	var cast := _cast(form, skill)
	check(cast.result.accepted and not cast.context.is_empty(), form + "/" + skill + " 实际模型接受")
	var fx := Effects.new(); root.add_child(fx); fx.set_process(false); fx.preview_pending_art = true
	var started := _open(cast, fx, "variant")
	check(started, form + "/" + skill + " 实际renderer接受已验证物理合同")
	if not started: fx.free(); return
	var committed: Dictionary = cast.engine.snapshot()
	var original: Array = cast.result.events.duplicate(true)
	var positions := _positions(cast)
	var accepted := H._event(cast.result.events, "command_accepted")
	fx.present_event(accepted, form, positions[cast.context.source_id], positions[cast.context.source_id], "variant", cast.context)
	fx._process(.05)
	var layers: Array = fx.layer_snapshot()
	check(layers.any(func(layer): return str(layer.phase).begins_with("cast") and layer.frame >= 1), "起手采样真实登记帧：" + form + "/" + skill)
	check(not layers.any(func(layer): return layer.cue == "impact"), "没有伤害/状态事件前不显示命中：" + skill)
	fx._process(.35)
	for event in cast.result.events:
		if event.type == "command_accepted": continue
		fx.present_event(event, form, positions[cast.context.source_id], positions.get(str(event.target_id), Vector2.ZERO), "variant", cast.context)
	layers = fx.layer_snapshot()
	check(layers.any(func(layer): return layer.cue == "impact" and layer.frame >= 1), "命中或增益事件实际创建可采样图层：" + skill)
	check(layers.all(func(layer): return layer.variant_key == cast.context.variant_key), "图层保持正确形态：" + skill)
	check(cast.engine.snapshot() == committed and cast.result.events == original, "表现不改模型/RNG/原事件：" + skill)
	var retained := layers.filter(func(layer): return layer.lifetime != "action").size()
	fx.finish_action(cast.context, "variant"); fx._process(.2)
	check(fx.layer_snapshot().size() == retained, "动作结束只保留真实持续状态：" + skill)
	if retained:
		check(fx.layer_snapshot().all(func(layer): return layer.frame >= 1), "持续层在动作后仍采样循环帧：" + skill)
	fx.clear()
	check(fx.active_count() == 0 and fx.texture_memory_bytes() == 0, "离场释放物理图集：" + skill)
	fx.free()

func _test_rejected_finish_and_coherence() -> void:
	var cast := _cast("rinne","heavy_slash")
	var fx := Effects.new();root.add_child(fx);fx.set_process(false);fx.preview_pending_art=true
	_open(cast,fx,"finish")
	fx.present_event(H._event(cast.result.events,"command_accepted"),"rinne",Vector2(850,360),Vector2(850,360),"finish",cast.context)
	var wrong: Dictionary = cast.context.duplicate(true);wrong.form="homura_sword";wrong.variant_key="homura_sword-heavy_slash"
	fx.finish_action(wrong,"finish")
	check(fx.action_count()==1,"错误形态finish不得移除合法动作时钟")
	fx.cancel_action(wrong,"finish")
	check(fx._cancelled.is_empty() and fx.action_count()==1,"错误形态cancel不得占位或取消合法动作")
	fx._process(.4)
	wrong=cast.context.duplicate(true);wrong.accepted_command.actor_id="intruder"
	var damage := H._event(cast.result.events,"damage")
	check(not fx.present_event(damage,"rinne",Vector2(850,360),Vector2(300,370),"finish",wrong),"不一致接纳命令在占去重位前拒绝")
	check(fx.present_event(damage,"rinne",Vector2(850,360),Vector2(300,370),"finish",cast.context),"错误accepted_command不能吞掉正确同一事件")
	fx.finish_action(cast.context,"finish")
	check(fx.active_count()==0 and fx.texture_memory_bytes()==0,"错误收尾后正确finish仍能完全释放")
	fx.free()

func _test_redirected_enemy_visual_targets() -> void:
	var cast := _cast("guard","cover","saga_anchor_left")
	var errors: Array[String]=[];H._next_actor(cast.engine,"enemy",errors)
	check(errors.is_empty(),"远程锚敌人真实轮序")
	var before: Dictionary=cast.engine.snapshot()
	var result: Dictionary=cast.engine.submit(H._command(cast.engine,"attack_physical","",["ally"]))
	check(result.accepted and not H._event(result.events,"cover_redirected").is_empty(),"远程真实攻击确实被掩护转伤")
	var view := View.new();view.engine=cast.engine
	var nodes: Array[Node]=[]
	for id in before.actors:
		var sprite:=Node2D.new();sprite.position=_positions(cast)[id];nodes.append(sprite)
		view._actors[id]={"sprite":sprite}
	var events: Array=result.events.duplicate(true)
	view.call("_annotate_effect_context",events,cast.engine.snapshot(),before)
	var accepted:=H._event(events,"command_accepted")
	var context:Dictionary=accepted._effect_context
	check(context.effect_target_ids==["ally"],"掩护证明保留原接纳目标，不混入守卫")
	var fx:=Effects.new();root.add_child(fx);fx.set_process(false);fx.preview_pending_art=true
	view._fx_layer=fx;view._skill_effects_ready=true
	view._on_action_started(accepted,{"native_impact_seconds":0.0,"action_duration":.65})
	var flights:Array=fx._bursts.filter(func(burst):return burst.phase=="travel")
	check(flights.size()==1 and flights[0].target_id=="source","一发远程只去真实承伤守卫，不额外飞向被保护队友")
	fx.free()
	for node in nodes:node.free()
	view.free()

func _test_enemy_effect_bridge() -> void:
	var fx := Effects.new();root.add_child(fx);fx.set_process(false);fx.preview_pending_art=true
	check(fx.has_method("present_enemy_action"), "敌方沿同一图集后端播放独立攻击视觉，不冒充玩家技能事务")
	if not fx.has_method("present_enemy_action"):fx.free();return
	var enemy := F.enemy("hound","enemy")
	var ally := F.actor("guard","ally")
	var engine = H._selection(Battle,enemy,[ally])
	var before: Dictionary = engine.snapshot()
	var result: Dictionary = engine.submit(H._command(engine,"attack_physical","",["ally"]))
	check(result.accepted, "敌军真实攻击可作为效果来源")
	var context := Policy.context_from_enemy_events(before.actors,result.events)
	context["impact_delay"]=.36;context["action_duration"]=.70
	var profile := EnemyProfiles.resolve("hound",context)
	check(fx.call("present_enemy_action",context,profile,Vector2(250,350),{"ally":Vector2(800,350)},"enemy"), "敌方撕咬实际采用登记攻击图集")
	fx._process(.1)
	check(fx.hit_count()==0,"敌方起手不能提前创造命中")
	fx._process(.26)
	for event in result.events:fx.present_event(event,"",Vector2(250,350),Vector2(800,350),"enemy",context)
	check(fx.hit_count()==1,"敌方实际damage只创建一次命中图")
	check(fx._bursts.any(func(burst):return burst.get("is_hit",false) and not fx.sample_burst(burst).is_empty()),"借用物理图集的damage_recovery确实可以采样")
	check(engine.snapshot().actors.ally.hp==result.events.filter(func(event):return event.type=="damage")[0].payload.absorption.hp_after,"敌效果不改变已提交伤害")
	fx._process(.5)
	check(fx.active_count()==0 and fx.texture_memory_bytes()==0,"敌方攻击尾段释放图集")
	fx.free()
func _test_simultaneous_forms() -> void:
	var fx := Effects.new(); root.add_child(fx); fx.set_process(false); fx.preview_pending_art = true
	var rinne := _cast("rinne", "heavy_slash")
	var homura := _cast("homura_sword", "heavy_slash")
	check(_open(rinne, fx, "two") and _open(homura, fx, "two"), "共享技能ID的两形态可以并存")
	check(fx._definitions.has("rinne-heavy_slash") and fx._definitions.has("homura_sword-heavy_slash"), "纹理缓存按变体隔离")
	if fx._definitions.has("rinne-heavy_slash") and fx._definitions.has("homura_sword-heavy_slash"):
		check(fx._definitions["rinne-heavy_slash"].atlas_sha256 != fx._definitions["homura_sword-heavy_slash"].atlas_sha256, "两形态实际使用不同PNG")
	fx.free()

func _test_battle_view_bridge() -> void:
	var view := View.new()
	var bridge: Array = view.get_method_list().filter(func(method): return method.name == "_annotate_effect_context")
	check(not bridge.is_empty() and bridge[0].args.size() >= 3, "BattleView桥接收真实submit前快照")
	if bridge.is_empty() or bridge[0].args.size() < 3: view.free(); return
	var cast := _cast("rinne", "heavy_slash")
	view.engine = cast.engine
	var nodes: Array[Node] = []
	for id in cast.before.actors:
		var sprite := Node2D.new(); sprite.position = _positions(cast)[id]
		nodes.append(sprite); view._actors[id] = {"sprite":sprite}
	var events: Array = cast.result.events.duplicate(true)
	view.call("_annotate_effect_context",events,cast.engine.snapshot(),cast.before)
	var accepted := H._event(events,"command_accepted")
	var context: Dictionary = accepted.get("_effect_context",{})
	check(context.get("precast_evidence",{}).get("target_statuses",{}).has("enemy"), "真实桥保存命中前目标状态证明")
	check(context.get("variant_key","") == "rinne-heavy_slash", "真实桥携带凛音变体身份")
	var fx := Effects.new(); root.add_child(fx); fx.set_process(false); fx.preview_pending_art = true
	view._fx_layer = fx; view._skill_effects_ready = true
	view._on_action_started(accepted,{"native_impact_seconds":.4,"action_duration":1.2})
	fx._process(.05)
	check(fx.action_count() == 1 and fx.layer_snapshot().any(func(layer): return layer.phase == "cast" and layer.frame >= 1), "BattleView实际action_started启动物理起手，无施法者附件点也可用")
	fx._process(.35)
	for event in events:
		if event.type != "command_accepted": view._on_event_presented(event)
	check(fx.layer_snapshot().any(func(layer): return layer.phase == "conditional_precision" and layer.frame >= 1), "真实命中和submit前证据开启破隙层")
	view._on_effect_actor_finished(str(context.source_id))
	check(fx.active_count() == 0, "真实动作结束回调释放物理瞬态")
	fx.free()
	for node in nodes: node.free()
	view.free()

func _test_context_rejection_and_cover() -> void:
	var cast := _cast("rinne","heavy_slash")
	var fx := Effects.new(); root.add_child(fx); fx.set_process(false); fx.preview_pending_art = true
	_open(cast,fx,"identity")
	var accepted := H._event(cast.result.events,"command_accepted")
	fx.present_event(accepted,"rinne",Vector2(850,360),Vector2(850,360),"identity",cast.context)
	fx._process(.4)
	var damage := H._event(cast.result.events,"damage")
	var wrong: Dictionary = cast.context.duplicate(true); wrong.form = "homura_sword"; wrong.variant_key = "homura_sword-heavy_slash"
	check(not fx.present_event(damage,"homura_sword",Vector2(850,360),Vector2(300,370),"identity",wrong), "错误物理形态不能抢占真实事件")
	check(fx.present_event(damage,"rinne",Vector2(850,360),Vector2(300,370),"identity",cast.context), "拒绝错误形态后相同真实事件仍可呈现")
	check(fx.layer_snapshot().any(func(layer): return layer.phase == "contact_damage"), "正确事件仍建立接触层")
	fx.clear();fx.free()
	cast = _cast("guard","cover")
	fx = Effects.new();root.add_child(fx);fx.set_process(false);fx.preview_pending_art = true
	_open(cast,fx,"cover")
	for event in cast.result.events:
		fx.present_event(event,"guard",Vector2(850,360),_positions(cast).get(str(event.target_id),Vector2.ZERO),"cover",cast.context)
	fx.finish_action(cast.context,"cover")
	check(fx.layer_snapshot().size() == 2, "掩护来源动作结束后连线和状态保留")
	var errors: Array[String] = []
	H._next_actor(cast.engine,"enemy",errors)
	check(errors.is_empty(), "真实模型轮序推进到敌军")
	var before: Dictionary = cast.engine.snapshot()
	var attack: Dictionary = cast.engine.submit(H._command(cast.engine,"attack_physical","",["ally"]))
	check(attack.accepted, "后续敌军真实攻击被掩护队友")
	var context := Policy.context_from_enemy_events(before.actors,attack.events)
	context["impact_delay"] = .36; context["action_duration"] = .7
	fx.prepare_event_window(context,"cover");fx._process(.36)
	for event in attack.events:
		fx.present_event(event,"",Vector2(300,370),_positions(cast).get(str(event.target_id),Vector2.ZERO),"cover",context)
	var layers: Array = fx.layer_snapshot()
	check(layers.size() == 1 and layers[0].phase == "cover_redirected" and layers[0].frame >= 13, "真实消耗后只剩原守卫转伤反应，且有可见原帧")
	check(fx.texture_memory_bytes() > 0, "掩护消耗和转伤之间不提前释放反应图集")
	fx.finish_action(context,"cover")
	check(fx.active_count() == 0 and fx.texture_memory_bytes() == 0, "敌方动作结束释放掩护反应和最后纹理")
	fx.free()
