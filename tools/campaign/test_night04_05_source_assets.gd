# 四/五夜同源资产全bounds胶囊采样，只检查艺术实体与旧物理的对应。
extends SceneTree
const CATALOG = preload("res://scripts/campaign/chapter_catalog.gd")
const GEOMETRY = preload("res://scripts/campaign/chapter_geometry.gd")
var failures: Array[String] = []
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _run() -> void:
	for id in OS.get_environment("CAMPAIGN_ENVIRONMENT_NIGHTS").split(","):
		await _check_reachable_solids(int(id))
	for failure in failures: printerr("ASSERT FAIL: ", failure)
	print("INNER SHRINE SPATIAL: ", assertions, " assertions, ", failures.size(), " failures")
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
