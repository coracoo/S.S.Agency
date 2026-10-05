# 第五夜本殿：局部暖石灯与冷色棺纹，不用动态阴影/镜面反射。
extends RefCounted

static func setup_environment(parent: Node3D) -> void:
	var node := WorldEnvironment.new()
	node.name = "Night5Environment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("171f2d")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8a9dac")
	environment.ambient_light_energy = 0.23
	environment.fog_enabled = true
	environment.fog_light_color = Color("293643")
	environment.fog_density = 0.005
	node.environment = environment
	parent.add_child(node)
	var key := DirectionalLight3D.new()
	key.name = "HondenCoolKey"
	key.rotation_degrees = Vector3(-49, -31, 0)
	key.light_color = Color("a8bdd0")
	key.light_energy = 0.50
	key.shadow_enabled = false
	parent.add_child(key)

static func build_lights(parent: Node3D, _art: Node3D) -> void:
	var lights := Node3D.new()
	lights.name = "Night5Lighting"
	parent.add_child(lights)
	# 石灯发光舱实际y=1.81..2.10，出光点在它的前下缘。
	_omni(lights, "OldStoneLanternWarmPool", Vector3(-3.8, 1.82, -1.86), Color("ffc37d"), 1.8, 3.5)
	_omni(lights, "HondenLeftRearLamp", Vector3(-4.45, 2.39, -5.81), Color("ffc084"), 1.5, 3.3)
	_omni(lights, "HondenRightRearLamp", Vector3(4.45, 2.39, -5.81), Color("ffc084"), 1.5, 3.3)
	_omni(lights, "SacredTreeColdHollow", Vector3(-0.54, 1.52, -3.35), Color("70aac8"), 0.9, 2.35)
	_omni(lights, "EmptyCoffinEcho", Vector3(0.8, 0.64, -1.42), Color("7daeb7"), 0.38, 1.5)

static func _omni(parent: Node3D, title: String, position: Vector3, color: Color, energy: float, radius: float) -> void:
	var light := OmniLight3D.new()
	light.name = title
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 1.25
	light.light_specular = 0.3
	light.shadow_enabled = false
	parent.add_child(light)
