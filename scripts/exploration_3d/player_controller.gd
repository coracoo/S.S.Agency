# 本场景专用的镜头平面 WASD；不改变原角色预览的左右操作。
extends "res://scripts/characters/pixel_character_world.gd"
var move_input := Vector2.ZERO
var keyboard_input := true
var _movement_armed := true
var camera_basis := Basis.IDENTITY
var shared_definition: Dictionary = {}
func select_form(id: String) -> bool:
	if not shared_definition.is_empty(): return apply_definition(id, shared_definition)
	return select_manifest(id, "res://assets/chars/pixel/%s/high_detail_complete/manifest.json" % id)
func apply_definition(id: String, definition: Dictionary) -> bool:
	if not animator.configure(definition): return false
	form_id = id
	var canvas: Dictionary = definition.manifest.canvas
	composite.size = Vector2i(canvas.w, canvas.h)
	billboard.offset = Vector2(float(canvas.w) * 0.5 - float(canvas.anchor[0]), float(canvas.anchor[1]) - float(canvas.h) * 0.5)
	billboard.pixel_size = float(canvas.height_m) / float(canvas.content_height_px)
	_reference_speed = float(definition.manifest.move_speed_mps)
	return true
func set_move_input(axis: Vector2) -> void:
	keyboard_input = false
	_movement_armed = true
	move_input = axis.limit_length(1.0) if input_enabled else Vector2.ZERO
func set_control_enabled(enabled: bool) -> void:
	input_enabled = enabled
	_movement_armed = not enabled
	move_input = Vector2.ZERO
	motion_axis = 0
	velocity.x = 0
	velocity.z = 0
	animator.set_motion(0, facing)
func set_camera_basis(value: Basis) -> void:
	camera_basis = value
func _physics_process(delta: float) -> void:
	if keyboard_input and input_enabled:
		var current_axis := Input.get_vector("approach_left", "approach_right", "approach_forward", "approach_back")
		if not _movement_armed and current_axis == Vector2.ZERO: _movement_armed = true
		move_input = current_axis if _movement_armed else Vector2.ZERO
	var axis := move_input.limit_length(1.0) if input_enabled and not animator.is_action_locked() else Vector2.ZERO
	if absf(axis.x) > 0.001: facing = 1 if axis.x > 0 else -1
	var right := Vector3(camera_basis.x.x, 0, camera_basis.x.z).normalized()
	var back := Vector3(camera_basis.z.x, 0, camera_basis.z.z).normalized()
	var direction := (right * axis.x + back * axis.y).limit_length(1.0)
	velocity.x = direction.x * _reference_speed
	velocity.z = direction.z * _reference_speed
	if not is_on_floor(): velocity.y -= 18.0 * delta
	else: velocity.y = 0
	var before := global_position
	move_and_slide()
	var displacement := global_position - before
	var planar := Vector2(displacement.x, displacement.z).length()
	var distance := displacement.length() if planar > 0.0001 else 0.0
	animator.set_motion(distance / maxf(delta, 0.0001), facing)
	_shadow_ray.force_raycast_update()
	shadow.visible = _shadow_ray.is_colliding() and scene_integration == null
	if shadow.visible:
		var normal := _shadow_ray.get_collision_normal()
		shadow.global_position = _shadow_ray.get_collision_point() + normal * 0.01
		shadow.global_basis = Basis(Quaternion(Vector3.UP, normal)).scaled(Vector3(1, 1, 0.45))
func _unhandled_key_input(_event: InputEvent) -> void:
	# 试玩探索没有 J 演示攻击，也不以即时攻击触发遭遇。
	pass
