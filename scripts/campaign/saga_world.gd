# 后六章连续地区。地面、路网、边界独立于剧情；同一章节可回走，不用传送冒充相连空间。
extends Node3D
const TEXTURES := {
	"stone":preload("res://assets/3d/night02_corridor/night02_corridor_stone.png"),
	"wood":preload("res://assets/3d/night02_corridor/night02_corridor_wood.png"),
	"roof":preload("res://assets/3d/night02_corridor/night02_corridor_roof.png"),
	"paper":preload("res://assets/3d/night02_corridor/night02_corridor_paper.png"),
	"plaster":preload("res://assets/3d/night02_corridor/night02_corridor_plaster.png")
}
const APPROACH := preload("res://assets/3d/act01_approach/act01_approach.glb")
const MIRROR_SOURCE := preload("res://assets/3d/night04_mirror/night04_mirror.glb")
const STONES := preload("res://scripts/campaign/act_one_stone_library.gd")
const FONT := preload("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
const TITLES := {2:"无眠街",3:"逆水渡",4:"镜中双影",5:"借命灯",6:"百夜无更",7:"天明之前"}
const LANDMARKS := {2:"SleeplessMarket",3:"ReverseWaterWharf",4:"TwinMirrorWorkshop",5:"BorrowedLifeClinic",6:"HundredNightRefuge",7:"BeforeDawnCore"}
var _materials: Dictionary = {}
var _source_stones: Array[Dictionary] = []
var _source_trees: Array[Dictionary] = []
var _source_roof: Dictionary = {}
var _cells: Dictionary = {}
var _physics: Node3D
var _art: Node3D
var _chapter := 2

static func bounds(chapter: int) -> Dictionary:
	var all := _rects(chapter)
	if all.is_empty(): return {}
	var area: Rect2 = all[0]
	for rect in all: area=area.merge(rect)
	return {"x":[area.position.x,area.end.x],"z":[area.position.y,area.end.y],"y":[-2.0,8.0]}

static func anchors(chapter: int) -> Dictionary:
	var values: Dictionary
	match chapter:
		2: values={"gate":[-21,0,0],"inn":[-14,0,-7],"square":[-8,0,7],"shop":[2,0,-7],"canal":[13,0,7],"alley":[18,0,-7],"exit":[22,0,0]}
		3: values={"gate":[-21,0,0],"dock":[0,0,0],"warehouse":[-14,0,-8],"bay":[15,0,0],"shrine":[15,0,10],"exit":[-3,0,10]}
		4: values={"gate":[-21,0,1],"shop":[-14,0,1],"workshop":[-14,0,-8],"corridor":[0,0,-8],"archive":[15,0,-8],"echo":[15,0,1],"exit":[22,0,1],"courtyard":[0,0,5]}
		5: values={"gate":[-20,0,0],"shop":[-11,0,0],"ward":[-11,0,-8],"yard":[1,0,0],"store":[13,0,0],"sanctum":[13,0,-9],"exit":[22,0,0]}
		6: values={"gate":[-20,0,0],"honden":[-7,0,-10],"courtyard":[-7,0,0],"junction":[9,0,0],"dock":[19,0,10],"alley":[19,0,-9],"drain":[9,0,10],"exit":[23,0,10]}
		7: values={"gate":[-21,0,0],"stairs":[-13,0,0],"hall":[0,0,0],"mirror":[0,0,-11],"names":[12,0,0],"exit":[23,0,0],"anchor_west":[-8,0,-11],"anchor_east":[8,0,-11],"anchor_north":[0,0,10]}
		_: return {}
	values["battle"]={2:[7,0,0],3:[5,0,0],4:[0,0,0],5:[1,0,0],6:[-7,0,0],7:[0,0,0]}[chapter]
	values["spawn"]=values.gate.duplicate()
	values["rest"]=values.get({2:"inn",3:"gate",4:"gate",5:"gate",6:"courtyard",7:"stairs"}[chapter]).duplicate()
	if not values.has("shop"): values["shop"]=values.get({3:"warehouse",6:"junction",7:"stairs"}.get(chapter,"gate")).duplicate()
	var aliases: Dictionary={
		2:{"street":"gate","lamp_shop":"shop","drain":"canal","dyehouse":"alley"},
		3:{"wharf":"dock","west_warehouse":"warehouse","retreat_bank":"exit","bridge":"shrine"},
		4:{"mirror_workshop":"workshop","gallery":"corridor"},
		5:{"sick_ward":"ward","lamp_courtyard":"yard","clinic":"gate"},
		6:{"city_streets":"junction","relay":"courtyard","gates":"gate","clock_district":"alley"},
		7:{"mirror_core":"hall","final_dais":"mirror","dawn_route":"exit"}
	}[chapter]
	for key in aliases: values[key]=values[aliases[key]].duplicate()
	return values

static func labels(chapter: int) -> Dictionary:
	var result: Dictionary={
		2:{"gate":"无眠街口","inn":"客栈","square":"晒场","shop":"灯铺","canal":"茶棚水口","alley":"染坊后巷","exit":"往逆水渡"},
		3:{"gate":"渡口入口","dock":"主码头","warehouse":"西仓","bay":"内湾","shrine":"旧堤小镜结","exit":"外岸灯路"},
		4:{"gate":"镜坊前院","shop":"镜坊柜台","workshop":"抛光间","corridor":"镜廊","archive":"修阵室","echo":"留声小室","courtyard":"镜坊中庭","exit":"往医馆"},
		5:{"gate":"医馆前堂","shop":"药房柜台","ward":"病房","yard":"灯影后院","store":"药库后药棚","sanctum":"地下静室","exit":"往山门"},
		6:{"gate":"山门","honden":"本殿","courtyard":"前庭","junction":"北街灯节点","dock":"外撤码头","alley":"后巷","drain":"排水道入口","exit":"往镜阵"},
		7:{"gate":"准备区","stairs":"休整石阶","hall":"主镜厅","mirror":"主镜台","names":"刻名板","exit":"天明外口","anchor_west":"西镜锚","anchor_east":"东镜锚","anchor_north":"护持镜锚"}
	}.get(chapter,{})
	return result.duplicate(true)

static func routes(chapter: int) -> Array:
	# 每条折线从共享干道抵达真正交互锚点；首条专供真实胶囊长程验收。
	match chapter:
		2: return [[[-21,0,0],[22,0,0]],[[-14,0,0],[-14,0,-7]],[[-8,0,0],[-8,0,7]],[[2,0,0],[2,0,-7]],[[13,0,0],[13,0,7]],[[18,0,0],[18,0,-7]]]
		3: return [[[-21,0,0],[15,0,0],[15,0,10],[-3,0,10],[-3,0,0]],[[-14,0,0],[-14,0,-8]],[[-21,0,0],[0,0,0]],[[0,0,0],[15,0,0]],[[15,0,0],[15,0,10]],[[15,0,10],[-3,0,10]]]
		4: return [[[-21,0,1],[15,0,1],[15,0,-8],[-14,0,-8],[-14,0,1]],[[15,0,1],[22,0,1]],[[-14,0,1],[-14,0,-8]],[[0,0,1],[0,0,5]],[[0,0,1],[0,0,-8]],[[15,0,1],[15,0,-8]]]
		5: return [[[-20,0,0],[22,0,0]],[[-11,0,0],[-11,0,-8]],[[1,0,0],[1,0,6]],[[13,0,0],[13,0,-9]],[[-11,0,0],[-15,0,0]],[[13,0,0],[17,0,0]]]
		6: return [[[-20,0,0],[19,0,0],[19,0,10],[9,0,10],[9,0,0]],[[-7,0,0],[-7,0,-10]],[[19,0,0],[19,0,-9]],[[19,0,10],[23,0,10]],[[9,0,0],[9,0,10]],[[-20,0,0],[-17,0,0]],[[-7,0,0],[-7,0,5]]]
		7: return [[[-21,0,0],[23,0,0]],[[0,0,0],[0,0,-11]],[[-8,0,0],[-8,0,-11],[8,0,-11],[8,0,0]],[[0,0,0],[0,0,10]],[[-13,0,0],[-16,0,0]],[[12,0,0],[15,0,0]]]
	return []

static func _rects(chapter: int) -> Array[Rect2]:
	match chapter:
		2: return [Rect2(-24,-3,49,6),Rect2(-18,-12,8,12),Rect2(-12,0,8,11),Rect2(-2,-12,8,12),Rect2(9,0,8,11),Rect2(14,-12,8,12)]
		3: return [Rect2(-24,-3,48,6),Rect2(-18,-13,8,13),Rect2(-7,0,8,14),Rect2(-7,7,30,7),Rect2(12,0,11,14)]
		4: return [Rect2(-24,-2,49,6),Rect2(-18,-13,8,17),Rect2(-18,-11,37,6),Rect2(11,-13,9,17),Rect2(-6,-8,13,17)]
		5: return [Rect2(-23,-3,48,6),Rect2(-16,-13,10,13),Rect2(-4,-3,10,13),Rect2(8,-14,10,14)]
		6: return [Rect2(-24,-3,48,7),Rect2(-13,-15,12,23),Rect2(15,-14,9,27),Rect2(5,0,8,14),Rect2(5,7,21,7)]
		7: return [Rect2(-24,-3,51,6),Rect2(-7,-7,14,15),Rect2(-12,-15,7,15),Rect2(5,-15,7,15),Rect2(-12,-15,24,7),Rect2(-4,-15,8,29)]
	return []

static func _grid(chapter: int) -> Dictionary:
	var cells: Dictionary={}
	for rect in _rects(chapter):
		for x in range(int(rect.position.x),int(rect.end.x)):
			for z in range(int(rect.position.y),int(rect.end.y)): cells[Vector2i(x,z)]=true
	return cells

static func _boundary_edges(chapter: int) -> Array:
	var cells:=_grid(chapter); var lines: Dictionary={}
	for cell: Vector2i in cells:
		for side in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if cells.has(cell+side): continue
			var vertical: bool=side.x!=0
			var at: int=cell.x+(1 if side.x==1 else 0) if vertical else cell.y+(1 if side.y==1 else 0)
			var line_key:=Vector3i(1 if vertical else 0,at,side.x if vertical else side.y)
			if not lines.has(line_key): lines[line_key]=[]
			lines[line_key].append(cell.y if vertical else cell.x)
	var edges: Array=[]
	for key: Vector3i in lines:
		var starts: Array=lines[key]; starts.sort()
		var first: int=starts[0]; var last:=first
		for index in range(1,starts.size()+1):
			if index<starts.size() and starts[index]==last+1: last=starts[index]; continue
			edges.append({"vertical":key.x==1,"at":key.y,"from":first,"to":last+1,"side":key.z})
			if index<starts.size(): first=starts[index]; last=first
	return edges

static func boundary_samples(chapter: int) -> Array:
	var result: Array=[]
	for edge in _boundary_edges(chapter):
		var center:=Vector3(edge.at,0,(edge.from+edge.to)*.5) if edge.vertical else Vector3((edge.from+edge.to)*.5,0,edge.at)
		var normal:=Vector3(edge.side,0,0) if edge.vertical else Vector3(0,0,edge.side)
		result.append([center-normal*.65,center+normal*.75])
	return result

static func build(chapter: int) -> Node3D:
	var world:=new(); world.name="SagaWorld_%d" % chapter
	world._chapter=chapter
	if not TITLES.has(chapter): return world
	world._construct()
	return world

func _construct() -> void:
	_cells=_grid(_chapter)
	_physics=Node3D.new(); _physics.name="PermanentCollision"; add_child(_physics)
	_art=Node3D.new(); _art.name=LANDMARKS[_chapter]; add_child(_art)
	_materials_init(); _original_natural_assets(); _environment(); _ground(); _boundary()
	match _chapter:
		2: _street()
		3: _wharf()
		4: _mirrors()
		5: _clinic()
		6: _refuge()
		7: _core()
	_landscape()
	set_meta("chapter",_chapter); set_meta("title",TITLES[_chapter]); set_meta("layout","saga_regions_v1")

func _materials_init() -> void:
	for key in TEXTURES:
		var mat:=StandardMaterial3D.new(); mat.albedo_texture=TEXTURES[key]; mat.roughness=.86
		mat.uv1_triplanar=true; mat.uv1_scale=Vector3(.6,.6,.6); mat.vertex_color_use_as_albedo=true
		_materials[key]=mat
	_materials.roof.albedo_color=Color("737b89"); _materials.wood.albedo_color=Color("a48b7d")
	_materials.stone.albedo_color=Color("78838b") if _chapter!=7 else Color("abb1b9")
	_materials.plaster.albedo_color=Color("b4b7b4")
	_materials.paper.emission_enabled=true; _materials.paper.emission=Color("e6bd7f"); _materials.paper.emission_energy_multiplier=.08
	_solid("earth",Color("343c3a")); _solid("bronze",Color("96774b"),.45); _solid("iron",Color("353f49"),.4)
	_solid("moss",Color("415848")); _solid("indigo",Color("344d70")); _solid("red",Color("79504e"))
	_solid("blanket",Color("637774")); _solid("mirror",Color("9ac4ca"),.18)
	_solid("glow",Color("ffd392"),.6,true); _solid("cold_glow",Color("92e0ed"),.5,true)
	_solid("ink",Color("25272c")); _solid("bark",Color("514a42")); _solid("leaf",Color("425a50"))

func _original_natural_assets() -> void:
	# 原山路网格拆成真实独石并保留UV/法线；不挤压整组岩石，也不以圆柱代替岩石。
	var source:=APPROACH.instantiate() as Node3D
	_source_stones=STONES.extract(source.find_child("51_Layered_Rocks_Front",true,false))
	var earth: MeshInstance3D=source.find_child("01_Terrain_Watertight_Sculpted_Earth",true,false)
	var mat:=earth.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	mat.uv1_triplanar=true; mat.uv1_world_triplanar=true; mat.uv1_scale=Vector3(.35,.35,.35)
	mat.albedo_color=Color(.53,.57,.50); mat.roughness=.98; _materials.earth=mat
	for variant in range(1,6):
		var selected: Array[Dictionary]=[]; var extents:=AABB(); var initial:=true
		for prefix in ["60_Cedar_%d_Trunk"%variant,"61_Cedar_%d_Foliage"%variant]:
			for part in source.find_children(prefix+"*","MeshInstance3D",true,false):
				var transform_value:=Transform3D.IDENTITY; var cursor: Node=part
				while cursor!=source and cursor!=null:
					if cursor is Node3D: transform_value=cursor.transform*transform_value
					cursor=cursor.get_parent()
				var aabb: AABB=transform_value*part.get_aabb()
				extents=aabb if initial else extents.merge(aabb); initial=false
				selected.append({"mesh":part.mesh,"transform":transform_value})
		var origin:=Vector3(extents.get_center().x,extents.position.y,extents.get_center().z)
		for part in selected: part.transform.origin-=origin
		if not selected.is_empty(): _source_trees.append({"pieces":selected,"height":maxf(.1,extents.size.y)})
	source.free()
	var mirror:=MIRROR_SOURCE.instantiate() as Node3D
	var roof: MeshInstance3D=mirror.find_child("Curved_original_roof",true,false)
	if roof!=null:
		var aabb:=roof.mesh.get_aabb()
		_source_roof={"mesh":roof.mesh,"bounds":aabb}
	mirror.free()

func _source_outcrop(at: Vector3,index: int,width: float) -> void:
	var source: Dictionary=_source_stones[posmod(index,_source_stones.size())]
	var extents: AABB=source.mesh.get_aabb()
	var node:=MeshInstance3D.new(); node.name="GroundedSourceOutcrop"; node.mesh=source.mesh
	node.position=at-Vector3(0,.1,0); node.rotation.y=index*.42
	node.scale=Vector3.ONE*(width/maxf(extents.size.x,extents.size.z)); _art.add_child(node)

func _sculpted_earth(extents: Dictionary) -> void:
	var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES); surface.set_material(_materials.earth)
	for x in range(int(extents.x[0])-9,int(extents.x[1])+9,2):
		for z in range(int(extents.z[0])-9,int(extents.z[1])+9,2):
			var corners: Array[Vector3]=[]
			for p in [Vector2(x,z),Vector2(x+2,z),Vector2(x+2,z+2),Vector2(x,z+2)]:
				var near_walk:=INF
				for rect in _rects(_chapter):
					var closest:=Vector2(clampf(p.x,rect.position.x,rect.end.x),clampf(p.y,rect.position.y,rect.end.y))
					near_walk=minf(near_walk,closest.distance_to(p))
				var height: float=-.22+minf(2.3,near_walk*.12)*(sin(p.x*.28+p.y*.15)*.25+.65)
				if _chapter==3 or _chapter==6 and p.y>14: height=-1.05
				if _chapter==2 and p.x>=16 and p.x<=22 and p.y>=3 and p.y<=13: height=-.85
				corners.append(Vector3(p.x,height,p.y))
			for i in [0,1,2,0,2,3]:
				surface.set_uv(Vector2(corners[i].x,corners[i].z)*.35); surface.add_vertex(corners[i])
	surface.generate_normals()
	var terrain:=MeshInstance3D.new(); terrain.name="SculptedRegionEarth"; terrain.mesh=surface.commit(); _art.add_child(terrain)

