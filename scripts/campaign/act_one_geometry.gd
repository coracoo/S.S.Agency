# 第一幕真实连续寺域：资产美术分块，地面/边界永久保留，不读取剧情状态。
extends Node3D

const ATMOSPHERE := preload("res://scripts/campaign/act_one_atmosphere.gd")
const STONE_LIBRARY := preload("res://scripts/campaign/act_one_stone_library.gd")
const TEXTURES := {
	"stone":preload("res://assets/3d/night02_corridor/night02_corridor_stone.png"),
	"wood":preload("res://assets/3d/night02_corridor/night02_corridor_wood.png"),
	"roof":preload("res://assets/3d/night02_corridor/night02_corridor_roof.png"),
	"paper":preload("res://assets/3d/night02_corridor/night02_corridor_paper.png"),
	"plaster":preload("res://assets/3d/night02_corridor/night02_corridor_plaster.png")
}
const APPROACH := preload("res://assets/3d/act01_approach/act01_approach.glb")
const CORRIDOR := preload("res://assets/3d/night02_corridor_hd2d/night02_corridor_hd2d.glb")
const PROCESSION := preload("res://assets/3d/night03_procession/night03_procession.glb")
const MIRROR := preload("res://assets/3d/night04_mirror/night04_mirror.glb")
const HONDEN := preload("res://assets/3d/night05_honden/night05_honden.glb")
const OLD_GEOMETRY := preload("res://scripts/campaign/chapter_geometry.gd")
const LAYOUT := preload("res://scripts/campaign/act_one_layout.gd")
const FLOOR := LAYOUT.TEMPLE_HEIGHT
var _walk_rects: Array[Rect2] = []
const ROOM_RECTS := [Rect2(17.9,-10.25,14.2,6.3),Rect2(37.2,1.1,11.6,5.8),Rect2(37.2,-15.85,11.6,5.7),Rect2(55.2,-7.85,11.6,5.7)]
var _chunks: Array[Dictionary] = []
var _materials: Dictionary = {}
var _physics: Node3D
var _source_stones: Array[Dictionary] = []
var _source_pavers: Array[Dictionary] = []
var _source_leaves: Array[Dictionary] = []
var _atmosphere_materials: Dictionary = {}
var _tree_occluders: Array[Dictionary] = []
var _earth_material: StandardMaterial3D

static func build(_config: Dictionary) -> Node3D:
	var world := new()
	world.name = "ChapterGeometry"
	world._construct()
	return world

func _construct() -> void:
	for entry in LAYOUT.walk_rects(): _walk_rects.append(entry.rect)
	_physics = Node3D.new(); _physics.name = "PermanentCollision"; add_child(_physics)
	_make_materials()
	_make_source_library()
	_environment()
	_approach()
	_courtyards()
	_landscape()
	_inner_regions()
	_perimeter()
	_configure_shadow_receivers()
	update_visibility(Vector3(8.5,FLOOR,0))

func update_visibility(position: Vector3, delta: float = 1.0/60.0, camera: Camera3D = null) -> void:
	for entry in _chunks:
		# 只裁美术与该区灯光，不销毁物理，不导致跨区换场。
		entry.node.visible = Vector2(position.x,position.z).distance_to(entry.center) < float(entry.radius)
	update_tree_occlusion(position,delta,camera)

func _chunk(name_value: String, center: Vector2, radius: float = 29.0) -> Node3D:
	var node := Node3D.new(); node.name = name_value; add_child(node)
	_chunks.append({"node":node,"center":center,"radius":radius})
	return node

func _make_materials() -> void:
	for key in ["stone","wood","roof","paper","plaster"]:
		var material := StandardMaterial3D.new()
		material.albedo_texture = TEXTURES[key]
		material.roughness = .86 if key != "stone" else .76
		material.uv1_triplanar = true
		material.uv1_scale = Vector3(.65,.65,.65) if key == "stone" else Vector3(.55,.55,.55)
		_materials[key] = material

func _environment() -> void:
	var node := WorldEnvironment.new(); node.name = "ActOneNightEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR; environment.background_color = Color("172438")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("9baac3"); environment.ambient_light_energy = .25
	environment.fog_enabled = true; environment.fog_light_color = Color("293b50"); environment.fog_density = .0035
	node.environment = environment; add_child(node)
	var key := DirectionalLight3D.new(); key.name = "ActOneMoonKey"
	key.rotation_degrees = Vector3(-46,-28,0); key.light_color = Color("c7c5cf"); key.light_energy = .42
	# 真实月光影限定在中景；较短阴影距离避免把整片远林投到可走台面。
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	key.directional_shadow_max_distance = 38.0
	key.directional_shadow_blend_splits = true
	key.shadow_bias = .045; key.shadow_normal_bias = .65
	key.shadow_opacity = .80
	# 原美术使用双面材质；实景A/B确认反向剔面去除岩石与瓦顶自阴影细纹。
	key.shadow_reverse_cull_face = true
	add_child(key)

