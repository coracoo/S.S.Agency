# 公开意图与六步循环：优先通过真实引擎自动敌方推进验证。
extends RefCounted

const F = preload("res://tools/rpg/fixtures.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const State = preload("res://scripts/rpg/battle_state.gd")
const Status = preload("res://scripts/rpg/status_rules.gd")
const Battle = preload("res://scripts/rpg/battle_engine.gd")
const Replay = preload("res://scripts/rpg/replay.gd")

static func run() -> Array[String]:
	F.assertion_count = 0
	var failures: Array[String] = []
	for script in ["enemy_policy", "boss_policy"]:
		F.expect(FileAccess.file_exists("res://scripts/rpg/%s.gd" % script), "未实现策略：" + script, failures)
	if not failures.is_empty(): return failures
	var Policy = load("res://scripts/rpg/enemy_policy.gd")
	_test_ordinary(Policy, failures)
	_test_cycle(Policy, failures)
	_test_fallback_and_skips(Policy, failures)
	_test_interrupt(Policy, failures)
	_test_reaction_window(Policy, failures)
	_test_phase(Policy, failures)
	_test_replay(Policy, failures)
	_test_group_target_refresh(Policy, failures)
	_test_policy_snapshot_validation(Policy, failures)
	_test_revival_window(Policy, failures)
	_test_charge_previews_and_modifiers(Policy, failures)
	_test_committed_command_rejection(Policy, failures)
	_test_wait_restore_and_immunity(Policy, failures)
	_test_policy_invalid_types(Policy, failures)
	_test_standalone_intent_refresh(Policy, failures)
	_test_policy_snapshot_consistency(Policy, failures)
	print("RPG ai 断言：", F.assertion_count)
	return failures

static func _catalog():
	var catalog := Catalog.new()
	catalog.load_all()
	return catalog

static func _players() -> Array:
	var result: Array = []
	for row in [["guard", "p_a", 40], ["swordsman", "p_b", 20], ["healer", "p_c", 10]]:
		var actor := F.actor(row[0], row[1])
		actor.stats.hp = 10000
		actor.hp = 10000
		actor.stats.spd = row[2]
		result.append(actor)
	return result

static func _engine(Policy, enemy: Dictionary, players: Array = []):
	var engine := Battle.new()
	engine.set_policy(Policy.new())
	var actors: Dictionary = {enemy.actor_id: enemy}
	for actor in (_players() if players.is_empty() else players): actors[actor.actor_id] = actor
	engine.start({"actors": actors, "inventory": {"healing_potion": 3, "mana_potion": 1, "revival_potion": 3, "cleansing_powder": 1}}, 1701)
	return engine

static func _command(engine, kind: String, ability: String = "", targets: Array = []) -> Dictionary:
	var state: Dictionary = engine.snapshot()
	return {"command_id": "test_%d" % state.revision, "expected_revision": state.revision, "actor_id": state.active_actor_id, "kind": kind, "ability_id": ability, "target_ids": targets}

static func _past_boss(engine, slot: int, failures: Array[String]) -> void:
	for index in range(60):
		engine.advance()
		var state: Dictionary = engine.snapshot()
		if state.actors.e_boss.slot_count >= slot and state.active_actor_id != "e_boss": return
		if not state.outcome.is_empty(): break
		if state.active_actor_id.is_empty() or state.actors[state.active_actor_id].side != "player":
			F.expect(false, "自动敌方必须推进到玩家；错误=" + str(engine.last_errors), failures)
			return
		var result: Dictionary = engine.submit(_command(engine, "defend"))
		F.expect(result.accepted, "推进玩家防御合法：" + str(result.reasons), failures)
	F.expect(false, "Boss槽应有限推进到" + str(slot), failures)

static func _boss_commands(engine) -> Array:
	var result: Array = []
	for command in engine.snapshot().command_log:
		if command.actor_id == "e_boss": result.append(command)
	return result

static func _events(engine, type: String, actor_id: String = "") -> Array:
	var result: Array = []
	for item in engine.snapshot().event_log:
		if item.type == type and (actor_id.is_empty() or item.actor_id == actor_id): result.append(item)
	return result

static func _test_ordinary(Policy, failures: Array[String]) -> void:
	var catalog = _catalog()
	var policy = Policy.new()
	var players := _players()
	players[0].hp = 9000
	players[1].hp = 8000
	players[2].hp = 8000
	players[1].stats.atk = 99
	for row in [["hound", "bite", "p_b"], ["fire_spirit", "fire_orb", "p_b"], ["shield_soldier", "attack_physical", "p_a"], ["cultist", "weak_curse", "p_b"], ["elite_shield_soldier", "shield_rush", "p_b"]]:
		var engine = _engine(Policy, F.enemy(row[0], "e_one"), players)
		var state: Dictionary = engine.snapshot()
		var intent: Dictionary = state.actors.e_one.intent
		F.expect(intent.get("ability_id") == row[1] and intent.get("target_ids") == [row[2]], "战前公布" + row[0] + "技能与确定目标", failures)
		F.expect(intent.size() == 8 and intent.has("preview") and intent.has("added_statuses"), "公开意图固定八字段", failures)
		if intent.is_empty(): continue
		state.actors.p_c.hp = 1
		var refreshed: Dictionary = policy.refresh_target(state, intent)
		F.expect(refreshed.target_ids == intent.target_ids and refreshed.ability_id == intent.ability_id, "活目标不随HP变化偷换", failures)
		state.actors[row[2]].hp = 0
		refreshed = policy.refresh_target(state, intent)
		F.expect(refreshed.target_ids != intent.target_ids and refreshed.ability_id == intent.ability_id, "倒地按原选择规则重选并保留招式", failures)
	var fire := F.enemy("fire_spirit", "e_one")
	fire.mp = 0
	var engine = _engine(Policy, fire, players)
	F.expect(engine.snapshot().actors.e_one.intent.ability_id == "attack_magic", "MP不足预先公布免费中性魔攻", failures)
	var shield := F.enemy("shield_soldier", "e_one")
	shield.hp = 120
	engine = _engine(Policy, shield, players)
	F.expect(engine.snapshot().actors.e_one.intent.ability_id == "shield_stance", "盾兵半血可用时优先盾姿", failures)
	engine = _engine(Policy, F.enemy("hound", "e_one"), players)
	engine.advance()
	F.expect(engine.snapshot().active_actor_id == "p_a", "同速玩家先行动", failures)
	var accepted: Dictionary = engine.submit(_command(engine, "skill", "taunt", ["e_one"]))
	F.expect(accepted.accepted and engine.snapshot().actors.e_one.intent.target_ids == ["p_a"], "挑衅立即刷新公开普通目标", failures)
	engine.advance()
	F.expect(engine.snapshot().actors.e_one.intent.ability_id == "attack_physical", "CD1在敌方槽末已预告下一槽普攻", failures)
	F.expect(not engine.snapshot().actors.e_one.intent.preview.is_empty(), "非活动槽也给模型共享伤害预览", failures)

static func _test_cycle(Policy, failures: Array[String]) -> void:
	var engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"))
	for slot in range(1, 8):
		_past_boss(engine, slot, failures)
		F.expect(State.validate(engine.snapshot()).is_empty(), "Boss每槽发布快照严格有效", failures)
	var ids: Array = []
	for command in _boss_commands(engine): ids.append(command.ability_id)
	F.expect(ids.slice(0, 7) == ["boss_suppress", "boss_pierce_charge", "boss_pierce_release", "boss_quake", "boss_pulse_charge", "boss_pulse_release", "boss_suppress"], "真实自动运行完整六步后循环", failures)
	F.expect(engine.snapshot().actors.e_boss.mp == 42, "两次蓄力只扣6加12MP，释放不扣费", failures)
	F.expect(_events(engine, "charge_started", "e_boss").size() == 2, "群体准备也仅记录一次成功蓄力", failures)
	for event in _events(engine, "damage", "e_boss"):
		F.expect(event.payload.critical_roll == null and not event.payload.can_crit, "Boss所有步骤不抽暴击", failures)

static func _test_fallback_and_skips(Policy, failures: Array[String]) -> void:
	var boss := F.enemy("gatekeeper", "e_boss")
	boss.mp = 0
	var engine = _engine(Policy, boss)
	_past_boss(engine, 6, failures)
	var commands := _boss_commands(engine)
	for index in [1, 2, 4, 5]:
		F.expect(commands.size() > index and commands[index].kind == "attack_physical", "MP不足准备和释放分别普通攻击", failures)
	F.expect(engine.snapshot().actors.e_boss.mp == 0 and _events(engine, "charge_started").is_empty(), "不足MP不免费蓄力或补MP", failures)
	engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"))
	_past_boss(engine, 1, failures)
	var saved: Dictionary = engine.snapshot()
	Status.apply(saved.actors.e_boss, F.status("stun", 1.0, 1, "p_a"))
	engine.restore(saved)
	_past_boss(engine, 3, failures)
	F.expect(engine.snapshot().actors.e_boss.boss.step == 4 and engine.snapshot().actors.e_boss.mp == 60, "跳过准备后释放空行动仍推进、不收费", failures)
	F.expect(_events(engine, "boss_idle").size() == 1, "跳过准备只有对应释放空行动", failures)

static func _test_interrupt(Policy, failures: Array[String]) -> void:
	var engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"))
	_past_boss(engine, 2, failures)
	var saved: Dictionary = engine.snapshot()
	var locked: Array = saved.actors.e_boss.boss.locked_targets.duplicate()
	Status.apply(saved.actors.e_boss, F.status("taunt", 1.0, 2, "p_c"))
	engine.restore(saved)
	# 推进到守卫，期间后续玩家仍只防御。
	for index in range(6):
		engine.advance()
		if engine.snapshot().active_actor_id == "p_a": break
		engine.submit(_command(engine, "defend"))
	F.expect(engine.snapshot().actors.e_boss.intent.target_ids == locked, "挑衅不改已锁定穿刺", failures)
	var bash: Dictionary = engine.submit(_command(engine, "skill", "shield_bash", ["e_boss"]))
	F.expect(bash.accepted, "盾击命中并打断", failures)
	F.expect(not engine.snapshot().actors.e_boss.intent.interruptible, "已取消穿刺意图必须停止显示可打断", failures)
	F.expect(not F.find_status(engine.snapshot().actors.e_boss, "stagger").is_empty(), "打断后到释放槽末有20%失衡", failures)
	F.expect(F.find_status(engine.snapshot().actors.e_boss, "stun").is_empty(), "盾击没有附赠眩晕", failures)
	_past_boss(engine, 3, failures)
	F.expect(engine.snapshot().actors.e_boss.boss.step == 4 and F.find_status(engine.snapshot().actors.e_boss, "stagger").is_empty(), "失衡释放槽结束移除且恰好推进一步", failures)
	var players := _players()
	players[0] = F.actor("controller", "p_a")
	players[0].stats.hp = 10000
	players[0].hp = 10000
	players[0].stats.spd = 40
	engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"), players)
	_past_boss(engine, 2, failures)
	for index in range(6):
		engine.advance()
		if engine.snapshot().active_actor_id == "p_a": break
		engine.submit(_command(engine, "defend"))
	var sealed: Dictionary = engine.submit(_command(engine, "skill", "seal", ["e_boss"]))
	F.expect(sealed.accepted, "封缄同时眩晕与取消蓄力", failures)
	_past_boss(engine, 3, failures)
	F.expect(engine.snapshot().actors.e_boss.boss.step == 4 and _events(engine, "boss_idle").is_empty(), "封缄跳释放槽后直接进入横震，没有双重空罚", failures)
	_past_boss(engine, 4, failures)
	F.expect(_boss_commands(engine).back().ability_id == "boss_quake", "封缄后下一Boss行动正常横震", failures)
	_past_boss(engine, 5, failures)
	saved = engine.snapshot()
	F.expect(not Status.immunity(saved.actors.e_boss, {"type": "apply_status", "status_id": "stun"}).is_empty(), "脉冲成功蓄力期间拒绝眩晕", failures)
	F.expect(not Status.immunity(saved.actors.e_boss, {"type": "interrupt"}).is_empty(), "脉冲成功蓄力期间拒绝打断", failures)
	F.expect(Status.apply(saved.actors.e_boss, F.status("weaken", 0.2, 2, "p_a")).applied, "不可打断期间软控照常", failures)
	engine.restore(saved)
	_past_boss(engine, 6, failures)
	F.expect(Status.immunity(engine.snapshot().actors.e_boss, {"type": "apply_status", "status_id": "stun"}).is_empty(), "脉冲释放结束后恢复正常眩晕规则", failures)

static func _test_reaction_window(Policy, failures: Array[String]) -> void:
	var engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"))
	_past_boss(engine, 2, failures)
	var saved: Dictionary = engine.snapshot()
	var locked: Array = saved.actors.e_boss.boss.locked_targets.duplicate()
	saved.actors.e_boss.stats.spd = 100
	engine.restore(saved)
	_past_boss(engine, 3, failures)
	F.expect(engine.snapshot().actors.e_boss.boss.step == 3 and engine.snapshot().actors.e_boss.mp == 54, "Boss变快但玩家尚无机会时继续蓄力，不推进不重扣", failures)
	F.expect(_events(engine, "charge_wait").size() == 1, "继续蓄力产生明确事件", failures)
	_past_boss(engine, 4, failures)
	F.expect(engine.snapshot().actors.e_boss.boss.step == 4, "各存活队员有机会后正常释放，非无限等待", failures)
	engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"))
	_past_boss(engine, 2, failures)
	saved = engine.snapshot()
	Status.apply(saved.actors.p_a, F.status("stun", 1.0, 1, "e_boss"))
	engine.restore(saved)
	_past_boss(engine, 3, failures)
	F.expect(engine.snapshot().actors.e_boss.boss.step == 3, "眩晕槽不算可选机会，Boss等待", failures)
	_past_boss(engine, 4, failures)
	F.expect(engine.snapshot().actors.e_boss.boss.step == 4, "眩晕后真实选择才允许释放", failures)
	engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"))
	_past_boss(engine, 2, failures)
	saved = engine.snapshot()
	locked = saved.actors.e_boss.boss.locked_targets.duplicate()
	saved.actors[locked[0]].hp = 0
	saved.actors[locked[0]].statuses = []
	saved.actors[locked[0]].shield = {}
	engine.restore(saved)
	_past_boss(engine, 3, failures)
	F.expect(engine.snapshot().actors.e_boss.boss.step == 4 and _events(engine, "charge_empty").size() == 1, "穿刺锁定者仍倒地时空放、不换目标", failures)

static func _test_phase(Policy, failures: Array[String]) -> void:
	var engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"))
	_past_boss(engine, 2, failures)
	var saved: Dictionary = engine.snapshot()
	saved.actors.e_boss.hp = 312
	engine.restore(saved)
	# 玩家命令结算时只预约，不能重排当前轮。
	var queue: Array = engine.snapshot().queue.duplicate()
	engine.submit(_command(engine, "defend"))
	F.expect(engine.snapshot().actors.e_boss.boss.phase == 1 and engine.snapshot().actors.e_boss.boss.pending_phase == 2, "40%血量只预约二阶段", failures)
	F.expect(engine.snapshot().queue == queue and engine.snapshot().actors.e_boss.stats.spd == 30, "本轮不提前加速重排", failures)
	_past_boss(engine, 3, failures)
	F.expect(engine.snapshot().actors.e_boss.boss.phase == 2 and engine.snapshot().actors.e_boss.stats.spd == 35, "下轮二阶段SPD只加5", failures)
	var pierces: Array = []
	for item in _events(engine, "damage", "e_boss"):
		if is_equal_approx(float(item.payload.factors.coefficient), 2.4): pierces.append(item)
	F.expect(pierces.size() == 1 and pierces[0].payload.factors.output_bonus == 0.0, "跨阶段穿刺保留蓄力时阶段倍率", failures)
	_past_boss(engine, 4, failures)
	var damage: Array = _events(engine, "damage", "e_boss")
	F.expect(is_equal_approx(float(damage.back().payload.factors.output_bonus), 0.2), "后续直接伤害获得二阶段20%输出", failures)
	F.expect(engine.snapshot().actors.e_boss.stats.spd == 35, "二阶段不会每轮重复加速", failures)

static func _test_replay(Policy, failures: Array[String]) -> void:
	var catalog = _catalog()
	var engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"))
	var initial: Dictionary = engine.snapshot()
	_past_boss(engine, 6, failures)
	var final_state: Dictionary = engine.snapshot()
	var commands: Array[Dictionary] = []
	commands.assign(final_state.command_log)
	var events: Array[Dictionary] = []
	events.assign(final_state.event_log.slice(initial.event_sequence))
	var recording := Replay.record(initial, commands, events)
	var result := Replay.verify(recording, catalog, Policy.new())
	F.expect(result.matches, "带同配置策略重放自动六步循环：" + str(result.get("first_difference", {})), failures)
	var transported: Dictionary = JSON.parse_string(JSON.stringify(recording, "", true, true))
	result = Replay.verify(transported, catalog, Policy.new())
	F.expect(result.matches, "Boss完整记录JSON传输后重放一致：" + str(result.get("first_difference", {})), failures)
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(final_state, "", true, true))
	var restored := Battle.new(catalog)
	restored.set_policy(Policy.new())
	restored.restore(decoded)
	F.expect(restored.last_errors.is_empty(), "带意图与Boss阈值的JSON快照严格恢复：" + str(restored.last_errors), failures)
	if restored.last_errors.is_empty():
		F.expect(State.validate(restored.snapshot()).is_empty(), "恢复未放松schema", failures)
		_past_boss(restored, 7, failures)
		F.expect(_boss_commands(restored).back().ability_id == "boss_suppress", "恢复后循环接续，无隐藏策略进度", failures)

