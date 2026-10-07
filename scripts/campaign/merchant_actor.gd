# 神秘商人的独立程序化静态表现；尚无专用逐帧角色美术，不借用任何既有NPC身份或原PNG。
extends Node3D

func _ready() -> void:
	name = "MysteriousMerchant"
	set_meta("art_status", "independent_procedural_static_no_dedicated_animation")
	var cloth := _material("24343b")
	var straw := _material("9b8050")
	var wood := _material("614b36")
	var dark := _material("10191d")
	var cord := _material("ad8b59")
	_cylinder("Cloak", .19, .37, 1.08, Vector3(0,.89,0), cloth)
	_cylinder("Shoulders", .22, .31, .25, Vector3(0,1.38,0), cloth)
	_sphere("HiddenFace", .15, Vector3(0,1.5,-.035), dark)
	_cylinder("StrawHat", .035, .49, .22, Vector3(0,1.73,0), straw)
	_cylinder("HatBrim", .49, .49, .045, Vector3(0,1.61,0), straw)
	_box("FaceVeil", Vector3(.24,.32,.045), Vector3(0,1.4,-.16), dark)
	_box("Sash", Vector3(.48,.075,.4), Vector3(0,.95,0), cord)
	for side in [-1,1]:
		_box("Boot_%d" % side, Vector3(.18,.17,.27), Vector3(side*.14,.1,-.06), dark)
		var sleeve := _cylinder("Sleeve_%d" % side, .11, .13, .55, Vector3(side*.28,1.13,0), cloth)
		sleeve.rotation.z = side*.17
	_box("Pack", Vector3(.47,.68,.25), Vector3(0,1.08,.31), wood)
	for index in 6:
		_box("Wicker_%d" % index, Vector3(.5,.025,.025), Vector3(0,.79+index*.115,.45), cord)
	_box("LanternPost", Vector3(.035,1.05,.035), Vector3(.65,.57,-.06), wood)
	_box("LanternCrossbar", Vector3(.31,.035,.035), Vector3(.5,1.1,-.06), wood)
	var glow := _material("edbd6d")
	glow.emission_enabled = true
	glow.emission = Color("ffb25b")
	glow.emission_energy_multiplier = .8
	_box("WarmLantern", Vector3(.18,.26,.18), Vector3(.4,.93,-.06), glow)
	for y in [.78,1.08]: _box("LanternFrame", Vector3(.22,.04,.22), Vector3(.4,y,-.06), wood)
	var light := OmniLight3D.new()
	light.name = "MerchantLanternLight"
	light.position = Vector3(.4,1.03,-.1)
	light.light_color = Color("ffd092")
	light.light_energy = .9
	light.omni_range = 3.2
	add_child(light)
	_box("GoodsCrate", Vector3(.48,.38,.44), Vector3(-.64,.21,-.06), wood)
	_box("CrateLid", Vector3(.53,.04,.49), Vector3(-.64,.42,-.06), straw)
	_sphere("WrappedBundle", .16, Vector3(-.63,.57,-.06), _material("819282"))
	var body := StaticBody3D.new()
	body.name = "MerchantBody"
	add_child(body)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .27
	capsule.height = 1.48
	collision.shape = capsule
	collision.position.y = .76
	body.add_child(collision)
	var label := Label3D.new()
	label.name = "MerchantName"
	label.text = "神秘商人"
	label.font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
	label.font_size = 32
	label.pixel_size = .005
	label.position.y = 2.06
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("edd6a3")
	label.outline_size = 7
	label.outline_modulate = Color("15242b")
	add_child(label)

func _material(hex: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(hex)
	material.roughness = .9
	return material

func _mesh(id: String, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = id
	node.mesh = mesh
	node.material_override = material
	node.position = at
	add_child(node)
	return node

func _box(id: String, dimensions: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	return _mesh(id, mesh, at, material)

func _cylinder(id: String, top: float, bottom: float, height: float, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 16
	return _mesh(id, mesh, at, material)

func _sphere(id: String, radius: float, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius*2
	return _mesh(id, mesh, at, material)
