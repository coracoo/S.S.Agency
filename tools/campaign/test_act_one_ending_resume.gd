# 完整故事事务到结案点，验证结束/已选分支的中断恢复不受入口距离限制。
extends SceneTree
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
const Session = preload("res://scripts/campaign/chapter_session.gd")
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func must(result: Dictionary, label: String) -> void:
	if not result.get("ok",false): printerr("PROBE_SETUP_FAIL ",label," ",result); quit(2)
func _run() -> void:
	var session := Session.new(); must(session.start_new(false),"new")
	for night in range(1,6):
		for event in Catalog.events(night):
			if event == "dialogue:hd5": continue
			must(session.commit_event(session.campaign.safe_snapshot().world,event),event)
		var started: Dictionary = session.begin_encounter(session.campaign.safe_snapshot().world,Catalog.night(night).clue_id); must(started,"battle")
		var roster: Array[Dictionary] = []
		for id in session.campaign.safe_snapshot().party: roster.append(started.setup.actors[id].duplicate(true))
		must(session.router.finish({"battle_id":started.battle_id,"outcome":"victory","roster":roster,"inventory":started.setup.inventory.duplicate(true),"xp":started.xp,"story_patch":started.story_patch.duplicate(true),"replay":{}}),"finish")
		if night == 5: must(session.commit_event(session.campaign.safe_snapshot().world,"dialogue:hd5"),"hd5")
		var world: Dictionary = session.campaign.safe_snapshot().world
		world.position = Catalog.night(night).anchors.exit.duplicate(); world.player_x = world.position[0]
		must(session.advance_night(world),"advance")
	var base: Dictionary = session.campaign.safe_snapshot()
	session.close()
	var failures := 0
	var checks := 0
	for resolution in ["", "sendoff", "seal_monitoring"]:
		var store = load("res://scripts/rpg/save_store.gd").new()
		if store.write_safe(base, Catalog.SAVE_PATH) != OK: quit(2); return
		var resumed := Session.new()
		var loaded: Dictionary = resumed.resume(); must(loaded,"resume")
		if not resolution.is_empty(): must(resumed.choose_resolution(resumed.campaign.safe_snapshot().world,resolution),"choose")
		must(await resumed.prepare_assets(),"assets")
		var disk_before := FileAccess.get_file_as_string(Catalog.SAVE_PATH)
		var stage: Node3D = load(loaded.next_scene).instantiate(); root.add_child(stage)
		for frame in 8: await physics_frame
		var expected: String = "t1" if resolution.is_empty() else ("e_send" if resolution == "sendoff" else "e_seal")
		checks += 1
		if stage._mode != "ending" or stage._dialogue == null or stage._dialogue._playing_id != expected:
			failures += 1; printerr("ASSERT FAIL:本殿结案点继续必须恢复结案分支:",expected,"，实际模式:",stage._mode)
		checks += 1
		if stage.controls_enabled or not stage.last_error.is_empty(): failures += 1; printerr("ASSERT FAIL:结案恢复必须锁行动且不要求再次提交出口")
		checks += 1
		if FileAccess.get_file_as_string(Catalog.SAVE_PATH) != disk_before: failures += 1; printerr("ASSERT FAIL:恢复结案显示不应二次提交模型")
		stage.free(); resumed.close()
	print("ACT_ONE_ENDING_RESUME:",checks," assertions, ",failures," failures")
	quit(0 if failures == 0 else 1)
