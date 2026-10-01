# 引擎契约先于实现：队列、原子提交、前三职业与四种道具。
extends RefCounted

const F = preload("res://tools/rpg/fixtures.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const State = preload("res://scripts/rpg/battle_state.gd")
const Status = preload("res://scripts/rpg/status_rules.gd")

static func run() -> Array[String]:
	F.assertion_count = 0
	var failures: Array[String] = []
	for script in ["command_rules", "effect_resolver", "battle_engine"]:
		F.expect(FileAccess.file_exists("res://scripts/rpg/%s.gd" % script), "未实现引擎：" + script, failures)
	if not failures.is_empty():
		return failures
	var Engine = load("res://scripts/rpg/battle_engine.gd")
	_test_queue(Engine, failures)
	_test_transactions(Engine, failures)
	_test_cooldown(Engine, failures)
	_test_core_skills(Engine, failures)
	_test_cover(Engine, failures)
	_test_items_death(Engine, failures)
	_test_restore(Engine, failures)
	_test_edge_cases(Engine, failures)
	_test_battle_cleanup(Engine, failures)
	_test_first_hit_only(Engine, failures)
	_test_restore_slot_consistency(Engine, failures)
	print("RPG engine 断言：", F.assertion_count)
	return failures

static func _new_engine(Engine, actors: Array, seed: int = 7):
	var engine = Engine.new()
	var roster: Dictionary = {}
	for actor in actors:
		roster[actor.actor_id] = actor
	var started: Dictionary = engine.start({"actors": roster, "inventory": {"healing_potion": 3, "mana_potion": 1, "revival_potion": 1, "cleansing_powder": 1}}, seed)
	if not started.started: print("START ERRORS:", started.reasons)
	return engine

static func _command(engine, kind: String, ability: String = "", targets: Array = [], id: String = "") -> Dictionary:
	var state: Dictionary = engine.snapshot()
	return {"command_id": id if not id.is_empty() else "cmd_%d" % state.revision, "expected_revision": state.revision, "actor_id": state.active_actor_id, "kind": kind, "ability_id": ability, "target_ids": targets}

static func _selection(Engine, source: Dictionary, others: Array, seed: int = 7):
	source.stats.spd = 999
	var engine = _new_engine(Engine, [source] + others, seed)
	engine.advance()
	return engine

static func _event(events: Array, type: String) -> Dictionary:
	for event in events:
		if event.type == type:
			return event
	return {}

static func _next_actor(engine, id: String, failures: Array[String]) -> void:
	for iteration in range(30):
		engine.advance()
		var state: Dictionary = engine.snapshot()
		if state.active_actor_id == id or not state.outcome.is_empty():
			return
		var result: Dictionary = engine.submit(_command(engine, "defend"))
		F.expect(result.accepted, "推进明确的防御命令", failures)
	F.expect(false, "推进应在有限步内找到目标角色", failures)

static func _test_queue(Engine, failures: Array[String]) -> void:
	var a := F.actor("guard", "p_a")
	var b := F.actor("healer", "p_b")
	var x := F.enemy("hound", "e_a")
	var y := F.enemy("hound", "e_b")
	for actor in [a, b, x, y]:
		actor.stats.spd = 30
	var engine = _new_engine(Engine, [y, b, x, a])
	var events: Array = engine.advance()
	F.expect(engine.snapshot().queue == ["p_a", "p_b", "e_a", "e_b"], "同速玩家优先且阵营内 ID 升序", failures)
	F.expect(not _event(events, "round_queue").is_empty(), "轮序写入事件", failures)
	var before: Dictionary = engine.snapshot()
	engine.advance()
	F.expect(engine.snapshot() == before, "等待选择时 advance 幂等不加机会", failures)
	var changed: Dictionary = engine.snapshot()
	Status.apply(changed.actors.p_b, F.status("slow", 0.3, 1, "e_a"))
	engine.restore(changed)
	engine.submit(_command(engine, "defend"))
	engine.advance()
	F.expect(engine.snapshot().queue == ["p_a", "p_b", "e_a", "e_b"], "轮内缓速不改队列", failures)
	for iteration in range(3):
		engine.submit(_command(engine, "defend"))
		engine.advance()
	var state: Dictionary = engine.snapshot()
	F.expect(state.round == 2 and state.queue == ["p_a", "e_a", "e_b", "p_b"], "未来快照减速参与固定排序", failures)
	F.expect(state.actors.p_b.slot_count == 1 and state.actors.e_b.slot_count == 1, "每轮只有一个槽", failures)
	var stunned := F.actor("guard", "p_a")
	stunned.stats.spd = 100
	Status.apply(stunned, F.status("stun", 1.0, 1, "e_a"))
	var dead := F.actor("healer", "p_dead")
	dead.hp = 0
	engine = _new_engine(Engine, [stunned, dead, F.enemy("hound", "e_a")])
	engine.advance()
	state = engine.snapshot()
	F.expect(state.actors.p_a.slot_count == 1 and state.actors.p_a.opportunity_count == 0, "眩晕增长槽但不增长可选机会", failures)
	F.expect(state.actors.p_dead.slot_count == 0 and not state.queue.has("p_dead"), "倒地不入队不推进槽", failures)
	F.expect(not F.find_status(state.actors.p_a, "awake").is_empty(), "眩晕跳槽确实授予清醒", failures)

static func _test_transactions(Engine, failures: Array[String]) -> void:
	var engine = _selection(Engine, F.actor("swordsman", "sword"), [F.enemy("hound", "enemy")])
	var command := _command(engine, "skill", "heavy_slash", ["enemy"])
	var before: Dictionary = engine.snapshot()
	for iteration in range(11):
		F.expect(engine.preview(command).legal, "重斩预览合法", failures)
	F.expect(engine.snapshot() == before, "反复预览与取消不变资源、槽、RNG及日志", failures)
	var invalids: Array = []
	for edit in [{"target_ids": ["sword"]}, {"target_ids": ["missing"]}, {"target_ids": ["enemy", "enemy"]}, {"expected_revision": -1}, {"actor_id": "enemy"}, {"kind": "unknown"}, {"ability_id": "heal"}, {"command_id": ""}, {"expected_revision": 1.5}, {"target_ids": [4]}]:
		var invalid := command.duplicate(true)
		invalid.merge(edit, true)
		invalids.append(invalid)
	for invalid in invalids:
		F.expect(not engine.submit(invalid).accepted, "非法命令拒绝：" + str(invalid), failures)
		F.expect(engine.snapshot() == before, "非法命令严格零副作用", failures)
	var low := before.duplicate(true)
	low.actors.sword.mp = 0
	engine.restore(low)
	F.expect(not engine.submit(command).accepted and engine.snapshot() == low, "不足 MP 不消耗动作或 RNG", failures)
	low.inventory.healing_potion = 0
	engine.restore(low)
	F.expect(not engine.submit(_command(engine, "item", "healing_potion", ["sword"])).accepted and engine.snapshot() == low, "空库存不变状态", failures)
	engine.restore(before)
	var result: Dictionary = engine.submit(command)
	F.expect(result.accepted and engine.snapshot().actors.sword.mp == 32, "合法动作只收费一次", failures)
	var accepted: Dictionary = engine.snapshot()
	F.expect(not engine.submit(command).accepted and engine.snapshot() == accepted, "重复确认不收费不结算第二次", failures)
	engine.advance()
	before = engine.snapshot()
	F.expect(not engine.submit(command).accepted and engine.snapshot() == before, "同 ID 在下个槽仍拒绝", failures)
	F.expect(not _event(result.events, "command_accepted").is_empty() and not _event(result.events, "resources_changed").is_empty(), "指令与资源变化有完整日志", failures)
	F.expect(State.validate(engine.snapshot()).is_empty(), "每次合法提交维持硬约束", failures)

static func _test_cooldown(Engine, failures: Array[String]) -> void:
	var healer := F.actor("healer", "healer")
	healer.slot_count = 1
	healer.opportunity_count = 1
	healer.hp = 1
	var engine = _selection(Engine, healer, [F.enemy("hound", "enemy")])
	var result: Dictionary = engine.submit(_command(engine, "skill", "heal", ["healer"]))
	F.expect(result.accepted and engine.snapshot().actors.healer.hp == 87, "第2槽愈合回复86", failures)
	F.expect(engine.snapshot().actors.healer.cooldown_until.heal == 4, "CD1记最早槽4", failures)
	_next_actor(engine, "healer", failures)
	F.expect(engine.snapshot().actors.healer.slot_count == 3 and not engine.preview(_command(engine, "skill", "heal", ["healer"])).legal, "槽3愈合不可用", failures)
	engine.submit(_command(engine, "defend"))
	_next_actor(engine, "healer", failures)
	F.expect(engine.snapshot().actors.healer.slot_count == 4 and engine.preview(_command(engine, "skill", "heal", ["healer"])).legal, "槽4愈合可用", failures)
	healer = F.actor("healer", "healer")
	healer.slot_count = 2
	healer.cooldown_until["heal"] = 4
	Status.apply(healer, F.status("stun", 1.0, 1, "enemy"))
	engine = _selection(Engine, healer, [F.enemy("hound", "enemy")])
	F.expect(engine.snapshot().actors.healer.slot_count == 3, "眩晕推进冷却所用槽时钟", failures)
	_next_actor(engine, "healer", failures)
	F.expect(engine.preview(_command(engine, "skill", "heal", ["healer"])).legal, "眩晕后第4槽可施放", failures)

static func _test_core_skills(Engine, failures: Array[String]) -> void:
	var cases := [
		["guard", "cover", "ally"], ["guard", "shield_bash", "enemy"], ["guard", "iron_wall", "source"], ["guard", "taunt", "enemy"],
		["swordsman", "heavy_slash", "enemy"], ["swordsman", "armor_break", "enemy"], ["swordsman", "sweep", ""], ["swordsman", "battle_spirit", "source"],
		["healer", "heal", "ally"], ["healer", "group_heal", ""], ["healer", "cleanse", "ally"], ["healer", "holy_shield", "ally"]]
	for item in cases:
		var source := F.actor(item[0], "source")
		var ally := F.actor("guard", "ally")
		ally.hp = 100
		Status.apply(ally, F.status("weaken", 0.2, 2, "enemy"))
		var enemy := F.enemy("hound", "enemy")
		enemy.stats.def = 25
		enemy.boss = {"charge_valid": true, "charge_interruptible": true}
		var engine = _selection(Engine, source, [ally, enemy, F.enemy("hound", "enemy2")])
		var command := _command(engine, "skill", item[1], [] if item[2].is_empty() else [item[2]])
		var preview: Dictionary = engine.preview(command)
		var result: Dictionary = engine.submit(command)
		F.expect(preview.legal and result.accepted, "前三职业技能可执行：" + item[1], failures)
		var state: Dictionary = engine.snapshot()
		F.expect(State.validate(state).is_empty(), "技能后快照合法：" + item[1], failures)
		match item[1]:
			"cover": F.expect(F.find_status(state.actors.source, "cover").get("snapshot", {}).get("target_id") == "ally", "掩护属于守卫，关联队友", failures)
			"shield_bash": F.expect(not state.actors.enemy.boss.charge_valid and F.find_status(state.actors.enemy, "stun").is_empty(), "盾击只打断不眩晕", failures)
			"iron_wall": F.expect(state.actors.source.shield.amount == 70 and state.actors.source.shield.remaining == 2, "铁壁70且本槽不扣时长", failures)
			"taunt": F.expect(F.find_status(state.actors.enemy, "taunt").remaining == 2, "挑衅未来两槽", failures)
			"heavy_slash": F.expect(preview.damage_ranges[0].normal == 72 and preview.damage_ranges[0].critical == 108, "重斩同源预览72/108", failures)
			"armor_break":
				F.expect(preview.damage_ranges[0].normal == 48, "破甲斩不先减防", failures)
				F.expect(F.find_status(state.actors.enemy, "armor_break").remaining == 2, "伤害后挂破甲", failures)
			"sweep": F.expect(state.actors.enemy.hp < 180 and state.actors.enemy2.hp < 180, "横扫全部敌人", failures)
			"battle_spirit": F.expect(F.find_status(state.actors.source, "battle_spirit").remaining == 2, "自身新增战意本槽不扣", failures)
			"heal": F.expect(state.actors.ally.hp == 186, "愈合实际治疗86", failures)
			"group_heal": F.expect(state.actors.ally.hp == 143, "群疗固定10+0.6MATK", failures)
			"cleanse": F.expect(F.find_status(state.actors.ally, "weaken").is_empty() and state.actors.ally.hp == 100, "净化不治疗", failures)
			"holy_shield": F.expect(state.actors.ally.shield.amount == 64 and state.actors.ally.shield.remaining == 2, "圣盾64两槽", failures)
	var healer := F.actor("healer", "healer")
	healer.hp = 1
	Status.apply(healer, F.status("battle_spirit", 0.4, 2, "healer"))
	Status.apply(healer, F.status("weaken", 0.2, 2, "enemy"))
	var engine = _selection(Engine, healer, [F.enemy("hound", "enemy")])
	var rng_before: String = engine.snapshot().rng_state
	engine.submit(_command(engine, "skill", "heal", ["healer"]))
	F.expect(engine.snapshot().actors.healer.hp == 87 and engine.snapshot().rng_state == rng_before, "治疗不吃战意/虚弱且不抽RNG", failures)

static func _test_cover(Engine, failures: Array[String]) -> void:
	var guard := F.actor("guard", "guard")
	var guard2 := F.actor("guard", "guard2")
	var ally := F.actor("healer", "ally")
	guard.stats.mdef = 50
	ally.stats.mdef = 0
	Status.apply(ally, F.status("defend", 0.4, 1, "ally"))
	Status.apply(guard, F.status("cover", 0.3, 1, "guard", {"target_id": "ally"}))
	Status.apply(guard2, F.status("cover", 0.3, 1, "guard2", {"target_id": "guard"}))
	var engine = _selection(Engine, F.enemy("cultist", "enemy"), [guard, guard2, ally])
	var command := _command(engine, "skill", "weak_curse", ["ally"])
	var preview: Dictionary = engine.preview(command)
	F.expect(preview.damage_ranges[0].target_id == "guard" and preview.damage_ranges[0].normal == 15, "转伤重读守卫MDEF且不用被保护者防御", failures)
	engine.submit(command)
	var state: Dictionary = engine.snapshot()
	F.expect(state.actors.ally.hp == 210 and state.actors.guard.hp < 320 and state.actors.guard2.hp == 320, "单体掩护只转移一次不成链", failures)
	F.expect(F.find_status(state.actors.guard, "cover").is_empty() and not F.find_status(state.actors.guard2, "cover").is_empty(), "首段命中立刻消费唯一使用掩护", failures)
	F.expect(not F.find_status(state.actors.guard, "weaken").is_empty() and F.find_status(state.actors.ally, "weaken").is_empty(), "附带负面跟随转伤", failures)
	engine = _selection(Engine, F.enemy("gatekeeper", "boss"), [guard, ally])
	engine.submit(_command(engine, "skill", "boss_quake"))
	state = engine.snapshot()
	F.expect(state.actors.ally.hp < 210 and not F.find_status(state.actors.guard, "cover").is_empty(), "群攻不消耗掩护", failures)

static func _test_items_death(Engine, failures: Array[String]) -> void:
	var healer := F.actor("healer", "healer")
	var fallen := F.actor("guard", "fallen")
	fallen.hp = 0
	fallen.mp = 7
	fallen.cooldown_until["iron_wall"] = 5
	var engine = _selection(Engine, healer, [fallen, F.enemy("hound", "enemy")])
	var before: Dictionary = engine.snapshot()
	F.expect(not engine.submit(_command(engine, "skill", "heal", ["fallen"])).accepted and engine.snapshot() == before, "普通治疗不能复活", failures)
	engine.submit(_command(engine, "item", "revival_potion", ["fallen"]))
	var state: Dictionary = engine.snapshot()
	F.expect(state.actors.fallen.hp == 96 and state.actors.fallen.mp == 7 and state.actors.fallen.cooldown_until.iron_wall == 5, "复苏药30%保留MP和冷却", failures)
	F.expect(state.actors.fallen.revived_round == 1 and not state.queue.has("fallen"), "复活本轮不得重新入队", failures)
	_next_actor(engine, "fallen", failures)
	F.expect(engine.snapshot().round == 2 and engine.snapshot().actors.fallen.slot_count == 1, "复活下一轮才得槽", failures)
	for item in ["healing_potion", "mana_potion", "cleansing_powder"]:
		healer = F.actor("healer", "healer")
		healer.hp = 1
		healer.mp = 0
		Status.apply(healer, F.status("weaken", 0.2, 2, "enemy"))
		engine = _selection(Engine, healer, [F.enemy("hound", "enemy")])
		before = engine.snapshot()
		F.expect(engine.submit(_command(engine, "item", item, ["healer"])).accepted, "道具可执行：" + item, failures)
		state = engine.snapshot()
		F.expect(state.inventory[item] == before.inventory[item] - 1 and state.rng_state == before.rng_state, "道具扣一库存不抽随机", failures)
		if item == "healing_potion": F.expect(state.actors.healer.hp == 81, "治疗药固定80", failures)
		if item == "mana_potion": F.expect(state.actors.healer.mp == 20, "魔力药固定20", failures)
		if item == "cleansing_powder": F.expect(F.find_status(state.actors.healer, "weaken").is_empty(), "净化粉移除负面", failures)
	var enemy := F.enemy("hound", "enemy")
	enemy.hp = 1
	engine = _selection(Engine, F.actor("swordsman", "sword"), [enemy])
	var result: Dictionary = engine.submit(_command(engine, "skill", "armor_break", ["enemy"]))
	state = engine.snapshot()
	F.expect(state.outcome == "victory" and state.actors.enemy.statuses.is_empty(), "致死命中不能挂状态且判胜", failures)
	F.expect(not _event(result.events, "actor_defeated").is_empty(), "倒地明确日志", failures)
	var e2 := F.enemy("hound", "enemy2")
	e2.hp = 1
	engine = _selection(Engine, F.actor("swordsman", "sword"), [enemy, e2])
	result = engine.submit(_command(engine, "skill", "sweep"))
	var hits := 0
	for event in result.events:
		if event.type == "damage": hits += 1
	F.expect(hits == 2 and result.events.back().type == "outcome", "群攻完整批次后才判胜负", failures)
	var p := F.actor("guard", "p")
	p.hp = 0
	enemy.hp = 0
	engine = _new_engine(Engine, [p, enemy])
	engine.advance()
	F.expect(engine.snapshot().outcome == "defeat", "双方全倒算失败", failures)

static func _test_restore(Engine, failures: Array[String]) -> void:
	var actor := F.actor("swordsman", "sword")
	Status.apply(actor, F.status("weaken", 0.2, 2, "enemy"))
	var engine = _selection(Engine, actor, [F.enemy("hound", "enemy")])
	var live: Dictionary = engine.snapshot()
	F.expect(live.get("slot_token", {}).get("begun", false) and not live.slot_token.ended, "等待确认保存权威slot token", failures)
	var second = Engine.new()
	second.restore(JSON.parse_string(JSON.stringify(live, "", true, true)))
	F.expect(second.snapshot() == live and State.validate(second.snapshot()).is_empty(), "JSON往返按schema恢复整数并保留状态float", failures)
	var command := _command(engine, "defend")
	var first: Dictionary = engine.submit(command)
	var replayed: Dictionary = second.submit(command)
	F.expect(first == replayed and engine.snapshot() == second.snapshot(), "恢复后结算事件与时钟完全一致", failures)
	F.expect(F.find_status(second.snapshot().actors.sword, "weaken").remaining == 1 and second.snapshot().slot_token.is_empty(), "槽末只扣一次并清token", failures)
	var saved: Dictionary = second.snapshot()
	F.expect(not second.submit(command).accepted and second.snapshot() == saved, "恢复后重复确认不可再次推进时钟", failures)
	var corrupt := live.duplicate(true)
	corrupt.actors.sword.hp = 1.5
	second.restore(corrupt)
	F.expect(second.snapshot() == saved and not second.last_errors.is_empty(), "恢复小数HP拒绝且保留旧运行状态", failures)
	corrupt = live.duplicate(true)
	corrupt.slot_token.actor_id = "enemy"
	F.expect(not State.validate(corrupt).is_empty(), "严格验证slot token拥有者", failures)

static func _test_edge_cases(Engine, failures: Array[String]) -> void:
	# 结构损坏不能进入提交；所有拒绝保留已有有效快照。
	var engine = _selection(Engine, F.actor("guard", "guard"), [F.enemy("hound", "enemy")])
	var valid: Dictionary = engine.snapshot()
	for mutate in [
		func(s): s.erase("phase"),
		func(s): s.erase("active_actor_id"),
		func(s): s.erase("slot_token"),
		func(s): s.erase("event_sequence"),
		func(s): s.erase("event_log"),
		func(s): s.event_sequence += 1,
		func(s): s.event_log[0].sequence = 99,
		func(s): s.event_log[0].payload = "bad",
		func(s): s.command_log = [{}],
		func(s): s.accepted_commands = {"old": 1.5},
		func(s): s.slot_token.slot_count = 9,
		func(s): s.actors.guard.shield = {"amount": 10, "remaining": 1.5, "generation": 1, "applied_slot": 1, "source_id": "guard", "clock": "target_slot"}
	]:
		engine.restore(valid)
		var invalid := valid.duplicate(true)
		mutate.call(invalid)
		engine.restore(invalid)
		F.expect(engine.snapshot() == valid and not engine.last_errors.is_empty(), "损坏引擎快照原子拒绝", failures)
	for bad_setup in [{"actors": 4, "inventory": {}}, {"actors": {}, "inventory": 4}]:
		F.expect(not engine.start(bad_setup, 7).started and engine.snapshot() == valid, "非法setup拒绝且保留旧状态", failures)
	# 消耗后的日志连同浮点乘区可高精度JSON往返。
	engine.submit(_command(engine, "attack_physical", "", ["enemy"]))
	var second = Engine.new()
	second.restore(JSON.parse_string(JSON.stringify(engine.snapshot(), "", true, true)))
	F.expect(second.snapshot() == engine.snapshot(), "含伤害乘区与资源事件快照精确恢复", failures)
	# 尚有队员等待行动时倒地再复活，也不能重复拿到原队列槽。
	var sword := F.actor("swordsman", "sword")
	sword.stats.spd = 90
	var healer := F.actor("healer", "healer")
	healer.stats.spd = 80
	var fallen := F.actor("guard", "fallen")
	fallen.stats.spd = 10
	engine = _selection(Engine, sword, [healer, fallen, F.enemy("hound", "enemy")])
	var changed: Dictionary = engine.snapshot()
	changed.actors.fallen.hp = 0
	engine.restore(changed)
	engine.submit(_command(engine, "defend"))
	engine.advance()
	engine.submit(_command(engine, "item", "revival_potion", ["fallen"]))
	_next_actor(engine, "sword", failures)
	F.expect(engine.snapshot().round == 2 and engine.snapshot().actors.fallen.slot_count == 0, "本轮队列仍有槽的复活者也不能再动", failures)
	# 致死灼烧在机会之前处理，清关联掩护，不推进随机数。
	var doomed := F.actor("healer", "doomed")
	doomed.hp = 1
	Status.apply(doomed, F.status("burn", 10.0, 2, "enemy"))
	var guard := F.actor("guard", "guard")
	Status.apply(guard, F.status("cover", 0.3, 1, "guard", {"target_id": "doomed"}))
	engine = _new_engine(Engine, [doomed, guard, F.enemy("hound", "enemy")])
	changed = engine.snapshot()
	changed.actors.doomed.stats.spd = 999
	var rng_before: String = changed.rng_state
	engine.restore(changed)
	engine.advance()
	changed = engine.snapshot()
	F.expect(changed.actors.doomed.hp == 0 and changed.actors.doomed.slot_count == 1 and changed.actors.doomed.opportunity_count == 0, "灼烧先于机会并取消致死槽", failures)
	F.expect(F.find_status(changed.actors.guard, "cover").is_empty() and changed.rng_state == rng_before, "周期伤害不掩护不抽随机且解除关联", failures)
	# 普攻不会补MP，三法系默认魔法接口合法，其余职业不能捏造魔法指令。
	engine = _selection(Engine, F.actor("guard", "guard"), [F.enemy("hound", "enemy")])
	F.expect(not engine.preview(_command(engine, "attack_magic", "", ["enemy"])).legal, "非法魔法普攻拒绝", failures)
	var mp_before: int = engine.snapshot().actors.guard.mp
	engine.submit(_command(engine, "attack_physical", "", ["enemy"]))
	F.expect(engine.snapshot().actors.guard.mp == mp_before, "免费普攻不恢复MP", failures)
	# 控制预览按实际有效施加判断；伤害附带无效打断仍然可确认。
	var immune := F.enemy("gatekeeper", "boss")
	immune.boss = {"charge_valid": true, "charge_interruptible": false}
	engine = _selection(Engine, F.actor("guard", "guard"), [immune])
	var preview: Dictionary = engine.preview(_command(engine, "skill", "shield_bash", ["boss"]))
	F.expect(preview.legal and not preview.reasons.is_empty(), "伤害技能保留无效打断原因但可确认", failures)
	engine = _selection(Engine, F.actor("controller", "controller"), [immune])
	var command := _command(engine, "skill", "seal", ["boss"])
	var before: Dictionary = engine.snapshot()
	F.expect(not engine.preview(command).legal and not engine.submit(command).accepted and engine.snapshot() == before, "纯控制全免疫拒绝且不收费", failures)
	# 清醒只挡眩晕；仍有有效打断时封缄可执行。
	immune.boss.charge_interruptible = true
	Status.apply(immune, F.status("awake", 1.0, 2, "boss"))
	engine = _selection(Engine, F.actor("controller", "controller"), [immune])
	F.expect(engine.preview(_command(engine, "skill", "seal", ["boss"])).legal, "清醒不妨碍独立打断生效", failures)
	# 单目标低伤害的暴击概率仍然5%，不会因取整相等而伪装免暴击。
	var weak := F.actor("swordsman", "sword")
	weak.stats.atk = 1
	immune.stats.def = 999
	engine = _selection(Engine, weak, [immune])
	preview = engine.preview(_command(engine, "attack_physical", "", ["boss"]))
	F.expect(preview.damage_ranges[0].normal == 1 and preview.damage_ranges[0].critical == 1 and preview.damage_ranges[0].critical_chance == 0.05, "预览暴击概率独立于取整伤害", failures)

static func _test_battle_cleanup(Engine, failures: Array[String]) -> void:
	var sword := F.actor("swordsman", "sword")
	Status.apply(sword, F.status("battle_spirit", 0.4, 2, "sword"))
	Status.apply_shield(sword, F.shield(20, 2, "sword"))
	var enemy := F.enemy("hound", "enemy")
	enemy.hp = 1
	var engine = _selection(Engine, sword, [enemy])
	engine.submit(_command(engine, "skill", "heavy_slash", ["enemy"]))
	var state: Dictionary = engine.snapshot()
	F.expect(state.outcome == "victory" and state.actors.sword.statuses.is_empty() and state.actors.sword.shield.is_empty() and state.actors.sword.cooldown_until.is_empty(), "战果确定后状态/护盾/冷却清零", failures)
	var before := state.duplicate(true)
	F.expect(engine.advance().is_empty() and engine.snapshot() == before, "终局advance幂等", failures)
	F.expect(not engine.submit(_command(engine, "defend")).accepted and engine.snapshot() == before, "终局不能额外行动", failures)

static func _test_first_hit_only(Engine, failures: Array[String]) -> void:
	var root := F.write_catalog_copy("engine_two_hits", "enemies", func(document):
		for enemy in document.definitions:
			if enemy.id == "hound": enemy.abilities[0].effects.append(enemy.abilities[0].effects[0].duplicate(true)))
	var catalog := Catalog.new()
	F.expect(catalog.load_all(root).is_empty(), "多段边界测试目录合法", failures)
	var guard := F.actor("guard", "guard")
	guard.hp = 1
	Status.apply(guard, F.status("cover", 0.3, 1, "guard", {"target_id": "ally"}))
	var ally := F.actor("healer", "ally")
	var enemy := F.enemy("hound", "enemy")
	enemy.stats.spd = 999
	var engine = Engine.new(catalog)
	engine.start({"actors": {"guard": guard, "ally": ally, "enemy": enemy}, "inventory": {}}, 7)
	engine.advance()
	var result: Dictionary = engine.submit(_command(engine, "skill", "bite", ["ally"]))
	var targets: Array = []
	for item in result.events:
		if item.type == "damage": targets.append(item.target_id)
	F.expect(result.accepted and targets == ["guard", "ally"], "多段只转首段；守卫首段致死不吞第二段", failures)

# 审查I1：不用重放历史，当前队列/槽轮数/generation本身就足以拒绝这些矛盾。
static func _test_restore_slot_consistency(Engine, failures: Array[String]) -> void:
	var source := F.actor("swordsman", "sword")
	Status.apply(source, F.status("weaken", 0.2, 2, "enemy"))
	Status.apply_shield(source, F.shield(20, 2, "sword"))
	var engine = _selection(Engine, source, [F.enemy("hound", "enemy")])
	var waiting: Dictionary = engine.snapshot()
	var command := _command(engine, "defend")
	engine.submit(command)
	var ended: Dictionary = engine.snapshot()
	var cursor_back := ended.duplicate(true)
	cursor_back.queue_index = 0
	_assert_restore_rejected(engine, cursor_back, ended, "已结束槽游标回退", failures)
	var wrong_phase := waiting.duplicate(true)
	wrong_phase.phase = "action_end"
	wrong_phase.slot_token = {}
	wrong_phase.active_actor_id = ""
	_assert_restore_rejected(engine, wrong_phase, ended, "等待槽伪装已结束但游标不前进", failures)
	var cursor_forward := ended.duplicate(true)
	cursor_forward.queue_index = cursor_forward.queue.size()
	_assert_restore_rejected(engine, cursor_forward, ended, "游标跳过尚未开始的存活槽", failures)
	for edit in [
		func(s): s.slot_token.status_generations.clear(),
		func(s): s.slot_token.status_generations.weaken += 1,
		func(s): s.slot_token.status_generations["mark"] = 1,
		func(s): s.slot_token.shield_generation = -1,
		func(s): s.slot_token.shield_generation += 1,
		func(s): s.actors.sword.erase("last_slot_round"),
		func(s): s.actors.sword.last_slot_round = 2,
		func(s): s.actors.sword.statuses[0].applied_slot = 2,
		func(s): s.phase = "action_resolution",
		func(s): s.outcome = 4
	]:
		var corrupted := waiting.duplicate(true)
		edit.call(corrupted)
		_assert_restore_rejected(engine, corrupted, ended, "等待槽时钟或阶段不完整", failures)
	var dangling := ended.duplicate(true)
	dangling.active_actor_id = "sword"
	_assert_restore_rejected(engine, dangling, ended, "结束阶段不得遗留活动角色", failures)
	# 即使未来hook破坏了内部游标，advance也不能静默再加一个行动。
	engine._state = cursor_back.duplicate(true)
	var guarded: Array = engine.advance()
	F.expect(guarded.is_empty() and not engine.last_errors.is_empty() and engine.snapshot() == cursor_back, "advance本轮已开始槽防线不变资源/RNG/日志", failures)
	engine.restore(waiting)
	F.expect(engine.last_errors.is_empty() and engine.submit(command).accepted, "原始完整token仍可确认", failures)
	var result: Dictionary = engine.snapshot()
	F.expect(F.find_status(result.actors.sword, "weaken").remaining == 1 and result.actors.sword.shield.remaining == 1, "既存状态与护盾各扣一次", failures)
	# 本槽新增/刷新代不属于开始快照，不误计时。
	var refreshed := waiting.duplicate(true)
	Status.apply(refreshed.actors.sword, F.status("weaken", 0.2, 3, "enemy"))
	Status.apply(refreshed.actors.sword, F.status("battle_spirit", 0.4, 2, "sword"))
	Status.apply_shield(refreshed.actors.sword, F.shield(30, 3, "sword"))
	engine.restore(JSON.parse_string(JSON.stringify(refreshed, "", true, true)))
	F.expect(engine.last_errors.is_empty() and engine.submit(command).accepted, "本槽新代/刷新快照经JSON恢复仍合法", failures)
	result = engine.snapshot()
	F.expect(F.find_status(result.actors.sword, "weaken").remaining == 3 and F.find_status(result.actors.sword, "battle_spirit").remaining == 2 and result.actors.sword.shield.remaining == 3, "新代状态与新盾本槽不扣", failures)
	# 灼烧消耗掉旧盾，token仍须保留旧代；从槽开始事件可核对该代。
	source = F.actor("swordsman", "sword")
	Status.apply(source, F.status("burn", 10.0, 2, "enemy"))
	Status.apply_shield(source, F.shield(5, 2, "sword"))
	engine = _selection(Engine, source, [F.enemy("hound", "enemy")])
	var burned: Dictionary = engine.snapshot()
	var missing_burned_shield := burned.duplicate(true)
	missing_burned_shield.slot_token.shield_generation = -1
	_assert_restore_rejected(engine, missing_burned_shield, burned, "灼烧耗尽护盾仍不能丢旧代记录", failures)
	engine.restore(JSON.parse_string(JSON.stringify(burned, "", true, true)))
	F.expect(engine.last_errors.is_empty() and engine.submit(_command(engine, "defend")).accepted, "灼烧耗盾后完整token JSON恢复合法", failures)

static func _assert_restore_rejected(engine, corrupted: Dictionary, previous: Dictionary, label: String, failures: Array[String]) -> void:
	F.expect(not State.validate(corrupted).is_empty(), label + "的跨字段校验拒绝", failures)
	engine.restore(corrupted)
	F.expect(not engine.last_errors.is_empty() and engine.snapshot() == previous, label + "拒绝保留完整状态/RNG/资源/日志", failures)
	engine.restore(previous)
