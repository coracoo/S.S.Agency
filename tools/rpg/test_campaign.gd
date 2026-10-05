# 存档测试仅由隔离runner运行；永不读取或删除真实玩家档。
extends RefCounted

const F = preload("res://tools/rpg/fixtures.gd")
const State = preload("res://scripts/rpg/battle_state.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Battle = preload("res://scripts/rpg/battle_engine.gd")
const Policy = preload("res://scripts/rpg/enemy_policy.gd")
const Replay = preload("res://scripts/rpg/replay.gd")
const SaveBase = preload("res://scripts/rpg/save_store.gd")
const Factory = preload("res://scripts/rpg/actor_factory.gd")

class RenameFailStore extends SaveBase:
	func _replace_file(_temporary: String, _destination: String) -> Error:
		return ERR_FILE_CANT_WRITE

class CorruptWriteStore extends SaveBase:
	func _write_temporary(path: String, _contents: String) -> Error:
		return super._write_temporary(path, "{broken")

class FailingStore extends RefCounted:
	var fail := false
	var delegate = null
	func write_safe(value: Dictionary, path: String) -> Error:
		return ERR_FILE_CANT_WRITE if fail else delegate.write_safe(value, path)
	func load_safe(path: String) -> Dictionary:
		return delegate.load_safe(path)

static func run() -> Array[String]:
	F.assertion_count = 0
	var failures: Array[String] = []
	var invalid := F.state(F.actor("guard", "p_guard"))
	invalid.inventory["unknown_item"] = 1
	F.expect(not State.validate(invalid).is_empty(), "库存未知道具必须被目录校验拒绝（M1）", failures)
	for name in ["campaign", "save_store", "encounter_router"]:
		F.expect(FileAccess.file_exists("res://scripts/rpg/%s.gd" % name), "尚未实现：" + name, failures)
	if failures.size() > 1: return failures
	var Campaign = load("res://scripts/rpg/campaign.gd")
	var Store = load("res://scripts/rpg/save_store.gd")
	var Router = load("res://scripts/rpg/encounter_router.gd")
	_test_resources(Campaign, Store, failures)
	_test_retry_and_atomicity(Campaign, Store, failures)
	_test_store(Campaign, Store, failures)
	_test_growth_and_setup(Campaign, Store, failures)
	_test_router(Campaign, Store, Router, failures)
	_test_write_failures(Campaign, Store, failures)
	_test_result_validation(Campaign, Store, failures)
	_test_gear_loot(Campaign, Store, failures)
	_test_stage_adapter(failures)
	_test_schema_types(Campaign, Store, failures)
	_test_branches_and_rest(Campaign, Store, failures)
	_test_story_failure(Campaign, Store, Router, failures)
	_test_real_battle(Campaign, Store, Router, failures)
	_test_nested_types(Campaign, Store, failures)
	_test_pending_resume(Campaign, Store, Router, failures)
	_test_stage_failure(Campaign, Store, Router, failures)
	_test_exit_commit(Campaign, Store, Router, failures)
	_test_stale_commits(Campaign, Store, failures)
	await _test_stage_ready(Campaign, Store, Router, failures)
	await _test_ritual_flow(Campaign, Store, Router, failures)
	await _test_ritual_boundaries(Campaign, Store, Router, failures)
	print("RPG campaign 断言：", F.assertion_count)
	return failures

static func _world() -> Dictionary:
	return {"scene_path": "res://scenes/v3/stage.tscn", "player_x": 735.5, "facing": -1, "resolved": {}, "dlg_fired": {"200": true}, "exit_prompted": false, "spirit": 2, "party_index": 1}

static func _new(Campaign, Store, tag: String, failures: Array[String], level: int = 5):
	var campaign = Campaign.new(null, Store.new(), "user://rpg_v1/tests/%s.json" % tag)
	var created: Dictionary = campaign.new_run(_ids(["guard", "swordsman", "healer"]), level)
	F.expect(created.get("ok", false), "新建完整队伍：" + str(created), failures)
	return campaign

static func _victory(campaign, start: Dictionary) -> Dictionary:
	var roster: Array[Dictionary] = []
	for id in campaign.safe_snapshot().party:
		roster.append(start.setup.actors[id].duplicate(true))
	return {"battle_id": start.battle_id, "outcome": "victory", "roster": roster, "inventory": start.setup.inventory.duplicate(true), "xp": start.xp, "story_patch": start.story_patch.duplicate(true), "replay": {}}

static func _test_resources(Campaign, Store, failures: Array[String]) -> void:
	var campaign = _new(Campaign, Store, "resources", failures)
	var original: Dictionary = campaign.snapshot()
	F.expect(original.roster.size() == 6 and original.party == ["p_guard", "p_swordsman", "p_healer"], "六人完整名单与三人出战分离", failures)
	var started: Dictionary = campaign.begin_battle("slice_1", _world())
	F.expect(started.ok and started.setup.actors.size() == 5, "三人加双敌人，不把替补送入战斗", failures)
	var result := _victory(campaign, started)
	result.roster[0].hp = 110
	result.roster[0].mp = 7
	result.roster[1].hp = 0
	result.roster[1].mp = 13
	result.roster[2].statuses = [F.status("weaken", 0.2, 2, "e_test")]
	result.roster[2].shield = F.shield(25, 2, "p_healer")
	result.roster[2].cooldown_until = {"heal": 2}
	result.inventory.healing_potion = 2
	F.expect(campaign.apply_result(result).ok, "第一场胜利提交", failures)
	var next: Dictionary = campaign.begin_battle("slice_2", _world())
	F.expect(next.setup.actors.p_guard.hp == 110 and next.setup.actors.p_guard.mp == 7 and next.setup.actors.p_swordsman.hp == 0 and next.setup.actors.p_swordsman.mp == 13, "跨战HP/MP/倒地不变", failures)
	F.expect(next.setup.inventory.healing_potion == 2, "跨战物品保留", failures)
	var healer: Dictionary = next.setup.actors.p_healer
	F.expect(healer.statuses.is_empty() and healer.shield.is_empty() and healer.cooldown_until.is_empty(), "状态盾冷却战后清空", failures)
	F.expect(campaign.apply_result(_victory(campaign, next)).ok, "第二场胜利", failures)
	var before_items: Dictionary = campaign.snapshot()
	F.expect(campaign.use_item_outside("healing_potion", "p_guard").ok, "战外治疗药合法", failures)
	F.expect(campaign.snapshot().roster.p_guard.hp == 190 and campaign.snapshot().inventory.healing_potion == 1, "治疗药80且只扣一瓶", failures)
	F.expect(campaign.use_item_outside("mana_potion", "p_guard").ok, "战外魔力药合法", failures)
	F.expect(campaign.snapshot().roster.p_guard.mp == 27, "魔力药20", failures)
	F.expect(not campaign.use_item_outside("healing_potion", "p_swordsman").ok, "治疗不能复活", failures)
	F.expect(campaign.use_item_outside("revival_potion", "p_swordsman").ok, "复苏药合法", failures)
	F.expect(campaign.snapshot().roster.p_swordsman.hp == 72 and campaign.snapshot().roster.p_swordsman.mp == 13, "复苏30%并保留MP", failures)
	F.expect(not campaign.use_item_outside("cleansing_powder", "p_guard").ok, "无负面净化不能白扣", failures)
	F.expect(campaign.snapshot().roster.p_ranger == before_items.roster.p_ranger, "替补从未被三人战果覆盖", failures)
	var inventory: Dictionary = campaign.snapshot().inventory.duplicate(true)
	F.expect(campaign.rest().ok, "休息点可休息", failures)
	for actor in campaign.snapshot().roster.values():
		F.expect(actor.hp == actor.stats.hp and actor.mp == actor.stats.mp, "休息回复六人", failures)
	F.expect(campaign.snapshot().inventory == inventory, "休息绝不补药", failures)
	var boss: Dictionary = campaign.begin_battle("slice_boss", _world())
	F.expect(campaign.apply_result(_victory(campaign, boss)).ok, "Boss胜利", failures)
	F.expect(campaign.snapshot().level == 5 and campaign.snapshot().xp == 200, "40+40+120只有200XP且仍5级", failures)
	F.expect(not campaign.rest().ok, "非休息点不能凭空全回复", failures)

static func _test_retry_and_atomicity(Campaign, Store, failures: Array[String]) -> void:
	var failing := FailingStore.new()
	failing.delegate = Store.new()
	var path := "user://rpg_v1/tests/atomic.json"
	var campaign = Campaign.new(null, failing, path)
	F.expect(campaign.new_run(_ids(["guard", "swordsman", "healer"])).ok, "原子测试新队伍", failures)
	var started: Dictionary = campaign.begin_battle("slice_1", _world())
	var before: Dictionary = campaign.snapshot()
	var old_text := FileAccess.get_file_as_string(path)
	var victory := _victory(campaign, started)
	victory.roster[0].hp -= 80
	victory.inventory.healing_potion -= 1
	failing.fail = true
	var failed: Dictionary = campaign.apply_result(victory)
	F.expect(not failed.ok and campaign.snapshot() == before, "写失败经验/资源/世界不部分提交", failures)
	F.expect(FileAccess.get_file_as_string(path) == old_text, "写失败原安全档逐字节不变", failures)
	F.expect(not campaign.rest().ok and not campaign.set_party(_ids(["p_mage", "p_healer", "p_controller"])).ok and not campaign.equip("p_guard", "armor", "").ok and not campaign.use_item_outside("healing_potion", "p_guard").ok, "战中休息换人换装用药全拒绝", failures)
	failing.fail = false
	F.expect(campaign.apply_result(victory).ok, "失败写档可用同战果重试", failures)
	var after: Dictionary = campaign.snapshot()
	for index in range(2):
		var duplicate: Dictionary = campaign.apply_result(victory)
		F.expect(duplicate.ok and duplicate.already_applied and duplicate.story_patch.is_empty() and campaign.snapshot() == after, "重复交付不重复经验或剧情", failures)
	var reloaded = Campaign.new(null, Store.new(), path)
	F.expect(reloaded.load_run().ok and reloaded.apply_result(victory).already_applied, "重启后仍幂等", failures)
	var second: Dictionary = campaign.begin_battle("slice_2", _world())
	var saved: Dictionary = campaign.safe_snapshot()
	var defeat := _victory(campaign, second)
	defeat.outcome = "defeat"
	defeat.xp = 0
	defeat.story_patch = {}
	for actor in defeat.roster: actor.hp = 0
	defeat.inventory.healing_potion = 0
	F.expect(campaign.apply_result(defeat).ok, "败北仅记录运行态", failures)
	F.expect(campaign.safe_snapshot() == saved and FileAccess.get_file_as_string(path) == JSON.stringify(saved, "", true, true), "败北不覆盖战前安全档", failures)
	var retry: Dictionary = campaign.retry_battle()
	F.expect(retry.ok and retry.setup == second.setup and retry.seed == second.seed and retry.battle_id == second.battle_id and retry.world == second.world, "重试完整回滚六人、三人设置、世界、种子、物资", failures)
	var retry_again: Dictionary = campaign.retry_battle()
	F.expect(retry_again.setup == retry.setup, "重复重试不赠药、不降难度", failures)
	var title = Campaign.new(null, Store.new(), path)
	F.expect(title.load_run().ok and title.safe_snapshot() == saved, "返回标题只读最后安全档", failures)

static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

static func _test_store(Campaign, Store, failures: Array[String]) -> void:
	var campaign = _new(Campaign, Store, "store_base", failures)
	var store = Store.new()
	var snapshot: Dictionary = campaign.snapshot()
	var path := "user://rpg_v1/tests/store.json"
	F.expect(store.write_safe(snapshot, path) == OK, "安全快照写档", failures)
	var sentinel := "legacy progress sentinel 不得改动"
	_write("user://progress.json", sentinel)
	for mode in ["battle", "cutscene", "action_resolution"]:
		var invalid: Dictionary = snapshot.duplicate(true)
		invalid.phase = mode
		F.expect(store.write_safe(invalid, path) != OK, "战中/过场不允许存档：" + mode, failures)
	for invalid_text in ["{broken", JSON.stringify({"schema_version": 2}), JSON.stringify({"schema_version": 0}), JSON.stringify({"schema_version": "1"})]:
		_write(path, invalid_text)
		F.expect(not store.load_safe(path).ok, "未知版本/损坏显式报错", failures)
		F.expect(store.write_safe(snapshot, path) != OK and FileAccess.get_file_as_string(path) == invalid_text, "不覆盖未来/损坏旧文件", failures)
	path = "user://rpg_v1/tests/extensions.json"
	var extended: Dictionary = snapshot.duplicate(true)
	extended.world = _world()
	extended["future_extension"] = {"enabled": true, "fraction": 1.25}
	extended.roster.p_guard["cosmetic_extension"] = {"hat": "red"}
	extended.world["custom_marker"] = "kept"
	F.expect(store.write_safe(extended, path) == OK, "同schema扩展可保存", failures)
	var loaded: Dictionary = store.load_safe(path)
	F.expect(loaded.ok and loaded.snapshot.future_extension == extended.future_extension and loaded.snapshot.roster.p_guard.cosmetic_extension == extended.roster.p_guard.cosmetic_extension and loaded.snapshot.world.custom_marker == "kept", "扩展字段往返保留", failures)
	var adopted = Campaign.new(null, store, path)
	F.expect(adopted.load_run().ok and adopted.equip("p_guard", "armor", "").ok, "已加载扩展继续编辑", failures)
	F.expect(store.load_safe(path).snapshot.future_extension == extended.future_extension and store.load_safe(path).snapshot.roster.p_guard.cosmetic_extension.hat == "red", "后续写档保留同schema未知字段", failures)
	var original_text := FileAccess.get_file_as_string(path)
	for mutation in ["fractional_hp", "unknown_item", "wrong_stats", "missing_member", "duplicate_party", "wrong_level", "bad_world", "wrong_rule", "wrong_branch", "bad_equipment"]:
		var invalid: Dictionary = snapshot.duplicate(true)
		match mutation:
			"fractional_hp": invalid.roster.p_guard.hp = 1.5
			"unknown_item": invalid.inventory["not_catalogued"] = 1
			"wrong_stats": invalid.roster.p_guard.stats.hp += 1
			"missing_member": invalid.roster.erase("p_ranger")
			"duplicate_party": invalid.party = ["p_guard", "p_guard", "p_healer"]
			"wrong_level": invalid.roster.p_mage.level = 6
			"bad_world": invalid.world = {"scene_path": "bad"}
			"wrong_rule": invalid.rules_version = "future"
			"wrong_branch": invalid.roster.p_guard.branch = {"id": "unknown"}
			"bad_equipment": invalid.roster.p_guard.equipment.armor = "standard_weapon"
		F.expect(store.write_safe(invalid, path) != OK and FileAccess.get_file_as_string(path) == original_text, "扩展不得绕过必需字段校验：" + mutation, failures)
	F.expect(store.write_safe(snapshot, "user://progress.json") != OK and store.write_safe(snapshot, "user://rpg_v1/../progress.json") != OK and store.write_safe(snapshot, "user://rpg_v10/save.json") != OK, "限制所有路径到rpg_v1目录", failures)
	F.expect(FileAccess.get_file_as_string("user://progress.json") == sentinel, "旧progress哨兵内容不变", failures)
	var blocked := "user://rpg_v1/tests/blocked.json"
	DirAccess.make_dir_recursive_absolute(blocked)
	F.expect(store.write_safe(snapshot, blocked) != OK, "目标不可写必须失败不删目录", failures)
	F.expect(DirAccess.dir_exists_absolute(blocked), "失败保留目标", failures)

static func _test_growth_and_setup(Campaign, Store, failures: Array[String]) -> void:
	var campaign = _new(Campaign, Store, "growth", failures, 1)
	for index in range(3):
		var started: Dictionary = campaign.begin_battle("slice_1", _world())
		var victory := _victory(campaign, started)
		victory.roster[0].hp = 10
		victory.roster[0].mp = 2
		F.expect(campaign.apply_result(victory).ok, "升级测试战果", failures)
	F.expect(campaign.snapshot().level == 2 and campaign.snapshot().xp == 20, "L1阈值100，余经验20", failures)
	for actor in campaign.snapshot().roster.values(): F.expect(actor.level == 2, "六人共享等级", failures)
	F.expect(campaign.snapshot().roster.p_guard.hp == 10 and campaign.snapshot().roster.p_guard.mp == 2, "升级只加上限不补HP/MP", failures)
	var capped = _new(Campaign, Store, "capped", failures, 10)
	var start: Dictionary = capped.begin_battle("slice_boss", _world())
	F.expect(capped.apply_result(_victory(capped, start)).ok and capped.snapshot().xp == 0 and capped.snapshot().level == 10, "十级停止累计XP", failures)
	var setup = _new(Campaign, Store, "setup", failures)
	F.expect(setup.set_party(_ids(["p_ranger", "p_mage", "p_controller"])).ok, "准备期六选三", failures)
	F.expect(not setup.set_party(_ids(["p_guard", "p_guard", "p_healer"])).ok and not setup.set_party(_ids(["p_guard"])).ok, "拒绝重复/不足三人", failures)
	F.expect(setup.equip("p_guard", "armor", "").ok and setup.snapshot().roster.p_guard.hp == 300, "脱甲降低上限钳制HP", failures)
	F.expect(setup.equip("p_guard", "armor", "standard_armor").ok and setup.snapshot().roster.p_guard.hp == 300 and setup.snapshot().roster.p_guard.stats.hp == 320, "换装上限提高不补血", failures)
	F.expect(not setup.equip("p_guard", "armor", "standard_weapon").ok and not setup.set_branch("p_guard", "not_a_branch").ok, "装备槽错配/非法分支拒绝", failures)
	var bad = Campaign.new(null, Store.new(), "user://rpg_v1/tests/invalid_new.json")
	F.expect(not bad.new_run(_ids(["guard", "guard", "healer"])).ok and not bad.new_run(_ids(["guard", "mage", "healer"]), 11).ok, "非法新局不给半成品", failures)

static func _test_router(Campaign, Store, Router, failures: Array[String]) -> void:
	var campaign = _new(Campaign, Store, "router", failures)
	Router.clear_session()
	var router = Router.new(campaign)
	F.expect(not Router.enabled(), "默认不影响旧入口", failures)
	Router.activate(router)
	F.expect(Router.enabled() and Router.session == router, "明确静态session启用", failures)
	F.expect(not router.supports("res://scenes/v3/stage_corridor.tscn", "res://scenes/v3/ritual.tscn", "coffin_sendoff"), "仪式不是RPG战斗，不篡改谜题", failures)
	var started: Dictionary = router.begin("res://scenes/v3/stage.tscn", "res://scenes/v3/battle.tscn", _world(), "basin_reflection")
	F.expect(started.ok and started.encounter_id == "slice_1", "现有参道线索映射首战", failures)
	F.expect(not campaign.safe_snapshot().world.resolved.has("basin_reflection"), "进战前线索绝不提前解决", failures)
	var engine = router.create_engine()
	F.expect(not engine.snapshot().actors.e_01_hound.intent.is_empty(), "策略在start前挂载，初始意图可见", failures)
	var initial: Dictionary = engine.snapshot()
	var record: Dictionary = router.capture_replay(engine)
	var catalog := Catalog.new()
	catalog.load_all()
	F.expect(record.events.is_empty() and record.initial.event_sequence == initial.event_sequence and Replay.verify(record, catalog, Policy.new()).matches, "重放不重复收集start初始意图", failures)
	var result := _victory(campaign, started)
	var done: Dictionary = router.finish(result)
	F.expect(done.ok and done.world.resolved.get("basin_reflection", false) and done.next_scene == "res://scenes/v3/stage.tscn", "原子胜利后才公开线索并回原舞台", failures)
	F.expect(router.finish(result).already_applied, "路由重复交付不重复剧情", failures)
	var restored: Dictionary = Router.take_world("res://scenes/v3/stage.tscn")
	F.expect(restored.resolved.get("basin_reflection", false) and restored.player_x == 735.5 and Router.take_world("res://scenes/v3/stage.tscn").is_empty(), "世界恢复一次且保留探索位置", failures)
	Router.clear_session()
	F.expect(not Router.enabled(), "退出可完全关闭新模式", failures)

static func _ids(values: Array) -> Array[String]:
	var result: Array[String] = []
	result.assign(values)
	return result

static func _test_write_failures(Campaign, Store, failures: Array[String]) -> void:
	var campaign = _new(Campaign, Store, "fault_base", failures)
	var snapshot: Dictionary = campaign.snapshot()
	var path := "user://rpg_v1/tests/fault_target.json"
	var store = Store.new()
	F.expect(store.write_safe(snapshot, path) == OK, "故障注入旧档存在", failures)
	var original := FileAccess.get_file_as_string(path)
	snapshot.world = _world()
	for faulty in [RenameFailStore.new(), CorruptWriteStore.new()]:
		F.expect(faulty.write_safe(snapshot, path) != OK and FileAccess.get_file_as_string(path) == original, "临时验证/原子替换失败保留旧档", failures)
	var directory := "user://rpg_v1/tests/readonly"
	DirAccess.make_dir_recursive_absolute(directory)
	var full_path := ProjectSettings.globalize_path(directory)
	if OS.get_name() == "Linux":
		F.expect(OS.execute("chmod", ["500", full_path]) == 0, "建立真实无写权限目录", failures)
		var error: Error = store.write_safe(snapshot, directory + "/save.json")
		var restored := OS.execute("chmod", ["700", full_path])
		F.expect(error != OK and restored == 0 and not FileAccess.file_exists(directory + "/save.json"), "目录无权限保存失败且无部分档", failures)
	var dir := DirAccess.open("user://rpg_v1/tests")
	for file in dir.get_files(): F.expect(not file.contains(".tmp-"), "写失败清理本次临时文件", failures)

static func _test_result_validation(Campaign, Store, failures: Array[String]) -> void:
	var campaign = _new(Campaign, Store, "bad_result", failures)
	var started: Dictionary = campaign.begin_battle("slice_1", _world())
	var initial: Dictionary = campaign.snapshot()
	for change in ["xp", "id", "story", "inventory", "hp", "member", "equipment", "defeat", "missing", "duplicate"]:
		var result := _victory(campaign, started)
		match change:
			"xp": result.xp = 41
			"id": result.battle_id = "unrelated"
			"story": result.story_patch = {"resolved": {"invented_clue": true}}
			"inventory": result.inventory.healing_potion += 1
			"hp": result.roster[0].hp = 0.5
			"member": result.roster[0] = initial.roster.p_mage.duplicate(true)
			"equipment": result.roster[0].equipment.armor = ""
			"defeat": result.outcome = "defeat"
			"missing": result.erase("inventory")
			"duplicate": result.roster[1] = result.roster[0].duplicate(true)
		F.expect(not campaign.apply_result(result).ok and campaign.snapshot() == initial, "拒绝非法战果且完整状态不变：" + change, failures)
	var stale = Campaign.new(null, Store.new(), "user://rpg_v1/tests/bad_result.json")
	F.expect(stale.load_run().ok and stale.retry_battle().ok, "另一个实例读取同一战前快照", failures)
	var victory := _victory(campaign, started)
	F.expect(campaign.apply_result(victory).ok, "首实例提交一次", failures)
	var duplicate: Dictionary = stale.apply_result(victory)
	F.expect(duplicate.ok and duplicate.already_applied and duplicate.story_patch.is_empty(), "重复交付必须读取持久已提交ID", failures)

static func _test_gear_loot(Campaign, Store, failures: Array[String]) -> void:
	var campaign = _new(Campaign, Store, "gear_loot", failures)
	var state: Dictionary = campaign.safe_snapshot()
	for standard in ["standard_weapon", "standard_armor", "standard_accessory"]:
		F.expect(state.gear.get(standard, 0) == 1, "新局持有标准装备：" + standard, failures)
	var denied: Dictionary = campaign.equip("p_swordsman", "weapon", "exorcism_sword")
	F.expect(not denied.ok and not denied.error.is_empty(), "未持有装备不能穿戴", failures)
	F.expect(campaign.safe_snapshot().roster.p_swordsman.equipment.weapon == "standard_weapon", "拒绝后装备保持不变", failures)
	var with_weapon: int = campaign.safe_snapshot().roster.p_swordsman.stats.atk
	var unequip: Dictionary = campaign.equip("p_swordsman", "weapon", "")
	F.expect(unequip.ok, "卸下已持有装备允许", failures)
	F.expect(campaign.safe_snapshot().roster.p_swordsman.stats.atk == with_weapon - 5, "卸下武器后攻击下降", failures)
	var requip: Dictionary = campaign.equip("p_swordsman", "weapon", "standard_weapon")
	F.expect(requip.ok and campaign.safe_snapshot().roster.p_swordsman.stats.atk == with_weapon, "穿回标准武器属性还原", failures)
	var store = Store.new()
	var forged: Dictionary = campaign.safe_snapshot()
	forged.gear = {}
	F.expect(store.write_safe(forged, "user://rpg_v1/tests/gear_forged.json") != OK, "穿装备却无持有表必须拒绝写入", failures)
	var legacy: Dictionary = campaign.safe_snapshot()
	legacy.erase("gear")
	var legacy_path := "user://rpg_v1/tests/gear_legacy.json"
	var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy, "", true, true))
	legacy_file.close()
	var loaded: Dictionary = store.load_safe(legacy_path)
	F.expect(loaded.ok and loaded.snapshot.gear.get("standard_weapon", 0) == 1, "旧档缺装备表读出时自动补默认", failures)
	var legacy_items: Dictionary = campaign.safe_snapshot()
	legacy_items.inventory.erase("energy_tea")
	var items_path := "user://rpg_v1/tests/items_legacy.json"
	var items_file := FileAccess.open(items_path, FileAccess.WRITE)
	items_file.store_string(JSON.stringify(legacy_items, "", true, true))
	items_file.close()
	var items_loaded: Dictionary = store.load_safe(items_path)
	F.expect(items_loaded.ok and items_loaded.snapshot.inventory.get("energy_tea", 0) == 2, "旧档缺新道具读出时补初始库存", failures)
	# 迁移补装：打到 slice_2 之后的旧档（无 gear 字段）按已清空遭遇补发战利品装备。
	var migrated: Dictionary = campaign.begin_battle("slice_2", _world())
	F.expect(migrated.get("ok", false), "迁移测试进战第二场", failures)
	F.expect(campaign.apply_result(_victory(campaign, migrated)).ok, "迁移测试提交第二场胜利", failures)
	var legacy_gear: Dictionary = campaign.safe_snapshot()
	legacy_gear.erase("gear")
	var gear_path := "user://rpg_v1/tests/gear_migrated.json"
	var gear_file := FileAccess.open(gear_path, FileAccess.WRITE)
	gear_file.store_string(JSON.stringify(legacy_gear, "", true, true))
	gear_file.close()
	var gear_loaded: Dictionary = store.load_safe(gear_path)
	F.expect(gear_loaded.ok and gear_loaded.snapshot.gear.get("exorcism_sword", 0) == 1 and gear_loaded.snapshot.gear.get("standard_weapon", 0) == 1, "旧档按已清空遭遇补发战利品装备", failures)
	var start: Dictionary = campaign.begin_battle("slice_2", _world())
	F.expect(start.get("ok", false), "战利品测试进战", failures)
	var before_gear: int = campaign.safe_snapshot().gear.get("exorcism_sword", 0)
	var applied: Dictionary = campaign.apply_result(_victory(campaign, start))
	F.expect(applied.ok, "提交胜利战果", failures)
	F.expect(campaign.safe_snapshot().gear.get("exorcism_sword", 0) == before_gear + 1, "胜利获得战利品装备", failures)
	var again: Dictionary = campaign.apply_result(_victory(campaign, start))
	F.expect(again.ok and again.already_applied, "重复提交只读已交付记录", failures)
	F.expect(campaign.safe_snapshot().gear.get("exorcism_sword", 0) == before_gear + 1, "战利品不重复发放", failures)
	var equipped: Dictionary = campaign.equip("p_swordsman", "weapon", "exorcism_sword")
	F.expect(equipped.ok, "获得战利品后可装备", failures)
	var actor: Dictionary = campaign.safe_snapshot().roster.p_swordsman
	var expected: Dictionary = Factory.new(null).stats_for("swordsman", actor.level, actor.equipment)
	F.expect(actor.stats == expected and actor.equipment.weapon == "exorcism_sword", "装备后属性按目录重算", failures)

