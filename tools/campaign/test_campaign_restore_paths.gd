# 五夜跨区域存读、真实战斗失败/重试与舞台返场回归。
# 位置采用登记锚点夹具；场景树和战斗指令是真实实现，不代表人工GUI行走通关。
extends SceneTree

const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Enemy = preload("res://scripts/rpg/enemy_policy.gd")
const Policies = preload("res://tools/rpg/strategy_policies.gd")
const Replay = preload("res://scripts/rpg/replay.gd")
const OTHER_REGION_NIGHTS := [4, 1, 5, 2, 3]
var failures: Array[String] = []
var assertions := 0
var catalog: RefCounted

func _initialize() -> void:
	var test_root := OS.get_environment("RPG_TEST_ROOT").replace("\\", "/").simplify_path().trim_suffix("/")
	var user_dir := OS.get_user_data_dir().replace("\\", "/").simplify_path()
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or test_root.is_empty() or not user_dir.begins_with(test_root + "/"):
		printerr("FAIL: 必须由隔离runner验证实际user目录后运行")
		quit(2)
		return
	_run.call_deferred()

func check(value: bool, message: String) -> bool:
	assertions += 1
	if not value:
		failures.append(message)
		printerr("ASSERT FAIL: ", message)
	return value

func _frames(count: int = 5) -> void:
	for frame in count: await physics_frame

func _silence(stage: Node3D) -> void:
	stage._generation += 1
	if is_instance_valid(stage._dialogue):
		stage._dialogue.abort()
		stage._dialogue.queue_free()
	stage._dialogue = null
	stage._arrival_checked = true
	stage._resume_explore()

func _stage(session: RefCounted, night: int) -> Node3D:
	var prepared: Dictionary = await session.prepare_assets()
	if not check(prepared.ok, "第%d夜真实人物资源准备" % night): return null
	var stage: Node3D = load(Chapters.scene_path(night)).instantiate()
	root.add_child(stage)
	await _frames()
	if not check(stage.ready_for_play and stage.last_error.is_empty(), "第%d夜舞台实际就绪" % night):
		stage.free()
		return null
	_silence(stage)
	return stage

func _battle(session: RefCounted, passive: bool) -> Dictionary:
	var engine: RefCounted = session.router.create_engine()
	if not check(engine != null, "由存档router创建真实战斗引擎"): return {}
	var policy := Policies.new(catalog)
	for turn in 1600:
		engine.advance(false)
		var state: Dictionary = engine.snapshot()
		if not str(state.outcome).is_empty(): break
		if not check(int(state.round) <= 100, "战斗安全上限不能作为完成"): return {}
		var player: bool = state.actors[state.active_actor_id].side == "player"
		var command: Dictionary
		if player and passive:
			command = {"command_id": "restore_defeat_%d" % state.revision, "expected_revision": int(state.revision), "actor_id": state.active_actor_id, "kind": "defend", "ability_id": "", "target_ids": []}
		elif player:
			command = policy.choose("direct_damage", state, engine)
		else:
			command = Enemy.new().choose_command(state, catalog)
		if not check(not command.is_empty() and engine.preview(command).get("legal", false), "测试只提交引擎预览合法指令"): return {}
		if not check(engine.submit(command).get("accepted", false), "真实战斗引擎接受指令"): return {}
	var result: Dictionary = session.router.result_from_engine()
	if not check(not result.is_empty() and result.outcome == ("defeat" if passive else "victory"), "真实战斗达到预期终局，未注入战果"): return {}
	check(Replay.verify(result.replay, catalog, Enemy.new()).get("matches", false), "真实战斗逐命令重放一致")
	return result

