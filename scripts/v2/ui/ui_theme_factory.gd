class_name UIThemeFactory
extends RefCounted
## UI 主题工厂 v2
##
## 从旧 battle_scene.gd 的 _make_*_panel_style / _make_card_style / _apply_chinese_font 抽取。
## 提供 9-slice 面板、字体、按钮样式、HP 条样式的统一生成入口。
##
## 蒸汽道术色板（替换旧 Art_Bible 色板）。
## 当前为骨架占位，P1 阶段会从旧代码迁移 StyleBox 生成逻辑。

const COLOR_JET_BLACK := Color("#1A1A1A")
const COLOR_BRASS := Color("#B8860B")
const COLOR_CINNABAR := Color("#C23B3B")
const COLOR_COPPER_GREEN := Color("#50A0A0")
const COLOR_STEAM_WHITE := Color("#E8E0D0")
const COLOR_INK_BLUE := Color("#2A5C6B")
const COLOR_PHOSPHOR_GREEN := Color("#7FFF50")

const FONT_REGULAR := "res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf"
const FONT_MEDIUM := "res://assets/fonts/Alibaba-PuHuiTi-Medium.ttf"
const FONT_BOLD := "res://assets/fonts/Alibaba-PuHuiTi-Bold.ttf"


## 蒸汽道术主面板样式（玄黑底 + 黄铜边）
static func make_panel_style() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.07, 0.09, 0.95)
	s.border_color = COLOR_BRASS
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(8)
	return s


## 卡牌面板样式（深底 + 黄铜细边）
static func make_card_style(selected: bool = false) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.08, 0.05, 1.0)
	s.border_color = COLOR_CINNABAR if selected else COLOR_BRASS
	s.set_border_width_all(2 if selected else 1)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(6)
	return s


## HP 条背景
static func make_hp_bar_background() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.15, 0.05, 0.05, 1)
	s.set_corner_radius_all(3)
	return s


## HP 条填充（敌人朱红 / 玩家翠绿）
static func make_hp_bar_fill(faction: String) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = COLOR_CINNABAR if faction == "enemy" else Color(0.31, 0.78, 0.31)
	s.set_corner_radius_all(3)
	return s


## 按钮样式（普通 / 悬停 / 按下）
static func make_button_style() -> Dictionary:
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.10, 0.07, 1)
	normal.border_color = COLOR_BRASS
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(8)
	var hover = normal.duplicate()
	hover.bg_color = Color(0.18, 0.14, 0.08, 1)
	var pressed = normal.duplicate()
	pressed.bg_color = Color(0.06, 0.05, 0.03, 1)
	return {"normal": normal, "hover": hover, "pressed": pressed}


## 应用中文字体到控件（若字体文件存在）
static func apply_font(control: Control, size: int = 16) -> void:
	if not ResourceLoader.exists(FONT_REGULAR):
		return
	control.add_theme_font_override("font", load(FONT_REGULAR))
	control.add_theme_font_size_override("font_size", size)
