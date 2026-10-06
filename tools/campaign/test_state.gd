# Only the isolation runner may execute these real storage/state transactions.
extends SceneTree
const Forms = preload("res://scripts/rpg/dual_form.gd")
const RpgCatalog = preload("res://scripts/rpg/catalog.gd")
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
const Campaign = preload("res://scripts/rpg/campaign.gd")
const SaveBase = preload("res://scripts/rpg/save_store.gd")
const Router = preload("res://scripts/rpg/encounter_router.gd")
const Session = preload("res://scripts/campaign/chapter_session.gd")
class FaultStore extends SaveBase:
	var fail_write := false
	var corrupt_write := false
	func _replace_file(temporary: String, destination: String) -> Error:
		return ERR_FILE_CANT_WRITE if fail_write else super._replace_file(temporary, destination)
	func _write_temporary(path: String, contents: String) -> Error:
		return super._write_temporary(path, "{broken" if corrupt_write else contents)
var failures: Array[String] = []
var assertions := 0
func expect(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1":
		printerr("FAIL: campaign tests require verified isolation")
		quit(1)
		return
	_test_registry()
	_test_connected_layout()
	_test_layout_surfaces()
	_test_clue_sources()
	_test_transactions()
	_test_legacy_duplicate_baseline()
	print("CAMPAIGN_STATE_ASSERTIONS: ", assertions)
	for failure in failures: printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
func _test_registry() -> void:
	var stages: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogues.json")).stages
	var reached := {}
	for id in range(1, 6):
		var night: Dictionary = Chapters.night(id)
		expect(night.night == id and night.scene_path == Chapters.scene_path(id), "registered five-night chapter %d" % id)
		expect(Chapters.validate_world(Chapters.initial_world(id)).is_empty(), "valid initial 3D world %d" % id)
		var roots: Array = [night.intro]
		for interaction in night.interactions:
			if not interaction.dialogue.is_empty(): roots.append(interaction.dialogue)
		for root_id in roots: _walk(root_id, stages[night.dialogue_stage].nodes, reached, night.dialogue_stops.get(root_id, ""))
		expect(not Chapters.complete(Chapters.initial_world(id)), "new chapter exit blocked %d" % id)
	expect(reached.size() == 38, "all 38 exploration nodes retain registered paths")
	var case_nodes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Chapters.CASE_PATH)).nodes
	var endings := {}
	_walk("t1", case_nodes, endings)
	expect(endings.size() == 14, "all 14 ending nodes reachable")
	expect(Chapters.night(0).is_empty() and Chapters.night(12).is_empty(), "unregistered chapters rejected")
	var invalid := Chapters.initial_world(1)
	invalid.position[0] = 100000
	expect(not Chapters.validate_world(invalid).is_empty(), "out-of-bounds position rejected")
	invalid = Chapters.initial_world(1)
	invalid.scene_id = "night_2"
	expect(not Chapters.validate_world(invalid).is_empty(), "wrong chapter scene rejected")
	invalid = Chapters.initial_world(2)
	invalid.event_flags["ritual:guide"] = true
	expect(not Chapters.validate_world(invalid).is_empty(), "out-of-order ritual flags rejected")
# 新地图标志缺失、坐标重复偏移或放宽旧局部边界均应使这些断言失败。
const ACT_ONE_LAYOUT_ID := "act_one_connected_v1"
const NIGHT_OFFSETS := [[0.0, 0.0, 0.0], [25.0, 2.86, -7.0], [43.0, 2.86, 4.0], [43.0, 2.86, -13.0], [61.0, 2.86, -5.0]]
func _offset_position(position: Array, night_id: int, direction: float = 1.0) -> Array:
	var offset: Array = NIGHT_OFFSETS[night_id - 1]
	return [position[0] + direction * offset[0], position[1] + direction * offset[1], position[2] + direction * offset[2]]
func _position_close(left: Array, right: Array) -> bool:
	return Vector3(left[0], left[1], left[2]).is_equal_approx(Vector3(right[0], right[1], right[2]))
func _old_world(world: Dictionary) -> Dictionary:
	var legacy := world.duplicate(true)
	if legacy.get("map_layout") == ACT_ONE_LAYOUT_ID:
		legacy.position = _offset_position(legacy.position, legacy.night, -1.0)
		legacy.player_x = legacy.position[0]
	legacy.erase("map_layout")
	return legacy
