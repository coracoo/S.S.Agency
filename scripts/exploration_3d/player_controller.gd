# 本场景专用的镜头平面 WASD；不改变原角色预览的左右操作。
extends "res://scripts/characters/pixel_character_world.gd"
const Stature = preload("res://scripts/characters/character_stature.gd")
const Bundle = preload("res://scripts/characters/party_asset_bundle.gd")
const JumpFeedback = preload("res://scripts/characters/jump_contact_feedback.gd")
var move_input := Vector2.ZERO
var keyboard_input := true
var _movement_armed := true
var camera_basis := Basis.IDENTITY
var shared_definition: Dictionary = {}
var run_input := false
var _run_speed := 4.2
var _hop_clock := 0.0
var _hop_duration := 0.0
var _hop_visual_baked := true
var _jump_armed := true
var _jump_feedback := JumpFeedback.new()
var _jump_feedback_generation := -1
const HOP_HEIGHT := 0.46
func _ready() -> void:
	# 正式舞台和保留的旧探索共用此控制器；新增动作必须在独立实例时也安全。
	for action in {"approach_run":KEY_SHIFT,"approach_jump":KEY_SPACE}:
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = KEY_SHIFT if action == "approach_run" else KEY_SPACE
		InputMap.action_add_event(action,event)
	super._ready()
	add_child(_jump_feedback)
	animator.action_marker.connect(_on_jump_marker)
func select_form(id: String) -> bool:
	if not shared_definition.is_empty():
		var manifest: Dictionary = shared_definition.get("manifest", {})
		var key := Bundle.asset_key(str(manifest.get("identity_id", "")), str(manifest.get("form_id", "")))
		return apply_definition(key if not key.is_empty() else id, shared_definition)
	if Bundle.MANIFESTS.has(id): return select_manifest(id, Bundle.MANIFESTS[id])
	return select_manifest(id, "res://assets/chars/pixel/%s/high_detail_complete/manifest.json" % id)
func select_manifest(id: String, path: String) -> bool:
	var changed := super.select_manifest(id,path)
	if changed: _cancel_hop()
	return changed
func apply_definition(id: String, definition: Dictionary) -> bool:
	if not animator.configure(definition): return false
	_cancel_hop()
	shared_definition = definition
	form_id = id
	configure_rendering(definition)
	_reference_speed = float(definition.manifest.move_speed_mps)
	_run_speed = float(definition.manifest.get("run_speed_mps",4.2))
	return true
func set_move_input(axis: Vector2) -> void:
	keyboard_input = false
	_movement_armed = true
	move_input = axis.limit_length(1.0) if input_enabled else Vector2.ZERO
func set_run_input(value: bool) -> void:
	run_input = value and input_enabled
func action_duration(action: StringName, fallback: float = .65) -> float:
	var frames: SpriteFrames = animator.sprite.sprite_frames
	if frames == null or not frames.has_animation(action): return fallback
	var fps := frames.get_animation_speed(action)
	if fps <= 0: return fallback
	var seconds := 0.0
	for index in frames.get_frame_count(action): seconds += frames.get_frame_duration(action,index) / fps
	return maxf(.1,seconds)
func request_jump() -> bool:
	if not input_enabled or not _movement_armed or not _jump_armed or _hop_duration > 0 or not is_on_floor() or animator.is_action_locked(): return false
	if not animator.request_action(&"jump"): return false
	_jump_armed = false
	_hop_duration = action_duration(&"jump")
	_hop_visual_baked = bool(animator.definition.manifest.get("anims",{}).get("jump",{}).get("vertical_motion_baked",true))
	_hop_clock = 0.0
	_jump_feedback_generation = animator._generation
	_jump_feedback.start(animator.definition.manifest.get("anims",{}).get("jump",{}).get("events",{}))
	return true
func _cancel_hop() -> void:
	_jump_feedback.cancel()
	_jump_feedback_generation = -1
	if _hop_duration > 0: animator.reset()
	_hop_duration = 0.0
	_hop_clock = 0.0
	billboard.position.y = 0.0
func set_control_enabled(enabled: bool) -> void:
	input_enabled = enabled
	_movement_armed = not enabled
	move_input = Vector2.ZERO
	run_input = false
	_jump_armed = not enabled
	_cancel_hop()
	motion_axis = 0
	velocity.x = 0
	velocity.z = 0
	animator.set_motion(0, facing)
func set_camera_basis(value: Basis) -> void:
	camera_basis = value
