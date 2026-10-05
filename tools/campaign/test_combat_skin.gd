# 战斗生图皮肤、真实字体留白及输入回归；仅从隔离入口运行。
extends SceneTree
const F = preload("res://tools/rpg/fixtures.gd")
const BattleEngine = preload("res://scripts/rpg/battle_engine.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const View = preload("res://scripts/rpg/ui/battle_view.gd")
const Status = preload("res://scripts/rpg/status_rules.gd")
const Policy = preload("res://scripts/rpg/enemy_policy.gd")
const Art = preload("res://scripts/campaign/presentation/night_menu_art.gd")
var assertions := 0
var failures: Array[String] = []
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func expect(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); printerr("FAIL: ", message)
func _run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	for count in [2, 4]:
		var view := _view(count)
		root.add_child(view)
		for frame in 3: await process_frame
		for size in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(1180, 812)]:
			root.size = size
			await process_frame
			for button in view._skill_buttons + view._basic_buttons.values() + [view._hud.confirm, view._hud.cancel, view._hud.form]:
				_check_button(button)
			for panel in [view._preview_panel, view._items, view._log_panel]:
				expect(panel.get_theme_stylebox("panel") is StyleBoxTexture, "战斗浮层采用批准生图纹理")
			_check_visible_text(view._canvas)
			for widgets in view._actors.values():
				expect(widgets.card.get_theme_stylebox("panel") is StyleBoxTexture, "角色状态卡采用生图内框")
				expect(widgets.hpbar is TextureProgressBar, "HP读数使用生成条槽且仍绑定真实模型")
				for key in ["title", "hp", "mp", "status"]:
					var control: Control = widgets[key]
					expect(Rect2(Vector2(24, 20), widgets.card.size - Vector2(48, 40)).encloses(control.get_rect()), "状态文字位于装饰内缘的阅读区：" + key)
				if widgets.intent != null:
					expect(root.get_visible_rect().encloses(widgets.intent.get_global_rect()), "敌方意图留在画布")
					expect(widgets.card.get_rect().end.y <= widgets.sprite.position.y - float(widgets.sprite.get_meta("content_height")) - 8, "敌方信息框与真实头顶至少8像素间隙")
					for label in view._canvas.get_children():
						if label is Label and label != widgets.intent and label.is_visible_in_tree():
							expect(not label.get_rect().intersects(widgets.intent.get_rect()), "真实敌人意图不能与战斗标题或操作提示叠字：" + label.text)
		view.select_command("attack_physical")
		var options: Dictionary = view.command_options("attack_physical")
		if not options.targets.is_empty(): view.select_target(options.targets[0])
		expect(view.current_preview().legal, "目标选择仍由模型合法预览驱动")
		var before: Dictionary = view.engine.snapshot()
		view.cancel_command()
		expect(view.pending_command.is_empty() and view.engine.snapshot() == before, "取消保持模型、库存与轮次")
		view._basic_pressed("item")
		expect(view._items.visible, "道具列表可打开")
		expect(view._hud.item_healing_potion.position.y < view._hud.item_mana_potion.position.y and view._hud.item_mana_potion.position.y < view._hud.item_revival_potion.position.y and view._hud.item_revival_potion.position.y < view._hud.item_cleansing_powder.position.y, "战斗道具沿用背包治疗、魔力、复苏、净化顺序")
		_check_visible_text(view._canvas)
		for id in view._catalog.get_ids("items"): _check_button(view._hud["item_" + id])
		await _check_focus_inside(view._items, "道具列表")
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE; escape.pressed = true
		view._unhandled_key_input(escape)
		expect(not view._items.visible, "Esc能关闭道具列表")
		view._toggle_log()
		for index in 80: view._log_lines.append("第 %d 条：目标受到伤害，状态与数值保留。" % index)
		view._render()
		for frame in 3: await process_frame
		expect(view._hud.log.scroll_active and view._hud.log.get_v_scroll_bar().visible, "80条日志提供可用滚动区")
		await _check_focus_inside(view._log_panel, "日志")
		view._unhandled_key_input(escape)
		expect(not view._log_panel.visible, "Esc先关闭日志而非触发背后操作")
		var tactical: Dictionary = view.engine.snapshot()
		Status.apply(tactical.actors.e_0, F.status("mark", 1, 2, "p_swordsman"))
		Status.apply(tactical.actors.e_0, F.status("weaken", 0.1, 3, "p_swordsman"))
		Status.apply(tactical.actors.e_0, F.status("slow", 0.3, 2, "p_swordsman"))
		tactical.actors.e_0.intent = {}
		view.engine.restore(tactical); view._render()
		expect(view._actors.e_0.status.text.contains("猎物标记") and not view._actors.e_0.status.text.begins_with("盾 0"), "敌方有状态时首行先读真实状态，零盾不能挤走战术信息")
		expect(view._actors.e_0.status.tooltip_text.contains("盾 0") and view._actors.e_0.status.tooltip_text.contains("2次行动"), "状态全文悬停保留盾值与持续时长")
		expect(view._actors.e_0.intent.text == "意图待定", "活着但尚无意图的敌人不能标为倒地")
		var status_control: RichTextLabel = view._actors.e_0.status
		expect(status_control.get_theme_font("normal_font").get_string_size(status_control.text.split("\n")[0], HORIZONTAL_ALIGNMENT_LEFT, -1, status_control.get_theme_font_size("normal_font_size")).x <= status_control.size.x - 16, "敌方首行状态名摘要不换行或挤入滚动条")
		var fallen: Dictionary = view.engine.snapshot()
		fallen.actors.p_guard.hp = 0
		view.engine.restore(fallen); view._render()
		var downed: Label = view._actors.p_guard.title
		expect(downed.get_theme_font("font").get_string_size(downed.text, HORIZONTAL_ALIGNMENT_LEFT, -1, downed.get_theme_font_size("font_size")).x <= downed.size.x, "友方姓名与倒地标记不得被头像挤掉")
		var ending: Dictionary = view.engine.snapshot()
		ending.outcome = "defeat"; ending.phase = "outcome"; ending.active_actor_id = ""; ending.slot_token = {}; ending.queue_index = mini(ending.queue_index + 1, ending.queue.size())
		view.engine.restore(ending); expect(view.engine.last_errors.is_empty(), "终局夹具经真实模型校验"); view._render(); view._check_result()
		expect(view._result.visible and view._hud.result_body is RichTextLabel, "战果全文具有可滚动阅读区")
		_check_visible_text(view._canvas)
		await _check_focus_inside(view._result, "战果")
		view.free()
	var catalog := Catalog.new(); catalog.load_all()
	for class_id in Catalog.CLASS_IDS:
		var actor := F.actor(class_id, "p_active")
		actor.stats.spd = 999
		var engine := BattleEngine.new(catalog)
		engine.start({"actors": {"p_active": actor, "e_1": F.enemy("hound", "e_1")}, "inventory": {}}, 7)
		var view := View.new(); view.bind(engine, null)
		root.add_child(view)
		await process_frame
		for button in view._skill_buttons:
			_check_button(button)
			expect(button.get_theme_font_size("font_size") >= 20, "六职业技能在原画布保持20像素及以上")
		view.free()
	print("CAMPAIGN_COMBAT_SKIN_ASSERTIONS:", assertions, " FAILURES:", failures.size())
	quit(0 if failures.is_empty() else 1)
