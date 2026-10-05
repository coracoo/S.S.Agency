# 只负责三维几何、碰撞和灯光；标题可复用，不含剧情/输入/存档逻辑。
extends RefCounted
const NIGHT_LIGHTING := {
	2: preload("res://scripts/campaign/environments/night_2_lighting.gd"),
	3: preload("res://scripts/campaign/environments/night_3_lighting.gd"),
	4: preload("res://scripts/campaign/environments/night_4_lighting.gd"),
	5: preload("res://scripts/campaign/environments/night_5_lighting.gd"),
}
const NIGHT_ART := {
	2: preload("res://scripts/campaign/environments/night_2_art.gd"),
	3: preload("res://scripts/campaign/environments/night_3_art.gd"),
	4: preload("res://scripts/campaign/environments/night_4_art.gd"),
	5: preload("res://scripts/campaign/environments/night_5_art.gd"),
}
static func build(night_id: int, config: Dictionary) -> Node3D:
	var world := Node3D.new()
	world.name = "ChapterGeometry"
	_environment(world, night_id)
	if night_id == 1:
		var packed: PackedScene = load("res://assets/3d/act01_approach/act01_approach.glb")
		if packed != null:
			var model := packed.instantiate()
			model.name = "ApproachArt"
			world.add_child(model)
			var front := model.find_child("50_Path_Boundary_Front", true, false)
			if front is Node3D: front.hide()
		_box(world, Vector3(-4.35, -0.07, 0.7), Vector3(9.5, 0.2, 2.9), Color.TRANSPARENT, true, false)
		var slope := _box(world, Vector3(3.658, 1.3686, -0.2), Vector3(7.042, 0.2, 3.8), Color.TRANSPARENT, true, false)
		slope.rotation.z = atan2(2.86, 6.435)
		_box(world, Vector3(8.255, 2.79, -0.45), Vector3(2.87, 0.2, 3.0), Color.TRANSPARENT, true, false)
		var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/exploration_3d/approach.json"))
		for index in range(old.walk_polygon.size()):
			var a: Array = old.walk_polygon[index]
			var b: Array = old.walk_polygon[(index + 1) % old.walk_polygon.size()]
			_boundary(world, Vector2(a[0], a[1]), Vector2(b[0], b[1]))
		_box(world, Vector3(0.12, 0.52, 1.94), Vector3(1.63, 1.02, 1.62), Color.TRANSPARENT, true, false)
		_light(world, Vector3(0.12, 1.25, 1.7), Color(0.25, 0.42, 1.0), 2.5, 3.0)
	else:
		# 保留原几何物理约定，旧网格/灯仅作为不可见的碰撞骨架。
		var collision_root := Node3D.new()
		collision_root.name = "LegacyCollision"
		world.add_child(collision_root)
		collision_root.hide()
		var bounds: Dictionary = config.bounds
		var width := float(bounds.x[1]) - float(bounds.x[0])
		var depth := float(bounds.z[1]) - float(bounds.z[0])
		_box(collision_root, Vector3(0, -0.08, 0), Vector3(width + 0.6, 0.2, depth + 0.6), Color("483e43"))
		# 木板缝与后墙是实物几何；前侧无高墙，避免镜头遮挡。
		for x in range(-5, 6):
			_box(collision_root, Vector3(x, 0.023, 0), Vector3(0.018, 0.008, depth), Color("221e29"), false)
		_box(collision_root, Vector3(0, 1.45, bounds.z[0] - 0.12), Vector3(width + 0.5, 2.9, 0.25), Color("332c39"))
		for x in [-5.35, -2.6, 0.0, 2.6, 5.35]:
			_box(collision_root, Vector3(x, 1.5, bounds.z[0] + 0.15), Vector3(0.26, 3.0, 0.26), Color("742f36"))
			_lantern(collision_root, Vector3(x, 2.25, bounds.z[0] + 0.6), night_id)
		_box(collision_root, Vector3(0, 2.9, bounds.z[0] + 0.15), Vector3(width + 0.6, 0.24, 0.48), Color("5b3035"), false)
		for points in [[Vector2(bounds.x[0], bounds.z[0]), Vector2(bounds.x[1], bounds.z[0])], [Vector2(bounds.x[1], bounds.z[0]), Vector2(bounds.x[1], bounds.z[1])], [Vector2(bounds.x[1], bounds.z[1]), Vector2(bounds.x[0], bounds.z[1])], [Vector2(bounds.x[0], bounds.z[1]), Vector2(bounds.x[0], bounds.z[0])]]:
			_boundary(collision_root, points[0], points[1])
		if night_id <= 3:
			# 吊钟、送行旧物与纸列队分占空间，不在步行中央设置不可通行大障碍。
			_box(collision_root, Vector3(-2.5, 1.85, -1.85), Vector3(0.58, 0.66, 0.58), Color("98836a"), false)
			_box(collision_root, Vector3(1.6, 0.28, -2.05), Vector3(1.0, 0.5, 0.55), Color("9e815d"))
			if night_id == 3:
				_coffin(collision_root, Vector3(0.6, 0.32, -1.55))
				for x in [-1.4, -0.5, 1.7, 2.6]: _paper_person(collision_root, Vector3(x, 0, -1.9))
		else:
			_coffin(collision_root, Vector3(0.8, 0.32, -1.6))
			_box(collision_root, Vector3(-3.8, 1.4, -2.1), Vector3(0.7, 2.8, 0.7), Color("504b45"))
			var mirror := _box(collision_root, Vector3(0.8, 0.67, -1.6), Vector3(0.48, 0.035, 0.62), Color("b9cfda"), false)
			mirror.name = "CoffinMirror"
			if night_id == 5:
				for x in [-2.2, -1.3, 2.7, 3.6]: _paper_person(collision_root, Vector3(x, 0, -1.9))
				_box(collision_root, Vector3(4.8, 1.2, -2.15), Vector3(1.0, 2.4, 0.22), Color("a07756"))
		var art := Node3D.new()
		art.name = "EnvironmentArt"
		world.add_child(art)
		NIGHT_ART[night_id].build(art, config)
		NIGHT_LIGHTING[night_id].build_lights(world, art)
	for target in config.get("interactions", []):
		var marker := Node3D.new()
		marker.name = "Anchor_" + str(target.id).replace(":", "_")
		marker.position = vector(target.position)
		world.add_child(marker)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.27
		torus.outer_radius = 0.32
		ring.mesh = torus
		ring.position.y = 0.035
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("b79e69")
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = material
		marker.add_child(ring)
	return world