func _test_connected_layout() -> void:
	for id in range(1, 6):
		var world := Chapters.initial_world(id)
		var definition := Chapters.night(id)
		expect(world.get("map_layout") == ACT_ONE_LAYOUT_ID, "新世界显式登记连续地图 %d" % id)
		expect(definition.bounds.x == [-9.05, 68.0] and definition.bounds.z == [-18.0, 11.0], "每夜共用全图边界 %d" % id)
		if id > 1:
			expect(_position_close(definition.anchors.spawn, _offset_position([-4.7, 0.0, 1.0], id)), "每夜安全锚点只做一次全图变换 %d" % id)
			expect(_position_close(definition.interactions[-1].position, _offset_position([4.5, 0.0, 0.0], id)), "出口调查坐标全图变换 %d" % id)
		var old := _old_world(world)
		old.position = [0.25, 0.04, 0.8]
		old.player_x = 0.25
		old.facing = -1
		old.event_flags["dialogue:" + definition.intro] = true
		old.dlg_fired[definition.intro] = true
		old["extension"] = {"camera_size": 8.0, "annotation": "旧档扩展保留"}
		var migrated := Chapters.normalize(old)
		expect(migrated.get("map_layout") == ACT_ONE_LAYOUT_ID and Chapters.validate_world(migrated).is_empty(), "合法旧局部世界可迁移 %d" % id)
		expect(_position_close(migrated.position, _offset_position(old.position, id)) and is_equal_approx(migrated.player_x, migrated.position[0]), "旧档位置和横坐标同步迁移 %d" % id)
		for field in ["facing", "event_flags", "resolved", "dlg_fired", "extension", "return_anchor"]:
			expect(migrated[field] == old[field], "坐标迁移保留已有内容 %d/%s" % [id, field])
		expect(Chapters.normalize(migrated) == migrated, "连续地图重复normalize不二次偏移 %d" % id)
		old.position[0] = 20.0
		old.player_x = 20.0
		var rejected := Chapters.normalize(old)
		expect(not Chapters.validate_world(rejected).is_empty() and not rejected.has("map_layout"), "旧局部越界不能因大图边界放宽变合法 %d" % id)
		for unknown in ["future_layout", "", null, 9, false]:
			var unsupported := world.duplicate(true)
			unsupported["map_layout"] = unknown
			expect(not Chapters.validate_world(Chapters.normalize(unsupported)).is_empty(), "未知或畸形布局拒绝 %d/%s" % [id, str(unknown)])
	var early := Chapters.initial_world(1)
	early.position = _offset_position([0.0, 0.04, 0.0], 5)
	early.player_x = early.position[0]
	expect(Chapters.validate_world(early).is_empty() and not Chapters.complete(early), "首夜允许走到本殿但不自动消耗剧情")
func _test_layout_surfaces() -> void:
	var path := "res://scripts/campaign/act_one_layout.gd"
	expect(ResourceLoader.exists(path), "连续地图登记模块必须存在")
	if not ResourceLoader.exists(path): return
	var layout = load(path)
	for id in range(1, 6):
		var offset: Vector3 = layout.night_offset(id)
		expect(offset.is_equal_approx(Vector3(NIGHT_OFFSETS[id - 1][0], NIGHT_OFFSETS[id - 1][1], NIGHT_OFFSETS[id - 1][2])), "布局与旧档迁移共享唯一区域偏移 %d" % id)
		expect(Chapters.night(id).bounds == layout.bounds(), "地图登记为夜次边界唯一来源 %d" % id)
	expect(layout.region_at(Vector3(-4.0, 0.04, 1.0)) == "approach", "原上山路有独立地区")
	expect(layout.region_at(Vector3(15.0, 2.9, 2.0)) == "forecourt", "山门接真实前庭")
	for entry in [{"region": "corridor", "point": Vector3(25, 2.9, -7)}, {"region": "procession", "point": Vector3(43, 2.9, 4)}, {"region": "mirror", "point": Vector3(43, 2.9, -13)}, {"region": "honden", "point": Vector3(61, 2.9, -5)}]:
		expect(layout.region_at(entry.point) == entry.region, "地理地区独立于当前故事：" + entry.region)
		expect(is_equal_approx(layout.surface_height(entry.point), 2.89), "寺内统一地面：" + entry.region)
	expect(is_equal_approx(layout.surface_height(Vector3(-4, 0, 1)), 0.03), "保留原山路低地面")
	expect(is_equal_approx(layout.surface_height(Vector3(8.65, 0, 0.35)), 2.89), "保留原山门平台高度")
	expect(layout.surface_height(Vector3(4, 0, 0)) > 1.0 and layout.surface_height(Vector3(4, 0, 0)) < 2.0, "原上山路仍为连续坡度")
	expect(is_nan(layout.surface_height(Vector3(-20, 0, 0))) and layout.region_at(Vector3(-20, 0, 0)).is_empty(), "地图外不伪造地面")
	var surfaces: Array = layout.walk_rects()
	expect(surfaces.size() == 8, "八块真实可走寺内地面")
	var connected := {"forecourt": true}
	for pass_index in range(surfaces.size()):
		for left in surfaces:
			for right in surfaces:
				if connected.has(left.id) and left.rect.intersects(right.rect, true): connected[right.id] = true
	expect(connected.size() == surfaces.size(), "全部寺内区域的矩形实际连通，不靠传送")
