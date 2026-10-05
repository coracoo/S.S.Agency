# 模型驱动E2E：每次只推进一个安全检查点，由Python重新启动Godot验证续档。
# 不控制GUI，不修改引擎状态，不注入胜利；对白正文沿登记路径读取后才提交根事件。
extends SceneTree

const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Store = preload("res://scripts/rpg/save_store.gd")
const Replay = preload("res://scripts/rpg/replay.gd")
const Enemy = preload("res://scripts/rpg/enemy_policy.gd")
const Policies = preload("res://tools/rpg/strategy_policies.gd")
const EXPECTED_ENEMIES := [["hound", "shield_soldier"], ["hound", "cultist"], ["shield_soldier", "elite_shield_soldier"], ["cultist", "fire_spirit"], ["gatekeeper"]]
const SESSION_METHODS := ["start_new", "resume", "save_world", "commit_event", "begin_encounter", "advance_night", "choose_resolution", "finish_ending", "prepare_assets", "close"]
var _args: Dictionary = {}
var _catalog: RefCounted
var _session: RefCounted
var _result := {"status": "pass", "mode": "", "resolution": "", "action": "", "assertions": [], "failures": [], "blockers": [], "dialogue_visits": [], "battles": [], "before": {}, "after": {}}

func _initialize() -> void:
	_args = _arguments()
	_result.mode = _args.get("mode", "graph")
	_result.resolution = _args.get("resolution", "sendoff")
	var root_path := OS.get_environment("RPG_TEST_ROOT").replace("\\", "/").simplify_path().trim_suffix("/")
	var user_path := OS.get_user_data_dir().replace("\\", "/").simplify_path()
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or root_path.is_empty() or not user_path.begins_with(root_path + "/"):
		_block("禁止运行：实际user://未通过独立预检")
		_finish()
		return
	_result["user_dir"] = user_path
	_catalog = Catalog.new()
	var errors: Array[String] = _catalog.load_all()
	_expect(errors.is_empty(), "RPG完整目录通过现有校验：" + str(errors))
	if not errors.is_empty():
		_finish()
		return
	match _result.mode:
		"graph": _test_graph()
		"new": _start_new()
		"roster": _test_roster()
		"step": _step()
		"repeat": _repeat_from_previous_process()
		_: _block("未登记E2E模式：" + str(_result.mode))
	if _session != null and _session.has_method("close"): _session.call("close")
	_finish()

func _arguments() -> Dictionary:
	var parsed := {}
	var values := OS.get_cmdline_user_args()
	var index := 0
	while index < values.size():
		var key: String = values[index].trim_prefix("--")
		if key == "force-defeat":
			parsed[key] = true
			index += 1
		elif index + 1 < values.size():
			parsed[key] = values[index + 1]
			index += 2
		else:
			index += 1
	return parsed

func _expect(value: bool, message: String) -> void:
	_result.assertions.append({"passed": value, "message": message})
	if not value:
		_result.failures.append(message)
		_result.status = "fail"

func _block(message: String) -> void:
	_result.blockers.append(message)
	if _result.status != "fail": _result.status = "blocked"

func _finish() -> void:
	var path: String = _args.get("evidence-file", "")
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_expect(false, "无法写仓库外E2E证据：" + path)
		else:
			file.store_string(JSON.stringify(_result, "", true, true))
			file.close()
	var summary := {"status": _result.status, "mode": _result.mode, "resolution": _result.resolution, "action": _result.action, "assertions": _result.assertions.size(), "failures": _result.failures, "blockers": _result.blockers}
	print("CAMPAIGN_E2E_RESULT:", JSON.stringify(summary))
	quit(0 if _result.status == "pass" else 2 if _result.status == "blocked" else 1)

func _contract() -> bool:
	_session = Session.new()
	for method in SESSION_METHODS:
		if not _session.has_method(method): _block("ChapterSession缺少共享接口：" + method)
	if not _session.campaign.has_method("set_form"): _block("RpgCampaign缺少正式焰华形态接口set_form")
	return _result.blockers.is_empty()

func _call(method: String, arguments: Array) -> Dictionary:
	var response = _session.callv(method, arguments)
	_expect(response is Dictionary, method + "返回Dictionary")
	if not response is Dictionary: return {"ok": false, "error": "接口返回非Dictionary", "world": {}}
	if not response.get("ok", false):
		_expect(false, method + "失败：" + str(response.get("error", "缺少error")))
	else:
		_expect(response.has("ok") and response.has("error") and response.get("world") is Dictionary, method + "遵循ok/error/world协议")
	return response

