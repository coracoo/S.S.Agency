extends CharacterBody3D
## 世界原点固定脚底；仅视觉拥有状态机，不拥有HP或行动资源。
const Definition = preload('res://scripts/characters/pixel_character_definition.gd')
const Animator = preload('res://scripts/characters/pixel_character_animator.gd')
var animator = Animator.new()
var composite := SubViewport.new()
var billboard := Sprite3D.new()
var shadow := MeshInstance3D.new()
var motion_axis := 0.0
var input_enabled := true
var form_id := ''
var facing := 1
var warning := ''
var _reference_speed := 2.6
var _shadow_ray := RayCast3D.new()
var scene_integration: Node3D

func enable_scene_integration(stage: Node = null) -> bool:
	if scene_integration == null:
		var helper = load('res://scripts/characters/character_scene_integration.gd').new()
		add_child(helper)
		if not helper.attach_to(self):
			helper.queue_free()
			return false
		scene_integration = helper
	if stage != null: scene_integration.apply_to_stage(stage)
	scene_integration.set_enabled(true)
	return true

func disable_scene_integration() -> void:
	if scene_integration == null: return
	scene_integration.set_enabled(false)
	scene_integration.restore_stage()

func _ready() -> void:
	floor_snap_length = 0.5
	floor_stop_on_slope = true
	floor_max_angle = deg_to_rad(48)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.22
	capsule.height = 1.4
	collision.shape = capsule
	collision.position.y = 0.7
	add_child(collision)
	composite.name = 'CharacterComposite'
	composite.transparent_bg = true
	composite.disable_3d = true
	composite.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(composite)
	composite.add_child(animator)
	animator.visual_warning.connect(func(message: String): warning = message)
	billboard.texture = composite.get_texture()
	billboard.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	billboard.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	billboard.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	billboard.alpha_scissor_threshold = 0.5
	billboard.shaded = false
	billboard.no_depth_test = false
	billboard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(billboard)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.25
	mesh.bottom_radius = 0.25
	mesh.height = 0.002
	shadow.mesh = mesh
	shadow.scale.z = 0.45
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.05, 0.05, 0.09, 0.25)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = material
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)
	_shadow_ray.position.y = 0.6
	_shadow_ray.target_position = Vector3(0, -2, 0)
	_shadow_ray.exclude_parent = true
	add_child(_shadow_ray)
	visibility_changed.connect(_update_visibility)
	if not select_form('rinne'): select_form('legacy_rinne')
	_update_visibility()

func select_form(id: String) -> bool:
	var path := 'res://assets/chars/rinne_25d/animation_manifest.json' if id == 'legacy_rinne' else 'res://assets/chars/pixel/%s/manifest.json' % id
	return select_manifest(id,path)

func select_manifest(id: String, path: String) -> bool:
	var definition := Definition.load_definition(path)
	if not definition.ok:
		warning = '%s尚未完成：%s' % [id, '; '.join(definition.errors)]
		return false
	if not animator.configure(definition): return false
	form_id = id
	warning = '原版凛音动作基线（非新像素成品）' if id == 'legacy_rinne' else str(definition.manifest.get('status', '待验收'))
	var canvas: Dictionary = definition.manifest.canvas
	composite.size = Vector2i(canvas.w, canvas.h)
	# Sprite3D offset.y为向上，和2D画布方向相反。
	billboard.offset = Vector2(float(canvas.w) * 0.5 - float(canvas.anchor[0]), float(canvas.anchor[1]) - float(canvas.h) * 0.5)
	billboard.pixel_size = float(canvas.height_m) / float(canvas.content_height_px)
	_reference_speed = float(definition.manifest.move_speed_mps)
	velocity = Vector3.ZERO
	motion_axis = 0
	return true

func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	motion_axis = 0

func _physics_process(delta: float) -> void:
	if input_enabled:
		motion_axis = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var axis := 0.0 if animator.is_action_locked() else motion_axis
	if axis != 0: facing = 1 if axis > 0 else -1
	velocity.x = axis * _reference_speed
	velocity.z = 0
	if not is_on_floor(): velocity.y -= 18.0 * delta
	else: velocity.y = 0
	var before := global_position
	move_and_slide()
	# 真实路径速度排除重力抖动，终点即便按住键也回idle。
	var moved_x := absf(global_position.x - before.x)
	var tangent_distance := Vector2(global_position.x - before.x, global_position.y - before.y).length() if moved_x > 0.0001 else 0.0
	animator.set_motion(tangent_distance / maxf(delta, 0.0001), facing)
	_shadow_ray.force_raycast_update()
	shadow.visible = _shadow_ray.is_colliding()
	if shadow.visible:
		var normal := _shadow_ray.get_collision_normal()
		shadow.global_position = _shadow_ray.get_collision_point() + normal * 0.01
		shadow.global_basis = Basis(Quaternion(Vector3.UP, normal)).scaled(Vector3(1, 1, 0.45))

func _unhandled_key_input(event: InputEvent) -> void:
	if not input_enabled or not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode == KEY_J or event.keycode == KEY_J:
		animator.request_action('attack')
		get_viewport().set_input_as_handled()

func _update_visibility() -> void:
	var active := is_visible_in_tree()
	composite.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	animator.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
