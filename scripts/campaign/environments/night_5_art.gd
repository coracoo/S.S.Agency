# 第五夜同源本殿。只加载表现资产，不改变玩法/相机/旧碰撞。
extends RefCounted

const HONDEN := preload("res://assets/3d/night05_honden/night05_honden.glb")

static func build(parent: Node3D, _config: Dictionary) -> void:
	var art := Node3D.new()
	art.name = "Night5Art"
	parent.add_child(art)
	var model := HONDEN.instantiate() as Node3D
	model.name = "SourceHonden"
	art.add_child(model)