func _start_new() -> void:
	_result.action = "start_new"
	if not _contract(): return
	var created := _call("start_new", [false])
	if not created.get("ok", false): return
	var safe: Dictionary = _session.campaign.safe_snapshot()
	_expect(safe.schema_version == 2 and safe.level == 5 and safe.xp == 0, "全新正式schema2与L5/0XP")
	_expect(safe.party == ["p_swordsman", "p_ranger", "p_guard"], "默认队凛音/薄荷/岑照")
	_expect(safe.world == Chapters.initial_world(1), "全新流程只从第一夜开始")
	_expect(not _session.call("advance_night", safe.world).get("ok", false), "未调查不能跨夜")
	_expect(not _session.call("commit_event", safe.world, "battle:cleared").get("ok", false), "不能用场景事件伪造胜利")
	_checkpoint()

func _resume() -> Dictionary:
	if not _contract(): return {}
	var resumed := _call("resume", [])
	if not resumed.get("ok", false): return {}
	var safe: Dictionary = _session.campaign.safe_snapshot()
	_result.before = safe.duplicate(true)
	_expect(safe.schema_version == 2 and safe.campaign_id == Chapters.PROFILE_ID, "新进程只恢复正式档")
	_expect(Chapters.validate_world(safe.world).is_empty(), "续档世界通过正式登记校验")
	_expect(safe.party == ["p_swordsman", "p_ranger", "p_guard"], "五夜均保持默认三人队")
	if safe.pending_battle.is_empty():
		var expected_scene: String = Chapters.ENDING_PATH if safe.story_phase == "complete" else Chapters.scene_path(safe.world.night)
		_expect(resumed.get("next_scene") == expected_scene, "续档恢复正确本夜/结尾场景")
	else:
		_expect(resumed.get("next_scene") == "res://scenes/rpg/battle.tscn", "战前退出恢复唯一RPG战斗场景")
	return safe

func _checkpoint() -> void:
	var safe: Dictionary = _session.campaign.safe_snapshot()
	_result.after = safe.duplicate(true)
	var loaded: Dictionary = Store.new(_catalog).load_safe(Chapters.SAVE_PATH)
	_expect(loaded.get("ok", false), "安全检查点实际落盘且可校验")
	if not loaded.get("ok", false): return
	for field in ["run_id", "schema_version", "night", "scene_id", "story_phase", "xp", "party", "inventory", "world", "world_history", "pending_battle", "applied_battle_ids", "resolution", "case_status", "chapter_complete"]:
		_expect(Replay.canonical(loaded.snapshot.get(field)) == Replay.canonical(safe.get(field)), "落盘与内存一致：" + field)
	for id in safe.roster:
		for field in ["hp", "mp", "identity_id", "form_id", "class_id", "skill_ids", "equipment", "branch", "active_class_id", "unlocked_forms", "dual_form_version"]:
			_expect(Replay.canonical(loaded.snapshot.roster[id].get(field)) == Replay.canonical(safe.roster[id].get(field)), "队伍资源持久：" + id + "/" + field)

func _repeat_from_previous_process() -> void:
	_result.action = "duplicate_restarted"
	var safe := _resume()
	if safe.is_empty(): return
	var path: String = _args.get("replay-result-file", "")
	_expect(not path.is_empty() and FileAccess.file_exists(path), "跨进程重复采用实际上一场战斗证据")
	if path.is_empty() or not FileAccess.file_exists(path): return
	var prior = JSON.parse_string(FileAccess.get_file_as_string(path))
	_expect(prior is Dictionary and prior.get("applied_result") is Dictionary, "上一进程具有实际捕获并已提交的战果")
	if not prior is Dictionary or not prior.get("applied_result") is Dictionary: return
	var result: Dictionary = prior.applied_result
	var verification: Dictionary = Replay.verify(result.replay, _catalog, Enemy.new())
	_expect(verification.get("matches", false), "上一进程落盘真实战斗重放通过")
	var duplicate: Dictionary = _session.router.finish(result)
	_expect(duplicate.get("ok", false) and duplicate.get("already_applied", false), "实际Godot进程重启后识别已提交战果")
	_expect(_session.campaign.safe_snapshot() == safe, "跨进程重复结算不改HP/MP/库存/XP/世界")
	_checkpoint()

