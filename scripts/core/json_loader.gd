class_name JsonLoader

static var _cache: Dictionary = {}

static func load_file(path: String) -> Variant:
	if _cache.has(path):
		return _cache[path].duplicate(true) if _cache[path] is Dictionary or _cache[path] is Array else _cache[path]
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open: " + path)
		return null
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(text)
	if err != OK:
		push_error("JSON parse error in %s: %s" % [path, json.get_error_message()])
		return null
	_cache[path] = json.data
	return json.data.duplicate(true) if json.data is Dictionary or json.data is Array else json.data

static func clear_cache() -> void:
	_cache.clear()