func _solid(key: String,color: Color,roughness: float=.9,emissive: bool=false) -> void:
	var mat:=StandardMaterial3D.new(); mat.albedo_color=color; mat.roughness=roughness
	if emissive: mat.emission_enabled=true; mat.emission=color; mat.emission_energy_multiplier=.6
	_materials[key]=mat

func _environment() -> void:
	var palette: Array={2:["182333","93a4bd","ffd1a0"],3:["142a35","8faec0","efd5a7"],4:["252336","a4a0c5","abdfed"],5:["1e2b2c","a9b8b4","ffe2b5"],6:["18222f","879aaf","f9c491"],7:["3a3846","c0b7c8","ffe2ae"]}[_chapter]
	var node:=WorldEnvironment.new(); node.name="RegionEnvironment"
	var env:=Environment.new(); env.background_mode=Environment.BG_COLOR; env.background_color=Color(palette[0])
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color=Color(palette[1]); env.ambient_light_energy=.5 if _chapter==7 else .42
	env.fog_enabled=true; env.fog_light_color=Color(palette[0]); env.fog_density=.004
	node.environment=env; add_child(node)
	var moon:=DirectionalLight3D.new(); moon.name="RegionMoonKey"; moon.rotation_degrees=Vector3(-48,-28,0)
	moon.light_color=Color(palette[1]); moon.light_energy=.62 if _chapter==7 else .5
	moon.shadow_enabled=true; moon.directional_shadow_max_distance=42; moon.shadow_bias=.04; moon.shadow_normal_bias=.65; moon.shadow_reverse_cull_face=true; add_child(moon)
	var fill:=DirectionalLight3D.new(); fill.name="SkyFill"; fill.rotation_degrees=Vector3(-52,140,0); fill.light_color=Color(palette[2]); fill.light_energy=.20; add_child(fill)

