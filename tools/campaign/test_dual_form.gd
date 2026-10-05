# Real engine commands prove that Homura switches careers without gaining actions.
extends SceneTree
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Factory = preload("res://scripts/rpg/actor_factory.gd")
const Battle = preload("res://scripts/rpg/battle_engine.gd")
const State = preload("res://scripts/rpg/battle_state.gd")
const Replay = preload("res://scripts/rpg/replay.gd")
const F = preload("res://tools/rpg/fixtures.gd")
var catalog: RefCounted
var failures: Array[String] = []
var assertions := 0
func expect(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1":
		printerr("FAIL: dual form tests require verified isolation")
		quit(1)
		return
	catalog = Catalog.new()
	catalog.load_all()
	_test_locked_form()
	_test_switch_protocol()
	_test_mage_skill_and_controls()
	print("CAMPAIGN_DUAL_FORM_ASSERTIONS: ", assertions)
	for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
func _actor(unlocked: bool = true) -> Dictionary:
	var actor := Factory.new(catalog).create("mage", "p_mage", 5, Factory.STANDARD)
	actor.merge({"identity_id": "homura", "form_id": "sword", "active_class_id": "swordsman", "dual_form_version": 1, "unlocked_forms": ["sword", "mage"] if unlocked else ["sword"], "skill_ids": catalog.get_definition("classes", "swordsman").skill_ids.duplicate()}, true)
	return actor
func _engine(actor: Dictionary) -> RefCounted:
	var engine := Battle.new(catalog)
	var enemy := F.enemy("hound", "enemy")
	enemy.stats.spd = 1
	var started := engine.start({"actors": {"p_mage": actor, "enemy": enemy}, "inventory": F.state(actor).inventory}, 137)
	expect(started.started, "true sword skill set validates on same mage-base Homura identity")
	return engine
func _command(engine: RefCounted, form: String, id: String = "") -> Dictionary:
	var state: Dictionary = engine.snapshot()
	return {"command_id": id if not id.is_empty() else "switch_%d" % state.revision, "expected_revision": state.revision, "actor_id": "p_mage", "kind": "switch_form", "ability_id": "", "target_ids": [], "form_id": form}
func _test_locked_form() -> void:
	var engine := _engine(_actor(false))
	if engine.snapshot().is_empty(): return
	engine.advance(false)
	var before: Dictionary = engine.snapshot()
	expect(not engine.preview(_command(engine, "mage")).legal and not engine.submit(_command(engine, "mage")).accepted and engine.snapshot() == before, "locked mage cannot switch and preview/submit never mutate")
	var actor := _actor()
	actor.skill_ids = catalog.get_definition("classes", "mage").skill_ids.duplicate()
	expect(not State.validate(F.state(actor)).is_empty(), "mismatched sword form and mage skill IDs rejected")
	var malformed := _actor()
	malformed.identity_id = false
	expect(not State.validate(F.state(malformed)).is_empty(), "dual metadata wrong identity type rejected without crashing")
	actor = _actor(false)
	actor.form_id = "mage"
	actor.active_class_id = "mage"
	actor.skill_ids = catalog.get_definition("classes", "mage").skill_ids.duplicate()
	expect(not State.validate(F.state(actor)).is_empty(), "mage form cannot forge an unlock")
func _test_switch_protocol() -> void:
	var actor := _actor()
	actor.hp -= 11
	actor.mp -= 9
	actor.cooldown_until = {"heavy_slash": 8, "firebolt": 8}
	actor.statuses = [F.status("weaken", 0.2, 3, "enemy")]
	var engine := _engine(actor)
	if engine.snapshot().is_empty(): return
	var initial: Dictionary = engine.snapshot()
	var events: Array[Dictionary] = []
	var commands: Array[Dictionary] = []
	events.append_array(engine.advance(false))
	var before: Dictionary = engine.snapshot()
	expect(before.active_actor_id == "p_mage", "Homura switch opportunity uses only its own current slot")
	var switch := _command(engine, "mage")
	expect(engine.preview(switch).legal and engine.snapshot() == before, "switch preview is read-only and costs no resources")
	var result: Dictionary = engine.submit(switch)
	expect(result.accepted, "unlocked Homura switches real skill set to mage")
	if not result.accepted: return
	commands.append(switch)
	events.append_array(result.events)
	var after: Dictionary = engine.snapshot()
	for field in ["phase", "active_actor_id", "slot_token", "queue", "queue_index", "round", "rng_state", "inventory"]:
		expect(after[field] == before[field], "switch preserves battle authority field " + field)
	for field in ["hp", "mp", "stats", "equipment", "statuses", "shield", "cooldown_until", "slot_count", "opportunity_count", "last_slot_round", "revived_round"]:
		expect(after.actors.p_mage[field] == before.actors.p_mage[field], "switch preserves shared actor field " + field)
	expect(after.actors.size() == before.actors.size() and after.actors.p_mage.skill_ids == catalog.get_definition("classes", "mage").skill_ids and after.actors.p_mage.active_class_id == "mage", "mage switch changes exactly the existing four real skills without a new actor")
	expect(after.revision == before.revision + 1 and after.command_log[-1] == switch and after.accepted_commands.has(switch.command_id), "switch participates in revision/command logs")
	expect(result.events.any(func(event): return event.type == "form_changed") and not result.events.any(func(event): return event.type == "slot_ended"), "switch emits form_changed and never ends the slot")
	expect(not engine.submit(switch).accepted and engine.snapshot() == after, "same command ID is rejected without double switching")
	var stale := _command(engine, "sword")
	stale.expected_revision -= 1
	expect(not engine.submit(stale).accepted and engine.snapshot() == after, "stale switch revision rejected")
	var wrong_actor := _command(engine, "sword")
	wrong_actor.actor_id = "enemy"
	expect(not engine.submit(wrong_actor).accepted and engine.snapshot() == after, "enemy/non-active actor cannot switch Homura")
	var back := _command(engine, "sword")
	result = engine.submit(back)
	expect(result.accepted and engine.snapshot().actors.p_mage.skill_ids == catalog.get_definition("classes", "swordsman").skill_ids and engine.snapshot().actors.p_mage.cooldown_until == before.actors.p_mage.cooldown_until, "switching back preserves cooldowns from both careers")
	commands.append(back)
	events.append_array(result.events)
	var sword_state: Dictionary = engine.snapshot()
	var skill := {"command_id": "actual_sword_skill", "expected_revision": sword_state.revision, "actor_id": "p_mage", "kind": "skill", "ability_id": "armor_break", "target_ids": ["enemy"]}
	var preview: Dictionary = engine.preview(skill)
	expect(preview.legal and preview.effects.any(func(event): return event.type == "damage"), "sword career actually resolves an existing sword skill")
	result = engine.submit(skill)
	expect(result.accepted and engine.snapshot().phase == "action_end", "ordinary sword skill still consumes exactly one action")
	commands.append(skill)
	events.append_array(result.events)
	var recording := Replay.record(initial, commands, events)
	var altered := recording.duplicate(true)
	altered.commands[0].form_id = "sword"
	expect(not Replay.verify(altered, catalog).matches, "tampered switch target cannot replay as the original events")
	expect(Replay.verify(recording, catalog).matches, "switch plus sword skill replay matches exact events")
	expect(Replay.verify(JSON.parse_string(JSON.stringify(recording, "", true, true)), catalog).matches, "JSON roundtrip preserves form-switch replay")
	var final: Dictionary = engine.snapshot()
	expect(not engine.submit(_command(engine, "mage")).accepted and engine.snapshot() == final, "switch outside current action selection cannot gain an action")

func _test_mage_skill_and_controls() -> void:
	var actor := _actor()
	var engine := _engine(actor)
	if engine.snapshot().is_empty(): return
	engine.advance(false)
	var before: Dictionary = engine.snapshot()
	var ordinary_magic := {"command_id": "wrong_magic", "expected_revision": before.revision, "actor_id": "p_mage", "kind": "attack_magic", "ability_id": "", "target_ids": ["enemy"]}
	expect(not engine.preview(ordinary_magic).legal, "sword career does not inherit mage basic attack")
	var wrong := _command(engine, "mage")
	wrong.target_ids = ["enemy"]
	expect(not engine.submit(wrong).accepted and engine.snapshot() == before, "switch cannot smuggle effect targets")
	wrong = _command(engine, "mage")
	wrong.ability_id = "firebolt"
	expect(not engine.submit(wrong).accepted and engine.snapshot() == before, "switch cannot smuggle a damaging ability")
	expect(engine.submit(_command(engine, "mage")).accepted, "mage skill execution switches current career")
	var mage_state: Dictionary = engine.snapshot()
	var magic := {"command_id": "actual_mage_skill", "expected_revision": mage_state.revision, "actor_id": "p_mage", "kind": "skill", "ability_id": "ice_arrow", "target_ids": ["enemy"]}
	expect(engine.preview(magic).legal, "actual current mage skill is selectable")
	var result: Dictionary = engine.submit(magic)
	expect(result.accepted and result.events.any(func(event): return event.type == "damage"), "actual mage skill damages through original effect pipeline")
	var after: Dictionary = engine.snapshot()
	expect(after.actors.p_mage.mp < mage_state.actors.p_mage.mp and after.actors.p_mage.cooldown_until.has("ice_arrow"), "mage skill pays original MP and stores its own cooldown ID")
	engine.advance(false)
	var enemy_state: Dictionary = engine.snapshot()
	var defend := {"command_id": "enemy_defend", "expected_revision": enemy_state.revision, "actor_id": enemy_state.active_actor_id, "kind": "defend", "ability_id": "", "target_ids": []}
	expect(engine.submit(defend).accepted, "next existing enemy slot progresses normally")
	engine.advance(false)
	var next_slot: Dictionary = engine.snapshot()
	var cooldowns: Dictionary = next_slot.actors.p_mage.cooldown_until.duplicate()
	expect(engine.submit(_command(engine, "sword")).accepted and engine.snapshot().actors.p_mage.cooldown_until == cooldowns, "returning to sword cannot clear or refresh an actual mage cooldown")
	var stunned := _actor()
	stunned.statuses = [F.status("stun", 0.0, 1, "enemy")]
	var controlled := _engine(stunned)
	if controlled.snapshot().is_empty(): return
	controlled.advance(false)
	var controlled_before: Dictionary = controlled.snapshot()
	expect(controlled_before.active_actor_id != "p_mage" and not controlled.submit(_command(controlled, "mage")).accepted and controlled.snapshot() == controlled_before, "stunned/skipped Homura cannot switch to recover a lost action")