static func _test_stage_adapter(failures: Array[String]) -> void:
	var Stage = load("res://scripts/scenes/stage_scene.gd")
	var stage = Stage.new()
	F.expect(stage.has_method("export_rpg_world") and stage.has_method("restore_rpg_world"), "舞台必须提供纯数据导出与恢复薄适配器", failures)
	if stage.has_method("export_rpg_world") and stage.has_method("restore_rpg_world"):
		stage.scene_file_path = "res://scenes/v3/stage.tscn"
		stage._player_x = 4.25
		stage._facing = -1
		stage._resolved = {"existing_clue": true}
		stage._dlg_fired = {"450": true}
		stage._exit_prompted = true
		stage._spirit = 7
		stage._party_index = 1
		var world: Dictionary = stage.export_rpg_world()
		F.expect(SaveBase.validate_world(world).is_empty() and State._plain(world) and world.resolved.existing_clue, "导出世界字段完整、无Node、保留谜题", failures)
		stage.restore_rpg_world(_world())
		F.expect(stage.export_rpg_world() == _world(), "恢复位置朝向谜题对话出口灵气与队员", failures)
		var invalid := _world()
		invalid.scene_path = "res://scenes/v3/stage_honden.tscn"
		stage.restore_rpg_world(invalid)
		F.expect(stage.export_rpg_world() == _world(), "不把其他舞台进度错误应用本场景", failures)
	stage.free()

