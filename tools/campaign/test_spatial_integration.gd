# 第三轮空间融合：真实人物投影、相机空间景深与可逆开关。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
var failures: Array[String] = []
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); printerr("ASSERT FAIL: ",message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _run() -> void:
	if OS.get_environment("SPATIAL_LAYERS_ONLY") == "1":
		_run_layers(); return
	var session := Session.new()
	check(session.start_new(true).ok,"隔离场景开始")
	check((await session.prepare_assets()).ok,"原人物素材加载")
	var stage: Node3D = load(Catalog.scene_path(1)).instantiate(); root.add_child(stage)
	for frame in 8: await physics_frame
	check(stage.player.billboard.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED,"主角真实alpha裁切薄片参与月光投影")
	check(float(stage.player.billboard.material_override.get_shader_parameter("scene_light_mix"))>=.60,"人物材质以真实受光为主")
	for actor in stage.get_node("ActOneNPCs").get_children():
		var body := actor.get_node_or_null("Body") as AnimatedSprite3D
		if body == null: continue
		check(body.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED,"驻场人物也有真实薄片投影")
		check(actor.get_node("ContactShadow").material_override is ShaderMaterial,"驻场脚影是小范围渐隐接触影")
	var depth: Node3D = stage._hd2d_profile
	var material: ShaderMaterial = depth.effect.material_override
	check(material.get_shader_parameter("camera_focus_mode")==true,"正式景深使用相机空间距离")
	var near_radius: Variant = material.get_shader_parameter("near_blur_radius")
	check(near_radius!=null and near_radius>=8.0,"近景具有可读的柔焦层次")
	_test_camera_depth(depth,stage.camera_rig.camera,stage.player.position)
	_test_root_contacts(stage._geometry)
	stage.free(); session.close()
	print("SPATIAL INTEGRATION: ",assertions," assertions, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func _test_camera_depth(depth: Node3D, camera: Camera3D, original_position: Vector3) -> void:
	var material: ShaderMaterial = depth.effect.material_override
	if material.get_shader_parameter("camera_focus_mode") != true: return
	var original_camera := camera.global_transform
	# 在同一世界Z上改变相机仰角/方位：焦距必须来自相机视空间，不能偷用世界Z。
	var actor_position := Vector3(20.0,2.89,-4.5)
	for offset in [Vector3(0,6.2,11),Vector3(7.5,7.0,8.5),Vector3(-5.5,4.0,12.5)]:
		camera.global_position = actor_position+Vector3.UP*1.1+offset
		camera.look_at(actor_position+Vector3.UP*1.1)
		depth.follow(actor_position)
		var near_depth: float = material.get_shader_parameter("focus_near_distance")
		var far_depth: float = material.get_shader_parameter("focus_far_distance")
		var view := camera.global_transform.affine_inverse()
		for relative in [Vector3.ZERO,Vector3.UP*2.0,Vector3(0,0,2.2),Vector3(0,0,-2.2),Vector3(2.2,0,0),Vector3(-2.2,0,0)]:
			var distance: float = -(view*(actor_position+relative)).z
			check(distance>=near_depth and distance<=far_depth,"变化镜位下人物脸、鞋和2.2米交互平面均在真实焦内")
		# 可交互近邻的脚与头也在焦带内；更远NPC保持正常离焦。
		for direction in range(8):
			var angle := float(direction)*TAU/8.0
			for height in [0.0,2.0]:
				var neighbor := actor_position+Vector3(cos(angle)*2.2,height,sin(angle)*2.2)
				var neighbor_depth := -(view*neighbor).z
				check(neighbor_depth>=near_depth and neighbor_depth<=far_depth,"2.2米可交互邻域人物头脚均保清")
		var center_distance := -(view*(actor_position+Vector3.UP*.95)).z
		check(is_equal_approx((near_depth+far_depth)*.5,center_distance+.35),"焦带随真实相机深度移动")
		check(center_distance-7.0<near_depth and center_distance+8.0>far_depth,"近景树枝和远山离开人物清晰带")
	var effect_id: int = depth.effect.get_instance_id()
	depth.set_enabled(false)
	check(not depth.effect.visible,"关闭景深完全移除全屏效果")
	depth.set_enabled(true)
	check(depth.effect.visible and depth.effect.get_instance_id()==effect_id,"重开景深复用同一个效果且不重建地图")
	camera.global_transform = original_camera
	depth.follow(original_position)

func _test_root_contacts(world: Node3D) -> void:
	var ground: MeshInstance3D = world.find_child("SculptedContinuousMountainGround",true,false)
	var terrain_faces := ground.mesh.get_faces()
	var grove: Node3D = world.find_child("OuterCedarGrove",true,false)
	var rooted_tree_count := 0
	for tree in grove.get_children():
		if not str(tree.name).begins_with("QuietDeadCedar"): continue
		rooted_tree_count += 1
		var root_collar := tree.get_node_or_null("GroundFollowingRoots")
		check(root_collar!=null,"界外枯木具有沿实际土坡落地的独立根颈")
		if root_collar == null: continue
		var tip_count := 0
		var max_gap := -INF
		var all_ground_found := true
		for mesh_node in root_collar.get_children():
			for local_vertex in mesh_node.mesh.get_faces():
				if Vector2(local_vertex.x/.89,local_vertex.z/.76).length()<.965: continue
				var point: Vector3 = mesh_node.global_transform*local_vertex
				var hit_y := _surface_height_from_faces(point,terrain_faces)
				all_ground_found = all_ground_found and is_finite(hit_y)
				max_gap = maxf(max_gap,point.y-hit_y)
				tip_count += 1
		check(all_ground_found and tip_count>15 and max_gap<=.012,"枯木各根末端埋入真实三角土坡，不能按单点高度悬空")
	check(rooted_tree_count==3,"三株原枯木均保留，不能用移除树木冒充接地修复")
	var framing := world.find_child("NearBoundaryCedarAccents",true,false)
	check(framing != null,"镜头侧下角有少量同源近景杉木框景")
	if framing != null:
		check(framing.get_child_count()==2,"框景复用两株原杉木，不复制整林")
		for tree in framing.get_children():
			check(not world._in_walk(Vector2(tree.position.x,tree.position.z)),"框景根部放在通路界外")

func _surface_height_from_faces(point: Vector3, faces: PackedVector3Array) -> float:
	for index in range(0,faces.size(),3):
		var a := faces[index]; var b := faces[index+1]; var c := faces[index+2]
		if point.x<minf(a.x,minf(b.x,c.x)) or point.x>maxf(a.x,maxf(b.x,c.x)) or point.z<minf(a.z,minf(b.z,c.z)) or point.z>maxf(a.z,maxf(b.z,c.z)): continue
		var hit: Variant = Geometry3D.segment_intersects_triangle(point+Vector3.UP*10,point-Vector3.UP*10,a,b,c)
		if hit != null: return hit.y
	return INF

func _run_layers() -> void:
	var rig: Node3D = load("res://scripts/campaign/presentation/act_one_camera.gd").new(); root.add_child(rig)
	var depth: Node3D = load("res://scripts/campaign/presentation/act_one_depth.gd").new(); root.add_child(depth)
	depth.configure(rig.camera)
	var material: ShaderMaterial = depth.effect.material_override
	check(material.get_shader_parameter("camera_focus_mode")==true,"正式景深使用相机空间距离")
	var near_radius: Variant = material.get_shader_parameter("near_blur_radius")
	check(near_radius!=null and near_radius>=8.0,"近景具有可读的柔焦层次")
	_test_camera_depth(depth,rig.camera,Vector3.ZERO)
	var world: Node3D = load("res://scripts/campaign/act_one_geometry.gd").build({}); root.add_child(world)
	_test_root_contacts(world)
	world.free(); depth.free(); rig.free()
	print("SPATIAL LAYERS: ",assertions," assertions, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
