# 七章扩展必须从真实隔离存档事务进入，不能把测试夹具当作完整通关证据。
extends SceneTree
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Campaign = preload("res://scripts/rpg/campaign.gd")
const Store = preload("res://scripts/rpg/save_store.gd")
var failures: Array[String] = []
var assertions := 0
func expect(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(1); return
	var model := Campaign.new(null, null, Chapters.SAVE_PATH)
	expect(model.has_method("leave_saga_battle"), "后六章败北整备事务存在")
	expect(model.has_method("continue_saga"), "第一章结案必须提供后六章继续事务")
	expect(ResourceLoader.exists("res://scripts/campaign/saga_catalog.gd"), "七章场次登记存在")
	if model.has_method("continue_saga"):
		if OS.get_environment("SAGA_REAL_BATTLES") != "1": _run_state_checks(model)
		for ending_id in (([OS.get_environment("SAGA_ENDING")] if not OS.get_environment("SAGA_ENDING").is_empty() else ["dawn", "vigil", "shatter", "eternal"]) if OS.get_environment("SAGA_SMOKE_ONLY") != "1" else []):
			_story_route(OS.get_environment("SAGA_RESOLUTION") if not OS.get_environment("SAGA_RESOLUTION").is_empty() else "sendoff", ending_id, OS.get_environment("SAGA_CLINIC_PLAN") if not OS.get_environment("SAGA_CLINIC_PLAN").is_empty() else "gentle")
		if OS.get_environment("SAGA_SMOKE_ONLY") != "1" and OS.get_environment("SAGA_ENDING").is_empty():
			_story_route("seal_monitoring", "dawn", "isolate")
			_story_route("seal_monitoring", "dawn", "isolate", true)
	print("SAGA_STATE_ASSERTIONS: ", assertions)
	for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
func _victory(model: RefCounted, started: Dictionary) -> Dictionary:
	if OS.get_environment("SAGA_REAL_BATTLES") == "1":
		var strategy = load("res://tools/campaign/saga_battle_strategy.gd")
		var router: RefCounted = Session.current.router
		var engine: RefCounted = router.create_engine()
		var commands := 0
		while engine != null and engine.snapshot().outcome.is_empty() and commands < 220:
			engine.advance()
			var state: Dictionary = engine.snapshot()
			if state.outcome.is_empty() and state.phase == "action_selection":
				var command: Dictionary = strategy.choose(state, engine, model._catalog)
				if command.is_empty(): break
				var submitted: Dictionary = engine.submit(command)
				if not submitted.get("accepted", false): break
				commands += 1
		var result: Dictionary = router.result_from_engine()
		expect(result.get("outcome") == "victory", "真实指令战斗胜利：" + str(started.encounter_id))
		print("SAGA_REAL_BATTLE: ", started.encounter_id, " commands=", commands, " outcome=", result.get("outcome", "stalled"))
		if not OS.get_environment("ACT_ONE_OUTPUT").is_empty():
			var path := OS.get_environment("ACT_ONE_OUTPUT").path_join(str(started.encounter_id) + "-replay.json")
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file != null: file.store_string(JSON.stringify(result, "  ")); file.close()
		return result
	var roster: Array[Dictionary] = []
	for id in model.safe_snapshot().party: roster.append(started.setup.actors[id].duplicate(true))
	return {"battle_id": started.battle_id, "outcome": "victory", "roster": roster, "inventory": started.setup.inventory.duplicate(true), "xp": started.xp, "story_patch": started.story_patch.duplicate(true), "replay": {}}
func _finish_first(session: RefCounted, resolution: String) -> bool:
	for id in range(1, 6):
		for event in Chapters.events(id):
			if event == "dialogue:hd5": continue
			if not session.commit_event(session.campaign.safe_snapshot().world, event).ok: return false
		if OS.get_environment("SAGA_REAL_BATTLES") == "1": session.campaign.rest()
		var started: Dictionary = session.begin_encounter(session.campaign.safe_snapshot().world, Chapters.night(id).clue_id)
		if not started.ok: return false
		if not session.router.finish(_victory(session.campaign, started)).ok: return false
		if id == 5 and not session.commit_event(session.campaign.safe_snapshot().world, "dialogue:hd5").ok: return false
		if not session.advance_night(session.campaign.safe_snapshot().world).ok: return false
	return session.choose_resolution(session.campaign.safe_snapshot().world, resolution).ok and session.finish_ending(session.campaign.safe_snapshot().world).ok
func _run_state_checks(model: RefCounted) -> void:
	var session := Session.new(model)
	expect(session.start_new(false).ok, "可新建正式局")
	expect(not model.call("continue_saga").ok, "未结首章不能直接跳到第二章")
	expect(_finish_first(session, "sendoff"), "真实五夜状态事务到送行结案")
	var first: Dictionary = model.safe_snapshot()
	var result: Dictionary = model.call("continue_saga")
	expect(result.ok, "送行旧档能进入第二章")
	if not result.ok: printerr(result); return
	var state: Dictionary = model.safe_snapshot()
	expect(state.saga.chapter == 2 and state.saga.scene == "C2-01", "第二章从批准开场开始")
	expect(state.resolution == "sendoff" and state.case_status == "closed", "首章已送行事实不会被清除")
	expect(state.saga.flags.first_chapter_sendoff == true, "后章明确保存亡者已离开分支")
	expect(state.applied_battle_ids == first.applied_battle_ids and state.roster == first.roster, "下山不重复奖励或恢复角色资源")
	expect(state.world.night == 6 and state.world.scene_path == "res://scenes/campaign/saga.tscn", "后续世界有独立正式场景路由")
	expect(Store.new().validate(state).is_empty(), "扩展正式档通过严格校验")
	expect(not model.call("continue_saga").ok, "重复下山不能重置进度")
	var resumed := Session.new()
	expect(resumed.resume().ok and resumed.campaign.safe_snapshot() == state, "后六章检查点可重启恢复")
	var malformed := state.duplicate(true)
	malformed.saga.version = 99
	expect(not Store.new().validate(malformed).is_empty(), "未知扩展版本拒绝")
	malformed = state.duplicate(true)
	malformed.saga.flags.first_chapter_sendoff = false
	expect(not Store.new().validate(malformed).is_empty(), "送行事实不可翻转")
	malformed = state.duplicate(true)
	malformed.saga.scene = "C7-01"
	expect(not Store.new().validate(malformed).is_empty(), "章节与当前场次不符拒绝")
	malformed = state.duplicate(true)
	malformed.saga.completed.append("C7-99")
	expect(not Store.new().validate(malformed).is_empty(), "未知完成场次拒绝")
	malformed = state.duplicate(true)
	malformed.saga.scene = "C2-16"; malformed.saga.cursors["2"] = "C2-16"
	expect(not Store.new().validate(malformed).is_empty(), "未完成前置不能伪造章末游标")
	malformed = state.duplicate(true)
	malformed.saga.active_scene = "C2-S02"; malformed.world.story_scene = "C2-S02"; malformed.world.story_encounter = "saga_c2_s02"
	malformed.world_history.night_6 = malformed.world.duplicate(true)
	expect(not Store.new().validate(malformed).is_empty(), "未开放支线不能伪造活动场次")
	malformed = state.duplicate(true)
	malformed.world.event_flags["battle:C2-03"] = true; malformed.world.resolved["C2-03"] = true
	malformed.world_history.night_6 = malformed.world.duplicate(true)
	expect(not Store.new().validate(malformed).is_empty(), "地图战果标记必须有同一真实胜利来源")

	malformed = state.duplicate(true)
	malformed.saga.events.append({"id":"C3-01", "choice":""}); malformed.saga.completed.append("C3-01")
	expect(not Store.new().validate(malformed).is_empty(), "未开放章节的无前置开场也不能伪造完成")

func _story_route(resolution: String, ending_id: String, clinic_plan: String, defer_seal: bool = false) -> void:
	defer_seal = defer_seal or OS.get_environment("SAGA_DEFER_SEAL") == "1"
	var model := Campaign.new(null, null, Chapters.SAVE_PATH)
	var session := Session.new(model)
	var party: Array[String] = []
	party.assign(["guard", "mage", "healer"] if OS.get_environment("SAGA_REAL_BATTLES") == "1" else Chapters.DEFAULT_CLASSES)
	expect(session.start_new(true, party).ok, "分支隔离新局：" + resolution + ending_id)
	if not _finish_first(session, resolution): failures.append("分支首章完成失败"); return
	if not model.continue_saga().ok: failures.append("分支下山失败"); return
	if OS.get_environment("SAGA_REAL_BATTLES") == "1": model.set_form("p_mage", "mage")
	var Saga = load("res://scripts/campaign/saga_catalog.gd")
	var choices := {"C2-S01": "a", "C3-S01": "a", "C4-S01": "a", "C5-S01": "a", "C3-06": "b", "C5-08": "a" if clinic_plan == "gentle" else "b", "C6-04": "b" if defer_seal else "a", "C6-R03": "temple_seal", "C6-05": "a", "C6-S01": "a", "C6-S03": "a", "C6-S04": "a", "C6-14": "a", "C7-01": "a", "C7-09": {"dawn": "a", "vigil": "b", "shatter": "c", "eternal": "d"}[ending_id]}
	var optional := {"C2-05": "C2-S01", "C3-06": "C3-S01", "C4-02": "C4-S01", "C5-02": "C5-S01"}
	var steps := 0
	var captured_chapters := {}
	var retry_tested := false
	while model.safe_snapshot().story_phase != "complete" and steps < 220:
		steps += 1
		var state: Dictionary = model.safe_snapshot()
		var saga: Dictionary = state.saga
		if not captured_chapters.has(saga.chapter):
			captured_chapters[saga.chapter] = true
			_save_resume_snapshot(model, "chapter_%d" % int(saga.chapter))
		var id: String = saga.active_scene if not saga.active_scene.is_empty() else saga.scene
		if saga.active_scene.is_empty() and optional.has(id) and not saga.completed.has(optional[id]): id = optional[id]
		if saga.active_scene.is_empty() and saga.scene == "C6-13":
			if defer_seal and not saga.flags.responsibility_resolved: id = "C6-R03"
			elif not saga.flags.clinic_awake: id = "C6-S01" if not saga.completed.has("C6-S01") else "C6-S02"
			elif not saga.flags.evacuation_route_ready: id = "C6-S03"
			elif not saga.flags.alley_rescued: id = "C6-S04"
		if id.is_empty(): failures.append("主线游标意外空：" + str(saga)); return
		if id == "C5-09":
			var skipped := state.duplicate(true)
			skipped.saga.scene = "C5-10"; skipped.saga.cursors["5"] = "C5-10"
			expect(not Store.new().validate(skipped).is_empty(), "稳灯分支不能伪造游标跳过药库战斗")
		var begin: Dictionary = model.begin_saga_scene(state.world, id)
		if not begin.ok: failures.append("开始" + id + "：" + begin.error); return
		state = model.safe_snapshot()
		var entry: Dictionary = Saga.scene(id)
		var options: Array = Saga.eligible_choices(entry, state.saga)
		if not options.is_empty():
			var selected: String = choices.get(id, str(options[0].id))
			var picked: Dictionary = model.choose_saga_option(state.world, id, selected)
			if not picked.ok: failures.append("选择" + id + "/" + selected + "：" + picked.error); return
		state = model.safe_snapshot()
		if id == "C7-09": _save_resume_snapshot(model, "confirmed_final_choice")
		if not state.world.story_encounter.is_empty() and not state.saga.battles.has(id):
			var premature: Dictionary = model.complete_saga_scene(state.world, id)
			expect(not premature.ok, "战前不能发放战后状态：" + id)
			if OS.get_environment("SAGA_REAL_BATTLES") == "1": model.rest()
			var started: Dictionary = session.begin_encounter(model.safe_snapshot().world, id)
			if not started.ok: failures.append("进战" + id + "：" + started.error + " 校验=" + model._store.last_error); return
			var before: Dictionary = model.safe_snapshot()
			if id.begins_with("C7-"): _save_resume_snapshot(model, "pending_" + id)
			if id == "C7-05" and ending_id == "vigil" and not retry_tested and OS.get_environment("SAGA_REAL_BATTLES") != "1":
				var lost := _victory(model, started)
				lost.outcome = "defeat"; lost.xp = 0; lost.story_patch = {}
				for actor in lost.roster: actor.hp = 0
				expect(session.router.finish(lost).ok, "终战败北仍保留战前安全档")
				expect(model.has_method("leave_saga_battle"), "终战败北可回真实整备并触发R04")
				if model.has_method("leave_saga_battle"):
					var left: Dictionary = model.call("leave_saga_battle")
					if not left.ok: failures.append("终战离战：" + left.error + " " + model._store.last_error); return
					expect(model.safe_snapshot().saga.active_scene == "C7-R04", "重试对白入口真实可达")
					expect(model.safe_snapshot().roster == before.roster and model.safe_snapshot().inventory == before.inventory, "败北整备恢复原战前资源且不送药")
					choices["C7-R04"] = "a"
					retry_tested = true
					continue
				else: session.router.retry()
			var result := _victory(model, started)
			var finished: Dictionary = session.router.finish(result)
			if not finished.ok:
				failures.append("结算" + id + "：" + finished.error + " 校验=" + model._store.last_error)
				return
			var won: Dictionary = model.safe_snapshot()
			expect(session.router.finish(result).ok and model.safe_snapshot() == won, "后章奖励重复提交幂等：" + id)
			expect(won.world.position == before.world.position and won.world.facing == before.world.facing, "后章战斗回到原位置：" + id)
		var completion: Dictionary = model.complete_saga_scene(model.safe_snapshot().world, id)
		if id == "C6-04" and defer_seal: choices["C6-04"] = "a"
		if not completion.ok:
			failures.append("完成" + id + "：" + completion.error + " 校验=" + model._store.last_error)
			return
		var resumed := Campaign.new(null, null, Chapters.SAVE_PATH)
		expect(resumed.load_run().ok and resumed.safe_snapshot() == model.safe_snapshot(), "每场检查点完整重读：" + id)
	var final: Dictionary = model.safe_snapshot()
	expect(final.story_phase == "complete" and final.saga.ending == ending_id, "完整事务路线到正确尾声：" + resolution + "/" + clinic_plan + "/" + ending_id)
	expect(final.saga.completed.has({"dawn":"C7-15", "vigil":"C7-17", "shatter":"C7-19", "eternal":"C7-22"}[ending_id]), "六人尾声全部播完才完成：" + ending_id)
	expect(final.saga.flags.letter_posted and final.saga.flags.responsibility_resolved, "书信和首章责任持续到终章")
	expect(final.saga.flags.night_market_rescued and final.saga.flags.family_rescued and final.saga.flags.qiuan_rescued, "已执行救援状态持续到终章")
	if resolution == "sendoff": expect(not final.saga.completed.has("C6-04") and not final.saga.completed.has("C6-05") and not final.saga.completed.has("C6-06"), "已离开小夜不会在第六章复生")
	print("SAGA_ROUTE: ", resolution, "/", clinic_plan, "/", ending_id, " scenes=", final.saga.completed.size(), " battles=", final.saga.battles.size(), " level=", final.level, " steps=", steps)
	session.close()

func _save_resume_snapshot(model: RefCounted, name: String) -> void:
	if OS.get_environment("SAGA_REAL_BATTLES") != "1" or OS.get_environment("ACT_ONE_OUTPUT").is_empty(): return
	var directory := OS.get_environment("ACT_ONE_OUTPUT").path_join("checkpoints")
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join(name + ".json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(model.safe_snapshot(), "  ")); file.close()
