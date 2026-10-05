# 正式UI色阶、五态、场景露出与中文布局契约；只从已核验的隔离入口运行。
extends SceneTree
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
const ThemeData = preload("res://scripts/ui/theme.gd")
const Stage = preload("res://scripts/campaign/chapter_stage.gd")
const Dialogue = preload("res://scripts/ui/dialogue_overlay.gd")
const WorldMap = preload("res://scripts/campaign/presentation/act_one_map.gd")
const Party = preload("res://scripts/campaign/party_panel.gd")
const F = preload("res://tools/rpg/fixtures.gd")
const Battle = preload("res://scripts/rpg/battle_engine.gd")
const RpgCatalog = preload("res://scripts/rpg/catalog.gd")
const BattleView = preload("res://scripts/rpg/ui/battle_view.gd")
var failures: Array[String] = []
var assertions := 0
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func expect(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); printerr("FAIL: ", message)
func _luminance(value: Color) -> float:
	var linear := value.srgb_to_linear()
	return linear.r * 0.2126 + linear.g * 0.7152 + linear.b * 0.0722
func _contrast(first: Color, second: Color) -> float:
	var a := _luminance(first)
	var b := _luminance(second)
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)
func _run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var host := Control.new()
	root.add_child(host)
	var standard := Kit.button(host, "返回探索", Rect2(0, 0, 220, 56))
	var primary := Kit.button(host, "开始新游戏", Rect2(0, 70, 300, 64), Callable(), true)
	for button in [standard, primary]:
		var state_colors: Array[Color] = []
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			expect(button.has_theme_stylebox_override(state), "按钮具有独立五态：" + state)
			var style := button.get_theme_stylebox(state) as StyleBoxFlat
			expect(style != null, "按钮五态使用无纹理轻量样式：" + state)
			if style == null: continue
			if state == "focus":
				expect(not style.draw_center and style.border_width_left >= 2 and style.expand_margin_left >= 2, "键盘焦点独立高对比外环，不遮盖当前按钮状态")
			else:
				expect(not state_colors.has(style.bg_color), "按钮状态底色可辨：" + state)
				state_colors.append(style.bg_color)
				var text_state: String = "font_disabled_color" if state == "disabled" else ("font_color" if state == "normal" else "font_" + state + "_color")
				expect(_contrast(button.get_theme_color(text_state), style.bg_color) >= (3.0 if state == "disabled" else 4.5), "状态中文字对比达标：" + state)
	var motion := InputEventMouseMotion.new()
	motion.position = primary.get_global_rect().get_center()
	root.push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.position = motion.position
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	for frame in 3: await process_frame
	expect(primary.get_draw_mode() in [BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED], "真实鼠标按住按钮持续显示按下态")
	press.pressed = false
	root.push_input(press, true)
	var normal := standard.get_theme_stylebox("normal") as StyleBoxFlat
	var action := primary.get_theme_stylebox("normal") as StyleBoxFlat
	expect(normal.bg_color != action.bg_color, "主动作和普通工具权重不同")
	expect(normal.border_width_left <= 1, "普通按钮不再使用厚金框")
	var panel := Kit.panel(host, Rect2(0, 150, 320, 100))
	var panel_style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	expect(panel_style != null and panel_style.bg_color.g >= panel_style.bg_color.r, "正式面板为墨青烟黑底")
	expect(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "装饰面板不吞世界鼠标事件")
	var map := WorldMap.new()
	map.size = Vector2(1440, 700)
	expect(map.has_method("label_rect"), "地图标签有安全区计算，避免文字压出面板")
	if map.has_method("label_rect"):
		for edge in [Vector2.ZERO, map.size, Vector2(12, 60)]:
			var bounds: Rect2 = map.call("label_rect", edge, "山门前庭")
			expect(Rect2(Vector2(10, 10), map.size - Vector2(20, 20)).encloses(bounds), "边缘地图标签留出阅读空间")
	expect(map.has_method("walk_outline"), "地图合并实际可走面外轮廓，不叠画调试矩形")
	if map.has_method("walk_outline"):
		var outlines: Array = map.call("walk_outline")
		expect(outlines.size() == 1 and outlines[0].size() > 8, "寺域全部实际可走面合成唯一连续多边形")
	if map.has_method("route_paths"):
		for route in map.call("route_paths"):
			for index in range(route.size() - 1):
				for sample in range(21):
					var point: Vector2 = route[index].lerp(route[index + 1], sample / 20.0)
					expect(not load("res://scripts/campaign/act_one_layout.gd").region_at(Vector3(point.x, 0, point.y)).is_empty(), "地图引导线不能画入不可通行的区域")
	map.free()
	var before_selected: StyleBoxFlat = standard.get_theme_stylebox("normal")
	Kit.set_selected(standard, true)
	var chosen: StyleBoxFlat = standard.get_theme_stylebox("normal")
	expect(chosen.bg_color != before_selected.bg_color and chosen.border_width_left == 3, "已选状态有底色与左侧标记，不改变按钮机制")
	Kit.set_selected(standard, false)
	expect((standard.get_theme_stylebox("normal") as StyleBoxFlat).bg_color == before_selected.bg_color, "取消选择恢复常态")
	host.free()
	for size in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(1180, 812)]:
		root.size = size
		await process_frame
		var stage := Stage.new()
		root.add_child(stage)
		stage.set_process(false)
		stage._close_modal()
		stage._world = {"event_flags": {"dialogue:a1": true}}
		stage._refresh_hud()
		expect(not stage._hud.objective.text.contains("应对异象"), "当前目标优先显示可调查线索，不提前要求尚未解锁的战斗")
		await process_frame
		var hud: Control = stage._ui_layer.get_child(0)
		var info := hud.find_child("NightInformation", true, false) as Panel
		expect(info != null, "HUD具有独立短信息卡：%s" % size)
		if info != null:
			expect(info.size.x <= 900 and info.size.y <= 112, "HUD不再全宽压住场景：%s" % size)
		for child in hud.get_children():
			if child is Button:
				expect(root.get_visible_rect().encloses(child.get_global_rect()), "右上工具保持可见：%s" % size)
				expect(child.get_theme_font_size("font_size") <= 24, "工具字级低于夜次标题")
		expect(stage._hud.has("map") and stage._hud.has("pause") and not stage._hud.has("exit"), "探索只保留地图与菜单，标题和景深收进夜巡菜单")
		expect(stage._hud.objective.size.x <= 760 and stage._hud.objective.get_theme_font_size("font_size") <= 24, "目标与地点层级紧凑")
		var dialog := Dialogue.new(ThemeData.load_theme())
		root.add_child(dialog)
		var dialogue_panel := dialog._root.find_child("DialoguePanel", true, false) as Panel
		expect(dialogue_panel != null, "对白使用命名烟墨面板")
		if dialogue_panel != null:
			var surface := dialogue_panel.get_theme_stylebox("panel") as StyleBoxFlat
			expect(surface != null, "对白不再使用厚纸纹/金框")
			if surface != null: expect(_contrast(dialog._text_label.get_theme_color("font_color"), surface.bg_color) >= 7.0, "对白正文高对比")
			expect(dialogue_panel.get_global_rect().encloses(dialog._text_label.get_global_rect()), "中文正文在对白安全区：%s" % size)
			expect(dialogue_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "对白面板不会截断点击快进")
		var ending: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cases/night_patrol.json"))
		for node in ending.nodes.values():
			var paragraph := TextParagraph.new()
			paragraph.width = dialog._text_label.size.x
			paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
			paragraph.add_string(str(node.get("text", "")), dialog._text_label.get_theme_font("font"), dialog._text_label.get_theme_font_size("font_size"))
			var height: float = paragraph.get_size().y + maxf(0.0, paragraph.get_line_count() - 1) * 8
			expect(height <= dialog._text_label.size.y, "结局最长三行正文完整容纳，不压继续提示")
		dialog._active = true
		dialog._show_choices([{"text": "送行，让执念在今夜止息。", "next": "sendoff"}, {"text": "镇守，留下继续查明真相。", "next": "hold"}])
		for choice in dialog._choices_box.get_children():
			expect(choice.has_theme_stylebox_override("focus") and choice.has_theme_stylebox_override("disabled"), "对白选项共享完整五态")
			expect(root.get_visible_rect().encloses(choice.get_global_rect()), "选项不出画布：%s" % size)
		dialog.abort(); dialog.free(); stage.free()
	var party := Party.new()
	root.add_child(party)
	party.open(null)
	for child in party._canvas.get_children():
		if child is Panel: expect(child.get_theme_stylebox("panel") is StyleBoxTexture, "整备面板使用批准的分层生图纹理")
	expect(party._hud.count.get_theme_color("font_color") != Kit.color("ink_900"), "整备次要文字避免深底深字")
	party.free()
	await _test_actual_focus()
	await _test_battle_readability()
	await _test_battle_exit_focus()
	print("CAMPAIGN_UI_POLISH_ASSERTIONS:", assertions, " FAILURES:", failures.size())
	quit(0 if failures.is_empty() else 1)