func _run() -> void:
	catalog = Catalog.new()
	if not check(catalog.load_all().is_empty(), "RPG目录加载合法"): _finish(); return
	var session := Session.new()
	if not check(session.start_new(false).ok, "隔离正式新游戏"): _finish(); return
	for night in range(1, 6):
		var stage: Node3D = await _stage(session, night)
		if stage == null: session.close(); _finish(); return
		# 仅提交已登记的测试前置事件，不把battle:cleared伪造成调查。
		for event in Chapters.events(night):
			if event == "dialogue:hd5": continue
			var committed: Dictionary = session.commit_event(stage.export_world(), event)
			if not check(committed.ok, "第%d夜登记前置：%s" % [night, event]): stage.free(); session.close(); _finish(); return
			stage.apply_committed_world(committed.world)
		var candidate: Dictionary = stage.export_world()
		candidate.position = Chapters.night(OTHER_REGION_NIGHTS[night - 1]).anchors.spawn.duplicate()
		candidate.facing = -1 if night % 2 == 0 else 1
		var restored: Dictionary = stage.restore_world(candidate)
		check(restored.ok and not restored.used_fallback, "第%d夜可在另一区域安全落脚" % night)
		await _frames()
		var saved: Dictionary = session.save_world(stage.export_world())
		if not check(saved.ok, "第%d夜跨区位置合法写入正式隔离档" % night): stage.free(); session.close(); _finish(); return
		var checkpoint: Dictionary = session.campaign.safe_snapshot()
		var saved_position := Vector3(saved.world.position[0], saved.world.position[1], saved.world.position[2])
		stage.free()
		session.close()
		session = Session.new()
		var resumed: Dictionary = session.resume()
		check(resumed.ok and resumed.next_scene == Chapters.scene_path(night), "第%d夜跨区存档回到本夜薄入口" % night)
		check(session.campaign.safe_snapshot() == checkpoint, "第%d夜重新建立会话逐字段恢复持久快照" % night)
		stage = await _stage(session, night)
		if stage == null: session.close(); _finish(); return
		check(stage.player.position.distance_to(saved_position) < 0.12 and stage.player.facing == saved.world.facing, "第%d夜新舞台恢复异区实际位置和朝向" % night)
		check(session.campaign.safe_snapshot() == checkpoint, "第%d夜呈现恢复不改存档或剧情" % night)
		check(session.campaign.rest().ok, "通过正式公开休息API准备战斗")
		var started: Dictionary = session.begin_encounter(stage.export_world(), Chapters.night(night).clue_id)
		if not check(started.ok, "第%d夜异区位置经正式遭遇事务存为战前位置" % night): stage.free(); session.close(); _finish(); return
		var pending: Dictionary = session.campaign.safe_snapshot()
		var disk_before := FileAccess.get_file_as_string(Chapters.SAVE_PATH)
		stage.free()
		session.close()
		session = Session.new()
		resumed = session.resume()
		check(resumed.ok and resumed.next_scene == "res://scenes/rpg/battle.tscn", "第%d夜战前退出继续回到RPG" % night)
		check(session.campaign.safe_snapshot() == pending and session.router._setup.seed == started.seed, "第%d夜战前重载保留全部资源/区域/种子" % night)
		var lost := _battle(session, true)
		if lost.is_empty(): session.close(); _finish(); return
		check(session.router.finish(lost).ok, "第%d夜真实失败结果正常受理" % night)
		check(session.campaign.safe_snapshot() == pending and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == disk_before, "第%d夜失败不消耗持久资源、不写新位置或奖励" % night)
		session.close()
		session = Session.new()
		check(session.resume().ok, "第%d夜失败后关闭再继续" % night)
		check(session.router._setup.seed == started.seed and session.router._setup.battle_id == started.battle_id and session.campaign.safe_snapshot() == pending, "第%d夜重启后仍为同场同种子的安全重试" % night)
		var won := _battle(session, false)
		if won.is_empty(): session.close(); _finish(); return
		var returned: Dictionary = session.router.finish(won)
		check(returned.ok and returned.next_scene == Chapters.scene_path(night), "第%d夜实际胜利返回本夜登记场景" % night)
		check(returned.world.position == pending.world.position and returned.world.facing == pending.world.facing, "第%d夜胜利事务原样保留异区战前坐标/朝向" % night)
		var awarded: Dictionary = session.campaign.safe_snapshot()
		var award_bytes := FileAccess.get_file_as_string(Chapters.SAVE_PATH)
		stage = await _stage(session, night)
		if stage == null: session.close(); _finish(); return
		var battle_position := Vector3(pending.world.position[0], pending.world.position[1], pending.world.position[2])
		check(stage.player.position.distance_to(battle_position) < 0.12 and stage.player.facing == pending.world.facing, "第%d夜胜利后新舞台恢复异区真实位置" % night)
		check(session.router.finish(won).get("already_applied", false), "第%d夜重复结算识别已发奖" % night)
		check(session.campaign.safe_snapshot() == awarded and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == award_bytes, "第%d夜新舞台与重复战果不二次发奖/改档" % night)
		stage.free()
		session.close()
		session = Session.new()
		check(session.resume().ok and session.router.finish(won).get("already_applied", false), "第%d夜再次续档仍识别重复战果" % night)
		check(session.campaign.safe_snapshot() == awarded and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == award_bytes, "第%d夜第二会话不重复发奖" % night)
		if night == 5: check(session.commit_event(awarded.world, "dialogue:hd5").ok, "Boss返场后才提交守门人结案对白")
		var before_advance: Dictionary = session.campaign.safe_snapshot().world
		check(session.advance_night(before_advance).ok, "第%d夜正式跨夜事务" % night)
		var after_advance: Dictionary = session.campaign.safe_snapshot().world
		check(after_advance.position == before_advance.position and after_advance.facing == before_advance.facing, "第%d夜推进不传送玩家" % night)
		print("CAMPAIGN_RESTORE_NIGHT_OK:", night)
	check(session.campaign.safe_snapshot().xp == 280 and session.campaign.safe_snapshot().story_phase == "ending", "五夜只累计登记280XP并到结案检查点")
	session.close()
	_finish()

func _finish() -> void:
	print("CAMPAIGN_RESTORE_PATHS:", assertions, " assertions, ", failures.size(), " failures; model_scene_integration, manual_gui_not_run")
	quit(0 if failures.is_empty() else 1)
