# 仅二夜可逆实验相机；关闭时严格恢复R03，原共享camera_rig不改。
extends "res://scripts/exploration_3d/camera_rig.gd"
var experimental_enabled := false
const EXPERIMENT_SIZE := 9.2
const EXPERIMENT_OFFSET := Vector3(0, 6.2, 11)
func set_experimental_enabled(enabled: bool) -> void:
	experimental_enabled = enabled
	_apply()
func _apply() -> void:
	if not experimental_enabled:
		camera.size = 8.0
		super._apply()
		return
	camera.size = EXPERIMENT_SIZE
	camera.position = target + EXPERIMENT_OFFSET
	camera.look_at(target)
