# 第四夜同源偏殿。只加载表现资产，灯光由共享集成层控制。
extends RefCounted

const MIRROR_HALL := preload("res://assets/3d/night04_mirror/night04_mirror.glb")

static func build(parent: Node3D, _config: Dictionary) -> void:
	var art := Node3D.new()
	art.name = "Night4Art"
	parent.add_child(art)
	var model := MIRROR_HALL.instantiate() as Node3D
	model.name = "SourceMirrorHall"
	art.add_child(model)