func _view(count: int) -> Control:
	var catalog := Catalog.new(); catalog.load_all()
	var actors := {"p_swordsman": F.actor("swordsman", "p_swordsman"), "p_guard": F.actor("guard", "p_guard"), "p_healer": F.actor("healer", "p_healer")}
	actors.p_swordsman.stats.spd = 999
	for index in count: actors["e_%d" % index] = F.enemy("hound", "e_%d" % index)
	var engine := BattleEngine.new(catalog)
	engine.set_policy(Policy.new())
	engine.start({"actors": actors, "inventory": {"healing_potion": 3, "mana_potion": 1, "revival_potion": 1, "cleansing_powder": 1}}, 1701)
	var view := View.new(); view.bind(engine, null)
	return view
func _check_button(button: Button) -> void:
	if not button.visible: return
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style: StyleBox = button.get_theme_stylebox(state)
		expect(style is StyleBoxTexture, "指令五态使用生图纹理：" + state)
		expect(style.content_margin_left >= 30 and style.content_margin_right >= 30 and style.content_margin_top >= 28 and style.content_margin_bottom >= 28, "指令文字在金色内框内另有20像素留白")
	var text_size := Vector2.ZERO
	for line in button.text.split("\n"):
		var measured: Vector2 = button.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size"))
		text_size.x = maxf(text_size.x, measured.x)
		text_size.y += measured.y
	expect(text_size.x <= button.size.x - 68, "真实字形宽度不触碰金边：" + button.text)
	expect(text_size.y <= button.size.y - 56, "多行技能真实行高保留上下金边留白：" + button.text)
	expect(button.size.y >= 72, "单行控制至少72像素高")
	expect(root.get_visible_rect().encloses(button.get_global_rect()), "指令仍在实际窗口内")

func _check_focus_inside(panel: Control, label: String) -> void:
	for repeat in 6:
		var key := InputEventKey.new(); key.keycode = KEY_TAB; key.pressed = true
		root.push_input(key, true)
		key.pressed = false; root.push_input(key, true)
		await process_frame
		expect(root.gui_get_focus_owner() != null and panel.is_ancestor_of(root.gui_get_focus_owner()), label + "键盘焦点不落到背后命令")

func _check_visible_text(node: Node) -> void:
	if node is Control and not node.is_visible_in_tree(): return
	if node is Label or node is RichTextLabel:
		expect(root.get_visible_rect().encloses(node.get_global_rect()), "可见文字不超出实际视口：" + node.text)
	for child in node.get_children(): _check_visible_text(child)
