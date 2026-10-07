# Actual rendered environmental interaction capture; launched by the isolated graphical runner.
extends SceneTree
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Fixture = preload("res://tools/campaign/world_action_fixture.gd")
var _directory := ""
var _failures: Array[String] = []
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_directory=OS.get_environment("ACT_ONE_OUTPUT")
	if _directory.is_empty(): quit(2); return
	_run.call_deferred()
func _capture(name_value: String) -> void:
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	var result:=root.get_texture().get_image().save_png(_directory.path_join(name_value + ".png"))
	if result!=OK: _failures.append("capture failed " + name_value)
	else: print("WORLD_OBJECT_CAPTURE:",name_value)
func _run() -> void:
	root.size=Vector2i(1920,1080)
	var session:=Session.new()
	if not session.start_new(false).ok: _finish("cannot initialize isolated campaign"); return
	var prepared: Dictionary=await session.prepare_assets()
	if not prepared.ok: _finish(str(prepared.error)); return
	session.commit_event(session.campaign.safe_snapshot().world,"dialogue:a1")
	var stage: Node3D=load("res://scripts/campaign/chapter_stage.gd").new(); root.add_child(stage)
	while not stage.ready_for_play and stage.last_error.is_empty(): await process_frame
	if not stage.ready_for_play: _finish(stage.last_error); return
	stage.player.position=Vector3(35.9,2.9,-12.3); stage.player.velocity=Vector3.ZERO
	stage.camera_rig.follow(stage.player,20)
	stage._tutorial_remaining=0
	await _capture("01-temple-door-closed")
	stage._confirm_armed=true
	if not stage.request_interaction("temple_mirror_door"): _failures.append("temple door interaction rejected")
	for frame in 100: await physics_frame
	await _capture("02-temple-door-open")
	stage.player.position=Vector3(-5.4,.04,1.1); stage.player.velocity=Vector3.ZERO; stage.camera_rig.follow(stage.player,20)
	await _capture("03-approach-pickup-present")
	stage._confirm_armed=true
	if not stage.request_interaction("temple_approach_bundle"): _failures.append("temple pickup interaction rejected")
	for frame in 100: await physics_frame
	await _capture("04-approach-pickup-collected")
	stage.shutdown(); stage.free()
	if not Fixture.complete_first(session.campaign) or not session.campaign.continue_saga().ok: _finish("cannot prepare later-map transaction fixture"); return
	stage=load("res://scripts/campaign/saga_stage.gd").new(); root.add_child(stage)
	while not stage.ready_for_play and stage.last_error.is_empty(): await process_frame
	if not stage.ready_for_play: _finish(stage.last_error); return
	stage.player.position=Vector3(2,.03,-6.25); stage.player.velocity=Vector3.ZERO; stage.camera_rig.follow(stage.player,20)
	stage._tutorial_remaining=0
	await _capture("05-lamp-shop-door-closed")
	stage._confirm_armed=true
	if not stage.request_interaction("region_2_door"): _failures.append("later-map door interaction rejected")
	for frame in 100: await physics_frame
	await _capture("06-lamp-shop-door-open")
	stage.player.position=Vector3(-8.65,.03,6.25); stage.player.velocity=Vector3.ZERO; stage.camera_rig.follow(stage.player,20)
	await _capture("07-drying-yard-pickup-present")
	stage._confirm_armed=true
	if not stage.request_interaction("region_2_bundle"): _failures.append("later-map pickup interaction rejected")
	for frame in 100: await physics_frame
	await _capture("08-drying-yard-pickup-collected")
	stage.shutdown(); stage.free(); session.close()
	_finish()
func _finish(error: String = "") -> void:
	if not error.is_empty(): _failures.append(error)
	for failure in _failures: printerr("FAIL: ",failure)
	print("WORLD_OBJECT_GRAPHICAL_FAILURES:",_failures.size())
	quit(0 if _failures.is_empty() else 1)
