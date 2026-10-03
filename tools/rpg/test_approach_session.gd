extends RefCounted
const F = preload("res://tools/rpg/fixtures.gd")
const A = preload("res://tools/rpg/approach_fixtures.gd")
const Store = preload("res://scripts/rpg/save_store.gd")
const Campaign = preload("res://scripts/rpg/campaign.gd")
const Router = preload("res://scripts/rpg/encounter_router.gd")
static func run() -> Array[String]:
	var failures: Array[String] = []
	for file in ["trial_profile", "approach_session"]:
		F.expect(FileAccess.file_exists("res://scripts/exploration_3d/%s.gd" % file), "缺少试玩接口：" + file, failures)
	if not failures.is_empty(): return failures
	var Profile = load("res://scripts/exploration_3d/trial_profile.gd")
	var Session = load("res://scripts/exploration_3d/approach_session.gd")
	var sentinels := {Store.DEFAULT_PATH: "existing-rpg-slot", "user://progress.json": "existing-card-progress"}
	DirAccess.make_dir_recursive_absolute("user://rpg_v1")
	for sentinel_path in sentinels:
		var sentinel := FileAccess.open(sentinel_path, FileAccess.WRITE)
		sentinel.store_string(sentinels[sentinel_path])
		sentinel.close()
	var profile: Dictionary = Profile.make(A.world())
	F.expect(Profile.validate(profile).is_empty(), "固定试玩身份配置合法", failures)
	var bad := profile.duplicate(true)
	bad.bindings.p_swordsman.identity_id = "homura"
	F.expect(not Profile.validate(bad).is_empty(), "拒绝替换试用人物", failures)
	var fault := A.FailingStore.new()
	var path := "user://rpg_v1/tests/approach_session.json"
	var session = Session.new(fault, path)
	fault.fail = true
	F.expect(not session.start_new(false).ok and session.campaign.safe_snapshot().is_empty() and Session.current == null, "新局写失败不激活空会话", failures)
	fault.fail = false
	F.expect(session.start_new(false).ok and Session.current == session and Router.session == session.router, "新局成功一次激活", failures)
	var safe: Dictionary = session.campaign.safe_snapshot()
	F.expect(safe.party == ["p_swordsman", "p_ranger", "p_guard"] and safe.phase == "exploration" and safe.level == 5, "L5 固定三人探索初态", failures)
	F.expect(safe.roster.p_swordsman.identity_id == "rinne" and safe.roster.p_ranger.form_id == "mint" and safe.roster.p_guard.identity_id == "guard", "人物形态与职业分离", failures)
	F.expect(safe.inventory == {"healing_potion": 3, "mana_potion": 1, "revival_potion": 1, "cleansing_powder": 1}, "不赠送额外道具", failures)
	var before := FileAccess.get_file_as_string(path)
	F.expect(not session.start_new(false).ok and FileAccess.get_file_as_string(path) == before, "未确认不覆盖有效档", failures)
	var campaign: RefCounted = session.campaign
	var world: Dictionary = safe.world.duplicate(true)
	F.expect(not campaign.commit_world_event(world, "basin_observed").ok, "观察不可跳过入场", failures)
	F.expect(not campaign.commit_world_event(world, "basin_cleared").ok, "不能伪造胜利", failures)
	F.expect(not campaign.commit_world_event(world, "approach_complete").ok, "没有胜利不能完成", failures)
	fault.fail = true
	F.expect(not campaign.commit_world_event(world, "approach_entered").ok and campaign.safe_snapshot() == safe and FileAccess.get_file_as_string(path) == before, "对白提交失败内存磁盘均不前进", failures)
	fault.fail = false
	for event in ["approach_entered", "basin_observed", "basin_inspected"]:
		world = campaign.safe_snapshot().world
		F.expect(campaign.commit_world_event(world, event).ok, "顺序提交事件：" + event, failures)
		world = campaign.safe_snapshot().world
		F.expect(campaign.commit_world_event(world, event).ok, "事件幂等：" + event, failures)
	world = campaign.safe_snapshot().world
	var forged := world.duplicate(true)
	forged.event_flags.clear()
	forged.dlg_fired.clear()
	F.expect(not session.save_world(forged).ok, "普通保存不能回滚剧情", failures)
	world.position = [0.1, 0.2, 1.5]
	world.player_x = 0.1
	F.expect(session.save_world(world).ok, "普通保存允许空间更新", failures)
	var resumed = Session.new(null, path)
	F.expect(resumed.resume().ok and resumed.campaign.safe_snapshot().world.position == world.position, "恢复完整位置", failures)
	F.expect(resumed.campaign.safe_snapshot().roster.p_guard.identity_id == "guard", "保存读取保留身份", failures)
	F.expect(resumed.start_new(true).ok, "同一会话确认新开成功", failures)
	F.expect(Router.take_world("res://scenes/exploration_3d/approach.tscn").is_empty() and resumed.router.engine == null and resumed.router._setup.is_empty(), "新开不沿用上一局路由缓存", failures)
	session.close()
	F.expect(Session.current == resumed and Router.session == resumed.router, "旧会话迟到关闭不能清除新会话", failures)
	resumed.close()
	F.expect(Session.current == null and Router.session == null, "退出试玩释放会话", failures)
	var broken_path := "user://rpg_v1/tests/approach_broken.json"
	var file := FileAccess.open(broken_path, FileAccess.WRITE)
	file.store_string("{future-or-broken")
	file.close()
	var broken = Session.new(null, broken_path)
	F.expect(not broken.start_new(true).ok and not broken.resume().ok and FileAccess.get_file_as_string(broken_path) == "{future-or-broken", "损坏档即使确认新开也保留", failures)
	var tampered: Dictionary = campaign.safe_snapshot()
	tampered.roster.p_guard.identity_id = "homura"
	F.expect(not Store.new().validate(tampered).is_empty(), "存档校验拒绝身份篡改", failures)
	_test_identity_persistence(Profile, failures)
	for sentinel_path in sentinels:
		F.expect(FileAccess.get_file_as_string(sentinel_path) == sentinels[sentinel_path], "试玩不改变旧槽：" + sentinel_path, failures)
	return failures

