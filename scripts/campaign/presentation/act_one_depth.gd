# 景深只改变呈现；使用相机视空间近中远，人物全身与身旁交互面保持焦内。
extends Node3D
const DEPTH_SHADER := preload("res://scripts/campaign/presentation/hd2d_depth_blur.gdshader")
const FOCUS_HEIGHT := .95
const CLEAR_NEAR_MARGIN := 2.7
const CLEAR_FAR_MARGIN := 3.4
var enabled := true
var effect: MeshInstance3D
var _camera: Camera3D
# 保留旧存量检查/试点的读取接口，正式shader不再以世界Z决定焦距。
var clear_far_z := -5.2
var clear_near_z := 4.8
func configure(camera: Camera3D) -> void:
	if effect != null: return
	_camera = camera
	var material := ShaderMaterial.new()
	material.shader = DEPTH_SHADER
	material.set_shader_parameter("camera_focus_mode", true)
	material.set_shader_parameter("near_blur_radius", 8.0)
	material.set_shader_parameter("far_blur_radius", 4.5)
	material.set_shader_parameter("near_fade_distance", 3.8)
	material.set_shader_parameter("far_fade_distance", 5.0)
	material.render_priority = -128
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	effect = MeshInstance3D.new()
	effect.name = "ActOneLayeredDepth"
	effect.mesh = quad
	effect.material_override = material
	effect.extra_cull_margin = 16384.0
	effect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(effect)
	effect.position.z = -1.0
	follow(Vector3.ZERO)
	set_enabled(enabled)
func follow(position: Vector3) -> void:
	clear_far_z = position.z - 5.2
	clear_near_z = position.z + 4.8
	if not is_instance_valid(effect) or not is_instance_valid(_camera): return
	# 真实相机变换包含平滑跟随滞后、地形高差和边界钳位；不能只按角色世界Z平移。
	var focus_position := position + Vector3.UP * FOCUS_HEIGHT
	var focus_distance := -(_camera.global_transform.affine_inverse() * focus_position).z
	var material: ShaderMaterial = effect.material_override
	material.set_shader_parameter("focus_near_distance", maxf(_camera.near, focus_distance - CLEAR_NEAR_MARGIN))
	material.set_shader_parameter("focus_far_distance", focus_distance + CLEAR_FAR_MARGIN)
func set_enabled(value: bool) -> bool:
	enabled = value
	if is_instance_valid(effect): effect.visible = enabled
	return true
func _exit_tree() -> void:
	if is_instance_valid(effect): effect.queue_free()