func _step() -> void:
	var safe := _resume()
	if safe.is_empty(): return
	var world: Dictionary = safe.world
	var night_id := int(world.night)
	if safe.story_phase == "complete":
		_result.action = "complete"
		_verify_complete(safe)
		_checkpoint()
		return
	if not safe.pending_battle.is_empty():
		_fight(safe, bool(_args.get("force-defeat", false)))
		_checkpoint()
		return
	if safe.story_phase == "ending":
		if str(safe.resolution).is_empty():
			_result.action = "choose_resolution"
			var nodes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Chapters.CASE_PATH)).nodes
			_visit_path(Chapters.CASE_ROOT, nodes, "t3", "ending")
			_call("choose_resolution", [world, _result.resolution])
			var chosen: Dictionary = _session.campaign.safe_snapshot()
			_expect(chosen.resolution == _result.resolution, "分支演出前先保存用户选择")
		else:
			_result.action = "finish_ending"
			_expect(safe.resolution == _result.resolution, "重启保留上一进程的结局选择")
			var nodes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Chapters.CASE_PATH)).nodes
			_visit_path("e_send" if safe.resolution == "sendoff" else "e_seal", nodes, "", "ending")
			_call("finish_ending", [world])
			_verify_complete(_session.campaign.safe_snapshot())
		_checkpoint()
		return
	for event_id in Chapters.events(night_id):
		if world.event_flags.has(event_id) or not str(event_id).begins_with("dialogue:"): continue
		if event_id == "dialogue:hd5" and not world.event_flags.has("battle:cleared"): continue
		var prerequisites: Array = Chapters.events(night_id)[event_id]
		if not prerequisites.all(func(required): return world.event_flags.has(required)): continue
		_result.action = str(event_id)
		var definition := Chapters.night(night_id)
		var nodes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogues.json")).stages[definition.dialogue_stage].nodes
		var root_id := str(event_id).trim_prefix("dialogue:")
		if root_id != definition.intro:
			for target in definition.interactions:
				if str(target.dialogue) == root_id:
					world = _registered_position_checkpoint(world, target.position)
					break
		var previous_failures: int = _result.failures.size()
		_visit_path(root_id, nodes, definition.dialogue_stops.get(root_id, ""), definition.dialogue_stage)
		if _result.failures.size() != previous_failures: return
		_call("commit_event", [world, event_id])
		_expect(_session.campaign.safe_snapshot().world.dlg_fired.has(root_id), "合法路径结束后保存对白根：" + root_id)
		_checkpoint()
		return
	if night_id == 2:
		for ritual in ["ritual:identify", "ritual:place", "ritual:guide"]:
			if world.event_flags.has(ritual): continue
			_result.action = ritual
			if ritual == "ritual:identify":
				_expect(not _session.call("commit_event", world, "ritual:guide").get("ok", false), "不能跳过辨认/安放直接引路")
			_call("commit_event", [world, ritual])
			var partial: Dictionary = _session.campaign.safe_snapshot()
			_expect(partial.world.resolved.has("coffin_sendoff") == (ritual == "ritual:guide"), "仪式仅引路完成才解锁送行调查")
			_expect(partial.story_phase == ("exploration" if ritual == "ritual:guide" else "ritual"), "仪式阶段在每步成功保存后更新")
			_checkpoint()
			return
	if not world.event_flags.has("battle:cleared"):
		_result.action = "begin_battle"
		for target in Chapters.night(night_id).interactions:
			if str(target.kind) == "battle":
				world = _registered_position_checkpoint(world, target.position)
				break
		# 使用正式整备面板同一个公开休息API，不改HP/MP/库存，不新增玩法。
		var rested: Dictionary = _session.campaign.rest()
		_expect(rested.get("ok", false), "正式整备休息成功，不注入资源")
		_expect(_session.campaign.safe_snapshot().inventory == safe.inventory, "公开休息不补道具库存")
		var started := _call("begin_encounter", [_session.campaign.safe_snapshot().world, Chapters.night(night_id).clue_id])
		if started.get("ok", false):
			_expect(started.get("battle_scene") == "res://scenes/rpg/battle.tscn", "调查只进入真实RPG引擎")
			_expect(started.get("xp") == (120 if night_id == 5 else 40), "本夜登记奖励正确")
			var actual: Array = []
			for actor in started.setup.actors.values():
				if actor.side == "enemy": actual.append(actor.class_id)
			_expect(actual == EXPECTED_ENEMIES[night_id - 1], "五夜既有敌人对应登记：" + str(actual))
			_result["started"] = started.duplicate(true)
		_checkpoint()
		return
	_result.action = "advance_night"
	_expect(Chapters.complete(world), "仅本夜全部调查/仪式/胜利完成才开放出口")
	var advanced := _call("advance_night", [world])
	if advanced.get("ok", false):
		var next: Dictionary = _session.campaign.safe_snapshot()
		_expect(next.world.night == mini(night_id + 1, 5), "一次跨夜只推进一夜")
		_expect(next.world_history.has("night_%d" % night_id), "跨夜保存前夜完整快照")
		_expect(next.world.position == world.position and next.world.facing == world.facing, "新进程间夜次推进保留大地图当前位置")
		if night_id < 5:
			_expect(advanced.get("next_scene") == Chapters.scene_path(night_id + 1), "跨夜到登记3D场景")
			_expect(not _session.call("advance_night", world).get("ok", false), "过期/重复出口不能再推进")
		else:
			_expect(next.story_phase == "ending", "第五夜完成进入结案链")
	_checkpoint()

