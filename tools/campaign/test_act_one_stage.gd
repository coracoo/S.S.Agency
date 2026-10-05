# 第一幕连续地图舞台的真实节点测试；所有写档必须来自隔离入口。
extends SceneTree
var failures: Array[String] = []
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		printerr("ASSERT FAIL: ", message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _run() -> void:
	var camera_path := "res://scripts/campaign/presentation/act_one_camera.gd"
	check(ResourceLoader.exists(camera_path), "连续地图必须提供双轴跟随镜头")
	if not ResourceLoader.exists(camera_path): quit(1); return
	var rig: Node3D = load(camera_path).new()
	root.add_child(rig)
	var actor := Node3D.new(); root.add_child(actor)
	actor.position = Vector3(43, 2.89, -12)
	rig.follow(actor, 10.0)
	check(is_equal_approx(rig.target.x, 43), "镜头跟随远区横坐标")
	check(is_equal_approx(rig.target.z, -12), "镜头跟随镜殿纵深，不被旧走廊z限制")
	check(is_equal_approx(rig.target.y, 3.99), "镜头跟随上山后高度")
	check(is_equal_approx(rig.camera.size, 9.2), "地图镜头中景保留真实人物读图尺寸")
	actor.position = Vector3(-999, -999, 999)
	rig.follow(actor, 10.0)
	print("CAMERA_BOUND_SAMPLE:",rig.target)
	check(rig.target.x >= -9.0501 and rig.target.z <= 11.0001 and rig.target.y >= 1.0999, "双轴镜头不超出地图安全边界")
	var saved: Dictionary = rig.snapshot()
	actor.position = Vector3(20, 2.89, 4); rig.follow(actor, 10)
	check(rig.restore(saved) and rig.snapshot() == saved, "连续镜头快照保持旧接口可恢复")
	actor.free(); rig.free()
	var depth_path := "res://scripts/campaign/presentation/act_one_depth.gd"
	check(ResourceLoader.exists(depth_path), "连续地图必须具有随人物位置移动的清晰景深带")
	if not ResourceLoader.exists(depth_path): quit(1); return
	var depth: Node3D = load(depth_path).new(); root.add_child(depth)
	rig = load(camera_path).new(); root.add_child(rig)
	depth.configure(rig.camera)
	depth.follow(Vector3(43, 2.89, -12))
	check(is_equal_approx(depth.clear_far_z, -17.2) and is_equal_approx(depth.clear_near_z, -7.2), "焦带随人物纵深移动并为角色全身保留余量")
	depth.set_enabled(false)
	check(not depth.enabled and not depth.effect.visible, "关闭景深立即移除全屏效果")
	depth.set_enabled(true)
	check(depth.enabled and depth.effect.visible, "景深可逆开启且不重建大地图")
	depth.free(); rig.free()
	var stage: Node3D = load("res://scripts/campaign/chapter_stage.gd").new()
	check(stage.has_method("_intro_area_ready"), "下一夜开场需要实地到达区域，不能在前夜出口远程触发")
	if not stage.has_method("_intro_area_ready"): stage.free(); quit(1); return
	stage.night_id = 2
	stage.config = {"anchors": {"spawn": [20.3, 2.89, -6.0]}}
	stage.player = CharacterBody3D.new()
	stage.player.position = Vector3(8.65, 2.89, 0.35)
	check(not stage._intro_area_ready(), "山门不能播放远处回廊开场")
	stage.player.position = Vector3(20.3, 2.89, -6)
	check(stage._intro_area_ready(), "实地走到回廊入口后允许现有开场")
	stage.night_id = 1
	check(stage._intro_area_ready(), "首夜新游戏开场保持立即出现")
	check(stage.has_method("_open_npc"), "同行NPC需独立非战斗交谈入口")
	check(stage.has_method("_open_map"), "连续地图需要可关闭的只读寺域总览")
	check(stage.has_method("_switch_story_world"), "夜次切换提供原地刷新接口而非更换地图")
	check(stage.get_script().get_script_constant_map().has("WorldGeometry"), "整图几何必须静态依赖以随resources导出")
	stage.player.free(); stage.player = null; stage.free()
	print("ACT_ONE_PRESENTATION_ASSERTIONS:", assertions, " FAILURES:", failures.size())
	quit(0 if failures.is_empty() else 1)
