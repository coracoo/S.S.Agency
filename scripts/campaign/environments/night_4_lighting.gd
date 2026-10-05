# 第四夜偏殿的低成本冷暖层次。固定GLB实物灯位，不改镜头或角色。
extends RefCounted

static func setup_environment(parent: Node3D) -> void:
	var node := WorldEnvironment.new()
	node.name = "Night4Environment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("121c29")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("859bad")
	environment.ambient_light_energy = 0.20
	environment.fog_enabled = true
	environment.fog_light_color = Color("263340")
	environment.fog_density = 0.006
	node.environment = environment
	parent.add_child(node)
	var key := DirectionalLight3D.new()
	key.name = "MirrorHallCoolKey"
	key.rotation_degrees = Vector3(-49, -31, 0)
	key.light_color = Color("a2b6cd")
	key.light_energy = 0.45
	key.shadow_enabled = false
	parent.add_child(key)

static func build_lights(parent: Node3D, _art: Node3D) -> void:
	var lights := Node3D.new()
	lights.name = "Night4Lighting"
	parent.add_child(lights)
	# 与manifest中真实灯罩中心一致，出光点降到纸罩下缘，暖池不铺满纸墙。
	_omni(lights, "LeftWashiLamp", Vector3(-4.72, 2.22, -2.28), Color("ffbc78"), 1.45, 3.2)
	_omni(lights, "RightWashiLamp", Vector3(4.68, 2.22, -2.28), Color("ffbc78"), 1.45, 3.2)
	_omni(lights, "CourtyardSmallLamp", Vector3(0.4, 0.52, -4.85), Color("f2af62"), 0.55, 1.8)
	_omni(lights, "CoffinMirrorVerdigris", Vector3(1.03, 0.72, -1.26), Color("72bbac"), 0.82, 2.3)

static func _omni(parent: Node3D, title: String, position: Vector3, color: Color, energy: float, radius: float) -> void:
	var light := OmniLight3D.new()
	light.name = title
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 1.25
	light.light_specular = 0.25
	light.shadow_enabled = false
	parent.add_child(light)
