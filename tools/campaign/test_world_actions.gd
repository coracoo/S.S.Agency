# One-shot world interaction transactions, only under verified isolated user://.
extends SceneTree
const Fixture = preload("res://tools/campaign/world_action_fixture.gd")
const Campaign = preload("res://scripts/rpg/campaign.gd")
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
const SaveBase = preload("res://scripts/rpg/save_store.gd")
class FaultStore extends SaveBase:
	var fail_write := false
	func _replace_file(temporary: String, destination: String) -> Error:
		return ERR_FILE_CANT_WRITE if fail_write else super._replace_file(temporary, destination)
var failures: Array[String] = []
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); printerr("ASSERT FAIL: ", message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	var store := FaultStore.new()
	var campaign := Campaign.new(null, store, Chapters.SAVE_PATH)
	check(campaign.new_run(Chapters.DEFAULT_CLASSES,5,{"id":Chapters.PROFILE_ID,"bindings":Chapters.BINDINGS.duplicate(true),"world":Chapters.initial_world(1)}).ok,"create isolated formal run")
	check(campaign.has_method("commit_world_object"),"authoritative world object transaction exists")
	check(ResourceLoader.exists("res://scripts/campaign/world_object_catalog.gd"),"world object catalog exists")
	if campaign.has_method("commit_world_object") and ResourceLoader.exists("res://scripts/campaign/world_object_catalog.gd"): _test_transactions(campaign,store)
	print("WORLD_ACTION_ASSERTIONS:", assertions, " FAILURES:", failures.size())
	quit(0 if failures.is_empty() else 1)
func _test_transactions(campaign: RefCounted, store: RefCounted) -> void:
	var objects: Script = load("res://scripts/campaign/world_object_catalog.gd")
	var definition: Dictionary = objects.get_object("temple_approach_bundle")
	var original: Dictionary = campaign.safe_snapshot()
	check(store.validate(original).is_empty(),"legacy schema2 without world_objects remains valid")
	check(not campaign.commit_world_object(original.world,"unknown").ok,"unknown object rejected")
	check(not campaign.commit_world_object(original.world,"region_2_bundle").ok,"other map pickup rejected")
	var world: Dictionary = original.world.duplicate(true)
	world.position = [61.0,2.89,-5.6]; world.player_x = 61.0
	check(not campaign.commit_world_object(world,"temple_approach_bundle").ok,"remote pickup rejected")
	world.position = definition.position.duplicate(); world.player_x = world.position[0]
	store.fail_write = true
	var failed: Dictionary = campaign.commit_world_object(world,"temple_approach_bundle")
	check(not failed.ok and campaign.safe_snapshot() == original,"failed write rolls back inventory and object state")
	check(store.load_safe(Chapters.SAVE_PATH).snapshot == original,"failed write leaves disk unchanged")
	store.fail_write = false
	var stale := Campaign.new(null,null,Chapters.SAVE_PATH)
	check(stale.load_run().ok,"second instance starts from original durable baseline")
	var result: Dictionary = campaign.commit_world_object(world,"temple_approach_bundle")
	check(result.ok,"registered nearby pickup commits")
	var committed: Dictionary = campaign.safe_snapshot()
	check(committed.inventory[definition.item_id] == original.inventory[definition.item_id] + int(definition.quantity),"pickup adds exact catalog amount")
	check(committed.world_objects.get("temple_approach_bundle",false),"pickup completion durable")
	check(committed.world.event_flags == original.world.event_flags and committed.roster == original.roster and committed.xp == original.xp,"pickup does not rewrite story or party")
	var duplicate: Dictionary = campaign.commit_world_object(world,"temple_approach_bundle")
	check(duplicate.ok and duplicate.already_applied and campaign.safe_snapshot() == committed,"repeated pickup is idempotent")
	check(not stale.commit_world_object(world,"temple_approach_bundle").ok and stale.safe_snapshot() == original,"stale instance cannot duplicate rewards or revert progress")
	var resumed := Campaign.new(null,null,Chapters.SAVE_PATH)
	check(resumed.load_run().ok and resumed.safe_snapshot() == committed,"save reload retains inventory and consumed object")
	check(resumed.commit_world_object(world,"temple_approach_bundle").already_applied,"reload cannot refill pickup")
	var malformed := committed.duplicate(true)
	malformed.world_objects["unknown"] = true
	check(not store.validate(malformed).is_empty(),"unknown persistent object rejected")
	for bad in [false,1,"true",null]:
		malformed = committed.duplicate(true); malformed.world_objects.temple_approach_bundle = bad
		check(not store.validate(malformed).is_empty(),"invalid completed-state type rejected")
	malformed = committed.duplicate(true); malformed.world_objects = []
	check(not store.validate(malformed).is_empty(),"world_objects must be dictionary")
	var door: Dictionary = objects.get_object("temple_mirror_door")
	world = resumed.safe_snapshot().world.duplicate(true); world.position = door.position.duplicate(); world.player_x = world.position[0]
	check(resumed.commit_world_object(world,"temple_mirror_door").ok,"door can be opened at registered position")
	check(resumed.safe_snapshot().inventory == committed.inventory,"door never grants inventory")
	check(resumed.safe_snapshot().world_objects.size() == 2,"door and pickup state coexist")
	for night in range(1,12):
		var targets: Array = objects.for_night(night)
		check(not targets.is_empty(),"every existing map has registered objects %d" % night)
		for target in targets:
			check(objects.belongs_to_night(str(target.id),night),"registered map binding %s" % target.id)
			check(target.kind in ["door","pickup"] and target.radius <= 1.8,"bounded direct interaction %s" % target.id)
	_test_travel(resumed,objects)

func _test_travel(model: RefCounted, objects: Script) -> void:
	var prior: Dictionary=model.safe_snapshot().world_objects.duplicate(true)
	check(Fixture.complete_first(model),"existing five-night transactions still reach both-choice checkpoint and sendoff")
	check(model.safe_snapshot().world_objects==prior,"all five nights and ending preserve one-time object state")
	check(model.continue_saga().ok,"existing continue transaction reaches second chapter")
	check(model.safe_snapshot().world_objects==prior,"first-to-second chapter preserves objects")
	var object: Dictionary=objects.get_object("region_2_bundle")
	var world: Dictionary=model.safe_snapshot().world.duplicate(true)
	world.position=object.position.duplicate(); world.player_x=world.position[0]
	check(model.commit_world_object(world,str(object.id)).ok,"later map pickup uses same durable transaction")
	prior=model.safe_snapshot().world_objects.duplicate(true)
	var Saga: Script=load("res://scripts/campaign/saga_catalog.gd")
	for step in 40:
		var state: Dictionary=model.safe_snapshot()
		if int(state.saga.chapter)!=2: break
		var id:=str(state.saga.active_scene) if not str(state.saga.active_scene).is_empty() else str(state.saga.scene)
		if not model.begin_saga_scene(state.world,id).ok: check(false,"fixture starts " + id); return
		state=model.safe_snapshot()
		var choices: Array=Saga.eligible_choices(Saga.scene(id),state.saga)
		if not choices.is_empty():
			if not model.choose_saga_option(state.world,id,str(choices[0].id)).ok: check(false,"fixture chooses " + id); return
		state=model.safe_snapshot()
		if not str(state.world.story_encounter).is_empty() and not state.saga.battles.has(id):
			var started: Dictionary=model.begin_battle(str(state.world.story_encounter),state.world,Chapters.battle_patch(state.world))
			if not started.ok or not model.apply_result(Fixture.victory(model,started)).ok: check(false,"fixture wins " + id); return
		if not model.complete_saga_scene(model.safe_snapshot().world,id).ok: check(false,"fixture completes " + id); return
	check(model.safe_snapshot().saga.chapter==3,"existing second chapter reaches third through registered story")
	check(model.safe_snapshot().world_objects==prior,"story map transition preserves object state")
	check(model.travel_saga(model.safe_snapshot().world,2).ok,"registered back travel to second chapter remains possible")
	check(model.safe_snapshot().world_objects==prior,"back travel never refills collected objects")
	world=model.safe_snapshot().world.duplicate(true); world.position=object.position.duplicate(); world.player_x=world.position[0]
	var inventory: Dictionary=model.safe_snapshot().inventory.duplicate(true)
	check(model.commit_world_object(world,str(object.id)).already_applied and model.safe_snapshot().inventory==inventory,"revisited pickup cannot reward twice")
	var resumed:=Campaign.new(null,null,Chapters.SAVE_PATH)
	check(resumed.load_run().ok and resumed.safe_snapshot()==model.safe_snapshot(),"later-map objects and history reload without migration loss")
