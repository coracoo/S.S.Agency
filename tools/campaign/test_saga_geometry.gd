# 后六章地图验收：逐锚点、真实物理连续通路、边界与章别地标，不写正式存档。
extends SceneTree
var failures: Array[String] = []
var assertions := 0
const REQUIRED := {
	2: ["gate", "inn", "square", "shop", "canal", "alley"],
	3: ["gate", "dock", "warehouse", "bay", "shrine", "exit"],
	4: ["gate", "shop", "workshop", "corridor", "archive", "echo"],
	5: ["gate", "shop", "ward", "yard", "store", "sanctum"],
	6: ["gate", "honden", "courtyard", "junction", "dock", "alley", "drain"],
	7: ["gate", "stairs", "hall", "mirror", "names", "exit"]
}
const LANDMARKS := {2: "SleeplessMarket", 3: "ReverseWaterWharf", 4: "TwinMirrorWorkshop", 5: "BorrowedLifeClinic", 6: "HundredNightRefuge", 7: "BeforeDawnCore"}
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); printerr("ASSERT FAIL: ", message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _run() -> void:
	var path := "res://scripts/campaign/saga_world.gd"
	check(ResourceLoader.exists(path), "后六章真实地图模块存在")
	if not ResourceLoader.exists(path): _finish(); return
	var factory: Script = load(path)
	check(factory.can_instantiate(),"地图脚本编译通过")
	if not factory.can_instantiate(): _finish(); return
	for chapter in range(2,8):
		var limits: Dictionary = factory.bounds(chapter)
		var points: Dictionary = factory.anchors(chapter)
		var world: Node3D = factory.build(chapter)
		root.add_child(world)
		check(world.get_meta("layout","")=="saga_regions_v1","第%d章世界标识与正式存档一致" % chapter)
		await physics_frame; await physics_frame
		var terrain: MeshInstance3D=world.find_child("SculptedRegionEarth",true,false)
		check(terrain!=null,"第%d章连续起伏环境地形" % chapter)
		if terrain!=null:
			var normals: PackedVector3Array=terrain.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
			check(normals[0].y>.8,"第%d章环境地面朝上可见" % chapter)
		check(world.find_child("GroundedSourceOutcrop",true,false)!=null,"第%d章环境使用原真实独石网格" % chapter)
		var gateway:=world.find_child("RegionGateway",true,false)
		check(gateway!=null,"第%d章入口牌楼后置分组" % chapter)
		if gateway!=null:
			check(gateway.position.z<=-2.4,"第%d章入口屋檐退出人物投影主带" % chapter)
			for sign_node in gateway.find_children("*","Label3D",true,false): check(sign_node.pixel_size<=.012,"入口招牌维持环境尺度")
		check(world.find_child(LANDMARKS[chapter],true,false) != null,"第%d章独立地标" % chapter)
		if chapter!=7:
			check(world.find_children("CompletePitchedRoof*","MeshInstance3D",true,false).size()>=2,"第%d章屋顶拥有完整承重面而非一条窄檐" % chapter)
		check(world.find_children("*","WorldEnvironment",true,false).size()==1,"第%d章独立环境" % chapter)
		check(world.find_children("*","MeshInstance3D",true,false).size()>=80,"第%d章建筑和场景细节" % chapter)
		check(world.find_children("*","StaticBody3D",true,false).size()<250,"第%d章物理体数量有界" % chapter)
		var space := world.get_world_3d().direct_space_state
		var capsule := CapsuleShape3D.new(); capsule.radius=.22; capsule.height=1.4
		var query := PhysicsShapeQueryParameters3D.new(); query.shape=capsule
		for key in REQUIRED[chapter]+["spawn","rest","shop","exit"]:
			check(points.has(key),"第%d章锚点%s存在" % [chapter,key])
			if not points.has(key): continue
			var p := Vector3(points[key][0],points[key][1],points[key][2])
			check(p.x>=limits.x[0] and p.x<=limits.x[1] and p.z>=limits.z[0] and p.z<=limits.z[1],"第%d章%s边界内" % [chapter,key])
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3(0,.4,0),p-Vector3(0,.5,0)))
			check(not hit.is_empty() and hit.normal.y>.9,"第%d章%s真实可站立地面" % [chapter,key])
			query.transform.origin=p+Vector3(0,.76,0); query.motion=Vector3.ZERO
			check(space.intersect_shape(query).is_empty(),"第%d章%s人物胶囊无遮挡" % [chapter,key])
		var battle: Array=points["battle"]
		for x in range(-4,5):
			for z in range(-2,3):
				var p:=Vector3(battle[0]+x,battle[1],battle[2]+z)
				query.transform.origin=p+Vector3(0,.76,0); query.motion=Vector3.ZERO
				check(space.intersect_shape(query).is_empty(),"第%d章8×4米战斗站位净空" % chapter)
				check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3(0,.4,0),p-Vector3(0,.5,0))).is_empty(),"第%d章战斗站位真实地面" % chapter)
		var routes: Array = factory.routes(chapter)
		check(routes.size()>=REQUIRED[chapter].size(),"第%d章所有区域有连续通路" % chapter)
		for key in REQUIRED[chapter]:
			var included:=false
			for route in routes:
				for p in route:
					if p==points[key]: included=true
			check(included,"第%d章%s已纳入真实通路验证" % [chapter,key])
		for route in routes:
			for index in range(route.size()-1):
				var a := Vector3(route[index][0],route[index][1],route[index][2])
				var b := Vector3(route[index+1][0],route[index+1][1],route[index+1][2])
				for direction in [1,-1]:
					query.transform.origin=(a if direction==1 else b)+Vector3(0,.76,0)
					query.motion=(b-a)*direction
					check(space.cast_motion(query)[0]>=.999,"第%d章双向通路%s→%s" % [chapter,a,b])
				for sample in range(int(ceil(a.distance_to(b)/.4))+1):
					var p := a.lerp(b,minf(1.0,float(sample)*.4/maxf(.01,a.distance_to(b))))
					var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3(0,.4,0),p-Vector3(0,.5,0)))
					check(not hit.is_empty() and hit.normal.y>.9,"第%d章路线地面 %.1f %.1f" % [chapter,p.x,p.z])
		# 每块可走地的外边界都必须阻住玩家；测试真实胶囊横扫，非只看节点名。
		for edge in factory.boundary_samples(chapter):
			var a: Vector3=edge[0]; var b: Vector3=edge[1]
			query.transform.origin=a+Vector3(0,.76,0); query.motion=b-a
			check(space.cast_motion(query)[0]<.99,"第%d章外沿不可跌落 %s" % [chapter,a])
		if OS.get_environment("SAGA_GEOMETRY_SKIP_WALK")!="1": await _walk_actual_capsule(world,routes[0],chapter)
		if not OS.get_environment("ACT_ONE_OUTPUT").is_empty(): await _capture(world,chapter,points)
		world.free()
	_finish()