static func _test_schema_types(Campaign, Store, failures: Array[String]) -> void:
	var campaign = _new(Campaign, Store, "types_base", failures)
	var store = Store.new()
	var baseline: Dictionary = campaign.snapshot()
	baseline.world = _world()
	var invalid_values: Array = [null, false, "bad", [], {}, 0.5]
	for field in ["schema_version", "rules_version", "phase", "run_id", "level", "xp", "roster", "party", "inventory", "world", "applied_battle_ids", "battle_counter", "next_encounter_id", "pending_battle"]:
		var missing: Dictionary = baseline.duplicate(true)
		missing.erase(field)
		F.expect(not store.validate(missing).is_empty(), "存档缺必需字段必须拒绝：" + field, failures)
		for value in invalid_values:
			# 空世界、空ID列表/后续ID、空待战字典各自合法。
			if (field == "run_id" and value is String) or (field in ["world", "pending_battle"] and value is Dictionary and value.is_empty()) or (field == "applied_battle_ids" and value is Array and value.is_empty()): continue
			var invalid: Dictionary = baseline.duplicate(true)
			invalid[field] = value
			F.expect(not store.validate(invalid).is_empty(), "存档必需字段错误类型/值：" + field + "/" + str(value), failures)

static func _test_branches_and_rest(Campaign, Store, failures: Array[String]) -> void:
	var campaign = _new(Campaign, Store, "branches", failures, 6)
	F.expect(campaign.set_branch("p_guard", "economy").ok and campaign.snapshot().roster.p_guard.branch == {"id": "economy"}, "六级允许目录已定义分支", failures)
	F.expect(campaign.set_branch("p_guard", "power").ok and campaign.snapshot().roster.p_guard.branch == {"id": "power"}, "换分支替换同一选择，不叠两条", failures)
	F.expect(campaign.set_branch("p_ranger", "duration").ok and campaign.set_branch("p_ranger", "power").ok, "游侠分支跨标记/猎杀两技能目录", failures)
	F.expect(not campaign.set_branch("p_mage", "duration").ok, "不能选择其他职业的分支", failures)
	var store = Store.new()
	var saved: Dictionary = campaign.safe_snapshot()
	for actor in saved.roster.values():
		actor.hp = 0
		actor.mp = 1
	F.expect(store.write_safe(saved, "user://rpg_v1/tests/branches.json") == OK and campaign.load_run().ok, "读入六人倒地安全档", failures)
	var inventory: Dictionary = campaign.snapshot().inventory
	F.expect(campaign.rest().ok, "准备点允许全队复活", failures)
	for actor in campaign.snapshot().roster.values(): F.expect(actor.hp == actor.stats.hp and actor.mp == actor.stats.mp, "包含未出战者在内全部复活回满", failures)
	F.expect(campaign.snapshot().inventory == inventory, "六人全复活仍不补道具", failures)
	var cap = _new(Campaign, Store, "cap_threshold", failures, 9)
	var near_cap: Dictionary = cap.safe_snapshot()
	near_cap.xp = 880
	F.expect(store.write_safe(near_cap, "user://rpg_v1/tests/cap_threshold.json") == OK and cap.load_run().ok, "载入接近十级阈值", failures)
	var battle: Dictionary = cap.begin_battle("slice_boss", _world())
	F.expect(cap.apply_result(_victory(cap, battle)).ok and cap.snapshot().level == 10 and cap.snapshot().xp == 0, "升到十级丢弃溢出经验不继续累计", failures)

