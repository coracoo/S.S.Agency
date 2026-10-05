# 实际物理世界验证，不写存档，不用逻辑地图代替胶囊与射线。
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
	var geometry_path := "res://scripts/campaign/act_one_geometry.gd"
	var connected_exists := ResourceLoader.exists(geometry_path)
	check(connected_exists, "连续寺域几何模块存在")
	var world: Node3D
	if connected_exists:
		world = load(geometry_path).build({})
	else:
		world = load("res://scripts/campaign/chapter_geometry.gd").build(1, {"interactions": []})
	root.add_child(world)
	await physics_frame
	await physics_frame
	var space := world.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new(); capsule.radius = 0.22; capsule.height = 1.4
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = capsule
	# 正程横贯前庭，经过回廊；北侧镜殿与南侧纸棺庭形成可回溯环路，再到本殿。
	var route: Array[Vector3] = [Vector3(8.5,2.89,0), Vector3(12,2.89,0), Vector3(21,2.89,0), Vector3(25,2.89,-5.6), Vector3(30.8,2.89,-5.6), Vector3(34,2.89,-5.6), Vector3(34,2.89,-12), Vector3(43,2.89,-12), Vector3(51.3,2.89,-12), Vector3(51.3,2.89,-5.6), Vector3(61,2.89,-5.6), Vector3(52,2.89,-3), Vector3(52,2.89,4.5), Vector3(43,2.89,4.5), Vector3(34,2.89,4.5), Vector3(27,2.89,4.5), Vector3(12,2.89,4.5), Vector3(12,2.89,0), Vector3(8.5,2.89,0)]
	for index in range(route.size()-1):
		var a := route[index]; var b := route[index+1]
		for direction in [1,-1]:
			query.transform.origin = (a if direction == 1 else b) + Vector3(0,.75,0)
			query.motion = (b-a)*direction
			var cast := space.cast_motion(query)
			check(cast[0] >= .999, "双向连续胶囊通路 %d/%d 无墙" % [index,direction])
		for step in range(int(ceil(a.distance_to(b)/.4))+1):
			var p := a.lerp(b, minf(1.0, float(step)*.4/maxf(a.distance_to(b),.01)))
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3(0,.3,0),p-Vector3(0,.4,0)))
			check(not hit.is_empty() and hit.normal.y > .95 and absf(hit.position.y-2.89)<.035, "连续地面 %.2f, %.2f" % [p.x,p.z])
	query.transform.origin = Vector3(20,2.89+.75,4.0)
	query.motion = Vector3.ZERO
	check(space.intersect_shape(query).is_empty(), "已验庭院[20,2.89,4]返场点无植床重叠")
	query.transform.origin = Vector3(20,2.89+.75,3.8)
	query.motion = Vector3(0,0,-5.8)
	check(space.cast_motion(query)[0] >= .999, "已验首段中心x20纵向主路不被新植床阻挡")
	if connected_exists:
		check(world.name == "ChapterGeometry", "连续几何接口根名称")
		check(world.has_method("update_visibility"), "空间可见性接口")
		for name in ["ApproachArt", "CorridorArt", "ProcessionArt", "MirrorArt", "HondenArt", "ForecourtArt"]:
			check(world.find_child(name,true,false) != null, "真实艺术分块 " + name)
		for region_name in ["CorridorArt","ProcessionArt","MirrorArt","HondenArt"]:
			var region_node: Node3D = world.find_child(region_name,true,false)
			var source_node: Node3D = region_node.get_node("SourceEnvironment")
			for light in region_node.find_children("*","OmniLight3D",true,false):
				check(light.global_position.distance_to(source_node.global_position) < 15, "分区灯光随原资产全局偏移 " + str(light.name))
		check(world.find_children("*","StaticBody3D",true,false).size() < 200, "连续边界合并为少量长段，不逐15cm生成物理体")
		var forecourt: Node3D = world.find_child("ForecourtArt",true,false)
		var paving: MultiMeshInstance3D = forecourt.find_child("WornStoneSlabPaving",true,false)
		check(paving.multimesh.mesh is ArrayMesh, "前庭铺面复用原不规则石板真网格")
		check(paving.multimesh.mesh.get_aabb().size.x < 1.2 and paving.multimesh.mesh.get_aabb().size.z < 1.2, "前庭使用独立原石，不再整模块挤压")
		var undistorted := true
		for paving_node in forecourt.find_children("WornStoneSlabPaving*","MultiMeshInstance3D",true,false):
			for index in range(paving_node.multimesh.instance_count):
				var scale_value: Vector3 = paving_node.multimesh.get_instance_transform(index).basis.get_scale()
				if absf(scale_value.x/scale_value.z-1.0) > .18: undistorted = false
		check(undistorted, "原落脚石逐石保持横纵比例，不在路口挤窄列")
		check(world.find_child("RollingMountainEarth",true,false) != null, "寺域外有起伏真实山坡承托")
		check(world.find_child("OuterCedarGrove",true,false) != null, "杉林中远景形成山林层次")
		check(world.find_child("CourtyardMossGardens",true,false) != null, "庭院植床石组具有独立构图")
		check(forecourt.find_child("WalkableEarthSurface",true,false) != null, "前庭主路外有独立可走泥土材质面")
		var soil_avoids_original_floors := true
		for soil in world.find_children("WalkableEarthSurface*","MeshInstance3D",true,false):
			var faces: PackedVector3Array = soil.mesh.get_faces()
			for index in range(0,faces.size(),3):
				var a: Vector3 = soil.global_transform*faces[index]
				var b: Vector3 = soil.global_transform*faces[index+1]
				var c: Vector3 = soil.global_transform*faces[index+2]
				var triangle_rect := Rect2(Vector2(a.x,a.z),Vector2.ZERO).expand(Vector2(b.x,b.z)).expand(Vector2(c.x,c.z))
				for room in world.ROOM_RECTS:
					var overlap: Rect2 = triangle_rect.intersection(room.grow(-.015))
					if overlap.has_area() and overlap.get_area()>.0001: soil_avoids_original_floors = false
		check(soil_avoids_original_floors, "泥土可见面避让原建筑木石地板，不造成板面穿插")
		var garden := world.find_child("CourtyardMossGardens",true,false)
		for bed in garden.find_children("*","MeshInstance3D",true,false):
			check(not bed.mesh is SphereMesh, "植床不能再用规则球面圆碟")
			if str(bed.name).begins_with("IrregularMossAndEarthBed"):
				var material: StandardMaterial3D = bed.mesh.surface_get_material(0)
				check(material.albedo_texture != null, "植床以同源土纹与院地融接，不是纯绿剪片")
		check(world.find_children("GroundedSourceStone*","MeshInstance3D",true,false).size() >= 10, "原岩组拆分独石后逐块贴地")
		var outer_grove := world.find_child("OuterCedarGrove",true,false)
		for group in outer_grove.get_children():
			check(not (absf(group.position.x-43)<2.0 and group.position.z>8 and group.position.z<14), "纸棺庭中央前景无遮角色杉树")
		var mirror_art := world.find_child("MirrorArt",true,false)
		check(mirror_art.find_child("MirrorSideGardenGround",true,false) != null, "镜殿神木独立侧庭有接地土面")
		check(mirror_art.find_child("MirrorPillarRoofBrace",true,false) != null, "镜殿前柱与后檐有实体托梁")
		var honden_art := world.find_child("HondenArt",true,false)
		check(honden_art.find_child("OpenSacredTreeFrame",true,false) != null, "本殿中间神木视口开放，梁柱不盖树洞")
		for region_name in ["ProcessionArt","MirrorArt","HondenArt"]:
			var region: Node3D = world.find_child(region_name,true,false)
			var coffin: Node3D = region.find_child("PaperCoffin" if region_name=="ProcessionArt" else "RitualPaperCoffin",true,false)
			check(absf(_group_world_bounds(coffin).position.y-2.89)<.012, "原棺底真实落在地面 " + region_name)
		var sacred_tree: Node3D = honden_art.find_child("SacredTreeHollow",true,false)
		var root_ground: MeshInstance3D = honden_art.find_child("HondenRootSoilPatch",true,false)
		check(root_ground != null, "本殿石台有独立神木种植开口")
		if root_ground != null:
			var ground_bounds: AABB = root_ground.global_transform*root_ground.get_aabb()
			check(absf(ground_bounds.end.y-_group_world_bounds(sacred_tree).position.y)<.015, "神木底面与坑内土面真实相接")
			var soil_rect := Rect2(ground_bounds.position.x,ground_bounds.position.z,ground_bounds.size.x,ground_bounds.size.z).grow(-.01)
			var clear_opening := true
			for piece in root_ground.get_parent().get_children():
				if piece is MeshInstance3D and piece.mesh is BoxMesh:
					var box: AABB = piece.global_transform*piece.get_aabb()
					if Rect2(box.position.x,box.position.z,box.size.x,box.size.z).intersection(soil_rect).has_area(): clear_opening = false
			check(clear_opening and honden_art.find_child("Rear_sanctuary_dais",true,false)==null, "石台真实几何未覆盖神木土穴开口")
		var mirror_glow: OmniLight3D = mirror_art.find_child("CoffinMirrorVerdigris",true,false)
		check(mirror_glow.light_energy<=.45 and mirror_glow.omni_range<=1.25, "绿色提示光限制在镜盘附近")
		var gate := world.find_child("ForecourtSanmon",true,false) as Node3D
		var gate_bounds := AABB(); var initialized := false
		for gate_mesh in gate.find_children("*","MeshInstance3D",true,false):
			var bounds: AABB = gate_mesh.global_transform*gate_mesh.get_aabb()
			gate_bounds = gate_bounds.merge(bounds) if initialized else bounds; initialized = true
		check(gate_bounds.size.x > 2.0, "山门从默认视角可辨横向门宽")
		# 门可按构图旋转；沿真实门包围盒横扫，验证实际柱体而非锁死旧坐标。
		var gate_hits := 0
		for sample in range(28):
			var z := lerpf(gate_bounds.position.z,gate_bounds.end.z,float(sample)/27.0)
			var gate_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(gate_bounds.end.x+.5,3.6,z),Vector3(gate_bounds.position.x-.5,3.6,z)))
			if not gate_hit.is_empty() and str(gate_hit.collider.name).begins_with("ReusedSanmon"): gate_hits += 1
		check(gate_hits >= 2, "新山门真实木柱不能穿过")
		var count_before := world.find_children("*","CollisionShape3D",true,false).size()
		world.update_visibility(Vector3(-8,0,0))
		check(world.find_children("*","CollisionShape3D",true,false).size() == count_before, "距离裁剪不移除碰撞")
		var far_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(61,4,-5.6),Vector3(61,2,-5.6)))
		check(not far_hit.is_empty(), "不可见远区地面仍参与物理")
	if connected_exists:
		check(world.has_method("update_tree_occlusion"), "前景树具有连续遮挡让位接口")
		if world.has_method("update_tree_occlusion"): _test_tree_occlusion(world)
		_test_tree_occlusion_many(world)
		await _walk_real_capsule(world)
	world.free()
	print("ACT ONE GEOMETRY: ", assertions," assertions, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func _walk_real_capsule(world: Node3D) -> void:
	# 沿用正式角色相同胶囊、48度坡限、0.5米贴地与2.6m/s速度，实际move_and_slide。
	var actor := CharacterBody3D.new(); actor.name = "ActualPhysicsCapsule"
	actor.floor_snap_length = .5; actor.floor_max_angle = deg_to_rad(48); actor.floor_stop_on_slope = true
	var shape := CollisionShape3D.new(); var capsule := CapsuleShape3D.new(); capsule.radius = .22; capsule.height = 1.4
	shape.shape = capsule; shape.position.y = .7; actor.add_child(shape); world.add_child(actor)
	actor.position = Vector3(-4.3,.04,.55)
	var destinations := [Vector3(-.9,.03,.2),Vector3(2,1,0),Vector3(8.5,2.89,0),Vector3(16,2.89,0),Vector3(8.5,2.89,0),Vector3(2,1,0),Vector3(-.9,.03,.2),Vector3(-4.3,.03,.55)]
	for destination in destinations:
		var reached := false; var on_floor_frames := 0; var minimum_y := INF
		for frame in range(900):
			await physics_frame
			var delta := Vector2(destination.x-actor.position.x,destination.z-actor.position.z)
			if delta.length() < .09: reached = true; break
			var direction := delta.normalized()
			actor.velocity.x = direction.x*2.6; actor.velocity.z = direction.y*2.6
			if actor.is_on_floor(): actor.velocity.y = 0; on_floor_frames += 1
			else: actor.velocity.y -= 18.0/60.0
			actor.move_and_slide()
			minimum_y = minf(minimum_y,actor.position.y)
		check(reached, "真实胶囊上山/返山抵达 " + str(destination))
		check(minimum_y > -.1 and on_floor_frames > 2, "坡面实走持续接地且不落空 " + str(destination))
	actor.free()

func _group_world_bounds(group: Node3D) -> AABB:
	var bounds := AABB(); var initialized := false
	for mesh_node in group.find_children("*","MeshInstance3D",true,false):
		var value: AABB = mesh_node.global_transform*mesh_node.get_aabb()
		bounds = bounds.merge(value) if initialized else value; initialized = true
	return bounds

func _test_tree_occlusion(world: Node3D) -> void:
	var grove := world.find_child("OuterCedarGrove",true,false)
	var tree: Node3D
	for group in grove.get_children():
		if absf(group.position.x-49)<.1 and absf(group.position.z-11)<.1: tree = group; break
	check(tree != null, "实际173–175帧挡路的x49前景树存在")
	if tree == null: return
	var leaves: MeshInstance3D = tree.find_children("61_Cedar*","MeshInstance3D",true,false)[0]
	var original: Material = leaves.get_active_material(0)
	var count := world.find_children("*","CollisionShape3D",true,false).size()
	var position_value := Vector3(49.19,2.89,4.86)
	world.update_tree_occlusion(position_value,1.0/60.0)
	var first: StandardMaterial3D = leaves.get_active_material(0)
	check(first.albedo_color.a<1.0 and first.albedo_color.a>.75, "进入遮挡逐帧渐隐，不整树瞬间消失")
	for index in range(18): world.update_tree_occlusion(position_value,1.0/60.0)
	check(leaves.get_active_material(0).albedo_color.a<=.02, "多层叶片遮挡时每层足够透明，叠加后不压暗角色")
	var bounds := _group_world_bounds(tree)
	for index in range(24):
		world.update_tree_occlusion(Vector3(bounds.end.x+.70+sin(index)*.035,2.89,4.86),1.0/60.0)
	check(leaves.get_active_material(0).albedo_color.a<=.15, "投影边缘微抖动由滞回稳定，不反复显隐")
	for index in range(45): world.update_tree_occlusion(Vector3(30,2.89,-7),1.0/60.0)
	check(leaves.get_active_material(0)==original, "离开遮挡恢复原材质与不透明度")
	check(world.find_children("*","CollisionShape3D",true,false).size()==count, "前景渐隐不改变任何物理碰撞")

func _test_tree_occlusion_many(world: Node3D) -> void:
	check(world.has_method("update_tree_occlusion_many"),"战斗前景让位支持一次检测多个参战身体")
	if not world.has_method("update_tree_occlusion_many"): return
	var grove := world.find_child("OuterCedarGrove",true,false)
	var tree: Node3D
	for group in grove.get_children():
		if absf(group.position.x-49)<.1 and absf(group.position.z-11)<.1: tree = group; break
	check(tree != null,"多人物遮挡测试使用真实x49前景树")
	if tree == null: return
	var leaves: MeshInstance3D = tree.find_children("61_Cedar*","MeshInstance3D",true,false)[0]
	var original: Material = leaves.get_active_material(0)
	var collision_count := world.find_children("*","CollisionShape3D",true,false).size()
	var blocked := Vector3(49.19,2.89,4.86)
	var clear := Vector3(30,2.89,-7)
	var blocked_first: Array[Vector3] = [blocked,clear]
	var blocked_last: Array[Vector3] = [clear,blocked]
	var no_actors: Array[Vector3] = []
	var clear_only: Array[Vector3] = [clear]
	world.update_tree_occlusion_many(blocked_first,1.0/60.0)
	var first_alpha: float = leaves.get_active_material(0).albedo_color.a
	check(is_equal_approx(first_alpha,1.0-5.5/60.0),"任一身体被遮挡即让位，且每棵树一帧只推进一次透明度")
	for index in range(18): world.update_tree_occlusion_many(blocked_first,1.0/60.0)
	check(leaves.get_active_material(0).albedo_color.a<=.02,"未被遮挡的另一身体不能覆盖先前的遮挡结果")
	for index in range(45): world.update_tree_occlusion_many(no_actors,1.0/60.0)
	check(leaves.get_active_material(0)==original,"无参战人物时逐帧恢复原树材质")
	world.update_tree_occlusion_many(blocked_last,1.0/60.0)
	check(is_equal_approx(leaves.get_active_material(0).albedo_color.a,first_alpha),"身体顺序反转不改变遮挡渐隐结果")
	for index in range(18): world.update_tree_occlusion_many(blocked_last,1.0/60.0)
	check(leaves.get_active_material(0).albedo_color.a<=.02,"列表中第二个身体被挡同样完成让位")
	for index in range(45): world.update_tree_occlusion_many(clear_only,1.0/60.0)
	check(leaves.get_active_material(0)==original,"所有身体离开后恢复原不透明度")
	check(world.find_children("*","CollisionShape3D",true,false).size()==collision_count,"多人物树冠让位不改变碰撞")
