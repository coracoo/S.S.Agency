class_name ChapterLoader
extends RefCounted
## 章节 JSON 加载器 v2
##
## 从 res://data/v2/chapters/<chapter_id>.json 加载章节节点图。
## 带内存缓存（章节在整个游戏流程中只加载一次）。

static var _cache: Dictionary = {}


static func load_chapter(chapter_id: String) -> Dictionary:
	if _cache.has(chapter_id):
		return _cache[chapter_id]
	var path = "res://data/v2/chapters/%s.json" % chapter_id
	var data = JsonLoader.load_file(path)
	if not (data is Dictionary):
		push_error("ChapterLoader: chapter not found " + path)
		return {}
	_cache[chapter_id] = data
	return data


static func list_chapter_ids() -> Array:
	# 扫描 chapters 目录下所有 .json
	var dir = DirAccess.open("res://data/v2/chapters")
	if dir == null:
		return []
	var result: Array = []
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			result.append(fname.substr(0, fname.length() - 5))
		fname = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result