func _ground() -> void:
	# 合并地格只用于地板可见面；物理按少量原矩形铺设，绝不每块砖生成刚体。
	for rect in _rects(_chapter):
		_collision("WalkableFloor",Vector3(rect.get_center().x,-.15,rect.get_center().y),Vector3(rect.size.x,.3,rect.size.y))
		_box("LoadBearingFoundation",Vector3(rect.get_center().x,-.56,rect.get_center().y),Vector3(rect.size.x,.92,rect.size.y),"wood" if _chapter==3 else "stone")
	var mesh:=BoxMesh.new(); mesh.size=Vector3(.97,.13,.97); mesh.material=_materials.wood if _chapter==3 else _materials.stone
	var multi:=MultiMesh.new(); multi.transform_format=MultiMesh.TRANSFORM_3D; multi.use_colors=true; multi.mesh=mesh; multi.instance_count=_cells.size()
	var index:=0
	for cell: Vector2i in _cells:
		multi.set_instance_transform(index,Transform3D(Basis.IDENTITY,Vector3(cell.x+.5,-.065,cell.y+.5)))
		var tint:=.91+float(posmod(cell.x*13+cell.y*17,10))*.015
		multi.set_instance_color(index,Color(tint,tint,tint)); index+=1
	var floor_node:=MultiMeshInstance3D.new(); floor_node.name="ContinuousLaidPaving"; floor_node.multimesh=multi; _art.add_child(floor_node)
	var extents:=bounds(_chapter)
	_sculpted_earth(extents)