static func _test_story_failure(Campaign, Store, Router, failures: Array[String]) -> void:
	var store := FailingStore.new()
	store.delegate = Store.new()
	var campaign = Campaign.new(null, store, "user://rpg_v1/tests/story_failure.json")
	F.expect(campaign.new_run(_ids(["guard", "swordsman", "healer"])).ok, "剧情原子测试新局", failures)
	var router = Router.new(campaign)
	Router.activate(router)
	var started: Dictionary = router.begin("res://scenes/v3/stage.tscn", "res://scenes/v3/battle.tscn", _world(), "basin_reflection")
	var before: Dictionary = campaign.snapshot()
	store.fail = true
	var victory := _victory(campaign, started)
	victory.inventory.healing_potion = 0
	var rejected: Dictionary = router.finish(victory)
	F.expect(not rejected.ok and rejected.story_patch.is_empty() and campaign.snapshot() == before and Router.take_world("res://scenes/v3/stage.tscn").is_empty(), "写失败不公开线索、不消费道具、不发经验、不安排返回世界", failures)
	store.fail = false
	F.expect(router.finish(victory).ok and Router.take_world("res://scenes/v3/stage.tscn").resolved.basin_reflection, "同战果重试成功才解决线索", failures)
	Router.clear_session()

static func _test_real_battle(Campaign, Store, Router, failures: Array[String]) -> void:
	var campaign = _new(Campaign, Store, "real", failures)
	var router = Router.new(campaign)
	var started: Dictionary = _fixed_start(campaign, Store, "real", "slice_1", 1701)
	F.expect(router.adopt_battle(started).ok, "独立切片接线采用同一战前设置", failures)
	var engine = router.create_engine()
	var initial: Dictionary = engine.snapshot()
	F.expect(router.create_engine() == engine, "重复创建请求不能免费重开战斗", failures)
	for index in range(150):
		engine.advance()
		var state: Dictionary = engine.snapshot()
		if not state.outcome.is_empty(): break
		var actor: Dictionary = state.actors[state.active_actor_id]
		var targets: Array = []
		for target in state.actors.values():
			if target.side == "enemy" and target.hp > 0: targets.append(target)
		targets.sort_custom(func(a, b): return a.hp < b.hp if a.hp != b.hp else a.actor_id < b.actor_id)
		var command := {"command_id": "real_%d" % state.revision, "expected_revision": state.revision, "actor_id": actor.actor_id, "kind": "attack_magic" if actor.class_id == "healer" else "attack_physical", "ability_id": "", "target_ids": [targets[0].actor_id]}
		if actor.class_id == "swordsman":
			var heavy := command.duplicate(true)
			heavy.kind = "skill"
			heavy.ability_id = "heavy_slash"
			if engine.preview(heavy).legal: command = heavy
		if actor.class_id == "healer":
			for id in campaign.safe_snapshot().party:
				if state.actors[id].hp > 0 and state.actors[id].hp <= state.actors[id].stats.hp - 86:
					var heal := command.duplicate(true)
					heal.kind = "skill"
					heal.ability_id = "heal"
					heal.target_ids = [id]
					if engine.preview(heal).legal: command = heal
		F.expect(engine.submit(command).accepted, "真实玩家指令能被同一引擎接受", failures)
	var result: Dictionary = router.result_from_engine()
	F.expect(result.get("outcome") == "victory" and result.get("roster", []).size() == 3, "真实引擎胜利产出三人战果", failures)
	var catalog := Catalog.new()
	catalog.load_all()
	F.expect(result.replay.initial == initial and Replay.verify(result.replay, catalog, Policy.new()).matches, "真实首战全事件可重放，起始意图不重复", failures)
	F.expect(router.finish(result).ok and campaign.snapshot().xp == 40, "真实引擎战果成功持久提交", failures)
	var setup: Dictionary = _fixed_start(campaign, Store, "real", "slice_2", 1702)
	router.adopt_battle(setup)
	engine = router.create_engine()
	for index in range(400):
		engine.advance()
		var state: Dictionary = engine.snapshot()
		if not state.outcome.is_empty(): break
		F.expect(engine.submit({"command_id": "defeat_%d" % state.revision, "expected_revision": state.revision, "actor_id": state.active_actor_id, "kind": "defend", "ability_id": "", "target_ids": []}).accepted, "真实战败路径指令合法", failures)
	var defeated: Dictionary = router.result_from_engine()
	F.expect(defeated.get("outcome") == "defeat" and router.finish(defeated).ok, "真实战败通过同一战果协议", failures)
	var retry: Dictionary = router.retry()
	F.expect(retry.ok and retry.setup == setup.setup and router.create_engine().snapshot().actors.p_guard.hp == setup.setup.actors.p_guard.hp, "真实败北重试回到消耗前状态", failures)