func _walk(id: String, nodes: Dictionary, reached: Dictionary, stop: String = "") -> void:
	if id.is_empty() or reached.has(id): return
	expect(nodes.has(id), "registered dialogue reference exists: " + id)
	if not nodes.has(id): return
	reached[id] = true
	if id == stop: return
	_walk(str(nodes[id].get("next", "")), nodes, reached, stop)
	for choice in nodes[id].get("choices", []): _walk(str(choice.next), nodes, reached, stop)
func _raw(path: String, contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents)
	file.close()
func _victory(campaign: RefCounted, started: Dictionary) -> Dictionary:
	var roster: Array[Dictionary] = []
	for id in campaign.safe_snapshot().party: roster.append(started.setup.actors[id].duplicate(true))
	return {"battle_id": started.battle_id, "outcome": "victory", "roster": roster, "inventory": started.setup.inventory.duplicate(true), "xp": started.xp, "story_patch": started.story_patch.duplicate(true), "replay": {}}
func _test_pending_layout_migration(snapshot: Dictionary, store: RefCounted) -> void:
	var disk := FileAccess.get_file_as_string(Chapters.SAVE_PATH)
	var old := snapshot.duplicate(true)
	old.world = _old_world(old.world)
	for key in old.world_history: old.world_history[key] = _old_world(old.world_history[key])
	_raw(Chapters.SAVE_PATH, JSON.stringify(old))
	var router := Router.new(Campaign.new(null, null, Chapters.SAVE_PATH))
	var loaded: Dictionary = router.load_safe_run()
	expect(loaded.ok and loaded.get("pending_battle", false) and loaded.get("next_scene") == "res://scenes/rpg/battle.tscn", "旧战前档通过真实Router续接战斗")
	if loaded.ok:
		var migrated: Dictionary = router.campaign.safe_snapshot()
		expect(migrated.world.get("map_layout") == ACT_ONE_LAYOUT_ID and _position_close(migrated.world.position, _offset_position(old.world.position, old.world.night)), "Router战前世界一次迁移至对应大地图区")
		expect(migrated.pending_battle == snapshot.pending_battle and migrated.roster == snapshot.roster and migrated.xp == snapshot.xp and migrated.applied_battle_ids == snapshot.applied_battle_ids, "旧战前迁移保留seed、战果、资源与奖励记录")
		expect(store.normalize(migrated) == migrated, "整档重复规范化幂等")
		for key in migrated.world_history:
			expect(migrated.world_history[key].get("map_layout") == ACT_ONE_LAYOUT_ID, "历史世界也同步迁移 " + key)
		var malformed := old.duplicate(true)
		malformed.world_history.night_1.position = [20.0, 0.04, 0.8]
		expect(not store.validate(store.normalize(malformed)).is_empty(), "畸形历史旧局部坐标不能被全图救活")
		malformed = old.duplicate(true)
		malformed.world_history.night_1["map_layout"] = "future_layout"
		expect(not store.validate(store.normalize(malformed)).is_empty(), "未知历史地图布局拒绝")
		var migrated_result := _victory(router.campaign, router.campaign.retry_battle())
		var completed: Dictionary = router.finish(migrated_result)
		expect(completed.ok and completed.get("world", {}).get("position") == migrated.world.position and completed.get("world", {}).get("facing") == migrated.world.facing, "旧档迁移后战胜仍返回原战前真实坐标")
		if completed.ok:
			var active_router: RefCounted = Router.session
			Router.activate(router)
			var returned := Router.take_world(migrated.world.scene_path)
			expect(returned.position == migrated.world.position and returned.get("map_layout") == ACT_ONE_LAYOUT_ID, "Router返场交接传递新地图与原位置")
			expect(Router.take_world(migrated.world.scene_path).is_empty(), "战斗返场世界只能领取一次")
			Router.activate(active_router)
			var after: Dictionary = router.campaign.safe_snapshot()
			expect(router.finish(migrated_result).ok and router.campaign.safe_snapshot().xp == after.xp and router.campaign.safe_snapshot().applied_battle_ids == after.applied_battle_ids, "旧档迁移战果重复交付不重复奖励")
	_raw(Chapters.SAVE_PATH, disk)