func _boundary() -> void:
	for edge in _boundary_edges(_chapter):
		var length: float=edge.to-edge.from
		var at:=Vector3(edge.at,.95,(edge.from+edge.to)*.5) if edge.vertical else Vector3((edge.from+edge.to)*.5,.95,edge.at)
		var size:=Vector3(.20,2.3,length+.12) if edge.vertical else Vector3(length+.12,2.3,.20)
		_collision("BoundedWalkEdge",at,size)
		var rail_size:=Vector3(.19,.13,length) if edge.vertical else Vector3(length,.13,.19)
		_box("EdgeCoping",Vector3(at.x,.1,at.z),rail_size,"stone")
		# 水岸有真实木栏；庭街用低台缘，物理上仍防止从高地跌落。
		if _chapter==3 or (_chapter==7 and length>4):
			_box("WaterfrontRail",Vector3(at.x,.74,at.z),rail_size,"wood" if _chapter==3 else "bronze")
			for step in range(int(length/2.2)+1):
				var t:=minf(length,float(step)*2.2)
				var p:=Vector3(edge.at,.43,edge.from+t) if edge.vertical else Vector3(edge.from+t,.43,edge.at)
				_box("RailPost",p,Vector3(.15,.86,.15),"wood" if _chapter==3 else "bronze")

func _street() -> void:
	_building("客栈",Vector3(-14,0,-7),7,4,"plaster")
	_building("灯铺",Vector3(2,0,-7),7,4,"wood")
	_building("染坊",Vector3(18,0,-7),7,4,"plaster")
	_building("布庄",Vector3(-6,0,-3.55),6,4,"wood")
	_building("杂货",Vector3(10,0,-3.55),6,4,"plaster")
	for x in [-8,-6,-4,8,10,12]: _cloth(Vector3(x,2.1,-3.5),Color("7e6158") if x<0 else Color("697872"),.75,.7)
	_gateway(Vector3(-22,0,0),"无眠街")
	for x in [-19,-5,9,22]: _lantern(Vector3(x,0,-2.35),true)
	for x in [-17,-11]: _lantern(Vector3(x,0,-6),true)
	for x in [0,2,4]:
		_lantern(Vector3(x,0,-9),false)
		_box("LampShopCounter",Vector3(x,.48,-9.1),Vector3(1.6,.96,.7),"wood",true)
	for x in [15,17,19,21]:
		_cloth(Vector3(x,2.25,-9),Color("596681") if x%4==1 else Color("854b55"),1.35,1.75)
		_cylinder("DyeVat",Vector3(x,.4,-10.5),.43,.8,"wood",true)
	for x in [-10,-6]:
		_box("DryingRackPost",Vector3(x,1.25,8.5),Vector3(.13,2.5,.13),"wood")
	_box("DryingRackCrossbar",Vector3(-8,2.45,8.5),Vector3(4.1,.12,.12),"wood")
	_cloth(Vector3(-8,2.2,8.5),Color("aba497"),2.7,1.2)
	_stall(Vector3(11,0,8.8),"茶",false)
	_water(Vector3(18,-.38,7),Vector2(5,7),false)
	_box("CanalStoneLip",Vector3(16.7,.2,7),Vector3(.4,.4,7),"stone",true)
	for z in [5.6,6.3,7,7.7,8.4]: _box("DrainGrating",Vector3(15.9,.025,z),Vector3(1.1,.05,.11),"iron")
	for p in [Vector3(-18,0,1.7),Vector3(-5,0,-1.9),Vector3(23,0,1.8)]: _crates(p,2)