static func _test_nested_types(Campaign, Store, failures: Array[String]) -> void:
	var campaign = _new(Campaign, Store, "nested", failures)
	var store = Store.new()
	var snapshot: Dictionary = campaign.snapshot()
	snapshot.world = _world()
	for field in ["actor_id", "class_id", "side", "level", "hp", "mp", "stats", "equipment", "skill_ids", "branch", "statuses", "shield", "cooldown_until", "intent", "boss", "slot_count", "opportunity_count", "revived_round"]:
		for value in [false, "bad", [], {}, 0.5]:
			# 这些字典/数组允许为空；固定字段值仍不可错型。
			if (field in ["branch", "shield", "cooldown_until", "intent", "boss"] and value is Dictionary) or (field == "statuses" and value is Array): continue
			var invalid: Dictionary = snapshot.duplicate(true)
			invalid.roster.p_guard[field] = value
			F.expect(not store.validate(invalid).is_empty(), "角色错型拒绝：" + field + "/" + str(value), failures)
	for flag in [0, "true", [], {}]:
		var invalid: Dictionary = snapshot.duplicate(true)
		invalid.world.resolved = {"clue": flag}
		F.expect(not store.validate(invalid).is_empty(), "世界已解决标记必须布尔true", failures)
	var start: Dictionary = campaign.begin_battle("slice_1", _world())
	for field in ["actor_id", "side", "class_id", "level", "stats", "equipment", "skill_ids", "branch"]:
		var result := _victory(campaign, start)
		result.roster[0][field] = false
		F.expect(not campaign.apply_result(result).ok, "错误类型战果拒绝不崩溃：" + field, failures)

