extends RefCounted
const F = preload("res://tools/rpg/fixtures.gd")
const A = preload("res://tools/rpg/approach_fixtures.gd")
const Session = preload("res://scripts/exploration_3d/approach_session.gd")
const Router = preload("res://scripts/rpg/encounter_router.gd")
const World = preload("res://scripts/exploration_3d/world_snapshot.gd")
const BaseView = preload("res://scripts/rpg/ui/battle_view.gd")
const Policies = preload("res://tools/rpg/strategy_policies.gd")
const Portraits = preload("res://scripts/characters/identity_portraits.gd")
class BrokenBundle extends RefCounted:
	func prepare(_bindings: Dictionary) -> Dictionary: return {"ok": false, "error": "注入资源加载失败"}
	func clear() -> void: pass
class NavigationView extends BaseView:
	var destinations: Array[String] = []
	func _change_scene(path: String) -> Error:
		destinations.append(path)
		return OK
static func run() -> Array[String]:
	var failures: Array[String] = []
	var probe := Session.new(null, "user://rpg_v1/tests/loop_probe.json")
	F.expect(probe.has_method("begin_encounter"), "缺少试玩遭遇接口", failures)
	F.expect(probe.router.supports(World.SCENE_PATH, "res://scenes/rpg/battle.tscn", "basin_reflection"), "显式 3D 遭遇路由登记", failures)
	if not failures.is_empty(): return failures
	_test_route_boundaries(failures)
	await _test_victory(failures)
	await _test_defeat(failures)
	await _test_load_cancel(failures)
	await _test_view_integration(failures)
	await _test_view_recovery(failures)
	return failures
static func _session(path: String, store: RefCounted, failures: Array[String]) -> RefCounted:
	var session := Session.new(store, path)
	F.expect(session.start_new(false).ok, "闭环新局", failures)
	for event in ["approach_entered", "basin_observed", "basin_inspected"]:
		F.expect(session.commit_event(session.campaign.safe_snapshot().world, event).ok, "闭环事件前置", failures)
	return session
