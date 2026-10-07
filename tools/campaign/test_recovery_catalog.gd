# 测试只读胜利来源投影；这些最小夹具不替代Store对完整正式存档的校验。
extends SceneTree
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Store = preload("res://scripts/rpg/save_store.gd")
var recovery: GDScript
var catalog: RefCounted
var assertions := 0
var failures: Array[String] = []

func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_expect(FileAccess.file_exists("res://scripts/campaign/recovery_catalog.gd"), "回收册需要可执行的纯派生目录")
	if failures.is_empty():
		recovery = load("res://scripts/campaign/recovery_catalog.gd")
		catalog = Catalog.new()
		_expect(catalog.load_all().is_empty(), "真实敌人与遭遇目录合法")
		_test_definitions()
		_test_first_victories()
		_test_order_and_previews()
		_test_source_rejection()
		_test_link_gates()
		_test_permanent_read_only()
		_test_approved_link_references()
		_test_strict_checkpoint()
	print("CAMPAIGN_RECOVERY_CATALOG: %d assertions, %d failures" % [assertions, failures.size()])
	for failure in failures: printerr("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)

func _saved(nights: int = 5, saga_encounters: Array = []) -> Dictionary:
	var result := {"schema_version": 3, "progression_version": 2, "campaign_id": "five_night_3d_v1", "run_id": "recovery_test_run", "world_history": {}, "applied_battle_ids": [], "battle_counter": 0, "pending_battle": {}}
	for night in range(1, nights + 1):
		result.world_history["night_%d" % night] = {"night": night, "event_flags": {"battle:cleared": true}}
		result.applied_battle_ids.append("recovery_test_run:" + str(result.applied_battle_ids.size() + 1))
	if not saga_encounters.is_empty():
		result.saga = {"battles": [], "battle_encounters": {}, "completed": []}
		for encounter_id in saga_encounters:
			var scene_id: String = catalog.get_definition("encounters", encounter_id).story_scene
			result.saga.battles.append(scene_id)
			result.saga.battle_encounters[scene_id] = encounter_id
			result.applied_battle_ids.append("recovery_test_run:" + str(result.applied_battle_ids.size() + 1))
	result.battle_counter = result.applied_battle_ids.size()
	return result

func _row(rows: Array, enemy_id: String) -> Dictionary:
	for row in rows:
		if row.enemy_id == enemy_id: return row
	return {}

func _test_definitions() -> void:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/enemy_recoveries.json"))
	_expect(document.schema_version == 1 and document.definitions.size() == 21, "六原敌与十五后章敌均登记")
	for enemy_id in catalog.get_ids("enemies"):
		var row: Dictionary = recovery.entry("recovery_" + enemy_id)
		_expect(not row.is_empty() and row.enemy_id == enemy_id, "回收条目对应实际敌种：" + enemy_id)
		if row.is_empty(): continue
		_expect(row.origin == "new_design_2026_10_08" and not row.provenance.is_empty(), "所有具体回收名均标明本轮新设计")
		_expect(row.quantity == 1 and not row.tradable and not row.consumable and not row.mainline_key, "永久观察记录不可交易/消耗或作主线钥匙")
		_expect(not row.name in ["同源镜屑", "总控实销"], "回收品不冒充批准关键物证")
		for link in row.links:
			_expect(not link.unlocked and link.text.is_empty(), "无存档上下文的entry查询不能泄漏后章链接文本")
	_expect(recovery.entry("missing").is_empty(), "未知回收ID不猜测条目")

func _test_first_victories() -> void:
	var saved := _saved()
	var rows: Array = recovery.earned(saved, catalog)
	_expect(rows.size() == 6, "五夜重复出场只收录六原敌")
	var expected := ["hound", "shield_soldier", "cultist", "elite_shield_soldier", "fire_spirit", "gatekeeper"]
	for index in rows.size(): _expect(rows[index].enemy_id == expected[index], "按首次胜利与遭遇内登记次序收录")
	_expect(_row(rows, "hound").encounter_id == "campaign_night_1" and _row(rows, "hound").battle_id == "recovery_test_run:1", "猎犬重复出场保留真正首胜来源")
	var all_saga: Array = []
	for id in catalog.get_ids("encounters"):
		if id.begins_with("saga_") and not id in ["saga_c7_11", "saga_c7_12", "saga_c7_13"]: all_saga.append(id)
	rows = recovery.earned(_saved(5, all_saga), catalog)
	_expect(rows.size() == 21, "单一结局路线的来源投影可覆盖全部21敌种")
	for row in rows:
		_expect(row.battle_id.begins_with("recovery_test_run:") and not row.preview, "实际回收绑定已提交战斗ID")
		_expect(not row.verified_scope.is_empty(), "每条回收明确说明已验证范围")
	for final_id in ["saga_c7_10", "saga_c7_11", "saga_c7_12", "saga_c7_13"]:
		rows = recovery.earned(_saved(5, [final_id]), catalog)
		for enemy_id in ["saga_exit_recoil", "saga_relay_recoil", "saga_final_recoil"]:
			_expect(_row(rows, enemy_id).encounter_id == final_id and _row(rows, enemy_id).battle_id == "recovery_test_run:6", "三层目标仅绑定本局所选第三阶段真实胜利")

func _test_order_and_previews() -> void:
	var saved := _saved(5, ["saga_c2_09", "saga_c2_03", "saga_c3_07"])
	var before := saved.duplicate(true)
	var rows: Array = recovery.earned(saved, catalog)
	_expect(_row(rows, "saga_lamp_shadow").encounter_id == "saga_c2_09" and _row(rows, "saga_lamp_shadow").battle_id == "recovery_test_run:6", "来源跟随真实胜利数组，不被字典或场次排序改写")
	_expect(_row(rows, "saga_lamp_shadow").get("scene_id") == "C2-09" and not str(_row(rows, "saga_lamp_shadow").get("encounter_name", "")).is_empty(), "来源场次与公开遭遇名可直接供回收页展示")
	_expect(_row(rows, "saga_paper_soldier").battle_id == "recovery_test_run:7", "后来的胜利不回填到早先暂缓场次")
	_expect(recovery.preview_new(saved, "saga_c3_07", catalog).is_empty(), "已收录敌种没有重复首收预览")
	saved.pending_battle = {"battle_id": "recovery_test_run:9", "encounter_id": "saga_c2_12"}
	saved.battle_counter = 9
	var preview: Array = recovery.preview_new(saved, "saga_c2_12", catalog)
	_expect(preview.size() == 1 and preview[0].enemy_id == "saga_borrowed_voice" and preview[0].battle_id == "recovery_test_run:9" and preview[0].preview, "预览采用真实待战ID并明确尚未首收")
	_expect(_row(recovery.earned(saved, catalog), "saga_borrowed_voice").is_empty(), "待战、败北、重试均未写胜利事实，不收录")
	_expect(recovery.preview_new(saved, "saga_c4_09", catalog).is_empty(), "已有待战不能预览另一个未提交遭遇")
	saved.erase("pending_battle")
	saved.pending_battle = {}; saved.battle_counter = 8
	_expect(saved == before, "所有查询没有改动原来源投影")

func _test_source_rejection() -> void:
	var base := _saved(5, ["saga_c2_03"])
	var invalid: Array = []
	for patch in [{"campaign_id": "legacy"}, {"applied_battle_ids": []}, {"battle_counter": 0}, {"world_history": null}, {"run_id": "other_run"}, {"schema_version": 99}]:
		var saved := base.duplicate(true); saved.merge(patch, true); invalid.append(saved)
	var saved := base.duplicate(true); saved.world_history.night_2.event_flags["battle:cleared"] = false; invalid.append(saved)
	saved = base.duplicate(true); saved.world_history.erase("night_1"); invalid.append(saved)
	saved = base.duplicate(true); saved.applied_battle_ids[5] = "recovery_test_run:5"; invalid.append(saved)
	saved = base.duplicate(true); saved.saga.battles.append("C2-03"); invalid.append(saved)
	saved = base.duplicate(true); saved.saga.battle_encounters["C2-03"] = "saga_c2_09"; invalid.append(saved)
	saved = base.duplicate(true); saved.saga.battle_encounters["C2-99"] = "saga_c2_09"; invalid.append(saved)
	saved = base.duplicate(true); saved.pending_battle = {"battle_id": "forged:7", "encounter_id": "saga_c2_12"}; saved.battle_counter = 7; invalid.append(saved)
	for item in invalid:
		var before: Dictionary = item.duplicate(true)
		_expect(recovery.earned(item, catalog).is_empty() and recovery.preview_new(item, "saga_c2_12", catalog).is_empty(), "来源不闭合时不发布回收或预览")
		_expect(item == before, "坏来源只读拒绝，不自动修补")
	_expect(recovery.earned({}, catalog).is_empty() and recovery.earned(base, null).is_empty(), "缺失来源或目录时安全关闭")
	for id in ["slice_1", "elite_test", "missing"]: _expect(recovery.preview_new(_saved(0), id, catalog).is_empty(), "历史/未知遭遇不提供正式回收")

func _test_link_gates() -> void:
	var saved := _saved(5, ["saga_c2_12", "saga_c3_03", "saga_c6_11", "saga_c7_06", "saga_c7_10"])
	var before := saved.duplicate(true)
	var rows: Array = recovery.earned(saved, catalog)
	for enemy_id in ["saga_borrowed_voice", "saga_mirror_shard", "saga_nochange_warden", "saga_lamp_bearer", "saga_final_recoil"]:
		for link in _row(rows, enemy_id).links: _expect(not link.unlocked and link.text.is_empty(), "胜利本身不能提前开放后续批准调查文本")
	saved.saga.completed = ["C2-13", "C4-02", "C6-08", "C6-12", "C7-07", "C7-08", "C7-15"]
	rows = recovery.earned(saved, catalog)
	for enemy_id in ["saga_borrowed_voice", "saga_mirror_shard", "saga_nochange_warden", "saga_lamp_bearer"]:
		_expect(_row(rows, enemy_id).links.any(func(link): return link.unlocked and not link.text.is_empty()), "指定批准场完成后开放对应对照：" + enemy_id)
	var final: Dictionary = _row(rows, "saga_final_recoil")
	_expect(final.links.filter(func(link): return link.unlocked).size() == 1, "只开放本局已完成的后日谈，不跨结局补齐")
	_expect(not saved.has("shared_mirror_shard") and not saved.has("master_pin") and not saved.saga.has("flags"), "回收查询不发同源镜屑/实销或任何剧情flag")
	saved.saga.completed = []
	_expect(saved == before, "链接查询保持所有战果及剧情来源不变")
	var first := _saved()
	var copper: Dictionary = _row(recovery.earned(first, catalog), "gatekeeper")
	_expect(not copper.links[0].unlocked, "第五夜胜利后对白未完成时仍锁定结案对照")
	first.world_history.night_5.event_flags["dialogue:hd5"] = true
	_expect(_row(recovery.earned(first, catalog), "gatekeeper").links[0].unlocked, "已完成批准战后对白才开放第一章对照")

func _test_permanent_read_only() -> void:
	var saved := _saved(5, ["saga_c6_11"])
	var initial: Array = recovery.earned(saved, catalog)
	saved["runtime"] = {"defeated": ["saga_anchor_left", "saga_anchor_left", "saga_anchor_right"], "repairs": 2, "outcome": "defeat"}
	saved.saga["chapter"] = 2
	_expect(recovery.earned(saved, catalog) == initial, "临时死亡/两次召回/跨章回访不能重复收录")
	var transported: Dictionary = _integerize(JSON.parse_string(JSON.stringify(saved)))
	_expect(recovery.earned(transported, catalog) == initial, "合法来源JSON续读后首收与ID稳定")
	var rows: Array = recovery.earned(saved, catalog)
	rows[0].name = "被改动"; rows[0].links.clear()
	_expect(recovery.earned(saved, catalog) == initial, "派生结果深复制，不破坏永久目录")
	var entry: Dictionary = recovery.entry("recovery_hound"); entry.name = "被改动"
	_expect(recovery.entry("recovery_hound").name != "被改动", "目录查询也不外泄共享可变引用")

func _test_approved_link_references() -> void:
	var approved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/saga.json"))
	var scenes := {}
	for chapter in approved.chapters:
		for scene in chapter.scenes: scenes[scene.id] = true
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/enemy_recoveries.json"))
	for row in document.definitions:
		for link in row.links:
			if link.gate.has("completed"):
				_expect(scenes.has(link.scene_id) and link.gate.completed == link.scene_id, "后章链接必须引用真实批准场次：" + link.scene_id)
			else:
				_expect(link.scene_id in ["night_1", "night_2", "night_3", "night_4", "night_5"] and link.gate.event in ["dialogue:h1", "battle:cleared", "dialogue:m1", "ritual:guide", "dialogue:p3", "dialogue:hd5"], "首章链接必须对应已批准观察/仪式/战后对白")

func _test_strict_checkpoint() -> void:
	# 可选外证据只读验证；不写入slot、不迁移merchant、不补充任何版本字段。
	var path := OS.get_environment("RECOVERY_CHECKPOINT")
	if path.is_empty(): return
	_expect(FileAccess.file_exists(path), "指定真实检查点存在")
	if not FileAccess.file_exists(path): return
	var before_hash := FileAccess.get_sha256(path)
	var loaded: Dictionary = Store.new(catalog)._decode(FileAccess.get_file_as_string(path))
	_expect(loaded.ok, "真实检查点通过当前Store完整严格校验：" + str(loaded.get("error", "")))
	if not loaded.ok: return
	var saved: Dictionary = loaded.snapshot
	var before := saved.duplicate(true)
	var rows: Array = recovery.earned(saved, catalog)
	_expect(not rows.is_empty(), "真实已胜来源可以派生回收册")
	var unique := {}
	for row in rows:
		_expect(saved.applied_battle_ids.has(row.battle_id) and not unique.has(row.enemy_id), "实际回收绑定已提交ID且敌种唯一：" + row.enemy_id)
		unique[row.enemy_id] = true
	if not saved.pending_battle.is_empty():
		for row in recovery.preview_new(saved, saved.pending_battle.encounter_id, catalog):
			_expect(row.preview and row.battle_id == saved.pending_battle.battle_id and not unique.has(row.enemy_id), "真实待战预览与永久回收严格分开")
	_expect(saved == before and FileAccess.get_sha256(path) == before_hash, "真实查询不修改快照或原检查点字节")

func _integerize(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floor(value): return int(value)
	if value is Array:
		var result: Array = []
		for item in value: result.append(_integerize(item))
		return result
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = _integerize(value[key])
		return result
	return value