static func _test_pending_resume(Campaign, Store, Router, failures: Array[String]) -> void:
	var campaign = _new(Campaign, Store, "pending_resume", failures)
	var edited: Dictionary = campaign.safe_snapshot()
	edited.roster.p_guard.hp = 100
	var store = Store.new()
	F.expect(store.write_safe(edited, "user://rpg_v1/tests/pending_resume.json") == OK and campaign.load_run().ok, "待战恢复先有真实受损资源", failures)
	var started: Dictionary = campaign.begin_battle("slice_1", _world())
	var reloaded = Campaign.new(null, store, "user://rpg_v1/tests/pending_resume.json")
	F.expect(reloaded.load_run().ok, "标题读到进战前安全档", failures)
	F.expect(not reloaded.use_item_outside("healing_potion", "p_guard").ok, "有待重试快照时不能改物资再覆盖战前基线", failures)
	F.expect(not reloaded.begin_battle("slice_2", _world()).ok, "待战上下文未处理前不能替换另一场战斗", failures)
	F.expect(reloaded.retry_battle().setup == started.setup, "加载再重试仍是原始完整战前快照", failures)
	var router = Router.new(Campaign.new(null, store, "user://rpg_v1/tests/pending_resume.json"))
	var loaded: Dictionary = router.load_safe_run()
	F.expect(loaded.ok and loaded.get("pending_battle", false) and loaded.get("next_scene") == "res://scenes/rpg/battle.tscn" and router.create_engine() != null, "继续待战安全档明确进入原始战前战斗", failures)

static func _fixed_start(campaign, Store, tag: String, encounter: String, seed_value: int) -> Dictionary:
	campaign.begin_battle(encounter, {})
	var saved: Dictionary = campaign.safe_snapshot()
	saved.pending_battle.seed = seed_value
	Store.new().write_safe(saved, "user://rpg_v1/tests/%s.json" % tag)
	campaign.load_run()
	return campaign.retry_battle()

static func _test_stage_failure(Campaign, Store, Router, failures: Array[String]) -> void:
	var failing := FailingStore.new()
	failing.delegate = Store.new()
	var campaign = Campaign.new(null, failing, "user://rpg_v1/tests/stage_failure.json")
	F.expect(campaign.new_run(_ids(["guard", "swordsman", "healer"])).ok, "舞台失败测试新局", failures)
	var router = Router.new(campaign)
	Router.activate(router)
	var Stage = load("res://scripts/scenes/stage_scene.gd")
	var stage = Stage.new()
	stage.scene_file_path = "res://scenes/v3/stage.tscn"
	stage._rpg_pending_clue = "basin_reflection"
	stage._hint_label = Label.new()
	stage._hint_label.visible = false
	stage._investigating = true
	stage._cinematic = true
	stage.input_enabled = false
	failing.fail = true
	stage._go_battle("res://scenes/v3/battle.tscn")
	F.expect(stage._resolved.is_empty() and not stage._investigating and not stage._cinematic and stage.input_enabled, "进战保存失败不解决谜题，恢复探索输入", failures)
	F.expect(stage._hint_label.visible and not stage._hint_label.text.is_empty(), "保存失败原因必须显示在既有提示条", failures)
	stage._hint_label.free()
	stage.free()
	Router.clear_session()

static func _test_stage_ready(Campaign, Store, Router, failures: Array[String]) -> void:
	var campaign = _new(Campaign, Store, "stage_ready", failures)
	var router = Router.new(campaign)
	Router.activate(router)
	router._return_world = _world()
	var packed = load("res://scenes/v3/stage.tscn")
	var stage = packed.instantiate()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(stage)
	await tree.process_frame
	F.expect(stage.export_rpg_world() == _world(), "真实舞台ready恢复全部探索字段", failures)
	F.expect(not stage._dlg_playing and not stage._dlg_cfg.is_empty(), "恢复舞台保留对话数据且不重播入场段", failures)
	F.expect(stage._stat_panel.get_child(0).text == stage._party[1].name, "恢复选中队员同步已有HUD", failures)
	stage.queue_free()
	await tree.process_frame
	router._return_world = _world()
	var backdrop = packed.instantiate()
	backdrop.backdrop_mode = true
	backdrop.input_enabled = false
	tree.root.add_child(backdrop)
	await tree.process_frame
	F.expect(backdrop._resolved.is_empty() and backdrop._player_x != 735.5 and router._return_world == _world(), "标题活背景不能消费或应用RPG恢复上下文", failures)
	backdrop._rpg_pending_clue = "basin_reflection"
	var before: Dictionary = campaign.snapshot()
	backdrop._go_battle("res://scenes/v3/battle.tscn")
	F.expect(campaign.snapshot() == before, "标题背景即使误调用入口也不能触发RPG战斗", failures)
	backdrop.queue_free()
	await tree.process_frame
	Router.clear_session()

