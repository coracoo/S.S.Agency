# 固定斜侧视角，仅目标柔和跟随；快照不包含节点引用。
extends Node3D
const World = preload("res://scripts/exploration_3d/world_snapshot.gd")
var camera := Camera3D.new()
var target := Vector3.ZERO
var limits := Vector2(-6.5, 8.0)
func _ready() -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 8.0
	camera.near = 0.1
	camera.far = 120.0
	add_child(camera)
	camera.make_current()
	_apply()
func follow(actor: Node3D, delta: float) -> void:
	var wanted := actor.global_position + Vector3(0, 1.1, 0)
	wanted.x = clampf(wanted.x, limits.x, limits.y)
	wanted.z = clampf(wanted.z, -0.5, 1.1)
	target = target.lerp(wanted, 1.0 - exp(-5.0 * maxf(delta, 0)))
	_apply()
func snapshot() -> Dictionary:
	return {"mode": "follow", "target": [target.x, target.y, target.z], "size": camera.size}
func restore(value: Dictionary) -> bool:
	if value.get("mode") != "follow" or not World._vector(value.get("target")) or not World._number(value.get("size")) or value.get("size", 0) <= 0: return false
	target = Vector3(value.target[0], value.target[1], value.target[2])
	camera.size = float(value.size)
	_apply()
	return true
func _apply() -> void:
	camera.position = target + Vector3(0, 4.8, 11.0)
	camera.look_at(target)
