# 六职业任意三人：每个Boss与收尾目标链均使用真实技能、道具和公开预览。
extends SceneTree
const Catalog = preload("res://scripts/rpg/catalog.gd")
const BattleEngine = preload("res://scripts/rpg/battle_engine.gd")
const Policy = preload("res://scripts/rpg/enemy_policy.gd")
const Factory = preload("res://scripts/rpg/actor_factory.gd")
const Fixture = preload("res://tools/rpg/fixtures.gd")
const Strategy = preload("res://tools/campaign/saga_battle_strategy.gd")
const BOSSES := ["saga_c2_12", "saga_c3_10", "saga_c4_09", "saga_c5_12", "saga_c6_11", "saga_c7_05", "saga_c7_06", "saga_c7_10"]
var failures: Array[String] = []
var count := 0
var cursor := 0
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _run() -> void:
	var catalog := Catalog.new()
	if not catalog.load_all().is_empty(): quit(1); return
	var factory := Factory.new(catalog)
	for encounter_id in BOSSES:
		if not OS.get_environment("SAGA_ENCOUNTER").is_empty() and encounter_id != OS.get_environment("SAGA_ENCOUNTER"): continue
		var encounter: Dictionary = catalog.get_definition("encounters", encounter_id)
		for first in range(4):
			for second in range(first + 1, 5):
				for third in range(second + 1, 6):
					cursor += 1
					if cursor <= int(OS.get_environment("SAGA_MATRIX_START")): continue
					var party: Array = [Catalog.CLASS_IDS[first], Catalog.CLASS_IDS[second], Catalog.CLASS_IDS[third]]
					var actors := {}
					for id in party: actors["p_" + id] = factory.create(id, "p_" + id, encounter.level, Factory.STANDARD)
					for index in encounter.enemy_ids.size():
						var enemy_id: String = encounter.enemy_ids[index]
						var actor_id := "e_%02d_%s" % [index + 1, enemy_id]
						actors[actor_id] = Fixture.enemy(enemy_id, actor_id, encounter.level)
					var engine := BattleEngine.new(catalog); engine.set_policy(Policy.new())
					var start: Dictionary = engine.start({"actors": actors, "inventory": {"healing_potion": 6, "mana_potion": 4, "revival_potion": 3, "cleansing_powder": 4}}, 17)
					if not start.started: failures.append(encounter_id + str(party) + str(start.reasons)); continue
					var commands := 0
					while engine.snapshot().outcome.is_empty() and commands < 100:
						engine.advance()
						var state: Dictionary = engine.snapshot()
						if not state.outcome.is_empty(): break
						if state.phase != "action_selection" or state.actors[state.active_actor_id].side != "player": break
						var command: Dictionary = Strategy.choose(state, engine, catalog)
						if command.is_empty(): break
						var result: Dictionary = engine.submit(command)
						if not result.accepted: break
						commands += 1
					var final: Dictionary = engine.snapshot()
					count += 1
					var summary := "%s %s outcome=%s round=%d commands=%d" % [encounter_id, "/".join(party), final.outcome, final.round, commands]
					print("SAGA_PARTY_RESULT:", summary)
					if final.outcome != "victory": failures.append(summary)
	print("SAGA_PARTY_MATRIX:", count, " FAILURES:", failures.size())
	for failure in failures: printerr("ASSERT FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
