# 仅检查可关闭HD2D资源及与旧碰撞的相容性，不推进剧情/不写正式档。
extends SceneTree
const CATALOG = preload("res://scripts/campaign/chapter_catalog.gd")
const GEOMETRY = preload("res://scripts/campaign/chapter_geometry.gd")
var failures: Array[String] = []
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(1); return
	_run.call_deferred()
func _run() -> void:
	var config: Dictionary = CATALOG.night(2)
	var snapshot := JSON.stringify(config)
	var world: Node3D = GEOMETRY.build(2, config); root.add_child(world)
	var variant := load("res://assets/3d/night02_corridor_hd2d/night02_corridor_hd2d.glb").instantiate() as Node3D
	world.add_child(variant)
	await physics_frame; await physics_frame
	check(snapshot == JSON.stringify(config), "HD2D不改变目录或交互")
	for label in ["MidCorridor", "NearFrame", "OuterForecourt", "DistantGate", "SideVeranda"]:
		check(variant.find_child(label, true, false) != null, "语义层存在：" + label)
	check(variant.find_children("*", "PhysicsBody3D", true, false).is_empty(), "HD2D不新增物理阻挡")
	check(variant.find_children("*", "Light3D", true, false).is_empty(), "GLB灯光交集成profile控制")
	check(variant.find_children("*", "Camera3D", true, false).is_empty(), "GLB不改变镜头")
	var old: Node = world.find_child("SourceCorridor", true, false)
	for label in ["HangingBell", "SendoffFragment", "OfferingTable", "GuideLantern"]:
		var a: Node3D = old.find_child(label, true, false)
		var b: Node3D = variant.find_child(label, true, false)
		check(a != null and b != null and a.global_position.distance_to(b.global_position) < 0.001, "四调查实物父级保位：" + label)
	var solids: Array[Dictionary] = []
	for mesh: MeshInstance3D in variant.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		check(mesh.mesh != null, "所有网格加载")
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
				var dx := maxf(maxf(box.position.x-point.x, point.x-box.end.x), 0)
				var dz := maxf(maxf(box.position.z-point.z, point.z-box.end.z), 0)
				var dy := maxf(maxf(box.position.y-1.21, .25-box.end.y), 0)
				if dx*dx+dy*dy+dz*dz < .22*.22-.000001: hits[solid.path] = point
	for path in hits: check(false, "可达胶囊穿入HD2D实体：%s at %s" % [path,hits[path]])
	check(hits.is_empty(), "全bounds不增加可穿实体")
	for label in ["NearFrame", "SideVeranda"]:
		var layer := variant.find_child(label, true, false)
		for mesh: MeshInstance3D in layer.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			check(box.end.x < -6.8 or box.position.x > 6.8, "近/侧景中央x±6.8留空：" + str(mesh.name))
	print("HD2D_REACHABILITY: samples=5883 free=",free_samples," unsafe=",hits.size())
	for failure in failures: printerr("ASSERT FAIL: ",failure)
	print("HD2D_SPATIAL: ",assertions," assertions, ",failures.size()," failures")
	world.free();quit(0 if failures.is_empty() else 1)