func _wharf() -> void:
	_building("西仓",Vector3(-14,0,-8),7,4,"wood")
	_gateway(Vector3(-22,0,0),"逆水渡")
	_water(Vector3(5,-.42,5),Vector2(13,5),true)
	_water(Vector3(1,-.45,19),Vector2(61,9),true)
	_water(Vector3(29,-.45,0),Vector2(10,30),true)
	for x in [-20,-10,1,10,20]: _lantern(Vector3(x,0,-2.25),true)
	for x in [-5,6,17]: _lantern(Vector3(x,0,12.7),true)
	for p in [Vector3(-17,0,-10),Vector3(-12,0,-10),Vector3(-16,0,-4),Vector3(19,0,2),Vector3(-5,0,12)]: _crates(p,3)
	_boat(Vector3(4,-.3,5),1.1); _boat(Vector3(18,-.3,16.8),1.35)
	for x in [-4,0,4]:
		_box("MooringBollard",Vector3(x,.35,2.4),Vector3(.32,.7,.32),"wood",true)
		_torus("MooringRope",Vector3(x,.64,2.4),.22,"bronze",Vector3(0,0,0))
	_box("BridgeCrossbeam",Vector3(15,-.35,5),Vector3(10,.25,.25),"wood")
	_mirror(Vector3(18,0,11),1.0)
	_sign(Vector3(17,1.2,11.8),"旧堤",.018)
	_stall(Vector3(-21,0,-1.8),"渡",true)

func _mirrors() -> void:
	_building("抛光间",Vector3(-14,0,-8),7,4,"plaster")
	_building("修阵室",Vector3(15,0,-8),8,4,"plaster")
	_building("留声室",Vector3(20,0,1),7,3,"wood")
	_gateway(Vector3(-22,0,1),"镜坊")
	_stall(Vector3(-17.1,0,-.8),"镜",true)
	for x in [-10,-6,-2,2,6,10]:
		_mirror(Vector3(x,0,-10.2),.8)
		_box("GalleryBeam",Vector3(x,2.7,-10.9),Vector3(4,.18,.2),"wood")
	for x in [-17,-11]:
		_cylinder("PolishingWheel",Vector3(x,.75,-9.7),.72,.16,"stone",true)
		_box("WheelWorktable",Vector3(x,.37,-9.7),Vector3(1.5,.7,1.15),"wood",true)
	for x in [12.4,17.7]: _shelf(Vector3(x,0,-10.5),true)
	for p in [Vector3(-4,0,6),Vector3(5,0,6)]: _planter(p,1.0)
	_mirror(Vector3(0,0,6.5),1.1)
	for p in [Vector3(-19,0,-1),Vector3(-8,0,2.2),Vector3(8,0,2.2),Vector3(21,0,2.2)]: _lantern(p,true,true)
	_cylinder("EchoResonanceBasin",Vector3(17, .6,-.4),.6,1.2,"bronze",true)

func _clinic() -> void:
	_gateway(Vector3(-21,0,0),"医馆")
	_building("医馆",Vector3(-20,0,0),5,3,"plaster")
	_building("病房",Vector3(-11,0,-8),9,4,"plaster")
	_building("药库",Vector3(20,0,0),7,3,"wood")
	_building("静室",Vector3(13,0,-9),8,4,"stone")
	_stall(Vector3(-14.1,0,-1.8),"药",true)
	for x in [-14,-8]:
		_bed(Vector3(x,0,-9.5)); _bed(Vector3(x,0,-5.5))
		_cloth(Vector3(x,2.3,-11.2),Color("a6b0ab"),2.0,1.25)
	for x in [10,16]: _shelf(Vector3(x,0,-1.4),false); _shelf(Vector3(x,0,-11.2),true)
	for p in [Vector3(-2,0,5.6),Vector3(4,0,5.6),Vector3(-2.5,0,-2.4),Vector3(4.5,0,-2.4)]: _lantern(p,true)
	_planter(Vector3(4.6,0,7.7),1.1)
	for x in [-1,1,3]: _cloth(Vector3(x,2.6,7),Color("b9baad"),.4,.65)
	_box("CourtyardLampLintel",Vector3(1,2.7,7),Vector3(5,.18,.18),"wood")
	for x in [-1.5,3.5]: _box("CourtyardLampPost",Vector3(x,1.35,7),Vector3(.18,2.7,.18),"wood")
	_mirror(Vector3(15.5,0,-11),.85)
	_box("ClinicRestBench",Vector3(-21.4,.35,1.7),Vector3(2.1,.7,.6),"wood",true)
	for z in [-7,-5]: _box("LowerChamberRetainingWall",Vector3(9,.8,z),Vector3(.4,1.6,1.4),"stone",true)

func _refuge() -> void:
	_gateway(Vector3(-21,0,0),"山门")
	_building("本殿",Vector3(-7,0,-10),10,4,"wood")
	_building("更楼",Vector3(19,0,-9),8,4,"plaster")
	_stall(Vector3(11,0,-1.8),"灯节点",true)
	for x in [-11,-3]: _lantern(Vector3(x,0,-4),true); _lantern(Vector3(x,0,5.7),true)
	_mirror(Vector3(-10.5,0,-12.2),.9)
	for p in [Vector3(-11,0,3.5),Vector3(-3,0,3.5),Vector3(21,0,-3.6)]:
		_bed(p)
		_crates(p+Vector3(0,0,2),2)
	_box("EvacuationBellFrame",Vector3(21.8,2.8,-10.6),Vector3(.2,5.6,.2),"wood")
	_cylinder("NightWatchBell",Vector3(21.8,3.5,-10.6),.62,1.0,"bronze")
	_water(Vector3(17,-.55,18),Vector2(30,9),true)
	_boat(Vector3(19,-.32,16.6),1.3)
	for x in [8,14,23]: _lantern(Vector3(x,0,12.6),true)
	for x in [7,8,9,10,11]: _box("DrainIronGrate",Vector3(x,.06,12.0),Vector3(.12,.12,2.0),"iron")
	_box("DrainStoneArchTop",Vector3(9,1.9,12.9),Vector3(4.5,.5,.7),"stone")
	for x in [7,11]: _box("DrainStonePier",Vector3(x,.95,12.9),Vector3(.55,1.9,.7),"stone",true)
	for p in [Vector3(6.2,0,4.5),Vector3(11.5,0,4.5),Vector3(17,0,-6)]: _crates(p,2)

