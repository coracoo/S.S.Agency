# 标题仅美术背景，不隐式创建会话、玩家或碰撞。
extends SceneTree
var failures: Array[String] = []
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); printerr("ASSERT FAIL: ",message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _run() -> void:
	var path := "res://scripts/campaign/title_atmosphere.gd"
	check(ResourceLoader.exists(path), "标题具有独立轻量山林背景")
	if ResourceLoader.exists(path):
		var library = load(path)
		check(library._height(10.0,12.0)<library._height(10.0,4.0), "标题近景山坡向谷底下降，不越过镜头底部形成纯色裁边")
		var backdrop: Node3D = library.build(); root.add_child(backdrop)
		check(backdrop.find_children("*","CollisionObject3D",true,false).is_empty(), "标题背景无物理体")
		check(backdrop.find_child("TitleMountainGround",true,false) != null, "标题有真实连续山地填满摄影边缘")
		check(backdrop.find_child("OriginalApproach",true,false) != null, "标题保留原山门参道资产")
		check(backdrop.find_children("*","WorldEnvironment",true,false).size()==1, "标题只有一个雾光环境")
		check(backdrop.find_children("*","MeshInstance3D",true,false).size()<110, "标题背景不实例化全寺域")
		var ground: MeshInstance3D = backdrop.find_child("TitleMountainGround",true,false)
		var normals: PackedVector3Array = ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		var mean := Vector3.ZERO
		for normal in normals: mean += normal
		check(mean.y/float(normals.size())>.9, "标题山地法线朝上")
		backdrop.free()
	print("TITLE ATMOSPHERE: ",assertions," assertions, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
