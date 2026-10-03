extends Node3D
## 已批准的绘制人物/三维场景融合。默认关闭，纹理不改；脚点是手绘落点提示而非骨架。
const DEFAULT_PROFILE := 'res://data/characters/scene_integration/dusk_illustration.json'
var enabled := false
var contact_mode := 'root_fallback'
var grounded_count := 0
var profile: Dictionary = {}
var _actor
var _material := ShaderMaterial.new()
var _baseline_material: Material
var _baseline_shadow_visible := false
var _metadata: Dictionary = {}
var _active_metadata_path := ''
var _verified_sources: Dictionary = {}
var _shadows: Array[MeshInstance3D] = []
var _stage
var _environment_original: Environment
var _environment_blended: Environment
var _material_pairs: Array = []
func attach_to(actor, profile_path: String = DEFAULT_PROFILE) -> bool:
	if _actor != null or not FileAccess.file_exists(profile_path): return false
	var decoded = JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	if not decoded is Dictionary: return false
	profile = decoded
	_actor = actor
	_baseline_material = actor.billboard.material_override
	_baseline_shadow_visible = actor.shadow.visible
	_material.shader = load(str(profile.character_shader))
	_material.set_shader_parameter('art_texture', actor.billboard.texture)
	_material.set_shader_parameter('scene_light_mix',float(profile.scene_light_mix))
	for i in 3:
		var shadow := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE
		shadow.mesh = plane
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = load('res://scripts/characters/ground_contact_shadow.gdshader')
		shadow.material_override = material
		shadow.visible = false
		add_child(shadow)
		_shadows.append(shadow)
	return true
func set_enabled(value: bool) -> void:
	if _actor == null: return
	enabled = value
	_actor.billboard.material_override = _material if enabled else _baseline_material
	_actor.shadow.visible = false if enabled else _baseline_shadow_visible
	if _stage != null:
		_stage.get_node('WorldEnvironment').environment = _environment_blended if enabled else _environment_original
		for pair in _material_pairs:
			pair[0].set_surface_override_material(pair[1],pair[3] if enabled else pair[2])
	if not enabled:
		for shadow in _shadows: shadow.hide()
func apply_to_stage(stage) -> void:
	if _stage == stage: return
	restore_stage()
	if stage == null or not stage.has_node('WorldEnvironment'): return
	_stage = stage
	_environment_original = stage.get_node('WorldEnvironment').environment
	_environment_blended = _environment_original.duplicate(true)
	_environment_blended.ambient_light_color = Color(0.48,0.51,0.63)
	_environment_blended.ambient_light_energy = 0.64
	_environment_blended.glow_intensity = 0.3
	if stage.has_node('Model'): _collect_materials(stage.get_node('Model'))
	set_enabled(enabled)
func restore_stage() -> void:
	if is_instance_valid(_stage):
		_stage.get_node('WorldEnvironment').environment = _environment_original
		for pair in _material_pairs:
			if is_instance_valid(pair[0]): pair[0].set_surface_override_material(pair[1],pair[2])
	_stage = null
	_material_pairs.clear()
