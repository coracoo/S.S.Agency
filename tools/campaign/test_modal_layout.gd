# 用真实字体换行与场景树Control矩形验证线索确认，不占用图形桌面。
extends SceneTree
const Stage = preload("res://scripts/campaign/chapter_stage.gd")
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
var failures: Array[String] = []
var assertions := 0
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1":
		printerr("FAIL: modal layout requires verified user isolation")
		quit(2)
		return
	call_deferred("_run")
func expect(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: ", description)
func _run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var source: Dictionary = Chapters.clue(4, "mirror_in_coffin")
	var body: String = str(source.hint) + "\n\n" + str(source.resolve_text)
	for window_size in [Vector2i(1920, 1080), Vector2i(1180, 812)]:
		root.size = window_size
		var stage = Stage.new()
		root.add_child(stage)
		stage.set_process(false)
		stage._show_modal(str(source.name), body, [{"text": "进入战斗", "call": Callable()}, {"text": "暂不应战", "call": Callable()}])
		await process_frame
		await process_frame
		var label: Label = _body_label(stage._modal, body)
		expect(label != null, "保留第四夜原hint+resolve全文：%s" % window_size)
		if label != null:
			var button: Button = stage._modal_buttons[0]
			expect(label.get_global_rect().end.y + 16.0 <= button.get_global_rect().position.y, "原正文全部换行在按钮上方且不相交：%s" % window_size)
			expect(label.size.y >= label.get_minimum_size().y, "正文容纳真实字体换行高度：%s" % window_size)
		var visible: Rect2 = root.get_visible_rect()
		for button in stage._modal_buttons:
			expect(visible.encloses(button.get_global_rect()), "按钮在可见画布内：%s" % window_size)
		stage._show_modal("长线索布局回归", body.repeat(30), [{"text": "确认", "call": Callable()}, {"text": "取消", "call": Callable()}])
		await process_frame
		await process_frame
		var scroll := stage._modal.find_child("ModalBodyScroll", true, false) as ScrollContainer
		expect(scroll != null, "长正文具有滚动阅读区：%s" % window_size)
		if scroll != null:
			var long_label: Label = _body_label(scroll, body.repeat(30))
			expect(long_label != null and long_label.get_minimum_size().y > scroll.size.y and scroll.get_v_scroll_bar().visible, "长正文不截字可垂直滚动：%s" % window_size)
			expect(scroll.get_global_rect().end.y + 16.0 <= stage._modal_buttons[0].get_global_rect().position.y, "滚动区与按钮不相交：%s" % window_size)
		for button in stage._modal_buttons:
			expect(visible.encloses(button.get_global_rect()), "长正文按钮不超屏：%s" % window_size)
		stage.free()
	print("CAMPAIGN_MODAL_LAYOUT_ASSERTIONS:", assertions)
	quit(0 if failures.is_empty() else 1)
func _body_label(node: Node, text: String) -> Label:
	if node is Label and node.text == text: return node
	for child in node.get_children():
		var found := _body_label(child, text)
		if found != null: return found
	return null
