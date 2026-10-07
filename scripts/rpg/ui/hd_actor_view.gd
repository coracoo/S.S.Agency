# 高清人物根节点就是脚点；只保存视觉状态，不保存或计算角色HP。
class_name HdActorView
extends Node2D
signal visual_warning(message: String)
signal presentation_position_changed
const Stature = preload("res://scripts/characters/character_stature.gd")
const Animator = preload("res://scripts/characters/pixel_character_animator.gd")
const Melee = preload("res://scripts/rpg/ui/melee_motion.gd")
var animator := Animator.new()
var feedback_label := Label.new()
var _definition: Dictionary = {}
var _height_px := 0.0
var _facing := 1
var _feedback_remaining := 0.0
var _melee: Dictionary = {}
var _melee_generation := 0
var _presentation_generation := 0
# 仅录制/组件诊断显式开启；正式演员默认不得用静帧滑移冒充已交付冲刺。
var allow_unapproved_melee_preview := false
# 实际3D战场应以整段投影范围配置；默认仅供独立人物/旧2D场景安全降级。
var _melee_allowed_feet := Rect2(180,590,1560,120)

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
	_presentation_generation += 1
	allow_unapproved_melee_preview = false
	restore_melee_home()
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
	if value: restore_melee_home()
	if value == is_downed(): return
	_presentation_generation += 1
	if value: animator.request_action(&"down")
	else:
		animator.reset()
		set_facing(_facing)

func is_downed() -> bool:
	return animator.is_downed()

func is_action_busy() -> bool:
	return animator.is_action_locked() and (not animator.is_downed() or animator.sprite.is_playing())

func action_timeout() -> float:
	var frames: SpriteFrames = animator.sprite.sprite_frames
	var action: StringName = animator.sprite.animation
	var duration := 0.0
	if frames != null and frames.has_animation(action):
		for index in frames.get_frame_count(action):
			duration += frames.get_frame_duration(action, index) / maxf(0.001, frames.get_animation_speed(action))
	return duration + 0.35

# 仅提供当前表现的命中时刻；未声明的旧人物仍按整段动作顺序播放。
func action_impact_time() -> float:
	var animations: Variant = _definition.get("manifest", {}).get("anims", {})
	if not animations is Dictionary: return 0.0
	var spec: Variant = animations.get(str(animator.sprite.animation), {})
	if not spec is Dictionary: return 0.0
	var value: Variant = spec.get("impact_ms")
	if not (value is int or value is float) or not is_finite(float(value)): return 0.0
	var seconds := float(value) / 1000.0
	return seconds if seconds > 0 and seconds < action_timeout() - 0.35 else 0.0

func cancel_action() -> void:
	_presentation_generation += 1
	restore_melee_home()
	var down := is_downed()
	animator.reset()
	set_facing(_facing)
	if down: animator.request_action(&"down")
	_feedback_remaining = 0.0
	feedback_label.visible = false

func configure_melee_bounds(allowed_feet: Rect2, target_radius_px: float = 45.0) -> void:
	if allowed_feet.has_area() and allowed_feet.position.is_finite() and allowed_feet.size.is_finite():
		_melee_allowed_feet = allowed_feet
	set_meta("melee_body_radius_px",maxf(24.0,target_radius_px))

func supports_melee_approach() -> bool:
	return Melee.is_melee_form(_definition) and (allow_unapproved_melee_preview or has_approved_melee_dash())

func has_approved_melee_dash() -> bool:
	var frames: SpriteFrames = animator.sprite.sprite_frames
	var spec: Dictionary = _definition.get("manifest",{}).get("anims",{}).get("battle_dash",{})
	var approved: Variant = spec.get("qa_approved",false)
	return approved is bool and approved and frames != null and frames.has_animation(&"battle_dash") and frames.get_frame_count(&"battle_dash") > 1

func presentation_generation() -> int:
	return _presentation_generation

