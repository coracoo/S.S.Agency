# 连续寺域镜头：人物保持中景尺寸，镜头沿真实横向、纵深与地形高差跟随。
extends "res://scripts/exploration_3d/camera_rig.gd"
const WORLD_SIZE := 9.2
const WORLD_OFFSET := Vector3(0, 6.2, 11.0)
var depth_limits := Vector2(-18, 11)
var height_limits := Vector2(1.1, 7.1)
func _ready() -> void:
	limits = Vector2(-9.05, 68)
	super._ready()
func configure_world(bounds: Dictionary) -> void:
	limits = Vector2(bounds.x[0], bounds.x[1])
	depth_limits = Vector2(bounds.z[0], bounds.z[1])
	var height: Array = bounds.get("y", [-0.5, 6.0])
	height_limits = Vector2(maxf(1.1, float(height[0]) + 1.1), float(height[1]) + 1.1)
func follow(actor: Node3D, delta: float) -> void:
	var wanted := actor.global_position + Vector3(0, 1.1, 0)
	wanted.x = clampf(wanted.x, limits.x, limits.y)
	wanted.z = clampf(wanted.z, depth_limits.x, depth_limits.y)
	wanted.y = clampf(wanted.y, height_limits.x, height_limits.y)
	target = target.lerp(wanted, 1.0 - exp(-5.0 * maxf(delta, 0)))
	_apply()
func _apply() -> void:
	camera.size = WORLD_SIZE
	camera.far = 180.0
	camera.position = target + WORLD_OFFSET
	camera.look_at(target)
