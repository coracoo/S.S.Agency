# 七形态共用动作语义；小纹理夹具只测试状态/事件，不冒充生产素材验收。
extends SceneTree
const Animator = preload("res://scripts/characters/pixel_character_animator.gd")
const ActorView = preload("res://scripts/rpg/ui/hd_actor_view.gd")
const Events = preload("res://scripts/rpg/ui/hd_event_player.gd")
var failed := 0
var markers: Array[String] = []
var presented: Array[Dictionary] = []
func check(value: bool, message: String) -> void:
	print(("PASS: " if value else "FAIL: ") + message)
	if not value: failed += 1
func _initialize() -> void: _run.call_deferred()
func definition() -> Dictionary:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var anims := {}
	for action in ["idle", "walk", "run", "attack", "interact", "pickup", "jump", "item", "down", "recover", "hit", "defend"]:
		frames.add_animation(action)
		frames.set_animation_speed(action, 1.0)
		frames.set_animation_loop(action, action in ["idle", "walk", "run"])
		for frame in range(4): frames.add_frame(action, texture, 0.10)
		anims[action] = {"frames":["a","b","c","d"],"durations_ms":[100,100,100,100],"loop":action in ["idle","walk","run"]}
	anims.item.impact_ms = 200
	anims.attack.impact_ms = 200
	anims.interact.events = {"interact": 180}
	anims.pickup.events = {"pickup": 220}
	return {"ok":true,"frames":frames,"manifest":{"canvas":{"w":16,"h":16,"anchor":[8,15],"content_height_px":14,"height_m":1.68},"move_speed_mps":2.6,"run_speed_mps":4.2,"mirror_allowed":true,"anims":anims}}
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(1); return
	var a := Animator.new()
	root.add_child(a)
	check(a.configure(definition()),"统一动作夹具装配")
	check(a.has_method("set_locomotion_mode"),"提供显式跑步语义接口")
	if a.has_method("set_locomotion_mode"):
		a.set_locomotion_mode(&"run")
		a.set_motion(4.2,1)
		check(a.sprite.animation == "run" and is_equal_approx(a.sprite.speed_scale,1.0),"奔跑参考速度对应原生选帧周期")
		a.set_motion(2.1,-1)
		check(a.sprite.animation == "run" and is_equal_approx(a.sprite.speed_scale,0.5) and a.sprite.flip_h,"实际半速与转向不重置奔跑语义")
		a.set_motion(0,1)
		check(a.sprite.animation == "idle","堵墙/无位移时奔跑仍回待机")
		a.set_locomotion_mode(&"walk")
		a.set_motion(2.6,1)
		check(a.sprite.animation == "walk","松开跑步恢复原有行走")
	check(a.has_signal("action_marker"),"提供交互提交标记信号")
	if a.has_signal("action_marker"):
		a.action_marker.connect(func(marker: StringName): markers.append(str(marker)))
		a.request_action(&"interact")
		await create_timer(0.25).timeout
		check(markers == ["interact"] and a.is_action_locked(),"开门标记在收招前恰好一次")
		await create_timer(0.25).timeout
		check(markers == ["interact"] and not a.is_action_locked(),"标记不重复且正常解锁")
	check(a.has_method("hit_stop"),"提供独立视觉短暂停顿")
	if a.has_method("hit_stop"):
		a.request_action(&"attack")
		a.hit_stop(0.045)
		check(a.sprite.speed_scale == 0 and a.is_action_locked(),"命中短停仅冻结精灵而不解锁动作")
		a._process(0.02)
		check(a.sprite.speed_scale == 0,"命中短停未到期不推进")
		a._process(0.03)
		check(a.sprite.speed_scale == 1.0,"命中短停到期恢复原速度")
		a.reset()
	a.request_action(&"down")
	a.sprite.pause()
	for tick in range(40): a._process(1.0/60.0)
	check(a.is_downed() and a.sprite.frame == 3 and not a.sprite.is_playing(),"倒地结束信号丢失时也强制末帧保持")
	check(not a.request_action(&"item"),"倒地不能吃物品打断保持")
	check(a.request_action(&"recover"),"复苏可解除倒地")
	await create_timer(0.5).timeout
	check(not a.is_downed() and not a.is_action_locked(),"复苏结束恢复可操作")
	a.free()
	await _test_item_event()
	print("EXPANDED_ACTIONS_RESULT: ",failed)
	quit(1 if failed else 0)
func _test_item_event() -> void:
	var actor := ActorView.new()
	root.add_child(actor)
	actor.configure(definition(),168,1)
	var player := Events.new()
	root.add_child(player)
	player.bind_actors({"p":actor})
	player.event_presented.connect(func(event:Dictionary): presented.append({"type":event.type,"action":str(actor.animator.sprite.animation),"busy":actor.is_action_busy()}))
	var events := [{"type":"command_accepted","actor_id":"p","target_id":"","payload":{"command":{"command_id":"item_one","kind":"item"}}},{"type":"healed","actor_id":"p","target_id":"p","payload":{"actual":40}}]
	player.enqueue(events,{"actors":{"p":{"hp":80}}})
	await process_frame
	await process_frame
	check(actor.animator.sprite.animation == "item","使用物品播放独立item动作")
	check(presented.is_empty(),"物品使用标记前不呈现恢复事件")
	await create_timer(0.24).timeout
	check(presented.size() == 1 and presented[0].type == "healed" and presented[0].action == "item" and presented[0].busy,"恢复在item标记点呈现，来源继续收招")
	await create_timer(0.25).timeout
	check(not player.is_busy(),"物品收招后队列结束")
	presented.clear()
	player.enqueue([{"type":"actor_defeated","actor_id":"e","target_id":"p","payload":{}}],{"actors":{"p":{"hp":0}}})
	await process_frame
	await process_frame
	check(player.is_busy() and actor.animator.sprite.animation == "down","死亡队列等待个人倒地过程")
	await create_timer(0.5).timeout
	check(not player.is_busy() and actor.is_downed() and actor.animator.sprite.frame == 3,"个人战败末帧保持，结束才放行队列")
	player.free()
	actor.free()