static func _test_victory(failures: Array[String]) -> void:
	var store := A.FailingStore.new()
	var path := "user://rpg_v1/tests/loop_victory.json"
	var session = _session(path, store, failures)
	var world: Dictionary = session.campaign.safe_snapshot().world
	world.position = [-1.2, 0.04, 0.55]
	world.player_x = -1.2
	world.facing = -1
	world.return_anchor = "basin_safe"
	world.camera = {"mode": "follow", "target": [-1.6, 1.3, 0.5], "size": 8.0}
	var before: Dictionary = session.campaign.safe_snapshot()
	var bytes := FileAccess.get_file_as_string(path)
	store.fail = true
	F.expect(not session.begin_encounter(world).ok and session.campaign.safe_snapshot() == before and FileAccess.get_file_as_string(path) == bytes, "进战写失败不半提交", failures)
	store.fail = false
	var started: Dictionary = session.begin_encounter(world)
	F.expect(started.ok and started.encounter_id == "approach_basin" and started.xp == 40, "本段登记遭遇与旧数值一致", failures)
	F.expect(not session.begin_encounter(world).ok, "双确认不能创建两场战斗", failures)
	var pending: Dictionary = session.campaign.safe_snapshot()
	for malformed in ["bad", [], null]:
		var bad: Dictionary = pending.duplicate(true)
		bad.world = malformed
		F.expect(not store.validate(bad).is_empty(), "损坏待战世界安全拒绝而非脚本崩溃", failures)
	session.bundle = BrokenBundle.new()
	F.expect(not (await session.prepare_assets()).ok and session.campaign.safe_snapshot() == pending, "资源失败保留同一待战 ID 与种子", failures)
	session.bundle = preload("res://scripts/characters/party_asset_bundle.gd").new()
	F.expect((await session.prepare_assets()).ok, "原待战上下文可重新加载", failures)
	var weak: WeakRef = weakref(session.bundle.get_definition("rinne").frames.get_frame_texture("idle", 0))
	var engine: RefCounted = session.router.create_engine()
	var count := _finish_model(engine, false)
	F.expect(count > 0 and engine.snapshot().outcome == "victory", "真实三人引擎完成胜利", failures)
	var result: Dictionary = session.router.result_from_engine()
	store.fail = true
	F.expect(not session.router.finish(result).ok and session.campaign.safe_snapshot() == pending and not session.campaign.safe_snapshot().world.event_flags.has("basin_cleared"), "胜利保存失败不发 XP 或开出口", failures)
	store.fail = false
	var finished: Dictionary = session.router.finish(result)
	F.expect(finished.ok and finished.next_scene == World.SCENE_PATH, "胜利正确导航返场", failures)
	var safe: Dictionary = session.campaign.safe_snapshot()
	F.expect(safe.xp == 40 and safe.world.position == world.position and safe.world.camera == world.camera and safe.world.facing == world.facing, "胜利精确恢复位置朝向镜头与 40 XP", failures)
	F.expect(safe.world.event_flags.has("basin_cleared") and safe.world.resolved == {"basin_reflection": true} and safe.inventory == result.inventory, "仅提交本场标记与实际库存", failures)
	for actor in result.roster:
		F.expect(safe.roster[actor.actor_id].hp == actor.hp and safe.roster[actor.actor_id].mp == actor.mp, "返场继承本场 HP/MP", failures)
	var duplicate: Dictionary = session.router.finish(result)
	F.expect(duplicate.ok and duplicate.already_applied and duplicate.get("next_scene") == World.SCENE_PATH and session.campaign.safe_snapshot() == safe, "重复战果不重复奖励且仍可导航", failures)
	F.expect(Router.take_world(World.SCENE_PATH) == safe.world and Router.take_world(World.SCENE_PATH).is_empty(), "返场快照只消费一次", failures)
	F.expect(weak.get_ref() != null, "探索战斗返场资源强引用保持", failures)
	session.close()
	await (Engine.get_main_loop() as SceneTree).process_frame
	F.expect(weak.get_ref() == null, "退出试玩释放纹理", failures)
static func _test_defeat(failures: Array[String]) -> void:
	var path := "user://rpg_v1/tests/loop_defeat.json"
	var session = _session(path, null, failures)
	var world: Dictionary = session.campaign.safe_snapshot().world
	var start: Dictionary = session.begin_encounter(world)
	var safe: Dictionary = session.campaign.safe_snapshot()
	var engine: RefCounted = session.router.create_engine()
	_finish_model(engine, true)
	F.expect(engine.snapshot().outcome == "defeat", "真实持续防御直到败北", failures)
	F.expect(session.router.finish(session.router.result_from_engine()).ok and session.campaign.safe_snapshot() == safe, "败北不写资源剧情", failures)
	var retry: Dictionary = session.router.retry()
	F.expect(retry.battle_id == start.battle_id and retry.seed == start.seed and retry.setup == start.setup and retry.world == world, "败北恢复同条件，不赠药治疗", failures)
	session.close()
	var resumed := Session.new(null, path)
	var loaded := resumed.resume()
	F.expect(loaded.ok and loaded.pending_battle and loaded.next_scene == "res://scenes/rpg/battle.tscn" and resumed.router._setup.battle_id == start.battle_id and resumed.router._setup.seed == start.seed, "战中退出再续回同一战前档", failures)
	resumed.close()
static func _test_load_cancel(failures: Array[String]) -> void:
	var session = _session("user://rpg_v1/tests/loop_cancel.json", null, failures)
	var callback := func(_done, _total): session.close()
	session.bundle.progress.connect(callback)
	var bundle: RefCounted = session.bundle
	var result: Dictionary = await session.prepare_assets()
	bundle.progress.disconnect(callback)
	F.expect(not result.ok and result.get("cancelled", false) and Session.current == null and Router.session == null, "close 后异步资源不得激活旧会话", failures)
