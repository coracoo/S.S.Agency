# 高清人物根节点就是脚点；只保存视觉状态，不保存或计算角色HP。
class_name HdActorView
extends Node2D
signal visual_warning(message: String)
const Stature = preload("res://scripts/characters/character_stature.gd")
const Animator = preload("res://scripts/characters/pixel_character_animator.gd")
var animator := Animator.new()
var feedback_label := Label.new()
var _definition: Dictionary = {}
var _height_px := 0.0
var _facing := 1
var _feedback_remaining := 0.0

func _init() -> void:
	add_child(animator)
	add_child(feedback_label)
	feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.size = Vector2(220, 38)
	feedback_label.add_theme_font_size_override("font_size", 28)
	feedback_label.add_theme_font_override("font", load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf"))
	feedback_label.add_theme_color_override("font_outline_color", Color(0.08, 0.07, 0.08))
	feedback_label.add_theme_constant_override("outline_size", 5)
	feedback_label.visible = false
	animator.visual_warning.connect(func(message: String): visual_warning.emit(message))

func configure(definition: Dictionary, height_px: float, facing: int) -> bool:
	if not definition.get("ok", false) or not is_finite(height_px) or height_px <= 0 or facing not in [-1, 1]: return false
	var canvas: Dictionary = definition.get("manifest", {}).get("canvas", {})
	if not canvas.get("content_height_px") is float and not canvas.get("content_height_px") is int: return false
	if not is_finite(float(canvas.content_height_px)) or float(canvas.content_height_px) <= 0: return false
	if not animator.configure(definition): return false
	_definition = definition
	_height_px = height_px
	animator.scale = Vector2.ONE * height_px / Stature.body_reference_pixels(definition)
	# 高清缩小使用线性过滤，素材与时序容器保持不变。
	animator.sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	set_facing(facing)
	_feedback_remaining = 0.0
	feedback_label.visible = false
	return true

func set_facing(facing: int) -> void:
	_facing = 1 if facing >= 0 else -1
	animator.set_motion(0.0, _facing)
	if _definition.is_empty(): return
	var canvas: Dictionary = _definition.manifest.canvas
	var anchor := Stature.body_anchor(_definition)
	var anchor_x := anchor.x
	if animator.sprite.flip_h: anchor_x = float(canvas.w) - anchor_x
	animator.position = -Vector2(anchor_x, anchor.y) * animator.scale

func play_action(action: StringName) -> bool:
	if action == &"recover" and not animator.is_downed():
		# 首次显示的快照可能已复苏，事件仍应有恢复表现。
		if animator.is_action_locked(): return false
		animator.request_action(&"down")
	return animator.request_action(action)

func set_downed(value: bool) -> void:
	if value == is_downed(): return
	if value: animator.request_action(&"down")
	else:
		animator.reset()
		set_facing(_facing)

func is_downed() -> bool:
	return animator.is_downed()

func is_action_busy() -> bool:
	return animator.is_action_locked() and not animator.is_downed()

func action_timeout() -> float:
	var frames: SpriteFrames = animator.sprite.sprite_frames
	var action: StringName = animator.sprite.animation
	var duration := 0.0
	if frames != null and frames.has_animation(action):
		for index in frames.get_frame_count(action):
			duration += frames.get_frame_duration(action, index) / maxf(0.001, frames.get_animation_speed(action))
	return duration + 0.35

func cancel_action() -> void:
	var down := is_downed()
	animator.reset()
	set_facing(_facing)
	if down: animator.request_action(&"down")
	_feedback_remaining = 0.0
	feedback_label.visible = false

func show_feedback(text: String, color: Color = Color.WHITE) -> void:
	feedback_label.text = text
	feedback_label.modulate = color
	feedback_label.position = Vector2(-110, -_height_px - 40)
	feedback_label.visible = true
	_feedback_remaining = 0.9

func _process(delta: float) -> void:
	if _feedback_remaining <= 0: return
	_feedback_remaining = maxf(0, _feedback_remaining - delta)
	feedback_label.position.y -= delta * 18
	feedback_label.modulate.a = minf(1.0, _feedback_remaining / 0.25)
	feedback_label.visible = _feedback_remaining > 0