func _core() -> void:
	_gateway(Vector3(-22,0,0),"主镜阵")
	# 中心镜厅是一整块承重石台；光环只作表面镶嵌，不拿发光平面冒充地形。
	_cylinder("MirrorHallInlaidFoundation",Vector3(0,-.06,0),5.6,.09,"bronze")
	_cylinder("MirrorHallStoneCenter",Vector3(0,-.005,0),5.1,.018,"stone")
	for radius in [2.7,4.7]: _torus("InlaidArrayRing",Vector3(0,.018,0),radius,"bronze",Vector3.ZERO)
	for x in [-8,8]:
		_mirror(Vector3(x,0,-13.2),1.25)
		_lantern(Vector3(x+2,0,-12.8),true,true)
	_mirror(Vector3(2,0,11.3),1.15)
	_mirror(Vector3(0,0,-13.1),1.65)
	for x in [-3.3,3.3]: _box("FinalDaisPillar",Vector3(x,1.7,-13.9),Vector3(.55,3.4,.55),"stone",true)
	_box("FinalDaisLintel",Vector3(0,3.4,-13.9),Vector3(7.2,.5,.8),"stone")
	for x in [-10,-6,-2,2,6,10]:
		_box("ArrayConnectionInlay",Vector3(x,.022,-11),Vector3(1.5,.018,.07),"cold_glow")
	for x in [-18,-15,-12]: _box("RestStoneBench",Vector3(x,.35,2),Vector3(2,.7,.6),"stone",true)
	for x in [11,13,15]:
		_box("NamesTablet",Vector3(x,1.0,-2.2),Vector3(1.4,2,.2),"stone",true)
		_sign(Vector3(x,1.2,-2.075),"记名\n归途",.012)
	for p in [Vector3(-5.8,0,-4.8),Vector3(5.8,0,-4.8),Vector3(-5.8,0,5.5),Vector3(5.8,0,5.5)]: _lantern(p,true,true)
	for x in [18,21,24]: _lantern(Vector3(x,0,-2.2),true)
	var dawn:=OmniLight3D.new(); dawn.name="DawnRouteLight"; dawn.position=Vector3(25,4,0); dawn.light_color=Color("ffe2af"); dawn.light_energy=2.1; dawn.omni_range=15; _art.add_child(dawn)
	_box("DawnThreshold",Vector3(25,.02,0),Vector3(.4,.03,4.5),"glow")

func _building(title: String,at: Vector3,width: float,depth: float,wall: String) -> void:
	var group:=Node3D.new(); group.name="Building_"+title; group.position=at; _art.add_child(group)
	# 前半敞开使斜侧相机看得到交互人物；实体后墙与侧柱阻挡，门前保持两米净空。
	_box("BackWall",Vector3(0,1.3,-depth+.12),Vector3(width,2.6,.24),wall,true,group)
	for x in [-width*.5,width*.5]:
		_box("SideWall",Vector3(x,1.05,-depth*.66),Vector3(.22,2.1,depth*.65),wall,true,group)
		_box("FrontPost",Vector3(x,1.35,-.35),Vector3(.24,2.7,.24),"wood",true,group)
		_box("RoofBrace",Vector3(x,2.45,-depth*.5),Vector3(.16,.22,depth),"wood",false,group)
	_box("FrontLintel",Vector3(0,2.65,-.35),Vector3(width+.4,.25,.3),"wood",false,group)
	for x in range(-int(width*.5)+1,int(width*.5),2):
		_box("PaperWindow",Vector3(x,1.4,-depth+.26),Vector3(1.3,1.05,.04),"paper",false,group)
		for offset in [-.45,0,.45]: _box("WindowMullion",Vector3(x+offset,1.4,-depth+.3),Vector3(.035,1.05,.04),"wood",false,group)
	# 原镜殿资源是敞顶后檐带，必须配完整双坡承重屋面；不将窄檐带拉伸冒充整屋顶。
	for side in [-1,1]:
		var slope:=_box("CompletePitchedRoof_%d" % side,Vector3(side*width*.25,2.97,-depth*.56),Vector3(width*.58,.17,depth+1.0),"roof",false,group)
		slope.rotation.z=-side*.19
	_box("RoofRidge",Vector3(0,3.33,-depth*.56),Vector3(.18,.17,depth+1.15),"roof",false,group)
	for course in range(int((depth+1.0)/.42)):
		var z: float=-depth-.35+course*.42
		for side in [-1,1]:
			var lip:=_box("OverlappingTileCourse",Vector3(side*width*.25,3.065,z),Vector3(width*.57,.045,.055),"roof",false,group)
			lip.rotation.z=-side*.19
	if not _source_roof.is_empty():
		var roof: MeshInstance3D=MeshInstance3D.new(); roof.name="ReusedCurvedKawaraEave"; roof.mesh=_source_roof.mesh
		var aabb: AABB=_source_roof.bounds
		var scale_value:=minf((width+1.0)/aabb.size.x,(depth+1.0)/aabb.size.z)
		roof.scale=Vector3.ONE*scale_value
		roof.position=Vector3(0,2.72,-.45)-Vector3(aabb.get_center().x,aabb.position.y,aabb.get_center().z)*scale_value
		group.add_child(roof)
	_box("ShopNameBoard",Vector3(0,2.4,-.15),Vector3(minf(width-1,2.6),.5,.1),"wood",false,group)
	_sign(Vector3(0,2.4,-.08),title,.017,group)
	_lantern(at+Vector3(width*.5-.55,0,-.7),true)