static func _finish_model(engine: RefCounted, passive: bool) -> int:
	var policy := Policies.new()
	var count := 0
	while engine.snapshot().outcome.is_empty() and count < 300:
		engine.advance()
		var state: Dictionary = engine.snapshot()
		if not state.outcome.is_empty(): break
		var command: Dictionary
		if passive:
			command = {"command_id": "defeat_%d" % count, "expected_revision": state.revision, "actor_id": state.active_actor_id, "kind": "defend", "ability_id": "", "target_ids": []}
		else:
			command = policy.choose("direct_damage", state, engine)
		if command.is_empty() or not engine.submit(command).accepted: break
		count += 1
	return count

static func _test_view_integration(failures: Array[String]) -> void:
	var View = load("res://scripts/rpg/ui/battle_view.gd")
	var probe = View.new()
	F.expect(probe.has_method("_await_presentation"), "战斗视图必须等待真实演出队列", failures)
	if not probe.has_method("_await_presentation"):
		probe.free()
		return
	probe.free()
	F.expect(FileAccess.file_exists("res://scripts/rpg/ui/legacy_actor_view.gd"), "敌方普通形象必须进入同一有序表现队列", failures)
	if not FileAccess.file_exists("res://scripts/rpg/ui/legacy_actor_view.gd"): return
	var session = _session("user://rpg_v1/tests/loop_view.json", null, failures)
	F.expect(session.begin_encounter(session.campaign.safe_snapshot().world).ok and (await session.prepare_assets()).ok, "实际战斗视图上下文", failures)
	var tree: SceneTree = Engine.get_main_loop()
	var view = View.new()
	view.router = session.router
	tree.root.add_child(view)
	await _wait_view(view, tree)
	F.expect(view._hd_views.size() == 3 and not view.processing, "实际BattleView挂接三人HD并开放输入", failures)
	for id in session.campaign.safe_snapshot().party:
		var identity: String = session.campaign.safe_snapshot().roster[id].identity_id
		var avatar: TextureRect = view._actors[id].avatar
		F.expect(avatar.texture is AtlasTexture and avatar.get_meta("identity_id", "") == identity and avatar.texture.atlas.get_rid() == Portraits.load_idle_definition(identity).frames.get_frame_texture("idle", 0).get_rid(), "实际战斗卡头像按身份共享批准静态原图：" + identity, failures)
	F.expect(view._presentation_views.size() == 5, "全体五名参战者受同一事件时序约束", failures)
	var enemy = view._presentation_views.e_01_hound
	view.select_command("attack_physical")
	view.select_target("e_01_hound")
	view.confirm_command()
	await tree.process_frame
	F.expect(enemy.feedback_label.text.is_empty(), "敌方伤害飘字不能抢在我方HD出招前播放", failures)
	var revision: int = view.engine.snapshot().revision
	view.confirm_command()
	F.expect(view.processing and view.engine.snapshot().revision == revision, "动画期间双确认不重复提交模型", failures)
	await _wait_view(view, tree)
	F.expect(not view.processing and not view._hd_player.is_busy(), "队列drained后开放下一命令", failures)
	view.select_command("defend")
	view.confirm_command()
	view.queue_free()
	await tree.process_frame
	await tree.create_timer(0.25).timeout
	session.close()
static func _wait_view(view: Node, tree: SceneTree) -> void:
	for index in range(1200):
		if not view.processing: return
		await tree.process_frame

