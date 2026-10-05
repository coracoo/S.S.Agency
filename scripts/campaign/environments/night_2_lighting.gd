# 第二夜独立呈现灯光：冷夜填光、错开的真实暖光池与低成本静态接触暗部。
# 不改变材质资产、相机、角色或物理；灯位由GLB实物包围盒解析而非凭截图摆点。
extends RefCounted

static func setup_environment(parent: Node3D) -> void:
	var node := WorldEnvironment.new()
	node.name = "Night2Environment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("111b2e")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8299b9")
	environment.ambient_light_energy = 0.18
	environment.fog_enabled = true
	environment.fog_light_color = Color("24324a")
	environment.fog_density = 0.006
	node.environment = environment
	parent.add_child(node)
	var key := DirectionalLight3D.new()
	key.name = "CoolNightKey"
	key.rotation_degrees = Vector3(-49, -31, 0)
	key.light_color = Color("a5b8d4")
	key.light_energy = 0.42
	# 同镜头A/B确认此软件渲染路径的方向阴影产生斜纹且多耗约22ms。
	# 保留真实方向受光；脚点暗部另用小面积静态柔影，避免把噪声当木纹。
	key.shadow_enabled = false
	parent.add_child(key)

static func build_lights(parent: Node3D, art: Node3D) -> void:
	var lighting := Node3D.new()
	lighting.name = "Night2Lighting"
	parent.add_child(lighting)
	# 邻灯全部叠加曾把整面纸墙照成橙亮。保留错开四盏墙灯与引路灯，
	# 左/中/右默认跟随视野都有光源，不随镜头开关灯而产生跳亮。
	var active_walls := ["WarmWallLantern_00", "WarmWallLantern_02", "WarmWallLantern_05", "WarmWallLantern_07"]
	for anchor in art.find_children("WarmWallLantern_*", "Node3D", true, false):
		if not str(anchor.name) in active_walls: continue
		var bounds := _bounds_relative_to(anchor, art)
		# 出光点靠灯罩下缘而不是正照自身纸面，保留纸纹并将暖色落在墙/地。
		_omni(lighting, str(anchor.name) + "_Pool", bounds.get_center() + Vector3(0, -0.36, 0.14), Color("ffb361"), 1.5, 4.2)
	var guide := art.find_child("Guide_paper_lantern", true, false) as Node3D
	if guide != null:
		_omni(lighting, "GuideLanternPool", _bounds_relative_to(guide, art).get_center() + Vector3(0, -0.28, 0.14), Color("ffc77d"), 1.35, 3.8)
	_contact_patches(lighting)

static func _omni(parent: Node3D, name: String, position: Vector3, color: Color, energy: float, radius: float) -> void:
	var light := OmniLight3D.new()
	light.name = name
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 1.25
	light.shadow_enabled = false
	parent.add_child(light)

static func _bounds_relative_to(anchor: Node3D, relative_to: Node3D) -> AABB:
	# Geometry.build在入树前建场，不能读取global_transform；累乘局部变换才正确。
	var transform := Transform3D.IDENTITY
	var cursor: Node = anchor
	while cursor != relative_to and cursor != null:
		if cursor is Node3D: transform = cursor.transform * transform
		cursor = cursor.get_parent()
	var result := {"initialized": false, "bounds": AABB()}
	_accumulate_bounds(anchor, transform, result)
	return result.bounds

static func _accumulate_bounds(node: Node3D, transform: Transform3D, result: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var bounds: AABB = transform * node.get_aabb()
		result.bounds = result.bounds.merge(bounds) if result.initialized else bounds
		result.initialized = true
	for child in node.get_children():
		if child is Node3D: _accumulate_bounds(child, transform * child.transform, result)

static func _contact_patches(parent: Node3D) -> void:
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, depth_draw_never; void fragment(){ float radius=length((UV-vec2(0.5))*2.0); ALBEDO=vec3(0.035,0.025,0.02); ALPHA=(1.0-smoothstep(0.2,1.0,radius))*0.23; }"
	var material := ShaderMaterial.new()
	material.shader = shader
	for x in [-5.35, -2.6, 0.0, 2.6, 5.35]:
		_contact(parent, "Contact_Post_" + str(x), Vector3(x, 0.036, -2.65), Vector2(0.64, 0.55), material)
	_contact(parent, "Contact_OldChest", Vector3(1.6, 0.036, -2.05), Vector2(1.17, 0.72), material)

static func _contact(parent: Node3D, name: String, position: Vector3, size: Vector2, material: Material) -> void:
	var node := MeshInstance3D.new()
	node.name = name
	node.position = position
	node.rotation_degrees.x = -90.0
	var mesh := QuadMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