func _test_battle_readability() -> void:
	var catalog := RpgCatalog.new()
	catalog.load_all()
	for enemy_count in [2, 4]:
		var actors := {"p_swordsman": F.actor("swordsman", "p_swordsman"), "p_guard": F.actor("guard", "p_guard"), "p_healer": F.actor("healer", "p_healer")}
		for index in enemy_count: actors["e_%d" % index] = F.enemy("hound", "e_%d" % index)
		var engine := Battle.new(catalog)
		engine.start({"actors": actors, "inventory": {}}, 1701)
		var view := BattleView.new()
		view.bind(engine, null)
		root.add_child(view)
		for frame in 3: await process_frame
		for id in view._actors:
			var row: Dictionary = view._actors[id]
			expect(row.hpbar.size.y <= 10 and row.hpbar.get_combined_minimum_size().y <= 10, "HP条实际尺寸不被StyleBox边距撑高：%s size=%s min=%s" % [id, row.hpbar.size, row.hpbar.get_combined_minimum_size()])
			expect(not row.hpbar.get_rect().intersects(row.mp.get_rect()), "HP条与MP文字互不遮挡：" + id)
			expect(not row.status.get_v_scroll_bar().visible, "常态两行状态不出现无意义滚动条：" + id)
			if id.begins_with("e_"):
				expect(row.card.size.y <= 164, "敌方状态卡高度紧凑：" + id)
				var head: float = row.sprite.position.y - float(row.sprite.get_meta("content_height"))
				expect(row.card.get_rect().end.y <= head - 8, "敌方资料与人物头部留空：" + id)
		view.free()