static func _test_group_target_refresh(Policy, failures: Array[String]) -> void:
	var engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"))
	_past_boss(engine, 3, failures)
	var saved: Dictionary = engine.snapshot()
	saved.actors.p_a.hp = 0
	saved.actors.p_a.statuses = []
	saved.actors.p_a.shield = {}
	engine.restore(saved)
	_past_boss(engine, 4, failures)
	F.expect(engine.snapshot().actors.e_boss.boss.step == 5, "横震前有人倒地仍应按当前全体合法目标自动结算", failures)
	if engine.snapshot().actors.e_boss.boss.step != 5: return
	saved = engine.snapshot()
	saved.actors.p_c.hp = 0
	saved.actors.p_c.statuses = []
	saved.actors.p_c.shield = {}
	# p_c当前选择槽不能直接变倒地；从槽末保存再修改。
	if saved.active_actor_id == "p_c":
		engine.submit(_command(engine, "defend"))
		saved = engine.snapshot()
		saved.actors.p_c.hp = 0
		saved.actors.p_c.statuses = []
		saved.actors.p_c.shield = {}
	engine.restore(saved)
	_past_boss(engine, 5, failures)
	F.expect(engine.snapshot().actors.e_boss.boss.locked_targets == ["p_b"], "群体蓄力开始前刷新存活集合，避免旧意图非法停机", failures)