func _test_transactions() -> void:
	_raw("user://rpg_v1/old_trial.json", "old trial stays unchanged")
	_raw("user://save.json", "old cards stay unchanged")
	var store := FaultStore.new()
	var campaign := Campaign.new(null, store, Chapters.SAVE_PATH)
	var session := Session.new(campaign)
	var created: Dictionary = session.start_new(false)
	expect(created.ok, "formal new run writes schema2 isolated slot")
	if not created.ok: return
	var safe: Dictionary = campaign.safe_snapshot()
	expect(safe.schema_version == 2 and safe.world.world_version == 3 and safe.world.night == 1, "schema2 starts in first 3D chapter")
	expect(safe.roster.size() == 6 and safe.roster.p_mage.identity_id == "homura" and safe.roster.p_mage.form_id == "sword" and safe.roster.p_mage.get("active_class_id") == "swordsman" and safe.roster.p_mage.get("unlocked_forms") == ["sword"], "six identities share canonical forms")
	expect(not session.start_new(false).ok and campaign.safe_snapshot() == safe, "existing valid formal run requires replace confirmation")
	expect(not session.commit_event(safe.world, "battle:cleared").ok, "scene cannot forge victory")
	expect(not session.commit_event(safe.world, "unknown").ok, "unknown event rejected")
	expect(not session.begin_encounter(safe.world, "unknown").ok, "unknown encounter does not fall back")
	expect(not session.advance_night(safe.world).ok, "cannot skip required events")
	var first_world: Dictionary = safe.world.duplicate(true)
	first_world.position = [0.2, 0.04, 0.4]
	first_world["extension"] = {"camera_size": 8.0}
	expect(session.save_world(first_world).ok, "safe position preserves valid world extension")
	expect(campaign.safe_snapshot().world.extension == first_world.extension, "unknown valid world fields retained")
	var forged: Dictionary = campaign.safe_snapshot().world
	forged.event_flags["dialogue:a1"] = true
	forged.dlg_fired["a1"] = true
	expect(not session.save_world(forged).ok, "save position cannot mutate story")
	var disk := FileAccess.get_file_as_string(Chapters.SAVE_PATH)
	store.fail_write = true
	expect(not session.commit_event(campaign.safe_snapshot().world, "dialogue:a1").ok, "failed dialogue checkpoint reported")
	expect(FileAccess.get_file_as_string(Chapters.SAVE_PATH) == disk and not campaign.safe_snapshot().world.event_flags.has("dialogue:a1"), "failed event keeps disk and memory unchanged")
	store.fail_write = false
	store.corrupt_write = true
	expect(not session.commit_event(campaign.safe_snapshot().world, "dialogue:a1").ok and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == disk, "corrupt temporary write preserves slot")
	store.corrupt_write = false
	expect(not campaign.set_form("p_mage", "mage").ok, "new run cannot select locked mage form")
	var forged_unlock: Dictionary = campaign.safe_snapshot()
	forged_unlock.roster.p_mage.unlocked_forms = ["sword", "mage"]
	expect(not store.validate(forged_unlock).is_empty(), "mage unlock cannot be forged before first-night victory")
	var total_xp := 0
	for id in range(1, 6):
		var world: Dictionary = campaign.safe_snapshot().world
		expect(world.night == id, "chapter progresses one night at a time %d" % id)
		for event in Chapters.events(id):
			if event == "dialogue:hd5" or event.begins_with("ritual:"): continue
			expect(session.commit_event(campaign.safe_snapshot().world, event).ok, "dialogue root checkpoint " + event)
		var stale_event := Campaign.new(null, null, Chapters.SAVE_PATH)
		expect(stale_event.load_run().ok, "capture repeated-event checkpoint")
		var event_world: Dictionary = stale_event.safe_snapshot().world
		var event_update: Dictionary = campaign.safe_snapshot().world
		event_update.position[0] += 0.03
		expect(session.save_world(event_update).ok, "second model commits new event checkpoint position")
		var event_bytes := FileAccess.get_file_as_string(Chapters.SAVE_PATH)
		expect(not stale_event.commit_chapter_event(event_world, "dialogue:" + Chapters.night(id).intro).ok and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == event_bytes, "stale repeated event cannot claim current success")
		store.fail_write = true
		expect(session.commit_event(campaign.safe_snapshot().world, "dialogue:" + Chapters.night(id).intro).ok and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == event_bytes, "valid repeated event remains read-only idempotent")
		store.fail_write = false
		if id == 2:
			expect(not session.commit_event(campaign.safe_snapshot().world, "ritual:guide").ok, "ritual guide cannot precede place")
			expect(session.commit_event(campaign.safe_snapshot().world, "ritual:identify").ok, "identify saves first step")
			expect(campaign.safe_snapshot().story_phase == "ritual" and not campaign.safe_snapshot().world.resolved.has("coffin_sendoff"), "entering ritual is not completion")
			var continued := Session.new(Campaign.new(null, null, Chapters.SAVE_PATH))
			expect(continued.resume().ok and continued.campaign.safe_snapshot().world.event_flags.has("ritual:identify"), "partial ritual survives resume")
			expect(session.resume().ok, "reactivate original model from same saved ritual checkpoint")
			expect(session.commit_event(campaign.safe_snapshot().world, "ritual:place").ok, "place saves second step")
			expect(session.commit_event(campaign.safe_snapshot().world, "ritual:guide").ok, "guide saves third step")
			expect(campaign.safe_snapshot().world.resolved.has("coffin_sendoff"), "ritual clue completed only after guide")
		var world_before: Dictionary = campaign.safe_snapshot().world
		world_before.position = _offset_position([0.25, 0.04, 0.8], id) if world_before.has("map_layout") else [0.25, 0.04, 0.8]
		world_before.player_x = world_before.position[0]
		world_before.facing = -1 if id % 2 == 0 else 1
		store.fail_write = true
		var before_begin: Dictionary = campaign.safe_snapshot()
		expect(not session.begin_encounter(world_before, Chapters.night(id).clue_id).ok and campaign.safe_snapshot() == before_begin, "failed battle checkpoint cannot enter or count battle")
		store.fail_write = false
		var started: Dictionary = session.begin_encounter(world_before, Chapters.night(id).clue_id)
		expect(started.ok and started.battle_scene == "res://scenes/rpg/battle.tscn", "registered RPG battle begins night %d" % id)
		if not started.ok: return
		expect(not session.begin_encounter(world_before, Chapters.night(id).clue_id).ok, "double begin cannot reenter night %d" % id)
		for field in ["battle_id", "encounter_id", "seed", "xp", "story_patch"]:
			for wrong in [null, false, "bad", [], 0.5]:
				var malformed_pending: Dictionary = campaign.safe_snapshot()
				malformed_pending.pending_battle[field] = wrong
				expect(not store.validate(malformed_pending).is_empty(), "malformed formal pending rejects without crashing " + field + "/" + str(wrong))
		_test_pending_layout_migration(campaign.safe_snapshot(), store)
		var changed_seed: Dictionary = campaign.safe_snapshot()
		changed_seed.pending_battle.seed += 1
		expect(not store.validate(changed_seed).is_empty(), "saved retry seed cannot change from battle identity")
		var retry: Dictionary = campaign.retry_battle()
		expect(retry.battle_id == started.battle_id and retry.seed == started.seed, "retry keeps battle ID and seed night %d" % id)
		var reloaded := Session.new(Campaign.new(null, null, Chapters.SAVE_PATH))
		var resume_result: Dictionary = reloaded.resume()
		expect(resume_result.ok and resume_result.next_scene == "res://scenes/rpg/battle.tscn" and reloaded.campaign.retry_battle().seed == started.seed, "battle quit resumes same seeded prebattle snapshot")
		expect(session.resume().ok, "reactivate original same-seed battle session")
		var defeated := _victory(campaign, started)
		defeated.outcome = "defeat"
		defeated.xp = 0
		defeated.story_patch = {}
		var prebattle_form: String = campaign.safe_snapshot().roster.p_mage.form_id
		var selected_final_form := "mage" if prebattle_form == "sword" else "sword"
		var form_catalog := RpgCatalog.new()
		form_catalog.load_all()
		for actor in defeated.roster:
			actor.hp = 0
			if id >= 2 and actor.actor_id == "p_mage": Forms.apply(actor, selected_final_form, form_catalog)
		var pre_defeat: Dictionary = campaign.safe_snapshot()
		expect(session.router.finish(defeated).ok and campaign.safe_snapshot() == pre_defeat and not session.advance_night(campaign.safe_snapshot().world).ok, "defeat keeps prebattle resources and chapter locked")
		var retried_after_defeat: Dictionary = session.router.retry()
		expect(retried_after_defeat.seed == started.seed, "defeat retry uses identical seed")
		if id >= 2: expect(retried_after_defeat.setup.actors.p_mage.form_id == prebattle_form and retried_after_defeat.setup.actors.p_mage.skill_ids == started.setup.actors.p_mage.skill_ids, "defeat retry restores prebattle career and skills")
		var won := _victory(campaign, started)
		if id >= 2:
			for actor in won.roster:
				if actor.actor_id == "p_mage":
					Forms.apply(actor, selected_final_form, form_catalog)
					actor.hp -= 2
					actor.mp -= 3
		var before_result: Dictionary = campaign.safe_snapshot()
		store.fail_write = true
		expect(not session.router.finish(won).ok and campaign.safe_snapshot() == before_result, "failed reward write stays prebattle")
		if id == 1: expect(campaign.safe_snapshot().roster.p_mage.unlocked_forms == ["sword"], "failed first-night reward cannot unlock mage")
		store.fail_write = false
		var applied: Dictionary = session.router.finish(won)
		expect(applied.ok and applied.next_scene == Chapters.scene_path(id), "victory returns to same registered scene")
		if id >= 2:
			var persisted_actor: Dictionary = campaign.safe_snapshot().roster.p_mage
			expect(persisted_actor.form_id == selected_final_form and persisted_actor.active_class_id == Forms.FORM_CLASSES[selected_final_form] and persisted_actor.skill_ids == form_catalog.get_definition("classes", persisted_actor.active_class_id).skill_ids, "victory persists final actual career and four skills")
			expect(persisted_actor.hp == started.setup.actors.p_mage.hp - 2 and persisted_actor.mp == started.setup.actors.p_mage.mp - 3, "victory career change preserves earned HP/MP loss")
		total_xp += 120 if id == 5 else 40
		expect(campaign.safe_snapshot().xp == total_xp, "only approved encounter XP applied")
		expect(campaign.safe_snapshot().world.position == world_before.position and campaign.safe_snapshot().world.facing == world_before.facing, "大地图胜利返场保留战前位置与朝向")
		expect(session.router.finish(won).ok and campaign.safe_snapshot().xp == total_xp, "duplicate results are idempotent")
		expect(reloaded.router.finish(won).ok and reloaded.campaign.safe_snapshot().xp == total_xp, "second loaded instance cannot duplicate rewards")
		if id >= 2: expect(reloaded.campaign.safe_snapshot().roster.p_mage.form_id == selected_final_form, "persisted winning career survives disk reload")
		if id == 1:
			expect(campaign.safe_snapshot().roster.p_mage.get("unlocked_forms") == ["sword", "mage"] and applied.get("unlocked_forms") == ["mage"], "first-night committed victory unlocks mage with one system result")
			expect(session.router.has_method("take_unlocked_forms") and session.router.call("take_unlocked_forms") == ["mage"] and session.router.call("take_unlocked_forms").is_empty(), "committed first-night unlock announcement consumed once")
			expect(not session.router.finish(won).has("unlocked_forms"), "duplicate reward does not repeat form-unlock announcement")
			_test_unlocked_form(campaign, store)

		if id == 5:
			expect(not session.choose_resolution(campaign.safe_snapshot().world, "sendoff").ok, "ending waits for returned gatekeeper dialogue")
			expect(session.commit_event(campaign.safe_snapshot().world, "dialogue:hd5").ok, "hd5 checkpoint only after boss victory")
		var current_world: Dictionary = campaign.safe_snapshot().world
		store.fail_write = true
		expect(not session.advance_night(current_world).ok and campaign.safe_snapshot().world.night == id, "failed chapter transition keeps old night")
		store.fail_write = false
		var advanced: Dictionary = session.advance_night(current_world)
		expect(advanced.ok and campaign.safe_snapshot().world.night == mini(id + 1, 5), "one atomic next-night transition")
		if id < 5:
			expect(campaign.safe_snapshot().world.position == current_world.position and campaign.safe_snapshot().world.facing == current_world.facing, "同地图推进夜次不能传送玩家")
			expect(not session.advance_night(current_world).ok, "stale/double exit cannot skip a night")
			expect(campaign.safe_snapshot().world_history.has("night_%d" % id), "previous scene checkpoint retained")
	var completed_five: Dictionary = campaign.safe_snapshot()
	expect(completed_five.story_phase == "ending" and completed_five.xp == 280, "five nights yield 280 XP and ending phase")
	for resolution in ["sendoff", "seal_monitoring"]:
		# Each branch uses its own valid copy of the same earned checkpoint in this isolated directory.
		if resolution == "seal_monitoring":
			expect(store.write_safe(completed_five, Chapters.SAVE_PATH) == OK, "restore earned branch checkpoint")
			expect(campaign.load_run().ok, "reload earned branch checkpoint")
		store.fail_write = true
		expect(not session.choose_resolution(campaign.safe_snapshot().world, resolution).ok and campaign.safe_snapshot().resolution == "", "failed resolution save leaves choice unset")
		store.fail_write = false
		expect(session.choose_resolution(campaign.safe_snapshot().world, resolution).ok, "choice saved before branch animation")
		var expected_status := "closed" if resolution == "sendoff" else "monitoring"
		expect(campaign.safe_snapshot().resolution == resolution and campaign.safe_snapshot().case_status == expected_status, "ending semantic case status")
		var chosen_resume := Session.new(Campaign.new(null, null, Chapters.SAVE_PATH))
		expect(chosen_resume.resume().ok and chosen_resume.campaign.safe_snapshot().resolution == resolution, "choice survives restart before branch end")
		expect(session.resume().ok, "reactivate chosen branch session")
		expect(not session.choose_resolution(campaign.safe_snapshot().world, "seal_monitoring" if resolution == "sendoff" else "sendoff").ok, "saved resolution cannot silently change")
		var stale_choice := Campaign.new(null, null, Chapters.SAVE_PATH)
		expect(stale_choice.load_run().ok, "capture repeated choice checkpoint")
		var choice_update: Dictionary = campaign.safe_snapshot().world
		choice_update.position[0] += 0.03
		expect(session.save_world(choice_update).ok, "second model commits new choice checkpoint position")
		var choice_bytes := FileAccess.get_file_as_string(Chapters.SAVE_PATH)
		expect(not stale_choice.choose_resolution(stale_choice.safe_snapshot().world, resolution).ok and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == choice_bytes, "stale repeated choice cannot claim current success")
		store.fail_write = true
		expect(session.choose_resolution(campaign.safe_snapshot().world, resolution).ok and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == choice_bytes, "valid repeated choice remains read-only idempotent")
		store.fail_write = false
		expect(session.finish_ending(campaign.safe_snapshot().world).ok and campaign.safe_snapshot().story_phase == "complete" and campaign.safe_snapshot().chapter_complete, "ending completion atomically recorded")
		expect(not session.advance_night(campaign.safe_snapshot().world).ok, "completed story cannot advance again")
		expect(not session.save_world(campaign.safe_snapshot().world).ok and campaign.safe_snapshot().return_scene == Chapters.ENDING_PATH, "complete checkpoint cannot reopen exploration")
	var valid := campaign.safe_snapshot()
	var stale_complete := Campaign.new(null, null, Chapters.SAVE_PATH)
	expect(stale_complete.load_run().ok, "capture repeated completion checkpoint")
	var complete_bytes := FileAccess.get_file_as_string(Chapters.SAVE_PATH)
	store.fail_write = true
	expect(session.finish_ending(campaign.safe_snapshot().world).ok and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == complete_bytes, "valid repeated completion remains read-only idempotent")
	store.fail_write = false
	for target in ["missing", "", Chapters.scene_path(5)]:
		var invalid_complete := valid.duplicate(true)
		if target == "missing": invalid_complete.erase("return_scene")
		else: invalid_complete.return_scene = target
		expect(not store.validate(invalid_complete).is_empty(), "complete checkpoint rejects inconsistent return scene " + target)
		expect(store.write_safe(invalid_complete, Chapters.SAVE_PATH) != OK and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == complete_bytes, "invalid complete write preserves valid ending slot " + target)
		_raw(Chapters.SAVE_PATH, JSON.stringify(invalid_complete))
		var invalid_bytes := FileAccess.get_file_as_string(Chapters.SAVE_PATH)
		expect(not session.resume().ok and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == invalid_bytes, "invalid complete resume fails without rewriting " + target)
		_raw(Chapters.SAVE_PATH, complete_bytes)
		var valid_resume: Dictionary = session.resume()
		expect(valid_resume.ok and valid_resume.next_scene == Chapters.ENDING_PATH, "valid complete resume reaches ending only")
	expect(not store.load_safe("user://campaign_v1/other.json").ok, "formal storage opens only exact approved slot")
	expect(store.write_safe(valid, "user://rpg_v1/formal.json") != OK, "schema2 cannot overwrite old profile directory")
	expect(FileAccess.get_file_as_string("user://rpg_v1/old_trial.json") == "old trial stays unchanged" and FileAccess.get_file_as_string("user://save.json") == "old cards stay unchanged", "old trial and card files unchanged")
	for field in ["story_phase", "night", "scene_id", "world_history", "resolution", "case_status", "chapter_complete", "campaign_id"]:
		for wrong in [null, false, "bad", [], 0.5]:
			var malformed := valid.duplicate(true)
			malformed[field] = wrong
			expect(not store.validate(malformed).is_empty(), "formal field wrong type/value rejected " + field + "/" + str(wrong))
	for field in ["position", "event_flags", "resolved", "dlg_fired", "return_anchor", "scene_id", "scene_path", "night", "world_version", "space", "facing"]:
		for wrong in [null, false, "bad", [], 0.5]:
			var malformed := valid.duplicate(true)
			malformed.world[field] = wrong
			malformed.world_history.night_5 = malformed.world.duplicate(true)
			expect(not store.validate(malformed).is_empty(), "formal world wrong type/value rejected " + field + "/" + str(wrong))
	var missing_unlock := valid.duplicate(true)
	missing_unlock.roster.p_mage.unlocked_forms = ["sword"]
	expect(not store.validate(missing_unlock).is_empty(), "earned mage unlock cannot disappear from formal save")
	var bad_history := valid.duplicate(true)
	bad_history.world_history.night_1 = false
	expect(not store.validate(bad_history).is_empty(), "form unlock proof rejects invalid night-one history without crashing")
	var mixed_world := valid.duplicate(true)
	mixed_world.world.world_version = false
	mixed_world.world.space = false
	mixed_world.world_history.night_5 = mixed_world.world.duplicate(true)
	expect(not store.validate(mixed_world).is_empty(), "mixed damaged formal world never reaches legacy validator")
	var mixed_profile := valid.duplicate(true)
	mixed_profile.run_profile = {"id": false, "bindings": []}
	expect(not store.validate(mixed_profile).is_empty(), "schema2 rejects injected legacy profile without legacy parsing")
	for wrong in [null, false, "", [], 0.5]:
		var malformed_applied := valid.duplicate(true)
		malformed_applied.applied_battle_ids[-1] = wrong
		expect(not store.validate(malformed_applied).is_empty(), "malformed applied ID rejects without crashing " + str(wrong))
	var invalid_resource := valid.duplicate(true)
	invalid_resource.xp += 1
	expect(not store.validate(invalid_resource).is_empty(), "formal XP must match exactly five committed encounters")
	var pending_copy := valid.duplicate(true)
	pending_copy.world_history.night_1.position[0] = 9999
	expect(not store.validate(pending_copy).is_empty(), "historical 3D checkpoints reject invalid positions")
	var stale_model := Campaign.new(null, null, Chapters.SAVE_PATH)
	expect(stale_model.load_run().ok, "capture valid completed model for stale duplicate test")
	var old_result := {"battle_id": valid.applied_battle_ids[-1]}
	expect(session.start_new(true).ok, "explicit replacement creates distinct new run")
	expect(not stale_model.apply_result(old_result).ok, "duplicate result from superseded run cannot return success")
	expect(not stale_complete.finish_ending(stale_complete.safe_snapshot().world).ok, "stale completed no-op cannot claim success after replacement")
	var bad := valid.duplicate(true)
	bad.schema_version = 99
	_raw(Chapters.SAVE_PATH, JSON.stringify(bad))
	var unknown := FileAccess.get_file_as_string(Chapters.SAVE_PATH)
	expect(not session.resume().ok and not session.start_new(true).ok and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == unknown, "unknown schema neither resumes nor overwrites")
	_raw(Chapters.SAVE_PATH, "{corrupt")
	expect(not session.resume().ok and not session.start_new(true).ok and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == "{corrupt", "corrupt slot preserved on resume/new")

