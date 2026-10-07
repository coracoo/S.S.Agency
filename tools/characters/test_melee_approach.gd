# 真实人物/事件队列的有限近战位移；夹具仅缩小纹理，不替换被测动作与事件类。
extends SceneTree
const Actor = preload("res://scripts/rpg/ui/hd_actor_view.gd")
const Player = preload("res://scripts/rpg/ui/hd_event_player.gd")
const Backdrop = preload("res://scripts/rpg/ui/battle_world_backdrop.gd")
var failures := 0
var assertions := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		print("FAIL: " + message)

func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	for identity in ["rinne", "guard", "homura"]:
		for facing in [-1, 1]:
			for distance in [420.0, 900.0]:
				await _test_strike(identity, facing, distance)
	await _test_multi_target()
	await _test_stationary()
	await _test_cancel()
	await _test_duplicate()
	await _test_stale_duplicate_snapshot()
	await _test_dash_and_native_timing()
	await _test_reconfiguration()
	await _test_reflection_and_revive()
	await _test_rendered_ground()
	print("MELEE_APPROACH: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)

func _definition(identity: String, form: String = "", duration: float = .6, impact: float = .24) -> Dictionary:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var image := Image.create(20, 40, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	for action in ["idle", "attack", "hit", "item", "defend", "down", "recover"]:
		frames.add_animation(action)
		frames.set_animation_speed(action, 1000.0)
		frames.set_animation_loop(action, action == "idle")
		frames.add_frame(action, texture, duration * 500.0 if action == "attack" else 40.0)
		frames.add_frame(action, texture, duration * 500.0 if action == "attack" else 40.0)
	return {"ok":true,"frames":frames,"layer_frames":[],"manifest":{"identity_id":identity,"form_id":form if not form.is_empty() else identity,"move_speed_mps":2.6,"mirror_allowed":true,"canvas":{"w":20,"h":40,"anchor":[10,39],"content_height_px":38,"height_m":1.7},"anims":{"attack":{"impact_ms":impact*1000}}}}

func _fixture(identity: String = "guard", facing: int = -1, distance: float = 700.0, form: String = "") -> Dictionary:
	var source := Actor.new()
	var target := Actor.new()
	var player := Player.new()
	for node in [source,target,player]: root.add_child(node)
	source.configure(_definition(identity,form), 320.0, facing)
	# 历史组件夹具故意保留缺dash场景；生产许可由独立gate门禁覆盖。
	source.allow_unapproved_melee_preview = true
	target.configure(_definition("enemy"), 260.0, -facing)
	source.position = Vector2(1450 if facing < 0 else 470, 680)
	target.position = source.position + Vector2(distance * facing, -30)
	source.set_meta("foot_point", source.position)
	target.set_meta("foot_point", target.position)
	target.set_meta("content_height", 260.0)
	target.set_meta("melee_body_radius_px", 48.0)
	player.bind_actors({"s":source,"t":target})
	return {"s":source,"t":target,"p":player,"home":source.position,"facing":facing,"snapshot":{"actors":{"s":{"hp":50},"t":{"hp":43}}}}

func _events(id: String = "one", kind: String = "attack_physical", damage_type: String = "physical", targets: Array = ["t"]) -> Array:
	var values: Array = [{"sequence":1,"type":"command_accepted","actor_id":"s","payload":{"command":{"command_id":id,"kind":kind,"target_ids":targets},"resolved_target_ids":targets}}]
	for index in targets.size():
		values.append({"sequence":index+2,"type":"damage","actor_id":"s","target_id":targets[index],"payload":{"damage":7,"factors":{"damage_type":damage_type}}})
	return values

func _wait_done(f: Dictionary) -> void:
	for tick in 300:
		if not f.p.is_busy(): return
		await process_frame
	check(false,"表现队列必须有限结束")

func _free(f: Dictionary) -> void:
	for key in ["p","s","t","u"]:
		if f.has(key) and is_instance_valid(f[key]): f[key].free()

func _test_strike(identity: String, facing: int, distance: float) -> void:
	var f := _fixture(identity,facing,distance,"sword" if identity == "homura" else "")
	var records: Array = []
	var clock := [0.0]
	f.p._frame_tick.connect(func(delta): clock[0] += delta)
	f.p.event_presented.connect(func(event):
		if event.type == "damage": records.append({"at":f.s.position,"time":clock[0],"animation":f.s.animator.sprite.animation,"busy":f.s.is_action_busy()}))
	var original: Array = _events().duplicate(true)
	f.p.enqueue(original,f.snapshot)
	var saw_transit := false
	var saw_recovery_move := false
	var original_scale: Vector2 = f.s.animator.scale
	for tick in 300:
		await process_frame
		var moved: float = f.s.position.distance_to(f.home)
		if records.is_empty() and moved > 20.0: saw_transit = true
		if not records.is_empty() and moved > 1.0 and f.s.position.distance_to(records[0].at) > 1.0 and f.s.is_action_busy(): saw_recovery_move = true
		check(f.s.animator.scale == original_scale,"闪身不逐帧改变身高")
		if not f.p.is_busy(): break
	var name := "%s/%d/%.0f" % [identity,facing,distance]
	check(records.size() == 1,"伤害呈现恰好一次："+name)
	check(saw_transit,"命中前可见接近敌人："+name)
	if records.size() == 1:
		var at: Vector2 = records[0].at
		check(at.distance_to(f.home) > distance * .4,"接近距离取决于实际目标而非固定轻推："+name)
		check(at.distance_to(f.t.position) < 240.0,"命中发生在敌人身体/武器可达范围："+name)
		check((f.t.position.x-at.x)*facing > 0,"停在目标前方，不越过敌人："+name)
		check(records[0].time >= .42 and records[0].time < .53,"先到达，再按原生240ms命中："+name)
		check(records[0].animation == &"attack" and records[0].busy,"命中仍处于原生攻击")
	check(saw_recovery_move,"收招期间可见返回："+name)
	check(f.s.position == f.home and not f.p.is_busy(),"收招后精确回到站位并解锁："+name)
	check(f.s._facing == facing,"返回后恢复原朝向")
	check(original == _events(),"不写入已提交事件")
	_free(f)

func _test_multi_target() -> void:
	var f := _fixture("rinne")
	f.u = Actor.new(); root.add_child(f.u)
	f.u.configure(_definition("enemy"),260,1)
	f.u.position = Vector2(450,620)
	f.p.bind_actors({"s":f.s,"t":f.t,"u":f.u})
	f.snapshot.actors.u = {"hp":43}
	var hits: Array = []
	f.p.event_presented.connect(func(event):
		if event.type == "damage": hits.append({"target":event.target_id,"foot":f.s.position}))
	f.p.enqueue(_events("sweep","skill","physical",["t","u"]),f.snapshot)
	await _wait_done(f)
	check(hits.size() == 2 and hits[0].target == "t" and hits[1].target == "u","群攻保持原事件顺序，各目标只呈现一次")
	if hits.size() == 2: check(hits[0].foot.distance_to(f.t.position) < 240,"群攻选首个有效实际承伤者作为接近代表")
	check(f.s.position == f.home,"群攻完成仅返回一次原站位")
	_free(f)

func _test_stationary() -> void:
	for entry in [["mint","","attack_physical","physical"],["homura","mage","attack_magic","magic"],["healer","","attack_physical","physical"],["guard","","skill","magic"],["guard","","defend","physical"],["guard","","item","physical"]]:
		var f := _fixture(entry[0],-1,700,entry[1])
		f.p.enqueue(_events("anchored",entry[2],entry[3]),f.snapshot)
		for tick in 200:
			await process_frame
			check(f.s.position == f.home,"投石/法术/防御/道具全程保持原地："+str(entry))
			if not f.p.is_busy(): break
		_free(f)

func _test_cancel() -> void:
	for stage in ["approach","strike","return","rebind","down","dead_target","exit"]:
		var f := _fixture()
		if stage == "down": f.snapshot.actors.s.hp = 0
		if stage == "dead_target": f.snapshot.actors.t.hp = 0
		var hits: Array = []
		f.p.event_presented.connect(func(event):
			if event.type == "damage": hits.append(event))
		f.p.enqueue(_events(),f.snapshot)
		var frames := 7 if stage in ["approach","rebind","down","dead_target","exit"] else (19 if stage == "strike" else 44)
		for tick in frames: await process_frame
		if stage == "dead_target": f.t.set_downed(true)
		elif stage == "down": f.s.set_downed(true)
		elif stage == "rebind": f.p.bind_actors({"s":f.s,"t":f.t})
		elif stage == "exit": root.remove_child(f.p)
		else: f.p.cancel()
		for tick in 100: await process_frame
		check(f.s.position == f.home,"中断/目标失效不会遗留位移："+stage)
		if stage in ["approach","strike","rebind","exit"]: check(hits.is_empty(),"取消后旧协程不能迟发命中："+stage)
		if stage == "down": check(f.s.is_downed(),"回程不能覆盖新的倒地姿态")
		if stage == "dead_target": check(f.t.is_downed(),"失效目标不会被旧hit改为站姿")
		_free(f)

func _test_duplicate() -> void:
	var f := _fixture()
	var hits: Array = []
	f.p.event_presented.connect(func(event):
		if event.type == "damage": hits.append(event))
	var events := _events("duplicate")
	f.p.enqueue(events,f.snapshot)
	f.p.enqueue(events,f.snapshot)
	await _wait_done(f)
	check(hits.size() == 1,"重入同一已提交sequence不会重复命中特效")
	check(f.s.position == f.home,"重复批次不会二次移动或改变原站位")
	_free(f)

func _test_dash_and_native_timing() -> void:
	for timing in [[.32,.10],[1.35,.83]]:
		var f := _fixture()
		var definition := _definition("guard","guard",timing[0],timing[1])
		var frames: SpriteFrames = definition.frames
		frames.add_animation(&"battle_dash")
		frames.set_animation_speed(&"battle_dash",1000.0)
		frames.set_animation_loop(&"battle_dash",false)
		for index in 4:
			var image := Image.create(20,40,false,Image.FORMAT_RGBA8)
			image.fill(Color.from_hsv(index*.2,.8,1))
			frames.add_frame(&"battle_dash",ImageTexture.create_from_image(image),40)
		definition.manifest.anims["battle_dash"]={"qa_approved":true}
		f.s.configure(definition,320,-1)
		var seen := {}
		var hits: Array = []
		var started: Array = []
		var elapsed := [0.0]
		f.p._frame_tick.connect(func(delta): elapsed[0] += delta)
		f.p.action_started.connect(func(event, info): started.append({"command":event,"info":info,"foot":f.s.position}))
		f.p.event_presented.connect(func(event):
			if event.type == "damage": hits.append(elapsed[0]))
		f.p.enqueue(_events(),f.snapshot)
		for tick in 250:
			await process_frame
			if f.s.animator.sprite.animation == &"battle_dash": seen[f.s.animator.sprite.frame] = true
			if not f.p.is_busy(): break
		check(seen.size() >= 3,"200ms接近必须真的推进多帧dash姿势")
		check(not f.s.get_meta("melee_dash_interim_fallback",true),"有battle_dash时不使用静止滑动降级")
		check(hits.size()==1 and absf(float(hits[0])-(.20+float(timing[1]))) <= .05,"命中使用新原生时长与marker，不硬编码旧动画")
		check(started.size()==1,"每个接纳动作只发一次动作起始信号")
		if started.size()==1:
			check(started[0].foot.distance_to(f.t.position)<240,"动作起始信号在真实抵达之后")
			check(started[0].command==_events()[0],"FX收到只读原始指令上下文")
			check(absf(float(started[0].info.native_impact_seconds)-float(timing[1]))<.001,"FX相对动作起始的命中时长不重复加接近时间")
			check(absf(float(started[0].info.total_impact_delay)-(.20+float(timing[1])))<.04,"FX另有完整接近加命中元数据")
		check(f.s.position==f.home,"不同原生时长均精确归位")
		_free(f)

func _test_stale_duplicate_snapshot() -> void:
	var f := _fixture()
	var first := _events("lethal")
	first.append({"sequence":3,"type":"actor_defeated","actor_id":"s","target_id":"t","payload":{}})
	var dead: Dictionary = f.snapshot.duplicate(true)
	dead.actors.t.hp = 0
	f.p.enqueue(first,dead)
	await _wait_done(f)
	check(f.t.is_downed(),"首次致死批次正常保留down")
	f.p.enqueue([{"sequence":4,"type":"revived","actor_id":"s","target_id":"t","payload":{"hp":43}}],f.snapshot)
	await _wait_done(f)
	check(not f.t.is_downed(),"新批次正常显示复苏")
	f.p.enqueue(first,dead)
	await _wait_done(f)
	check(not f.t.is_downed(),"全重复旧批次的旧快照不能覆盖已经显示的新复苏")
	_free(f)

func _test_reconfiguration() -> void:
	for mode in ["configure","action_callback","move_callback","free_target","free_source","paused_source"]:
		var f := _fixture()
		var starts: Array = []
		f.p.action_started.connect(func(event,info): starts.append(event))
		if mode=="move_callback": f.s.presentation_position_changed.connect(func():
			if f.s.position!=f.home: f.p.cancel())
		if mode=="action_callback": f.p.action_started.connect(func(_event,_info): f.p.cancel())
		f.p.enqueue(_events(),f.snapshot)
		for tick in 5: await process_frame
		if mode=="configure": f.s.configure(_definition("homura","mage"),320,-1)
		if mode=="free_target": f.t.free()
		if mode=="free_source": f.s.free()
		if mode=="paused_source": f.s.set_process(false)
		await _wait_done(f)
		if mode=="configure":
			check(starts.is_empty(),"重配人物后旧接近协程不能启动新形态的攻击")
			check(f.s.animator.sprite.animation==&"idle","重配后保留新形态站姿")
		if is_instance_valid(f.s): check(f.s.position==f.home,"中途重配/信号取消/释放精确归位："+mode)
		check(not f.p.is_busy(),"中途重配/信号取消/释放有限结束："+mode)
		_free(f)

func _test_rendered_ground() -> void:
	var f := _fixture()
	var backdrop := Backdrop.new()
	root.add_child(backdrop)
	backdrop.configure({"position":[-4.5,.03,.45]})
	backdrop.bind_visuals({"s":{"sprite":f.s},"t":{"sprite":f.t}})
	f.s.configure_melee_bounds(Rect2(180,600,1560,110))
	f.s.presentation_position_changed.connect(func(): backdrop.sync_visuals(0.0))
	var body: Sprite3D = backdrop.actor_entries.s.body
	var shadow: MeshInstance3D = backdrop.actor_entries.s.shadow
	var world_home := body.position
	var native_scale := body.pixel_size
	var hits: Array = []
	f.p.event_presented.connect(func(event):
		if event.type == "damage": hits.append({"world":body.position,"gap":body.position.distance_to(backdrop.actor_entries.t.body.position)}))
	f.p.enqueue(_events(),f.snapshot)
	for tick in 200:
		await process_frame
		check(backdrop.camera.unproject_position(body.position).distance_to(f.s.position)<.01,"真正Sprite3D脚点每帧同步接近与回程")
		check(is_equal_approx(body.position.y,backdrop.stage_origin.y),"全程沿地面移动，没有空中脚点")
		check(shadow.position.distance_to(body.position+Vector3(0,.014,0))<.001,"真实接触阴影跟随实际身体")
		check(is_equal_approx(body.pixel_size,native_scale),"实际3D角色无逐帧缩放")
		if not f.p.is_busy(): break
	check(hits.size()==1,"真实3D世界仅收到一次命中")
	if hits.size()==1:
		check(hits[0].world.distance_to(world_home)>1.0,"真正绘制的身体确实离开站位")
		check(hits[0].gap<1.25,"真实地面命中距离小于1.25米")
		print("MELEE_WORLD_HIT: home=",world_home," strike=",hits[0].world," gap_m=",hits[0].gap," returned=",body.position)
	check(body.position==world_home,"实际Sprite3D最终精确回到原世界位置")
	backdrop.free()
	_free(f)

func _test_reflection_and_revive() -> void:
	var f := _fixture()
	var events := _events()
	events.append({"sequence":3,"type":"actor_defeated","actor_id":"t","target_id":"s","payload":{}})
	f.snapshot.actors.s.hp = 0
	var defeat_feet: Array = []
	f.p.event_presented.connect(func(event):
		if event.type=="actor_defeated": defeat_feet.append(f.s.position))
	f.p.enqueue(events,f.snapshot)
	await _wait_done(f)
	check(defeat_feet==[f.home] and f.s.is_downed(),"收招中来源被反伤倒地：先复位再显示down，旧回程不复活")
	var revive := [{"sequence":4,"type":"command_accepted","actor_id":"t","payload":{"command":{"command_id":"revive","kind":"item","target_ids":["s"]}}},{"sequence":5,"type":"revived","actor_id":"t","target_id":"s","payload":{"hp":20}}]
	f.snapshot.actors.s.hp = 20
	f.p.enqueue(revive,f.snapshot)
	await _wait_done(f)
	check(not f.s.is_downed() and f.s.position==f.home,"下一次复苏留在精确home，旧回程不会重新覆盖恢复姿态")
	check(f.s.animator.sprite.animation==&"idle","复苏完整结束后正常回到待机")
	_free(f)
