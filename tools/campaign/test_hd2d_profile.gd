# 实际几何/相机上的可逆实验profile，不写章节模型或正式玩家存档。
extends SceneTree
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
const Geometry = preload("res://scripts/campaign/chapter_geometry.gd")
const Camera = preload("res://scripts/campaign/presentation/night_2_hd2d_camera.gd")
var failures: Array[String] = []
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); printerr("ASSERT FAIL: ", message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _run() -> void:
	var subject: Node3D = load("res://scripts/campaign/chapter_stage.gd").new()
	check(subject.has_method("set_hd2d_experiment"), "正式stage具备显式可逆试点接口")
	check(subject.get("hd2d_experiment") == false, "正式stage默认关闭试点")
	subject.free()
	var path := "res://scripts/campaign/presentation/night_2_hd2d_profile.gd"
	check(ResourceLoader.exists(path), "独立二夜profile资源存在")
	if not ResourceLoader.exists(path): quit(1); return
	var stage := Node3D.new(); root.add_child(stage)
	var geometry := Geometry.build(2, Catalog.night(2)); stage.add_child(geometry)
	var rig := Camera.new(); stage.add_child(rig)
	rig.target = Vector3(0, 1.1, 0.8); rig._apply()
	var before := rig.camera.transform
	var base: Node3D = geometry.get_node("EnvironmentArt/Night2Art/SourceCorridor")
	var physical_before := geometry.find_children("*", "CollisionShape3D", true, false)
	var anchors: Dictionary = {}
	for node in geometry.get_children():
		if node.name.begins_with("Anchor_"): anchors[node.name] = node.transform
	var profile: Node3D = load(path).new(); stage.add_child(profile)
	check(not profile.configure(1, geometry, rig), "非二夜拒绝启用")
	check(profile.configure(2, geometry, rig), "二夜绑定实际几何与独立相机")
	check(base.visible and not profile.enabled and profile.variant == null, "默认关闭且不分配HD2D资产")
	check(profile.set_enabled(true), "显式开启成功")
	check(not base.visible and profile.variant.visible, "只显示一个完整变体")
	check(profile.variant.find_children("*", "MeshInstance3D", true, false).size() >= 100, "真实扩展GLB被实例化")
	check(profile.effect.visible and profile.effect.material_override.shader != null, "启用真实深度后期节点")
	check(profile.variant.find_children("*", "PhysicsBody3D", true, false).is_empty(), "扩展变体无新增物理")
	var bounds: Dictionary = Catalog.night(2).bounds
	var material: ShaderMaterial = profile.effect.material_override
	check(float(material.get_shader_parameter("clear_far_z")) < float(bounds.z[0]) - 0.5 and float(material.get_shader_parameter("clear_near_z")) > float(bounds.z[1]) + 0.5, "焦内带覆盖整个可走Z区并留出角色/武器余量")
	check(rig.experimental_enabled and is_equal_approx(rig.camera.size, 9.2), "实验相机一并启用")
	var first_id: int = profile.variant.get_instance_id()
	check(profile.set_enabled(true) and profile.variant.get_instance_id() == first_id, "重复开启不重复实例化")
	check(geometry.find_children("*", "CollisionShape3D", true, false) == physical_before, "全部原碰撞节点保留")
	for key in anchors: check(geometry.get_node(NodePath(key)).transform == anchors[key], "交互锚点不变" + str(key))
	check(profile.set_enabled(false), "显式关闭成功")
	check(base.visible and not profile.variant.visible and not profile.effect.visible, "关闭完整恢复R03显示且无后期")
	check(not rig.experimental_enabled and rig.camera.transform.is_equal_approx(before) and is_equal_approx(rig.camera.size, 8.0), "关闭恢复原相机位置角度和尺度")
	check(profile.set_enabled(true) and profile.variant.get_instance_id() == first_id, "再次开启复用已实例资产")
	profile.free()
	check(base.visible and not rig.experimental_enabled, "移除profile不留下隐藏R03或实验相机")
	stage.free()
	print("HD2D PROFILE: ", assertions, " assertions, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