static func _test_policy_snapshot_validation(Policy, failures: Array[String]) -> void:
	var engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"))
	_past_boss(engine, 2, failures)
	var original: Dictionary = engine.snapshot()
	var cases: Array = []
	for pair in [["step", 2.5], ["phase", 3], ["charge_valid", "yes"], ["locked_targets", ["missing"]], ["opportunity_thresholds", {"p_a": 0.5}], ["committed_coefficient", -1.0], ["committed_phase_multiplier", 1.4], ["pending_phase", 1], ["pending_phase_round", 999]]:
		var bad := original.duplicate(true)
		bad.actors.e_boss.boss[pair[0]] = pair[1]
		cases.append(bad)
	var missing := original.duplicate(true)
	missing.actors.e_boss.boss.erase("step")
	cases.append(missing)
	missing = original.duplicate(true)
	missing.actors.e_boss.intent.erase("locked")
	cases.append(missing)
	missing = original.duplicate(true)
	missing.actors.e_boss.intent.target_ids = ["missing"]
	cases.append(missing)
	for bad in cases:
		engine.restore(bad)
		F.expect(not engine.last_errors.is_empty() and engine.snapshot() == original, "损坏Boss/意图快照必须原子拒绝，不重置步骤或机会", failures)
	var json: Dictionary = JSON.parse_string(JSON.stringify(original, "", true, true))
	engine.restore(json)
	F.expect(engine.last_errors.is_empty(), "有效蓄力等待快照JSON往返成功", failures)
	var restored: Dictionary = engine.snapshot()
	F.expect(restored.actors.e_boss.boss.step is int and restored.actors.e_boss.boss.phase is int, "Boss步骤与阶段严格恢复整数", failures)
	for value in restored.actors.e_boss.boss.opportunity_thresholds.values(): F.expect(value is int, "机会门槛严格恢复整数", failures)

