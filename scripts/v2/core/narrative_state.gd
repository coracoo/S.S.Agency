extends Node
## 叙事状态机 v2（Autoload 单例）
##
## 管理多结局所需的全部状态：
##   - 当前章节 ID 与当前节点 ID
##   - 玩家累计的 flag 字典（choices.set_flag 写入，ending.condition 判定读取）
##   - 持久化到 user://save.json
##
## 这是项目"多角色多结局"的核心数据层。剧情分支通过 set_flag 累计，最终在结局判定时
## 由 ending_scene 读 flags 并匹配 endings.json 的 condition。

signal flag_set(flag_name: String, value: Variant)
signal chapter_changed(chapter_id: String)

const SAVE_PATH := "user://narrative_save.json"

var flags: Dictionary = {}
var current_chapter: String = ""
var current_node: String = ""
var completed_chapters: Array = []
var unlocked_endings: Array = []  # 已达成的结局 ID（meta-progression）


func set_flag(name: String, value: Variant = true) -> void:
	flags[name] = value
	flag_set.emit(name, value)


func get_flag(name: String, default: Variant = null) -> Variant:
	return flags.get(name, default)


func has_flag(name: String) -> bool:
	return flags.has(name) and flags.get(name) != false


func clear_flags() -> void:
	flags.clear()


## 进入某章节的某节点（通常 entry 节点）
func enter_chapter(chapter_id: String, node_id: String = "") -> void:
	current_chapter = chapter_id
	# node_id 留空时不写 current_node（让 dialog 场景用 entry 兜底）
	if not node_id.is_empty():
		current_node = node_id
	chapter_changed.emit(chapter_id)


func mark_chapter_complete(chapter_id: String) -> void:
	if not completed_chapters.has(chapter_id):
		completed_chapters.append(chapter_id)


## 根据当前 flags 匹配结局。返回 endings.json 里第一个满足 condition 的结局 dict。
## 战斗失败等强制结局由调用方直接传 ending_id，不走匹配。
func resolve_ending(endings: Array) -> Dictionary:
	# 按 priority 降序排序，优先匹配高优先级结局
	var sorted := endings.duplicate(true)
	sorted.sort_custom(func(a, b): return int(a.get("priority", 0)) > int(b.get("priority", 0)))
	for e in sorted:
		if _condition_met(e.get("condition", {})):
			var eid = e.get("id", "")
			if not unlocked_endings.has(eid):
				unlocked_endings.append(eid)
			return e
	return {}


func _condition_met(condition: Dictionary) -> bool:
	# 所有键值对必须在 flags 中满足（AND）
	for key in condition:
		if not flags.has(key):
			return false
		var expected = condition[key]
		var actual = flags.get(key)
		if expected is bool:
			if bool(actual) != bool(expected):
				return false
		elif str(actual) != str(expected):
			return false
	return true


# ===== 持久化 =====

func save() -> bool:
	var data := {
		"flags": flags,
		"current_chapter": current_chapter,
		"current_node": current_node,
		"completed_chapters": completed_chapters,
		"unlocked_endings": unlocked_endings
	}
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("NarrativeState: save failed " + SAVE_PATH)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


func load() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK:
		push_error("NarrativeState: save parse error")
		return false
	var data = json.data
	if not (data is Dictionary):
		return false
	flags = data.get("flags", {})
	current_chapter = data.get("current_chapter", "")
	current_node = data.get("current_node", "")
	completed_chapters = data.get("completed_chapters", [])
	unlocked_endings = data.get("unlocked_endings", [])
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func wipe() -> void:
	flags.clear()
	current_chapter = ""
	current_node = ""
	completed_chapters.clear()
	# 不清 unlocked_endings（meta-progression 永久保留）
