# 角色旁和纸命令：真实 BattleView/Engine 与 Godot GUI 输入事件回归。
# root.push_input 是引擎事件自动化，不代表实体键鼠或手柄实操。
extends SceneTree

const F = preload("res://tools/rpg/fixtures.gd")
const Battle = preload("res://scripts/rpg/battle_engine.gd")
const View = preload("res://scripts/rpg/ui/battle_view.gd")
const Factory = preload("res://scripts/rpg/actor_factory.gd")

var assertions := 0
var failures: Array[String] = []

func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1":
		printerr("FAIL: 请经隔离 Python 入口执行角色旁命令测试")
		quit(2)
		return
	_run.call_deferred()

func expect(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		printerr("ASSERT FAIL: ", message)

func _run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.size = Vector2i(1920, 1080)
	# 先动态检查新接口；原版必须是明确断言红灯，不能因不存在的新类解析失败。
	var probe = View.new()
	var contract_ok: bool = probe.has_method("command_ui_state")
	expect(contract_ok, "缺少角色旁和纸命令接口 command_ui_state（预期原版红灯）")
	probe.free()
	if not contract_ok:
		_finish()
		return
	await _test_free_cancel_and_focus()
	await _test_disabled_mp()
	await _test_four_skills_and_cd()
	await _test_actual_skill_text()
	await _test_invalidated_target()
	await _test_resize_and_frozen_anchor()
	await _test_joypad_focus()
	await _test_form_shortcuts()
	await _test_same_actor_next_turn_and_popup_restore()
	await _test_duplicate_confirm()
	_finish()

func _finish() -> void:
	print("ACTOR_COMMAND_UI: %d assertions, %d failures" % [assertions, failures.size()])
	print("ACTOR_COMMAND_UI_INPUT: Godot GUI injected events; OS hardware input not tested")
	quit(0 if failures.is_empty() else 1)

func _make_fixture(low_mp: bool = false, on_cooldown: bool = false, source_class: String = "swordsman") -> Dictionary:
	var actors := {
		"p_swordsman": F.actor(source_class, "p_swordsman"),
		"p_guard": F.actor("guard", "p_guard"),
		"p_healer": F.actor("healer", "p_healer"),
		"e_1": F.enemy("hound", "e_1"),
		"e_2": F.enemy("cultist", "e_2"),
	}
	actors.p_swordsman.stats.spd = 999
	if low_mp: actors.p_swordsman.mp = 0
	var engine = Battle.new()
	var started: Dictionary = engine.start({"actors": actors, "inventory": {"healing_potion": 3}}, 1701)
	expect(bool(started.get("started", false)), "真实三人两敌战斗模型可建立")
	expect(engine.last_errors.is_empty(), "真实夹具start通过状态校验：" + str(engine.last_errors))
	if on_cooldown:
		# heavy_slash原始CD为0；用真实CD2的战意，不伪造计数或更改规则。
		engine.advance(false)
		var cast_before: Dictionary = engine.snapshot()
		var applied := _submit_fixture(engine, "skill", "battle_spirit")
		expect(bool(applied.get("accepted", false)) and engine.last_errors.is_empty(), "真实战意提交产生合法冷却：" + str(applied.get("reasons", [])))
		expect(engine.snapshot().actors.p_swordsman.mp == cast_before.actors.p_swordsman.mp - 6, "CD夹具真实战意只消耗既定6MP")
		_advance_back_to_source(engine, int(cast_before.actors.p_swordsman.slot_count))
		var cooling: Dictionary = engine.snapshot()
		expect(int(cooling.actors.p_swordsman.cooldown_until.get("battle_spirit", 0)) > int(cooling.actors.p_swordsman.slot_count), "真实下次行动仍在战意CD内，比较演员自己的slot_count")
	var view = View.new()
	view.bind(engine, null)
	root.add_child(view)
	for frame in 3: await process_frame
	expect(engine.snapshot().active_actor_id == "p_swordsman", "夹具真实行动者为凛音")
	return {"view": view, "engine": engine}

func _submit_fixture(engine, kind: String, ability_id: String = "") -> Dictionary:
	var state: Dictionary = engine.snapshot()
	return engine.submit({"command_id": "fixture_%d" % int(state.revision), "expected_revision": int(state.revision), "actor_id": str(state.active_actor_id), "kind": kind, "ability_id": ability_id, "target_ids": []})

func _advance_back_to_source(engine, previous_slot: int) -> void:
	var returned := false
	for safety in 20:
		engine.advance(false)
		var state: Dictionary = engine.snapshot()
		if state.get("phase") == "action_selection" and state.get("active_actor_id") == "p_swordsman" and int(state.actors.p_swordsman.slot_count) > previous_slot:
			returned = true
			break
		if state.get("phase") != "action_selection" or not str(state.get("outcome", "")).is_empty():
			expect(false, "循环真实防御时战斗保持合法进行中")
			break
		var defended := _submit_fixture(engine, "defend")
		expect(bool(defended.get("accepted", false)) and engine.last_errors.is_empty(), "其他玩家/敌人真实防御推进：" + str(defended.get("reasons", [])))
		if not bool(defended.get("accepted", false)): break
	expect(returned and engine.last_errors.is_empty(), "真实advance回到凛音下一行动槽且无状态错误")

func _state(view: Object) -> Dictionary:
	var value = view.call("command_ui_state")
	if value is Dictionary: return value
	expect(false, "command_ui_state 必须返回 Dictionary")
	return {}

func _has_property(object: Object, property_name: String) -> bool:
	for item in object.get_property_list():
		if str(item.name) == property_name: return true
	return false

func _menu(view: Object) -> Control:
	if not _has_property(view, "_command_menu"):
		expect(false, "正式 BattleView 必须拥有真实命令控件 _command_menu")
		return null
	var value = view.get("_command_menu")
	if value is Control: return value
	expect(false, "_command_menu 必须是 Control")
	return null

func _find_button(scope: Node, key: String, text: String = "") -> Button:
	if scope == null: return null
	for candidate in scope.find_children("*", "Button", true, false):
		var button := candidate as Button
		if not button.is_visible_in_tree(): continue
		var named := str(button.name) == key
		for meta_key in ["key", "command_key", "action_key"]:
			named = named or str(button.get_meta(meta_key, "")) == key
		if named or (not text.is_empty() and button.text == text): return button
	return null

func _button(view: Object, key: String, text: String = "") -> Button:
	var button := _find_button(_menu(view), key, text)
	expect(button != null, "可见真实命令按钮存在：" + key)
	return button

func _key(code: Key, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func _click(button: Button) -> void:
	if button == null: return
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = motion.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func _skill_buttons(view: Object) -> Array[Button]:
	var result: Array[Button] = []
	var menu := _menu(view)
	if menu == null: return result
	for candidate in menu.find_children("*", "Button", true, false):
		var button := candidate as Button
		if not button.is_visible_in_tree(): continue
		for meta_key in ["key", "command_key", "action_key"]:
			if str(button.get_meta(meta_key, "")).begins_with("skill:"):
				result.append(button)
				break
	return result

func _joy_button(code: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = code
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func _focus_is_inside(menu: Control) -> bool:
	var focused := root.gui_get_focus_owner()
	return focused != null and menu.is_ancestor_of(focused) and focused.is_visible_in_tree() and (not focused is BaseButton or not focused.disabled)

func _leaf_label(button: Button, label_name: String) -> Label:
	var label := button.get_node_or_null(NodePath(label_name)) as Label
	expect(label != null, "技能按钮具有真实文本标签：" + label_name)
	return label

func _check_leaf_text(button: Button, context: String) -> void:
	var occupied: Array[Rect2] = []
	for label_name in ["Title", "Resource", "Detail", "Reason"]:
		var label := _leaf_label(button, label_name)
		if label == null: continue
		if label_name in ["Title", "Resource"]:
			expect(label.is_visible_in_tree() and not label.text.strip_edges().is_empty(), context + "的" + label_name + "实际可见且非空")
		if label_name == "Reason" and button.disabled:
			expect(label.is_visible_in_tree() and not label.text.strip_edges().is_empty(), context + "禁用原因是实际可见的文本，不依赖tooltip")
		if not label.is_visible_in_tree() or label.text.is_empty(): continue
		var font := label.get_theme_font("font")
		var font_size := label.get_theme_font_size("font_size")
		expect(font_size >= (27 if label_name == "Title" else 24), context + "不通过缩小" + label_name + "字体挤入卡片")
		expect(Rect2(Vector2.ZERO, button.size).encloses(label.get_rect()), context + "的" + label_name + "真实矩形在按钮纸面内")
		for previous in occupied:
			expect(not previous.intersects(label.get_rect()), context + "的可见文本标签互不覆盖：" + label_name)
		occupied.append(label.get_rect())
		# Label本身的line_count由生产字体和真实控件宽度完成换行；不测空Button.text。
		var line_count := label.get_line_count()
		var line_spacing := label.get_theme_constant("line_spacing")
		var wrapped_height := float(line_count) * font.get_height(font_size) + float(maxi(0, line_count - 1)) * line_spacing
		expect(line_count > 0 and wrapped_height <= label.size.y + 1.0, context + "的" + label_name + "实际换行高度可完整容纳：" + label.text)
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF and label.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
			for line in label.text.split("\n"):
				expect(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= label.size.x + 1.0, context + "的" + label_name + "未换行文本不越阅读宽度")

func _test_free_cancel_and_focus() -> void:
	var fixture := await _make_fixture()
	var view = fixture.view
	var before: Dictionary = fixture.engine.snapshot()
	var menu := _menu(view)
	if menu == null:
		view.free()
		return
	var initial := _state(view)
	expect(str(initial.get("actor_id", "")) == "p_swordsman", "命令菜单锚定真实当前角色")
	var skills := _button(view, "skills", "技能")
	if skills == null:
		view.free()
		return
	expect(skills.has_focus(), "初始实际焦点位于技能按钮")
	await _key(KEY_ENTER)
	var skill_page := _state(view)
	expect(str(skill_page.get("page", "")) != str(initial.get("page", "")), "Enter通过真实按钮进入技能页")
	expect(_skill_buttons(view).size() == 4, "技能页保留四个真实技能按钮")
	await _click(_button(view, "skill:heavy_slash"))
	var selected: Dictionary = view.get("pending_command")
	expect(selected.get("kind", "") == "skill" and selected.get("ability_id", "") == "heavy_slash", "真实技能按钮建立原六字段命令")
	expect(selected.size() == 6, "新菜单不向模型命令添加界面字段")
	await _key(KEY_ESCAPE)
	expect(_state(view).get("page") == skill_page.get("page"), "第一次Esc从目标层只回技能页")
	expect(fixture.engine.snapshot() == before, "取消目标不收费、不改轮次和RNG")
	await _key(KEY_ESCAPE)
	expect(_state(view).get("page") == initial.get("page"), "第二次Esc只回角色命令根页")
	var restored := _button(view, "skills", "技能")
	expect(restored != null and restored.has_focus(), "逐层取消恢复原技能入口实际焦点")
	await _key(KEY_ESCAPE)
	expect(fixture.engine.snapshot() == before and not view.get("processing"), "根页再次取消不提交、不推进战斗")
	view.free()

func _test_disabled_mp() -> void:
	var fixture := await _make_fixture(true)
	var view = fixture.view
	var before: Dictionary = fixture.engine.snapshot()
	await _click(_button(view, "skills", "技能"))
	var buttons := _skill_buttons(view)
	expect(buttons.size() == 4, "MP不足时仍保留四个技能位")
	var heavy := _button(view, "skill:heavy_slash")
	if heavy != null:
		expect(heavy.disabled, "真实重斩按钮因模型MP不足禁用")
		var reason := _leaf_label(heavy, "Reason")
		expect(reason != null and reason.is_visible_in_tree() and reason.text.contains("MP不足"), "MP不足原因常显于Reason，不依赖悬停")
		_check_leaf_text(heavy, "MP不足重斩")
		await _click(heavy)
		expect(fixture.engine.snapshot() == before, "鼠标点击禁用技能不改模型或资源")
	view.free()

func _test_four_skills_and_cd() -> void:
	var fixture := await _make_fixture(false, true)
	var view = fixture.view
	var before: Dictionary = fixture.engine.snapshot()
	await _click(_button(view, "skills", "技能"))
	var buttons := _skill_buttons(view)
	expect(buttons.size() == 4, "CD状态仍呈现四个真实技能位")
	for skill_id in before.actors.p_swordsman.skill_ids:
		expect(_button(view, "skill:" + str(skill_id)) != null, "每个技能按钮对应当前演员真实skill_id")
	var cooling := _button(view, "skill:battle_spirit")
	if cooling != null:
		expect(cooling.disabled, "真实下槽战意冷却由模型状态禁用")
		var reason := _leaf_label(cooling, "Reason")
		expect(reason != null and reason.is_visible_in_tree() and (reason.text.contains("CD") or reason.text.contains("冷却")), "CD禁用原因在Reason常显，无需悬停")
		_check_leaf_text(cooling, "真实CD战意")
		await _click(cooling)
		expect(fixture.engine.snapshot() == before, "禁用CD技能的实际鼠标输入不提交模型")
	var menu := _menu(view)
	if menu != null:
		for repeat in 8:
			await _key(KEY_TAB)
			expect(_focus_is_inside(menu), "技能页Tab焦点留在可见且可用的真实控件")
		for code in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			await _key(code)
			expect(_focus_is_inside(menu), "技能页方向键焦点不进入禁用卡或背景")
		await _key(KEY_TAB, true)
		expect(_focus_is_inside(menu), "Shift+Tab同样限制在当前页真实操作")
	view.free()

func _test_actual_skill_text() -> void:
	for class_id in ["swordsman", "guard", "healer", "ranger", "mage", "controller"]:
		var fixture := await _make_fixture(false, false, class_id)
		var view = fixture.view
		await _click(_button(view, "skills", "技能"))
		var buttons := _skill_buttons(view)
		expect(buttons.size() == 4, class_id + "真实职业完整四技能文案")
		for button in buttons:
			_check_leaf_text(button, class_id + "/" + str(button.get_meta("command_key", "")))
		view.free()

func _test_invalidated_target() -> void:
	var fixture := await _make_fixture()
	var view = fixture.view
	await _click(_button(view, "skills", "技能"))
	await _click(_button(view, "skill:heavy_slash"))
	var actors: Dictionary = view.get("_actors")
	await _click(actors.e_1.target)
	var confirm := _button(view, "confirm", "确认")
	if confirm == null:
		view.free()
		return
	var old_confirm_position := confirm.get_global_rect().get_center()
	var changed: Dictionary = fixture.engine.snapshot()
	changed.actors.e_1.hp = 0
	fixture.engine.restore(changed)
	expect(fixture.engine.last_errors.is_empty(), "目标倒地夹具经过真实引擎restore校验")
	view.call("_render")
	await process_frame
	var before_retry: Dictionary = fixture.engine.snapshot()
	var preview: Dictionary = view.call("current_preview")
	expect(not bool(preview.get("legal", false)), "已选择目标失效后旧预览不再合法")
	# 点击原确认位置，再按Enter；旧控件即使已重建也不能提交过时目标。
	var click := InputEventMouseButton.new()
	click.position = old_confirm_position; click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	root.push_input(click, true)
	click.pressed = false; root.push_input(click, true)
	await _key(KEY_ENTER)
	expect(fixture.engine.snapshot() == before_retry, "失效目标的旧确认不扣资源、不增command_log、不推进RNG")
	view.free()

func _test_resize_and_frozen_anchor() -> void:
	root.size = Vector2i(1920, 1080)
	var fixture := await _make_fixture()
	var view = fixture.view
	var menu := _menu(view)
	if menu == null:
		view.free()
		return
	var initial := _state(view)
	var initial_rect = initial.get("menu_rect")
	expect(initial_rect is Rect2, "公开UI状态提供Rect2菜单位置")
	var anchor = initial.get("anchor_rect")
	expect(anchor is Rect2, "公开UI状态提供冻结的演员anchor_rect")
	for frame in 6: await process_frame
	if initial_rect is Rect2 and _state(view).get("menu_rect") is Rect2:
		expect(initial_rect.position.is_equal_approx(_state(view).menu_rect.position), "同页idle期间菜单位置固定不随待机动画抖动")
	await _click(_button(view, "skills", "技能"))
	var skills_state := _state(view)
	if anchor is Rect2 and skills_state.get("anchor_rect") is Rect2:
		expect(anchor.is_equal_approx(skills_state.anchor_rect), "不同大小页面可clamp，但角色冻结锚点不随翻页改变")
	await _click(_button(view, "skill:heavy_slash"))
	var target_state := _state(view)
	if anchor is Rect2 and target_state.get("anchor_rect") is Rect2:
		expect(anchor.is_equal_approx(target_state.anchor_rect), "目标选择沿用打开时的冻结演员锚点")
	for window_size in [Vector2i(1280, 720), Vector2i(1180, 812), Vector2i(960, 720), Vector2i(1920, 1080)]:
		root.size = window_size
		for frame in 2: await process_frame
		expect(root.get_visible_rect().encloses(menu.get_global_rect()), "resize后菜单实际屏幕范围内：" + str(window_size))
		expect(str(_state(view).get("actor_id", "")) == "p_swordsman", "resize保持同一命令角色而非重选目标")
		for candidate in menu.find_children("*", "Button", true, false):
			var button := candidate as Button
			if button.is_visible_in_tree():
				expect(root.get_visible_rect().encloses(button.get_global_rect()), "resize后真实按钮热区留在视口：" + button.text)
	view.free()

func _test_joypad_focus() -> void:
	root.size = Vector2i(1920, 1080)
	var fixture := await _make_fixture()
	var view = fixture.view
	var menu := _menu(view)
	if menu == null:
		view.free()
		return
	var before: Dictionary = fixture.engine.snapshot()
	var initial := _state(view)
	var skills := _button(view, "skills", "技能")
	expect(skills != null and skills.has_focus(), "手柄场景初始真实焦点在技能入口")
	await _joy_button(JOY_BUTTON_A)
	expect(_state(view).get("page") != initial.get("page") and _skill_buttons(view).size() == 4, "手柄A经真实GUI按钮进入技能页")
	await _joy_button(JOY_BUTTON_B)
	expect(_state(view).get("page") == initial.get("page"), "手柄B执行与Esc一致的逐层返回")
	expect(_focus_is_inside(menu), "手柄返回后焦点没有落到背景目标")
	var previous := root.gui_get_focus_owner()
	await _joy_button(JOY_BUTTON_DPAD_DOWN)
	expect(_focus_is_inside(menu) and root.gui_get_focus_owner() != previous, "手柄D-pad移动真实按钮焦点")
	var motion := InputEventJoypadMotion.new()
	motion.device = 0; motion.axis = JOY_AXIS_LEFT_Y; motion.axis_value = -1.0
	root.push_input(motion, true)
	await process_frame
	motion.axis_value = 0.0; root.push_input(motion, true)
	await process_frame
	expect(_focus_is_inside(menu), "摇杆越阈值后归零，焦点仍在命令菜单")
	expect(fixture.engine.snapshot() == before, "手柄导航与取消完全免费")
	view.free()

func _test_same_actor_next_turn_and_popup_restore() -> void:
	var fixture := await _make_fixture()
	var view = fixture.view
	var engine = fixture.engine
	var menu := _menu(view)
	if menu == null:
		view.free()
		return
	var before: Dictionary = engine.snapshot()
	await _click(_button(view, "skills", "技能"))
	await _click(_button(view, "skill:battle_spirit"))
	await _click(_button(view, "confirm", "确认"))
	expect(engine.snapshot().command_log.size() == before.command_log.size() + 1, "同角色下回合夹具先通过真实GUI完成一条自施术式")
	# 其余单位的真实防御仅准备下一槽模型；来源提交与最终菜单恢复均走生产视图。
	_advance_back_to_source(engine, int(before.actors.p_swordsman.slot_count))
	for safety in 120:
		await process_frame
		if not bool(view.get("processing")): break
	expect(not bool(view.get("processing")), "生产表现完成后解除菜单输入锁")
	expect(_state(view).get("actor_id") == "p_swordsman" and _state(view).get("page") == "commands", "同一actor_id进入下一行动槽时重新回commands，不残留target页")
	expect(menu.visible and _focus_is_inside(menu), "同一角色新行动槽菜单恢复且具有实际焦点")
	var stable: Dictionary = engine.snapshot()
	await _click(_button(view, "skills", "技能"))
	var enabled_leaves: Array[Button] = []
	for leaf in _skill_buttons(view):
		if not leaf.disabled: enabled_leaves.append(leaf)
	expect(enabled_leaves.size() >= 2, "弹层恢复夹具至少有两个合法技能叶")
	if enabled_leaves.size() < 2:
		view.free()
		return
	# 只为本项恢复契约设置非首项焦点；真实Tab/方向导航由独立用例覆盖。
	var previous_leaf := enabled_leaves[1]
	var previous_key := str(previous_leaf.get_meta("command_key", ""))
	previous_leaf.grab_focus()
	expect(previous_leaf.has_focus() and not previous_key.is_empty(), "弹层开启前记录第二个合法技能叶的实际焦点和command_key")
	# 日志开启是夹具准备，关闭由真实Esc分发；不将方法调用称为硬件操作。
	view.call("_toggle_log")
	await process_frame
	expect(not menu.visible, "日志弹层打开时隐藏角色命令菜单")
	await _key(KEY_ESCAPE)
	expect(menu.visible and _focus_is_inside(menu), "Esc关闭日志后菜单重新显示并恢复有效焦点")
	expect(_find_button(menu, previous_key) == previous_leaf and previous_leaf.has_focus(), "日志关闭精确恢复原技能叶，而非首项：" + previous_key)
	await _key(KEY_T)
	expect(not menu.visible, "键盘T打开战术层后命令菜单隐藏")
	await _key(KEY_ESCAPE)
	expect(menu.visible and _focus_is_inside(menu), "Esc关闭战术弹层后恢复角色命令菜单")
	expect(_find_button(menu, previous_key) == previous_leaf and previous_leaf.has_focus(), "战术层关闭精确恢复原技能叶，而非首项：" + previous_key)
	expect(engine.snapshot() == stable, "菜单与弹层恢复不额外消耗资源或推进轮次")
	view.free()

func _test_duplicate_confirm() -> void:
	var fixture := await _make_fixture()
	var view = fixture.view
	var before: Dictionary = fixture.engine.snapshot()
	await _click(_button(view, "skills", "技能"))
	await _click(_button(view, "skill:heavy_slash"))
	# 目标也使用生产真实 Button；不通过 select_target 跳过 GUI 分发。
	var actors: Dictionary = view.get("_actors")
	var target: Button = actors.e_1.target
	await _click(target)
	var confirm := _button(view, "confirm", "确认")
	if confirm != null:
		expect(confirm.has_focus(), "选中目标后实际焦点转到确认")
		expect(not confirm.disabled, "真实目标的模型预览启用确认")
		var chosen: Dictionary = view.get("pending_command").duplicate(true)
		var preview: Dictionary = view.call("current_preview")
		# 同一帧两次Enter按放，确保测试重复输入窗口而非等待动作结束。
		for repeat in 2:
			var event := InputEventKey.new()
			event.keycode = KEY_ENTER; event.physical_keycode = KEY_ENTER; event.pressed = true
			root.push_input(event, true)
			event.pressed = false; root.push_input(event, true)
		await process_frame
		var after: Dictionary = fixture.engine.snapshot()
		expect(after.command_log.size() == before.command_log.size() + 1, "真实按钮连续确认只接纳一条指令")
		expect(after.accepted_commands.has(chosen.get("command_id", "")), "接纳的仍是预览阶段同一个命令ID")
		expect(after.actors.p_swordsman.mp == before.actors.p_swordsman.mp - int(preview.get("mp_cost", 0)), "连续确认只扣一次真实MP")
		var menu := _menu(view)
		expect(menu != null and not menu.visible, "提交processing期间命令菜单隐藏")
	view.free()

func _test_form_shortcuts() -> void:
	var catalog = load("res://scripts/rpg/catalog.gd").new()
	catalog.load_all()
	var actor: Dictionary = Factory.new(catalog).create("mage","p_mage",5,Factory.STANDARD)
	actor.merge({"identity_id":"homura","form_id":"sword","active_class_id":"swordsman","dual_form_version":1,"unlocked_forms":["sword","mage"],"skill_ids":catalog.get_definition("classes","swordsman").skill_ids.duplicate()},true)
	actor.stats.spd = 999
	var engine = Battle.new(catalog)
	var started: Dictionary = engine.start({"actors":{"p_mage":actor,"e_1":F.enemy("hound","e_1")},"inventory":{}},1701)
	expect(bool(started.get("started",false)),"换形输入使用现有双形态协议的合法模型夹具")
	if not started.get("started",false): return
	var view = View.new()
	view.bind(engine,null)
	root.add_child(view)
	for frame in 3: await process_frame
	var before: Dictionary = engine.snapshot()
	expect(view._hud.form.visible and not view._hud.form.disabled,"焰华真实行动显示换形入口与F/Y提示")
	await _key(KEY_F)
	var mage: Dictionary = engine.snapshot()
	expect(mage.actors.p_mage.form_id == "mage","键盘F从菜单内焦点触发现有换形命令")
	expect(mage.actors.p_mage.hp == before.actors.p_mage.hp and mage.actors.p_mage.mp == before.actors.p_mage.mp and mage.actors.p_mage.slot_count == before.actors.p_mage.slot_count,"换形不额外治疗/补蓝/消耗行动")
	await _joy_button(JOY_BUTTON_Y)
	var sword: Dictionary = engine.snapshot()
	expect(sword.actors.p_mage.form_id == "sword","手柄Y从菜单内焦点切回剑形")
	expect(sword.actors.p_mage.slot_count == before.actors.p_mage.slot_count and sword.actors.p_mage.mp == before.actors.p_mage.mp,"手柄换形仍由原模型维护同一行动槽与资源")
	expect(_state(view).get("page") == "commands" and _focus_is_inside(_menu(view)),"换形刷新四技能后恢复角色命令与有效焦点")
	view.free()
