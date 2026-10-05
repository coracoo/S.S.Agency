# 仅第二夜可逆的HD2D呈现试点。默认不分配扩展资产，不改物理/章节/存档。
extends Node3D
const VARIANT := preload("res://assets/3d/night02_corridor_hd2d/night02_corridor_hd2d.glb")
const DEPTH_SHADER := preload("res://scripts/campaign/presentation/hd2d_depth_blur.gdshader")
const CLEAR_FAR_Z := -4.2
const CLEAR_NEAR_Z := 3.8
var enabled := false
var variant: Node3D
var effect: MeshInstance3D
var _base: Node3D
var _rig: Node3D
var _base_visible := true
func configure(night_id: int, geometry: Node3D, camera_rig: Node3D) -> bool:
	if night_id != 2 or not camera_rig.has_method("set_experimental_enabled"): return false
	var base := geometry.get_node_or_null("EnvironmentArt/Night2Art/SourceCorridor") as Node3D
	if base == null: return false
	_base = base
	_rig = camera_rig
	_base_visible = base.visible
	return true
func set_enabled(value: bool) -> bool:
	if not is_instance_valid(_base) or not is_instance_valid(_rig): return false
	if value and variant == null:
		variant = VARIANT.instantiate() as Node3D
		variant.name = "SourceCorridorHD2D"
		add_child(variant)
		var material := ShaderMaterial.new()
		material.shader = DEPTH_SHADER
		material.set_shader_parameter("clear_far_z", CLEAR_FAR_Z)
		material.set_shader_parameter("clear_near_z", CLEAR_NEAR_Z)
		material.render_priority = -128
		var mesh := QuadMesh.new()
		mesh.size = Vector2(2, 2)
		effect = MeshInstance3D.new()
		effect.name = "LayeredDepthBlur"
		effect.mesh = mesh
		effect.material_override = material
		effect.extra_cull_margin = 16384.0
		effect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rig.camera.add_child(effect)
		effect.position.z = -1.0
	enabled = value
	_base.visible = false if enabled else _base_visible
	if is_instance_valid(variant): variant.visible = enabled
	if is_instance_valid(effect): effect.visible = enabled
	_rig.set_experimental_enabled(enabled)
	return true
func _exit_tree() -> void:
	if is_instance_valid(_base): _base.visible = _base_visible
	if is_instance_valid(_rig): _rig.set_experimental_enabled(false)
	if is_instance_valid(effect): effect.queue_free()
