# 标题、对白与结尾的生图皮肤和中断流程；仅在已核验的临时 user:// 中运行。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
const Dialogue = preload("res://scripts/ui/dialogue_overlay.gd")
const ThemeData = preload("res://scripts/ui/theme.gd")
var failures: Array[String] = []
var assertions := 0
class DisplayCampaign extends RefCounted:
	var state: Dictionary = {}
	func safe_snapshot() -> Dictionary: return state.duplicate(true)
class DisplaySession extends RefCounted:
	var campaign: RefCounted
	func close() -> void: pass
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); printerr("FAIL: ", message)
func _run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	check(load("res://tools/campaign/capture_story_skin.gd").can_instantiate(), "图形采集脚本可解析")
	await _title_flows()
	await _dialogue_flows()
	await _ending_states()
	await process_frame
	load("res://scripts/campaign/presentation/night_menu_art.gd").textures.clear()
	load("res://scripts/ui/png_loader.gd").clear_cache()
	print("STORY_SKIN_ASSERTIONS:", assertions, " FAILURES:", failures.size())
	quit(0 if failures.is_empty() else 1)
func _raster_controls(node: Node) -> void:
	if node is Panel:
		check(node.get_theme_stylebox("panel") is StyleBoxTexture, "生图面板：" + str(node.name))
	if node is Button:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			check(node.get_theme_stylebox(state) is StyleBoxTexture, "生图按钮五态：" + str(node.text) + "/" + state)
		check(node.size.y >= 72, "按钮至少72px：" + str(node.text))
		check(node.get_theme_stylebox("normal").content_margin_top >= 20, "按钮文字避开金框：" + str(node.text))
	for child in node.get_children(): _raster_controls(child)
func _visible_buttons(node: Node) -> void:
	if node is Button and node.is_visible_in_tree():
		check(root.get_visible_rect().encloses(node.get_global_rect()), "操作不出屏幕：" + str(node.text))
	for child in node.get_children(): _visible_buttons(child)