static func _test_revival_window(Policy, failures: Array[String]) -> void:
	# 穿刺已锁定者倒地后在本轮复活，仍攻击原ID，但必须先给复活者新选择。
	var players := _players()
	players[0].hp = 5000
	var engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"), players)
	_past_boss(engine, 2, failures)
	var saved: Dictionary = engine.snapshot()
	F.expect(saved.actors.e_boss.boss.locked_targets == ["p_a"], "准备锁定测试中的最低比例者", failures)
	saved.actors.p_a.hp = 0
	saved.actors.p_a.statuses = []
	saved.actors.p_a.shield = {}
	engine.restore(saved)
	var revived: Dictionary = engine.submit(_command(engine, "item", "revival_potion", ["p_a"]))
	F.expect(revived.accepted and engine.snapshot().actors.e_boss.boss.locked_targets == ["p_a"], "复苏药不改原蓄力目标", failures)
	var threshold: int = engine.snapshot().actors.e_boss.boss.opportunity_thresholds.p_a
	F.expect(threshold == engine.snapshot().actors.p_a.opportunity_count + 1, "复活者立即获得新的选择门槛", failures)
	_past_boss(engine, 3, failures)
	var pierces: Array = []
	for item in _events(engine, "damage", "e_boss"):
		if is_equal_approx(item.payload.factors.coefficient, 2.4): pierces.append(item)
	F.expect(pierces.size() == 1 and pierces[0].payload.original_target_id == "p_a", "复活后穿刺仍攻击原目标", failures)
	# 蓄力时已倒地者不在原门槛中；复活加入，即使其本轮已错过队列也不能偷放。
	players = _players()
	players[0].hp = 0
	players[1].stats.spd = 40
	players[2].stats.spd = 10
	engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"), players)
	_past_boss(engine, 2, failures)
	F.expect(not engine.snapshot().actors.e_boss.boss.opportunity_thresholds.has("p_a"), "准备仅记当时存活队员门槛", failures)
	revived = engine.submit(_command(engine, "item", "revival_potion", ["p_a"]))
	F.expect(revived.accepted and engine.snapshot().actors.e_boss.boss.opportunity_thresholds.has("p_a"), "蓄力中原本倒地的队员复活后加入门槛", failures)
	saved = engine.snapshot()
	saved.actors.e_boss.stats.spd = 100
	engine.restore(saved)
	_past_boss(engine, 3, failures)
	F.expect(engine.snapshot().actors.e_boss.boss.step == 3, "快Boss必须等新复活成员实际获得机会", failures)
	_past_boss(engine, 4, failures)
	F.expect(engine.snapshot().actors.e_boss.boss.step == 4, "复活者行动之后解除等待", failures)

