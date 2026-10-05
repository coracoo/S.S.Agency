# 仅二夜实验相机的可逆性；不需要渲染器、更改存档或改原camera_rig。
extends SceneTree
var failures: Array[String] = []
var assertions := 0
func check(value: bool, text: String) -> void:
	assertions += 1
	if not value: failures.append(text); printerr("ASSERT FAIL: ", text)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _run() -> void:
	var path := "res://scripts/campaign/presentation/night_2_hd2d_camera.gd"
	check(ResourceLoader.exists(path), "二夜实验相机独立于原默认camera_rig")
	if not ResourceLoader.exists(path): quit(1); return
	var rig: Node3D = load(path).new(); root.add_child(rig)
	rig.target = Vector3(0, 1.1, 0.8); rig._apply()
	var original: Transform3D = rig.camera.transform
	check(is_equal_approx(rig.camera.size, 8.0), "默认关闭时size8")
	check(rig.camera.position.is_equal_approx(rig.target + Vector3(0, 4.8, 11)), "默认关闭时原offset")
	rig.set_experimental_enabled(true)
	check(is_equal_approx(rig.camera.size, 9.2), "仅实验size9.2")
	check(rig.camera.position.is_equal_approx(rig.target + Vector3(0, 6.2, 11)), "仅实验略俯视offset")
	check(rig.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "保留正交投影")
	rig.set_experimental_enabled(false)
	check(rig.camera.transform.is_equal_approx(original) and is_equal_approx(rig.camera.size, 8.0), "关闭完整恢复R03相机")
	rig.free()
	print("HD2D CAMERA: ", assertions, " assertions, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