static func _test_exit_commit(Campaign, Store, Router, failures: Array[String]) -> void:
	var campaign = _new(Campaign, Store, "exit_commit", failures)
	var destination := "res://scenes/v3/stage_corridor.tscn"
	var started: Dictionary = campaign.begin_battle("slice_1", _world(), {"next_scene": destination})
	F.expect(campaign.apply_result(_victory(campaign, started)).ok, "授权已有场景出口随胜利提交", failures)
	var router = Router.new(Campaign.new(null, Store.new(), "user://rpg_v1/tests/exit_commit.json"))
	var loaded: Dictionary = router.load_safe_run()
	F.expect(loaded.ok and loaded.next_scene == destination, "保存成功后退出再继续仍采用已提交出口，不丢过场结果", failures)

static func _test_stale_commits(Campaign, Store, failures: Array[String]) -> void:
	for phase in ["preparation", "exploration", "rest"]:
		var tag: String = "stale_" + phase
		var path: String = "user://rpg_v1/tests/" + tag + ".json"
		var current = _new(Campaign, Store, tag, failures, 6)
		# 用正常战果进入探索/休息；准备夹具受伤仅用于让战外药物产生有效作用。
		if phase != "preparation":
			var first: Dictionary = current.begin_battle("slice_1", _world())
			var result := _victory(current, first)
			result.roster[0].hp = 200
			F.expect(current.apply_result(result).ok, "建立陈旧探索态", failures)
		if phase == "rest":
			var second: Dictionary = current.begin_battle("slice_2", _world())
			F.expect(current.apply_result(_victory(current, second)).ok, "建立陈旧休息态", failures)
		if phase == "preparation":
			var fixture: Dictionary = current.safe_snapshot()
			fixture.roster.p_guard.hp = 200
			F.expect(Store.new().write_safe(fixture, path) == OK and current.load_run().ok, "建立陈旧准备态", failures)
		var stale = Campaign.new(null, Store.new(), path)
		F.expect(stale.load_run().ok and stale.snapshot().phase == phase, "另实例读取" + phase, failures)
		var old_memory: Dictionary = stale.snapshot()
		var started: Dictionary = current.begin_battle("slice_1", _world())
		var victory := _victory(current, started)
		victory.roster[0].hp = 100
		victory.inventory.healing_potion = 1
		F.expect(current.apply_result(victory).ok, "当前实例先提交资源与奖励", failures)
		var disk := FileAccess.get_file_as_string(path)
		var operations: Array = [func(): return stale.use_item_outside("healing_potion", "p_guard"), func(): return stale.begin_battle("slice_1", _world()), func(): return stale.begin_ritual(_world())]
		if phase != "exploration":
			operations.append_array([func(): return stale.rest(), func(): return stale.equip("p_guard", "armor", ""), func(): return stale.set_party(_ids(["p_ranger", "p_mage", "p_controller"])), func(): return stale.set_branch("p_guard", "economy")])
		for operation in operations:
			var rejected: Dictionary = operation.call()
			F.expect(not rejected.ok and stale.snapshot() == old_memory and FileAccess.get_file_as_string(path) == disk, "陈旧" + phase + "普通提交必须拒绝且不回退内存/最新磁盘", failures)
		var duplicate: Dictionary = stale.apply_result(victory)
		F.expect(duplicate.ok and duplicate.already_applied and duplicate.story_patch.is_empty() and FileAccess.get_file_as_string(path) == disk, "陈旧普通提交失败后仍只交付原ID一次", failures)
		var latest: Dictionary = Store.new().load_safe(path).snapshot
		F.expect(latest.xp == current.snapshot().xp and latest.roster.p_guard.hp == 100 and latest.inventory.healing_potion == 1 and latest.applied_battle_ids.has(started.battle_id), "完整保留最新资源/XP/计数/提交记录", failures)
		# 用户明确新开局可以替换合法旧槽，但不会复用旧run_id/battle_id。
		var old_run: String = latest.run_id
		F.expect(stale.new_run(_ids(["guard", "swordsman", "healer"])).ok and stale.snapshot().run_id != old_run, "显式新局区别于陈旧普通修改", failures)
		F.expect(not current.rest().ok and not current.begin_battle("slice_1", _world()).ok, "旧run不能覆盖明确的新局", failures)

