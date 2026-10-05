# 第三夜轻量露天冷夜：两座原石灯暖池与克制的棺盖冷缝。
# 只用源GLB语义锚，入树前累乘局部变换；无动态阴影、无镜头/物理变化。
extends RefCounted

static func setup_environment(parent: Node3D) -> void:
	var node := WorldEnvironment.new()
	node.name = "Night3Environment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("151e31")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8b9dbd")
	environment.ambient_light_energy = 0.26
	environment.fog_enabled = true
	environment.fog_light_color = Color("28324b")
	environment.fog_density = 0.005
	node.environment = environment
	parent.add_child(node)
	var key := DirectionalLight3D.new()
	key.name = "Night3CoolKey"
	key.rotation_degrees = Vector3(-49, -31, 0)
	key.light_color = Color("a8b8d1")
	key.light_energy = 0.62
	key.shadow_enabled = false
	parent.add_child(key)

static func build_lights(parent: Node3D, art: Node3D) -> void:
	var lighting := Node3D.new()
	lighting.name = "Night3Lighting"
	parent.add_child(lighting)
	# 保留画面主要两处暖池，避免四盏叠加冲平纸纹与冷夜对比。
	for name in ["StoneLanternLightAnchor_01", "StoneLanternLightAnchor_02"]:
		var anchor := art.find_child(name, true, false) as Node3D
		if anchor == null: continue
		_omni(lighting, name + "_WarmPool", _relative_transform(anchor, art).origin + Vector3(0, -0.05, 0.10), Color("ffba72"), 1.05, 3.0)
	var seam := art.find_child("CoffinLightSeam", true, false) as MeshInstance3D
	if seam != null:
		var point := (_relative_transform(seam, art) * seam.get_aabb()).get_center()
		_omni(lighting, "CoffinSeamColdPool", point + Vector3(0, 0.06, 0.025), Color("9aaff5"), 0.48, 1.25)

static func _relative_transform(node: Node3D, relative_to: Node3D) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != relative_to and cursor != null:
		if cursor is Node3D: transform = cursor.transform * transform
		cursor = cursor.get_parent()
	return transform

static func _omni(parent: Node3D, name: String, position: Vector3, color: Color, energy: float, radius: float) -> void:
	var light := OmniLight3D.new()
	light.name = name
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	parent.add_child(light)
