# 同源材质的荒废供养小景。只生成美术，不创建碰撞、不读剧情、也不更改通路。
extends RefCounted

static func build(materials: Dictionary, floor_y: float) -> Node3D:
	var scene := Node3D.new(); scene.name = "ForecourtAbandonedOffering"
	var bark: StandardMaterial3D = materials.bark.duplicate()
	bark.albedo_texture = materials.wood.albedo_texture
	bark.albedo_color = Color(.58,.53,.46)
	bark.roughness = .98; bark.uv1_triplanar = false; bark.uv1_scale = Vector3(.60,1.0,1.0)
	var pale_wood: StandardMaterial3D = materials.wood.duplicate()
	pale_wood.albedo_color = Color(.51,.44,.33); pale_wood.roughness = 1.0
	var stone: StandardMaterial3D = materials.stone.duplicate()
	stone.albedo_color = Color(.70,.75,.69); stone.roughness = .97
	var moss: StandardMaterial3D = materials.earth.duplicate()
	moss.albedo_color = Color(.30,.34,.23); moss.roughness = 1.0
	var bone := _material(Color("827965"))
	var dry_leaf := _material(Color("4a4232"))
	var spent_petal := _material(Color("4e3532"))
	var dry_blood := _material(Color("39271f"))
	var exposed_blood := _material(Color("493027"))
	var grove := Node3D.new(); grove.name = "LightningSplitCedar"; grove.position = Vector3(15.65,floor_y-.018,-3.27); scene.add_child(grove)
	_dead_tree(grove,bark,pale_wood)
	var shrine := Node3D.new(); shrine.name = "HalfBuriedRoadsideMemorial"; shrine.position = Vector3(16.60,floor_y-.29,-3.12)
	shrine.rotation_degrees = Vector3(-6,-13,-11); scene.add_child(shrine)
	_tablet(shrine,stone,moss)
	# 枯花曾被放在旧碑前，如今倒向树根；骨片藏在同一根石缝，不均匀撒满道路。
	_withered_offering(scene,Vector3(16.56,floor_y+.02,-2.43),dry_leaf,spent_petal)
	_hidden_bones(scene,Vector3(15.00,floor_y+.018,-2.91),bone)
	_stain(scene,"DriedSeepAtTablet",Vector3(16.67,floor_y+.006,-2.75),Vector2(.47,.32),1.4,dry_blood)
	_stain(scene,"DriedSeepAtRoot",Vector3(15.20,floor_y+.006,-2.58),Vector2(.22,.12),.2,exposed_blood)
	# 檐外拖痕只占两条短木缝；厚度不到一毫米，颜色来自材质而非自发光。
	_stain(scene,"OldTraceAtVerandaEdge",Vector3(18.93,floor_y+.004,-4.40),Vector2(.085,.44),.43,dry_blood)
	_stain(scene,"OldTraceAtVerandaSeam",Vector3(19.02,floor_y+.004,-4.66),Vector2(.035,.19),.14,exposed_blood)
	return scene

static func dead_tree_at(materials: Dictionary, at: Vector3, scale_value: float, yaw: float) -> Node3D:
	var tree := Node3D.new(); tree.name = "QuietDeadCedar"; tree.position = at
	tree.scale = Vector3.ONE*scale_value; tree.rotation.y = yaw
	var bark: StandardMaterial3D = materials.bark.duplicate(); bark.roughness = .98
	bark.uv1_triplanar = false; bark.uv1_scale = Vector3(.60,1.0,1.0)
	bark.albedo_texture = materials.wood.albedo_texture; bark.albedo_color = Color(.58,.53,.46)
	var exposed: StandardMaterial3D = materials.wood.duplicate(); exposed.albedo_color = Color(.46,.39,.29)
	_dead_tree(tree,bark,exposed)
	return tree

static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new(); material.albedo_color = color; material.roughness = 1.0
	return material