func begin_melee_approach(target: Node2D) -> bool:
	if not supports_melee_approach() or is_downed() or is_action_busy() or not is_instance_valid(target): return false
	if target.has_method("is_downed") and target.is_downed(): return false
	restore_melee_home()
	var destination := Melee.strike_point(position,target.position,_height_px,Melee.form_key(_definition),float(target.get_meta("melee_body_radius_px",45.0)),_melee_allowed_feet)
	if position.distance_to(destination) < 2.0: return false
	_melee_generation += 1
	_melee = {"phase":"approach","home":position,"from":position,"to":destination,"elapsed":0.0,"facing":_facing,"target":weakref(target)}
	set_facing(1 if target.position.x >= position.x else -1)
	var frames: SpriteFrames = animator.sprite.sprite_frames
	if frames.has_animation(&"battle_dash") and frames.get_frame_count(&"battle_dash") > 1:
		animator.sprite.play(&"battle_dash")
		var duration := 0.0
		for index in frames.get_frame_count(&"battle_dash"):
			duration += frames.get_frame_duration(&"battle_dash",index) / maxf(.001,frames.get_animation_speed(&"battle_dash"))
		animator.sprite.speed_scale = duration / Melee.APPROACH_SECONDS
		set_meta("melee_dash_interim_fallback",false)
	else:
		# 不加载世界专用大页；缺少紧凑dash时仅供诊断，最终素材门禁不得接受。
		animator.sprite.animation = &"attack"
		animator.sprite.set_frame_and_progress(0,0)
		animator.sprite.pause()
		set_meta("melee_dash_interim_fallback",true)
		visual_warning.emit("近战缺少多帧 battle_dash，当前接近姿势仅为临时降级")
	return true

func is_melee_approaching() -> bool:
	return _melee.get("phase", "") == "approach"

func is_melee_moving() -> bool:
	return not _melee.is_empty()

func begin_melee_recovery(remaining_action: float) -> void:
	if _melee.is_empty() or is_downed(): return
	_melee.phase = "hold"
	_melee.elapsed = 0.0
	# 正式多帧返回须等完整原生攻击E，不把攻击/idle尾帧平移当跑回。
	# 旧静帧路径仅供明确历史诊断，保留其对照时序。
	_melee.return_dash = has_approved_melee_dash()
	_melee.delay = maxf(Melee.CONTACT_HOLD_SECONDS,remaining_action if _melee.return_dash else remaining_action-Melee.RETURN_SECONDS)

func restore_melee_home() -> void:
	if _melee.is_empty(): return
	var previous := _melee
	_melee_generation += 1
	_melee = {}
	position = previous.home
	set_facing(int(previous.facing))
	presentation_position_changed.emit()

func _step_melee(delta: float) -> void:
	if _melee.is_empty(): return
	if is_downed(): restore_melee_home(); return
	var target: Variant = _melee.target.get_ref()
	if _melee.phase == "approach" and (not is_instance_valid(target) or not target.is_inside_tree() or (target.has_method("is_downed") and target.is_downed())):
		restore_melee_home()
		return
	_melee.elapsed += delta
	if _melee.phase == "hold":
		if float(_melee.elapsed) < float(_melee.delay): return
		if _melee.get("return_dash",false) and is_action_busy(): return
		_melee.phase = "return"
		_melee.from = position
		_melee.elapsed = 0.0
		if _melee.get("return_dash",false):
			set_facing(1 if (_melee.home as Vector2).x >= position.x else -1)
			animator.sprite.play(&"battle_dash")
			var frames: SpriteFrames = animator.sprite.sprite_frames
			var duration := 0.0
			for index in frames.get_frame_count(&"battle_dash"):
				duration += frames.get_frame_duration(&"battle_dash",index) / maxf(.001,frames.get_animation_speed(&"battle_dash"))
			animator.sprite.speed_scale = duration / Melee.RETURN_SECONDS
	if _melee.phase not in ["approach","return"]: return
	var returning: bool = _melee.phase == "return"
	var duration: float = Melee.RETURN_SECONDS if returning else Melee.APPROACH_SECONDS
	var progress := clampf(float(_melee.elapsed)/duration,0.0,1.0)
	# 以有限线性地面运动避免末端拖沓；两端精确钉住脚点，不产生高度或缩放补偿。
	position = (_melee.from as Vector2).lerp(_melee.home if returning else _melee.to,progress)
	var generation := _melee_generation
	presentation_position_changed.emit()
	if generation != _melee_generation: return
	if progress >= 1.0:
		if returning: restore_melee_home()
		else:
			_melee.phase = "strike"
			animator.sprite.speed_scale = 1.0
			animator.sprite.pause()

func _exit_tree() -> void:
	restore_melee_home()

func show_feedback(text: String, color: Color = Color.WHITE) -> void:
	feedback_label.text = text
	feedback_label.modulate = color
	feedback_label.position = Vector2(-110, -_height_px - 40)
	feedback_label.visible = true
	_feedback_remaining = 0.9

func _process(delta: float) -> void:
	_step_melee(delta)
	if _feedback_remaining <= 0: return
	_feedback_remaining = maxf(0, _feedback_remaining - delta)
	feedback_label.position.y -= delta * 18
	feedback_label.modulate.a = minf(1.0, _feedback_remaining / 0.25)
	feedback_label.visible = _feedback_remaining > 0