func _physics_process(delta: float) -> void:
	if not keyboard_input and input_enabled and _hop_duration <= 0: _jump_armed = true
	if keyboard_input and input_enabled:
		var current_axis := Input.get_vector("approach_left", "approach_right", "approach_forward", "approach_back")
		# A+D/W+S的合成轴为零仍代表按住；关闭菜单后必须四个action全松。
		if not _movement_armed and not Input.is_action_pressed("approach_left") and not Input.is_action_pressed("approach_right") and not Input.is_action_pressed("approach_forward") and not Input.is_action_pressed("approach_back") and not Input.is_action_pressed("approach_run") and not Input.is_action_pressed("approach_jump"):
			_movement_armed = true
		move_input = current_axis if _movement_armed else Vector2.ZERO
		run_input = Input.is_action_pressed("approach_run") and _movement_armed
		if not Input.is_action_pressed("approach_jump"): _jump_armed = true
	var axis := move_input.limit_length(1.0) if input_enabled and _hop_duration <= 0 and not animator.is_action_locked() else Vector2.ZERO
	if absf(axis.x) > 0.001: facing = 1 if axis.x > 0 else -1
	var right := Vector3(camera_basis.x.x, 0, camera_basis.x.z).normalized()
	var back := Vector3(camera_basis.z.x, 0, camera_basis.z.z).normalized()
	var direction := (right * axis.x + back * axis.y).limit_length(1.0)
	var speed := _run_speed if run_input else _reference_speed
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor(): velocity.y -= 18.0 * delta
	else: velocity.y = 0
	var before := global_position
	move_and_slide()
	var displacement := global_position - before
	var planar := Vector2(displacement.x, displacement.z).length()
	var distance := displacement.length() if planar > 0.0001 else 0.0
	if animator.has_method("set_locomotion_mode"): animator.set_locomotion_mode(&"run" if run_input else &"walk")
	animator.set_motion(distance / maxf(delta, 0.0001), facing)
	# 原生视频已带起落，不额外叠加正弦位移；脚底胶囊始终接地，不能越门或越界。
	if _hop_duration > 0:
		_hop_clock = minf(_hop_clock + delta,_hop_duration)
		billboard.position.y = 0.0 if _hop_visual_baked else sin(PI*_hop_clock/_hop_duration)*HOP_HEIGHT
		if _hop_clock >= _hop_duration:
			_hop_duration = 0.0
			billboard.position.y = 0.0
			if not keyboard_input: _jump_armed = true
	_shadow_ray.force_raycast_update()
	shadow.visible = _shadow_ray.is_colliding() and (scene_integration == null or not scene_integration.enabled)
	if shadow.visible:
		var normal := _shadow_ray.get_collision_normal()
		shadow.global_position = _shadow_ray.get_collision_point() + normal * 0.01
		var factors := get_jump_shadow_factors()
		shadow.global_basis = Basis(Quaternion(Vector3.UP, normal)).scaled_local(Vector3(factors.x, 1, 0.45*factors.x))
		shadow.material_override.albedo_color.a = 0.25*factors.y
# 阶段读取实际动画时钟；不另加物理抬升，也不把收招结束当作落地。
func get_jump_shadow_factors() -> Vector2:
	if not _jump_feedback_current() or animator.sprite.animation != &"jump": return Vector2.ONE
	return _jump_feedback.sample(animator._action_elapsed)
func _jump_feedback_current() -> bool:
	if not input_enabled or _jump_feedback_generation != animator._generation:
		_jump_feedback.cancel()
		return false
	return _jump_feedback.active
func _on_jump_marker(marker: StringName) -> void:
	if marker != &"landing" or not _jump_feedback_current() or animator.sprite.animation != &"jump": return
	_shadow_ray.force_raycast_update()
	if not _shadow_ray.is_colliding(): return
	var normal := _shadow_ray.get_collision_normal()
	if normal.dot(Vector3.UP) < .5: return
	var surface_offset := 0.0
	if scene_integration != null and scene_integration.enabled:
		surface_offset = float(scene_integration.profile.get("shadow_surface_offset_m",0.0))
	_jump_feedback.land(_shadow_ray.get_collision_point()+normal*(surface_offset+.008),normal)
func _process(delta: float) -> void:
	super._process(delta)
	_jump_feedback_current()
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo: return
	if event.is_action_pressed("approach_jump") and request_jump(): get_viewport().set_input_as_handled()
