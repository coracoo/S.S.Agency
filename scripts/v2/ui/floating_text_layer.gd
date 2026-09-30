class_name FloatingTextLayer
extends Control
## 飘字层 v2
##
## 显示伤害/治疗/combo 触发等飘字。用 Label + Tween 实现上浮+淡出，不需要粒子系统。
## 调用 show_text(world_pos, text, color) 即可。
##
## 注意：本节点应放在 battle_scene 的最上层，mouse_filter = IGNORE，不阻挡点击。

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## 在指定位置显示一个飘字
## [param pos] 父节点坐标系下的位置（一般是 unit 视图的全局位置）
## [param text] 文本内容
## [param color] 文字颜色
## [param big] 是否大号（combo 触发用）
func show_text(pos: Vector2, text: String, color: Color = Color.WHITE, big: bool = false) -> void:
	var label = Label.new()
	label.text = text
	label.position = pos + Vector2(randf_range(-12, 12), -20)
	label.add_theme_font_size_override("font_size", 28 if big else 20)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	label.z_index = 100
	label.pivot_offset = Vector2(40, 20)  # 大致居中
	add_child(label)

	# 上浮 + 淡出 + 轻微放大
	var t = create_tween()
	t.set_parallel(true)
	t.tween_property(label, "position:y", label.position.y - 50.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate:a", 0.0, 0.9).set_ease(Tween.EASE_IN)
	t.tween_property(label, "scale", Vector2(1.15, 1.15), 0.2).set_trans(Tween.TRANS_BACK)
	t.chain().tween_property(label, "scale", Vector2(1.0, 1.0), 0.2)
	t.tween_callback(label.queue_free).set_delay(1.0)


## 在某个 Control 节点上方飘字（自动取其全局位置转本层坐标）
func show_above(control: Control, text: String, color: Color = Color.WHITE, big: bool = false) -> void:
	if control == null:
		return
	var global_pos = control.global_position
	var local_pos = global_pos - global_position
	show_text(Vector2(local_pos.x + control.size.x * 0.5, local_pos.y + 20), text, color, big)
