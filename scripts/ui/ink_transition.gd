class_name InkTransition
extends Control
## 墨线收拢转场（GDD §9.6：解密→战斗/幕间切换）。
## 用法: InkTransition.transition(get_tree(), 切换回调) —— 四角墨线合拢 → 执行回调 → 拉开。

signal opened

var _p := 0.0:
	set(value):
		_p = value
		queue_redraw()
var _ink := Color("#14110E")
var _mid: Callable

static func transition(tree: SceneTree, midpoint: Callable) -> void:
	var t := InkTransition.new()
	t._mid = midpoint
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.mouse_filter = Control.MOUSE_FILTER_STOP # 转场期间阻挡输入
	# 放进高层 CanvasLayer：必须盖过 WashiOverlay（层 1）等全屏叠加
	var layer := CanvasLayer.new()
	layer.layer = 128
	layer.add_child(t)
	tree.root.add_child(layer)
	t._run()

func _run() -> void:
	var tw: Tween = create_tween()
	tw.tween_property(self, "_p", 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_on_closed)
	tw.tween_property(self, "_p", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(0.08)
	tw.tween_callback(_finish)

func _on_closed() -> void:
	if _mid.is_valid():
		_mid.call()

func _finish() -> void:
	opened.emit()
	if get_parent() is CanvasLayer: get_parent().queue_free()
	else: queue_free()

func _coverage_rects() -> Array[Rect2]:
	# CanvasLayer 的 draw 坐标已经按 stretch 缩放，不能再次使用窗口物理像素。
	var canvas_size := get_viewport().get_visible_rect().size
	var w := canvas_size.x
	var h := canvas_size.y
	var half_w := w * 0.5 * _p
	var half_h := h * 0.5 * _p
	return [
		Rect2(0, 0, w, half_h),
		Rect2(0, h - half_h, w, half_h),
		Rect2(0, half_h, half_w, h - half_h * 2.0),
		Rect2(w - half_w, half_h, half_w, h - half_h * 2.0),
	]

func _draw() -> void:
	if _p <= 0.0:
		return
	for rect in _coverage_rects():
		draw_rect(rect, _ink)