func _gateway(at: Vector3,title: String) -> void:
	# 入口牌楼后置于北侧，横向轮廓和小匾不覆盖固定斜侧镜头中的人物与交互提示。
	var group:=Node3D.new(); group.name="RegionGateway"; group.position=Vector3(at.x,at.y,-2.65); _art.add_child(group)
	for x in [-1.05,1.05]:
		_box("GateTimberPillar",Vector3(x,1.18,0),Vector3(.24,2.36,.24),"wood",true,group)
		_box("GateStoneFoot",Vector3(x,.12,0),Vector3(.44,.24,.44),"stone",false,group)
	_box("GatewayCrossbeam",Vector3(0,2.3,0),Vector3(2.8,.22,.3),"wood",false,group)
	_box("GatewayRoof",Vector3(0,2.6,0),Vector3(3.3,.17,.88),"roof",false,group)
	for x in [-1.65,1.65]:
		var tip:=_box("RaisedGateRoofTip",Vector3(x,2.65,0),Vector3(.4,.12,.94),"roof",false,group)
		tip.rotation.z=.22 if x>0 else -.22
	_box("GatewayHangingBoard",Vector3(0,2.12,.19),Vector3(1.6,.43,.09),"wood",false,group)
	_sign(Vector3(0,2.12,.245),title,.0085,group)

func _lantern(at: Vector3,light: bool,cold: bool=false) -> void:
	_box("LanternFoot",at+Vector3(0,.12,0),Vector3(.4,.24,.4),"stone")
	_box("LanternStem",at+Vector3(0,.85,0),Vector3(.13,1.45,.13),"wood")
	_box("LanternPaper",at+Vector3(0,1.63,0),Vector3(.42,.55,.42),"cold_glow" if cold else "glow")
	for y in [1.34,1.92]: _box("LanternFrame",at+Vector3(0,y,0),Vector3(.5,.09,.5),"wood")
	if light:
		var node:=OmniLight3D.new(); node.name="LanternPool"; node.position=at+Vector3(0,1.6,0)
		node.light_color=Color("a2dcea") if cold else Color("ffcf92"); node.light_energy=.75; node.omni_range=4.6
		_art.add_child(node)

func _stall(at: Vector3,title: String,small: bool) -> void:
	var width:=2.3 if small else 3.2
	_box("MarketCounter",at+Vector3(0,.45,0),Vector3(width,.9,.7),"wood",true)
	for x in [-width*.5,width*.5]: _box("StallPost",at+Vector3(x,1.25,0),Vector3(.1,2.5,.1),"wood")
	_box("StallCanopy",at+Vector3(0,2.5,0),Vector3(width+.4,.12,1.65),"indigo")
	_sign(at+Vector3(0,1.75,.1),title,.023)
	for x in [-.6,0,.6]: _cylinder("GoodsJar",at+Vector3(x,1.06,0),.13,.32,"paper")

func _crates(at: Vector3,count: int) -> void:
	for index in count:
		var p:=at+Vector3((index%2)*.68,(index/2)*.55,0)
		_box("CargoCrate",p+Vector3(0,.27,0),Vector3(.6,.54,.6),"wood",true)
		for x in [-.21,.21]: _box("CrateIronBand",p+Vector3(x,.27,.31),Vector3(.05,.54,.04),"iron")

func _bed(at: Vector3) -> void:
	_box("WardBedFrame",at+Vector3(0,.31,0),Vector3(1.0,.4,1.75),"wood",true)
	_box("WardBedding",at+Vector3(0,.57,0),Vector3(.9,.13,1.65),"paper")
	_box("WardBlanket",at+Vector3(0,.68,.25),Vector3(.88,.08,1.04),"blanket")
	_box("WardPillow",at+Vector3(0,.69,-.58),Vector3(.61,.15,.32),"paper")

func _shelf(at: Vector3,scrolls: bool) -> void:
	for x in [-.7,.7]: _box("ShelfUpright",at+Vector3(x,1.05,0),Vector3(.1,2.1,.48),"wood",true)
	for y in [.15,.8,1.45,2.05]:
		_box("ShelfBoard",at+Vector3(0,y,0),Vector3(1.5,.1,.55),"wood")
		if y>1.8: continue
		for x in [-.45,0,.45]:
			if scrolls: _box("ArchiveScroll",at+Vector3(x,y+.19,.04),Vector3(.23,.28,.33),"paper")
			else: _cylinder("MedicineJar",at+Vector3(x,y+.24,0),.14,.37,"paper")

func _mirror(at: Vector3,radius: float) -> void:
	_box("MirrorPedestal",at+Vector3(0,.18,0),Vector3(radius*1.2,.36,.8),"stone",true)
	_box("MirrorStand",at+Vector3(0,.78,0),Vector3(.18,1.3,.22),"bronze")
	var disk:=_cylinder("BronzeMirrorDisc",at+Vector3(0,1.4,0),radius,.11,"bronze"); disk.rotation.x=PI*.5
	var face:=_cylinder("SilverMirrorFace",at+Vector3(0,1.4,.075),radius*.9,.025,"mirror"); face.rotation.x=PI*.5
	_torus("MirrorChasedRim",at+Vector3(0,1.4,.12),radius*.95,"bronze",Vector3(PI*.5,0,0))

func _planter(at: Vector3,radius: float) -> void:
	_cylinder("MossPlanter",at+Vector3(0,.12,0),radius,.24,"stone",true)
	_cylinder("PlantedEarth",at+Vector3(0,.25,0),radius*.86,.03,"earth")
	_tree(at+Vector3(0,.26,0),1.15)

func _tree(at: Vector3,size: float) -> void:
	if _source_trees.is_empty(): return
	var source: Dictionary=_source_trees[posmod(int(at.x*3+at.z),_source_trees.size())]
	var group:=Node3D.new(); group.name="ReusedCedarTree"; group.position=at; group.rotation.y=at.x*.17
	group.scale=Vector3.ONE*(size*3.3/source.height); _art.add_child(group)
	for piece in source.pieces:
		var copy:=MeshInstance3D.new(); copy.name="OriginalCedarMesh"; copy.mesh=piece.mesh; copy.transform=piece.transform; group.add_child(copy)

func _cloth(at: Vector3,color: Color,width: float,height: float) -> void:
	var mat:=_materials.paper.duplicate() as StandardMaterial3D; mat.albedo_color=color; mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	var mesh:=PlaneMesh.new(); mesh.size=Vector2(width,height)
	var node:=MeshInstance3D.new(); node.name="HangingWovenCloth"; node.mesh=mesh; node.material_override=mat
	node.position=at-Vector3(0,height*.5,0); node.rotation.x=PI*.5; _art.add_child(node)