func _registered_position_checkpoint(world: Dictionary, position: Array) -> Dictionary:
	# 模型层使用登记调查位置；这不是键鼠走路或碰撞验证，人工GUI验收另行负责。
	var candidate := world.duplicate(true)
	candidate.position = position.duplicate()
	candidate.player_x = position[0]
	candidate.facing = -1 if int(world.night) % 2 == 0 else 1
	var saved := _call("save_world", [candidate])
	_expect(saved.get("ok", false) and saved.get("world", {}).get("position") == position, "登记调查坐标通过正式save_world安全检查点")
	return saved.get("world", world)

func _battle_run(engine: RefCounted, passive: bool, probe_dual_form: bool = false) -> Dictionary:
	var policy := Policies.new(_catalog)
	var decision_log: Array = []
	var guard := 0
	var form_opportunities := 0
	while guard < 1600:
		guard += 1
		engine.advance(false)
		var state: Dictionary = engine.snapshot()
		if not str(state.outcome).is_empty(): break
		if int(state.round) > 100:
			_expect(false, "100轮安全上限，保持未完成且不发奖励")
			break
		var player: bool = state.actors[state.active_actor_id].side == "player"
		var command: Dictionary
		if probe_dual_form and player and state.active_actor_id == "p_mage" and form_opportunities < 3:
			if form_opportunities == 0:
				_probe_switch(engine, "mage", decision_log)
				_probe_switch(engine, "sword", decision_log)
			elif form_opportunities == 1:
				_expect(state.actors.p_mage.cooldown_until.has("armor_break"), "真实剑技能产生的CD在下次行动仍保留")
				_probe_switch(engine, "mage", decision_log)
				_probe_switch(engine, "sword", decision_log)
				_probe_switch(engine, "mage", decision_log)
			else:
				_expect(state.actors.p_mage.cooldown_until.has("armor_break") and state.actors.p_mage.cooldown_until.has("ice_arrow"), "同actor同时保留两职业真实技能CD")
				_probe_switch(engine, "sword", decision_log)
				_probe_switch(engine, "mage", decision_log)
			state = engine.snapshot()
			command = _form_skill_command(state, "armor_break" if form_opportunities == 0 else "ice_arrow" if form_opportunities == 1 else "firebolt")
			form_opportunities += 1
		elif player and (passive or (probe_dual_form and form_opportunities < 3)):
			command = {"command_id": "e2e_defeat_%d" % state.revision, "expected_revision": int(state.revision), "actor_id": state.active_actor_id, "kind": "defend", "ability_id": "", "target_ids": []}
		elif player:
			command = policy.choose(str(_args.get("policy", "direct_damage")), state, engine)
		else:
			command = Enemy.new().choose_command(state, _catalog)
		if command.is_empty():
			_expect(false, "公开策略没有给出合法指令")
			break
		var preview: Dictionary = engine.preview(command)
		_expect(preview.get("legal", false), "真实引擎预览合法指令：" + str(command.command_id))
		if not preview.get("legal", false): break
		var submitted: Dictionary = engine.submit(command)
		_expect(submitted.get("accepted", false), "真实引擎接受指令：" + str(command.command_id))
		if not submitted.get("accepted", false): break
		if probe_dual_form and player and command.kind == "skill" and command.actor_id == "p_mage":
			_expect(skill_action_consumed(submitted.events, engine.snapshot(), str(command.actor_id)), "当前实际职业技能产生伤害且正常消耗一个行动")
		decision_log.append({"round": state.round, "actor_id": state.active_actor_id, "command": command.duplicate(true), "reason": "真实败北夹具仅防御" if passive and player else policy.last_decision.get("reason", "现有敌人策略") if player else "现有敌人策略"})
	if probe_dual_form: _expect(form_opportunities == 3, "真实战斗完成剑/法四技能切换及双方实际CD回归")
	var final: Dictionary = engine.snapshot()
	var recording: Dictionary = _session.router.capture_replay(engine)
	var verified: Dictionary = Replay.verify(recording, _catalog, Enemy.new())
	_expect(verified.get("matches", false), "战斗逐命令/逐事件重放一致：" + str(verified.get("first_difference", {})))
	var battle := {"passive_fixture": passive, "seed": final.seed, "round": final.round, "outcome": final.outcome, "decisions": decision_log, "replay": recording, "verification": verified, "final": final}
	_result.battles.append(battle)
	return battle

