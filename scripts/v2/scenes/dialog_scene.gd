extends Control
## 对话/叙事场景 v2
##
## 读章节 JSON 节点图，按 current_node 渲染当前节点（背景+立绘+文本+选项）。
## 节点 type：
##   dialog  - 显示文本与选项，选择后跳转下一节点
##   battle  - 切到 card_battle 场景，传入 enemies
##   ending  - 切到 ending 场景
##
## 章节流转：当某节点 next == "__chapter_complete__" 时，标记章节完成并跳到结局判定
## （或下一章节，暂未实现多章节串联，先回标题）。

@onready var bg: TextureRect = $BG
@onready var portrait: TextureRect = $PortraitRect
@onready var speaker_label: Label = $DialogPanel/Margin/VBox/SpeakerLabel
@onready var text_label: RichTextLabel = $DialogPanel/Margin/VBox/TextLabel
@onready var choices_container: VBoxContainer = $DialogPanel/Margin/VBox/ChoicesScroll/ChoicesContainer

var chapter_id: String = ""
var chapter_data: Dictionary = {}
var current_node_id: String = ""


func _ready() -> void:
	chapter_id = GameBridge.next_chapter_id
	current_node_id = GameBridge.next_node_id
	GameBridge.clear_chapter()
	DebugLog.node_ready("DialogScene", "ch=" + chapter_id + " node=" + current_node_id)
	# 9-slice 对话面板主题
	UIThemeFactoryV2.apply_panel($DialogPanel, "main")
	if chapter_id.is_empty():
		# 兜底：默认第一章
		chapter_id = "chapter_1"
		current_node_id = ""  # 让下面走 entry 逻辑
	chapter_data = ChapterLoader.load_chapter(chapter_id)
	if chapter_data.is_empty() or not chapter_data.has("nodes"):
		push_error("DialogScene: chapter not found " + chapter_id)
		text_label.text = "[章节加载失败: %s]" % chapter_id
		return
	if current_node_id.is_empty():
		current_node_id = chapter_data.get("entry", "start")
	NarrativeState.enter_chapter(chapter_id, current_node_id)
	_render_current_node()


func _render_current_node() -> void:
	NarrativeState.current_node = current_node_id
	NarrativeState.save()  # 每个节点都存档（便于"继续游戏"）
	var node = _get_node(current_node_id)
	if node.is_empty():
		push_error("DialogScene: node not found " + current_node_id)
		DebugLog.info("DIALOG_ERROR: node not found " + current_node_id)
		return
	DebugLog.info("DIALOG_RENDER: node=" + current_node_id + " type=" + node.get("type", "?"))

	# 检查是否有战斗结果需要消费（从战斗场景回来时）
	if GameBridge.battle_result != "":
		_consume_battle_result(node)
		return

	var node_type: String = node.get("type", "dialog")
	match node_type:
		"dialog":
			_render_dialog_node(node)
		"battle":
			_enter_battle(node)
		"ending":
			_enter_ending(node)
		_:
			_render_dialog_node(node)


func _render_dialog_node(node: Dictionary) -> void:
	# 背景
	var bg_path = node.get("bg", "")
	if bg_path is String and not bg_path.is_empty() and ResourceLoader.exists(bg_path):
		bg.texture = load(bg_path)
	elif bg_path == null:
		bg.texture = null
	else:
		bg.texture = null

	# 立绘
	var portrait_key = node.get("speaker_portrait", "")
	if portrait_key != null and not portrait_key.is_empty():
		var portrait_path = _resolve_portrait(portrait_key)
		if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path):
			portrait.texture = load(portrait_path)
			portrait.visible = true
		else:
			portrait.visible = false
	else:
		portrait.visible = false

	# 说话者名字
	var speaker = node.get("speaker", "")
	speaker_label.text = "" if speaker == "narrator" else speaker

	# 文本
	text_label.text = node.get("text", "")

	# 选项
	_clear_choices()
	var choices = node.get("choices", [])
	if choices.is_empty():
		# 无选项：显示"继续"按钮（等价于空 next）
		_add_choice_button("继续", node.get("next", "__chapter_complete__"), "")
	else:
		for choice in choices:
			_add_choice_button(choice.get("text", ""), choice.get("next", ""), choice.get("set_flag", ""))


func _consume_battle_result(node: Dictionary) -> void:
	var result = GameBridge.battle_result
	var src_node_id = GameBridge.battle_node_id
	GameBridge.clear_battle()
	var next_id = ""
	if result == "victory":
		next_id = node.get("on_victory", "")
		NarrativeState.set_flag("last_battle_victory", true)
	elif result == "defeat":
		next_id = node.get("on_defeat", "")
		NarrativeState.set_flag("battle_defeated", true)
	if next_id.is_empty():
		next_id = "__chapter_complete__"
	_navigate(next_id)


func _enter_battle(node: Dictionary) -> void:
	var enemy_ids = node.get("enemies", [])
	SceneRouter.go_battle(current_node_id, enemy_ids, chapter_id)


func _enter_ending(node: Dictionary) -> void:
	var ending_id = node.get("ending_id", "")
	if ending_id.is_empty():
		ending_id = "defeat"
	NarrativeState.set_flag("battle_defeated", ending_id == "defeat")
	SceneRouter.go_ending(ending_id)


func _add_choice_button(text: String, next: String, set_flag: String) -> void:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 44)
	btn.pressed.connect(func(): _on_choice_selected(next, set_flag))
	choices_container.add_child(btn)


func _on_choice_selected(next: String, set_flag: String) -> void:
	if not set_flag.is_empty():
		NarrativeState.set_flag(set_flag, true)
	_navigate(next)


func _navigate(next: String) -> void:
	if next == "__chapter_complete__":
		NarrativeState.mark_chapter_complete(chapter_id)
		# 单章节骨架：回标题。多章节串联留待 P3 阶段。
		SceneRouter.go_title()
		return
	if next == "__enter_explore__":
		# 从 intro 对话进入探索场景
		SceneRouter.go_explore(chapter_id)
		return
	if next == "__return_explore__":
		# 对话结束 → 回探索场景
		SceneRouter.go_explore(chapter_id)
		return
	if next.is_empty():
		push_error("DialogScene: empty next on node " + current_node_id)
		return
	current_node_id = next
	_render_current_node()


func _clear_choices() -> void:
	for c in choices_container.get_children():
		c.queue_free()


func _get_node(node_id: String) -> Dictionary:
	return chapter_data.get("nodes", {}).get(node_id, {})


func _resolve_portrait(key: String) -> String:
	# 暂用章节里 speaker_portrait 字段直接当 unit id，去 units.json 查 portrait 路径
	# P0 阶段可简化为直接返回空（无立绘），P1 接上数据驱动
	var units_data = JsonLoader.load_file("res://data/v2/units.json")
	if units_data is Dictionary:
		for u in units_data.get("units", []):
			if u is Dictionary and u.get("id", "") == key:
				return u.get("sprites", {}).get("portrait", "")
	return ""
