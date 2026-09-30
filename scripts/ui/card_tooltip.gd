class_name CardTooltip
extends PanelContainer
## 卡牌悬浮说明（替代原 S5 详情弹层）：悬停手牌时在卡的上方浮出
## 名称/费用/类型/效果文本，移开即散。战斗与仪式两处共用。
## 用法：var tip = CardTooltip.build(theme, def); layer.add_child(tip); tip.place_above(card)

const TYPE_LABEL := {"attack": "攻击", "slot": "场景", "seal": "结界", "skill": "术法"}

var _theme = null

static func build(theme, def: Dictionary) -> CardTooltip:
	var tip := CardTooltip.new()
	tip._theme = theme
	tip.z_index = 40 # 盖过悬停/选中手牌（z 10–20）
	tip.add_theme_stylebox_override("panel", theme.washi_panel())
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(330, 0)
	v.add_theme_constant_override("separation", 8)
	tip.add_child(v)
	var ink: Color = theme.color("ink_900")
	# 名称 + 费用行
	var name_l := _mk_label("%s　·　费用 %d 灵墨" % [def.get("name", "?"), int(def.get("cost", 0))],
		22, theme.color("vermilion_500"), true)
	v.add_child(name_l)
	# 类型签 + 归属（归属名从 data/units.json 查，查不到显示原 id）
	var meta := "类型：%s" % TYPE_LABEL.get(String(def.get("type", "")), "卡")
	var owner := String(def.get("owner", ""))
	if not owner.is_empty():
		meta += "　归属：%s" % _owner_name(owner)
	var meta_l := _mk_label(meta, 16, Color(ink, 0.7), false)
	v.add_child(meta_l)
	# 效果文本
	var desc_l := _mk_label(String(def.get("desc", "")), 18, ink, false)
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_l.custom_minimum_size = Vector2(330, 0)
	v.add_child(desc_l)
	return tip

## 浮在指定卡上方（水平居中于卡，卡锚点为手牌层内坐标）。
## 需在入树后由调用方 call_deferred 调用（容器尺寸要一次布局后才可取）。
func place_above(card: Control) -> void:
	var card_w: float = card.size.x * card.scale.x
	var x: float = card.position.x + card_w * 0.5 - size.x * 0.5
	x = clampf(x, 12.0, 1920.0 - size.x - 12.0)
	position = Vector2(x, maxf(12.0, card.position.y - size.y - 18.0))

## 归属名查询缓存（悬停频繁触发，避免每次读盘+解析）
static var _owner_names: Dictionary = {}

static func _owner_name(owner: String) -> String:
	if _owner_names.is_empty():
		var f := FileAccess.open("res://data/units.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			var units: Array = parsed.get("units", []) if parsed is Dictionary else []
			for u in units:
				_owner_names[String((u as Dictionary).get("id", ""))] = String((u as Dictionary).get("name", ""))
	return _owner_names.get(owner, owner)

static func _mk_label(text: String, sz: int, c: Color, bold: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sz)
	var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-%s.ttf" % ("Bold" if bold else "Regular"))
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_color_override("font_color", c)
	return l
