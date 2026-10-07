# 真实引擎炎浪三目标：直接承伤同M；原数组不改，各目标保留hit→down并等待收尾。
extends SceneTree
const F=preload("res://tools/rpg/fixtures.gd")
const Battle=preload("res://scripts/rpg/battle_engine.gd")
const Definition=preload("res://scripts/characters/pixel_character_definition.gd")
const Fixture=preload("res://tools/characters/test_imagegen_battle_view.gd").Fixture
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:_run.call_deferred()
func _run()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	for lethal in [false,true]:await _case(lethal)
	await _case(true,1)
	print("PARALLEL_IMPACT_TIMING: %d assertions, %d failures"%[checks,failures])
	quit(1 if failures else 0)
func _case(lethal:bool,target_count:int=3)->void:
	var mage:=F.actor("mage","source");mage["identity_id"]="homura";mage["form_id"]="mage";mage.stats.spd=999
	var actors:Dictionary={"source":mage}
	for i in target_count:
		var id:="e_%d"%i;var enemy:=F.enemy("hound",id);enemy.stats.hp=5000;enemy.hp=1 if lethal else 5000;actors[id]=enemy
	var engine:=Battle.new();var initialized:=engine.start({"actors":actors,"inventory":{}},112)
	check(initialized.started,"真实三敌引擎初始化")
	if not initialized.started:return
	engine.advance(false)
	var view:=Fixture.new();view.definition=Definition.load_definition("res://assets/chars/pixel/homura_mage/video_actions/manifest.json","battle");view.engine=engine;root.add_child(view)
	view._fx_layer.preview_pending_art=true;view._skill_effects_ready=true
	var before:=engine.snapshot()
	var result:=engine.submit({"command_id":"parallel-"+str(lethal),"expected_revision":before.revision,"actor_id":"source","kind":"skill","ability_id":"flame_wave","target_ids":[]})
	check(result.accepted,"真实炎浪一次接纳")
	var committed:=engine.snapshot();var original:Array=result.events.duplicate(true)
	var rows:Array[Dictionary]=[];var hits:Dictionary={};var deaths:Dictionary={};var ends:Dictionary={};var timing:Dictionary={"S":-1,"E":-1,"drained":-1}
	view._hd_player.action_started.connect(func(_event,info):timing.S=Engine.get_process_frames();timing.duration=info.action_duration;timing.impact=info.native_impact_seconds)
	view._actors.source.sprite.animator.action_finished.connect(func():timing.E=Engine.get_process_frames())
	view._hd_player.drained.connect(func():timing.drained=Engine.get_process_frames())
	view._hd_player.event_presented.connect(func(event):
		if event.type=="damage":
			hits[event.target_id]=Engine.get_process_frames()
			rows.append({"type":"damage","sequence":event.sequence,"target":event.target_id,"frame":Engine.get_process_frames(),"hp":view._actors[event.target_id].hpbar.value,"hit_layers":view._fx_layer.hit_count()})
			check(view._actors[event.target_id].hpbar.value==event.payload.absorption.hp_after,"每目标HP在自身实际事件更新")
		elif event.type=="actor_defeated":
			deaths[event.target_id]=Engine.get_process_frames();check(view._actors[event.target_id].sprite.is_downed() and (view._actors[event.target_id].sprite.is_action_busy() if target_count>1 else true),"KO信号成立且多目标hit姿态继续");rows.append({"type":"down","sequence":event.sequence,"target":event.target_id,"frame":Engine.get_process_frames()})
		elif event.type=="resources_changed":rows.append({"type":"MP","frame":Engine.get_process_frames(),"mp":view._actors.source.mpbar.value}))
	view.processing=true;view._display_actor_id="source";view._consume_events(result.events,before);view._render()
	for frame in 300:
		await process_frame
		for id in hits:
			var actor:Node=view._actors[id].sprite
			if not actor.is_action_busy() and not ends.has(id):ends[id]=Engine.get_process_frames()
			if lethal:
				var body:Sprite3D=view._world_backdrop.actor_entries[id].body
				var tint:Color=body.material_override.get_shader_parameter("appearance_tint")
				check(absf(tint.a-.55)<.0001,"实际材质KO alpha在每个相邻帧只应用一次")
				if ends.has(id) and Engine.get_process_frames()>int(ends[id])+1:
					check(tint.is_equal_approx(Color(.4,.4,.4,.55)),"hit尾段后实际灰色保持，不二次变暗")
		if not view._hd_player.is_busy():break
	print("PARALLEL_TIMELINE:",JSON.stringify({"lethal":lethal,"target_count":target_count,"timing":timing,"rows":rows,"reaction_end":ends}))
	check(hits.size()==target_count,"每名实际承伤者各一次")
	check(hits.values().all(func(frame):return frame==hits.values()[0]),"同一命令不同目标直接伤害共用同一M")
	var damage_rows:=rows.filter(func(row):return row.type=="damage")
	check(damage_rows.map(func(row):return row.target)==(["e_0","e_1","e_2"] if target_count==3 else ["e_0"]),"直接承伤目标顺序服从原事件")
	if lethal:
		check(deaths.size()==target_count,"每个实际死亡各呈现一次")
		for id in deaths:
			check(deaths[id]==hits[id] if target_count>1 else deaths[id]>hits[id],"多目标KO不跨序；单目标仍保持既有受击后KO信号")
			check(int(ends.get(id,0))-int(hits[id])>=10,"逻辑KO后仍保留每目标必要hit反应时长")
	check(int(timing.drained)>=int(timing.E) and ends.values().all(func(frame):return frame<=timing.drained),"队列等来源E及必要目标反应结束才开放")
	var signals:=rows.filter(func(row):return row.has("sequence")).map(func(row):return row.sequence)
	var expected:=original.filter(func(event):return event.type in ["damage","actor_defeated"]).map(func(event):return event.sequence)
	check(signals==expected,"全部damage/KO信号维持原sequence顺序")
	check(engine.snapshot()==committed and result.events==original,"不改模型数值/RNG/权威事件数组")
	view.free()
