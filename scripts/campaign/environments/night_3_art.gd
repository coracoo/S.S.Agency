# 第三夜同源露天石道与折纸列队。艺术层不改变旧碰撞、镜头、锚点与故事状态。
extends RefCounted

const PROCESSION := preload("res://assets/3d/night03_procession/night03_procession.glb")

static func build(parent: Node3D, _config: Dictionary) -> void:
	var art := Node3D.new()
	art.name = "Night3Art"
	parent.add_child(art)
	var model := PROCESSION.instantiate() as Node3D
	model.name = "SourceProcession"
	art.add_child(model)
