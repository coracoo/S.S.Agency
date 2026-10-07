# 正式schema3装配的真实轮序门禁。统一runner连续启动本脚本两次，第二进程验证续档。
# 只从公开整备/战斗接口改变构筑、资源和进度，不改引擎内部状态或注入战果。
extends SceneTree

const Session = preload("res://scripts/campaign/chapter_session.gd")
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const BattleEngine = preload("res://scripts/rpg/battle_engine.gd")
const Enemy = preload("res://scripts/rpg/enemy_policy.gd")
const Loadouts = preload("res://scripts/rpg/loadout_rules.gd")
const Replay = preload("res://scripts/rpg/replay.gd")
const Strategy = preload("res://tools/campaign/saga_battle_strategy.gd")
const RESUME_EXPECTED := "user://loadout_initiative_expected.json"
const NORMAL_QUEUE := ["p_controller", "e_01_hound", "p_swordsman", "p_guard", "e_02_shield_soldier"]
const SLOWED_QUEUE := ["p_controller", "p_swordsman", "e_01_hound", "p_guard", "e_02_shield_soldier"]

var checks := 0
var failures: Array[String] = []
var catalog: RefCounted

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: ", message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var root_path := OS.get_environment("RPG_TEST_ROOT").replace("\\", "/").simplify_path().trim_suffix("/")
	var user_path := OS.get_user_data_dir().replace("\\", "/").simplify_path()
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or root_path.is_empty() or not user_path.begins_with(root_path + "/"):
		printerr("FAIL: 未核验实际隔离user目录，禁止轮序写档测试")
		quit(2)
		return
	catalog = Catalog.new()
	check(catalog.load_all().is_empty(), "正式目录完整校验")
	if FileAccess.file_exists(RESUME_EXPECTED):
		print("LOADOUT_INITIATIVE_PHASE: restarted_process")
		_test_restarted_process()
	else:
		print("LOADOUT_INITIATIVE_PHASE: fresh_process")
		_test_equal_speeds()
		var baseline := _speed_case("baseline")
		var passive := _speed_case("passive")
		var equipped := _speed_case("equipment")
		if not baseline.is_empty() and not passive.is_empty() and not equipped.is_empty():
			check(baseline.speed == 39 and baseline.queue[0] == "e_01_hound", "法铃配静息SPD39，首轮先于角色的是SPD40影犬")
			check(passive.speed == 43 and passive.queue[0] == "p_controller" and passive.queue != baseline.queue, "换轻步后SPD43，真实首轮排序发生改变")
			check(equipped.speed == 40 and equipped.queue == NORMAL_QUEUE and equipped.queue != baseline.queue, "保留静息换符具后SPD40，同速玩家先于影犬")
			check(passive.gear == baseline.gear and equipped.gear == baseline.gear, "速度对照只互换已持有装备，不发放新装备")
			_test_slow_and_persistence(equipped.session, equipped.engine)
	_finish()