func _test_clue_sources() -> void:
	var script = load("res://scripts/campaign/chapter_catalog.gd")
	expect(script.has_method("clue"), "catalog exposes original clue text without copying content")
	if not script.has_method("clue"): return
	for id in range(1, 6):
		var definition: Dictionary = Chapters.night(id)
		var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/clues/" + definition.dialogue_stage + ".json"))
		for original in source.clues:
			var exposed: Dictionary = script.clue(id, original.id)
			expect(exposed == original and not exposed.hint.is_empty() and not exposed.resolve_text.is_empty(), "original clue retained " + original.id)
	expect(script.clue(1, "unknown").is_empty(), "unregistered clue text rejected")

func _test_legacy_duplicate_baseline() -> void:
	var profile = load("res://scripts/exploration_3d/trial_profile.gd")
	var worlds = load("res://scripts/exploration_3d/world_snapshot.gd")
	var store := FaultStore.new()
	var path := "user://rpg_v1/tests/repeated_event_baseline.json"
	var active := Campaign.new(null, store, path)
	expect(active.new_run(profile.CLASS_IDS, 5, profile.make(worlds.initial({}))).ok, "legacy trial valid profile remains writable")
	expect(active.commit_world_event(active.safe_snapshot().world, "approach_entered").ok, "legacy event checkpoint committed")
	var stale := Campaign.new(null, null, path)
	expect(stale.load_run().ok, "legacy duplicate checkpoint read by second model")
	var moved: Dictionary = active.safe_snapshot().world
	moved.position[0] += 0.1
	moved.player_x = moved.position[0]
	expect(active.save_exploration(moved).ok, "legacy active model saves changed position")
	var durable_bytes := FileAccess.get_file_as_string(path)
	expect(not stale.commit_world_event(stale.safe_snapshot().world, "approach_entered").ok and FileAccess.get_file_as_string(path) == durable_bytes, "legacy stale event duplicate also checks durable baseline")
	store.fail_write = true
	expect(active.commit_world_event(active.safe_snapshot().world, "approach_entered").ok and FileAccess.get_file_as_string(path) == durable_bytes, "legacy legitimate repeated event stays read-only idempotent")

