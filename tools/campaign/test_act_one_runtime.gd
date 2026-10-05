# 真实主线会话与地图舞台集成；不把伪造完整战斗当作人工通关。
extends SceneTree
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
const Session = preload("res://scripts/campaign/chapter_session.gd")
var failures: Array[String] = []
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); printerr("ASSERT FAIL: ", message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _silence(stage: Node) -> void:
	stage._generation += 1
	if is_instance_valid(stage._dialogue): stage._dialogue.abort(); stage._dialogue.queue_free()
	stage._dialogue = null
	stage._arrival_checked = true
	stage._resume_explore()
func _run() -> void:
	check(ResourceLoader.exists("res://scripts/campaign/act_one_geometry.gd"), "连续地图真实物理几何必须存在")
	if not ResourceLoader.exists("res://scripts/campaign/act_one_geometry.gd"): quit(1); return
	var session := Session.new()
	check(session.start_new(true).ok, "真实新游戏创建")
	check((await session.prepare_assets()).ok, "沿用正式人物资源装配")
	var stage: Node3D = load(Catalog.scene_path(1)).instantiate()
	root.add_child(stage)
	for frame in 5: await physics_frame
	check(stage.ready_for_play and stage._mode == "dialogue", "上山路新游戏保留原开场")
	_silence(stage)
	var map_before: Dictionary = stage.export_world()
	stage._open_map()
	check(stage._mode == "map" and not stage.controls_enabled and stage._modal.get_node_or_null("WorldMapView") != null, "地图总览显示真实地区并暂停行走")
	var key := InputEventAction.new(); key.action = "approach_map"; key.pressed = true
	stage._unhandled_input(key)
	check(stage._mode == "explore" and stage.controls_enabled and stage.export_world() == map_before, "M关闭总览不传送、不写剧情")
	var player_id: int = stage.player.get_instance_id()
	var geometry_id: int = stage._geometry.get_instance_id()
	var world: Dictionary = stage.export_world()
	world.position = [20.0, 2.89, 4.0]
	var restored: Dictionary = stage.restore_world(world)
	check(restored.ok and not restored.used_fallback, "第一夜可自由进入山门后庭院")
	stage._confirm_armed = true
	check(not stage.request_interaction("exit"), "自由入庭不跳过第一夜必需剧情")
	for event in Catalog.events(1):
		var committed: Dictionary = session.commit_event(stage.export_world(), event)
		check(committed.ok, "原第一夜事件合法提交：" + event)
		stage.apply_committed_world(committed.world)
	var encounter: Dictionary = session.begin_encounter(stage.export_world(), Catalog.night(1).clue_id)
	check(encounter.ok, "仍经原统一RPG入口")
	var roster: Array[Dictionary] = []
	for id in session.campaign.safe_snapshot().party: roster.append(encounter.setup.actors[id].duplicate(true))
	var result := {"battle_id": encounter.battle_id, "outcome": "victory", "roster": roster, "inventory": encounter.setup.inventory.duplicate(true), "xp": encounter.xp, "story_patch": encounter.story_patch.duplicate(true), "replay": {}}
	var returned: Dictionary = session.router.finish(result)
	check(returned.ok and Vector3(returned.world.position[0], returned.world.position[1], returned.world.position[2]).distance_to(Vector3(world.position[0], world.position[1], world.position[2])) < 0.001, "战果事务保留真实所在庭院位置")
	stage.apply_committed_world(returned.world)
	var prior_token: int = stage.operation_token()
	stage._advance_night()
	check(not stage.callback_valid(prior_token), "同地图换夜后前夜回调失效")
	check(stage.night_id == 2 and stage.player.get_instance_id() == player_id and stage._geometry.get_instance_id() == geometry_id, "夜次推进沿用同一地图和同一角色")
	check(stage.player.position.distance_to(Vector3(20, 2.89, 4)) < 0.1, "夜次推进不会把角色传送到回廊")
	check(stage._mode == "explore", "尚未到回廊时不远程触发开场")
	world = stage.export_world()
	world.position = [-4.3, 0.04, 1.6]
	restored = stage.restore_world(world)
	check(restored.ok and not restored.used_fallback, "第二夜可以返回原上山路")
	check(stage._world.night == 2 and stage._world.event_flags.is_empty(), "回走不回退夜次或凭空完成剧情")
	world.position = Catalog.night(2).anchors.spawn.duplicate()
	restored = stage.restore_world(world)
	check(restored.ok and not restored.used_fallback, "回廊出生锚点在连续地图可落脚")
	stage._start_checkpoint_dialogue()
	check(stage._mode == "dialogue" and stage._dialogue._playing_id == "c1", "走到回廊后才播放原c1剧情")
	_silence(stage)
	var saved: Dictionary = session.save_world(stage.export_world())
	check(saved.ok, "全图实际位置可以保存")
	stage.free(); session.close()
	var resumed := Session.new()
	check(resumed.resume().ok and resumed.campaign.safe_snapshot().world.position == saved.world.position, "继续游戏保留新地图全局坐标")
	resumed.close()
	print("ACT_ONE_RUNTIME_ASSERTIONS:", assertions, " FAILURES:", failures.size())
	quit(0 if failures.is_empty() else 1)
