# 同目标多击、周期、反射、取消与目标重绑边界使用真正演员/队列，不修改规则。
extends SceneTree
const Actor=preload("res://scripts/rpg/ui/hd_actor_view.gd")
const Player=preload("res://scripts/rpg/ui/hd_event_player.gd")
const Actions=preload("res://tools/characters/test_expanded_actions.gd")
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:_run.call_deferred()
func _run()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	for mode in ["repeat_target","periodic","reflect","cancel","rebind"]:await _case(mode)
	print("PARALLEL_IMPACT_BOUNDARIES: %d assertions, %d failures"%[checks,failures])
	quit(1 if failures else 0)
func _case(mode:String)->void:
	var fixture:=Actions.new();var definition:=fixture.definition();fixture.free()
	definition.manifest["identity_id"]="homura";definition.manifest["form_id"]="mage"
	var source:=Actor.new();var a:=Actor.new();var b:=Actor.new();var player:=Player.new()
	for actor in [source,a,b]:root.add_child(actor);actor.configure(definition,300,1)
	root.add_child(player);player.bind_actors({"source":source,"a":a,"b":b})
	var events:Array=[{"sequence":1,"type":"command_accepted","actor_id":"source","payload":{"command":{"command_id":mode,"kind":"skill","ability_id":"flame_wave","target_ids":["a","b"]}}}]
	var kinds:= ["damage","damage","damage"] if mode=="repeat_target" else (["damage","periodic_damage","damage"] if mode=="periodic" else (["damage","saga_reflected","damage"] if mode=="reflect" else ["damage","damage"]))
	for i in kinds.size():events.append({"sequence":i+2,"type":kinds[i],"actor_id":"source","target_id":"b" if i==kinds.size()-1 else "a","payload":{"damage":3}})
	var original:=events.duplicate(true)
	var observed:Array[Dictionary]=[];var changed:Dictionary={"rebound":false,"stale_hit":false}
	player.event_presented.connect(func(event):
		observed.append({"sequence":event.sequence,"type":event.type,"frame":Engine.get_process_frames()})
		if event.get("sequence")==2:
			if mode=="cancel":player.cancel()
			elif mode=="rebind":a.configure(definition,300,-1);changed.rebound=true)
	player.enqueue(events,{"actors":{"source":{"hp":50},"a":{"hp":44},"b":{"hp":47}}})
	for frame in 240:
		await process_frame
		if changed.rebound and a.animator.sprite.animation==&"hit":changed.stale_hit=true
		if not player.is_busy():break
	if mode in ["repeat_target","periodic","reflect"]:
		check(observed.size()==3 and observed[1].frame>observed[0].frame,mode+"保持既有串行反应边界")
		check(observed.map(func(event):return event.sequence)==[2,3,4],mode+"不重排或重复事件")
	elif mode=="cancel":
		for frame in 30:await process_frame
		check(observed.size()==1 and not player.is_busy(),"同M首个回调取消后不再呈现第二目标")
		check(player._target_reactions.is_empty(),"取消释放所有并行反应引用")
	else:
		check(observed.size()==2 and not changed.stale_hit,"目标在damage回调重绑后旧hit不得覆盖新姿态")
	check(events==original,"边界夹具原事件数组保持不变："+mode)
	player.free();source.free();a.free();b.free()
