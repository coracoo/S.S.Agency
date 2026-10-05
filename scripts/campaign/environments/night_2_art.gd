# 第二夜原始回廊的可编辑派生资产。只呈现，不改变旧碰撞、锚点或章节状态。
extends RefCounted

const CORRIDOR := preload("res://assets/3d/night02_corridor/night02_corridor.glb")

static func build(parent: Node3D, _config: Dictionary) -> void:
	var art := Node3D.new()
	art.name = "Night2Art"
	parent.add_child(art)
	var model := CORRIDOR.instantiate() as Node3D
	model.name = "SourceCorridor"
	art.add_child(model)
