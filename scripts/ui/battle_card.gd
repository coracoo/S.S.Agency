extends Control
## 战斗卡牌控件（GDD §9.5 Card 组件的 demo 实现）。
## 紧凑竖卡（176×246）：满幅卡图（居中裁切不拉伸）+ 底部墨晕带压名与类型签，
## 无留白纸面；费用勾玉右上角。态：常态 / 悬停立起(1.08×) / 选中抬高 / AP 不足置灰。
## 性能：StyleBox/字体/卡图源裁切全部 setup 期缓存，_draw 只做纯绘制指令；
## 贴图走 mipmap 三线性过滤（PngLoader 生成 mip 链），缩小不糊。

signal clicked(card)
signal hover_changed(card, is_hovered)

var data: Dictionary = {}
var disabled := false:
	set(v):
		disabled = v
		queue_redraw()

var _theme = null
var _art: Texture2D = null
var _hovered := false
var _selected := false

var _home_pos := Vector2.ZERO

const _CW := 176
const _CH := 246

# setup 期缓存（_draw 内不再新建 Resource，避免悬停/选中重绘时的分配卡顿）
var _font_name: Font = null
var _font_small: Font = null
var _sb_base: StyleBox = null
var _sb_gold: StyleBox = null
var _sb_sel: StyleBox = null
var _ink := Color.BLACK
var _wood := Color.BLACK
var _paper := Color.WHITE
var _gold := Color.WHITE
var _hi := Color.WHITE
var _art_src := Rect2() # 卡图按卡面竖幅比例裁好的源矩形

func setup(card_data: Dictionary, theme) -> void:
	data = card_data
	_theme = theme
	size = Vector2(_CW, _CH)
	custom_minimum_size = size
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS # 带 mip 三线性，缩小清晰
	mouse_filter = MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	# 缓存调色板与字体
	_ink = _theme.color("ink_900")
	_wood = _theme.color("ink_700")
	_paper = _theme.color("paper_100")
	_gold = _theme.color("gold_500")
	_hi = _theme.color("hi_500")
	_font_name = _load_font()
	_font_small = _font_name
	_sb_base = _make_style(_wood, 10)
	_sb_gold = _make_style(Color(0, 0, 0, 0), 7, _gold, 2)
	_sb_sel = _make_style(Color(0, 0, 0, 0), 8, _hi, 3)
	# 卡图：加载并按目标竖幅比例预计算源裁切矩形
	_art = _load_texture(data.get("art", ""))
	_art_src = _calc_art_src()
	queue_redraw()

func set_home(p: Vector2) -> void:
	_home_pos = p
	position = p

func set_selected(v: bool) -> void:
	_selected = v
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if v:
		tw.tween_property(self, "position:y", _home_pos.y - 46, 0.18)
		z_index = 20
	else:
		tw.tween_property(self, "position:y", _home_pos.y, 0.18)
		if not _hovered:
			z_index = 0

func _on_mouse_entered() -> void:
	_hovered = true
	z_index = 10
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.08, 1.08), 0.15)
	hover_changed.emit(self, true)

func _on_mouse_exited() -> void:
	_hovered = false
	if not _selected:
		z_index = 0
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.15)
	hover_changed.emit(self, false)

func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)

func _draw() -> void:
	var dim := 0.45 if disabled else 1.0
	# 底：深木框 + 金缮内线（卡图为满幅主体，不再衬和纸白纸面）
	draw_style_box(_sb_base, Rect2(Vector2.ZERO, size))
	draw_style_box(_sb_gold, Rect2(Vector2(4, 4), size - Vector2(8, 8)))
	# 满幅卡图（源矩形已按竖幅比例预裁，居中不拉伸）
	var art_rect := Rect2(Vector2(10, 10), Vector2(_CW - 20, _CH - 20))
	if _art == null:
		draw_style_box(_make_style(_paper, 5), art_rect)
		draw_circle(art_rect.get_center(), 18, Color(_wood, 0.5))
	elif _art_src.has_area():
		draw_texture_rect_region(_art, art_rect, _art_src, Color(1, 1, 1, dim))
	else:
		draw_texture_rect(_art, art_rect, false, Color(1, 1, 1, dim))
	if disabled:
		draw_rect(art_rect, Color(0.1, 0.1, 0.1, 0.5))

	# 底部墨晕带（近不透明，压住 AI 卡图底部自 baked 的浅色标签边）
	var band_top := _CH - 76
	for i in 8:
		var t := float(i) / 7.0
		draw_rect(Rect2(10, band_top + i * 9, _CW - 20, 9),
			Color(_ink, lerpf(0.72, 0.96, t)))
	draw_line(Vector2(10, band_top), Vector2(_CW - 10, band_top),
		Color(_gold, 0.55), 1.5)

	# 名称（墨带上，Regular+墨色描边——Bold 字体在 draw_string 管线 rasterize 异常，不用）
	var name_pos := Vector2(_CW * 0.5, _CH - 46)
	var name: String = data.get("name", "?")
	draw_string_outline(_font_name, name_pos, name,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 20, 2, Color(_ink, dim))
	draw_string(_font_name, name_pos, name,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color(_paper, dim))
	# 类型小签
	var type_txt: String = {"attack": "攻", "slot": "景", "seal": "结", "skill": "术"}\
		.get(data.get("type", ""), "卡")
	draw_string(_font_small, Vector2(_CW * 0.5, _CH - 22), "· %s ·" % type_txt,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(_gold, 0.9 * dim))

	# 费用勾玉（右上角压卡图；数字同用 Regular 描边）
	var cost := int(data.get("cost", 0))
	draw_circle(Vector2(_CW - 30, 30), 16, Color(_ink, 0.82 * dim))
	draw_arc(Vector2(_CW - 30, 30), 16, 0, TAU, 32,
		_gold if not disabled else Color(0.4, 0.4, 0.4), 2.0)
	var gem_pos := Vector2(_CW - 30, 36)
	draw_string_outline(_font_name, gem_pos, str(cost),
		HORIZONTAL_ALIGNMENT_CENTER, -1, 17, 2, Color(_ink, dim))
	draw_string(_font_name, gem_pos, str(cost),
		HORIZONTAL_ALIGNMENT_CENTER, -1, 17, Color(_paper, dim))
	if _selected:
		draw_style_box(_sb_sel, Rect2(Vector2(2, 2), size - Vector2(4, 4)))

## 卡图源矩形：按卡面竖幅比例居中裁切（避免拉伸变形）；无图信息返回空矩形
func _calc_art_src() -> Rect2:
	if _art == null:
		return Rect2()
	var tw := float(_art.get_width())
	var th := float(_art.get_height())
	if tw <= 0.0 or th <= 0.0:
		return Rect2()
	var dest_ratio := float(_CW - 20) / float(_CH - 20)
	if tw / th > dest_ratio:
		var w := th * dest_ratio # 源图偏横：裁左右
		return Rect2((tw - w) * 0.5, 0, w, th)
	if tw / th < dest_ratio:
		var h := tw / dest_ratio # 源图偏方/竖：裁上下
		return Rect2(0, (th - h) * 0.5, tw, h)
	return Rect2(0, 0, tw, th)

func _make_style(fill: Color, radius: int, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.bg_color = fill
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	return sb

func _load_font() -> Font:
	var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
	return f if f else ThemeDB.fallback_font

func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	return PngLoader.load_texture(path)