static func _test_identity_persistence(Profile, failures: Array[String]) -> void:
	# 仅测试目录加入后续登记的同数值遭遇，生产目录由任务6接线。
	var catalog = A.catalog()
	var encounter: Dictionary = catalog.get_definition("encounters", "slice_1")
	encounter.id = "approach_basin"
	encounter.next_id = ""
	encounter.erase("scene_routes")
	catalog._definitions.encounters[encounter.id] = encounter
	var store := Store.new(catalog)
	var path := "user://rpg_v1/tests/approach_identity.json"
	var campaign := Campaign.new(catalog, store, path)
	F.expect(campaign.new_run(Profile.CLASS_IDS, 5, Profile.make(A.world())).ok, "身份兼容夹具", failures)
	for event in ["approach_entered", "basin_observed", "basin_inspected"]:
		F.expect(campaign.commit_world_event(campaign.safe_snapshot().world, event).ok, "身份测试推进对白", failures)
	var safe := campaign.safe_snapshot()
	safe.xp = 480
	F.expect(store.write_safe(safe, path) == OK and campaign.load_run().ok, "升级阈值夹具合法", failures)
	var patch := {"patch_version": 2, "encounter_id": "approach_basin", "event_flags": {"basin_cleared": true}, "resolved": {"basin_reflection": true}}
	var started := campaign.begin_battle("approach_basin", safe.world, patch)
	F.expect(started.ok, "身份带入战斗", failures)
	if not started.ok: return
	var fallen: Array[Dictionary] = []
	for id in safe.party:
		var actor: Dictionary = started.setup.actors[id].duplicate(true)
		actor.hp = 0
		fallen.append(actor)
	var defeat := {"battle_id": started.battle_id, "outcome": "defeat", "roster": fallen, "inventory": started.setup.inventory.duplicate(true), "xp": 0, "story_patch": {}, "replay": {}}
	F.expect(campaign.apply_result(defeat).ok, "败北不写安全资源", failures)
	var retry := campaign.retry_battle()
	F.expect(retry.ok and retry.battle_id == started.battle_id and retry.seed == started.seed and retry.setup == started.setup, "重试完整保留三人身份和资源", failures)
	# 增长和装备钳制在兼容记录上原位更新，不重建身份。
	var candidate := campaign.safe_snapshot()
	campaign._add_xp(candidate, 40)
	candidate.pending_battle = {}
	candidate.phase = "rest"
	F.expect(store.write_safe(candidate, path) == OK and campaign.load_run().ok, "升级后的身份完整存读", failures)
	F.expect(campaign.equip("p_guard", "armor", "").ok, "装备钳制可运行", failures)
	var after := campaign.safe_snapshot()
	F.expect(after.level == 6 and after.xp == 20 and after.roster.p_guard.identity_id == "guard" and after.roster.p_swordsman.form_id == "rinne" and after.roster.p_ranger.form_id == "mint", "升级装备不覆盖身份", failures)