static func _dead_tree(parent: Node3D, bark: Material, exposed: Material) -> void:
	# 错节主干、分叉与断口是连续锥管；根的终点埋入土面，避免直插圆柱。
	_tube(parent,"SplitCedarTrunk",[Vector3(0,-.06,0),Vector3(-.12,.52,.02),Vector3(-.07,1.30,.02),Vector3(.12,2.13,.05),Vector3(.05,2.88,.03),Vector3(.29,3.68,-.02)], [.27,.23,.19,.14,.085,.024],bark,9)
	_tube(parent,"WestBrokenBough",[Vector3(-.03,1.18,.04),Vector3(-.56,1.64,.12),Vector3(-.89,2.27,.03),Vector3(-1.12,2.60,-.04)], [.16,.105,.065,.018],bark,7)
	_tube(parent,"WestDryFork",[Vector3(-.54,1.66,.10),Vector3(-1.03,1.93,.25),Vector3(-1.30,2.19,.33)],[.075,.04,.009],bark,6)
	_tube(parent,"RaisedEasternLimb",[Vector3(.10,2.04,.04),Vector3(.58,2.43,-.04),Vector3(.99,2.51,-.13),Vector3(1.33,2.93,-.09)],[.14,.095,.053,.015],bark,7)
	_tube(parent,"EastBareFork",[Vector3(.68,2.45,-.05),Vector3(.77,2.95,-.02),Vector3(.67,3.20,.05)],[.061,.035,.009],bark,6)
	_tube(parent,"RearSnappedLimb",[Vector3(.02,1.67,-.05),Vector3(.20,2.12,-.54),Vector3(.10,2.48,-.69)],[.11,.060,.011],bark,7)
	_tube(parent,"DryCrownFork",[Vector3(.10,2.96,.04),Vector3(-.30,3.33,.18),Vector3(-.47,3.63,.18)],[.068,.040,.009],bark,6)
	# 细梢在断枝外再分叉，折点前后错开；主干仍保持一眼可读的疏空轮廓。
	var fine_twigs := [
		[Vector3(-.88,2.27,.03),Vector3(-.86,2.62,-.04),Vector3(-1.02,2.88,-.10),Vector3(-.99,3.10,-.15)],
		[Vector3(-1.09,2.58,-.04),Vector3(-1.30,2.78,.01),Vector3(-1.49,2.78,.08)],
		[Vector3(-1.00,1.95,.24),Vector3(-1.23,2.30,.35),Vector3(-1.21,2.52,.41)],
		[Vector3(1.01,2.55,-.12),Vector3(1.32,2.63,-.22),Vector3(1.51,2.85,-.24)],
		[Vector3(1.29,2.87,-.08),Vector3(1.35,3.18,.03),Vector3(1.26,3.40,.08)],
		[Vector3(.71,3.04,.01),Vector3(.98,3.22,.10),Vector3(1.14,3.44,.11)],
		[Vector3(.19,3.36,.02),Vector3(.15,3.80,.09),Vector3(.30,4.02,.18),Vector3(.28,4.19,.20)],
		[Vector3(-.30,3.33,.18),Vector3(-.57,3.39,.33),Vector3(-.76,3.64,.40)],
		[Vector3(.11,2.43,-.66),Vector3(.39,2.58,-.84),Vector3(.50,2.92,-.87)],
		[Vector3(-.05,1.62,.16),Vector3(-.17,1.95,.43),Vector3(-.41,2.11,.59)],
	]
	for index in range(fine_twigs.size()):
		var twig: Array = fine_twigs[index]; var radii: Array[float] = []
		for knot in range(twig.size()): radii.append(lerpf(.037,.0025,float(knot)/float(twig.size()-1)))
		_tube(parent,"CrookedFineTwig_%d"%index,twig,radii,bark,5)
	for index in range(5):
		var angle := float(index)*1.23+.22; var end := Vector3(cos(angle),-.035,sin(angle))
		var knee := Vector3(cos(angle)*.46,.13,sin(angle)*.40)
		_tube(parent,"ExposedRoot_%d"%index,[Vector3(0,.30,0),knee,end*Vector3(.89,1,.76)],[.15,.11,.012],bark,7)
	# 长短不一的树皮裂口沿原干体折线走，保留暗部缝隙与少量撕裂的浅木边。
	var crack := _material(Color("211e19"))
	for index in range(7):
		var angle := float(index)*TAU/7.0+.16
		var radial := Vector3(cos(angle),0,sin(angle))
		var start := Vector3(-.12,.46+float(index%3)*.14,.02)+radial*.229
		var middle := Vector3(-.07,1.16+float(index%2)*.08,.02)+radial*.192
		var end := Vector3(.09,1.89+float(index%4)*.07,.045)+radial*.142
		_tube(parent,"CedarBarkSplit_%d"%index,[start,middle,end],[.010,.016,.003],crack,4)
	# 不规则脱皮纵缝，局部浅木色而非全干白化。
	_tube(parent,"PeeledWoodScar",[Vector3(-.24,.42,.16),Vector3(-.245,.73,.14),Vector3(-.16,1.21,.14)],[.023,.033,.004],exposed,4)
	_tube(parent,"SplitTopSplinter",[Vector3(.18,3.28,.02),Vector3(.34,3.58,.03),Vector3(.40,3.66,.015)],[.027,.021,.002],exposed,4)

	_compact_surfaces(parent)

