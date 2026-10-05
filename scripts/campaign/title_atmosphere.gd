# 标题专用的只读美术景片：一份原参道、真实山坡和少量杉林；不建立完整寺域或碰撞。
extends RefCounted
const APPROACH := preload("res://assets/3d/act01_approach/act01_approach.glb")

static func build() -> Node3D:
	var root_node := Node3D.new(); root_node.name = "TitleAtmosphere"
	var source: Node3D = APPROACH.instantiate(); source.name = "OriginalApproach"; root_node.add_child(source)
	var front := source.find_child("50_Path_Boundary_Front",true,false) as Node3D
	if front != null: front.hide()
	var earth: MeshInstance3D = source.find_child("01_Terrain_Watertight_Sculpted_Earth",true,false)
	var material := earth.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	material.uv1_triplanar = true; material.uv1_scale = Vector3(.30,.30,.30)
	material.albedo_color = Color(.46,.54,.48); material.roughness = .97
	var builder := SurfaceTool.new(); builder.begin(Mesh.PRIMITIVE_TRIANGLES); builder.set_material(material)
	# 摄影边界由地形延伸承接，不用纯色遮罩盖掉悬空底边。
	for x in range(-34,37,2):
		for z in range(-42,23,2):
			var points := [Vector3(x,_height(x,z),z),Vector3(x+2,_height(x+2,z),z),Vector3(x+2,_height(x+2,z+2),z+2),Vector3(x,_height(x,z+2),z+2)]
			for index in [0,1,2,0,2,3]:
				builder.set_uv(Vector2(points[index].x,points[index].z)*.30); builder.add_vertex(points[index])
	builder.generate_normals()
	var ground := MeshInstance3D.new(); ground.name = "TitleMountainGround"; ground.mesh = builder.commit()
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; root_node.add_child(ground)
	var positions := [Vector2(-15,-10),Vector2(-10,-12),Vector2(-3,-10),Vector2(3,-11),Vector2(9,-12),Vector2(15,-10),Vector2(-19,-17),Vector2(1,-22),Vector2(17,-20)]
	for index in range(positions.size()):
		var point: Vector2 = positions[index]
		_tree(source,root_node,index%5+1,Vector3(point.x,_height(point.x,point.y)-.04,point.y),.78+.12*float(index%4),float(index)*.67)
	for node in source.find_children("*","MeshInstance3D",true,false):
		if str(node.name).begins_with("01_Terrain") or str(node.name).begins_with("02_Path") or str(node.name).begins_with("03_Stone_Stairs") or str(node.name).begins_with("04_Upper_Landing"):
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_environment(root_node)
	_lamp(root_node,Vector3(-6.25,1.58,.4),Color("ffc784"),1.8,4.5)
	_lamp(root_node,Vector3(4.8,3.20,1.7),Color("ffcc91"),1.25,4.0)
	_lamp(root_node,Vector3(.12,1.22,1.70),Color("6d7fae"),1.10,2.5)
	return root_node

static func _height(x: float, z: float) -> float:
	var base := clampf((x-.6)*.444,0.0,2.86)-.85
	var outside := maxf(0.0,absf(z)-4.0)
	var waves := sin(x*.16+z*.12)*.44+sin(x*.31-z*.17)*.22
	# 近镜头一侧是真实下山谷坡；若向相机上拱，低正交视口底边会落到地表背面。
	if z>4.0: return base-(z-4.0)*.32+waves*.35
	return base+minf(outside*.13,3.8)+waves*minf(outside*.25,1.0)

static func _tree(source: Node3D, parent: Node3D, variant: int, at: Vector3, scale_value: float, yaw: float) -> void:
	var meshes: Array[MeshInstance3D] = []
	var bounds := AABB(); var initialized := false
	for prefix in ["60_Cedar_%d_Trunk"%variant,"61_Cedar_%d_Foliage"%variant]:
		var original := source.find_child(prefix,true,false) as MeshInstance3D
		if original == null: continue
		meshes.append(original)
		var box := _transform(original,source)*original.get_aabb()
		bounds = bounds.merge(box) if initialized else box; initialized = true
	if not initialized: return
	var group := Node3D.new(); group.name = "DistantCedar"; group.position = at
	group.scale = Vector3.ONE*scale_value; group.rotation.y = yaw; parent.add_child(group,true)
	var origin := Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
	for original in meshes:
		var copy := MeshInstance3D.new(); copy.name = original.name; copy.mesh = original.mesh
		copy.transform = _transform(original,source); copy.position -= origin; group.add_child(copy)

static func _transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var value := Transform3D.IDENTITY; var cursor: Node = node
	while cursor != ancestor and cursor != null:
		if cursor is Node3D: value = cursor.transform*value
		cursor = cursor.get_parent()
	return value

static func _environment(parent: Node3D) -> void:
	var node := WorldEnvironment.new(); node.name = "TitleForestFog"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR; environment.background_color = Color("172a30")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("9baac3"); environment.ambient_light_energy = .27
	environment.fog_enabled = true; environment.fog_light_color = Color("253b43"); environment.fog_density = .007
	node.environment = environment; parent.add_child(node)
	var moon := DirectionalLight3D.new(); moon.name = "TitleMoonlight"
	moon.rotation_degrees = Vector3(-46,-28,0); moon.light_color = Color("c7c5cf"); moon.light_energy = .42
	moon.shadow_enabled = true; moon.shadow_reverse_cull_face = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 32.0; moon.shadow_bias = .045; moon.shadow_normal_bias = .65; moon.shadow_opacity = .80
	parent.add_child(moon)

static func _lamp(parent: Node3D, at: Vector3, color: Color, energy: float, radius: float) -> void:
	var light := OmniLight3D.new(); light.position = at; light.light_color = color
	light.light_energy = energy; light.omni_range = radius; light.omni_attenuation = 1.4
	parent.add_child(light)
