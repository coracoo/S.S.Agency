# 墨迹绘制以画布逻辑坐标覆盖全屏，避免缩放窗口只遮住左上角。
extends RefCounted
const F = preload("res://tools/rpg/fixtures.gd")
static func run() -> Array[String]:
	var failures: Array[String] = []
	var tree: SceneTree = Engine.get_main_loop()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1180, 812)
	viewport.size_2d_override = Vector2i(1920, 1321)
	viewport.size_2d_override_stretch = true
	tree.root.add_child(viewport)
	var layer := CanvasLayer.new()
	viewport.add_child(layer)
	var transition = preload("res://scripts/ui/ink_transition.gd").new()
	layer.add_child(transition)
	transition._p = 1.0
	F.expect(transition.has_method("_coverage_rects"), "墨迹转场具有可验证的逻辑画布覆盖范围", failures)
	if transition.has_method("_coverage_rects"):
		for physical in [Vector2i(1180, 812), Vector2i(960, 720), Vector2i(1280, 720)]:
			viewport.size = physical
			var covered := Rect2()
			for rect in transition._coverage_rects(): covered = covered.merge(rect)
			F.expect(covered == Rect2(Vector2.ZERO, Vector2(viewport.size_2d_override)), "墨迹闭合覆盖整个逻辑画布：" + str(physical), failures)
	transition.free()
	viewport.free()
	return failures