static func _test_charge_previews_and_modifiers(Policy, failures: Array[String]) -> void:
	var engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"))
	_past_boss(engine, 1, failures)
	# 停在准备槽，验证预览没有写入MP、锁定、阈值或RNG。
	for index in range(10):
		engine.advance(false)
		if engine.snapshot().active_actor_id == "e_boss": break
		engine.submit(_command(engine, "defend"))
	var policy = Policy.new()
	var command: Dictionary = policy.choose_command(engine.snapshot(), _catalog())
	var before: Dictionary = engine.snapshot()
	var preview: Dictionary = engine.preview(command)
	F.expect(preview.legal and preview.mp_cost == 6 and engine.snapshot() == before, "准备技预览合法且纯只读，费用6MP", failures)
	var result: Dictionary = engine.submit(command)
	F.expect(result.accepted and engine.snapshot().actors.e_boss.mp == 54, "预览与真实准备共享路径且只收费一次", failures)
	var duplicate: Dictionary = engine.submit(command)
	F.expect(not duplicate.accepted and engine.snapshot().actors.e_boss.mp == 54, "重复准备命令不得再次收费或续承诺", failures)
	var saved: Dictionary = engine.snapshot()
	Status.apply(saved.actors.e_boss, F.status("battle_spirit", 0.1, 5, "e_boss"))
	Status.apply(saved.actors.e_boss, F.status("weaken", 0.2, 2, "p_c"))
	saved.actors.e_boss.hp = 312
	engine.restore(saved)
	# 让预约阶段在玩家命令后建立，在下一轮释放时生效。
	for index in range(12):
		engine.advance(false)
		if engine.snapshot().active_actor_id == "e_boss": break
		engine.submit(_command(engine, "defend"))
	before = engine.snapshot()
	command = policy.choose_command(before, _catalog())
	preview = engine.preview(command)
	F.expect(preview.legal and preview.damage_ranges.size() == 1 and engine.snapshot() == before, "穿刺预览与真实目标一致且不推进RNG", failures)
	result = engine.submit(command)
	var damage: Dictionary = {}
	for item in result.events:
		if item.type == "damage": damage = item
	F.expect(not damage.is_empty() and damage.payload.normal == preview.damage_ranges[0].normal, "穿刺预览与真实伤害整数一致", failures)
	F.expect(is_equal_approx(damage.payload.factors.output_bonus, 0.1), "旧阶段承诺仅叠当前战意一次，不追补二阶段", failures)
	F.expect(is_equal_approx(damage.payload.factors.weaken_reduction, 0.2) and is_equal_approx(damage.payload.factors.reduction, 0.4), "释放时重新读取当前虚弱与目标防御", failures)
	_past_boss(engine, 4, failures)
	damage = _events(engine, "damage", "e_boss").back()
	F.expect(is_equal_approx(damage.payload.factors.output_bonus, 0.3), "新动作阶段20%与战意10%只加一次", failures)

