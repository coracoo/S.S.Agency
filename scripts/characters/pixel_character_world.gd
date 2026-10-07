extends CharacterBody3D
## 世界原点固定脚底；仅视觉拥有状态机，不拥有HP或行动资源。
const Definition = preload('res://scripts/characters/pixel_character_definition.gd')
const BodyStature = preload('res://scripts/characters/character_stature.gd')
const Animator = preload('res://scripts/characters/pixel_character_animator.gd')
const TightFrame = preload('res://scripts/characters/tight_sprite_frame.gd')
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
var _tight_frames := TightFrame.new()
var _direct_rendering := false
var _direct_last_texture_id := 0
var _direct_last_flip := false
var _direct_last_tint := Color.WHITE

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
	animator.sprite.frame_changed.connect(_sync_direct_frame)
	animator.sprite.animation_changed.connect(_sync_direct_frame)
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
	configure_rendering(definition)
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

func configure_rendering(definition: Dictionary) -> void:
	_tight_frames.clear()
	_direct_last_texture_id = 0
	var canvas: Dictionary = definition.manifest.canvas
	composite.size = Vector2i(canvas.w,canvas.h)
	billboard.pixel_size = BodyStature.world_pixel_size(definition)
	# 只旁路已校验的单层视频。旧预览/动态头发层仍由原2D视口合成。
	_direct_rendering = definition.manifest.has('packed_frames') and definition.get('layer_frames',[]).is_empty()
	animator.visible = not _direct_rendering
	if _direct_rendering:
		_sync_direct_frame()
	else:
		var anchor := BodyStature.body_anchor(definition)
		billboard.offset = Vector2(float(canvas.w)*.5-anchor.x,anchor.y-float(canvas.h)*.5)
		billboard.flip_h = false
		billboard.modulate = Color.WHITE
		billboard.texture = composite.get_texture()
		for key in ['logical_frame_texture_id','logical_frame_rect','logical_canvas_size']:
			if billboard.has_meta(key): billboard.remove_meta(key)
	_update_visibility()

func _sync_direct_frame() -> void:
	if not _direct_rendering or animator.definition.is_empty(): return
	var sprite: AnimatedSprite2D = animator.sprite
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(sprite.animation): return
	var source: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame)
	if source == null: return
	var tint: Color = animator.modulate*sprite.modulate*sprite.self_modulate
	if source.get_instance_id() == _direct_last_texture_id and sprite.flip_h == _direct_last_flip and tint == _direct_last_tint: return
	_direct_last_texture_id = source.get_instance_id()
	_direct_last_flip = sprite.flip_h
	_direct_last_tint = tint
	billboard.offset = TightFrame.offset_for(source,BodyStature.body_anchor(animator.definition),sprite.flip_h)
	billboard.flip_h = sprite.flip_h
	billboard.modulate = tint
	billboard.texture = _tight_frames.texture_for(source)
	# 截图量测只记录整数ID/矩形，不延长旧定义纹理的生命周期。
	billboard.set_meta('logical_frame_texture_id',source.get_instance_id())
	billboard.set_meta('logical_frame_rect',TightFrame.logical_rect(source))
	billboard.set_meta('logical_canvas_size',source.get_size())
	if scene_integration != null: scene_integration.sync_art_texture()

func _process(_delta: float) -> void:
	# flip_h没有专用变更信号；帧事件即时同步，朝向/染色在绘制前补齐。
	_sync_direct_frame()

func _update_visibility() -> void:
	var active := is_visible_in_tree()
	composite.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active and not _direct_rendering else SubViewport.UPDATE_DISABLED
	animator.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
