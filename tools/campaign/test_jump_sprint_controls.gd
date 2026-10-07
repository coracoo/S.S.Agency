# 七章真实舞台的键盘回归；进度只由隔离事务夹具建立，不代表人工通关。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Fixture = preload("res://tools/campaign/world_action_fixture.gd")
const Saga = preload("res://scripts/campaign/saga_catalog.gd")
var failures: Array[String] = []
var assertions := 0
var evidence: Array[Dictionary] = []
var jump_markers: Array[StringName] = []

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		printerr("ASSERT FAIL: ", message)

func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()

func key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	event.shift_pressed = Input.is_physical_key_pressed(KEY_SHIFT) and code != KEY_SHIFT
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func release_keys() -> void:
	for code in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_SHIFT, KEY_SPACE, KEY_M, KEY_ESCAPE, KEY_E]: key(code, false)

func frames(count: int) -> void:
	for index in count: await physics_frame
	await process_frame

func _run() -> void:
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.keycode = KEY_SPACE
	check(not InputMap.event_is_action(space, "ui_interact"), "空格不再兼任旧调查动作，避免同一跳跃键触发互动")
	space.physical_keycode = KEY_E
	space.keycode = KEY_E
	check(InputMap.event_is_action(space, "ui_interact"), "旧调查仍可使用E键")
	var session := Session.new()
	check(session.start_new(true).ok, "从隔离正式新局建立首章")
	check(session.commit_event(session.campaign.safe_snapshot().world, "dialogue:a1").ok, "首章开场事务夹具防止移动测试自动进入对白")
	await _test_stage(session, 1)
	check(Fixture.complete_first(session.campaign) and session.campaign.continue_saga().ok, "合法事务夹具进入后六章")
	for chapter in range(2, 8):
		check(int(session.campaign.safe_snapshot().saga.chapter) == chapter, "正式会话抵达第%d章" % chapter)
		await _test_stage(session, chapter)
		if chapter < 7 and not _advance_chapter(session, chapter): break
	release_keys()
	session.close()
	var output := OS.get_environment("ACT_ONE_OUTPUT")
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("jump-sprint-controls.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"kind":"真实七章舞台输入与物理回归", "manual_gui":false, "progress":"隔离事务夹具", "jump_semantics":"原地视觉短跳，导航胶囊接地，不扩大地图可达边界", "assertions":assertions, "failures":failures, "chapters":evidence}, "  "))
	print("JUMP_SPRINT_CONTROLS_ASSERTIONS:", assertions, " FAILURES:", failures.size())
	quit(0 if failures.is_empty() else 1)

func _test_stage(session: RefCounted, chapter: int) -> void:
	release_keys()
	var scene_path := str(session.campaign.safe_snapshot().world.scene_path)
	var stage: Node3D = load(scene_path).instantiate()
	root.add_child(stage)
	for index in 900:
		await frames(1)
		if stage.ready_for_play or not stage.last_error.is_empty(): break
	check(stage.ready_for_play and stage.controls_enabled, "第%d章正式场景可探索：%s" % [chapter, stage.last_error])
	if not stage.ready_for_play:
		stage.free()
		return
	await frames(5)
	var player: CharacterBody3D = stage.player
	var at := player.position
	var story_before: Dictionary = session.campaign.safe_snapshot()
	key(KEY_D, true)
	await frames(10)
	var walking := Vector2(player.position.x-at.x, player.position.z-at.z).length()
	check(player.animator.sprite.animation == &"walk", "第%d章方向键真实选择行走动画" % chapter)
	key(KEY_D, false)
	await frames(2)
	player.position = at
	player.velocity = Vector3.ZERO
	key(KEY_SHIFT, true)
	key(KEY_D, true)
	await frames(10)
	var running := Vector2(player.position.x-at.x, player.position.z-at.z).length()
	check(running > walking * 1.4 and walking > .1, "第%d章按住Shift产生更快的真实平面位移" % chapter)
	check(player.animator.sprite.animation == &"run", "第%d章Shift选择原有跑步动画" % chapter)
	key(KEY_SHIFT, false)
	await frames(3)
	check(not player.run_input and player.animator.sprite.animation == &"walk", "第%d章释放Shift立即恢复行走" % chapter)
	key(KEY_D, false)
	await frames(3)
	check(player.animator.sprite.animation == &"idle", "第%d章松开方向后回到待机" % chapter)
	player.position = at
	player.velocity = Vector3.ZERO
	await frames(4)
	jump_markers.clear()
	var marker_listener := func(marker: StringName): jump_markers.append(marker)
	player.animator.action_marker.connect(marker_listener)
	key(KEY_SPACE, true)
	await frames(2)
	check(player._hop_duration > 0 and player.animator.sprite.animation == &"jump", "第%d章空格事件经真实输入路径启动跳跃" % chapter)
	var generation: int = player.animator._generation
	var max_frame := 0
	var grounded := true
	var pulse_seen := false
	for index in 300:
		await frames(1)
		max_frame = maxi(max_frame, player.animator.sprite.frame if player.animator.sprite.animation == &"jump" else 0)
		grounded = grounded and player.is_on_floor() and player.position.distance_to(at) < .04
		pulse_seen = pulse_seen or player._jump_feedback.pulse.visible
		if index == 5: key(KEY_SPACE, true, true)
		if player._hop_duration <= 0 and not player.animator.is_action_locked(): break
	await frames(5)
	check(max_frame > 0 and jump_markers.has(&"landing") and pulse_seen, "第%d章原跳跃动画逐帧播放并触发落地反馈" % chapter)
	check(grounded and player.billboard.position.y == 0, "第%d章短跳胶囊接地、未跨越地图边界且回到原脚锚" % chapter)
	check(player.animator._generation == generation and player._hop_duration == 0, "第%d章长按/重复空格不连续跳跃" % chapter)
	key(KEY_SPACE, false)
	await frames(3)
	key(KEY_SPACE, true)
	await frames(2)
	check(player._hop_duration > 0, "第%d章释放空格后可再次跳跃" % chapter)
	key(KEY_M, true)
	key(KEY_M, false)
	await frames(3)
	check(stage._mode == "map" and not stage.controls_enabled and player._hop_duration == 0, "第%d章打开地图取消跳跃并锁住操作" % chapter)
	key(KEY_SHIFT, true)
	key(KEY_D, true)
	await frames(5)
	check(player.position.distance_to(at) < .04 and not player.run_input, "第%d章地图中按跑步与方向不移动" % chapter)
	key(KEY_M, true)
	key(KEY_M, false)
	await frames(5)
	check(stage.controls_enabled and player.position.distance_to(at) < .04 and player._hop_duration == 0, "第%d章关闭地图后仍按住的跑步/空格不漏入探索" % chapter)
	key(KEY_A, true)
	key(KEY_SPACE, false)
	key(KEY_SHIFT, false)
	await frames(3)
	check(not player._movement_armed, "第%d章A+D合成零轴不冒充全部松键" % chapter)
	key(KEY_A, false)
	key(KEY_D, false)
	await frames(3)
	key(KEY_D, true)
	await frames(5)
	check(player.position.distance_to(at) > .1, "第%d章全部松键后可重新移动" % chapter)
	release_keys()
	await frames(3)
	check(session.campaign.safe_snapshot() == story_before, "第%d章跳跑与地图不提交剧情或奖励" % chapter)
	key(KEY_ESCAPE, true)
	key(KEY_ESCAPE, false)
	await frames(4)
	check(not stage.controls_enabled and (is_instance_valid(stage._party_panel) or is_instance_valid(stage._modal)), "第%d章Esc打开真实菜单并锁住探索" % chapter)
	var menu_at := player.position
	key(KEY_SHIFT, true)
	key(KEY_D, true)
	key(KEY_SPACE, true)
	await frames(5)
	check(player.position.distance_to(menu_at) < .04 and player._hop_duration == 0 and not player.run_input, "第%d章整备中方向/Shift/空格不触发跳跑" % chapter)
	for attempt in 2:
		if stage.controls_enabled: break
		key(KEY_ESCAPE, true)
		key(KEY_ESCAPE, false)
		await frames(3)
	check(stage.controls_enabled and player.position.distance_to(menu_at) < .04, "第%d章Esc关闭整备后持续按键仍需松开" % chapter)
	release_keys()
	await frames(3)
	key(KEY_SPACE, true)
	await frames(2)
	check(player._hop_duration > 0, "第%d章整备关闭并全松键后空格可再次起跳" % chapter)
	release_keys()
	player.animator.action_marker.disconnect(marker_listener)
	evidence.append({"chapter":chapter, "walk_distance":walking, "run_distance":running, "jump_max_frame":max_frame, "landing_marker":jump_markers.has(&"landing"), "landing_pulse":pulse_seen, "capsule_stays_grounded":grounded})
	print("JUMP_SPRINT_CHAPTER:", chapter, " WALK:", walking, " RUN:", running, " LANDING:", pulse_seen)
	stage.shutdown()
	stage.free()
	await frames(2)

func _advance_chapter(session: RefCounted, chapter: int) -> bool:
	# 此处只构造下一章合法存档；不声称真实战斗或GUI通关。
	var model: RefCounted = session.campaign
	for step in 80:
		var state: Dictionary = model.safe_snapshot()
		if int(state.saga.chapter) > chapter: return true
		var id := str(state.saga.active_scene if not str(state.saga.active_scene).is_empty() else state.saga.scene)
		var began: Dictionary = model.begin_saga_scene(state.world, id)
		if not began.ok: check(false, "夹具开始场次失败："+id+str(began)); return false
		state = model.safe_snapshot()
		var options := Saga.eligible_choices(Saga.scene(id), state.saga)
		if not options.is_empty():
			var selected := str(options[0].id)
			if id == "C3-06": selected = "b"
			var picked: Dictionary = model.choose_saga_option(state.world, id, selected)
			if not picked.ok: check(false, "夹具选择失败："+id+str(picked)); return false
		state = model.safe_snapshot()
		if not str(state.world.story_encounter).is_empty() and not state.saga.battles.has(id):
			var started: Dictionary = session.begin_encounter(state.world, id)
			if not started.ok: check(false, "夹具进战失败："+id+str(started)); return false
			var won: Dictionary = session.router.finish(Fixture.victory(model, started))
			if not won.ok: check(false, "夹具结算失败："+id+str(won)); return false
		var completed: Dictionary = model.complete_saga_scene(model.safe_snapshot().world, id)
		if not completed.ok: check(false, "夹具完成失败："+id+str(completed)); return false
	check(false, "夹具章节推进超时："+str(chapter))
	return false