func _title_flows() -> void:
	var title: Node3D = load("res://scenes/campaign/title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	_raster_controls(title)
	check(title._buttons[0].has_focus(), "标题默认聚焦新游戏")
	title._continue()
	check(not title._busy and not title._status.text.is_empty(), "无存档继续显示错误并恢复操作")
	title._request_new()
	check(title._busy, "新游戏进入可取消加载")
	title._cancel_loading()
	await process_frame
	check(not title._busy and not title._cancel_button.visible, "新游戏加载中断收回取消按钮")
	check(FileAccess.file_exists(Catalog.SAVE_PATH), "取消不删除最近成功提交的新档")
	var saved := FileAccess.get_file_as_string(Catalog.SAVE_PATH)
	title._request_new()
	check(is_instance_valid(title._replace_panel), "已有存档必须先显示替换确认")
	_raster_controls(title._replace_panel)
	var keep: Button
	for child in title._replace_panel.get_children():
		if child is Button and child.text == "保留存档": keep = child
	check(keep != null and keep.has_focus(), "替换确认默认聚焦保留")
	for resolution in [Vector2i(1920,1080), Vector2i(1280,720), Vector2i(1180,812)]:
		root.size = resolution
		for frame in 2: await process_frame
		_visible_buttons(title)
		check(title._replace_panel.size == root.get_visible_rect().size, "替换遮罩覆盖不同比例画布")
	title._cancel_replace()
	await process_frame
	check(FileAccess.get_file_as_string(Catalog.SAVE_PATH) == saved, "取消替换不改写存档")
	title._continue()
	check(title._busy, "继续有效存档进入加载")
	title._cancel_loading()
	await process_frame
	check(not title._busy and FileAccess.get_file_as_string(Catalog.SAVE_PATH) == saved, "继续加载取消保留记录")
	title._confirm_replace()
	title._set_busy(true)
	title._failed("存档未能写入：磁盘空间不足。请保留当前主线记录，确认目录可写后再重试。")
	await process_frame
	check(not title._busy and not is_instance_valid(title._replace_panel), "失败关闭确认层并恢复主操作")
	check(title._buttons[0].has_focus(), "失败恢复键盘焦点")
	check(_text_height(title._status) <= title._status.size.y, "长错误提示完整容纳")
	title._continue()
	await process_frame
	check(not title._status.get_global_rect().intersects(title._cancel_button.get_global_rect()), "错误后再继续，加载文字不覆盖取消按钮")
	title._cancel_loading()
	await process_frame
	var file := FileAccess.open(Catalog.SAVE_PATH, FileAccess.WRITE)
	file.store_string("{broken campaign"); file.close()
	title._continue()
	check(not title._busy and FileAccess.get_file_as_string(Catalog.SAVE_PATH) == "{broken campaign", "损坏存档继续失败且不覆盖原字节")
	title.free()
	if Session.current != null: Session.current.close()
func _text_height(label: Label) -> float:
	var paragraph := TextParagraph.new()
	paragraph.width = label.size.x
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	paragraph.add_string(label.text, label.get_theme_font("font"), label.get_theme_font_size("font_size"))
	return paragraph.get_size().y + maxf(0, paragraph.get_line_count() - 1) * label.get_theme_constant("line_spacing")
func _dialogue_flows() -> void:
	var dialogue := Dialogue.new(ThemeData.load_theme())
	root.add_child(dialogue)
	var nodes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cases/night_patrol.json")).nodes
	for resolution in [Vector2i(1920,1080), Vector2i(1280,720), Vector2i(1180,812)]:
		root.size = resolution
		for frame in 2: await process_frame
		var panel := dialogue._root.find_child("DialoguePanel", true, false) as Panel
		check(panel != null and panel.get_theme_stylebox("panel") is StyleBoxTexture, "对白使用批准的纹理面板")
		check(absf(panel.get_global_rect().end.y - (root.get_visible_rect().end.y - 44)) < 2, "对白跟随扩展画布底部")
		for id in nodes:
			dialogue._active = true
			dialogue._nodes = nodes
			dialogue._present_node(id)
			check(_text_height(dialogue._text_label) <= dialogue._text_label.size.y, "全部结局正文可读：" + id)
			check(panel.get_global_rect().grow(-20).encloses(dialogue._text_label.get_global_rect()), "对白文字有20px以上内框留白")
			check(not dialogue._text_label.get_global_rect().intersects(dialogue._hint_label.get_global_rect()), "正文不覆盖继续提示")
			dialogue.abort()
		await process_frame
		dialogue._active = true
		dialogue._show_choices([{"text":"送行，让执念在今夜止息。待灯火越过山门之后，再把她未说完的话带给山下的人，记下灯火、钟声与山门前的约定。", "next":"sendoff"}, {"text":"镇守，留下继续查明真相。将本案列为续监，等到来年逢魔时刻，再回此地听完最后一句话，保留这一夜尚未解开的疑问。", "next":"seal"}])
		for frame in 2: await process_frame
		_raster_controls(dialogue._choices_box)
		for button in dialogue._choices_box.get_children():
			check(root.get_visible_rect().encloses(button.get_global_rect()), "长选项不出画布")
			var contained := button.find_child("ChoiceText", true, false) as Label
			check(contained != null, "选项独立正文框，长文字换行不截断")
			if contained != null:
				check(_text_height(contained) <= contained.size.y, "长选项全部文字可见")
				check(button.get_global_rect().grow(-20).encloses(contained.get_global_rect()), "选项正文离真实边框留白：%s / %s" % [button.get_global_rect(), contained.get_global_rect()])
		var failed := [0]
		dialogue.choice_guard = func(_next): return {"ok":false,"error":"存档写入失败"}
		var listener := func(_message): failed[0] += 1
		dialogue.choice_failed.connect(listener)
		dialogue._pick_choice("sendoff")
		check(failed[0] == 1 and dialogue._waiting_choice and dialogue._choice_next.is_empty(), "选择保存失败时仍可重试且不进入分支")
		dialogue.choice_failed.disconnect(listener)
		dialogue.choice_guard = Callable()
		dialogue._pick_choice("sendoff")
		check(not dialogue._waiting_choice and dialogue._choice_next == "sendoff", "成功选择只记录原分支标识")
		dialogue.abort()
		await process_frame
	dialogue._nodes = {"portrait":{"name":"凛音","speaker":"rinne","portrait":"res://assets/chars/portraits/rinne_half.png","text":"立绘滑入检查。","side":"left","next":""}}
	dialogue._active = true
	dialogue._present_node("portrait")
	var portrait: Control = dialogue._portraits.left.ctrl
	check(portrait.position.y > float(portrait.get_meta("home").y), "换图首帧保留立绘滑入位移，不被正文布局抹去")
	root.size = Vector2i(1920,1080)
	await process_frame
	await create_timer(0.4).timeout
	check(portrait.position.is_equal_approx(portrait.get_meta("home")), "滑入中更改画布比例后，立绘不能被旧动画拉回旧位置")
	dialogue.abort()
	dialogue._nodes = {"one":{"name":"凛音","text":"还未说完的第一句。","next":"two"},"two":{"name":"薄荷","text":"下一句。","next":""}}
	dialogue._active = true
	dialogue._present_node("one")
	var advance := InputEventAction.new()
	advance.action = &"ui_accept"; advance.pressed = true
	dialogue._unhandled_input(advance)
	dialogue._process(0.0)
	check(dialogue._playing_id == "one" and not dialogue._typing, "打字时首次确认仅快进")
	dialogue._unhandled_input(advance)
	dialogue._process(0.0)
	check(dialogue._playing_id == "two", "第二次确认才进入下一句")
	dialogue.abort()
	check(not dialogue._active and not dialogue._typing, "中断后无残留打字时钟")
	dialogue.free()
func _ending_states() -> void:
	for state in [{}, {"story_phase":"complete", "chapter_complete":true, "resolution":"sendoff"}, {"story_phase":"complete", "chapter_complete":true, "resolution":"seal_monitoring"}]:
		var session := DisplaySession.new()
		session.campaign = DisplayCampaign.new(); session.campaign.state = state
		Session.current = session
		var ending: Node3D = load("res://scenes/campaign/ending.tscn").instantiate()
		root.add_child(ending)
		await process_frame
		_raster_controls(ending)
		var visible_panels := 0
		for child in ending._card.get_children():
			if child is Panel and child.is_visible_in_tree(): visible_panels += 1
		check(visible_panels == (1 if state.is_empty() else 2), "无正式完成记录时隐藏空徽章，两条正式分支仍显示徽章")
		for resolution in [Vector2i(1920,1080), Vector2i(1280,720), Vector2i(1180,812)]:
			root.size = resolution
			for frame in 2: await process_frame
			_visible_buttons(ending)
		var labels := _all_text(ending)
		check(labels.contains("正式完成记录尚未提交") if state.is_empty() else labels.contains("送行 · 安魂" if state.resolution == "sendoff" else "镇守 · 本案未结"), "三种结尾状态保留正式文本")
		check(root.gui_get_focus_owner() is Button, "结尾可直接用键盘返回标题")
		ending.free()
	Session.current = null
func _all_text(node: Node) -> String:
	var result: String = node.text + "\n" if node is Label else ""
	for child in node.get_children(): result += _all_text(child)
	return result