func _approach() -> void:
	var art := _chunk("ApproachArt",Vector2(0,0),30)
	var model := APPROACH.instantiate() as Node3D; model.name = "OriginalApproach"; art.add_child(model)
	for index in range(1,6):
		var pieces: Array[MeshInstance3D] = []
		for prefix in ["60_Cedar_%d_Trunk"%index,"61_Cedar_%d_Foliage"%index]:
			var mesh_node := model.find_child(prefix,true,false) as MeshInstance3D
			if mesh_node != null: pieces.append(mesh_node)
		_register_tree_occluder(pieces)
	var front := model.find_child("50_Path_Boundary_Front",true,false) as Node3D
	if front != null: front.hide()
	_collision("ApproachLowerFloor",Vector3(-4.35,-.07,.7),Vector3(9.5,.2,2.9))
	var slope := _collision("ApproachContinuousSlope",Vector3(3.658,1.3686,-.2),Vector3(7.042,.2,3.8))
	slope.rotation.z = atan2(2.86,6.435)
	_collision("ApproachUpperLanding",Vector3(8.255,2.79,-.45),Vector3(2.87,.2,3.0))
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/exploration_3d/approach.json"))
	for index in range(old.walk_polygon.size()):
		var a: Array = old.walk_polygon[index]; var b: Array = old.walk_polygon[(index+1)%old.walk_polygon.size()]
		# 仅解除原右边封口；两条坡边与其余原路线不动。
		if float(a[0]) > 9.5 and float(b[0]) > 9.5: continue
		_boundary("ApproachEdge_%02d" % index,Vector2(a[0],a[1]),Vector2(b[0],b[1]),2.0)
	_collision("Basin",Vector3(.12,.52,1.94),Vector3(1.63,1.02,1.62))
	_lamp(art,Vector3(.12,1.25,1.7),Color("627dc8"),2.0,3.0)
	_lamp(art,Vector3(-6.25,1.62,.3),Color("ffc784"),1.8,4.5)
	_lamp(art,Vector3(8.5,3.7,-1.8),Color("ffc784"),1.2,4.2)
	# 山門以原鳥居真實木構向上層入口轉向複用；原山路模型原位不改。
	var gate := Node3D.new(); gate.name = "ForecourtSanmon"; art.add_child(gate)
	_clone_group(model,gate,["10_Torii","11_Torii","12_Torii","13_Torii","14_Torii","15_Torii","16_Torii","17_Torii","18_Torii"],Vector3(11.0,FLOOR,-.45),.63,PI/3)

func _courtyards() -> void:
	for index in range(_walk_rects.size()):
		var rect: Rect2 = _walk_rects[index]
		_collision("ContinuousSurface_%02d" % index,Vector3(rect.get_center().x,FLOOR-.1,rect.get_center().y),Vector3(rect.size.x,.2,rect.size.y))
	# 不铺全图巨地板；以真实地基承接各庭与侧路，建筑原地板仍为可见表面。
	var zones := [{"name":"ForecourtArt","rect":Rect2(9.5,-5,19.5,13)}, {"name":"CentralCourtArt","rect":Rect2(29,-10,26.6,11)}, {"name":"NorthWalkArt","rect":Rect2(31,-13.8,24,4)}, {"name":"SouthWalkArt","rect":Rect2(27,1,28,6.5)}]
	var used_paving_cells: Dictionary = {}
	for zone in zones:
		var rect: Rect2 = zone.rect
		var art := _chunk(zone.name,rect.get_center(),31)
		_visual_box(art,"StoneRetainingFoundation",Vector3(rect.get_center().x,2.05,rect.get_center().y),Vector3(rect.size.x,1.6,rect.size.y),"stone")
		var soil := MeshInstance3D.new(); soil.name = "WalkableEarthSurface"
		soil.mesh = _earth_surface(rect); art.add_child(soil)
		# 每块原石保持0.63×0.73米真实比例。路边允许自然外伸，不将模块挤进短边格。
		var batches: Array = [[],[],[],[]]
		var shades: Array = [[],[],[],[]]
		for iz in range(int(floor(rect.position.y/.77)),int(ceil(rect.end.y/.77))):
			var stagger := .335 if posmod(iz,2) else 0.0
			for ix in range(int(floor((rect.position.x-stagger)/.67)),int(ceil((rect.end.x-stagger)/.67))):
				var point := Vector2((ix+.5)*.67+stagger,(iz+.5)*.77)
				var cell := Vector2i(ix,iz)
				if not rect.has_point(point) or used_paving_cells.has(cell) or not _on_paving(point): continue
				used_paving_cells[cell] = true
				var road_edge := _at_paving_edge(point)
				# 仅在外缘稀疏留下旧缺口；路心原石、物理落脚面与通路登记均保持。
				if road_edge and posmod(ix*11+iz*17,23)==0: continue
				var variant := posmod(ix*7+iz*11,4)
				var stone_mesh: Mesh = _source_pavers[variant*4].mesh
				var basis := Basis(Vector3.UP,sin(float(ix*13+iz*7))*.014).scaled(Vector3(1,.90,1))
				var at := Vector3(point.x,FLOOR-.008-stone_mesh.get_aabb().size.y*.90,point.y)
				batches[variant].append(Transform3D(basis,at))
				var wear := float(posmod(ix*19+iz*13,11))/10.0
				shades[variant].append(Color(lerpf(.76,.95,wear),lerpf(.80,.96,wear),lerpf(.76,.94,wear)) if road_edge else Color(lerpf(.92,1.0,wear),lerpf(.95,1.0,wear),lerpf(.93,1.0,wear)))
		for variant in range(4):
			var multiple := MultiMesh.new(); multiple.transform_format = MultiMesh.TRANSFORM_3D
			multiple.use_colors = true
			var paving_mesh: ArrayMesh = _source_pavers[variant*4].mesh.duplicate()
			for surface in range(paving_mesh.get_surface_count()):
				var stone_material: StandardMaterial3D = paving_mesh.surface_get_material(surface).duplicate()
				stone_material.vertex_color_use_as_albedo = true; paving_mesh.surface_set_material(surface,stone_material)
			multiple.mesh = paving_mesh
			multiple.instance_count = batches[variant].size()
			for index in range(batches[variant].size()):
				multiple.set_instance_transform(index,batches[variant][index])
				multiple.set_instance_color(index,shades[variant][index])
			var paving := MultiMeshInstance3D.new(); paving.name = "WornStoneSlabPaving"; paving.multimesh = multiple; art.add_child(paving,true)
	# 保留可绕行空场。杉木和灯笼放在石庭边缘与非主路的小植床。
	var source := APPROACH.instantiate() as Node3D
	var decoration := _chunk("CourtyardMossGardens",Vector2(29,-1),46)
	for spec in [Vector3(15.6,FLOOR,-3.1),Vector3(23.4,FLOOR,2.85),Vector3(26.7,FLOOR,6.8),Vector3(32.2,FLOOR,-9.0),Vector3(54,FLOOR,.3)]:
		_garden_island(decoration,source,spec)
	var offering: Node3D = ATMOSPHERE.build(_atmosphere_materials,FLOOR)
	decoration.add_child(offering)
	_place_stone(offering,32,Vector3(16.38,FLOOR,-2.84),.38,.10)
	_place_stone(offering,37,Vector3(16.83,FLOOR,-2.90),.27,.085)
	var branches: Array[MeshInstance3D] = []
	for mesh in offering.get_node("LightningSplitCedar").find_children("*","MeshInstance3D",true,false): branches.append(mesh)
	_register_tree_occluder(branches)
	for p in [Vector3(12.8,FLOOR,2.5),Vector3(20,FLOOR,6.8),Vector3(28,FLOOR,-2.8),Vector3(34.4,FLOOR,1.3),Vector3(35.5,FLOOR,-13.2),Vector3(50.2,FLOOR,-8.8),Vector3(52.7,FLOOR,6.6),Vector3(55.5,FLOOR,-3.3)]:
		_clone_group(source,decoration,["20_Lantern_Upper_Stone","21_Lantern_Upper_WashiGlow"],p,.80)
		_collision("CourtyardStoneLantern",p+Vector3(0,.64,0),Vector3(.55,1.28,.55))
		_contact_shadow(decoration,p+Vector3(0,.009,0),Vector2(1.1,.85),.34)
		_lamp(decoration,p+Vector3(0,1.1,.25),Color("ffc889"),1.35,5.5)
	decoration.add_child(ATMOSPHERE.spent_lamp_offering(_atmosphere_materials,Vector3(35.65,FLOOR,-13.62)))
	decoration.add_child(ATMOSPHERE.boundary_remains(_atmosphere_materials,Vector3(49.0,_landscape_height(49.0,8.55),8.55)))
	var weeds: Array[Vector3] = []
	for point in [Vector2(13.9,1.48),Vector2(17.7,1.47),Vector2(22.2,1.53),Vector2(25.4,-1.54),Vector2(17.1,5.68),Vector2(25.1,5.67),Vector2(30.5,-7.2),Vector2(35.6,-7.2),Vector2(47.8,-7.16),Vector2(49.7,-9.0),Vector2(35.5,-11.7),Vector2(48.7,-14.0),Vector2(32.8,5.82),Vector2(51.9,5.89)]:
		var within_room := false
		for room in ROOM_RECTS:
			if room.grow(.1).has_point(point): within_room = true; break
		if not _on_paving(point) and not within_room: weeds.append(Vector3(point.x,FLOOR-.006,point.y))
	decoration.add_child(ATMOSPHERE.roadside_weeds(weeds))
	source.free()

