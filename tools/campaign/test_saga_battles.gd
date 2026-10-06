# 七章遭遇与机制：隔离目录内用真实模型和公开预览验证，不伪造胜利。
extends SceneTree
const Catalog = preload("res://scripts/rpg/catalog.gd")
const BattleEngine = preload("res://scripts/rpg/battle_engine.gd")
const Policy = preload("res://scripts/rpg/enemy_policy.gd")
const Factory = preload("res://scripts/rpg/actor_factory.gd")
const State = preload("res://scripts/rpg/battle_state.gd")
const Resolver = preload("res://scripts/rpg/effect_resolver.gd")
const Fixture = preload("res://tools/rpg/fixtures.gd")
var failures: Array[String] = []
var assertions := 0
var catalog: RefCounted
var rules: Script
const ENCOUNTERS := ["saga_c2_03", "saga_c2_07", "saga_c2_09", "saga_c2_12", "saga_c2_s02", "saga_c3_03", "saga_c3_07", "saga_c3_10", "saga_c3_s01", "saga_c3_s02", "saga_c4_04", "saga_c4_09", "saga_c4_s02", "saga_c5_09", "saga_c5_12", "saga_c5_s02", "saga_c6_04", "saga_c6_11", "saga_c6_s02", "saga_c6_s04", "saga_c7_05", "saga_c7_06", "saga_c7_10", "saga_c7_11", "saga_c7_12", "saga_c7_13"]
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); printerr("ASSERT FAIL: ", message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _run() -> void:
	check(FileAccess.file_exists("res://data/rpg/saga_enemies.json"), "后六章必须有独立敌人定义，保留六原敌源表")
	check(FileAccess.file_exists("res://data/rpg/saga_encounters.json"), "批准战斗场次必须有真实遭遇")
	check(ResourceLoader.exists("res://scripts/rpg/saga_boss_rules.gd"), "必须提供六章可执行机制")
	if not failures.is_empty(): _finish(); return
	rules = load("res://scripts/rpg/saga_boss_rules.gd")
	catalog = Catalog.new()
	check(catalog.load_all().is_empty(), "Saga数据通过权威目录整体验证")
	if not failures.is_empty(): _finish(); return
	_test_catalog()
	_test_voice()
	_test_banner()
	_test_mirror()
	_test_lamp()
	_test_anchors()
	_test_closure()
	_test_snapshot()
	_test_preview_purity()
	if OS.get_environment("SAGA_SKIP_LIVE") != "1": _test_live_battles()
	_finish()
func _finish() -> void:
	print("SAGA_BATTLE_ASSERTIONS:", assertions, " FAILURES:", failures.size())
	quit(0 if failures.is_empty() else 1)
func _test_catalog() -> void:
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rpg/enemies.json"))
	check(original.definitions.size() == 6, "六个原敌与xlsx定义保持不变")
	for id in ENCOUNTERS:
		var row: Dictionary = catalog.get_definition("encounters", id)
		check(not row.is_empty(), "批准战斗已接线：" + id)
		for enemy_id in row.get("enemy_ids", []):
			var enemy: Dictionary = catalog.get_definition("enemies", enemy_id)
			check(enemy.get("sprite_id", enemy_id) in ["hound", "shield_soldier", "fire_spirit", "cultist", "elite_shield_soldier", "gatekeeper"], "新敌必须使用已登记原图：" + enemy_id)
func _setup(encounter_id: String, party: Array = ["guard", "mage", "healer"], level: int = 8) -> Dictionary:
	var actors: Dictionary = {}
	var factory := Factory.new(catalog)
	for id in party: actors["p_" + id] = factory.create(id, "p_" + id, level, Factory.STANDARD)
	var encounter: Dictionary = catalog.get_definition("encounters", encounter_id)
	for index in encounter.enemy_ids.size():
		var enemy_id: String = encounter.enemy_ids[index]
		var actor_id := "e_%02d_%s" % [index + 1, enemy_id]
		actors[actor_id] = Fixture.enemy(enemy_id, actor_id, encounter.level)
	return {"actors": actors, "inventory": {"healing_potion": 6, "mana_potion": 4, "revival_potion": 3, "cleansing_powder": 4}}
func _engine(encounter_id: String, party: Array = ["guard", "mage", "healer"], level: int = 8) -> RefCounted:
	var engine := BattleEngine.new(catalog)
	engine.set_policy(Policy.new())
	var result: Dictionary = engine.start(_setup(encounter_id, party, level), 17)
	check(result.started, "模型可启动：" + encounter_id + str(result.reasons))
	return engine
func _enemy_id(state: Dictionary, class_id: String) -> String:
	for id in state.actors:
		if state.actors[id].class_id == class_id: return id
	return ""
func _command(state: Dictionary, actor_id: String, kind: String, ability_id: String = "", targets: Array = []) -> Dictionary:
	return {"command_id": "saga_test_%d_%s" % [state.revision, actor_id], "expected_revision": int(state.revision), "actor_id": actor_id, "kind": kind, "ability_id": ability_id, "target_ids": targets.duplicate()}
func _test_voice() -> void:
	var engine := _engine("saga_c2_12")
	var state: Dictionary = engine.snapshot()
	var id := _enemy_id(state, "saga_borrowed_voice")
	var policy := Policy.new()
	policy.after_command(state, _command(state, "p_guard", "defend", "", ["p_guard"]), catalog)
	state.round += 1
	policy.before_round(state, catalog)
	check(state.actors[id].intent.ability_id == "saga_voice_guard", "借声客逐轮回放上一轮最后行动中的防守")
	policy.after_command(state, _command(state, "p_mage", "attack_magic", "", [id]), catalog)
	state.round += 1; var round_events: Array = policy.before_round(state, catalog)
	check(round_events.any(func(e): return e.type == "saga_voice_replay"), "回放语料只在真实换轮回放时触发")
	var response: Array = policy.after_command(state, _command(state, "p_guard", "defend", "", ["p_guard"]), catalog)
	check(response.any(func(e): return e.type == "saga_voice_guarded"), "攻后转守反馈来自真实防御行动")
	check(state.actors[id].intent.ability_id == "saga_voice_magic", "借声客改为回放实际术法，不能只改文案")
func _test_banner() -> void:
	var state: Dictionary = _engine("saga_c3_10").snapshot()
	var id := _enemy_id(state, "saga_backshore_general")
	state.actors[id].saga.step = 1
	state.actors[id].saga.interrupted = false
	state.actors[id].intent = Policy.new().plan(state, id, catalog)
	check(state.actors[id].intent.interruptible, "背岸将号令给出可打断意图")
	var support := _enemy_id(state, "saga_paper_soldier")
	state.actors[support].hp = 0
	var events: Array = Resolver.resolve(state, _command(state, "p_guard", "skill", "shield_bash", [id]), catalog, null)
	check(events.any(func(e): return e.type == "charge_interrupted"), "固定盾击真正打断补位号令")
	Resolver.resolve(state, _command(state, id, "skill", "saga_banner_release", ["p_guard", "p_healer", "p_mage"]), catalog, null)
	check(state.actors[support].hp == 0, "打断后不会复起纸兵")
	state.actors[id].hp = 0
	Policy.new().after_command(state, _command(state, "p_guard", "attack_physical", "", [id]), catalog)
	check(state.actors.values().all(func(a): return a.side != "enemy" or a.hp == 0), "击断旧令即清除失去号令纸兵，不要求全清")
func _test_mirror() -> void:
	var state: Dictionary = _engine("saga_c4_09").snapshot()
	var id := _enemy_id(state, "saga_joined_mirror")
	var before: int = state.actors.p_guard.hp
	state.actors[id].saga.phase = 1
	var events: Array = Resolver.resolve(state, _command(state, "p_guard", "attack_physical", "", [id]), catalog, null)
	check(state.actors.p_guard.hp < before and events.any(func(e): return e.type == "saga_reflected"), "刀光面真实反物理，预览与实际同管线")
	var body: Dictionary = state.actors.p_guard.duplicate(true)
	state.actors[id].saga.phase = 3
	Resolver.resolve(state, _command(state, "p_guard", "attack_physical", "", [id]), catalog, null)
	check(state.actors.p_guard.hp == body.hp, "脱面窗口允许纯物理队攻击")
	check(state.actors.p_guard.actor_id == body.actor_id and state.actors.p_guard.mp == body.mp and state.actors.p_guard.skill_ids == body.skill_ids, "反射机制不改变玩家身份、技能或资源归属")
func _test_lamp() -> void:
	var state: Dictionary = _engine("saga_c5_12").snapshot()
	var id := _enemy_id(state, "saga_hundredhand_lamp")
	state.actors[id].hp -= 100; state.actors[id].saga.step = 1
	var before: int = state.actors[id].hp
	var events: Array = Resolver.resolve(state, _command(state, id, "skill", "saga_lamp_drain", ["p_guard", "p_healer", "p_mage"]), catalog, null)
	check(state.actors[id].hp > before and not state.actors[id].shield.is_empty(), "吸取确实借伤害补生命及灯罩")
	check(events.any(func(e): return e.type == "saga_lamp_drained"), "吸命真实收益有明示反馈")
	state.actors[id].saga.interrupted = true
	var hp_before: int = state.actors.p_guard.hp
	Resolver.resolve(state, _command(state, id, "skill", "saga_lamp_drain", ["p_guard", "p_healer", "p_mage"]), catalog, null)
	check(state.actors.p_guard.hp == hp_before, "打断吸取后无伤害、无暗补罩")
func _test_anchors() -> void:
	var state: Dictionary = _engine("saga_c6_11").snapshot()
	var id := _enemy_id(state, "saga_nochange_warden")
	var before: int = state.actors[id].hp
	Resolver.resolve(state, _command(state, "p_guard", "attack_physical", "", [id]), catalog, null)
	check(state.actors[id].hp == before, "联动锚点未隔离时不能靠削核心跳过目标")
	for actor in state.actors.values():
		if actor.class_id in ["saga_anchor_left", "saga_anchor_right"]: actor.hp = 0
	Resolver.resolve(state, _command(state, "p_guard", "attack_physical", "", [id]), catalog, null)
	check(state.actors[id].hp < before, "两侧隔离后胸牌真正暴露")
func _test_closure() -> void:
	for encounter_id in ["saga_c7_10", "saga_c7_11", "saga_c7_12", "saga_c7_13"]:
		var state: Dictionary = _engine(encounter_id).snapshot()
		var core := _enemy_id(state, "saga_final_recoil")
		var relay := _enemy_id(state, "saga_relay_recoil")
		var exit_id := _enemy_id(state, "saga_exit_recoil")
		var before: int = state.actors[core].hp
		Resolver.resolve(state, _command(state, "p_guard", "attack_physical", "", [core]), catalog, null)
		check(state.actors[core].hp == before, "收尾不可只清核心跳救援：" + encounter_id)
		before = state.actors[relay].hp
		Resolver.resolve(state, _command(state, "p_guard", "attack_physical", "", [relay]), catalog, null)
		check(state.actors[relay].hp == before, "必须先保出口再处理分流：" + encounter_id)
		state.actors[exit_id].hp = 0
		Resolver.resolve(state, _command(state, "p_guard", "attack_physical", "", [relay]), catalog, null)
		check(state.actors[relay].hp < before, "出口完成后真实开放下一目标：" + encounter_id)
		state.actors[relay].hp = 1
		var cleared: Array = Resolver.resolve(state, _command(state, "p_guard", "attack_physical", "", [relay]), catalog, null)
		check(cleared.any(func(e): return e.type == "saga_objective_completed"), "分流完成由真实击破事件确认：" + encounter_id)
func _test_snapshot() -> void:
	var engine := _engine("saga_c4_09")
	engine.advance(false)
	var before: Dictionary = engine.snapshot()
	var restored := BattleEngine.new(catalog); restored.set_policy(Policy.new())
	restored.restore(JSON.parse_string(JSON.stringify(before, "", false, true)))
	check(restored.last_errors.is_empty() and _equivalent(restored.snapshot(), before), "Saga战斗状态JSON往返保留机制、意图和行动token：" + str(restored.last_errors))
	var invalid: Dictionary = before.duplicate(true)
	var id := _enemy_id(invalid, "saga_joined_mirror")
	invalid.actors[id].saga.step = 1.5
	check(not State.validate(invalid).is_empty(), "拒绝小数机制步骤")
	invalid = before.duplicate(true); invalid.actors.p_guard["saga"] = invalid.actors[id].saga.duplicate(true)
	check(not State.validate(invalid).is_empty(), "玩家不得伪造敌方机制或第二身份")
	invalid = before.duplicate(true); invalid.actors[id].erase("saga")
	check(not State.validate(invalid).is_empty(), "公开意图已建立后不得剥除机制重置阶段与修复次数")
	invalid.actors[id].intent = null
	check(not State.validate(invalid).is_empty(), "损坏意图返回验证错误而非脚本异常")
	invalid = before.duplicate(true); invalid.actors[id].intent.ability_id = "saga_lamp_drain"
	check(not State.validate(invalid).is_empty(), "镜Boss不能恢复为另一Boss的吸取指令")
func _test_preview_purity() -> void:
	check(Resolver.new().has_method("simulation_state"), "解析器副本须剥离只读历史，避免长战逐候选复制全部日志")
	if not Resolver.new().has_method("simulation_state"): return
	for encounter in ["saga_c3_10", "saga_c4_09", "saga_c5_12", "saga_c6_11", "saga_c7_10"]:
		var engine := _engine(encounter)
		var state: Dictionary = engine.snapshot()
		var original: Dictionary = state.duplicate(true)
		var simulation: Dictionary = Resolver.new().call("simulation_state", state)
		check(not simulation.has("event_log") and not simulation.has("command_log"), "预览副本不复制不可变重放历史：" + encounter)
		for id in simulation.actors:
			var actor: Dictionary = simulation.actors[id]
			if actor.side != "enemy": continue
			var plan: Dictionary = Policy.new().plan(simulation, id, catalog)
			Resolver.resolve(simulation, _command(simulation, id, "skill", plan.ability_id, plan.target_ids), catalog, null)
			Resolver.resolve(simulation, _command(simulation, "p_guard", "skill", "shield_bash", [id]), catalog, null)
			Resolver.resolve(simulation, _command(simulation, "p_mage", "attack_magic", "", [id]), catalog, null)
		check(_equivalent(state, original), "解析器所有嵌套写入均隔离，资源/库存/RNG/日志不变：" + encounter)
		engine.advance()
		state = engine.snapshot(); original = state.duplicate(true)
		var command: Dictionary = load("res://tools/campaign/saga_battle_strategy.gd").choose(state, engine, catalog)
		var first: Dictionary = engine.preview(command)
		var second: Dictionary = engine.preview(command)
		check(_equivalent(first, second) and _equivalent(engine.snapshot(), original), "真实预览可重复且不改变任何快照字段：" + encounter)

func _test_live_battles() -> void:
	for encounter_id in ENCOUNTERS:
		if not OS.get_environment("SAGA_ENCOUNTER").is_empty() and encounter_id != OS.get_environment("SAGA_ENCOUNTER"): continue
		var level: int = mini(10, int(catalog.get_definition("encounters", encounter_id).level) + 1)
		var engine := _engine(encounter_id, ["guard", "mage", "healer"], level)
		var commands := 0
		while engine.snapshot().outcome.is_empty() and commands < 180:
			engine.advance()
			var state: Dictionary = engine.snapshot()
			if not state.outcome.is_empty(): break
			if state.phase != "action_selection" or state.actors[state.active_actor_id].side != "player":
				check(false, "敌方自动执行不能卡住：" + encounter_id + str(engine.last_errors)); break
			var command: Dictionary = load("res://tools/campaign/saga_battle_strategy.gd").choose(state, engine, catalog)
			if command.is_empty(): check(false, "玩家须有合法动作：" + encounter_id); break
			var result: Dictionary = engine.submit(command)
			if not result.accepted: check(false, "真实行动被拒：" + encounter_id + str(result.reasons)); break
			commands += 1
			if commands % 20 == 0: print("SAGA_PROGRESS:", encounter_id, " commands=", commands, " round=", state.round, " command=", command, " hp=", state.actors.values().map(func(a): return [a.actor_id,a.hp,a.mp]))
		var final: Dictionary = engine.snapshot()
		print("SAGA_BATTLE_RESULT:", encounter_id, " outcome=", final.outcome, " rounds=", final.round, " commands=", commands)
		check(final.outcome == "victory", "合理固定技能战术真实取胜：" + encounter_id)

# JSON数值可发生末位浮点舍入；离散状态严格相等，连续预览因子在浮点精度内比较。
func _equivalent(left, right) -> bool:
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size(): return false
		for key in left:
			if not right.has(key) or not _equivalent(left[key], right[key]): return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size(): return false
		for index in left.size():
			if not _equivalent(left[index], right[index]): return false
		return true
	if left is float and right is float: return is_equal_approx(left, right)
	return left == right
