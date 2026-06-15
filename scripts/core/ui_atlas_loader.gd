class_name UiAtlasLoader
extends RefCounted

## UI 图集加载器
## 读取 data/ui_atlas.json，为代码提供统一的 UI 底板/图标/9-slice 边距。
## 用法：
##   var atlas = UiAtlasLoader.new()
##   var panel_info = atlas.get_panel("status_panel")
##   nine_patch_rect.texture = load(panel_info.source_path)
##   nine_patch_rect.region_rect = panel_info.region
##   nine_patch_rect.patch_margin_left = panel_info.patch_margin.x
##   ...

const ATLAS_PATH := "res://data/ui_atlas.json"

var _data: Dictionary = {}
var _loaded := false

func _init():
	_reload()

func _reload() -> void:
	if not FileAccess.file_exists(ATLAS_PATH):
		push_error("UI 图集配置不存在: %s" % ATLAS_PATH)
		return
	var file := FileAccess.open(ATLAS_PATH, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_error("UI 图集配置解析失败")
		return
	_data = parsed
	_loaded = true

## 获取单个面板配置
func get_panel(name: String) -> Dictionary:
	if not _loaded:
		return {}
	var panels: Dictionary = _data.get("panels", {})
	var panel: Dictionary = panels.get(name, {})
	if panel.is_empty():
		push_warning("UI 面板未找到: %s" % name)
		return {}
	var source_name: String = panel.get("source", "")
	var source_path: String = _get_source_path(source_name)
	var region_arr: Array = panel.get("region", [0, 0, 0, 0])
	var margin_arr: Array = panel.get("patch_margin", [0, 0, 0, 0])
	return {
		"name": name,
		"source": source_name,
		"source_path": source_path,
		"region": Rect2i(region_arr[0], region_arr[1], region_arr[2], region_arr[3]),
		"patch_margin": Vector4i(margin_arr[0], margin_arr[1], margin_arr[2], margin_arr[3]),
		"description": panel.get("description", "")
	}

## 获取单个图标配置
func get_icon(name: String) -> Dictionary:
	if not _loaded:
		return {}
	var icons: Dictionary = _data.get("icons", {})
	var icon: Dictionary = icons.get(name, {})
	if icon.is_empty():
		push_warning("UI 图标未找到: %s" % name)
		return {}
	var source_name: String = icon.get("source", "")
	var source_path: String = _get_source_path(source_name)
	var region_arr: Array = icon.get("region", [0, 0, 0, 0])
	return {
		"name": name,
		"source": source_name,
		"source_path": source_path,
		"region": Rect2i(region_arr[0], region_arr[1], region_arr[2], region_arr[3]),
		"description": icon.get("description", "")
	}

func _get_source_path(source_name: String) -> String:
	var sources: Dictionary = _data.get("sources", {})
	var source: Dictionary = sources.get(source_name, {})
	return source.get("path", "")

## 获取所有面板名称
func get_panel_names() -> Array:
	if not _loaded:
		return []
	return _data.get("panels", {}).keys()

## 获取所有图标名称
func get_icon_names() -> Array:
	if not _loaded:
		return []
	return _data.get("icons", {}).keys()
