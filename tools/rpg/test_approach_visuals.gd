# 表现测试只读取模型快照；真实高清资源与小画布动作夹具分别验证持有和事件顺序。
extends RefCounted
const F = preload("res://tools/rpg/fixtures.gd")
const Profile = preload("res://scripts/exploration_3d/trial_profile.gd")
const Definition = preload("res://scripts/characters/pixel_character_definition.gd")
const Presenter = preload("res://scripts/rpg/ui/battle_presenter.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []
	for path in ["res://scripts/characters/party_asset_bundle.gd", "res://scripts/rpg/ui/hd_actor_view.gd", "res://scripts/rpg/ui/hd_event_player.gd"]:
		F.expect(FileAccess.file_exists(path), "缺少高清表现接口：" + path, failures)
	if not failures.is_empty(): return failures
	await _test_bundle(failures)
	await _test_actor(failures)
	await _test_events(failures)
	await _test_cancel_unwinds(failures)
	_test_names(failures)
	return failures

static func _test_bundle(failures: Array[String]) -> void:
	var Bundle = load("res://scripts/characters/party_asset_bundle.gd")
	for key in ["rinne", "mint", "guard", "homura_sword", "homura_mage", "healer", "controller"]:
		F.expect(Bundle.MANIFESTS.get(key) == "res://assets/chars/pixel/%s/video_actions/manifest.json" % key, "七形态正式映射不得遗留静态占位：" + key, failures)
	var bundle = Bundle.new()
	var progress: Array = []
	bundle.progress.connect(func(completed, total): progress.append([completed, total]))
	var prepared: Dictionary = await bundle.prepare(Profile.BINDINGS)
	F.expect(prepared.get("ok", false), "三人高清资源可预加载", failures)
	if not prepared.get("ok", false): return
	F.expect(progress == [[1, 3], [2, 3], [3, 3]], "每个选定人物报告一次加载进度", failures)
	var weak: WeakRef
	for id in ["rinne", "mint", "guard"]:
		var definition: Dictionary = bundle.get_definition(id)
		F.expect(definition.get("ok", false) and definition.manifest.dir == "res://assets/chars/pixel/%s/video_actions/frames/" % id and definition.manifest.has("packed_frames"), id + "严格使用已验视频图集白名单", failures)
		F.expect(definition.manifest.identity_id == id, id + "身份未变成职业", failures)
		if id == "rinne": weak = weakref(definition.frames.get_frame_texture("idle", 0))
	F.expect(bundle.get_definition("homura").is_empty() and bundle.get_definition("healer").is_empty(), "不预载其它人物或形态", failures)
	var original: Dictionary = bundle.get_definition("rinne")
	var second: Dictionary = Definition.load_definition(Bundle.MANIFESTS.rinne, "battle")
	var world: Dictionary = Definition.load_definition(Bundle.MANIFESTS.rinne, "world")
	F.expect(second.ok and world.ok and _atlas_page(original.frames.get_frame_texture("idle", 0)).get_rid() == _atlas_page(second.frames.get_frame_texture("idle", 0)).get_rid() and _atlas_page(world.frames.get_frame_texture("idle", 0)).get_rid() == _atlas_page(second.frames.get_frame_texture("idle", 0)).get_rid(), "探索与战斗共享相同底层PNG页，而非要求各Atlas视图对象相同", failures)
	F.expect(not world.frames.has_animation("attack") and not second.frames.has_animation("walk"), "世界与战斗不额外加载对方专用动作", failures)
	world.clear()
	second.clear()
	original.clear()
	prepared = await bundle.prepare(Profile.BINDINGS)
	F.expect(prepared.ok and progress.size() == 3, "重复prepare保持已有定义且不重新解码", failures)
	F.expect(weak.get_ref() != null, "跨场景没有ActorView仍强持有纹理", failures)
	var invalid := Profile.BINDINGS.duplicate(true)
	invalid.p_swordsman.form_id = "../rinne/frames"
	F.expect(not (await bundle.prepare(invalid)).ok, "错误资源路径不能越过高清白名单", failures)
	invalid = Profile.BINDINGS.duplicate(true)
	invalid.p_swordsman.identity_id = "homura"
	F.expect(not (await bundle.prepare(invalid)).ok, "错误身份形态映射拒绝", failures)
	bundle.clear()
	await _tree().process_frame
	F.expect(bundle.get_definition("rinne").is_empty() and weak.get_ref() == null, "最终clear释放强引用和纹理", failures)
	var interrupted = Bundle.new()
	var interrupt_load := func(_completed, _total): interrupted.clear()
	interrupted.progress.connect(interrupt_load)
	var cancelled: Dictionary = await interrupted.prepare(Profile.BINDINGS)
	interrupted.progress.disconnect(interrupt_load)
	F.expect(not cancelled.ok and cancelled.get("cancelled", false), "clear中断加载且旧回调不公布成功", failures)
	F.expect(interrupted.get_definition("rinne").is_empty(), "中断不暴露半个队伍", failures)

static func _test_actor(failures: Array[String]) -> void:
	var View = load("res://scripts/rpg/ui/hd_actor_view.gd")
	var view = View.new()
	_tree().root.add_child(view)
	var definition := _definition()
	F.expect(view.configure(definition, 120.0, 1), "高清Actor可装配", failures)
	F.expect(view.animator.scale == Vector2(20, 20), "缩放来自content_height而不是全画布", failures)
	F.expect(view.animator.position == Vector2(-60, -140), "脚锚位于根节点原点", failures)
	view.set_facing(-1)
	F.expect(view.animator.sprite.flip_h and view.animator.position.x == -100, "不对称脚锚镜像仍保持根脚点", failures)
	view.play_action(&"attack")
	view.set_downed(true)
	await _tree().create_timer(0.25).timeout
	F.expect(view.is_downed() and view.animator.sprite.animation == &"down", "旧攻击完成不会覆盖倒地保持", failures)
	F.expect(view.play_action(&"recover"), "恢复动作解除倒地", failures)
	await _tree().create_timer(0.25).timeout
	F.expect(not view.is_downed() and not view.is_action_busy(), "恢复动作收招为待机", failures)
	var warnings: Array = []
	view.visual_warning.connect(func(message): warnings.append(message))
	definition.frames.remove_animation(&"hit")
	view.play_action(&"hit")
	await _tree().process_frame
	F.expect(not view.is_action_busy() and not warnings.is_empty(), "可选动作缺帧明确neutral完成", failures)
	view.play_action(&"attack")
	view.animator.sprite.pause()
	await _tree().create_timer(0.25).timeout
	F.expect(not view.is_action_busy(), "结束信号丢失由原animator watchdog解锁", failures)
	view.show_feedback("-12", Color.RED)
	F.expect(view.feedback_label.text == "-12" and view.feedback_label.visible, "HP反馈直接展示事件数值", failures)
	view.cancel_action()
	F.expect(not view.feedback_label.visible and not view.is_action_busy(), "取消动作同时清理反馈", failures)
	F.expect(not view.configure({}, 120, 1) and not view.configure(definition, -1, 1), "错误装配不能冒充成功", failures)
	var nonfinite := _definition()
	nonfinite.manifest.canvas.content_height_px = NAN
	F.expect(not view.configure(nonfinite, 120, 1), "非有限源高度不可生成损坏变换", failures)
	view.free()

static func _test_events(failures: Array[String]) -> void:
	var View = load("res://scripts/rpg/ui/hd_actor_view.gd")
	var Player = load("res://scripts/rpg/ui/hd_event_player.gd")
	var source = View.new()
	var target = View.new()
	var player = Player.new()
	for node in [source, target, player]: _tree().root.add_child(node)
	source.configure(_definition(), 120, 1)
	target.configure(_definition(), 120, -1)
	player.bind_actors({"p_swordsman": source, "e_1": target})
	var actions: Array = []
	source.animator.sprite.animation_changed.connect(func(): actions.append("source:" + str(source.animator.sprite.animation)))
	target.animator.sprite.animation_changed.connect(func(): actions.append("target:" + str(target.animator.sprite.animation)))
	var drains: Array = []
	player.drained.connect(func(): drains.append(true))
	var snapshot := {"actors": {"p_swordsman": {"hp": 90}, "e_1": {"hp": 0}}, "inventory": {"healing_potion": 2}}
	var events: Array = [_command("swing", "attack_physical"), _event("damage", {"damage": 7}), _event("damage", {"damage": 9}), _event("actor_defeated", {})]
	var before := snapshot.duplicate(true)
	var event_copy := events.duplicate(true)
	player.enqueue(events, snapshot)
	F.expect(player.is_busy(), "接受事件批次立即锁输入", failures)
	await _wait(player, failures)
	F.expect(actions.count("source:attack") == 1 and actions.count("target:hit") == 2, "多段伤害只播放一次来源出招但每段受击", failures)
	F.expect(target.is_downed() and drains.size() == 1, "down保持不等待永不发出的结束信号，队列可drain", failures)
	F.expect(snapshot == before and events == event_copy, "表现前后模型快照和事件完全不变", failures)
	F.expect(target.feedback_label.text == "-9", "最后一段HP反馈来自已结算事件", failures)
	actions.clear()
	player.enqueue([_command("swing", "attack_physical"), _command("support", "skill")], snapshot)
	await _wait(player, failures)
	F.expect(actions.count("source:attack") == 1, "重复command_id不重播，无伤害技能仍出招", failures)
	actions.clear()
	player.enqueue([_command("guard", "defend")], snapshot)
	await _wait(player, failures)
	F.expect(actions.has("source:defend"), "防御命令映射防御而不是攻击", failures)
	actions.clear()
	snapshot.actors.e_1.hp = 25
	player.enqueue([_event("revived", {"hp": 25})], snapshot)
	await _wait(player, failures)
	F.expect(actions.has("target:recover") and not target.is_downed(), "复苏事件播放恢复且批次末与HP同步", failures)
	actions.clear()
	player.enqueue([_event("periodic_damage", {"damage": 4, "status": {"id": "burn"}})], snapshot)
	await _wait(player, failures)
	F.expect(not actions.has("source:attack") and actions.has("target:hit"), "DOT不伪造来源出招", failures)
	player.enqueue([_event("damage", {"damage": 8, "absorption": {"hp_loss": 3, "absorbed": 5}})], snapshot)
	await _wait(player, failures)
	F.expect(target.feedback_label.text == "HP -3 · 盾 -5", "护盾吸收与实际HP损失按模型分开展示", failures)
	var warnings: Array = []
	player.visual_warning.connect(func(message): warnings.append(message))
	player.enqueue([_command("lost_completion", "attack_physical")], snapshot)
	await _tree().process_frame
	await _tree().process_frame
	source.animator.set_process(false)
	source.animator.sprite.pause()
	await _wait(player, failures)
	F.expect(not warnings.is_empty() and not source.is_action_busy(), "动画整体停止仍由队列超时保护继续", failures)
	source.animator.set_process(true)
	var finished_before: int = drains.size()
	player.enqueue([_command("batch_one", "attack_physical")], before)
	player.enqueue([_event("revived", {"hp": 25})], snapshot)
	await _wait(player, failures)
	F.expect(drains.size() == finished_before + 1 and not target.is_downed(), "排队两批顺序同步快照且全部结束才drain", failures)
	player.enqueue([_command("cancelled", "attack_physical"), _event("actor_defeated", {})], before)
	await _tree().process_frame
	player.cancel()
	var drain_count: int = drains.size()
	await _tree().create_timer(0.3).timeout
	F.expect(not player.is_busy() and not target.is_downed() and drains.size() == drain_count, "cancel代次屏障阻止旧批次与快照回写", failures)
	# 真引擎只算一次；播放其已提交事件不调用第二次submit/advance。
	var engine = load("res://scripts/rpg/battle_engine.gd").new()
	var real_actor := F.actor("swordsman", "p_swordsman")
	real_actor.stats.spd = 100
	engine.start({"actors": {"p_swordsman": real_actor, "e_1": F.enemy("hound", "e_1")}, "inventory": {"healing_potion": 2}}, 911)
	engine.advance(false)
	var state: Dictionary = engine.snapshot()
	var command := {"command_id": "real", "expected_revision": state.revision, "actor_id": state.active_actor_id, "kind": "attack_physical", "ability_id": "", "target_ids": ["e_1"]}
	var result: Dictionary = engine.submit(command)
	F.expect(result.accepted, "真实模型接受测试命令：" + str(result.get("reasons", [])), failures)
	var committed: Dictionary = engine.snapshot()
	player.enqueue(result.events, committed)
	await _wait(player, failures)
	F.expect(engine.snapshot() == committed, "真实表现不二次计算HP、MP、库存或RNG", failures)
	player.enqueue([_command("detached", "attack_physical")], snapshot)
	await _tree().process_frame
	await _tree().process_frame
	source.free()
	await _wait(player, failures)
	F.expect(not player.is_busy(), "角色退出树不阻塞动作队列", failures)
	player.free()
	target.free()

# 取消必须在free之前同步退出等待栈，单纯generation屏障不能回收挂在全局帧信号上的协程。
static func _test_cancel_unwinds(failures: Array[String]) -> void:
	var view = load("res://scripts/rpg/ui/hd_actor_view.gd").new()
	var player = load("res://scripts/rpg/ui/hd_event_player.gd").new()
	_tree().root.add_child(view)
	_tree().root.add_child(player)
	view.configure(_definition(), 120, 1)
	player.bind_actors({"p_swordsman": view})
	var completed: Array = []
	var drained: Array = []
	player.drained.connect(func(): drained.append(true))
	_observe_event_return(player, completed)
	F.expect(view.is_action_busy() and completed.is_empty(), "生命周期夹具已进入真实动作等待", failures)
	player.cancel()
	F.expect(completed == [true], "cancel同步退出动作协程而非等下一次全局帧", failures)
	F.expect(drained.is_empty(), "取消等待栈不伪报drained", failures)
	await _tree().process_frame
	completed.clear()
	_observe_event_return(player, completed)
	_tree().root.remove_child(player)
	F.expect(completed == [true], "离开树在free前同步退出嵌套等待", failures)
	F.expect(drained.is_empty(), "退出树不伪报drained", failures)
	# RED阶段给旧实现一次收尾机会，避免失败断言本身污染后续资源检查。
	await _tree().process_frame
	player.free()
	view.free()

static func _observe_event_return(player: Node, completed: Array) -> void:
	await player._play_event(_command("lifecycle", "attack_physical"), player._generation)
	completed.append(true)

static func _test_names(failures: Array[String]) -> void:
	var catalog = load("res://scripts/rpg/catalog.gd").new()
	catalog.load_all()
	for pair in [["swordsman", "rinne", "凛音"], ["ranger", "mint", "薄荷"], ["guard", "guard", "岑照"]]:
		var actor := F.actor(pair[0], "p_" + pair[0])
		var old_name: String = Presenter.actor_name(actor, catalog)
		F.expect(old_name == catalog.get_definition("classes", pair[0]).name, "旧职业视图姓名兼容", failures)
		actor.identity_id = pair[1]
		actor.form_id = pair[1]
		F.expect(Presenter.actor_name(actor, catalog) == pair[2], "身份清单姓名优先：" + pair[2], failures)

static func _definition() -> Dictionary:
	var texture := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for action in ["idle", "walk", "attack", "hit", "defend", "down", "recover"]:
		frames.add_animation(action)
		frames.set_animation_speed(action, 1.0)
		frames.set_animation_loop(action, action in ["idle", "walk"])
		frames.add_frame(action, texture, 0.02)
	return {"ok": true, "frames": frames, "layer_frames": [], "manifest": {"canvas": {"w": 8, "h": 8, "anchor": [3, 7], "content_height_px": 6}, "move_speed_mps": 2.6, "mirror_allowed": true}}

static func _command(id: String, kind: String) -> Dictionary:
	return {"type": "command_accepted", "actor_id": "p_swordsman", "target_id": "", "payload": {"command": {"command_id": id, "kind": kind, "ability_id": ""}}}

static func _event(kind: String, payload: Dictionary) -> Dictionary:
	return {"type": kind, "actor_id": "p_swordsman", "target_id": "e_1", "payload": payload}

static func _wait(player: Node, failures: Array[String]) -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while player.is_busy() and Time.get_ticks_msec() < deadline: await _tree().process_frame
	F.expect(not player.is_busy(), "事件队列在有界时间内结束", failures)

static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

static func _atlas_page(texture: Texture2D) -> Texture2D:
	while texture is AtlasTexture: texture = texture.atlas
	return texture