func _inner_regions() -> void:
	var definitions := [{"name":"CorridorArt","scene":CORRIDOR,"offset":LAYOUT.night_offset(2),"night":2}, {"name":"ProcessionArt","scene":PROCESSION,"offset":LAYOUT.night_offset(3),"night":3}, {"name":"MirrorArt","scene":MIRROR,"offset":LAYOUT.night_offset(4),"night":4}, {"name":"HondenArt","scene":HONDEN,"offset":LAYOUT.night_offset(5),"night":5}]
	for definition in definitions:
		var offset: Vector3 = definition.offset
		var art := _chunk(definition.name,Vector2(offset.x,offset.z),27)
		var model: Node3D = definition.scene.instantiate(); model.name = "SourceEnvironment"; art.add_child(model); model.position = offset
		# 拆去旧摄影棚的远景填地与前景遮挡，新地图只接入一套真实中景。
		var unwanted: Array[String] = []
		match int(definition.night):
			2: unwanted = ["DistantGate","NearFrame","OuterForecourt","SideVeranda"]
			3: unwanted = ["DistantGrove","DistantTorii","ForegroundRockBank"]
			4,5: unwanted = ["CourtyardStones"]
		for name_value in unwanted:
			var node := model.find_child(name_value,true,false)
			if node != null: node.get_parent().remove_child(node); node.free()
		if definition.night == 4:
			# 两侧灰泥实墙挖成2m通口；背侧短墙与门楣仍留真实原材质。
			for wall in model.find_children("Side_wall_plaster*","MeshInstance3D",true,false):
				wall.get_parent().remove_child(wall); wall.free()
			for sign_value in [-1,1]:
				var x: float = offset.x + 5.98*sign_value
				_visual_box(art,"SideDoorRearPlaster",Vector3(x,FLOOR+1.33,offset.z-2.25),Vector3(.18,2.66,1.40),"plaster")
				_collision("SideDoorRearPlaster",Vector3(x,FLOOR+1.33,offset.z-2.25),Vector3(.18,2.66,1.40))
				_visual_box(art,"SideDoorLintel",Vector3(x,FLOOR+2.60,offset.z+.10),Vector3(.23,.22,3.30),"wood")
		if definition.night == 4:
			var tree := model.find_child("SacredTreeHollow",true,false) as Node3D
			if tree != null: tree.position.x += 6.6
			var ground := MeshInstance3D.new(); ground.name = "MirrorSideGardenGround"
			var plane := PlaneMesh.new(); plane.size = Vector2(4.4,3.4); plane.material = _earth_material
			ground.mesh = plane; ground.position = offset+Vector3(7.8,-.015,-5.7); art.add_child(ground)
			_visual_box(art,"MirrorPillarRoofBrace",offset+Vector3(-3.8,2.88,-2.61),Vector3(.35,.24,1.20),"wood")
		elif definition.night == 5:
			# 神木与梁实际上前后分离，但旧中柱/横梁正好遮树洞；改两翼开口框架。
			for name_value in ["Front_sanctuary_cedar_beam","Legacy_rear_post_2"]:
				var part := model.find_child(name_value,true,false)
				if part != null: part.get_parent().remove_child(part); part.free()
			var frame := Node3D.new(); frame.name = "OpenSacredTreeFrame"; art.add_child(frame)
			for sign_value in [-1,1]:
				_visual_box(frame,"SideCedarBeam",offset+Vector3(sign_value*3.825,3.05,-2.75),Vector3(4.05,.27,.31),"wood")
		if definition.night >= 3: _ground_coffin(model,art,int(definition.night))
		if definition.night == 5: _open_root_planting_well(model,art,offset)
		# 墙柱与故事实物用精简包围体，不能再穿过原纯美术墙。
		_art_colliders(model,int(definition.night))
		var local_lighting := Node3D.new(); local_lighting.name = "SourceLighting"; local_lighting.position = offset; art.add_child(local_lighting)
		OLD_GEOMETRY.NIGHT_LIGHTING[int(definition.night)].build_lights(local_lighting,model)
		if definition.night == 4:
			var glow := local_lighting.find_child("CoffinMirrorVerdigris",true,false) as OmniLight3D
			if glow != null: glow.light_energy = .38; glow.omni_range = 1.0
		elif definition.night == 3:
			var glow := local_lighting.find_child("CoffinSeamColdPool",true,false) as OmniLight3D
			if glow != null: glow.light_energy = .23; glow.omni_range = .90
		var room: Rect2 = ROOM_RECTS[int(definition.night)-2]
		_visual_box(art,"SourceRoomStoneFoundation",Vector3(room.get_center().x,2.05,room.get_center().y),Vector3(room.size.x,1.55,room.size.y),"stone")