static func _tablet(parent: Node3D, stone: Material, moss: Material) -> void:
	var silhouette := PackedVector2Array([Vector2(-.32,-.06),Vector2(.31,-.06),Vector2(.29,.87),Vector2(.17,1.13),Vector2(-.19,1.10),Vector2(-.34,.89)])
	_extruded_outline(parent,"WeatheredMemorialStone",silhouette,.19,stone)
	# 碑文已蚀为残缺刻痕：纵列窄凹形跟随碑面，不能作为明亮UI文字。
	for index in range(5):
		var y := .30+index*.135
		_tube(parent,"ErodedInscription_%d"%index,[Vector3(-.025,y,.104),Vector3(-.006,y+.075,.105)],[.012,.010],moss,4)
		if index%2==0:
			_tube(parent,"ErodedInscriptionChip_%d"%index,[Vector3(-.085,y+.03,.104),Vector3(.043,y+.041,.104)],[.007,.005],moss,4)
	# 镜头看向负Z，正Z正面应可见；局部青苔贴根，避免纯色大遮片。
	for index in range(3):
		_stain(parent,"BuriedStoneMoss_%d"%index,Vector3(-.16+index*.15,.015,.12),Vector2(.15,.12),float(index),moss)

	_compact_surfaces(parent)

static func _withered_offering(parent: Node3D, at: Vector3, stalk: Material, petal: Material) -> void:
	var bundle := Node3D.new(); bundle.name = "WitheredOfferingFlowers"; bundle.position = at; parent.add_child(bundle)
	for index in range(7):
		var angle := float(index)*2.37
		var base := Vector3(cos(angle)*.09,0,sin(angle)*.07)
		var high := .24+.045*(index%4)
		var neck := base+Vector3(cos(angle)*.11,high,sin(angle)*.10)
		var tip := neck+Vector3(cos(angle)*.095,-.085-.013*(index%3),sin(angle)*.055)
		_tube(bundle,"BentFlowerStalk_%d"%index,[base,base+Vector3(.04,high*.56,-.015),neck,tip],[.013,.011,.008,.005],stalk,5)
		for leaf_index in range(4):
			var theta := angle+leaf_index*TAU/4.0
			var end := tip+Vector3(cos(theta)*.073,-.045,sin(theta)*.073)
			_leaf(bundle,"CollapsedPetal",tip,end,.037,petal)
		_leaf(bundle,"CurledStemLeaf",base+Vector3(.02,high*.43,0),base+Vector3(-.10,high*.34,.035),.036,stalk)

	_compact_surfaces(bundle)

static func _hidden_bones(parent: Node3D, at: Vector3, material: Material) -> void:
	var remains := Node3D.new(); remains.name = "RootHiddenOldBones"; remains.position = at; remains.rotation.y = -.41; parent.add_child(remains)
	_tube(remains,"PartBuriedLongBone",[Vector3(-.13,.02,.04),Vector3(-.02,.037,.01),Vector3(.19,.029,-.018),Vector3(.29,.014,-.01)],[.044,.027,.024,.04],material,7)
	_tube(remains,"BrokenRibArc",[Vector3(-.02,-.005,-.08),Vector3(.045,.055,-.13),Vector3(.13,.082,-.13),Vector3(.22,.045,-.075)],[.016,.015,.013,.01],material,6)
	_tube(remains,"BuriedSecondFragment",[Vector3(-.25,-.01,.03),Vector3(-.21,.018,.13),Vector3(-.12,.012,.18)],[.02,.025,.012],material,6)

	_compact_surfaces(remains)

