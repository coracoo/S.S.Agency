# 生产只开放已QA的多帧冲刺；诊断许可显式且不跨定义重配保留。
extends SceneTree
const Actor = preload("res://scripts/rpg/ui/hd_actor_view.gd")
const Player = preload("res://scripts/rpg/ui/hd_event_player.gd")
const Fixtures = preload("res://tools/characters/test_melee_approach.gd")
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",message)
func _definition(count: int, approved: Variant = false) -> Dictionary:
	var fixture := Fixtures.new()
	var definition: Dictionary = fixture._definition("guard")
	fixture.free()
	if count > 0:
		definition.frames.add_animation("battle_dash"); definition.frames.set_animation_speed("battle_dash",1000)
		for index in count: definition.frames.add_frame("battle_dash",definition.frames.get_frame_texture("attack",0),100)
		definition.manifest.anims["battle_dash"] = {"qa_approved":approved,"clean_body":true,"frames":["a","b"]}
	return definition
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	var actor := Actor.new(); var target := Node2D.new(); root.add_child(actor); root.add_child(target)
	target.position=Vector2(400,650)
	for entry in [[0,false,"缺失"],[1,true,"单帧"],[2,false,"未QA"],[2,"true","字符串伪标记"]]:
		actor.configure(_definition(entry[0],entry[1]),353.4,-1); actor.position=Vector2(1200,680)
		check(not actor.supports_melee_approach(),str(entry[2])+"不能选择生产接近")
		check(not actor.begin_melee_approach(target),str(entry[2])+"不启动首帧滑移")
		actor._process(.1)
		check(actor.position==Vector2(1200,680),str(entry[2])+"保持旧原地站位")
		check(actor.play_action(&"attack"),str(entry[2])+"仍可正常播放原地原生攻击")
		actor.cancel_action()
	actor.configure(_definition(3,true),353.4,-1); actor.position=Vector2(1200,680)
	check(actor.supports_melee_approach() and actor.begin_melee_approach(target),"有效QA多帧dash自动开放")
	actor._process(.1)
	check(actor.position.distance_to(Vector2(1200,680))>20 and actor.animator.sprite.animation==&"battle_dash","正式接近连续播放专用dash")
	actor.cancel_action(); check(actor.position==Vector2(1200,680),"取消仍精确回原站位")
	var supported := false
	for property in actor.get_property_list():
		if property.name=="allow_unapproved_melee_preview": supported=true
	check(supported,"诊断具有显式的独立许可")
	if supported:
		actor.configure(_definition(0),353.4,-1); actor.position=Vector2(1200,680)
		actor.allow_unapproved_melee_preview=true
		check(actor.begin_melee_approach(target) and actor.get_meta("melee_dash_interim_fallback",false),"只有明确诊断许可可复现旧首帧滑移")
		actor.cancel_action(); actor.configure(_definition(0),353.4,-1)
		check(not actor.allow_unapproved_melee_preview and not actor.supports_melee_approach(),"重配清掉旧诊断许可")
	var mage := _definition(3,true); mage.manifest.identity_id="homura"; mage.manifest.form_id="mage"
	actor.configure(mage,323,-1)
	check(not actor.supports_melee_approach(),"施法形态始终保持原地")
	actor.free(); target.free()
	await _queue_check(false)
	await _queue_check(true)
	print("MELEE_PRODUCTION_GATE: %d assertions, %d failures" % [checks,failures])
	quit(1 if failures else 0)
func _queue_check(approved: bool) -> void:
	var source := Actor.new(); var target := Actor.new(); var queue := Player.new()
	for node in [source,target,queue]: root.add_child(node)
	source.configure(_definition(3 if approved else 0,approved),353.4,-1)
	target.configure(_definition(0),260,1)
	source.position=Vector2(1200,680); target.position=Vector2(400,650)
	var home:=source.position
	queue.bind_actors({"s":source,"t":target})
	var seen := {"approach":-1.0,"hits":0,"position":Vector2.ZERO}
	queue.action_started.connect(func(_event,timing):seen.approach=timing.approach_seconds)
	queue.event_presented.connect(func(event):
		if event.type=="damage":seen.hits+=1;seen.position=source.position)
	queue.enqueue([{"sequence":1,"type":"command_accepted","actor_id":"s","payload":{"command":{"command_id":"gate","kind":"attack_physical","target_ids":["t"]}}},{"sequence":2,"type":"damage","actor_id":"s","target_id":"t","payload":{"damage":7,"factors":{"damage_type":"physical"}}}],{"actors":{"s":{"hp":50},"t":{"hp":43}}})
	for frame in 120:
		await process_frame
		if not queue.is_busy():break
	check(not queue.is_busy() and seen.hits==1,"真实队列只呈现一次且正常结束")
	check(seen.approach>=.18 if approved else seen.approach==0.0,"真实队列只为已QA动作添加接近时长")
	check(seen.position!=home if approved else seen.position==home,"命中时有QA接近，无QA保持原地")
	check(source.position==home,"两种生产路径均精确保持最终home")
	queue.free();source.free();target.free()
