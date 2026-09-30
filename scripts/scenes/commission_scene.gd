class_name CommissionScene
extends Node2D
## 《逢魔退治帖》v3 委托挂轴（GDD §9.4 S2）。
## 竖幅挂轴自轴下展开（空白纸面垂下 → 委托文墨渐次晕开），朱红承印落章后
## 墨线转场进对应探索舞台。数据驱动 data/commissions.json；
## locked 条目以「未完笔」墨影占位。ESC 墨线返回标题屏。

const DATA_PATH := "res://data/commissions.json"
const TITLE_SCENE := "res://scenes/v3/title.tscn"
const STAGE_BACKDROP := "res://scenes/v3/stage.tscn"
const UIThemeScript = preload("res://scripts/ui/theme.gd")
const InkTransitionScript = preload("res://scripts/ui/ink_transition.gd")
const SfxScript = preload("res://scripts/ui/sfx.gd")

var _theme = null
var _hud: CanvasLayer = null
var _list: Array = []
var _unlocked: Array = [] # 可承接委托（多委托时挂轴左右翻页切换）
var _sel := 0
var _bg_stage: Variant = null
var _content_layer: Control = null

func _ready() -> void:
	_theme = UIThemeScript.load_theme()
	_load_data()
	_build_live_background()
	_build_scroll()
	set_process(true)

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		SfxScript.play(self, "turn_end", -14.0)
		InkTransitionScript.transition(get_tree(), func() -> void:
			get_tree().change_scene_to_file(TITLE_SCENE))

# ---------- 数据 ----------