static func _stain(parent: Node3D, name_value: String, at: Vector3, size: Vector2, yaw: float, material: Material) -> void:
	var builder := SurfaceTool.new(); builder.begin(Mesh.PRIMITIVE_TRIANGLES); builder.set_material(material)
	var edge: Array[Vector3] = []
	for index in range(15):
		var theta := float(index)*TAU/15.0
		var radius := .43+.12*sin(float(index)*2.6)+.055*cos(float(index)*4.1)
		edge.append(Vector3(cos(theta)*size.x*radius,0,sin(theta)*size.y*radius))
	for index in range(edge.size()):
		for point in [Vector3.ZERO,edge[index],edge[(index+1)%edge.size()]]:
			builder.set_uv(Vector2(point.x,point.z)); builder.add_vertex(point)
	builder.generate_normals()
	var node := _mesh(parent,name_value,builder.commit()); node.position = at; node.rotation.y = yaw
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _leaf(parent: Node3D, name_value: String, a: Vector3, b: Vector3, width: float, material: Material) -> void:
	var direction := b-a
	var sideways := direction.cross(Vector3.UP).normalized()*width
	var center := a.lerp(b,.48)+Vector3(0,.018,0)
	var builder := SurfaceTool.new(); builder.begin(Mesh.PRIMITIVE_TRIANGLES); builder.set_material(material)
	for p in [a,center+sideways,b,a,b,center-sideways,a,b,center+sideways,a,center-sideways,b]:
		builder.set_uv(Vector2(p.x,p.z)); builder.add_vertex(p)
	builder.generate_normals(); _mesh(parent,name_value,builder.commit())

static func _extruded_outline(parent: Node3D, name_value: String, outline: PackedVector2Array, depth: float, material: Material) -> void:
	var builder := SurfaceTool.new(); builder.begin(Mesh.PRIMITIVE_TRIANGLES); builder.set_material(material)
	var center := Vector2(0,.48)
	for index in range(outline.size()):
		var a: Vector2 = outline[index]; var b: Vector2 = outline[(index+1)%outline.size()]
		var v := [Vector3(a.x,a.y,depth*.5),Vector3(b.x,b.y,depth*.5),Vector3(a.x,a.y,-depth*.5),Vector3(b.x,b.y,-depth*.5)]
		for p in [Vector3(center.x,center.y,depth*.5),v[1],v[0],Vector3(center.x,center.y,-depth*.5),v[2],v[3],v[0],v[1],v[2],v[1],v[3],v[2]]:
			builder.set_uv(Vector2(p.x,p.y)); builder.add_vertex(p)
	builder.generate_normals(); _mesh(parent,name_value,builder.commit())

static func _tube(parent: Node3D, name_value: String, points: Array, radii: Array, material: Material, sides: int) -> void:
	var builder := SurfaceTool.new(); builder.begin(Mesh.PRIMITIVE_TRIANGLES); builder.set_material(material)
	var rings: Array = []
	for index in range(points.size()):
		var tangent: Vector3 = points[mini(index+1,points.size()-1)]-points[maxi(index-1,0)]
		tangent = tangent.normalized()
		var side := tangent.cross(Vector3.FORWARD).normalized()
		if side.length_squared()<.01: side = tangent.cross(Vector3.RIGHT).normalized()
		var other := tangent.cross(side).normalized()
		var ring: Array[Vector3] = []
		for face in range(sides):
			var angle := float(face)*TAU/float(sides)
			var width: float = float(radii[index])*(1.0+.085*sin(float(face*3+index)))
			ring.append(points[index]+(side*cos(angle)+other*sin(angle))*width)
		rings.append(ring)
	for index in range(rings.size()-1):
		for face in range(sides):
			var next := (face+1)%sides
			for p in [rings[index][face],rings[index+1][face],rings[index][next],rings[index][next],rings[index+1][face],rings[index+1][next]]:
				builder.set_uv(Vector2(p.y,float(face)/float(sides))); builder.add_vertex(p)
	for endpoint in [0,rings.size()-1]:
		for face in range(sides):
			var next := (face+1)%sides
			var corners: Array = [points[endpoint],rings[endpoint][face],rings[endpoint][next]] if endpoint == 0 else [points[endpoint],rings[endpoint][next],rings[endpoint][face]]
			for p in corners: builder.set_uv(Vector2(p.x,p.z)); builder.add_vertex(p)
	builder.generate_normals(); _mesh(parent,name_value,builder.commit())