func _form_skill_command(state: Dictionary, ability_id: String) -> Dictionary:
	var target := ""
	var ids: Array = state.actors.keys()
	ids.sort()
	for id in ids:
		if state.actors[id].side == "enemy" and int(state.actors[id].hp) > 0:
			target = id
			break
	return {"command_id": "e2e_dual_skill_%d" % state.revision, "expected_revision": int(state.revision), "actor_id": state.active_actor_id, "kind": "skill", "ability_id": ability_id, "target_ids": [target]}

func _probe_switch(engine: RefCounted, form_id: String, decisions: Array) -> void:
	var before: Dictionary = engine.snapshot()
	var command := {"command_id": "e2e_dual_switch_%d" % before.revision, "expected_revision": int(before.revision), "actor_id": "p_mage", "kind": "switch_form", "ability_id": "", "target_ids": [], "form_id": form_id}
	_expect(engine.preview(command).get("legal", false) and engine.snapshot() == before, "真实战内切职业预览合法且只读")
	var submitted: Dictionary = engine.submit(command)
	_expect(submitted.get("accepted", false), "真实战内职业命令被接受：" + form_id)
	if not submitted.get("accepted", false): return
	var after: Dictionary = engine.snapshot()
	for field in ["phase", "active_actor_id", "slot_token", "queue", "queue_index", "round", "rng_state", "inventory"]:
		_expect(after[field] == before[field], "切职业不刷新行动/队列/RNG：" + field)
	for field in ["actor_id", "identity_id", "class_id", "hp", "mp", "stats", "equipment", "statuses", "shield", "cooldown_until", "slot_count", "opportunity_count", "last_slot_round", "revived_round"]:
		_expect(after.actors.p_mage[field] == before.actors.p_mage[field], "两职业共享实际角色资源：" + field)
	var career := "swordsman" if form_id == "sword" else "mage"
	_expect(after.actors.size() == before.actors.size() and after.actors.p_mage.active_class_id == career and after.actors.p_mage.skill_ids == _catalog.get_definition("classes", career).skill_ids, "切到现有职业真实四技能且不增加actor")
	_expect(submitted.events.any(func(event): return event.type == "form_changed") and not submitted.events.any(func(event): return event.type == "slot_ended"), "切职业仅记form_changed，不额外结束/获得行动")
	decisions.append({"round": before.round, "actor_id": "p_mage", "command": command, "reason": "真实双职业共享资源/CD/行动回归"})

func _fight(safe: Dictionary, passive: bool) -> void:
	_result.action = "defeat_retry" if passive else "win_battle"
	var pending: Dictionary = safe.pending_battle
	var started: Dictionary = _session.campaign.retry_battle()
	_expect(started.get("ok", false), "续档恢复真实战前设置")
	var engine: RefCounted = _session.router.create_engine()
	if engine == null:
		_block("正式router未能创建引擎：" + _session.router.last_error)
		return
	_expect(engine.snapshot().seed == pending.seed, "续档使用持久seed")
	var played := _battle_run(engine, passive)
	_expect(played.outcome == ("defeat" if passive else "victory"), "真实模型终局满足此用例：" + str(played.outcome))
	if played.outcome != ("defeat" if passive else "victory"): return
	var result: Dictionary = _session.router.result_from_engine()
	_expect(result.outcome == played.outcome and result.battle_id == pending.battle_id, "战果由router从实际引擎捕获")
	var finished: Dictionary = _session.router.finish(result)
	_expect(finished.get("ok", false), "真实战果事务提交：" + str(finished.get("error", "")))
	if not finished.get("ok", false): return
	if passive:
		_expect(_session.campaign.safe_snapshot() == safe, "真实败北不保存战内损耗/XP/调查/跨夜")
		_expect(not _session.call("advance_night", safe.world).get("ok", false), "真实败北不能提前解锁下一夜")
		var retried: Dictionary = _session.router.retry()
		_expect(retried.get("ok", false) and retried.battle_id == pending.battle_id and retried.seed == pending.seed and retried.setup == started.setup, "败北重试同战斗ID/seed/战前资源")
		var replayed := _battle_run(_session.router.create_engine(), true)
		_expect(Replay.canonical(replayed.final) == Replay.canonical(played.final), "同seed同合法命令真实败北逐事件完全相同")
		_expect(_session.router.finish(_session.router.result_from_engine()).get("ok", false) and _session.campaign.safe_snapshot() == safe, "第二次败北仍保持安全档")
		return
	var after: Dictionary = _session.campaign.safe_snapshot()
	var night_id := int(safe.world.night)
	_expect(after.xp == (280 if night_id == 5 else night_id * 40) and after.level == 5, "逐夜只提交规定XP，总计280且L5")
	_expect(after.world.event_flags.has("battle:cleared") and after.world.resolved.has(Chapters.night(night_id).clue_id), "真实胜利才提交本夜调查")
	_expect(finished.get("next_scene") == Chapters.scene_path(night_id), "胜利返场当前正式3D夜晚")
	_expect(after.world.position == safe.world.position and after.world.facing == safe.world.facing, "胜利返场保留大地图战前位置与朝向")
	_expect(after.pending_battle.is_empty() and after.applied_battle_ids.size() == night_id, "每夜仅一个已提交battle_id")
	var repeated: Dictionary = _session.router.finish(result)
	_expect(repeated.get("ok", false) and repeated.get("already_applied", false) and _session.campaign.safe_snapshot() == after, "同进程重复战果不能重复XP或推进")
	var fresh: RefCounted = Session.new()
	var restored: Dictionary = fresh.call("resume")
	_expect(restored.get("ok", false), "新会话恢复胜利返场检查点")
	var duplicate: Dictionary = fresh.router.finish(result)
	_expect(duplicate.get("ok", false) and duplicate.get("already_applied", false) and fresh.campaign.safe_snapshot() == after, "新会话重复战果也不重复奖励")
	fresh.call("close")
	_result["applied_result"] = result