static func _test_route_boundaries(failures: Array[String]) -> void:
	var session := Session.new(null, "user://rpg_v1/tests/route_forged.json")
	session.start_new(false)
	var forged: Dictionary = session.campaign.safe_snapshot().world
	forged.event_flags = {"approach_entered": true, "basin_observed": true, "basin_inspected": true}
	forged.dlg_fired = {"a1": true, "h1": true}
	F.expect(not session.begin_encounter(forged).ok, "合法形状也不能伪造未持久化的剧情前置", failures)
	session.close()
	var Campaign = load("res://scripts/rpg/campaign.gd")
	var campaign = Campaign.new(null, null, "user://rpg_v1/tests/route_legacy.json")
	var classes: Array[String] = ["guard", "swordsman", "healer"]
	campaign.new_run(classes)
	var world := {"scene_path": "res://scenes/v3/stage.tscn", "player_x": 735.5, "facing": -1, "resolved": {}, "dlg_fired": {}, "exit_prompted": false, "spirit": 2, "party_index": 0}
	F.expect(not campaign.begin_battle("approach_basin", world).ok, "试玩遭遇不能与旧二维世界混搭", failures)
	campaign.new_run(classes)
	var router := Router.new(campaign)
	var destination := "res://scenes/v3/stage_corridor.tscn"
	var started: Dictionary = campaign.begin_battle("slice_1", world, {"next_scene": destination})
	router.adopt_battle(started)
	_finish_model(router.create_engine(), false)
	var result: Dictionary = router.result_from_engine()
	F.expect(router.finish(result).get("next_scene") == destination, "旧出口补丁首次目的地", failures)
	F.expect(router.finish(result).get("next_scene") == destination, "旧出口补丁重复提交保留持久目的地", failures)

static func _test_view_recovery(failures: Array[String]) -> void:
	var probe := BaseView.new()
	F.expect(probe.has_method("_change_scene"), "结果导航需有可测且能报告失败的边界", failures)
	if not probe.has_method("_change_scene"):
		probe.free()
		return
	probe.free()
	var tree: SceneTree = Engine.get_main_loop()
	var store := A.FailingStore.new()
	var session = _session("user://rpg_v1/tests/view_result_recovery.json", store, failures)
	session.begin_encounter(session.campaign.safe_snapshot().world)
	await session.prepare_assets()
	var view := NavigationView.new()
	view.router = session.router
	tree.root.add_child(view)
	await _wait_view(view, tree)
	view._cancel_presentation()
	_finish_model(view.engine, false)
	store.fail = true
	view._check_result()
	F.expect(view._result.visible and not view.result_saved and view._hud.result_action.text.contains("重试保存") and session.campaign.safe_snapshot().xp == 0, "真实结果UI保存失败保留战果可重试", failures)
	view._return_title()
	var warning := ""
	for child in view._exit_confirmation.get_children():
		if child is Label: warning += child.text
	F.expect(warning.contains("丢失本场未提交战果"), "真实结果UI退出明确警告未提交战果", failures)
	view._cancel_return_title()
	store.fail = false
	view._result_action()
	F.expect(view.result_saved and session.campaign.safe_snapshot().xp == 40, "真实结果按钮重试提交只得40XP", failures)
	view._result_action()
	view._result_action()
	F.expect(view.destinations == [World.SCENE_PATH], "真实结果返回按钮只导航一次且目的地正确", failures)
	view.queue_free()
	await tree.process_frame
	session.close()
	var resource_session = _session("user://rpg_v1/tests/view_asset_recovery.json", null, failures)
	resource_session.begin_encounter(resource_session.campaign.safe_snapshot().world)
	var before: Dictionary = resource_session.campaign.safe_snapshot()
	var asset_view := NavigationView.new()
	asset_view.router = resource_session.router
	tree.root.add_child(asset_view)
	F.expect(asset_view._hd_failed and asset_view._asset_error_panel.visible and asset_view.processing and asset_view.engine.snapshot().revision == 0, "高清装配失败真实UI保持锁定且不推进模型", failures)
	await asset_view._retry_hd_assets()
	await _wait_view(asset_view, tree)
	F.expect(not asset_view._hd_failed and not asset_view.processing and resource_session.campaign.safe_snapshot() == before, "高清错误UI重试恢复同一待战数据", failures)
	asset_view.queue_free()
	await tree.process_frame
	resource_session.close()
