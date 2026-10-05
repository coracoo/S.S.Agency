# 第四/五夜呈现模块真实实例检查；此脚本不读写存档。
extends SceneTree
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
var failures: Array[String] = []
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(1); return
	_run.call_deferred()
func _run() -> void:
	var only := int(OS.get_environment("ENV_ART_NIGHT"))
	for night in [4, 5]:
		if only > 0 and only != night: continue
		var path := "res://scripts/campaign/environments/night_%d_art.gd" % night
		check(FileAccess.file_exists(path), "第%d夜呈现模块已存在" % night)
		if not FileAccess.file_exists(path): continue
		var Art = load(path)
		check(Art != null and Art.has_method("build"), "第%d夜build接口可加载" % night)
		if Art == null: continue
		var world := Node3D.new(); root.add_child(world)
		var config := Catalog.night(night)
		var before := config.duplicate(true)
		Art.build(world, config)
		check(config == before, "呈现不改登记坐标/剧情：%d" % night)
		var groups := ["MirrorSideHall", "LatticeScreens", "PaperCoffin", "CoffinMirror", "OldRedCloth"] if night == 4 else ["HondenSanctuary", "TieredRoof", "SacredTreeHollow", "Shimenawa", "CoffinGlow", "PaperAttendants"]
		for expected in groups:
			var group := world.find_child(expected, true, false)
			check(group != null, "第%d夜辨认构造：%s" % [night, expected])
			if group != null: check(_count_meshes(group) >= 1, "构造包含真实网格：" + expected)
		if night == 4:
			var mirror: Node3D = world.find_child("CoffinMirror", true, false)
			var view_normal := Vector3(0, 4.8, 11).normalized()
			check(mirror != null and mirror.global_basis.y.normalized().dot(view_normal) >= 0.9, "铜镜圆面朝默认镜头，避免棺沿挡成细线")
		var exterior := world.find_child("ExteriorFoundation", true, false)
		check(exterior != null, "默认镜头前沿和侧移有低于地板的连续外景：%d" % night)
		var meshes: Array[MeshInstance3D] = []
		_collect(world, meshes)
		check(meshes.size() >= 60 and meshes.size() <= 600, "轻量真实3D网格数量：%d/%d" % [night, meshes.size()])
		var materials: Dictionary = {}
		var non_boxes := 0
		var highest_walk_surface := -INF
		for item in meshes:
			check(item.mesh != null and item.material_override is StandardMaterial3D, "网格与材质有效：" + str(item.get_path()))
			if item.material_override != null: materials[item.material_override.get_instance_id()] = true
			if not item.mesh is BoxMesh: non_boxes += 1
			var bounds := item.global_transform * item.get_aabb()
			if bounds.intersects(AABB(Vector3(-5.5, -0.1, -0.65), Vector3(11.0, 0.23, 2.0))):
				highest_walk_surface = maxf(highest_walk_surface, bounds.end.y)
			# 中央行走带与各互动点只有贴地纹理几何，不能竖起新障碍。
			check(not bounds.intersects(AABB(Vector3(-5.5, 0.13, -0.65), Vector3(11.0, 2.4, 2.0))), "中央与返场通道无装饰体积：" + item.name)
		check(highest_walk_surface <= 0.02501, "可走地面不得覆盖原始y=.035交互环：%d/%.3f" % [night, highest_walk_surface])
		check(materials.size() <= 18, "每夜复用不超过18个材质：%d" % materials.size())
		check(non_boxes >= 15, "包含曲面/分片/圆柱等非盒造型：%d" % non_boxes)
		print("ENV_ART_COUNTS: night=", night, " meshes=", meshes.size(), " materials=", materials.size(), " non_boxes=", non_boxes)
		world.free()
	for failure in failures: printerr("ASSERT FAIL: ", failure)
	print("MIRROR HONDEN ART: ", assertions, " assertions, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
func _collect(node: Node, meshes: Array[MeshInstance3D]) -> void:
	check(not node is PhysicsBody3D, "呈现模块绝不创建物理体：" + node.name)
	check(not node is GPUParticles3D and not node is CPUParticles3D, "无新增遮挡粒子：" + node.name)
	if node is MeshInstance3D: meshes.append(node)
	for child in node.get_children(): _collect(child, meshes)
func _count_meshes(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children(): count += _count_meshes(child)
	return count