func _collect_materials(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		for surface in node.mesh.get_surface_count():
			var original = node.get_active_material(surface)
			if original is StandardMaterial3D:
				var tuned: StandardMaterial3D = original.duplicate(true)
				tuned.roughness = 0.95
				tuned.metallic_specular = minf(original.metallic_specular,0.15)
				tuned.normal_enabled = false
				var color: Color = original.albedo_color
				var grey := color.get_luminance()
				tuned.albedo_color = color.lerp(Color(grey,grey,grey,color.a),0.12)
				_material_pairs.append([node,surface,node.get_surface_override_material(surface),tuned])
	for child in node.get_children(): _collect_materials(child)
func current_contact_specs() -> Array:
	contact_mode = 'root_fallback'
	if _actor == null or _actor.animator.definition.is_empty(): return []
	var manifest: Dictionary = _actor.animator.definition.manifest
	_ensure_contact_metadata(manifest)
	var canvas: Dictionary = manifest.canvas
	var sprite = _actor.animator.sprite
	var name = str(sprite.animation)
	if str(manifest.get('character_id','')) == str(_metadata.get('character_id','')) and _metadata.get('canvas',[]) == [float(canvas.w),float(canvas.h)]:
		var animation: Dictionary = manifest.anims.get(name,{})
		var names: Array = animation.get('frames',[])
		var index: int = sprite.frame
		if animation.get('pingpong',false) and index >= names.size(): index = names.size()*2-2-index
		if index >= 0 and index < names.size():
			var frame_name = str(names[index])
			var record: Dictionary = _metadata.get('frames',{}).get(frame_name,{})
			var path = str(manifest.dir).path_join(frame_name+'.png')
			var source_key = path+':'+str(sprite.sprite_frames.get_frame_texture(name,sprite.frame).get_rid().get_id())
			if not _verified_sources.has(source_key):
				if _verified_sources.size() >= 64: _verified_sources.clear()
				_verified_sources[source_key] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ''
			if not record.is_empty() and _verified_sources[source_key] == record.get('sha256','invalid'):
				contact_mode = 'annotated'
				return record.get('contacts',[])
	return [{'point':canvas.anchor,'width_px':float(canvas.content_height_px)*0.28,'strength':0.55,'kind':'root'}]
func _ensure_contact_metadata(manifest: Dictionary) -> void:
	var integration: Dictionary = manifest.get('scene_integration',{})
	var path = str(integration.get('contact_metadata',profile.get('contact_metadata','')))
	if path == _active_metadata_path: return
	_active_metadata_path = path
	_metadata = {}
	_verified_sources.clear()
	if path.is_empty() or not FileAccess.file_exists(path): return
	var value = JSON.parse_string(FileAccess.get_file_as_string(path))
	if value is Dictionary: _metadata = value
func canvas_point_to_world(point: Vector2) -> Vector3:
	var canvas: Dictionary = _actor.animator.definition.manifest.canvas
	var x = float(canvas.w)-point.x if _actor.animator.sprite.flip_h else point.x
	var camera = get_viewport().get_camera_3d()
	var right = camera.global_basis.x if camera != null else Vector3.RIGHT
	right.y = 0.0
	right = right.normalized()
	var density: float = _actor.billboard.pixel_size
	return _actor.global_position + right*(x-float(canvas.anchor[0]))*density + Vector3.UP*(float(canvas.anchor[1])-point.y)*density
func _ground_ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from,to,_actor.collision_mask,[_actor.get_rid()])
	var hit: Dictionary = _actor.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.normal.dot(Vector3.UP) < 0.5: return {}
	return hit
func update_contacts() -> void:
	grounded_count = 0
	for shadow in _shadows: shadow.hide()
	if not enabled or _actor == null or not _actor.is_visible_in_tree(): return
	_actor.shadow.hide()
	var root_hit = _ground_ray(_actor.global_position+Vector3.UP*0.2,_actor.global_position-Vector3.UP*1.4)
	if root_hit.is_empty(): return
	var elevation = maxf(0.0,_actor.global_position.y-root_hit.position.y)
	var air_fade = clampf(1.0-elevation/0.8,0.0,1.0)
	var contacts = current_contact_specs()
	var camera = get_viewport().get_camera_3d()
	for i in mini(contacts.size(),_shadows.size()):
		var spec: Dictionary = contacts[i]
		var hit: Dictionary = root_hit
		var direction = Vector3.DOWN
		if contact_mode == 'annotated' and camera != null:
			var point = canvas_point_to_world(Vector2(spec.point[0],spec.point[1]))
			var screen = camera.unproject_position(point)
			var origin = camera.project_ray_origin(screen)
			direction = camera.project_ray_normal(screen)
			hit = _ground_ray(origin,origin+direction*150.0)
		if hit.is_empty(): continue
		var normal: Vector3 = hit.normal
		var location: Vector3 = hit.position
		# 碰撞坡面与石板美术有已知高度差；沿投影射线补偿，保持屏幕落点不被竖直抬偏。
		var visual_offset = float(profile.get('shadow_surface_offset_m',0.0))
		if absf(direction.dot(normal)) > 0.05: location += direction*visual_offset/direction.dot(normal)
		location += normal*0.004
		var width = float(spec.width_px)*_actor.billboard.pixel_size*1.45
		var length = width*0.75
		if contact_mode == 'root_fallback': width = 0.65; length = 0.30
		var shadow: MeshInstance3D = _shadows[i]
		shadow.global_transform = Transform3D(Basis(Quaternion(Vector3.UP,normal)).scaled_local(Vector3(width,1,length)),location)
		var opacity = float(profile.get('shadow_opacity',0.36)) if contact_mode == 'annotated' else float(profile.get('root_shadow_opacity',0.20))
		shadow.material_override.set_shader_parameter('opacity',opacity*float(spec.strength)*air_fade)
		shadow.show()
		grounded_count += 1
func _process(_delta: float) -> void:
	update_contacts()
func _exit_tree() -> void:
	# helper可单独移除；恢复仍存活的actor，不把材质/隐藏影遗留给调用方。
	if is_instance_valid(_actor):
		if is_instance_valid(_actor.billboard): _actor.billboard.material_override = _baseline_material
		if is_instance_valid(_actor.shadow): _actor.shadow.visible = _baseline_shadow_visible
	restore_stage()
