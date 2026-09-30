extends Node2D
## 战斗场景槽（GDD §5.2b demo 实现）：嵌在背景画中的可交互元素。
## 态：idle(灯火橙呼吸描边) / targetable(高亮等待点击) /
##     burning(朱红火光+余烬闪烁) / ringing(声波扩散环) / spilled(水渍晕开)。

signal slot_clicked(slot)

const FIRE_TEX_PATH := "res://assets/effects/fire_painterly.png" # 素材批次②水彩火焰（Image 直读绕 .import）

var slot_id := ""
var display_name := ""
var seal_point := false
var extinguish := false
var adjacent: Array = []
var state := "idle":
	set(v):
		state = v
		_elapsed = 0.0
		queue_redraw()

var _theme = null
var _hovered := false
var _elapsed := 0.0
var _fire_tex: Texture2D = null

func setup(id: String, cname: String, theme, world_pos: Vector2) -> void:
	slot_id = id
	display_name = cname
	_theme = theme
	position = world_pos
	set_process(true)

func _ready() -> void:
	var area := Area2D.new()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 70.0
	shape.shape = circle
	area.add_child(shape)
	area.mouse_entered.connect(_on_hover.bind(true))
	area.mouse_exited.connect(_on_hover.bind(false))
	area.input_event.connect(_on_input)
	add_child(area)

func _on_hover(v: bool) -> void:
	_hovered = v
	queue_redraw()

func _on_input(_v: Node, event: InputEvent, _s: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		slot_clicked.emit(self)

func _process(delta: float) -> void:
	_elapsed += delta
	if state != "idle":
		queue_redraw()
	elif int(_elapsed * 2.0) != int((_elapsed - delta) * 2.0):
		queue_redraw() # idle 呼吸 2Hz 重绘

func _draw() -> void:
	var hi: Color = _theme.color("hi_500")
	var verm: Color = _theme.color("vermilion_500")
	match state:
		"idle":
			var pulse := 0.55 + 0.25 * sin(_elapsed * TAU * 0.5)
			_ring(58.0, hi, pulse)
			_ring(74.0, hi, pulse * 0.4)
		"targetable":
			var fast := 0.7 + 0.3 * sin(_elapsed * TAU * 2.0)
			_ring(58.0, hi, fast)
			_ring(74.0, Color(1, 1, 1), fast * 0.5)
			draw_arc(Vector2.ZERO, 66.0, 0, TAU, 48, hi, 3.0)
		"burning":
			# 水彩火焰贴图：摇曳缩放 + 轻摆（素材批次②，替换纯矢量火环）
			var ft := _fire_texture()
			if ft:
				var fh := 200.0
				var fw := 150.0
				var sway := sin(_elapsed * 3.1) * 4.0
				var fscale := 0.94 + 0.08 * sin(_elapsed * 13.0) * sin(_elapsed * 5.3)
				var falpha := 0.9 + 0.1 * sin(_elapsed * 17.0)
				draw_texture_rect(ft, Rect2(Vector2(-fw * 0.5 + sway, -fh * fscale + 26.0),
					Vector2(fw, fh * fscale)), false, Color(1, 1, 1, falpha))
			var flick := 0.75 + 0.2 * sin(_elapsed * 23.0) * sin(_elapsed * 7.0)
			for i in range(3):
				_ring(46.0 + i * 16.0, verm, flick * (0.5 - i * 0.13))
			# 余烬
			for i in range(6):
				var a := _elapsed * 1.7 + i * 1.05
				var r := 34.0 + 14.0 * sin(_elapsed * 2.0 + i)
				draw_circle(Vector2(cos(a), sin(a) * 0.7 - 0.4) * r, 3.2,
					Color(verm.r, verm.g * 0.7, 0.2, 0.8))
		"ringing":
			for i in range(3):
				var rr := fmod(_elapsed * 90.0 + i * 55.0, 165.0)
				var alpha: float = 0.75 * (1.0 - rr / 165.0)
				draw_arc(Vector2.ZERO, rr, 0, TAU, 64, Color(hi, alpha), 3.0)
		"sealed":
			# 结界符：金墨五芒星 + 内环流光（GDD §5.5 封印阵眼）
			var gold: Color = _theme.color("gold_500")
			var pts := PackedVector2Array()
			for i in range(6):
				var a := -PI * 0.5 + i * TAU / 5.0
				pts.append(Vector2(cos(a), sin(a)) * 46.0)
			for i in range(5):
				draw_line(pts[i], pts[i + 2 if i + 2 <= 5 else i + 2 - 5], Color(gold, 0.9), 2.5)
			var shimmer := 0.6 + 0.3 * sin(_elapsed * 3.0)
			draw_arc(Vector2.ZERO, 56.0, 0, TAU, 48, Color(gold, shimmer), 2.0)
		"spilled":
			var grow := minf(_elapsed * 40.0, 60.0)
			var mizu: Color = _theme.color("mizu_500")
			draw_circle(Vector2.ZERO, 40.0 + grow, Color(mizu, 0.28))
			draw_arc(Vector2.ZERO, 40.0 + grow, 0, TAU, 48, Color(mizu, 0.6), 2.0)
	if _hovered and state != "idle":
		draw_string(_font(20), Vector2(-30, -86), display_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, _theme.color("paper_100"))

func _ring(radius: float, c: Color, alpha: float) -> void:
	draw_arc(Vector2.ZERO, radius, 0, TAU, 48, Color(c, alpha), 2.5)

## 火焰贴图懒加载（FileAccess 虚拟文件系统，导出 pck 内可用）
func _fire_texture() -> Texture2D:
	if _fire_tex == null:
		_fire_tex = PngLoader.load_texture(FIRE_TEX_PATH)
	return _fire_tex

func _font(sz: int) -> Font:
	var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
	return f if f else ThemeDB.fallback_font