static func _test_committed_command_rejection(Policy, failures: Array[String]) -> void:
	var engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"))
	engine.advance(false)
	engine.submit(_command(engine, "defend"))
	engine.advance(false)
	var before: Dictionary = engine.snapshot()
	var wrong := _command(engine, "skill", "boss_quake", [])
	var result: Dictionary = engine.submit(wrong)
	F.expect(not result.accepted and engine.snapshot() == before, "不能绕过公开压制指令偷换横震", failures)
	var expected: Dictionary = Policy.new().choose_command(before, _catalog())
	expected.target_ids = ["p_c"]
	result = engine.submit(expected)
	F.expect(not result.accepted and engine.snapshot() == before, "不能保持招式却偷换活目标", failures)

static func _test_wait_restore_and_immunity(Policy, failures: Array[String]) -> void:
	var engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"))
	_past_boss(engine, 2, failures)
	var saved: Dictionary = engine.snapshot()
	saved.actors.e_boss.stats.spd = 100
	engine.restore(saved)
	_past_boss(engine, 3, failures)
	var initial: Dictionary = engine.snapshot()
	var catalog = _catalog()
	var restored := Battle.new(catalog)
	restored.set_policy(Policy.new())
	restored.restore(JSON.parse_string(JSON.stringify(initial, "", true, true)))
	F.expect(restored.last_errors.is_empty(), "继续蓄力跨轮等待快照可恢复", failures)
	_past_boss(restored, 4, failures)
	F.expect(restored.snapshot().actors.e_boss.mp == 54 and restored.snapshot().actors.e_boss.boss.step == 4, "恢复等待不重复收费或重置门槛", failures)
	var commands: Array[Dictionary] = []
	commands.assign(restored.snapshot().command_log.slice(initial.command_log.size()))
	var events: Array[Dictionary] = []
	events.assign(restored.snapshot().event_log.slice(initial.event_sequence))
	var recording := Replay.record(State.normalize_snapshot(JSON.parse_string(JSON.stringify(initial, "", true, true))), commands, events)
	var result := Replay.verify(recording, catalog, Policy.new())
	F.expect(result.matches, "从继续蓄力中点带完整槽token精确重放：" + str(result.get("first_difference", {})), failures)
	var players := _players()
	players[0] = F.actor("controller", "p_a")
	players[0].stats.hp = 10000
	players[0].hp = 10000
	players[0].stats.spd = 40
	engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"), players)
	_past_boss(engine, 5, failures)
	for index in range(6):
		engine.advance()
		if engine.snapshot().active_actor_id == "p_a": break
		engine.submit(_command(engine, "defend"))
	var before: Dictionary = engine.snapshot()
	var seal := _command(engine, "skill", "seal", ["e_boss"])
	var preview: Dictionary = engine.preview(seal)
	F.expect(not preview.legal and preview.reasons.size() >= 2, "真实脉冲蓄力封缄预览明确报告眩晕和打断均免疫", failures)
	var submitted: Dictionary = engine.submit(seal)
	F.expect(not submitted.accepted and engine.snapshot() == before, "脉冲免疫纯控免费拒绝，MP/CD/行动/RNG均不变", failures)
	# 在独立战斗让清醒拒绝眩晕，但同一封缄的打断仍可取消穿刺。
	engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"), players)
	_past_boss(engine, 2, failures)
	saved = engine.snapshot()
	Status.apply(saved.actors.e_boss, F.status("awake", 1.0, 2, "e_boss"))
	engine.restore(saved)
	for index in range(6):
		engine.advance()
		if engine.snapshot().active_actor_id == "p_a": break
		engine.submit(_command(engine, "defend"))
	seal = _command(engine, "skill", "seal", ["e_boss"])
	preview = engine.preview(seal)
	F.expect(preview.legal and not preview.reasons.is_empty(), "清醒穿刺的封缄预览仍能打断，并显示眩晕无效", failures)
	submitted = engine.submit(seal)
	F.expect(submitted.accepted and engine.snapshot().actors.e_boss.boss.charge_interrupted and F.find_status(engine.snapshot().actors.e_boss, "stun").is_empty(), "封缄独立打断无额外眩晕", failures)
	_past_boss(engine, 3, failures)
	F.expect(engine.snapshot().actors.e_boss.boss.step == 4 and _events(engine, "boss_idle").size() == 1, "清醒下封缄取消的释放只空一槽", failures)

