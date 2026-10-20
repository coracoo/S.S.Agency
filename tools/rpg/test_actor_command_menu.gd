# 控件契约草稿：由统一隔离入口执行；本子任务不启动Godot。
extends SceneTree
const Menu = preload("res://scripts/rpg/ui/actor_command_menu.gd")
var failures: Array[String] = []
var emitted: Array[Dictionary] = []

func expect(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()

func _run() -> void:
	var menu = Menu.new()
	root.add_child(menu)
	menu.set_placement(Rect2(40, 100, 480, 560), false)
	menu.command_requested.connect(func(kind: String, ability: String): emitted.append({"kind": kind, "ability": ability}))
	menu.page_requested.connect(func(page: String): emitted.append({"page": page}))
	menu.back_requested.connect(func(): emitted.append({"back": true}))
	menu.confirm_requested.connect(func(): emitted.append({"confirm": true}))
	var model := _model("skills")
	var original := model.duplicate(true)
	menu.present(model)
	await process_frame
	expect(menu.skill_buttons.size() == 4, "固定四个真实技能按钮")
	var stable: Array[int] = []
	for button in menu.skill_buttons: stable.append(button.get_instance_id())
	expect(menu.skill_buttons[0].get_meta("command_key") == "skill:heavy_slash", "真实GUI可按metadata定位技能")
	expect(not menu.skill_buttons[0].disabled, "legal=true即使含免疫提示仍可选")
	expect(menu.skill_buttons[1].disabled, "MP不足按legal禁用")
	expect(_text(menu.skill_buttons[1]).contains("MP不足"), "禁用原因仍常显")
	menu.skill_buttons[1].pressed.emit()
	expect(emitted.is_empty(), "禁用技能即使合成pressed也不发命令")
	expect(_text(menu.skill_buttons[0]).contains("MP 9"), "显示模型提供的真实MP")
	expect(_text(menu.skill_buttons[0]).contains("CD 2"), "显示模型提供的CD文本")
	for button in menu.skill_buttons: _check_leaf_geometry(button)
	menu.skill_buttons[0].pressed.emit()
	expect(emitted.back() == {"kind": "skill", "ability": "heavy_slash"}, "技能只发命令信号")
	menu.present(model)
	for index in 4: expect(menu.skill_buttons[index].get_instance_id() == stable[index], "present不重建技能控件")
	expect(model == original, "present不修改输入模型")
	menu.focus_key("skill:heavy_slash")
	var previous := root.gui_get_focus_owner()
	menu.present(model)
	expect(root.gui_get_focus_owner() == previous, "present不抢焦点")
	model.page = "commands"
	model.basics.erase("attack_magic")
	menu.present(model)
	expect(not menu.basic_buttons.attack_magic.visible, "术法普攻按basics可见")
	var command_size: Vector2 = menu.required_size_for_page("commands", false)
	menu.set_placement(Rect2(Vector2(40, 100), command_size), false)
	var command_controls: Array = menu.enabled_controls()
	expect(command_controls.size() == 4, "四个入口组成两行")
	expect(command_controls[0].position.y == command_controls[1].position.y, "命令浮动首行两列")
	expect(command_controls[2].position.y == command_controls[3].position.y, "命令浮动次行两列")
	expect(command_controls[1].position.y + command_controls[1].size.y < command_controls[2].position.y, "两行命令不重叠")
	model.basics.append("attack_magic")
	menu.present(model)
	expect(menu.required_size_for_page("commands", false).y > command_size.y, "五入口增加第三行")
	var before := emitted.size()
	menu.skill_buttons[0].pressed.emit()
	expect(emitted.size() == before, "隐藏页不能发命令")
	for button in menu.skill_buttons:
		expect(button.focus_mode == Control.FOCUS_NONE, "隐藏技能页退出焦点")
	menu.focus_key("skills")
	expect(root.gui_get_focus_owner() in menu.enabled_controls(), "命令页能恢复技能入口焦点")
	menu.basic_buttons.attack_physical.pressed.emit()
	expect(emitted.back() == {"kind": "attack_physical", "ability": ""}, "物理普攻使用原kind")
	menu.basic_buttons.defend.pressed.emit()
	expect(emitted.back() == {"kind": "defend", "ability": ""}, "防御使用原kind")
	menu.basic_buttons.item.pressed.emit()
	expect(emitted.back() == {"page": "items"}, "道具先打开列表")
	expect(menu.basic_buttons.attack_physical.get_meta("command_key") == "attack_physical", "普通命令保留metadata键")
	model.page = "items"
	menu.present(model)
	expect(menu.enabled_controls().size() == 8, "七项道具和返回均保留")
	menu.focus_key("item:healing_potion")
	var item_button = root.gui_get_focus_owner()
	expect(item_button.get_meta("command_key") == "item:healing_potion", "道具按metadata恢复焦点")
	item_button.pressed.emit()
	expect(emitted.back() == {"kind": "item", "ability": "healing_potion"}, "道具只发选择信号")
	model.page = "target"
	model.target_text = "纸妖·疾行、纸妖·守盾、纸妖·火灵、纸妖·镇守"
	menu.present(model)
	var target_size: Vector2 = menu.required_size_for_page("target",false)
	menu.set_placement(Rect2(Vector2.ZERO,target_size),false)
	var target_line: Label = menu._target_line
	expect(target_line.get_theme_font("font").get_string_size(target_line.text,HORIZONTAL_ALIGNMENT_LEFT,-1,24).x <= target_line.size.x,"多目标名称和费用在确认单行内完整可读")
	model.confirm_legal = false
	menu.present(model)
	before = emitted.size()
	menu.confirm_button.pressed.emit()
	expect(emitted.size() == before, "非法预览不能确认")
	model.confirm_legal = true
	menu.present(model)
	menu.confirm_button.pressed.emit()
	expect(emitted.back() == {"confirm": true}, "显式确认仅发信号")
	menu.back_button.pressed.emit()
	expect(emitted.back() == {"back": true}, "返回仅发信号，层级归控制器")
	model.page = "skills"
	menu.present(model)
	var floating: Vector2 = menu.required_size_for_page("skills", false)
	expect(floating.x == 400, "四技能浮动纸叶采用400宽")
	menu.set_placement(Rect2(Vector2(40, 100), floating), false)
	await process_frame
	var skill_scroll: ScrollContainer = menu.skill_buttons[0].get_parent().get_parent()
	expect(not skill_scroll.get_v_scroll_bar().visible, "浮动四技能首屏完整无需滚动")
	for button in menu.skill_buttons:
		expect(button.position.y + button.size.y <= skill_scroll.size.y, "四技能都落在首屏可见范围")
	var compact: Vector2 = menu.required_size_for_page("skills", true)
	menu.set_placement(Rect2(Vector2(24, 984 - compact.y), compact), true)
	await process_frame
	for button in menu.skill_buttons:
		expect(Rect2(Vector2.ZERO, menu.size).encloses(Rect2(button.position, button.size)), "底部四纸叶在约定范围内")
		_check_leaf_geometry(button)
	model.skills[0].name = "重斩·长中文技能名称必须完整换行且保持二十七号字体"
	model.skills[1].reasons = ["MP不足，当前法力无法支付本次技能的真实消耗", "技能仍在冷却中，等待行动槽推进后才可使用；完整禁用原因必须换行显示，不得缩字或用省略号隐藏"]
	menu.present(model)
	compact = menu.required_size_for_page("skills", true)
	expect(compact.y > Menu.size_for_page("skills", true).y, "完整长文本提高停靠高度")
	menu.set_placement(Rect2(Vector2(24, 984 - compact.y), compact), true)
	await process_frame
	for button in menu.skill_buttons:
		_check_leaf_geometry(button)
		expect(Rect2(Vector2.ZERO, menu.size).encloses(Rect2(button.position, button.size)), "长文本四纸叶依然在真实外框内")
	var reason_label: Label = menu.skill_buttons[1].get_node("Reason")
	expect(reason_label.text.contains("不得缩字或用省略号隐藏"), "完整原因文本保留")
	expect(reason_label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "停靠原因完整换行")
	expect(reason_label.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING, "停靠原因不省略")
	for control in menu.enabled_controls():
		expect(control.mouse_filter == Control.MOUSE_FILTER_STOP, "按钮命中阻止后层穿透")
	menu.hide()
	expect(menu.enabled_controls().is_empty(), "整簇隐藏后无可交互控件")
	menu.free()
	for failure in failures: printerr("FAIL:", failure)
	print("ACTOR_COMMAND_MENU_CONTRACT:", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func _text(node: Node) -> String:
	var result := ""
	if node is Label or node is Button: result = node.text
	for child in node.get_children(): result += "\n" + _text(child)
	return result

func _check_leaf_geometry(button: Button) -> void:
	var title: Label = button.get_node("Title")
	var resource: Label = button.get_node("Resource")
	expect(title.get_theme_font_size("font_size") == 27, "技能名称保持27号")
	expect(title.position.y + title.size.y <= resource.position.y, "标题与资源不重叠")
	for key in ["Title", "Resource", "Detail", "Reason"]:
		var label: Label = button.get_node(key)
		if not label.visible or label.text.is_empty(): continue
		var font_size := label.get_theme_font_size("font_size")
		var font := label.get_theme_font("font")
		var flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		var measured := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, label.size.x, font_size, -1, flags)
		expect(label.size.y >= font.get_height(font_size), "%s容纳真实字体单行高度" % key)
		expect(label.size.y >= measured.y, "%s容纳完整实际换行高度" % key)
		expect(label.get_theme_constant("line_spacing") == 0, "%s行距与Font度量一致" % key)
		expect(label.size.y >= font.get_height(font_size) * label.get_line_count(), "%s容纳Label实际排出的行数" % key)
		expect(Rect2(Vector2.ZERO, button.size).encloses(Rect2(label.position, label.size)), "%s完整落在纸叶内" % key)
		if key != "Title": expect(font_size == 24, "%s保持24号" % key)
		if key in ["Detail", "Reason"]: expect(label.position.y >= resource.position.y + resource.size.y, "%s不与资源重叠" % key)

func _model(page: String) -> Dictionary:
	var skills: Array = []
	for index in 4:
		skills.append({"id": "heavy_slash" if index == 0 else "skill_%d" % index, "name": "重斩·破隙" if index == 0 else "技能%d" % index, "mp_cost": 9, "cd_text": "CD 2", "legal": index != 1, "reasons": ["MP不足"] if index == 1 else (["附带控制免疫"] if index == 0 else []), "summary": "单体物攻", "target_label": "敌方单体"})
	var items: Array = []
	for id in ["healing_potion", "mana_potion", "revival_potion", "cleansing_powder", "energy_tea", "guard_charm", "moxa_roll"]:
		items.append({"id": id, "name": id, "count": 2, "legal": true, "reasons": []})
	return {"page": page, "actor_name": "凛音", "skills": skills, "basics": ["attack_physical", "attack_magic", "defend", "item"], "items": items, "selected_label": "重斩·破隙", "cost_text": "MP 9 · CD 2", "target_text": "纸妖·疾行", "prompt": "选择目标后显式确认", "confirm_legal": true}