static func _mesh(parent: Node3D, name_value: String, mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new(); node.name = name_value; node.mesh = mesh; parent.add_child(node,true)
	return node

# 花瓣和细枝按相同材质合批，轮廓保留而不为每片花瓣增加独立绘制调用。
static func _compact_surfaces(parent: Node3D) -> void:
	var builders: Dictionary = {}
	for node in parent.get_children():
		if not node is MeshInstance3D: continue
		for surface in range(node.mesh.get_surface_count()):
			var material: Material = node.mesh.surface_get_material(surface)
			if not builders.has(material):
				var builder := SurfaceTool.new(); builder.begin(Mesh.PRIMITIVE_TRIANGLES); builder.set_material(material)
				builders[material] = builder
			builders[material].append_from(node.mesh,surface,node.transform)
		parent.remove_child(node); node.free()
	for material in builders:
		_mesh(parent,"WeatheredContourBatch",builders[material].commit())

static func spent_lamp_offering(materials: Dictionary, at: Vector3) -> Node3D:
	var root_node := Node3D.new(); root_node.name = "SpentLampOffering"; root_node.position = at
	_withered_offering(root_node,Vector3.ZERO,_material(Color("464130")),_material(Color("5b4430")))
	# 灯脚旁只剩供花与裂开的小陶盏，和前庭旧碑不是同一个模块复印。
	var clay: Material = materials.stone.duplicate()
	for fragment in [[0.0,1.8],[2.0,3.4],[4.0,5.6]]:
		var points: Array[Vector3] = []; var radii: Array[float] = []
		for index in range(6):
			var angle := lerpf(fragment[0],fragment[1],float(index)/5.0)
			points.append(Vector3(cos(angle)*.16,.03+sin(angle)*.012,sin(angle)*.12)); radii.append(.022)
		_tube(root_node,"BrokenOfferingBowl",points,radii,clay,5)
	_compact_surfaces(root_node)
	return root_node

static func boundary_remains(materials: Dictionary, at: Vector3) -> Node3D:
	var root_node := Node3D.new(); root_node.name = "BoundaryStoneRemains"; root_node.position = at
	var fragment := Node3D.new(); fragment.name = "BuriedBrokenMarker"; fragment.position = Vector3(0,-.19,0)
	fragment.rotation_degrees = Vector3(33,18,23); root_node.add_child(fragment)
	var stone: Material = materials.stone.duplicate()
	_extruded_outline(fragment,"BrokenMossBoundaryStone",PackedVector2Array([Vector2(-.22,0),Vector2(.25,0),Vector2(.25,.51),Vector2(.10,.62),Vector2(-.02,.55),Vector2(-.20,.68)]),.15,stone)
	_hidden_bones(root_node,Vector3(-.16,-.02,.20),_material(Color("716c58")))
	_withered_offering(root_node,Vector3(.28,-.035,.13),_material(Color("444331")),_material(Color("49382b")))
	return root_node

static func roadside_weeds(places: Array[Vector3]) -> Node3D:
	var root_node := Node3D.new(); root_node.name = "PathEdgeDryGrass"
	var material := _material(Color("494735"))
	for index in range(places.size()):
		var base: Vector3 = places[index]
		for blade in range(7):
			var angle := float(index)*.73+float(blade)*2.39
			var spread := Vector3(cos(angle),0,sin(angle))
			var bottom := base+spread*.10
			var high := .17+float(posmod(index*3+blade,5))*.025
			_tube(root_node,"BentDryStem",[bottom,bottom+Vector3(0,high*.65,0)+spread*.025,bottom+Vector3(0,high,0)+spread*.065,bottom+Vector3(0,high*.87,0)+spread*.13],[.010,.008,.004,.001],material,4)
	_compact_surfaces(root_node)
	for mesh in root_node.get_children(): mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root_node
