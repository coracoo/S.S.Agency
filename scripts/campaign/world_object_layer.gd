# 可见物件只呈现模型已提交状态。门的叶片、碰撞和存档状态共享同一个ID。
extends Node3D
const Objects = preload("res://scripts/campaign/world_object_catalog.gd")
const WOOD = preload("res://assets/3d/night02_corridor/night02_corridor_wood.png")
const PAPER = preload("res://assets/3d/night02_corridor/night02_corridor_paper.png")
var _nodes: Dictionary = {}
var _completed: Dictionary = {}
var _tweens: Array[Tween] = []
var _clock := 0.0

func configure(night: int, completed: Dictionary) -> void:
	for tween in _tweens:
		if tween.is_valid(): tween.kill()
	_tweens.clear()
	for child in get_children(): remove_child(child); child.queue_free()
	_nodes.clear(); _completed.clear()
	for entry in Objects.for_night(night):
		var node := Node3D.new(); node.name=str(entry.id)
		node.position=Vector3(entry.position[0],entry.position[1],entry.position[2])
		add_child(node); _nodes[entry.id]=node
		if entry.kind=="door": _build_door(node,float(entry.get("yaw",0)))
		else: _build_bundle(node,str(entry.item_id))
	apply_state(completed,false)

func object_node(id: String) -> Node3D:
	return _nodes.get(id)

