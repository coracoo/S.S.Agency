class_name UIThemeFactoryV2
extends RefCounted
## 高精度 UI 主题工厂 v2 —— JSON 驱动的 9-slice 主题系统
##
## 读取 data/v2/ui_theme.json（由 build_asset_pipeline.py 生成/维护）：
##   - 面板/按钮的 9-slice 源图、边距（margins）、内容边距（content）全部像素级配置在 JSON
##   - 修改 JSON 即可全局调整 UI，无需改代码
##   - 贴图缺失时回退到 StyleBoxFlat（色板仍来自 JSON colors）
##
## 用法：
##   var sb = UIThemeFactoryV2.panel("main")
##   control.add_theme_stylebox_override("panel", sb)
##   UIThemeFactoryV2.apply_button(button)   # normal/hover/pressed 三态

const THEME_PATH := "res://data/v2/ui_theme.json"

static var _theme: Dictionary = {}
static var _loaded := false
static var _cache: Dictionary = {}


static func load_theme(force := false) -> Dictionary:
	if _loaded and not force:
		return _theme
	_loaded = true
	var data = JsonLoader.load_file(THEME_PATH)
	if data is Dictionary:
		_theme = data
	return _theme


static func _color(hex: String, fallback: Color) -> Color:
	var c = Color.from_string(hex, fallback)
	return c


## 解析 9-slice 配置 → StyleBoxTexture；贴图缺失回退 StyleBoxFlat
static func _make_stylebox(cfg: Dictionary, fallback_bg: Color, fallback_border: Color) -> StyleBox:
	var source = str(cfg.get("source", ""))
	if not source.is_empty() and ResourceLoader.exists(source):
		var sb := StyleBoxTexture.new()
		sb.texture = load(source)
		var m = cfg.get("margins", [10, 10, 10, 10])
		sb.texture_margin_left = float(m[0])
		sb.texture_margin_top = float(m[1])
		sb.texture_margin_right = float(m[2])
		sb.texture_margin_bottom = float(m[3])
		var c = cfg.get("content", [8, 8, 8, 8])
		sb.content_margin_left = float(c[0])
		sb.content_margin_top = float(c[1])
		sb.content_margin_right = float(c[2])
		sb.content_margin_bottom = float(c[3])
		var mod = str(cfg.get("modulate", ""))
		if not mod.is_empty():
			sb.modulate_color = _color(mod, Color.WHITE)
		return sb
	# 回退：平面样式
	var fb := StyleBoxFlat.new()
	fb.bg_color = fallback_bg
	fb.border_color = fallback_border
	fb.set_border_width_all(2)
	fb.set_corner_radius_all(5)
	var cc = cfg.get("content", [8, 8, 8, 8])
	fb.content_margin_left = float(cc[0])
	fb.content_margin_top = float(cc[1])
	fb.content_margin_right = float(cc[2])
	fb.content_margin_bottom = float(cc[3])
	return fb


## 面板样式："main"（黄铜边）/ "dark"（铜绿边）
static func panel(kind: String = "main") -> StyleBox:
	var key = "panel_" + kind
	if _cache.has(key):
		return _cache[key]
	load_theme()
	var colors = _theme.get("colors", {})
	var cfg = _theme.get("panels", {}).get(kind, {})
	var fallback_bg := Color(0.08, 0.07, 0.05, 0.95)
	var fallback_border := _color(str(colors.get("brass", "#B8860B")), Color.BROWN)
	var sb = _make_stylebox(cfg, fallback_bg, fallback_border)
	_cache[key] = sb
	return sb


## 按钮三态样式，直接 override 到 Button
static func apply_button(btn: Button) -> void:
	load_theme()
	var colors = _theme.get("colors", {})
	var buttons = _theme.get("buttons", {})
	var brass = _color(str(colors.get("brass", "#B8860B")), Color.BROWN)
	var normal_cfg = buttons.get("normal", {})
	var hover_cfg = buttons.get("hover", {})
	var pressed_cfg = buttons.get("pressed", {})
	btn.add_theme_stylebox_override("normal", _make_stylebox(normal_cfg, Color(0.16, 0.12, 0.06), brass))
	btn.add_theme_stylebox_override("hover", _make_stylebox(hover_cfg, Color(0.22, 0.16, 0.08), brass))
	btn.add_theme_stylebox_override("pressed", _make_stylebox(pressed_cfg, Color(0.08, 0.06, 0.03), brass))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## 面板样式直接挂到 Panel/PanelContainer
static func apply_panel(control: Control, kind: String = "main") -> void:
	control.add_theme_stylebox_override("panel", panel(kind))
