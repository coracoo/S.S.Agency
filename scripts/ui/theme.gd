class_name UITheme
extends RefCounted
## 《逢魔退治帖》v3 设计令牌加载器（GDD §9.3 / 规范6：UI 常量禁硬编码）。
## 用法: var t := UITheme.load_theme(); t.color("vermilion_500")

const THEME_PATH := "res://data/ui_theme.json"
## 和纸九图面板源图（GDD §9.10 素材批次②）：墨框 + 金线 + 右下角朱印
const WASHI_PANEL_PATH := "res://assets/ui/panel_washi_9slice.png"
const WASHI_PANEL_MARGIN := 108 # 1536px 源图 7%：覆盖墨框 + 金线

var _data: Dictionary = {}
var _washi_sb: StyleBoxTexture = null

static func load_theme() -> UITheme:
	var t := UITheme.new()
	var f := FileAccess.open(THEME_PATH, FileAccess.READ)
	if f == null:
		push_warning("[UITheme] 找不到 %s，使用空令牌" % THEME_PATH)
		return t
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		t._data = parsed
	else:
		push_warning("[UITheme] %s 解析失败" % THEME_PATH)
	return t

func color(key: String) -> Color:
	var hex: String = _data.get("colors", {}).get(key, "#FF00FF")
	return Color(hex)

func semantic_color(key: String) -> Color:
	var mapping: Dictionary = _data.get("semantic_colors", {})
	return color(mapping.get(key, key))

func dim(key: String) -> int:
	return int(_data.get("dims", {}).get(key, 0))

func dims(key: String) -> Dictionary:
	return _data.get("dims", {}).get(key, {})

func motion(key: String) -> float:
	return float(_data.get("motion", {}).get(key, 0.0))

func typography(key: String) -> Dictionary:
	return _data.get("typography", {}).get(key, {})

func shape(key: String) -> int:
	return int(_data.get("shape", {}).get(key, 0))

func canvas(key: String) -> int:
	return int(_data.get("canvas", {}).get(key, 0))

func raw() -> Dictionary:
	return _data

## 和纸九图面板样式（FileAccess 直读，导出 pck 内可用；全局共享只读实例）
func washi_panel() -> StyleBoxTexture:
	if _washi_sb == null:
		var tex := PngLoader.load_texture(WASHI_PANEL_PATH)
		if tex == null:
			return null
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.set_texture_margin_all(WASHI_PANEL_MARGIN)
		sb.set_content_margin_all(WASHI_PANEL_MARGIN + 14)
		_washi_sb = sb
	return _washi_sb

## 当前主线的烟墨面板。和纸接口保留供历史内容使用，正式界面不叠加纹样。
func surface_style(raised: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color("ui_surface" if raised else "ui_ink"), 0.97 if raised else 0.92)
	style.border_color = Color(color("ui_line"), 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(16)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 3)
	return style

func button_style(state: String, primary: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(3)
	style.set_content_margin_all(12)
	style.set_border_width_all(1)
	style.border_color = Color(color("ui_line"), 0.75)
	match state:
		"hover":
			style.bg_color = color("ui_accent_hover" if primary else "ui_hover")
			style.border_color = color("ui_muted")
		"pressed":
			style.bg_color = color("ui_accent_pressed" if primary else "ui_pressed")
			style.border_color = color("ui_muted")
			style.border_width_top = 3
		"disabled":
			style.bg_color = color("ui_disabled")
			style.border_color = Color(color("ui_line"), 0.3)
		"focus":
			style.draw_center = false
			style.set_border_width_all(2)
			style.border_color = color("ui_focus")
			style.expand_margin_left = 3
			style.expand_margin_right = 3
			style.expand_margin_top = 3
			style.expand_margin_bottom = 3
		_:
			style.bg_color = color("ui_accent" if primary else "ui_surface")
			if primary: style.border_color = color("ui_accent_hover")
	return style