func apply_state(completed: Dictionary, animate: bool = false) -> void:
	for id in _nodes:
		var node: Node3D=_nodes[id]
		var done: bool=bool(completed.get(id,false))
		var newly_done: bool=done and not bool(_completed.get(id,false))
		if node.has_node("Hinge"):
			var hinge: Node3D=node.get_node("Hinge")
			# 只开放已保存的通行状态；动画中也不会留下隐形墙。
			var shape: CollisionShape3D=node.get_node("DoorCollision/Shape")
			shape.set_deferred("disabled",done)
			if animate and newly_done:
				var tween:=create_tween(); _tweens.append(tween)
				tween.tween_property(hinge,"rotation:y",-PI*.52,.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			else: hinge.rotation.y=-PI*.52 if done else 0.0
			node.get_node("InteractionGlow").visible=not done
		else:
			if animate and newly_done:
				_pickup_spark(node.global_position)
				var tween:=create_tween(); _tweens.append(tween)
				tween.tween_property(node,"scale",Vector3.ONE*.01,.25)
				tween.tween_callback(node.hide)
			else:
				node.visible=not done
				node.scale=Vector3.ONE
	_completed=completed.duplicate(true)

func _material(color: Color, texture: Texture2D = null, glow: bool = false) -> StandardMaterial3D:
	var result:=StandardMaterial3D.new(); result.albedo_color=color; result.albedo_texture=texture; result.roughness=.86
	if glow:
		result.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		result.emission_enabled=true; result.emission=color; result.emission_energy_multiplier=.35
	return result

func _box(parent: Node3D, label: String, at: Vector3, size_value: Vector3, material: Material) -> MeshInstance3D:
	var node:=MeshInstance3D.new(); node.name=label; node.position=at
	var mesh:=BoxMesh.new(); mesh.size=size_value; node.mesh=mesh; node.material_override=material; parent.add_child(node)
	return node

func _build_door(node: Node3D, yaw: float) -> void:
	node.rotation.y=yaw
	var wood:=_material(Color("aa937c"),WOOD)
	var dark_wood:=_material(Color("655443"),WOOD)
	var brass:=_material(Color("a58c55"))
	for x in [-.84,.84]: _box(node,"DoorPost",Vector3(x,1.12,0),Vector3(.12,2.24,.18),dark_wood)
	_box(node,"DoorLintel",Vector3(0,2.21,0),Vector3(1.8,.12,.2),dark_wood)
	var hinge:=Node3D.new(); hinge.name="Hinge"; hinge.position.x=-.76; node.add_child(hinge)
	_box(hinge,"DoorLeaf",Vector3(.76,1.05,0),Vector3(1.5,2.1,.09),wood)
	for y in [.38,1.7]: _box(hinge,"DoorCrossbrace",Vector3(.76,y,.055),Vector3(1.5,.11,.055),dark_wood)
	for x in [.24,.5,.76,1.02,1.28]: _box(hinge,"DoorPlankSeam",Vector3(x,1.05,.049),Vector3(.017,2.05,.01),dark_wood)
	_box(hinge,"DoorHandle",Vector3(1.29,.95,.11),Vector3(.065,.23,.12),brass)
	var body:=StaticBody3D.new(); body.name="DoorCollision"; node.add_child(body)
	var shape:=CollisionShape3D.new(); shape.name="Shape"
	var box:=BoxShape3D.new(); box.size=Vector3(1.55,2.18,.12); shape.shape=box; shape.position.y=1.09; body.add_child(shape)
	_glow(node,Vector3(.59,1.13,.16),.07)

func _build_bundle(node: Node3D, item_id: String) -> void:
	var colors: Dictionary={"healing_potion":Color("906057"),"energy_tea":Color("63806b"),"cleansing_powder":Color("acaa8a"),"moxa_roll":Color("97965f"),"revival_potion":Color("8e738f")}
	var cloth:=_material(colors.get(item_id,Color("8b8775")),PAPER)
	var material:=_material(Color("c9b581"))
	var mesh:=SphereMesh.new(); mesh.radius=.22; mesh.height=.3; mesh.radial_segments=12; mesh.rings=6
	var parcel:=MeshInstance3D.new(); parcel.name="SupplySatchel"; parcel.mesh=mesh; parcel.material_override=cloth; parcel.position.y=.15; parcel.scale=Vector3(1.3,1,.85); node.add_child(parcel)
	_box(node,"ClothFold",Vector3(0,.26,0),Vector3(.23,.11,.16),cloth)
	_box(node,"ParcelTie",Vector3(0,.325,0),Vector3(.32,.035,.075),material)
	_box(node,"MedicineLabel",Vector3(.04,.195,.151),Vector3(.13,.14,.018),material)
	_glow(node,Vector3(0,.62,0),.09)

func _glow(parent: Node3D, at: Vector3, radius: float) -> void:
	var node:=MeshInstance3D.new(); node.name="InteractionGlow"; node.position=at
	var mesh:=SphereMesh.new(); mesh.radius=radius; mesh.height=radius*2; mesh.radial_segments=8; mesh.rings=4
	node.mesh=mesh; node.material_override=_material(Color("e8c784"),null,true); node.set_meta("base_y",at.y); parent.add_child(node)

func _pickup_spark(at: Vector3) -> void:
	var group:=Node3D.new(); group.name="PickupSpark"; add_child(group); group.global_position=at+Vector3.UP*.3
	var tween:=create_tween(); _tweens.append(tween); tween.set_parallel(true)
	for index in 7:
		var mote:=MeshInstance3D.new(); var mesh:=SphereMesh.new(); mesh.radius=.025; mesh.height=.05; mesh.radial_segments=6; mesh.rings=4
		mote.mesh=mesh; mote.material_override=_material(Color("eed59d"),null,true); group.add_child(mote)
		var angle:=TAU*float(index)/7.0
		tween.tween_property(mote,"position",Vector3(cos(angle)*.35,.55+float(index%3)*.13,sin(angle)*.35),.5)
		tween.tween_property(mote,"scale",Vector3.ONE*.01,.5)
	tween.chain().tween_callback(group.queue_free)

func _process(delta: float) -> void:
	_clock+=delta
	for node in _nodes.values():
		if not node.visible: continue
		var glow: MeshInstance3D=node.get_node("InteractionGlow")
		if glow.visible:
			glow.position.y=float(glow.get_meta("base_y"))+sin(_clock*2.8)*.04
			glow.scale=Vector3.ONE*(.87+sin(_clock*3.2)*.13)
