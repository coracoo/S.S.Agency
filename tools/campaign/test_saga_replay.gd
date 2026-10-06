# 战斗扩展必须可从相同种子与真实输入逐事件重演，包括JSON运输。
extends SceneTree
const Catalog = preload("res://scripts/rpg/catalog.gd")
const BattleEngine = preload("res://scripts/rpg/battle_engine.gd")
const Policy = preload("res://scripts/rpg/enemy_policy.gd")
const Factory = preload("res://scripts/rpg/actor_factory.gd")
const Fixture = preload("res://tools/rpg/fixtures.gd")
const Strategy = preload("res://tools/campaign/saga_battle_strategy.gd")
const Replay = preload("res://scripts/rpg/replay.gd")
var failures: Array[String] = []
var count := 0
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _run() -> void:
	var catalog := Catalog.new()
	if not catalog.load_all().is_empty(): quit(1); return
	var factory := Factory.new(catalog)
	for encounter_id in ["saga_c2_12", "saga_c3_10", "saga_c4_09", "saga_c5_12", "saga_c6_11", "saga_c7_05", "saga_c7_06", "saga_c7_10"]:
		var encounter: Dictionary = catalog.get_definition("encounters", encounter_id)
		var actors := {}
		for id in ["guard", "mage", "healer"]: actors["p_" + id] = factory.create(id, "p_" + id, encounter.level, Factory.STANDARD)
		for index in encounter.enemy_ids.size():
			var enemy_id: String = encounter.enemy_ids[index]
			var actor_id := "e_%02d_%s" % [index + 1, enemy_id]
			actors[actor_id] = Fixture.enemy(enemy_id, actor_id, encounter.level)
		var engine := BattleEngine.new(catalog); engine.set_policy(Policy.new())
		var started: Dictionary = engine.start({"actors": actors, "inventory": {"healing_potion": 3, "mana_potion": 2, "revival_potion": 1, "cleansing_powder": 1}}, 43)
		if not started.started: failures.append(encounter_id + str(started.reasons)); continue
		var initial: Dictionary = engine.snapshot()
		for opportunity in range(12):
			engine.advance()
			var state: Dictionary = engine.snapshot()
			if not state.outcome.is_empty(): break
			var command: Dictionary = Strategy.choose(state, engine, catalog)
			if command.is_empty() or not engine.submit(command).accepted: failures.append(encounter_id + "未执行真实行动"); break
		var final: Dictionary = engine.snapshot()
		var commands: Array[Dictionary] = []
		commands.assign(final.command_log)
		var events: Array[Dictionary] = []
		events.assign(final.event_log.slice(initial.event_log.size()))
		var recording: Dictionary = Replay.record(initial, commands, events)
		for transported in [false, true]:
			var record: Dictionary = JSON.parse_string(JSON.stringify(recording, "", true, true)) if transported else recording
			var verification: Dictionary = Replay.verify(record, catalog, Policy.new())
			count += 1
			if not verification.matches: failures.append(encounter_id + " JSON=" + str(transported) + str(verification.first_difference))
		print("SAGA_REPLAY_RESULT:", encounter_id, " commands=", commands.size(), " events=", events.size())
	print("SAGA_REPLAY_ASSERTIONS:", count, " FAILURES:", failures.size())
	for failure in failures: printerr("ASSERT FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