func _art_colliders(model: Node3D, night_id: int) -> void:
	var prefixes: Array[String] = ["Continuous_dark_sanctuary_backing","Cedar_post_","Corridor_end_post","Heirloom_chest","Kept_legacy_wood_box","Paper_coffin_body","Folded_paper_coffin_shell","Legacy_left_timber_pillar_timber","Legacy_rear_post_","Deep_rear_wall","Cedar_back_dado","Honden_plaster_backing","Legacy_rear_stone_boundary","Aged_tablet_body","Tall_moss_stone_pedestal"]
	for mesh_node in model.find_children("*","MeshInstance3D",true,false):
		var accepted := false
		for prefix in prefixes:
			if str(mesh_node.name).begins_with(prefix): accepted = true; break
		if not accepted: continue
		# 后柱的鞋和接头不重复创建体积。
		if str(mesh_node.name).begins_with("Legacy_rear_post_") and not str(mesh_node.name).ends_with("_timber"): continue
		var bounds := _bounds_in(mesh_node,self)
		_collision("ArtCollision_"+str(mesh_node.name),bounds.get_center(),bounds.size)
	# 露天纸棺庭后围栏在路径后方；前庭、两侧通道无封闭旧boundary。
	if night_id == 3:
		_collision("ProcessionRearEnclosure",model.position+Vector3(0,1.45,-3.05),Vector3(12.0,2.9,.22))

func _perimeter() -> void:
	# 按矩形端点切分边缘，删除并集内部线段；不是每15cm一个物理体。
	var x_cuts: Array[float] = []; var z_cuts: Array[float] = [-1.85,.98]
	for rect in _walk_rects:
		x_cuts.append(rect.position.x); x_cuts.append(rect.end.x)
		z_cuts.append(rect.position.y); z_cuts.append(rect.end.y)
	x_cuts.sort(); z_cuts.sort()
	var segments: Dictionary = {}
	var trim := _chunk("TempleStoneCoping",Vector2(37,-2),57)
	for rect in _walk_rects:
		for edge in [[Vector2(rect.position.x,rect.position.y),Vector2(rect.end.x,rect.position.y)],[Vector2(rect.end.x,rect.position.y),Vector2(rect.end.x,rect.end.y)],[Vector2(rect.position.x,rect.end.y),Vector2(rect.end.x,rect.end.y)],[Vector2(rect.position.x,rect.position.y),Vector2(rect.position.x,rect.end.y)]]:
			var a: Vector2 = edge[0]; var b: Vector2 = edge[1]; var delta := b-a
			var vertical := is_zero_approx(delta.x)
			var cuts: Array[float] = z_cuts if vertical else x_cuts
			var values: Array[float] = []
			var first := a.y if vertical else a.x; var last := b.y if vertical else b.x
			for value in cuts:
				if value >= first and value <= last and not values.has(value): values.append(value)
			for index in range(values.size()-1):
				var p := Vector2(a.x,values[index]) if vertical else Vector2(values[index],a.y)
				var q := Vector2(a.x,values[index+1]) if vertical else Vector2(values[index+1],a.y)
				var center := (p+q)*.5; var normal := Vector2(-delta.y,delta.x).normalized()*.03
				if _in_walk(center+normal) and _in_walk(center-normal): continue
				if absf(center.x-9.5)<.03 and center.y > -1.85 and center.y < .98: continue
				var key := str(p)+"/"+str(q)
				if segments.has(key): continue
				segments[key] = true
				_boundary("TempleOuterEdge",p,q,FLOOR+1.3)
				var size := Vector3(.20,.22,q.y-p.y) if vertical else Vector3(q.x-p.x,.22,.20)
				_visual_box(trim,"StoneCopingEdge",Vector3(center.x,FLOOR+.02,center.y),size,"stone")

func _in_walk(point: Vector2) -> bool:
	for rect in _walk_rects:
		if rect.has_point(point): return true
	return false

func _garden_island(parent: Node3D, source: Node3D, position_value: Vector3) -> void:
	var garden := Node3D.new(); garden.name = "MossStoneGarden"; parent.add_child(garden)
	# 低于土面的自然边缘与小起伏接入院地，不制造独立圆碟轮廓。
	var patch := SurfaceTool.new(); patch.begin(Mesh.PRIMITIVE_TRIANGLES); patch.set_material(_earth_material)
	var points: Array[Vector3] = []
	for index in range(17):
		var angle := TAU*float(index)/17.0
		var radius := 1.0+.17*sin(float(index)*2.27)+.11*cos(float(index)*3.19)
		points.append(Vector3(cos(angle)*1.74*radius,-.023,sin(angle)*1.25*radius))
	for index in range(points.size()):
		for vertex in [Vector3(.20,.028,-.1),points[index],points[(index+1)%points.size()]]: patch.add_vertex(vertex)
	patch.generate_normals()
	var bed := MeshInstance3D.new(); bed.name = "IrregularMossAndEarthBed"; bed.mesh = patch.commit(); bed.position = position_value; garden.add_child(bed)
	_collision("GardenIsland",position_value+Vector3(0,.24,0),Vector3(2.9,.55,2.35))
	for index in range(5):
		var p := position_value+Vector3(cos(index*1.41)*1.07,0,sin(index*1.41)*.73)
		_place_stone(garden,index+int(position_value.x),p,.38+.10*(index%3),.075)
	if not is_equal_approx(position_value.x,15.6):
		var variant := posmod(int(position_value.x)*3,5)+1
		_clone_group(source,garden,["60_Cedar_%d_Trunk"%variant,"61_Cedar_%d_Foliage"%variant],position_value+Vector3(.12,-.015,-.14),.59,float(variant)*.29)
	_scattered_source_leaves(garden,position_value)

