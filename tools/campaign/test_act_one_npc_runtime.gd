# 正式舞台NPC模态与编队过滤；只在隔离会话执行。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
var failures: Array[String] = []
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("ASSERT FAIL:",message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _run() -> void:
	var session := Session.new()
	check(session.start_new(true).ok,"创建隔离正式会话")
	check((await session.prepare_assets()).ok,"正式主角装配")
	var stage: Node3D = load(Catalog.scene_path(1)).instantiate()
	root.add_child(stage)
	for frame in 6: await physics_frame
	stage._generation += 1
	if is_instance_valid(stage._dialogue): stage._dialogue.abort(); stage._dialogue.queue_free()
	stage._dialogue = null; stage._arrival_checked = true; stage._resume_explore()
	check(stage.get_node_or_null("ActOneNPCs") != null,"三维寺域实际挂载NPC")
	if stage.get_node_or_null("ActOneNPCs") == null: stage.free();session.close();quit(1);return
	var targets: Array = stage.config.interactions.filter(func(t): return t.kind == "npc")
	check(targets.size() >= 3,"默认队伍至少有两名守寺人及未出战同伴")
	check(targets.filter(func(t): return str(t.id) == "npc:mint" or str(t.id) == "npc:guard").is_empty(),"已出战薄荷和岑照不重复站岗")
	var target: Dictionary = targets[0]
	var world: Dictionary = stage.export_world()
	world.position = target.position.duplicate()
	var result: Dictionary = stage.restore_world(world)
	check(result.ok and not result.used_fallback,"NPC脚下与邻近可接近")
	stage._confirm_armed = true
	var disk := FileAccess.get_file_as_string(Catalog.SAVE_PATH)
	var story: Dictionary = session.campaign.safe_snapshot()
	check(stage.nearest_interaction().kind == "npc","靠近提供真实交谈目标")
	check(stage.request_interaction(str(target.id)),"E对应NPC交谈入口")
	check(stage._mode == "npc" and not stage.controls_enabled,"交谈模态阻止角色移动")
	check(not stage.request_interaction(str(target.id)),"重复交谈不能叠加模态")
	Input.action_press("approach_right")
	var before: Vector3 = stage.player.position
	stage._dialogue.abort()
	for frame in 4: await physics_frame
	check(absf(stage.player.position.x-before.x) < .005,"关闭NPC对话后持续按键不穿透")
	Input.action_release("approach_right")
	for frame in 2: await physics_frame
	check(FileAccess.get_file_as_string(Catalog.SAVE_PATH) == disk and session.campaign.safe_snapshot() == story,"可重复NPC闲谈不发奖励不消费主线")
	stage.free();session.close()
	print("ACT_ONE_NPC_RUNTIME:",checks," assertions, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