func _load_data() -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("[CommissionScene] 缺少 %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_list = parsed.get("commissions", [])
	for c in _list:
		if not bool((c as Dictionary).get("locked", false)):
			_unlocked.append(c)

# ---------- 背景：探索场景实例作活绘卷，墨色压暗托出挂轴 ----------

func _build_live_background() -> void:
	var packed: PackedScene = load(STAGE_BACKDROP)
	if packed == null:
		push_error("[CommissionScene] 无法加载背景场景 %s" % STAGE_BACKDROP)
		return
	_bg_stage = packed.instantiate()
	if _bg_stage.has_method("set"):
		_bg_stage.set("input_enabled", false)
		_bg_stage.set("backdrop_mode", true)
	add_child(_bg_stage)
	# 墨色压暗（挂轴屏比标题屏沉一档）
	var dim := ColorRect.new()
	dim.color = Color(_theme.color("ink_900"), 0.62)
	dim.position = Vector2.ZERO
	dim.size = Vector2(float(_theme.canvas("base_width")), float(_theme.canvas("base_height")))
	_hud_dim_parent().add_child(dim)

## 暗罩放 CanvasLayer，保证屏幕固定
func _hud_dim_parent() -> CanvasLayer:
	_hud = CanvasLayer.new()
	add_child(_hud)
	return _hud

# ---------- 挂轴 ----------

func _build_scroll() -> void:
	var cw := float(_theme.canvas("base_width"))
	# 轴身版面：居中竖幅
	var scroll_w := 500.0
	var sx := (cw - scroll_w) * 0.5
	var top := 96.0
	var body_h := 872.0
	# 顶轴（深色木轴 + 金线）
	var rod_t := _rod(Vector2(sx - 30, top - 22))
	_hud.add_child(rod_t)
	# 轴身纸面：初始收拢，自上垂下展开（scale 自顶轴向下生长，纸面纯色无拉伸感）
	var body := Panel.new()
	body.position = Vector2(sx, top)
	body.size = Vector2(scroll_w, body_h)
	body.add_theme_stylebox_override("panel", _theme.washi_panel())
	body.scale.y = 0.02
	body.pivot_offset = Vector2.ZERO
	_hud.add_child(body)
	# 底轴：挂在轴身下缘，随展开垂落
	var rod_b := _rod(Vector2(-30, body_h - 8))
	body.add_child(rod_b)
	# 委托文墨层（屏幕固定，展开后晕开；不挂轴身，避免随 scale 拉伸）
	_content_layer = Control.new()
	_content_layer.position = Vector2(sx, top)
	_content_layer.size = Vector2(scroll_w, body_h)
	_content_layer.clip_contents = true
	_content_layer.modulate.a = 0.0
	_hud.add_child(_content_layer)
	_fill_content()
	# 多委托翻页 ◀ ▶（挂轴两侧墨字小签）
	if _unlocked.size() > 1:
		_hud.add_child(_pager("◀", Vector2(sx - 62, top + body_h * 0.5 - 24), -1))
		_hud.add_child(_pager("▶", Vector2(sx + scroll_w + 14, top + body_h * 0.5 - 24), 1))
	# 展开演出：纸面垂下 → 文墨晕开
	var tw: Tween = create_tween()
	tw.tween_interval(0.3)
	tw.tween_property(body, "scale:y", 1.0, 0.85)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.chain().tween_callback(func() -> void: SfxScript.play(self, "door", -12.0))
	tw.chain().tween_property(_content_layer, "modulate:a", 1.0, 0.55)

func _rod(pos: Vector2) -> Panel:
	var rod := Panel.new()
	rod.position = pos
	rod.size = Vector2(560, 30)
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = _theme.color("ink_700")
	rsb.set_corner_radius_all(15)
	rsb.set_border_width_all(2)
	rsb.border_color = Color(_theme.color("gold_500"), 0.8)
	rod.add_theme_stylebox_override("panel", rsb)
	return rod

## 委托文墨：夜次朱签 + 题名 + 委托人 + 事由 + 报酬 + 承印
func _fill_content() -> void:
	var ink: Color = _theme.color("ink_900")
	if _unlocked.is_empty():
		return
	_sel = posmod(_sel, _unlocked.size())
	var main: Dictionary = _unlocked[_sel]
	# 夜次朱签
	var no_l := _label(main.get("no", ""), Vector2(0, 40), 20)
	no_l.size = Vector2(_content_layer.size.x, 28)
	no_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	no_l.add_theme_color_override("font_color", _theme.color("vermilion_500"))
	_content_layer.add_child(no_l)
	# 题名
	var title_l := _label(main.get("title", ""), Vector2(0, 84), 30)
	title_l.size = Vector2(_content_layer.size.x, 40)
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_l.add_theme_color_override("font_color", ink)
	var tf: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Bold.ttf")
	if tf:
		title_l.add_theme_font_override("font", tf)
	_content_layer.add_child(title_l)
	_content_layer.add_child(_divider(168))
	# 已结案朱签（该委托对应的案件真相已结算，红签斜挂题名右侧）
	var case_id := String(main.get("case", ""))
	if not case_id.is_empty() and ProgressSaveV4.is_case_done(case_id):
		var done_l := _label("已结案", Vector2(_content_layer.size.x - 132, 88), 18)
		done_l.rotation = -0.12
		done_l.add_theme_color_override("font_color", _theme.color("vermilion_500"))
		var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Bold.ttf")
		if f:
			done_l.add_theme_font_override("font", f)
		_content_layer.add_child(done_l)
	# 委托人
	var client_l := _label("委托人：" + main.get("client", ""), Vector2(44, 190), 16)
	client_l.add_theme_color_override("font_color", Color(ink, 0.75))
	_content_layer.add_child(client_l)
	# 事由
	var desc_l := _label(main.get("desc", ""), Vector2(44, 236), 18)
	desc_l.add_theme_color_override("font_color", ink)
	desc_l.custom_minimum_size = Vector2(_content_layer.size.x - 88, 0)
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD
	_content_layer.add_child(desc_l)
	# 报酬
	var rw_l := _label("报酬：" + main.get("reward", ""), Vector2(44, 560), 17)
	rw_l.add_theme_color_override("font_color", _theme.color("gold_500"))
	rw_l.custom_minimum_size = Vector2(_content_layer.size.x - 88, 0)
	rw_l.autowrap_mode = TextServer.AUTOWRAP_WORD
	_content_layer.add_child(rw_l)
	# 未完笔占位（后续锁定委托）
	var locked_n := 0
	for c in _list:
		if bool(c.get("locked", false)):
			locked_n += 1
	if locked_n > 0:
		var ghost := _label("※ 另有 %d 纸委托未完笔……" % locked_n, Vector2(44, 640), 15)
		ghost.add_theme_color_override("font_color", Color(ink, 0.42))
		_content_layer.add_child(ghost)
	# 承印（未锁定时可落章）
	if not bool(main.get("locked", false)):
		var seal := _accept_seal()
		seal.position = Vector2(_content_layer.size.x * 0.5 - 70, 700)
		seal.pressed.connect(_on_accept.bind(main))
		_content_layer.add_child(seal)
	else:
		var un := _label("（未开放）", Vector2(0, 716), 18)
		un.size = Vector2(_content_layer.size.x, 26)
		un.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		un.add_theme_color_override("font_color", Color(ink, 0.5))
		_content_layer.add_child(un)

func _divider(y: float) -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(_theme.color("ink_900"), 0.7)
	line.position = Vector2(44, y)
	line.size = Vector2(_content_layer.size.x - 88, 2)
	return line

## 承印：朱红方印「承 知」，悬停金框微浮
func _accept_seal() -> Button:
	var btn := Button.new()
	btn.text = "承  知"
	btn.size = Vector2(140, 64)
	btn.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = _theme.color("vermilion_500")
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = Color(_theme.color("paper_100"), 0.5)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Bold.ttf")
	if f:
		btn.add_theme_font_override("font", f)
	btn.add_theme_font_size_override("font_size", 24)
	btn.add_theme_color_override("font_color", _theme.color("paper_100"))
	btn.mouse_entered.connect(func() -> void:
		SfxScript.play(self, "bell", -22.0)
		var tw: Tween = create_tween()
		tw.tween_property(btn, "position:y", btn.position.y - 4.0, 0.12))
	btn.mouse_exited.connect(func() -> void:
		var tw: Tween = create_tween()
		tw.tween_property(btn, "position:y", btn.position.y + 4.0, 0.12))
	return btn

# ---------- 动作 ----------

## 挂轴翻页小签（◀ ▶）：切换当前展示的委托，文墨淡去重晕
func _pager(text: String, pos: Vector2, dir: int) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.position = pos
	btn.size = Vector2(48, 48)
	btn.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(_theme.color("ink_900"), 0.55)
	sb.set_border_width_all(2)
	sb.border_color = Color(_theme.color("gold_500"), 0.75)
	sb.set_corner_radius_all(24)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_font_override("font", _font(20))
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", _theme.color("paper_100"))
	btn.pressed.connect(_switch_page.bind(dir))
	return btn

func _switch_page(dir: int) -> void:
	SfxScript.play(self, "bell", -16.0)
	_sel = posmod(_sel + dir, _unlocked.size())
	for child in _content_layer.get_children():
		child.queue_free()
	_content_layer.modulate.a = 0.0
	_fill_content()
	var tw: Tween = create_tween()
	tw.tween_property(_content_layer, "modulate:a", 1.0, 0.35)

func _on_accept(com: Dictionary) -> void:
	SfxScript.play(self, "seal")
	# 登记当前案件：真相结算场景据此取 data/cases/<case_id>.json 授予奖励
	if not String(com.get("case", "")).is_empty():
		CaseFlowV4.case_id = String(com.get("case"))
	var target: String = com.get("stage", STAGE_BACKDROP)
	InkTransitionScript.transition(get_tree(), func() -> void:
		get_tree().change_scene_to_file(target))

# ---------- 工具 ----------

func _label(text: String, pos: Vector2, sz: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", _theme.color("paper_100"))
	return l

func _font(_sz: int) -> Font:
	var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
	return f if f else ThemeDB.fallback_font
