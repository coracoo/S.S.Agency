# 可选本地片段只替代已批准的h1/h2；完整对白结束后仍提交原h1事件。
extends RefCounted

const STONE_BOWL_FILE := "night1_stone_bowl.ogv"
const SOURCE_DIRECTORY := "res://assets/cutscenes"
const EXTERNAL_DIRECTORY := "cutscenes"

static func for_dialogue(night: int, root_id: String) -> Dictionary:
	if night != 1 or root_id != "h1": return {}
	return {"file": STONE_BOWL_FILE, "continue_at": "h3"}

static func resolve_file(file_name: String) -> String:
	# 编辑器/源码固定目录；导出包优先读EXE旁的独立cutscenes目录。
	var paths: Array[String] = []
	if not OS.has_feature("editor"):
		var base := OS.get_executable_path().get_base_dir()
		paths.append(base.path_join(EXTERNAL_DIRECTORY).path_join(file_name))
	# 官方引擎运行独立PCK会移除main-pack参数，res根也没有物理路径。
	# 现有launch_campaign.bat/sh会先cd到发布目录，因此这里使用该工作目录。
	if ProjectSettings.globalize_path("res://").is_empty():
		var directory := DirAccess.open(".")
		if directory != null:
			paths.append(directory.get_current_dir().path_join(EXTERNAL_DIRECTORY).path_join(file_name))
	paths.append(SOURCE_DIRECTORY.path_join(file_name))
	for path in paths:
		if FileAccess.file_exists(path): return path
	return ""