static func _test_policy_invalid_types(Policy, failures: Array[String]) -> void:
	var engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"))
	var original: Dictionary = engine.snapshot()
	for field in original.actors.e_boss.boss:
		for invalid in [null, "bad", [], {}]:
			if typeof(invalid) == typeof(original.actors.e_boss.boss[field]) and invalid == original.actors.e_boss.boss[field]: continue
			# release_id本来就是字符串，但未知ID仍非法。
			var bad := original.duplicate(true)
			bad.actors.e_boss.boss[field] = invalid
			engine.restore(bad)
			F.expect(not engine.last_errors.is_empty() and engine.snapshot() == original, "Boss字段错误类型原子拒绝：" + field, failures)
	for field in original.actors.e_boss.intent:
		var bad := original.duplicate(true)
		bad.actors.e_boss.intent[field] = null
		engine.restore(bad)
		F.expect(not engine.last_errors.is_empty() and engine.snapshot() == original, "意图字段空值原子拒绝：" + field, failures)

static func _test_standalone_intent_refresh(Policy, failures: Array[String]) -> void:
	var engine = _engine(Policy, F.enemy("hound", "e_one"))
	var state: Dictionary = engine.snapshot()
	var policy = Policy.new()
	var planned: Dictionary = policy.plan(state, "e_one", _catalog())
	state.actors[planned.target_ids[0]].hp = 0
	var refreshed: Dictionary = policy.refresh_target(state, planned)
	F.expect(refreshed.target_ids != planned.target_ids and refreshed.ability_id == planned.ability_id, "plan直接返回的意图也能刷新目标，不依赖先写回actor.intent", failures)

static func _test_policy_snapshot_consistency(Policy, failures: Array[String]) -> void:
	var engine = _engine(Policy, F.enemy("gatekeeper", "e_boss"))
	var original: Dictionary = engine.snapshot()
	var bad := original.duplicate(true)
	bad.actors.e_boss.intent.ability_id = "boss_quake"
	engine.restore(bad)
	F.expect(not engine.last_errors.is_empty() and engine.snapshot() == original, "恢复不能让意图跨过Boss循环步骤", failures)
	engine.restore(original)
	_past_boss(engine, 2, failures)
	original = engine.snapshot()
	for field in ["locked", "target_ids", "preview"]:
		bad = original.duplicate(true)
		if field == "locked": bad.actors.e_boss.intent.locked = false
		if field == "target_ids": bad.actors.e_boss.intent.target_ids = ["p_c"]
		if field == "preview": bad.actors.e_boss.intent.preview.actor_id = "p_a"
		engine.restore(bad)
		F.expect(not engine.last_errors.is_empty() and engine.snapshot() == original, "恢复拒绝与蓄力承诺冲突的意图：" + field, failures)