static func vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
static func _box(parent: Node3D, position: Vector3, size: Vector3, color: Color, collision: bool = true, visible: bool = true) -> Node3D:
	var body: Node3D = StaticBody3D.new() if collision else Node3D.new()
	body.position = position
	parent.add_child(body)
	if visible:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.9
		mesh.material_override = material
		body.add_child(mesh)
	if collision:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
	return body
static func _boundary(parent: Node3D, a: Vector2, b: Vector2) -> void:
	var delta := b - a
	var wall := _box(parent, Vector3((a.x + b.x) * 0.5, 2.0, (a.y + b.y) * 0.5), Vector3(delta.length() + 0.1, 6.0, 0.16), Color.TRANSPARENT, true, false)
	wall.rotation.y = -atan2(delta.y, delta.x)
static func _coffin(parent: Node3D, position: Vector3) -> void:
	_box(parent, position, Vector3(1.85, 0.55, 0.8), Color("6a363b"))
	_box(parent, position + Vector3(0, 0.31, 0), Vector3(1.98, 0.09, 0.92), Color("ac7656"), false)
static func _paper_person(parent: Node3D, position: Vector3) -> void:
	_box(parent, position + Vector3(0, 0.65, 0), Vector3(0.3, 1.05, 0.07), Color("d0c4aa"), false)
	_box(parent, position + Vector3(0, 1.32, 0), Vector3(0.3, 0.3, 0.08), Color("e3d5b7"), false)
	_box(parent, position + Vector3(0, 0.95, 0), Vector3(0.8, 0.16, 0.06), Color("d0c4aa"), false)
static func _lantern(parent: Node3D, position: Vector3, night_id: int) -> void:
	_box(parent, position, Vector3(0.3, 0.48, 0.3), Color("e6be83"), false)
	_light(parent, position, Color("c2b3ec") if night_id == 3 else Color("ffd29b"), 0.55, 2.8)
static func _light(parent: Node3D, position: Vector3, color: Color, energy: float, radius: float) -> void:
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	parent.add_child(light)
static func _environment(parent: Node3D, night_id: int) -> void:
	if NIGHT_LIGHTING.has(night_id):
		NIGHT_LIGHTING[night_id].setup_environment(parent)
		return
	var node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("171c2e") if night_id < 5 else Color("241b2a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8c91b5")
	environment.ambient_light_energy = 0.62
	environment.fog_enabled = true
	environment.fog_light_color = Color("44445d")
	environment.fog_density = 0.012 if night_id > 1 else 0.005
	node.environment = environment
	parent.add_child(node)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-46, -28, 0)
	key.light_color = Color("c9b4b7")
	key.light_energy = 1.05
	parent.add_child(key)