func _landscape() -> void:
	var terrain := _chunk("RollingMountainEarth",Vector2(27,-2),90)
	var source := APPROACH.instantiate() as Node3D
	var earth_source := source.find_child("01_Terrain_Watertight_Sculpted_Earth",true,false) as MeshInstance3D
	var material := earth_source.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	material.uv1_triplanar = true; material.uv1_scale = Vector3(.3,.3,.3); material.roughness = .94; material.albedo_color = Color(.46,.54,.48)
	var builder := SurfaceTool.new(); builder.begin(Mesh.PRIMITIVE_TRIANGLES); builder.set_material(material)
	for x in range(-24,83,2):
		for z in range(-42,27,2):
			var points := [Vector3(x,_landscape_height(x,z),z),Vector3(x+2,_landscape_height(x+2,z),z),Vector3(x+2,_landscape_height(x+2,z+2),z+2),Vector3(x,_landscape_height(x,z+2),z+2)]
			for i in [0,1,2,0,2,3]:
				builder.set_uv(Vector2(points[i].x,points[i].z)*.3); builder.add_vertex(points[i])
	builder.generate_normals()
	var ground := MeshInstance3D.new(); ground.name = "SculptedContinuousMountainGround"; ground.mesh = builder.commit(); terrain.add_child(ground)
	var grove := _chunk("OuterCedarGrove",Vector2(28,-8),86)
	# 前庭后方缺口形成两簇杉林，远山树线高低错落，不侵入实际可走面。
	var places := [Vector2(-15,-8),Vector2(-11,-10),Vector2(-5,-11),Vector2(1,-10),Vector2(7,-8),Vector2(11,-7.6),Vector2(15,-7.4),Vector2(17,-11.8),Vector2(21,-13.8),Vector2(27,-13.7),Vector2(32,-18),Vector2(36,-21),Vector2(42,-22),Vector2(48,-21),Vector2(53,-17),Vector2(58,-16),Vector2(65,-17),Vector2(72,-14),Vector2(74,-7),Vector2(72,2),Vector2(62,3.8),Vector2(60,7.0),Vector2(55,10.5),Vector2(49,11),Vector2(36,10.8),Vector2(29,11),Vector2(23,11),Vector2(16,11.2),Vector2(10,7.5)]
	for index in range(places.size()):
		var p: Vector2 = places[index]
		var scale_value := .72+float(index%4)*.10
		if index in [7,14,27]:
			var snag: Node3D = ATMOSPHERE.dead_tree_at(_atmosphere_materials,Vector3(p.x,_landscape_height(p.x,p.y)-.03,p.y),.78 if index==27 else 1.03,float(index)*.41)
			grove.add_child(snag,true)
			var branches: Array[MeshInstance3D] = []
			for mesh in snag.find_children("*","MeshInstance3D",true,false): branches.append(mesh)
			_register_tree_occluder(branches)
		else:
			# 保留已验遮挡位置x49的原树形，其余外林复用原五株的自然高矮差。
			var variant := 2 if is_equal_approx(p.x,49.0) else posmod(index*3,5)+1
			_clone_group(source,grove,["60_Cedar_%d_Trunk"%variant,"61_Cedar_%d_Foliage"%variant],Vector3(p.x,_landscape_height(p.x,p.y)-.03,p.y),scale_value,float(index%5)*.57)
	# 原岩组拆成独石后逐块贴当地土坡，界外一石一高程；不再保留山阶原高差。
	var stones := [Vector2(10.8,-6.1),Vector2(12.1,-6.6),Vector2(13.6,-6.0),Vector2(15.1,-6.5),Vector2(16.5,-6.1),Vector2(12.4,9.0),Vector2(14.0,9.3),Vector2(15.8,9.2),Vector2(17.2,9.3),Vector2(19.0,9.3),Vector2(22.0,9.0),Vector2(24.1,9.2),Vector2(26.0,9.1),Vector2(28.5,9.4),Vector2(31.0,9.0),Vector2(34.0,9.2),Vector2(37.0,9.4),Vector2(51.5,9.0),Vector2(54.4,9.2)]
	for index in range(stones.size()):
		var p: Vector2 = stones[index]
		_place_stone(terrain,index*3,Vector3(p.x,_landscape_height(p.x,p.y),p.y),.95+.2*(index%4),.15)
	source.free()

func _landscape_height(x: float, z: float) -> float:
	var base := clampf((x-.6)*.444,0.0,2.86)-.58
	var distance_to_walk := INF
	for rect in _walk_rects:
		var nearest := Vector2(clampf(x,rect.position.x,rect.end.x),clampf(z,rect.position.y,rect.end.y))
		distance_to_walk = minf(distance_to_walk,nearest.distance_to(Vector2(x,z)))
	if x < 9.5:
		distance_to_walk = maxf(0,absf(z)-3.4)
	var hills := sin(x*.14+z*.10)*.55+sin(x*.32-z*.19)*.28
	return base + minf(distance_to_walk*.17,2.4) + hills*minf(distance_to_walk*.20,1.0)