func _verify_complete(safe: Dictionary) -> void:
	_expect(safe.story_phase == "complete" and safe.chapter_complete and safe.xp == 280 and safe.applied_battle_ids.size() == 5, "五夜全部真实胜利与本章完成记录")
	_expect(safe.resolution == _result.resolution and safe.case_status == ("closed" if _result.resolution == "sendoff" else "monitoring"), "送行结案/镇守续监含义保留")
	_expect(safe.world_history.size() == 5, "五个世界检查点均保留")
	for id in range(1, 6):
		var key := "night_%d" % id
		_expect(safe.world_history.has(key) and Chapters.complete(safe.world_history.get(key, {})), "前夜完整状态保留：" + key)
	_expect(not _session.call("advance_night", safe.world).get("ok", false), "本章完成后不能再跨夜")

func _visit_path(root_id: String, nodes: Dictionary, stop: String, stage_id: String) -> void:
	var node_id := root_id
	var seen := {}
	while not node_id.is_empty():
		_expect(nodes.has(node_id) and not seen.has(node_id), "对白合法引用且无循环：" + node_id)
		if not nodes.has(node_id) or seen.has(node_id): return
		seen[node_id] = true
		var node: Dictionary = nodes[node_id]
		_expect(not str(node.get("text", "")).is_empty(), "保留对白正文：" + node_id)
		_result.dialogue_visits.append({"stage": stage_id, "root": root_id, "node": node_id, "text_sha256": str(node.text).sha256_text()})
		if node_id == stop: break
		var choices: Array = node.get("choices", [])
		if choices.is_empty(): node_id = str(node.get("next", ""))
		else:
			var index := 0 if _result.resolution == "sendoff" else 1
			_expect(index < choices.size(), "两个保留选项均有实际路径：" + node_id)
			if index >= choices.size(): return
			node_id = str(choices[index].get("next", ""))

func _all_paths(root_id: String, nodes: Dictionary, stop: String, prefix: Array = []) -> Array:
	_expect(nodes.has(root_id) and not prefix.has(root_id), "登记触发引用存在且无循环：" + root_id)
	if not nodes.has(root_id) or prefix.has(root_id): return []
	var path := prefix.duplicate()
	path.append(root_id)
	if root_id == stop: return [path]
	var node: Dictionary = nodes[root_id]
	var targets: Array = []
	if not str(node.get("next", "")).is_empty(): targets.append(str(node.next))
	for choice in node.get("choices", []): targets.append(str(choice.next))
	if targets.is_empty(): return [path]
	var result: Array = []
	for target in targets: result.append_array(_all_paths(target, nodes, stop, path))
	return result

