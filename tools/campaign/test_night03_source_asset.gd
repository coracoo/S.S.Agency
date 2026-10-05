# 第三夜同源资源轻测：真实集成与全bounds直立胶囊；不改正式存档。
extends SceneTree
const CATALOG = preload("res://scripts/campaign/chapter_catalog.gd")
const GEOMETRY = preload("res://scripts/campaign/chapter_geometry.gd")
const ART = preload("res://scripts/campaign/environments/night_3_art.gd")
var failures: Array[String] = []
var assertions := 0

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(1); return
	_run.call_deferred()

func _run() -> void:
	var config: Dictionary = CATALOG.night(3)
	var before := JSON.stringify(config)
	var isolated := Node3D.new(); root.add_child(isolated)
	ART.build(isolated, config)
	check(JSON.stringify(config) == before, "不修改第三夜登记")
	check(isolated.find_children("*", "PhysicsBody3D", true, false).is_empty(), "艺术资源无新物理体")
	check(isolated.find_children("*", "CollisionShape3D", true, false).is_empty(), "艺术资源无新碰撞")
	check(isolated.find_children("*", "Light3D", true, false).is_empty(), "艺术资源无内置灯")
	check(isolated.find_children("*", "Camera3D", true, false).is_empty(), "艺术资源无新相机")
	var meshes := isolated.find_children("*", "MeshInstance3D", true, false)
	check(meshes.size() >= 25 and meshes.size() <= 80, "合理合批25至80网格")
	var paper_count := 0
	var textured_surfaces := 0
	for mesh: MeshInstance3D in meshes:
		check(mesh.visible and mesh.mesh != null, "可见有效网格")
		check(mesh.material_override == null, "不以纯色覆盖源材质")
		for surface in mesh.mesh.get_surface_count():
			var mat := mesh.get_active_material(surface) as StandardMaterial3D
			check(mat != null, "标准PBR材质")
			if mat != null and mat.albedo_texture != null: textured_surfaces += 1
		var box := mesh.global_transform * mesh.get_aabb()
		if str(mesh.name).begins_with("Washi_attendant_folded_body_"):
			paper_count += 1
			check(box.position.y >= 0.59 and box.size.y > 1.0, "完整纸躯在低围垣上方")
			check(box.end.z < -2.8, "纸躯位于旧后墙外")
	check(paper_count == 7, "七具完整折纸侍从")
	check(textured_surfaces >= 35, "原图真实材质覆盖主要石木纸表面")
	check(isolated.find_child("PaperDoors", true, false) == null, "露天场景没有室内纸门墙")
	var lighting_script: Script = load("res://scripts/campaign/environments/night_3_lighting.gd")
	check(lighting_script != null and lighting_script.can_instantiate(), "独立灯模块可以编译")
	if lighting_script != null and lighting_script.can_instantiate():
		lighting_script.setup_environment(isolated)
		lighting_script.build_lights(isolated, isolated.find_child("Night3Art", true, false))
		var local_lights := isolated.find_children("*", "OmniLight3D", true, false)
		check(local_lights.size() == 3, "恰有两石灯暖池和一棺缝冷池")
		for light: Light3D in isolated.find_children("*", "Light3D", true, false):
			check(not light.shadow_enabled, "第三夜不引入动态阴影斜纹或开销")
		var cool := isolated.find_child("CoffinSeamColdPool", true, false) as OmniLight3D
		check(cool != null and cool.position.distance_to(Vector3(.6, .677, -1.126)) < .03, "棺缝灯由真实GLB缝隙位置导出")
	isolated.free()
	var world: Node3D = GEOMETRY.build(3, config); root.add_child(world)
	await physics_frame
	await physics_frame
	var art := world.find_child("Night3Art", true, false)
	check(art != null, "真实第三夜已接入同源资源")
	var solids: Array[Dictionary] = []
	for mesh: MeshInstance3D in art.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		if box.end.y <= 0.10 or box.position.y >= 1.87: continue
		if box.end.x < -5.7 or box.position.x > 5.7 or box.end.z < -2.8 or box.position.z > 2.8: continue
		solids.append({"aabb": box, "path": str(mesh.get_path())})
	var space := world.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new(); capsule.radius = .22; capsule.height = 1.4
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = capsule
	var hits: Dictionary = {}; var free_samples := 0
	for ix in 111:
		for iz in 53:
			var point := Vector3(-5.5 + ix * .1, .73, -2.6 + iz * .1)
			query.transform.origin = point
			if not space.intersect_shape(query, 1).is_empty(): continue
			free_samples += 1
			for solid in solids:
				if hits.has(solid.path): continue
				var box: AABB = solid.aabb
				var dx := maxf(maxf(box.position.x - point.x, point.x - box.end.x), 0)
				var dz := maxf(maxf(box.position.z - point.z, point.z - box.end.z), 0)
				var dy := maxf(maxf(box.position.y - 1.21, .25 - box.end.y), 0)
				if dx * dx + dy * dy + dz * dz < .22 * .22 - .000001: hits[solid.path] = point
	for path in hits: check(false, "可达胶囊穿入实体：%s at %s" % [path, hits[path]])
	check(hits.is_empty(), "全bounds零新增穿模")
	check(free_samples > 4500, "全bounds真实物理采样没有缩水")
	print("NIGHT03_REACHABILITY: samples=5883 free=", free_samples, " unsafe_meshes=", hits.size())
	world.free()
	for failure in failures: printerr("ASSERT FAIL: ", failure)
	print("NIGHT03_SOURCE_ASSET: ", assertions, " assertions, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