static func _test_ritual_flow(Campaign, Store, Router, failures: Array[String]) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var campaign = _new(Campaign, Store, "ritual_flow", failures)
	var router = Router.new(campaign)
	Router.activate(router)
	var world := _world()
	world.scene_path = "res://scenes/v3/stage_corridor.tscn"
	world.player_x = 1041.25
	world.dlg_fired = {"310": true, "940": true}
	world.exit_prompted = true
	world.spirit = 3
	var second: Dictionary = router.begin(world.scene_path, "res://scenes/v3/battle.tscn", world, "bell_self_ring")
	F.expect(router.finish(_victory(campaign, second)).ok, "真实仪式链先提交钟鸣战果", failures)
	var Deck = load("res://scripts/scenes/deck_scene.gd")
	var build := JSON.stringify({"version": 1, "main": "rinne", "support": "mint", "artifact": "", "deck": Deck.PRESET_DECK, "sentinel_extension": "keep unchanged"}, "  ")
	var progress := "{\"unlocked_cards\":[],\"unlocked_artifacts\":[],\"cases_done\":[],\"sentinel_extension\":\"keep unchanged\"}"
	_write("user://build.json", build)
	_write("user://progress.json", progress)
	F.expect(tree.change_scene_to_file(world.scene_path) == OK, "真实回廊场景载入", failures)
	await tree.process_frame
	await tree.process_frame
	var stage = tree.current_scene
	F.expect(stage._resolved == {"bell_self_ring": true}, "回廊已有战斗线索恢复", failures)
	var before: Dictionary = stage.export_rpg_world()
	# 实际执行特写/入口；旧代码会经过deck，回归必须检测这条中间路径。
	stage._investigating = true
	stage.input_enabled = false
	var clue: Dictionary = {}
	for row in stage._clues:
		if row.id == "coffin_sendoff": clue = row
	stage._show_clue_closeup(clue)
	var entered := await _wait_scene(tree, "res://scenes/v3/ritual.tscn", 4.0)
	F.expect(entered, "RPG仪式直接进入既有仪式，不经会写旧构筑的deck", failures)
	if not entered and tree.current_scene != null and tree.current_scene.scene_file_path == "res://scenes/v3/deck.tscn":
		tree.current_scene._on_go()
		entered = await _wait_scene(tree, "res://scenes/v3/ritual.tscn", 2.0)
	F.expect(entered, "真实仪式场景已开始", failures)
	if not entered:
		Router.clear_session()
		return
	F.expect(FileAccess.get_file_as_string("user://build.json") == build and FileAccess.get_file_as_string("user://progress.json") == progress, "仪式入口/出战均不改旧build/progress字节", failures)
	F.expect(campaign.safe_snapshot().world.resolved.get("coffin_sendoff", false) and campaign.safe_snapshot().world.resolved.get("bell_self_ring", false), "按旧线索语义在仪式入口持久提交送行标记且保留钟鸣", failures)
	F.expect(not campaign.rest().ok and not campaign.set_party(_ids(["p_mage", "p_ranger", "p_controller"])).ok, "仪式运行态不能旁路更改RPG资源", failures)
	# 实际取消输入走仪式_process的退场回调。
	Input.action_press("ui_cancel")
	await tree.process_frame
	Input.action_release("ui_cancel")
	F.expect(await _wait_scene(tree, world.scene_path, 2.0), "真实仪式取消返回回廊", failures)
	stage = tree.current_scene
	var expected: Dictionary = before.duplicate(true)
	expected.resolved["coffin_sendoff"] = true
	F.expect(stage.export_rpg_world() == expected and not stage._dlg_playing, "取消返场完整保留线索/位置/朝向/对话/出口/灵气/队员且不重播", failures)
	if OS.get_environment("RPG_TEST_LEGACY_CONTRACTS") == "1":
		F.expect(stage._all_clues_resolved() and stage._cfg.next == "res://scenes/v3/stage_honden.tscn", "历史契约：原本殿出口可继续，不重复钟鸣战斗", failures)
	else:
		F.expect(stage._all_clues_resolved() and stage._cfg.next == "res://scenes/v3/stage_night3.tscn", "保留兼容舞台的五夜叙事顺序，回廊先到第三夜且不重打钟鸣", failures)
	F.expect(FileAccess.get_file_as_string("user://build.json") == build and FileAccess.get_file_as_string("user://progress.json") == progress, "仪式取消返回不改旧档字节", failures)
	var resumed = Router.new(Campaign.new(null, Store.new(), "user://rpg_v1/tests/ritual_flow.json"))
	var loaded: Dictionary = resumed.load_safe_run()
	F.expect(loaded.ok and loaded.next_scene == world.scene_path and resumed.campaign.safe_snapshot().world == expected, "标题继续与真实仪式返场世界一致", failures)
	# 再次进入仅为测试既有结算返回按钮，不增加XP/奖励/战斗ID。
	stage._rpg_pending_clue = "coffin_sendoff"
	stage._go_battle("res://scenes/v3/ritual.tscn")
	entered = await _wait_scene(tree, "res://scenes/v3/ritual.tscn", 2.0)
	if not entered and tree.current_scene.scene_file_path == "res://scenes/v3/deck.tscn":
		tree.current_scene._on_go()
		entered = await _wait_scene(tree, "res://scenes/v3/ritual.tscn", 2.0)
	F.expect(entered, "仪式结算返场测试入口", failures)
	if entered:
		var ritual = tree.current_scene
		# 运行原仪式目标/添灯/回合规则至终局，未改HP、费用、目标或胜负条件。
		for turn in range(6):
			for id in ["identify", "place", "guide"]:
				var objective: Dictionary = ritual._objectives[id]
				if BattleRulesV4.ritual_objective_available(objective.def, {"turn": ritual._turn, "done": ritual._done_map()}).ok:
					ritual._try_objective(id)
			if ritual._lamp <= 4: ritual._on_add_fuel()
			await ritual._end_turn_resolve()
			if ritual._over: break
		F.expect(ritual._over and ritual._objectives.guide.done and ritual._hp > 0 and ritual._lamp > 0, "实际仪式规则仍能完成原目标链", failures)
		var back := _find_button(ritual, "返回探索")
		F.expect(back != null, "原仪式结算保留返回探索按钮", failures)
		if back != null: back.pressed.emit()
		F.expect(await _wait_scene(tree, world.scene_path, 2.0), "结算返回按钮回到原探索", failures)
		F.expect(tree.current_scene.export_rpg_world() == expected and campaign.snapshot().xp == 40 and campaign.snapshot().applied_battle_ids.size() == 1, "仪式结算返场无额外经验/奖励且保留完整世界", failures)
	F.expect(FileAccess.get_file_as_string("user://build.json") == build and FileAccess.get_file_as_string("user://progress.json") == progress, "完整仪式入口/取消/结算返回旧档均逐字节不变", failures)
	Router.clear_session()
	tree.current_scene.queue_free()
	await tree.process_frame

static func _wait_scene(tree: SceneTree, path: String, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
		if tree.current_scene != null and tree.current_scene.scene_file_path == path:
			await tree.process_frame
			return true
	return false

static func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null: return found
	return null

static func _test_ritual_boundaries(Campaign, Store, Router, failures: Array[String]) -> void:
	var failing := FailingStore.new()
	failing.delegate = Store.new()
	var campaign = Campaign.new(null, failing, "user://rpg_v1/tests/ritual_failures.json")
	F.expect(campaign.new_run(_ids(["guard", "swordsman", "healer"])).ok, "仪式边界测试新局", failures)
	var router = Router.new(campaign)
	Router.activate(router)
	var world := _world()
	world.scene_path = "res://scenes/v3/stage_corridor.tscn"
	world.resolved = {"bell_self_ring": true}
	var ritual_scene := "res://scenes/v3/ritual.tscn"
	F.expect(router.supports_ritual(world.scene_path, ritual_scene), "唯一仪式的直接入口可按来源+场景解析既有线索", failures)
	var before: Dictionary = campaign.snapshot()
	var disk := FileAccess.get_file_as_string("user://rpg_v1/tests/ritual_failures.json")
	failing.fail = true
	var failed: Dictionary = router.begin_ritual(world.scene_path, ritual_scene, world, "coffin_sendoff")
	F.expect(not failed.ok and campaign.snapshot() == before and FileAccess.get_file_as_string("user://rpg_v1/tests/ritual_failures.json") == disk and not router.ritual_active(ritual_scene), "仪式入场写失败保留世界/资源/原档且不建立上下文", failures)
	failing.fail = false
	F.expect(router.begin_ritual(world.scene_path, ritual_scene, world).ok and router.ritual_active(ritual_scene), "仪式入场写失败可重试，唯一场景入口补全既有线索", failures)
	var active: Dictionary = campaign.snapshot()
	F.expect(Store.new().write_safe(active, "user://rpg_v1/tests/not_ritual_midpoint.json") != OK, "运行中的仪式也不允许作为安全档保存", failures)
	failing.fail = true
	failed = router.finish_ritual(ritual_scene)
	F.expect(not failed.ok and router.ritual_active(ritual_scene) and campaign.snapshot() == active and Router.take_world(world.scene_path).is_empty(), "仪式返场写失败不丢上下文或发布未提交世界", failures)
	failing.fail = false
	F.expect(router.finish_ritual(ritual_scene).ok and not router.ritual_active(ritual_scene) and Router.take_world(world.scene_path).resolved.coffin_sendoff, "仪式返场写失败可再次确认返回", failures)
	F.expect(not router.finish_ritual(ritual_scene).ok and Router.take_world(world.scene_path).is_empty(), "重复仪式返回不重排世界补丁", failures)
	Router.clear_session()
	# 未启用新模式时，原统一入口仍到deck，返回按钮继续原有存档与跳转行为。
	var tree := Engine.get_main_loop() as SceneTree
	F.expect(tree.change_scene_to_file(world.scene_path) == OK, "旧模式回廊可加载", failures)
	await tree.process_frame
	await tree.process_frame
	tree.current_scene._go_battle(ritual_scene)
	F.expect(await _wait_scene(tree, "res://scenes/v3/deck.tscn", 2.0), "关闭RPG时仪式仍经原deck入口", failures)
	if tree.current_scene.scene_file_path == "res://scenes/v3/deck.tscn":
		tree.current_scene._on_back()
		F.expect(await _wait_scene(tree, world.scene_path, 2.0), "旧deck取消仍回原舞台", failures)
	tree.current_scene.queue_free()
	await tree.process_frame