func _test_unlocked_form(campaign: RefCounted, store: RefCounted) -> void:
	var all_party: Array[String] = ["p_mage", "p_healer", "p_controller"]
	expect(campaign.set_party(all_party).ok and campaign.safe_snapshot().party == all_party, "all six identities available during formal exploration")
	var resources: Dictionary = campaign.safe_snapshot().roster.p_mage.duplicate(true)
	expect(campaign.set_form("p_mage", "sword").ok, "homura sword form saves atomically")
	expect(campaign.safe_snapshot().roster.p_mage.hp == resources.hp and campaign.safe_snapshot().roster.p_mage.mp == resources.mp and campaign.safe_snapshot().roster.p_mage.class_id == "mage", "form switch shares HP MP rules and actor identity")
	expect(not campaign.set_form("p_guard", "sword").ok and not campaign.set_form("p_mage", "homura_sword").ok, "form update restricted to canonical homura values")
	var saved_form: Dictionary = campaign.safe_snapshot()
	store.fail_write = true
	expect(not campaign.set_form("p_mage", "mage").ok and campaign.safe_snapshot() == saved_form, "failed form save does not publish form")
	store.fail_write = false
	var stale_form := Campaign.new(null, null, Chapters.SAVE_PATH)
	expect(stale_form.load_run().ok, "two models read same form checkpoint")
	var original_form: String = stale_form.safe_snapshot().roster.p_mage.form_id
	var other_form := "mage" if original_form == "sword" else "sword"
	expect(campaign.set_form("p_mage", other_form).ok, "second model commits changed form")
	var changed_form_bytes := FileAccess.get_file_as_string(Chapters.SAVE_PATH)
	expect(not stale_form.set_form("p_mage", original_form).ok and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == changed_form_bytes, "stale no-op form cannot claim success against changed durable form")
	store.fail_write = true
	expect(campaign.set_form("p_mage", other_form).ok and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == changed_form_bytes, "valid duplicate form remains read-only idempotent")
	store.fail_write = false