func _test_actual_focus() -> void:
	var title: Node3D = load("res://scenes/campaign/title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	expect(title.get_node_or_null("TitleAtmosphere/TitleMountainGround") != null and title.get_node_or_null("TitleAtmosphere/TitleForestFog") != null, "真实标题挂载轻量山林与雾，替换露底的小景片")
	expect(title._buttons[0].focus_mode == Control.FOCUS_ALL and title._buttons[0].has_focus(), "正式标题主动作取得实际键盘焦点")
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	root.push_input(tab, true)
	await process_frame
	expect(title._buttons[1].has_focus(), "正式标题实际Tab移动到继续游戏")
	tab.pressed = false
	root.push_input(tab, true)
	title._confirm_replace()
	await process_frame
	var kept: Button
	for child in title._replace_panel.get_children():
		if child is Button and child.text == "保留存档": kept = child
	expect(kept != null and kept.focus_mode == Control.FOCUS_ALL and kept.has_focus(), "替换存档确认框默认聚焦保留，不误选覆盖")
	if kept != null and kept.has_focus():
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.pressed = true
		root.push_input(enter, true)
		enter.pressed = false
		root.push_input(enter, true)
		await process_frame
		expect(not is_instance_valid(title._replace_panel), "正式模态Enter实际选择保留并关闭")
	title.free()

	var stage := Stage.new()
	root.add_child(stage)
	stage.set_process(false)
	var calls := [0]
	Input.action_press("approach_interact")
	stage._show_modal("键盘确认检查", "等待释放调查键，然后确认。", [{"text": "确认", "call": func(): calls[0] += 1}, {"text": "取消", "call": Callable()}])
	stage._process(0.0)
	expect(stage._modal_buttons[0].disabled, "舞台模态仍需先释放E才可确认")
	Input.action_release("approach_interact")
	stage._process(0.0)
	expect(stage._modal_buttons[0].focus_mode == Control.FOCUS_ALL and stage._modal_buttons[0].has_focus(), "舞台模态释放后真实聚焦首个操作")
	var confirm := InputEventKey.new()
	confirm.keycode = KEY_ENTER
	confirm.pressed = true
	root.push_input(confirm, true)
	confirm.pressed = false
	root.push_input(confirm, true)
	stage._modal_buttons[0].pressed.emit()
	expect(calls[0] == 1, "舞台模态真实Enter提交一次，紧接重复信号受arming保护")
	stage.player = load("res://scripts/exploration_3d/player_controller.gd").new()
	stage.add_child(stage.player)
	stage.ready_for_play = true
	stage._mode = "explore"
	stage._open_map()
	expect(stage._modal_buttons[0].focus_mode == Control.FOCUS_ALL, "地图返回按钮允许真实键盘焦点，避免每帧尝试不可聚焦控件")
	stage.free()

func _test_battle_exit_focus() -> void:
	var session: RefCounted = load("res://scripts/campaign/chapter_session.gd").new()
	expect(session.start_new(true).ok, "战斗确认框使用真实隔离主线")
	expect((await session.prepare_assets()).ok, "战斗确认框真实素材会话")
	for event in ["dialogue:a1", "dialogue:r1", "dialogue:h1"]: session.commit_event(session.campaign.safe_snapshot().world, event)
	expect(session.begin_encounter(session.campaign.safe_snapshot().world, "basin_reflection").ok, "真实登记主线遭遇")
	var view := BattleView.new()
	view.router = session.router
	root.add_child(view)
	await process_frame
	view._skill_buttons[0].grab_focus()
	var previous: Control = root.gui_get_focus_owner()
	view._return_title()
	var buttons: Array[Button] = []
	for child in view._exit_confirmation.get_children():
		if child is Button: buttons.append(child)
	expect(buttons.size() == 2 and buttons[1].has_focus(), "战斗返回标题确认默认聚焦取消")
	if buttons.size() == 2:
		var tab := InputEventKey.new()
		tab.keycode = KEY_TAB
		tab.pressed = true
		for index in 4:
			root.push_input(tab, true)
			expect(root.gui_get_focus_owner() in buttons, "战斗确认Tab只在本框两按钮间循环")
			tab.pressed = false; root.push_input(tab, true); tab.pressed = true
		var down := InputEventKey.new()
		down.keycode = KEY_DOWN
		for repeat in 2:
			down.pressed = true; root.push_input(down, true)
			down.pressed = false; root.push_input(down, true)
			expect(root.gui_get_focus_owner() in buttons, "战斗确认向下方向键不能进入遮罩后的技能")
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.pressed = true; root.push_input(enter, true)
		enter.pressed = false; root.push_input(enter, true)
		await process_frame
		expect(view.pending_command.is_empty(), "确认框内方向键加Enter不能选择背景普攻")
		expect(not is_instance_valid(view._exit_confirmation), "两次向下回到取消，Enter关闭当前确认框")
		view._cancel_return_title()
		expect(root.gui_get_focus_owner() == previous, "取消返回标题恢复战斗原焦点")
		view._return_title()
		buttons.clear()
		for child in view._exit_confirmation.get_children():
			if child is Button: buttons.append(child)
		for key in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			var direction := InputEventKey.new()
			direction.keycode = key
			for repeat in 2:
				direction.pressed = true; root.push_input(direction, true)
				direction.pressed = false; root.push_input(direction, true)
				expect(root.gui_get_focus_owner() in buttons, "返回确认四方向焦点均局限本模态")
		view._cancel_return_title()
	view.free(); session.close()