func _finish() -> void:
	print("LOADOUT_INITIATIVE: %d assertions, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _new_session(party: Array[String]) -> RefCounted:
	var session := Session.new()
	var created: Dictionary = session.start_new(true, party)
	check(created.ok, "公开入口建立隔离正式队伍")
	if not created.ok:
		session.close()
		return null
	var safe: Dictionary = session.campaign.safe_snapshot()
	check(safe.schema_version == 3 and not safe.has("level") and not safe.has("xp"), "轮序夹具使用无等级schema3正式档")
	return session

func _begin_first_battle(session: RefCounted) -> Dictionary:
	for event in ["dialogue:a1", "dialogue:r1", "dialogue:h1"]:
		check(session.commit_event(session.campaign.safe_snapshot().world, event).ok, "正常提交首战前置：" + event)
	var started: Dictionary = session.begin_encounter(session.campaign.safe_snapshot().world, Chapters.night(1).clue_id)
	check(started.ok, "正式路由创建首夜战前检查点")
	return started

func _test_equal_speeds() -> void:
	var session := _new_session(["mage", "healer", "guard"])
	if session == null: return
	var build: Dictionary = session.campaign.safe_snapshot().roster.p_healer.build.duplicate(true)
	build.passive = ["light_step"]
	check(session.campaign.set_loadout("p_healer", build).ok, "轻步通过正式整备装到治疗者")
	var started := _begin_first_battle(session)
	if not started.ok:
		session.close()
		return
	check(started.setup.actors.p_healer.stats.spd == 28 and started.setup.actors.p_mage.stats.spd == 28, "两位不同身份以真实构筑达到同速28")
	var expected := ["e_01_hound", "p_healer", "p_mage", "p_guard", "e_02_shield_soldier"]
	for seed_value in [7, 91, 20261008]:
		for reverse in [false, true]:
			var setup: Dictionary = started.setup.duplicate(true)
			if reverse:
				var ids: Array = setup.actors.keys()
				ids.reverse()
				var reordered := {}
				for actor_id in ids: reordered[actor_id] = setup.actors[actor_id]
				setup.actors = reordered
			var engine := BattleEngine.new(catalog)
			engine.set_policy(Enemy.new())
			check(engine.start(setup, seed_value).started, "真实引擎接受合法正式构筑，seed=%d reverse=%s" % [seed_value, str(reverse)])
			engine.advance(false)
			check(engine.snapshot().queue == expected, "同速按ID确定排序，不随种子或字典插入顺序改变")
	session.close()

func _speed_case(kind: String) -> Dictionary:
	var session := _new_session(["controller", "swordsman", "guard"])
	if session == null: return {}
	# 后备治疗者先合法卸空主动卡与法铃，才将法铃交给控制者；六人穿戴数量仍由正式模型验证。
	var healer_build: Dictionary = session.campaign.safe_snapshot().roster.p_healer.build.duplicate(true)
	healer_build.active.default = []
	check(session.campaign.set_loadout("p_healer", healer_build).ok, "后备治疗者合法卸下主动卡")
	check(session.campaign.equip("p_healer", "weapon", "").ok, "后备治疗者归还已有法铃")
	var build: Dictionary = session.campaign.safe_snapshot().roster.p_controller.build.duplicate(true)
	build.passive = ["light_step" if kind == "passive" else "steady_breath"]
	check(session.campaign.set_loadout("p_controller", build).ok, "通过正式整备保存速度被动：" + kind)
	check(session.campaign.equip("p_controller", "weapon", "training_sigil" if kind == "equipment" else "training_bell").ok, "通过正式整备更换已拥有的速度武器：" + kind)
	var safe: Dictionary = session.campaign.safe_snapshot()
	check(Loadouts.validate_actor(safe.roster.p_controller, catalog, safe.cards).is_empty(), "SPD由有效装备与被动共同派生")
	var started := _begin_first_battle(session)
	if not started.ok:
		session.close()
		return {}
	var engine: RefCounted = session.router.create_engine()
	check(engine != null, "正式路由创建真实轮序引擎：" + kind)
	if engine == null:
		session.close()
		return {}
	engine.advance(false)
	var result := {"speed": safe.roster.p_controller.stats.spd, "queue": engine.snapshot().queue, "gear": safe.gear, "session": session, "engine": engine}
	print("LOADOUT_INITIATIVE_ORDER: ", kind, " SPD=", result.speed, " queue=", result.queue)
	if kind != "equipment": session.close()
	return result

func _command(state: Dictionary, kind: String, ability: String = "", targets: Array = []) -> Dictionary:
	return {"command_id": "initiative_%d_%s" % [state.revision, state.active_actor_id], "expected_revision": state.revision, "actor_id": state.active_actor_id, "kind": kind, "ability_id": ability, "target_ids": targets.duplicate()}

func _submit(engine: RefCounted, command: Dictionary) -> bool:
	var preview: Dictionary = engine.preview(command)
	check(preview.legal, "真实指令预览合法：" + str(command.get("kind", "")) + " / " + str(preview.reasons))
	if not preview.legal: return false
	var submitted: Dictionary = engine.submit(command)
	check(submitted.accepted, "真实引擎接受指令并消费行动")
	return submitted.accepted

func _test_slow_and_persistence(session: RefCounted, engine: RefCounted) -> void:
	var prepared: Dictionary = session.campaign.safe_snapshot()
	var before: Dictionary = engine.snapshot()
	check(before.round == 1 and before.active_actor_id == "p_controller", "真实同速优先使控制者能首个施放迟滞术")
	var slow := _command(before, "skill", "slow")
	if not _submit(engine, slow):
		session.close()
		return
	var after_slow: Dictionary = engine.snapshot()
	check(after_slow.queue == before.queue and after_slow.queue_index == 1, "施放减速只消费当前行动，不重排已建立的本轮队列")
	for enemy_id in ["e_01_hound", "e_02_shield_soldier"]:
		var statuses: Array = after_slow.actors[enemy_id].statuses.filter(func(status): return status.id == "slow")
		check(statuses.size() == 1 and statuses[0].remaining == 2 and statuses[0].clock == "round_snapshot", "真实迟滞术给予两次后续轮首快照：" + enemy_id)
		check(after_slow.actors[enemy_id].stats == before.actors[enemy_id].stats, "减速不篡改固定敌方基础属性：" + enemy_id)
	check(not engine.submit(slow).accepted and engine.snapshot() == after_slow, "重复提交减速不增加行动或重复扣资源")
	var steps := 0
	while engine.snapshot().outcome.is_empty() and steps < 30:
		engine.advance(false)
		var state: Dictionary = engine.snapshot()
		if state.round >= 4: break
		if state.phase != "action_selection":
			check(false, "等待减速过期时引擎必须抵达真实可行动阶段")
			break
		var command: Dictionary = _command(state, "defend") if state.actors[state.active_actor_id].side == "player" else Enemy.new().choose_command(state, catalog)
		if not _submit(engine, command): break
		steps += 1
	var fourth: Dictionary = engine.snapshot()
	check(fourth.round == 4 and fourth.outcome.is_empty() and fourth.actors.values().all(func(actor): return actor.hp > 0), "所有角色通过真实指令存活到第四轮，未通过死亡缩减行动队列")
	for round_id in range(1, 5):
		var queues: Array = fourth.event_log.filter(func(event): return event.type == "round_queue" and event.payload.round == round_id)
		check(queues.size() == 1, "每轮只构造一次队列：%d" % round_id)
		if queues.size() != 1: continue
		var payload: Dictionary = queues[0].payload
		var slowed: bool = round_id in [2, 3]
		check(payload.queue == (SLOWED_QUEUE if slowed else NORMAL_QUEUE), "减速仅影响第二、三轮，第四轮恢复自然顺序：%d" % round_id)
		check(is_equal_approx(float(payload.effective_speeds.e_01_hound), 28.0 if slowed else 40.0), "影犬有效速度按30%%减速快照结算：%d" % round_id)
		check(is_equal_approx(float(payload.effective_speeds.e_02_shield_soldier), 12.6 if slowed else 18.0), "盾兵有效速度保留真实小数：%d" % round_id)
		if round_id < 4:
			for actor_id in fourth.actors:
				for type in ["slot_started", "slot_ended"]:
					var slots: Array = fourth.event_log.filter(func(event): return event.type == type and event.actor_id == actor_id and event.payload.round == round_id)
					check(slots.size() == 1, "减速前后不重复或遗漏行动：%d/%s/%s" % [round_id, actor_id, type])
	for enemy_id in ["e_01_hound", "e_02_shield_soldier"]:
		check(not fourth.actors[enemy_id].statuses.any(func(status): return status.id == "slow"), "最后一次受减速轮结束后移除状态：" + enemy_id)
		var removals: Array = fourth.event_log.filter(func(event): return event.type == "status_removed" and event.target_id == enemy_id and event.payload.status.id == "slow")
		check(removals.size() == 1 and removals[0].payload.reason == "last_snapshot_round_end", "减速仅在最后一次快照所属轮末失效：" + enemy_id)
	_test_replay(session.router.capture_replay(engine), prepared)
	var finished_commands := 0
	while engine.snapshot().outcome.is_empty() and finished_commands < 180:
		engine.advance(false)
		var state: Dictionary = engine.snapshot()
		if not state.outcome.is_empty(): break
		var command: Dictionary = Strategy.choose(state, engine, catalog) if state.actors[state.active_actor_id].side == "player" else Enemy.new().choose_command(state, catalog)
		if command.is_empty():
			check(false, "公开策略必须给出真实合法战斗指令")
			break
		if not _submit(engine, command): break
		finished_commands += 1
	check(engine.snapshot().outcome == "victory", "轮序回归队伍以真实合法指令取得胜利")
	if engine.snapshot().outcome != "victory":
		session.close()
		return
	_test_replay(session.router.capture_replay(engine), prepared)
	var result: Dictionary = session.router.result_from_engine()
	check(session.router.finish(result).ok, "真实战后构筑和资源提交正式安全档")
	var saved: Dictionary = session.campaign.safe_snapshot()
	for actor_id in saved.roster:
		for field in ["stats", "build", "equipment"]:
			check(saved.roster[actor_id][field] == prepared.roster[actor_id][field], "战后保留装配派生速度及配置：" + actor_id + "/" + field)
	check(saved.roster.p_controller.stats.spd == 40 and saved.pending_battle.is_empty() and saved.applied_battle_ids.size() == 1, "真实首战结算后保留SPD40与唯一战果")
	var file := FileAccess.open(RESUME_EXPECTED, FileAccess.WRITE)
	check(file != null, "仅在隔离user目录写跨进程期待快照")
	if file != null:
		file.store_string(JSON.stringify(saved, "", true, true))
		file.close()
	check(FileAccess.file_exists(RESUME_EXPECTED), "后续独立进程具有实际落盘检查点")
	session.close()

func _test_replay(recording: Dictionary, prepared: Dictionary) -> void:
	check(not recording.is_empty(), "正式router捕获真实初始状态、指令与事件")
	if recording.is_empty(): return
	var actor: Dictionary = recording.initial.actors.p_controller
	check(actor.build == prepared.roster.p_controller.build and actor.equipment == prepared.roster.p_controller.equipment and actor.stats.spd == 40, "重放初始快照携带实际装配、装备和速度")
	var verified: Dictionary = Replay.verify(recording, catalog, Enemy.new())
	check(verified.matches and verified.fingerprint_verified, "真实轮序和减速逐命令重演一致且验证规则指纹：" + str(verified.first_difference))
	var transported: Dictionary = JSON.parse_string(JSON.stringify(recording, "", true, true))
	check(Replay.verify(transported, catalog, Enemy.new()).matches, "重放经过真实JSON运输仍保持轮序与事件一致")
	var changed := recording.duplicate(true)
	changed.initial.actors.p_controller.build.passive = ["light_step"]
	check(not Replay.verify(changed, catalog, Enemy.new()).matches, "篡改重放构筑但不匹配速度时必须拒绝")
	changed = recording.duplicate(true)
	changed.mechanics_fingerprint = "0".repeat(64)
	check(not Replay.verify(changed, catalog, Enemy.new()).matches, "规则指纹不符的重放必须拒绝")

func _test_restarted_process() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RESUME_EXPECTED))
	var session := Session.new()
	var resumed: Dictionary = session.resume()
	check(resumed.ok, "新Godot进程从正式slot恢复已提交首战")
	if not resumed.ok:
		session.close()
		return
	var safe: Dictionary = session.campaign.safe_snapshot()
	check(Replay.canonical(safe) == Replay.canonical(expected), "跨进程恢复完整正式快照，构筑/装备/资源没有变更")
	check(safe.schema_version == 3 and not safe.has("level") and not safe.has("xp"), "续档仍使用无等级正式模型")
	check(safe.roster.p_controller.stats.spd == 40 and safe.roster.p_controller.build.passive == ["steady_breath"] and safe.roster.p_controller.equipment.weapon == "training_sigil", "跨进程保留由静息与符具计算的SPD40")
	check(Loadouts.validate_actor(safe.roster.p_controller, catalog, safe.cards).is_empty(), "续档速度仍能由持有卡片和装备独立派生")
	check(session.advance_night(safe.world).ok, "新进程按已提交首战正常进入第二夜")
	check(session.commit_event(session.campaign.safe_snapshot().world, "dialogue:c1").ok, "新进程正常调查第二夜战斗前置")
	check(session.campaign.rest().ok, "新进程通过正式休息准备下一场")
	var started: Dictionary = session.begin_encounter(session.campaign.safe_snapshot().world, Chapters.night(2).clue_id)
	check(started.ok, "续档后的下一场仍由正式路由准备")
	var engine: RefCounted = session.router.create_engine()
	check(engine != null, "续档下一场真实引擎可建立")
	if engine != null:
		engine.advance(false)
		var state: Dictionary = engine.snapshot()
		check(state.actors.p_controller.stats.spd == 40 and state.actors.p_controller.build == safe.roster.p_controller.build and state.actors.p_controller.equipment == safe.roster.p_controller.equipment, "续档下一场实际演员继承同一速度构筑")
		check(state.queue == ["p_controller", "e_01_hound", "p_swordsman", "e_02_cultist", "p_guard"], "新进程下一场首轮继续按SPD40及同速规则排序")
	session.close()
