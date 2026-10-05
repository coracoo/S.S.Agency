# 正式标题、对白、结尾的真实图形采集；状态夹具不作为人工五夜全通证据。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
const Dialogue = preload("res://scripts/ui/dialogue_overlay.gd")
const ThemeData = preload("res://scripts/ui/theme.gd")
var output := ""
var captures: Array[Dictionary] = []
var failed := false
class DisplayCampaign extends RefCounted:
	var state: Dictionary = {}
	func safe_snapshot() -> Dictionary: return state.duplicate(true)
class DisplaySession extends RefCounted:
	var campaign: RefCounted
	func close() -> void: pass
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or OS.get_environment("ACT_ONE_OUTPUT").is_empty(): quit(2); return
	output = OS.get_environment("ACT_ONE_OUTPUT")
	_run.call_deferred()
func _run() -> void:
	root.content_scale_size = Vector2i(1920,1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var title: Node3D = load("res://scenes/campaign/title.tscn").instantiate()
	root.add_child(title)
	await _shots("01_title", title)
	title._confirm_replace()
	await _shots("02_title_replace", title._replace_panel)
	title._cancel_replace()
	title._set_busy(true)
	title._status.text = "正在装配高清人物素材……"
	await _shots("03_title_loading", title)
	title._cancel_loading()
	await _shots("04_title_cancelled", title)
	title._failed("存档未能写入：磁盘空间不足。请保留当前主线记录，确认目录可写后再重试。")
	await _shots("05_title_save_error", title)
	title.free()
	var session := Session.new()
	if not session.start_new(true).ok or not (await session.prepare_assets()).ok: quit(1); return
	var stage: Node3D = load(Catalog.scene_path(1)).instantiate()
	root.add_child(stage)
	for frame in 10: await physics_frame
	if not stage.ready_for_play: quit(1); return
	stage._generation += 1
	if is_instance_valid(stage._dialogue): stage._dialogue.abort(); stage._dialogue.queue_free()
	stage._dialogue = null; stage._arrival_checked = true; stage._resume_explore()
	if not stage.begin_operation("dialogue"): quit(1); return
	stage._refresh_hud()
	var dialogue := Dialogue.new(ThemeData.load_theme())
	dialogue.portrait_provider = stage._dialogue_portrait
	stage.add_child(dialogue)
	var nodes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cases/night_patrol.json")).nodes
	var longest := ""
	var choice := ""
	for id in nodes:
		if longest.is_empty() or str(nodes[id].get("text", "")).length() > str(nodes[longest].get("text", "")).length(): longest = id
		if not nodes[id].get("choices", []).is_empty(): choice = id
	dialogue._nodes = nodes
	dialogue._active = true
	dialogue._present_node(longest)
	dialogue._typing = false; dialogue._process(0)
	dialogue.set_process(false)
	await _shots("06_dialogue_longest", dialogue)
	dialogue._present_node(choice)
	dialogue._typing = false; dialogue._process(0)
	await _shots("07_dialogue_choices", dialogue)
	dialogue._show_choices([{"text":"长选项换行检查：送行，让执念在今夜止息。待灯火越过山门之后，再把她未说完的话带给山下的人，记下灯火、钟声与山门前的约定。", "next":"sendoff"}, {"text":"长选项换行检查：镇守，留下继续查明真相。将本案列为续监，等到来年逢魔时刻，再回此地听完最后一句话，保留这一夜尚未解开的疑问。", "next":"seal"}])
	await _shots("08_dialogue_long_choice_qa", dialogue)
	dialogue.abort(); dialogue.free(); stage.free(); session.close()
	for state in [{}, {"story_phase":"complete", "chapter_complete":true, "resolution":"sendoff"}, {"story_phase":"complete", "chapter_complete":true, "resolution":"seal_monitoring"}]:
		var display := DisplaySession.new()
		display.campaign = DisplayCampaign.new(); display.campaign.state = state
		Session.current = display
		var ending: Node3D = load("res://scenes/campaign/ending.tscn").instantiate()
		root.add_child(ending)
		await _shots("09_ending_missing" if state.is_empty() else ("10_ending_sendoff" if state.resolution == "sendoff" else "11_ending_monitoring"), ending)
		ending.free()
	Session.current = null
	var file := FileAccess.open(output.path_join("story-skin-capture-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"status":"fail" if failed else "pass", "source":"正式场景与生产控件；结尾状态、加载状态与超长选项使用显示夹具，不冒称人工全章通关。", "captures":captures}, "\t")); file.close()
	print("STORY_SKIN_CAPTURE:", captures.size(), " screenshots")
	quit(1 if failed else 0)
func _shots(name: String, surface: Node) -> void:
	for resolution in [Vector2i(1920,1080), Vector2i(1280,720), Vector2i(1180,812)]:
		root.size = resolution
		for frame in 6: await process_frame
		# 成对截图冻结场景动画，透明装饰外缘不应把身后人物帧差误判成文字。
		paused = true
		await RenderingServer.frame_post_draw
		var filename := "%s_%dx%d.png" % [name,resolution.x,resolution.y]
		var screenshot := root.get_texture().get_image()
		if screenshot.save_png(output.path_join(filename)) != OK: failed = true; return
		captures.append({"image":filename, "width":screenshot.get_width(), "height":screenshot.get_height()})
		await _text_mask(surface, filename)
		paused = false
func _text_mask(surface: Node, filename: String) -> void:
	var backups: Array[Dictionary] = []
	var buttons: Array[Dictionary] = []
	var pending: Array[Node] = [surface]
	var scale := float(root.size.y) / root.get_visible_rect().size.y
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if not node is Control or not node.is_visible_in_tree(): continue
		if node is Button:
			var rect: Rect2 = node.get_global_rect()
			var text: String = node.text
			var choice_text := node.get_node_or_null("ChoiceText") as Label
			if choice_text != null: text = choice_text.text
			buttons.append({"text":text, "rect":[rect.position.x*scale,rect.position.y*scale,rect.size.x*scale,rect.size.y*scale]})
			var colors: Dictionary = {}
			for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_disabled_color","font_outline_color","font_shadow_color"]:
				colors[key] = node.get_theme_color(key)
				node.add_theme_color_override(key, Color.TRANSPARENT)
			backups.append({"node":node,"colors":colors})
		elif node is Label or node is RichTextLabel:
			backups.append({"node":node,"modulate":node.self_modulate})
			node.self_modulate = Color(1,1,1,0)
	for frame in 2: await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output.path_join(filename.trim_suffix(".png")+"_notext.png")) != OK: failed = true
	var file := FileAccess.open(output.path_join(filename.trim_suffix(".png")+"_text_bounds.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"image":filename,"scale":scale,"buttons":buttons},"\t")); file.close()
	for saved in backups:
		if saved.has("colors"):
			for key in saved.colors: saved.node.add_theme_color_override(key,saved.colors[key])
		else: saved.node.self_modulate = saved.modulate
	await process_frame
