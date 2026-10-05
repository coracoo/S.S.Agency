# 包外运行此检查；res://只允许来自正式PCK，无宿主项目回退。
extends SceneTree
const Geometry = preload("res://scripts/campaign/act_one_geometry.gd")
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")

func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1":
		printerr("FAIL: PCK场景检查必须先核验实际隔离user目录")
		quit(1)
		return
	var paths: Array[String] = ["res://scenes/campaign/title.tscn", "res://scenes/campaign/ending.tscn", "res://scenes/rpg/battle.tscn"]
	var failures: Array[String] = []
	for night in range(1, 6):
		paths.append(Chapters.scene_path(night))
		var geometry: Node3D = Geometry.build(Chapters.night(night))
		if geometry.get_node_or_null("ForecourtArt") == null or geometry.get_node_or_null("HondenArt") == null: failures.append("正式发布必须构建连续前庭与本殿，不能仅验遗留单块")
		if geometry.get_child_count() < 5: failures.append("缺少本夜三维几何：" + str(night))
		print("PCK_GEOMETRY_BUILT:", night, ":", geometry.get_child_count())
		geometry.free()
	for path in paths:
		var scene: PackedScene = load(path)
		if scene == null:
			failures.append("场景加载失败：" + path)
			continue
		var instance: Node = scene.instantiate()
		if instance == null:
			failures.append("场景实例失败：" + path)
			continue
		if instance.get_script() == null: failures.append("场景生产脚本缺失或解析失败：" + path)
		instance.free()
		print("PCK_SCENE_INSTANTIATED:", path)
	for failure in failures: printerr("ASSERT FAIL: ", failure)
	print("PCK_GEOMETRY_SCENES: 5 nights, 8 scenes, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
