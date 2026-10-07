# 真实身份队伍的代表性战斗；只用公开预览选指令，保留胜败与资源，不注入胜利。
extends RefCounted
const F = preload("res://tools/rpg/fixtures.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Factory = preload("res://scripts/rpg/actor_factory.gd")
const Forms = preload("res://scripts/rpg/dual_form.gd")
const BattleEngine = preload("res://scripts/rpg/battle_engine.gd")
const Policy = preload("res://scripts/rpg/enemy_policy.gd")
const Strategy = preload("res://tools/campaign/saga_battle_strategy.gd")
const Replay = preload("res://scripts/rpg/replay.gd")
const IDENTITIES := {"swordsman": "rinne", "ranger": "mint", "guard": "guard", "mage": "homura", "healer": "healer", "controller": "controller"}

static func run() -> Array[String]:
	var failures: Array[String] = []
	F.assertion_count = 0
	var catalog := Catalog.new()
	F.expect(catalog.load_all().is_empty(), "实战使用权威技能目录", failures)
	var cases := [
		["slice_boss", 5, ["guard", "mage", "healer"], "mage"],
		["saga_c3_10", 7, ["swordsman", "ranger", "controller"], "sword"],
		["saga_c4_09", 8, ["guard", "mage", "healer"], "sword"],
		["saga_c7_13", 10, ["swordsman", "mage", "healer"], "mage"]
	]
	for row in cases:
		var actors: Dictionary = {}
		for class_id in row[2]:
			var actor: Dictionary = Factory.new(catalog).create(class_id, "p_" + class_id, row[1], Factory.STANDARD)
			actor["identity_id"] = IDENTITIES[class_id]
			if class_id == "mage":
				Forms.initialize(actor, catalog)
				actor.unlocked_forms = ["sword", "mage"]
				Forms.apply(actor, row[3], catalog)
			actors[actor.actor_id] = actor
		var encounter: Dictionary = catalog.get_definition("encounters", row[0])
		for index in encounter.enemy_ids.size():
			var id: String = "e_%02d_%s" % [index + 1, encounter.enemy_ids[index]]
			actors[id] = F.enemy(encounter.enemy_ids[index], id, encounter.level)
		var engine := BattleEngine.new(catalog)
		engine.set_policy(Policy.new())
		var started: Dictionary = engine.start({"actors": actors, "inventory": {"healing_potion": 3, "mana_potion": 1, "revival_potion": 1, "cleansing_powder": 1}}, 17)
		F.expect(started.started, "真实身份遭遇可启动：" + row[0], failures)
		var initial := engine.snapshot()
		var count := 0
		var used: Dictionary = {}
		while engine.snapshot().outcome.is_empty() and count < 180:
			engine.advance()
			var current := engine.snapshot()
			if not current.outcome.is_empty(): break
			var command: Dictionary = Strategy.choose(current, engine, catalog)
			F.expect(not command.is_empty(), "遭遇仍有真实合法指令：" + row[0], failures)
			if command.is_empty(): break
			if command.kind == "skill": used[command.actor_id + "/" + command.ability_id] = true
			var result := engine.submit(command)
			F.expect(result.accepted, "遭遇真实指令获接受：" + row[0], failures)
			if not result.accepted: break
			count += 1
		var final := engine.snapshot()
		F.expect(final.outcome in ["victory", "defeat"], "代表遭遇达到真实终局而非超时：" + row[0], failures)
		var commands: Array[Dictionary] = []
		commands.assign(final.command_log)
		var events: Array[Dictionary] = []
		events.assign(final.event_log.slice(initial.event_log.size()))
		var recording := Replay.record(initial, commands, events, catalog)
		var verified := Replay.verify(JSON.parse_string(JSON.stringify(recording, "", true, true)), catalog, Policy.new())
		F.expect(verified.matches, "含敌方机制的全战JSON重放逐事件相同：" + row[0] + str(verified.get("first_difference", {})), failures)
		var resources: Dictionary = {}
		for id in final.actors:
			if final.actors[id].side == "player": resources[id] = {"hp": final.actors[id].hp, "mp": final.actors[id].mp}
		print("TACTICS_ENCOUNTER:", JSON.stringify({"encounter": row[0], "level": row[1], "party": row[2], "homura_form": row[3], "outcome": final.outcome, "rounds": final.round, "commands": count, "used_skills": used.keys(), "resources": resources, "inventory": final.inventory, "replay_matches": verified.matches}))
	print("RPG 技法遭遇断言：", F.assertion_count)
	return failures
