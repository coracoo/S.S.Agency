# 回廊/抬棺场景的独立呈现契约；不依赖正式关卡集成是否已经接上。
extends SceneTree
const CATALOG = preload("res://scripts/campaign/chapter_catalog.gd")
const GEOMETRY = preload("res://scripts/campaign/chapter_geometry.gd")
const REQUIRED := {
	2: ["CourtyardFront", "CorridorArchitecture", "PaperDoors", "RoofRafters", "HangingBell", "SendoffFragment", "OfferingTable", "GuideLantern"],
	3: ["StoneProcessionPath", "ShrineEnclosure", "DistantTorii", "PaperCoffin", "CarryingPoles", "PaperProcession", "StoneLanterns"]
}
var failures: Array[String] = []
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(1); return
	_run.call_deferred()
func _run() -> void:
	var selected := int(OS.get_environment("CAMPAIGN_ART_NIGHT"))
	for night in [2, 3]:
		if selected != 0 and selected != night: continue
		var path := "res://scripts/campaign/environments/night_%d_art.gd" % night
		check(FileAccess.file_exists(path), "艺术模块存在：" + path)
		if not FileAccess.file_exists(path): continue
		var art: Script = load(path)
		check(art != null and art.can_instantiate(), "艺术模块可以编译：" + path)
		if art == null or not art.can_instantiate(): continue
		var config: Dictionary = CATALOG.night(night)
		var before := JSON.stringify(config)
		var world := Node3D.new(); root.add_child(world)
		art.build(world, config)
		check(JSON.stringify(config) == before, "不修改章节登记：%d" % night)
		for group_name in REQUIRED[night]:
			var group := world.find_child(group_name, true, false)
			check(group is Node3D and group.find_children("*", "MeshInstance3D", true, false).size() > 0, "可见主题结构：%d/%s" % [night, group_name])
		var meshes := world.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() >= (20 if night == 2 else 80), "真实组成足够且允许GLB逻辑合批：%d" % night)
		check(meshes.size() <= 850, "轻量呈现节点预算：%d" % night)
		check(world.find_children("*", "PhysicsBody3D", true, false).is_empty(), "艺术层不创建额外物理体：%d" % night)
		check(world.find_children("*", "CollisionShape3D", true, false).is_empty(), "艺术层不创建额外碰撞：%d" % night)
		var materials: Dictionary = {}
		for mesh: MeshInstance3D in meshes:
			check(mesh.visible and mesh.mesh != null and mesh.mesh.get_aabb().size.length() > 0.01, "可见非空网格：" + str(mesh.get_path()))
			# GLB保留原材质槽与UV；不要求用override覆盖真实纹理。
			for surface_index in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface_index)
				check(material is StandardMaterial3D, "轻量标准材质：" + str(mesh.get_path()))
				if material != null: materials[material.get_instance_id()] = true
			var aabb := mesh.global_transform * mesh.mesh.get_aabb()
			# 中央走廊及所有z=0交互点必须保留脚下至头顶的可视空间；地板和高处屋架除外。
			var lane := AABB(Vector3(-5.6, 0.10, -0.65), Vector3(11.2, 2.45, 2.75))
			check(not aabb.intersects(lane), "不侵入中央通行/交互空间：" + str(mesh.get_path()))
			for anchor_name in config.anchors:
				var point: Array = config.anchors[anchor_name]
				var safe := AABB(Vector3(point[0] - 0.28, 0.12, point[2] - 0.28), Vector3(0.56, 1.85, 0.56))
				check(not aabb.intersects(safe), "锚点未落在可见装饰中：%s/%s" % [anchor_name, mesh.name])
		check(materials.size() <= 26, "复用材质而非逐网格创建：%d" % night)
		for light: Light3D in world.find_children("*", "Light3D", true, false):
			check(not light.shadow_enabled, "没有昂贵实时阴影：" + str(light.get_path()))
		if night == 2:
			for landmark in {"HangingBell": -2.5, "SendoffFragment": -0.6, "OfferingTable": 1.0, "GuideLantern": 2.5}:
				var prop := world.find_child(landmark, true, false) as Node3D
				if prop != null: check(absf(prop.global_position.x - float({"HangingBell": -2.5, "SendoffFragment": -0.6, "OfferingTable": 1.0, "GuideLantern": 2.5}[landmark])) < 0.15 and prop.global_position.z < -1.15, "道具对应真实交互x并留在后侧：" + landmark)
			check(world.find_child("BellRedThread", true, false) != null, "钟舌上有红线")
			check(world.find_child("FragmentInk", true, false) != null, "纸门残文有墨迹几何")
		else:
			check(world.find_child("PaperDoors", true, false) == null, "露天队列不复用回廊门墙")
			check(world.find_child("CoffinLightSeam", true, false) != null, "纸棺留出发光棺盖缝")
			var procession := world.find_child("PaperProcession", true, false)
			if procession != null: check(procession.get_child_count() >= 6, "错列多纸人队列")
		print("ART_MODULE_METRICS: night=", night, " meshes=", meshes.size(), " materials=", materials.size())
		world.free()
		await _check_reachable_solids(night)
	for failure in failures: printerr("ASSERT FAIL: ", failure)
	print("CORRIDOR PROCESSION ART: ", assertions, " assertions, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

# 真胶囊先询问保留物理世界；不能只凭中央走线或安全锚点认定后排装饰不可达。
func _check_reachable_solids(night: int) -> void:
	var world: Node3D = GEOMETRY.build(night, CATALOG.night(night)); root.add_child(world)
	await physics_frame
	await physics_frame
	var art := world.find_child("Night%dArt" % night, true, false)
	check(art != null, "全bounds回归使用真实集成艺术：%d" % night)
	if art == null: world.free(); return
	var solids: Array[Dictionary] = []
	for mesh: MeshInstance3D in art.find_children("*", "MeshInstance3D", true, false):
		var aabb: AABB = mesh.global_transform * mesh.get_aabb()
		# 贴地纸片/木纹/石板是表面纹理，不当作站立实体；头顶之外的屋架同理。
		if aabb.end.y <= 0.10 or aabb.position.y >= 1.87: continue
		if aabb.end.x < -5.7 or aabb.position.x > 5.7 or aabb.end.z < -2.8 or aabb.position.z > 2.8: continue
		solids.append({"aabb": aabb, "path": str(mesh.get_path())})
	var space := world.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new(); capsule.radius = 0.22; capsule.height = 1.4
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = capsule
	var hits: Dictionary = {}
	var free_samples := 0
	for ix in 111:
		for iz in 53:
			var point := Vector3(-5.5 + ix * 0.1, 0.73, -2.6 + iz * 0.1)
			query.transform.origin = point
			if not space.intersect_shape(query, 1).is_empty(): continue
			free_samples += 1
			for solid in solids:
				if hits.has(solid.path): continue
				var aabb: AABB = solid.aabb
				# 保守检查真实0.22m半径直立胶囊与网格世界AABB，不放宽到仅检查物体中心。
				var dx := maxf(maxf(aabb.position.x - point.x, point.x - aabb.end.x), 0)
				var dz := maxf(maxf(aabb.position.z - point.z, point.z - aabb.end.z), 0)
				var dy := maxf(maxf(aabb.position.y - 1.21, 0.25 - aabb.end.y), 0)
				if dx * dx + dy * dy + dz * dz < 0.22 * 0.22 - 0.000001:
					hits[solid.path] = point
	for path in hits: check(false, "可达胶囊穿入实体：%s at %s" % [path, hits[path]])
	check(hits.is_empty(), "全bounds所有可站立采样无新增实体穿模：%d" % night)
	print("ART_REACHABILITY_METRICS: night=", night, " samples=5883 free=", free_samples, " unsafe_meshes=", hits.size())
	world.free()
