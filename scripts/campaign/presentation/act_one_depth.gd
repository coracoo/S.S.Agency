# 景深只改变呈现；焦带跟随人物，跨庭院纵深时不会仍聚焦旧回廊坐标。
extends Node3D
const DEPTH_SHADER := preload("res://scripts/campaign/presentation/hd2d_depth_blur.gdshader")
var enabled := true
var effect: MeshInstance3D
var clear_far_z := -5.2
var clear_near_z := 4.8
func configure(camera: Camera3D) -> void:
	if effect != null: return
	var material := ShaderMaterial.new()
	material.shader = DEPTH_SHADER
	material.set_shader_parameter("max_blur_radius", 4.0)
	material.set_shader_parameter("fade_distance", 4.5)
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
	if is_instance_valid(effect):
		effect.material_override.set_shader_parameter("clear_far_z", clear_far_z)
		effect.material_override.set_shader_parameter("clear_near_z", clear_near_z)
func set_enabled(value: bool) -> bool:
	enabled = value
	if is_instance_valid(effect): effect.visible = enabled
	return true
func _exit_tree() -> void:
	if is_instance_valid(effect): effect.queue_free()