func _walk_actual_capsule(world: Node3D, route: Array, chapter: int) -> void:
	var body:=CharacterBody3D.new(); body.floor_snap_length=.5; body.floor_max_angle=deg_to_rad(48)
	var shape:=CollisionShape3D.new(); var capsule:=CapsuleShape3D.new(); capsule.radius=.22; capsule.height=1.4
	shape.shape=capsule; shape.position.y=.7; body.add_child(shape); world.add_child(body)
	body.position=Vector3(route[0][0],route[0][1]+.04,route[0][2])
	for target in route.slice(1):
		var destination:=Vector3(target[0],target[1],target[2]); var reached:=false; var grounded:=0
		for frame in range(1800):
			await physics_frame
			var difference:=Vector2(destination.x-body.position.x,destination.z-body.position.z)
			if difference.length()<.1: reached=true; break
			var direction:=difference.normalized(); body.velocity.x=direction.x*2.6; body.velocity.z=direction.y*2.6
			if body.is_on_floor(): body.velocity.y=0; grounded+=1
			else: body.velocity.y-=18.0/60.0
			body.move_and_slide()
		check(reached and grounded>2 and body.position.y>-.1,"第%d章真实控制器胶囊实走 %s" % [chapter,destination])
	body.free()
func _capture(world: Node3D, chapter: int, points: Dictionary) -> void:
	var camera:=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=36; camera.far=180
	world.add_child(camera); camera.position=Vector3(0,40,43); camera.look_at(Vector3(0,0,-1)); camera.make_current()
	root.size=Vector2i(1600,1000)
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	var output:=OS.get_environment("ACT_ONE_OUTPUT")
	check(root.get_texture().get_image().save_png(output.path_join("saga_%d_overview.png" % chapter))==OK,"实景总览保存")
	var p: Array=points["spawn"]; var focus:=Vector3(p[0],p[1]+1,p[2])
	camera.size=8; camera.position=focus+Vector3(0,4.8,11); camera.look_at(focus)
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join("saga_%d_spawn.png" % chapter))==OK,"实景游玩机位保存")
	var file:=FileAccess.open(output.path_join("saga_%d_capture.json" % chapter),FileAccess.WRITE)
	file.store_string(JSON.stringify({"chapter":chapter,"renderer":RenderingServer.get_video_adapter_name(),"note":"实际Godot地区几何；总览仅拉远镜头，spawn为8米正交游玩机位；未缩放几何", "spawn_camera":{"position":[camera.position.x,camera.position.y,camera.position.z],"target":[focus.x,focus.y,focus.z],"orthographic_size":camera.size}},"\t"))
	file.close()
	camera.free()
func _finish() -> void:
	print("SAGA GEOMETRY: ",assertions," assertions, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
