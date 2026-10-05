# 氛围呈现契约；真实构建世界，不写存档。画面优劣仍须相同机位实景审查。
extends SceneTree
var failures: Array[String] = []
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		printerr("ASSERT FAIL: ",message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _run() -> void:
	var world: Node3D = load("res://scripts/campaign/act_one_geometry.gd").build({})
	root.add_child(world)
	await process_frame
	var moon: DirectionalLight3D = world.find_child("ActOneMoonKey",true,false)
	check(moon != null and moon.shadow_enabled, "月光启用真实投影，不能只靠黑色椭圆接触片")
	check(moon.directional_shadow_max_distance <= 45.0, "月光阴影只覆盖中景，限制兼容渲染成本")
	for name_value in ["WalkableEarthSurface","SculptedContinuousMountainGround","IrregularMossAndEarthBed"]:
		var surface: MeshInstance3D = world.find_child(name_value,true,false)
		var normals: PackedVector3Array = surface.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		var mean_normal := Vector3.ZERO
		for normal in normals: mean_normal += normal
		mean_normal /= float(normals.size())
		check(mean_normal.y>.90, "可见土石表面法线朝上，避免反面normal bias斜纹 "+name_value)
	for name_value in ["WalkableEarthSurface","SculptedContinuousMountainGround","Deck_aged_cedar_planks_nails"]:
		var receiver: GeometryInstance3D = world.find_child(name_value,true,false)
		check(receiver.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "大型接收面不重复自投影 "+name_value)
	var roof: MeshInstance3D = world.find_child("Curved_kawara_roof",true,false)
	check(roof.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "瓦檐仍参与实体投影")
	var offering = world.find_child("ForecourtAbandonedOffering",true,false)
	check(offering != null, "回廊入口存在有主次的荒废供养小景")
	if offering != null:
		check(offering.find_child("LightningSplitCedar",true,false) != null, "枯木有独立分叉轮廓")
		check(offering.find_child("HalfBuriedRoadsideMemorial",true,false) != null, "旧碑半藏于树根植床")
		check(offering.find_child("WitheredOfferingFlowers",true,false) != null, "垂败供花与碑形成关系")
		check(offering.find_child("RootHiddenOldBones",true,false) != null, "骨段藏在根石间而非铺满路面")
		check(offering.find_children("*","CollisionObject3D",true,false).is_empty(), "环境小景不增加通路碰撞")
		var triangles := 0
		for mesh in offering.find_children("*","MeshInstance3D",true,false):
			check(mesh.mesh is ArrayMesh, "新环境实物使用有轮廓的真实三角网格")
			triangles += mesh.mesh.get_faces().size()/3
		check(triangles < 6500, "前庭小景三角预算低于6500")
	var grove: Node3D = world.find_child("OuterCedarGrove",true,false)
	check(grove.find_children("QuietDeadCedar*","Node3D",true,false).size()>=2, "外林以少量枯枝打破机械重复树冠")
	var paving: MultiMeshInstance3D = world.find_child("WornStoneSlabPaving",true,false)
	check(paving.multimesh.use_colors, "铺面支持路缘有限色差而非等亮网格")
	check(world.find_child("SpentLampOffering",true,false)!=null, "北侧路灯有独立衰败供花而非复制全套旧碑")
	check(world.find_child("BoundaryStoneRemains",true,false)!=null, "南路界外有半掩旧石与细骨余片")
	world.free()
	print("ACT ONE ATMOSPHERE: ",assertions," assertions, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