func _clone_fitted(source: Node3D, parent: Node3D, prefixes: Array, target: Vector3, size: Vector3) -> void:
	var count := parent.get_child_count()
	_clone_group(source,parent,prefixes,target,1.0)
	if parent.get_child_count() == count: return
	var group: Node3D = parent.get_child(parent.get_child_count()-1)
	var bounds := AABB(); var initialized := false
	for child in group.get_children():
		if child is MeshInstance3D:
			var aabb: AABB = child.transform*child.get_aabb()
			bounds = bounds.merge(aabb) if initialized else aabb; initialized = true
	if initialized: group.scale = size/bounds.size.max(Vector3(.001,.001,.001))

func _clone_group(source: Node3D, parent: Node3D, prefixes: Array, target: Vector3, scale_value: float, yaw: float = 0.0) -> void:
	var selected: Array[MeshInstance3D] = []
	var bounds := AABB(); var initialized := false
	for node in source.find_children("*","MeshInstance3D",true,false):
		for prefix in prefixes:
			if str(node.name).begins_with(str(prefix)):
				selected.append(node)
				var value := _bounds_in(node,source)
				bounds = bounds.merge(value) if initialized else value; initialized = true; break
	if not initialized: return
	var root_node := Node3D.new(); root_node.name = "ReusedOriginalDetail"; parent.add_child(root_node)
	root_node.position = target; root_node.rotation.y = yaw; root_node.scale = Vector3.ONE*scale_value
	var origin := Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
	var copies: Array[MeshInstance3D] = []
	for node in selected:
		var copy := MeshInstance3D.new(); copy.name = node.name; copy.mesh = node.mesh
		copy.transform = _transform_in(node,source); copy.position -= origin; root_node.add_child(copy); copies.append(copy)
		if str(copy.name).begins_with("10_Torii") or str(copy.name).begins_with("11_Torii"):
			var body := StaticBody3D.new(); body.name = "ReusedSanmonSolidStructure"; _physics.add_child(body)
			var shape := CollisionShape3D.new(); shape.shape = copy.mesh.create_trimesh_shape()
			shape.transform = _transform_in(copy,self); body.add_child(shape)
	for prefix in prefixes:
		if str(prefix).begins_with("60_Cedar") or str(prefix).begins_with("61_Cedar"):
			_register_tree_occluder(copies); break

