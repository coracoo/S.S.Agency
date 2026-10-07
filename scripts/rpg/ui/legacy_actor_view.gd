# 旧敌方素材的表现适配器：和高清人物共用顺序队列，不读取或结算 HP。
extends Node2D
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
var visual: Node2D
var feedback_label := Label.new()
var _facing := 1
var _down := false
# BattleView在根节点统一施加KO基色；独立适配器默认仍自行着色。
var parent_controls_defeat_tint := false
var _action: StringName = &""
var _remaining := 0.0
var _duration := 0.0
var _feedback_remaining := 0.0
func configure(sprite: Node2D, height: float, native_facing: String, toward_right: bool) -> void:
	visual = sprite
	add_child(visual)
	visual.set_meta("source_facing", native_facing)
	visual.position = Vector2.ZERO
	_facing = 1 if toward_right else -1
	Kit.face_actor(visual, toward_right)
	feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feedback_label.position = Vector2(-115, -height * 0.65)
	feedback_label.size = Vector2(230, 48)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.add_theme_font_override("font", Kit.font)
	feedback_label.add_theme_font_size_override("font_size", 28)
	feedback_label.add_theme_color_override("font_outline_color", Color(0.08, 0.07, 0.08))
	feedback_label.add_theme_constant_override("outline_size", 6)
	feedback_label.hide()
	add_child(feedback_label)
func play_action(action: StringName) -> bool:
	if _down and action != &"recover": return false
	if action == &"recover": _down = false
	_action = action
	_duration = 0.36 if action == &"attack" else 0.2
	_remaining = _duration
	return true
func set_downed(value: bool) -> void:
	_down = value
	if value: cancel_action()
func set_downed_after_hit() -> void:
	if _action == &"hit" and _remaining>0: _down=true
	else: set_downed(true)
func is_downed() -> bool: return _down
func is_action_busy() -> bool: return _remaining > 0
func action_timeout() -> float: return 1.0
func cancel_action() -> void:
	_remaining = 0.0
	if is_instance_valid(visual):
		visual.position = Vector2.ZERO
		visual.modulate = _resting_tint()
	_feedback_remaining = 0.0
	feedback_label.hide()
func _resting_tint() -> Color:
	return Color(0.4,0.4,0.4,0.55) if _down and not parent_controls_defeat_tint else Color.WHITE
func show_feedback(text: String, color: Color) -> void:
	feedback_label.text = text
	feedback_label.modulate = color
	feedback_label.show()
	_feedback_remaining = 0.8
func _process(delta: float) -> void:
	if _feedback_remaining > 0:
		_feedback_remaining = maxf(0, _feedback_remaining - delta)
		feedback_label.modulate.a = minf(1, _feedback_remaining / 0.2)
		if _feedback_remaining <= 0: feedback_label.hide()
	if _remaining <= 0: return
	_remaining = maxf(0, _remaining - delta)
	var wave := sin((1.0 - _remaining / _duration) * PI)
	if _action == &"attack": visual.position.x = wave * 30 * _facing
	elif _action == &"hit": visual.modulate = Color.WHITE.lerp(Color(1.0, 0.45, 0.35), wave)
	elif _action == &"defend": visual.modulate = Color.WHITE.lerp(Color(0.6, 0.8, 1.0), wave)
	if _remaining <= 0:
		visual.position = Vector2.ZERO
		visual.modulate = _resting_tint()