func _water(at: Vector3,size: Vector2,moving: bool) -> void:
	var shader:=Shader.new()
	shader.code="shader_type spatial; render_mode cull_disabled; uniform vec3 deep_color : source_color = vec3(0.06,0.19,0.24); void fragment(){ float rip=sin(UV.x*35.0+sin(UV.y*18.0)*1.7+TIME*0.45)*0.55+sin(UV.y*63.0+UV.x*12.0-TIME*0.3)*0.3; ALBEDO=deep_color+vec3(0.024,0.045,0.05)*smoothstep(0.70,0.88,rip); ROUGHNESS=0.50; METALLIC=0.10; }"
	var mat:=ShaderMaterial.new(); mat.shader=shader
	mat.set_shader_parameter("deep_color",Color("203e4c") if moving else Color("283b40"))
	var mesh:=PlaneMesh.new(); mesh.size=size
	var node:=MeshInstance3D.new(); node.name="ReverseCurrentWater" if moving else "CanalWater"; node.mesh=mesh; node.material_override=mat; node.position=at; _art.add_child(node)

func _boat(at: Vector3,size: float) -> void:
	var group:=Node3D.new(); group.name="MooredRiverBoat"; group.position=at; group.scale=Vector3.ONE*size; _art.add_child(group)
	_box("BoatKeel",Vector3(0,.12,0),Vector3(3.4,.25,1.0),"wood",false,group)
	for side in [-1,1]:
		var plank:=_box("RaisedHullSide",Vector3(0,.43,side*.57),Vector3(3.8,.45,.14),"wood",false,group)
		plank.rotation.x=side*.22
	for x in [-1.8,1.8]:
		var prow:=_box("AngledBoatProw",Vector3(x,.33,0),Vector3(.5,.35,1.05),"wood",false,group); prow.rotation.z=.35 if x>0 else -.35
	for x in [-1,0,1]: _box("BoatSeat",Vector3(x,.56,0),Vector3(.28,.1,1.05),"wood",false,group)

func _landscape() -> void:
	var extents:=bounds(_chapter)
	# 地图背面有实体承托、远墙和屋脊。前景不种高树，避免固定镜头遮住人物。
	_box("NorthRetainingWall",Vector3(0,.2,extents.z[0]-1.5),Vector3(63,2.1,.8),"stone")
	for index in 14:
		var x: float=-29+index*4.5
		if _chapter in [2,4,5,6]:
			var depth: float=extents.z[0]-5.0-(index%3)
			var height: float=3.1+float(index%4)*.32
			_box("DistantTownSilhouette",Vector3(x,height*.5-.25,depth),Vector3(3.8,height,3.4),"plaster")
			for side in [-1,1]:
				var roof:=_box("DistantPitchedRoof",Vector3(x+side,height-.16,depth),Vector3(2.35,.18,3.9),"roof")
				roof.rotation.z=-side*.22
			for sx in [-.85,.85]:
				_box("DistantWindowFrame",Vector3(x+sx,1.25,depth+1.72),Vector3(.8,1.1,.1),"wood")
				_box("DistantPaperWindow",Vector3(x+sx,1.25,depth+1.78),Vector3(.62,.92,.03),"paper")
			if index%3==0: _tree(Vector3(x+2.0,-.2,depth+1.7),1.2)
		else: _tree(Vector3(x,-.5,extents.z[0]-4.0),1.4+float(index%3)*.2)
	for x in [extents.x[0]-2,extents.x[1]+2]:
		for z in [-9,-1,8]:
			for n in range(3): _source_outcrop(Vector3(x+.45*n,-.20,z+.4*n),int(x+z)+n,1.2+.3*n)

func _box(title: String,at: Vector3,size: Vector3,material: String,solid: bool=false,parent: Node3D=null) -> MeshInstance3D:
	var mesh:=BoxMesh.new(); mesh.size=size
	var node:=MeshInstance3D.new(); node.name=title; node.mesh=mesh; node.material_override=_materials[material]; node.position=at
	(parent if parent!=null else _art).add_child(node)
	if solid:
		var world_at:=at+(parent.position if parent!=null else Vector3.ZERO)
		_collision(title+"Collision",world_at,size)
	return node

func _cylinder(title: String,at: Vector3,radius: float,height: float,material: String,solid: bool=false) -> MeshInstance3D:
	var mesh:=CylinderMesh.new(); mesh.top_radius=radius; mesh.bottom_radius=radius; mesh.height=height; mesh.radial_segments=16
	var node:=MeshInstance3D.new(); node.name=title; node.mesh=mesh; node.material_override=_materials[material]; node.position=at; _art.add_child(node)
	if solid: _collision(title+"Collision",at,Vector3(radius*2,height,radius*2))
	return node

func _torus(title: String,at: Vector3,radius: float,material: String,rotation_value: Vector3) -> void:
	var mesh:=TorusMesh.new(); mesh.inner_radius=maxf(.01,radius-.035); mesh.outer_radius=radius+.035; mesh.rings=24; mesh.ring_segments=6
	var node:=MeshInstance3D.new(); node.name=title; node.mesh=mesh; node.material_override=_materials[material]; node.position=at; node.rotation=rotation_value; _art.add_child(node)

func _collision(title: String,at: Vector3,size: Vector3) -> void:
	var body:=StaticBody3D.new(); body.name=title; body.position=at
	var collider:=CollisionShape3D.new(); var shape:=BoxShape3D.new(); shape.size=size; collider.shape=shape
	body.add_child(collider); _physics.add_child(body)

func _sign(at: Vector3,value: String,pixel: float,parent: Node3D=null) -> void:
	var node:=Label3D.new(); node.name="WorldSign"; node.text=value; node.font=FONT; node.font_size=38; node.pixel_size=pixel
	node.modulate=Color("eddfb8"); node.outline_modulate=Color("211f25"); node.outline_size=5; node.position=at
	(parent if parent!=null else _art).add_child(node)

func update_visibility(_position: Vector3,_delta: float=1.0/60.0,_camera: Camera3D=null) -> void:
	# 地区尺度限定在约50米，不按剧情或距离移除地面与NPC所在建筑。
	pass