func _test_graph() -> void:
	_result.action = "catalogue_52_paths"
	var dialogue: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogues.json"))
	var reached := {}
	var paths: Array = []
	for id in range(1, 6):
		var definition := Chapters.night(id)
		var roots: Array = [definition.intro]
		for interaction in definition.interactions:
			if not str(interaction.dialogue).is_empty() and not roots.has(interaction.dialogue): roots.append(interaction.dialogue)
		for root_id in roots:
			var available := _all_paths(root_id, dialogue.stages[definition.dialogue_stage].nodes, definition.dialogue_stops.get(root_id, ""))
			for path in available:
				paths.append({"night": id, "stage": definition.dialogue_stage, "root": root_id, "nodes": path})
				for node_id in path: reached[node_id] = true
		_expect(Chapters.validate_world(Chapters.initial_world(id)).is_empty(), "五夜登记有合法3D初始世界%d" % id)
	_expect(reached.size() == 38, "38探索节点均有登记触发路径")
	var endings := {}
	var case_nodes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Chapters.CASE_PATH)).nodes
	for path in _all_paths(Chapters.CASE_ROOT, case_nodes, ""):
		paths.append({"night": 5, "stage": "ending", "root": Chapters.CASE_ROOT, "nodes": path})
		for node_id in path: endings[node_id] = true
	_expect(endings.size() == 14, "14结案节点有合法双分支路径")
	_expect(not paths.filter(func(path): return path.root == "hd1" and path.nodes.has("hd5")).size(), "hd5不会在Boss战前对白中出现")
	_expect(paths.any(func(path): return path.root == "hd5" and path.nodes == ["hd5"]), "hd5具有独立胜利返场触发根")
	_result["paths"] = paths
	_result["exploration_nodes"] = reached.keys()
	_result["ending_nodes"] = endings.keys()

