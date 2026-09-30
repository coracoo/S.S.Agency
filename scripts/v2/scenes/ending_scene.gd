extends Control
## 结局场景 v2
##
## 读 endings.json，根据 NarrativeState.flags 匹配结局（或直接显示 EndingBridge.ending_id）。
## 显示结局名称、描述、立绘。提供"回到标题"按钮。

@onready var title_label: Label = $VBox/TitleLabel
@onready var desc_label: RichTextLabel = $VBox/DescLabel
@onready var back_btn: Button = $VBox/BackBtn


func _ready() -> void:
	back_btn.pressed.connect(_on_back)
	var ending_dict := _resolve_ending()
	title_label.text = ending_dict.get("name", "未知结局")
	desc_label.text = ending_dict.get("description", "")
	# 记录达成（meta-progression）
	var eid = ending_dict.get("id", "")
	if not eid.is_empty() and not NarrativeState.unlocked_endings.has(eid):
		NarrativeState.unlocked_endings.append(eid)
	NarrativeState.save()


func _resolve_ending() -> Dictionary:
	# 若指定了 ending_id（如失败结局），直接用
	var explicit_id = GameBridge.ending_id
	GameBridge.clear_ending()
	var endings = _load_endings()
	if not explicit_id.is_empty():
		for e in endings:
			if e.get("id", "") == explicit_id:
				return e
	# 否则按 flags 匹配
	return NarrativeState.resolve_ending(endings)


func _load_endings() -> Array:
	var data = JsonLoader.load_file("res://data/v2/endings.json")
	if not (data is Dictionary):
		return []
	return data.get("endings", [])


func _on_back() -> void:
	NarrativeState.wipe()
	SceneRouter.go_title()