func _transform_in(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY; var cursor: Node = node
	while cursor != ancestor and cursor != null:
		if cursor is Node3D: result = cursor.transform*result
		cursor = cursor.get_parent()
	return result

func _bounds_in(node: MeshInstance3D, ancestor: Node3D) -> AABB:
	return _transform_in(node,ancestor)*node.get_aabb()

func _collision(name_value: String, position_value: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new(); body.name = name_value; body.position = position_value; _physics.add_child(body)
	var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = size.max(Vector3(.015,.015,.015)); shape.shape = box; body.add_child(shape)
	return body

func _boundary(name_value: String, a: Vector2, b: Vector2, y: float) -> void:
	var delta := b-a
	var wall := _collision(name_value,Vector3((a.x+b.x)*.5,y,(a.y+b.y)*.5),Vector3(delta.length()+.015,4.0,.12))
	wall.rotation.y = -atan2(delta.y,delta.x)

func _visual_box(parent: Node3D, name_value: String, position_value: Vector3, size: Vector3, material_key: String) -> MeshInstance3D:
	var node := MeshInstance3D.new(); node.name = name_value; node.position = position_value
	var mesh := BoxMesh.new(); mesh.size = size; mesh.material = _materials[material_key]; node.mesh = mesh; parent.add_child(node)
	return node

func _lamp(parent: Node3D, position_value: Vector3, color: Color, energy: float, radius: float) -> void:
	var light := OmniLight3D.new(); light.name = "LanternLightPool"; light.position = position_value
	light.light_color = color; light.light_energy = energy; light.omni_range = radius; light.omni_attenuation = 1.4; light.shadow_enabled = false
	parent.add_child(light)

func _contact_shadow(parent: Node3D, position_value: Vector3, size: Vector2, opacity: float) -> void:
	var material := ShaderMaterial.new(); var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, depth_draw_never; uniform float opacity=0.3; void fragment(){vec2 p=(UV-vec2(0.5))*2.0; float r=length(p); ALBEDO=vec3(0.025,0.035,0.035); ALPHA=(1.0-smoothstep(0.25,1.0,r))*opacity;}"
	material.shader = shader; material.set_shader_parameter("opacity",opacity)
	var plane := QuadMesh.new(); plane.size = size
	var node := MeshInstance3D.new(); node.name = "GroundedContactShade"; node.mesh = plane; node.material_override = material
	node.position = position_value; node.rotation.x = -PI/2; node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; parent.add_child(node)

func _make_source_library() -> void:
	var source := APPROACH.instantiate() as Node3D
	_source_stones = STONE_LIBRARY.extract(source.find_child("51_Layered_Rocks_Front",true,false))
	_source_pavers = STONE_LIBRARY.extract(source.find_child("04_Upper_Landing_Flagstones",true,false))
	_source_leaves = STONE_LIBRARY.extract(source.find_child("72_Leaves_On_Stone",true,false))
	var earth: MeshInstance3D = source.find_child("01_Terrain_Watertight_Sculpted_Earth",true,false)
	_earth_material = earth.mesh.surface_get_material(0).duplicate()
	_earth_material.uv1_triplanar = true; _earth_material.uv1_world_triplanar = true; _earth_material.uv1_scale = Vector3(.6,.6,.6)
	_earth_material.albedo_color = Color(.58,.60,.51); _earth_material.roughness = .97
	var trunk: MeshInstance3D = source.find_child("60_Cedar_2_Trunk",true,false)
	_atmosphere_materials = {"bark":trunk.mesh.surface_get_material(0),"wood":_materials.wood,"stone":_source_stones[0].mesh.surface_get_material(0),"earth":_earth_material}
	source.free()

func _place_stone(parent: Node3D, index: int, position_value: Vector3, width: float, bury: float) -> void:
	if _source_stones.is_empty(): return
	var source: Dictionary = _source_stones[posmod(index,_source_stones.size())]
	var bounds: AABB = source.mesh.get_aabb()
	var scale_value := width/maxf(bounds.size.x,bounds.size.z)
	var stone := MeshInstance3D.new(); stone.name = "GroundedSourceStone"; stone.mesh = source.mesh
	stone.position = position_value-Vector3(0,bury,0); stone.scale = Vector3.ONE*scale_value
	stone.rotation.y = float(index%7)*.52; parent.add_child(stone,true)

func _on_paving(point: Vector2) -> bool:
	# 横向主路、回廊南北路与内庭环路；路外泥土同样可走，视觉主次不改变物理面。
	for room in ROOM_RECTS:
		if room.has_point(point): return false
	var roads := [Rect2(9.5,-1.4,19.5,2.8),Rect2(18.6,-5,2.8,10.8),Rect2(11.2,3.45,17.8,2.1),Rect2(29,-7.0,26.6,2.8),Rect2(32.7,-13.8,2.6,20.3),Rect2(50.0,-13.8,2.6,20.3),Rect2(31,-13.3,24,2.6),Rect2(27,3.35,28,2.3)]
	for road in roads:
		if road.has_point(point): return true
	return false

func _earth_surface(rect: Rect2) -> ArrayMesh:
	# 新土院必须给原木板/石地留下完整洞口；不能仅压低平均高度造成部分板面穿插。
	var xs: Array[float] = [rect.position.x,rect.end.x]; var zs: Array[float] = [rect.position.y,rect.end.y]
	for room in ROOM_RECTS:
		var overlap: Rect2 = room.intersection(rect)
		if not overlap.has_area(): continue
		for x in [overlap.position.x,overlap.end.x]:
			if not xs.has(x): xs.append(x)
		for z in [overlap.position.y,overlap.end.y]:
			if not zs.has(z): zs.append(z)
	xs.sort(); zs.sort()
	var builder := SurfaceTool.new(); builder.begin(Mesh.PRIMITIVE_TRIANGLES); builder.set_material(_earth_material)
	for x in range(xs.size()-1):
		for z in range(zs.size()-1):
			var center := Vector2((xs[x]+xs[x+1])*.5,(zs[z]+zs[z+1])*.5)
			var covered := false
			for room in ROOM_RECTS:
				if room.has_point(center): covered = true; break
			if covered: continue
			var corners := [Vector3(xs[x],FLOOR-.017,zs[z]),Vector3(xs[x+1],FLOOR-.017,zs[z]),Vector3(xs[x+1],FLOOR-.017,zs[z+1]),Vector3(xs[x],FLOOR-.017,zs[z+1])]
			for index in [0,1,2,0,2,3]:
				builder.set_uv(Vector2(corners[index].x,corners[index].z)*.6); builder.add_vertex(corners[index])
	builder.generate_normals()
	return builder.commit()

func _group_bounds_in_world(group: Node3D) -> AABB:
	var bounds := AABB(); var initialized := false
	for mesh_node in group.find_children("*","MeshInstance3D",true,false):
		var value := _bounds_in(mesh_node,self)
		bounds = bounds.merge(value) if initialized else value; initialized = true
	return bounds

func _ground_coffin(model: Node3D, art: Node3D, night_id: int) -> void:
	var coffin := model.find_child("PaperCoffin" if night_id == 3 else "RitualPaperCoffin",true,false) as Node3D
	if coffin == null: return
	var before := _group_bounds_in_world(coffin)
	# 原底面比新共同地面高约2cm；先真实落地，再按实体底座轮廓处理接触暗部。
	coffin.position.y += FLOOR-before.position.y
	var bounds := _group_bounds_in_world(coffin)
	var material := ShaderMaterial.new(); var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, depth_draw_never; void fragment(){vec2 p=abs((UV-vec2(0.5))*2.0); float edge=max(max(p.x,p.y),(p.x+p.y)*0.69); ALBEDO=vec3(0.026,0.022,0.018); ALPHA=(1.0-smoothstep(0.70,1.0,edge))*0.38;}"
	material.shader = shader
	var plane := QuadMesh.new(); plane.size = Vector2(bounds.size.x*1.15,bounds.size.z*1.12)
	var shade := MeshInstance3D.new(); shade.name = "CoffinFootprintContactShade"; shade.mesh = plane; shade.material_override = material
	shade.position = Vector3(bounds.get_center().x,FLOOR+.007,bounds.get_center().z); shade.rotation.x = -PI/2
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; art.add_child(shade)

func _open_root_planting_well(model: Node3D, art: Node3D, offset: Vector3) -> void:
	# 原神木底0.0被原石台顶0.61穿入；保留神木，给根区真实下沉种植开口。
	var old_dais := model.find_child("Rear_sanctuary_dais",true,false)
	if old_dais != null: old_dais.get_parent().remove_child(old_dais); old_dais.free()
	var frame := Node3D.new(); frame.name = "HondenRootPlantingWell"; art.add_child(frame)
	for area in [Rect2(-5.825,-8.025,4.075,5.05),Rect2(.70,-8.025,5.125,5.05),Rect2(-1.75,-8.025,2.45,2.925),Rect2(-1.75,-3.10,2.45,.125)]:
		_visual_box(frame,"OriginalStoneDaisAroundRoots",offset+Vector3(area.get_center().x,-.015,area.get_center().y),Vector3(area.size.x,1.25,area.size.y),"stone")
	var soil := MeshInstance3D.new(); soil.name = "HondenRootSoilPatch"
	var plane := PlaneMesh.new(); plane.size = Vector2(2.45,2.0); plane.material = _earth_material
	soil.mesh = plane; soil.position = offset+Vector3(-.525,-.005,-4.10); frame.add_child(soil)
	# 纸人继续站在石台上，不悬在新开口里；六人数量与原纸形都保留。
	var attendant := model.find_child("Folded_washi_attendant_2",true,false) as Node3D
	if attendant != null: attendant.position.x -= 1.0
	var rim := [Vector2(-1.77,-4.80),Vector2(-1.78,-4.10),Vector2(-1.77,-3.50),Vector2(.72,-4.75),Vector2(.73,-4.10),Vector2(.72,-3.48),Vector2(-1.30,-5.12),Vector2(-.55,-5.14),Vector2(.25,-5.12)]
	for index in range(rim.size()):
		_place_stone(frame,index*5+3,offset+Vector3(rim[index].x,.61,rim[index].y),.36+.045*(index%3),.03)

func _register_tree_occluder(meshes: Array[MeshInstance3D]) -> void:
	if meshes.is_empty(): return
	var bounds := AABB(); var initialized := false
	for mesh_node in meshes:
		var value := _bounds_in(mesh_node,self)
		bounds = bounds.merge(value) if initialized else value; initialized = true
	_tree_occluders.append({"meshes":meshes,"bounds":bounds,"opacity":1.0,"occluded":false,"materials":[],"overrides_active":false})

func update_tree_occlusion(position: Vector3, delta: float, camera: Camera3D = null) -> void:
	# 正交相机真实投影框；默认采用正式镜头固定方向，测试/旧单参调用仍可运行。
	var right := Vector3.RIGHT; var up := Vector3(0,11.0,-6.2).normalized(); var toward_camera := Vector3(0,6.2,11).normalized()
	if is_instance_valid(camera):
		right = camera.global_basis.x.normalized(); up = camera.global_basis.y.normalized(); toward_camera = camera.global_basis.z.normalized()
	var actor_center := position+Vector3.UP*.90
	var point := Vector2(actor_center.dot(right),actor_center.dot(up))
	var actor_rect := Rect2(point-Vector2(.72,.95),Vector2(1.44,1.90))
	for entry in _tree_occluders:
		var bounds: AABB = entry.bounds
		var projection := Rect2(); var initialized := false; var front_depth := -INF
		for index in range(8):
			var corner := bounds.get_endpoint(index)
			var projected := Vector2(corner.dot(right),corner.dot(up))
			projection = projection.expand(projected) if initialized else Rect2(projected,Vector2.ZERO)
			initialized = true; front_depth = maxf(front_depth,corner.dot(toward_camera))
		# 退出阈值比进入宽0.35m，人物在树冠边缘微动不会逐帧闪烁。
		var actor_test := actor_rect.grow(.35 if entry.occluded else 0.0)
		var blocked := front_depth>actor_center.dot(toward_camera)+.20 and projection.intersects(actor_test)
		entry.occluded = blocked
		var target := .012 if blocked else 1.0
		var opacity := move_toward(float(entry.opacity),target,clampf(delta,0.0,.10)*(5.5 if blocked else 2.0))
		_apply_tree_opacity(entry,opacity)

func _apply_tree_opacity(entry: Dictionary, opacity: float) -> void:
	entry.opacity = opacity
	if opacity >= .999:
		if entry.overrides_active:
			for record in entry.materials: record.mesh.set_surface_override_material(record.surface,record.previous)
			entry.overrides_active = false
		return
	if entry.materials.is_empty():
		for mesh_node in entry.meshes:
			for surface in range(mesh_node.mesh.get_surface_count()):
				var original := mesh_node.get_active_material(surface) as StandardMaterial3D
				if original == null: continue
				var faded := original.duplicate() as StandardMaterial3D
				# Compatibility可靠支持的逐实例材质alpha；不改共享原材质或物理。
				faded.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				entry.materials.append({"mesh":mesh_node,"surface":surface,"previous":mesh_node.get_surface_override_material(surface),"faded":faded,"alpha":original.albedo_color.a})
	for record in entry.materials:
		var color: Color = record.faded.albedo_color; color.a = float(record.alpha)*opacity; record.faded.albedo_color = color
		if not entry.overrides_active: record.mesh.set_surface_override_material(record.surface,record.faded)
	entry.overrides_active = true

# 大地表接收柱、梁、树的影子，但不向自己的共面三角形重复投影。
# 原GLB均双面材质；这条规则仅作用于当前连续场景实例，不修改导入资产。
func _configure_shadow_receivers() -> void:
	var prefixes := ["01_Terrain", "02_Path", "03_Stone_Stairs", "04_Upper_Landing", "Deck_aged_cedar_planks", "Deck_underfloor", "Deck_understructure", "Garden_ground", "WalkableEarthSurface", "SculptedContinuousMountainGround", "IrregularMossAndEarthBed", "WornStoneSlabPaving", "StoneRetainingFoundation", "SourceRoomStoneFoundation"]
	for node in find_children("*","GeometryInstance3D",true,false):
		for prefix in prefixes:
			if str(node.name).begins_with(prefix):
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				break

func _scattered_source_leaves(parent: Node3D, at: Vector3) -> void:
	if _source_leaves.is_empty(): return
	var builder := SurfaceTool.new(); builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	builder.set_material(_source_leaves[0].mesh.surface_get_material(0))
	for index in range(43):
		# 疏密由两处避风根角形成，不把整片原落叶层非均匀拉伸到新矩形。
		var angle := float(index)*2.399+at.x
		var radius := .35+pow(float(posmod(index*17,43))/43.0,1.6)*1.25
		var cluster := Vector3(-.35,.012,.28) if index<29 else Vector3(.62,.012,-.32)
		var position_value := at+cluster+Vector3(cos(angle)*radius,0,sin(angle)*radius*.56)
		var scale_value := .64+.35*float(index%5)/4.0
		var transform := Transform3D(Basis(Vector3.UP,angle).scaled(Vector3.ONE*scale_value),position_value)
		var leaf: Mesh = _source_leaves[posmod(index*11+int(at.x),_source_leaves.size())].mesh
		builder.append_from(leaf,0,transform)
	var leaves := MeshInstance3D.new(); leaves.name = "WindGatheredOriginalLeaves"; leaves.mesh = builder.commit()
	leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; parent.add_child(leaves)

func _at_paving_edge(point: Vector2) -> bool:
	for offset in [Vector2(.38,0),Vector2(-.38,0),Vector2(0,.44),Vector2(0,-.44)]:
		if not _on_paving(point+offset): return true
	return false