func _test_roster() -> void:
	_result.action = "six_identity_interface_regression"
	if not _contract(): return
	if not _call("start_new", [false]).get("ok", false): return
	var safe: Dictionary = _session.campaign.safe_snapshot()
	_expect(safe.roster.size() == 6, "只有六个身份，不创建第七角色")
	for id in Chapters.BINDINGS:
		var actor: Dictionary = safe.roster.get(id, {})
		_expect(actor.get("identity_id") == Chapters.BINDINGS[id].identity_id and actor.get("form_id") == Chapters.BINDINGS[id].form_id, "六身份规范绑定：" + id)
		_expect(actor.get("skill_ids", []).size() == 4, "六身份原四技能可用：" + id)
	var alternate: Array[String] = ["p_mage", "p_healer", "p_controller"]
	_expect(_session.campaign.set_party(alternate).get("ok", false), "其余三身份均可编队")
	var actor: Dictionary = _session.campaign.safe_snapshot().roster.p_mage
	_expect(actor.form_id == "sword" and actor.active_class_id == "swordsman" and actor.unlocked_forms == ["sword"] and actor.skill_ids == _catalog.get_definition("classes", "swordsman").skill_ids, "新局焰华从真实剑职业与既有四技能开始")
	var locked: Dictionary = _session.campaign.safe_snapshot()
	var locked_disk := FileAccess.get_file_as_string(Chapters.SAVE_PATH)
	_expect(not _session.campaign.set_form("p_mage", "mage").get("ok", false), "首夜剧情胜利前不能使用法职业")
	_expect(_session.campaign.safe_snapshot() == locked and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == locked_disk, "拒绝未解锁形态不改内存或正式档")
	var duplicate: Array[String] = ["p_mage", "p_mage", "p_healer"]
	var incomplete: Array[String] = ["p_mage", "p_healer"]
	_expect(not _session.campaign.set_party(duplicate).get("ok", false) and not _session.campaign.set_party(incomplete).get("ok", false), "拒绝重复或不足三人编队")
	var defaults: Array[String] = ["p_swordsman", "p_ranger", "p_guard"]
	_expect(_session.campaign.set_party(defaults).get("ok", false), "默认三身份均可重新编队")
	# 从合法原剧情根与真实engine首夜胜利获取解锁；不写unlock字段或伪造战果。
	var definition := Chapters.night(1)
	var nodes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogues.json")).stages[definition.dialogue_stage].nodes
	for root_id in ["a1", "r1", "h1"]:
		_visit_path(root_id, nodes, "", definition.dialogue_stage)
		if not _call("commit_event", [_session.campaign.safe_snapshot().world, "dialogue:" + root_id]).get("ok", false): return
	if not _call("begin_encounter", [_session.campaign.safe_snapshot().world, definition.clue_id]).get("ok", false): return
	_fight(_session.campaign.safe_snapshot(), false)
	if not _result.failures.is_empty(): return
	# _fight的重复交付回归激活了新会话；后续修改必须显式从持久档恢复。
	_session = Session.new()
	if not _call("resume", []).get("ok", false): return
	var unlocked: Dictionary = _session.campaign.safe_snapshot()
	_expect(unlocked.xp == 40 and unlocked.world.event_flags.has("battle:cleared") and unlocked.roster.p_mage.unlocked_forms == ["sword", "mage"], "真实首夜胜利解锁同actor法职业并持久保存")
	_expect(_session.campaign.set_party(alternate).get("ok", false), "解锁后焰华与另外两身份仍可合法编队")
	var shared: Dictionary = _session.campaign.safe_snapshot().roster.p_mage
	for form_id in ["mage", "sword", "mage"]:
		_expect(_session.campaign.set_form("p_mage", form_id).get("ok", false), "解锁后战外真实职业切换：" + form_id)
		var changed: Dictionary = _session.campaign.safe_snapshot().roster.p_mage
		var career: String = "swordsman" if form_id == "sword" else "mage"
		_expect(changed.form_id == form_id and changed.active_class_id == career and changed.skill_ids == _catalog.get_definition("classes", career).skill_ids, "战外切换实际职业四技能：" + career)
		for field in ["actor_id", "identity_id", "class_id", "hp", "mp", "stats", "equipment", "statuses", "shield", "cooldown_until", "slot_count", "opportunity_count"]:
			_expect(changed[field] == shared[field], "战外两职业共享资源且不刷新：" + field)
		_checkpoint()
	_session = Session.new()
	if not _call("resume", []).get("ok", false): return
	var persisted: Dictionary = _session.campaign.safe_snapshot().roster.p_mage
	_expect(persisted.form_id == "mage" and persisted.active_class_id == "mage" and persisted.skill_ids == _catalog.get_definition("classes", "mage").skill_ids and persisted.unlocked_forms == ["sword", "mage"], "新会话持久读回解锁/当前职业/实际四技能")
	# 第二夜正常调查进战；用真实技能生成CD后切换，证明不是空CD的外观检查。
	if not _call("advance_night", [_session.campaign.safe_snapshot().world]).get("ok", false): return
	definition = Chapters.night(2)
	nodes = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogues.json")).stages[definition.dialogue_stage].nodes
	_visit_path("c1", nodes, "", definition.dialogue_stage)
	if not _call("commit_event", [_session.campaign.safe_snapshot().world, "dialogue:c1"]).get("ok", false): return
	_expect(_session.campaign.rest().get("ok", false) and _session.campaign.set_form("p_mage", "sword").get("ok", false), "通过正式整备进入第二夜双职业实际战斗")
	if not _call("begin_encounter", [_session.campaign.safe_snapshot().world, definition.clue_id]).get("ok", false): return
	var engine: RefCounted = _session.router.create_engine()
	if engine == null:
		_block("双职业真实第二夜引擎未建立")
		return
	var battle := _battle_run(engine, false, true)
	_expect(battle.outcome == "victory", "双职业回归第二夜仍由合法动作产生真实胜利")
	if battle.outcome != "victory": return
	var result: Dictionary = _session.router.result_from_engine()
	_expect(_session.router.finish(result).get("ok", false), "双职业真实战斗结果正常保存")
	var final_actor: Dictionary = _session.campaign.safe_snapshot().roster.p_mage
	_expect(final_actor.form_id == battle.final.actors.p_mage.form_id and final_actor.skill_ids == battle.final.actors.p_mage.skill_ids and final_actor.hp == battle.final.actors.p_mage.hp and final_actor.mp == battle.final.actors.p_mage.mp, "真实战内当前职业/技能/共享HPMP随战果持久保存")
	_session = Session.new()
	if not _call("resume", []).get("ok", false): return
	_expect(_session.campaign.safe_snapshot().roster.p_mage == final_actor, "新会话完整读回真实双职业战后角色")
	_checkpoint()

# 将行动末击与普通行动共用同一检查，避免终局击杀被误判为没有消耗行动。
static func skill_action_consumed(events: Array, after: Dictionary, actor_id: String) -> bool:
	var damaged := events.any(func(event): return event.type == "damage" and event.actor_id == actor_id)
	var ended: Array = events.filter(func(event): return event.type == "slot_ended" and event.actor_id == actor_id and not event.payload.get("skipped", true))
	var victory_events: Array = events.filter(func(event): return event.type == "outcome" and event.payload.get("outcome") == "victory")
	var ordinary: bool = after.phase == "action_end" and str(after.get("outcome", "")).is_empty()
	var final_blow: bool = after.phase == "outcome" and after.get("outcome") == "victory" and victory_events.size() == 1
	return damaged and ended.size() == 1 and (ordinary or final_blow)
