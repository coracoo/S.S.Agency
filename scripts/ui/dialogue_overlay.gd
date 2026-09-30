class_name DialogueOverlay
extends CanvasLayer
## 《逢魔退治帖》v3 剧情对话层（xlsx 配置驱动，data/dialogues.json）。
## 能力：立绘（左右侧滑入/说话者提亮）、姓名牌、打字机（标点停顿、点击快进）、
## 分支选项（按钮 / 数字键）、await 式播放。
## 用法:
##   var dlg := DialogueOverlayScript.new(theme)
##   add_child(dlg)
##   await dlg.play(nodes, start_id)   # nodes = dialogues.json 里某 stage 的 "nodes"
##   dlg.queue_free()

signal finished
signal advanced(node_id: String)

var _theme = null # UITheme（stage_scene 传入，设计令牌禁硬编码）

var _nodes: Dictionary = {}
var _active := false
var _typing := false
var _advance := false # 翻页信号（_unhandled_input 事件驱动，一次按键只算一次）
var _waiting_choice := false
var _choice_next := ""

# 屏幕固定布局（令牌 canvas 基准 1920×1080）
var _portraits: Dictionary = {} # side -> {ctrl, tex, name}
var _name_label: Label = null
var _name_strip: ColorRect = null
var _text_label: Label = null
var _hint_label: Label = null
var _choices_box: VBoxContainer = null
var _root: Control = null

const TYPE_SPEED := 30.0 # 字/秒（CJK 全角一字一符）
const PAUSE_CHARS := "，。！？；：、—…" # 标点后额外停顿
const PORTRAIT_SIZE := Vector2(480, 720)

# 调试参数：--dlg-auto 自动翻页（验证/CI 用）；--dlg-pause-choice 分支处暂停等截图
var _auto := false
var _pause_at_choice := false

func _init(theme = null) -> void:
	layer = 12 # 高于场景与 HUD、低于墨线转场(128)
	_theme = theme
	var args := OS.get_cmdline_user_args()
	_auto = "--dlg-auto" in args
	_pause_at_choice = "--dlg-pause-choice" in args

func _ready() -> void:
	_build_layout()

# ---------- 对外 ----------

## 顺序播放节点链（next 串联；节点带 choices 时等玩家选择）；结束后发 finished
func play(nodes: Dictionary, start_id: String) -> void:
	_nodes = nodes
	_active = true
	var id := start_id
	while _active and not id.is_empty() and _nodes.has(id):
		_choice_next = ""
		_waiting_choice = false
		await _show_node(_nodes[id], id)
		advanced.emit(id)
		if _choice_next != "":
			id = _choice_next
		else:
			id = String(_nodes[id].get("next", ""))
	_active = false
	finished.emit()

## 中途强制结束（切场景等）
func abort() -> void:
	_active = false
	_hide_choices()

# ---------- 内部 ----------

func _build_layout() -> void:
	var cw := float(_theme.canvas("base_width")) if _theme else 1920.0
	var ch := float(_theme.canvas("base_height")) if _theme else 1080.0
	_root = Control.new()
	_root.size = Vector2(cw, ch)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# 对话面板（和纸九图，底部居中）
	var panel := Panel.new()
	panel.position = Vector2(cw * 0.5 - 660, ch - 300)
	panel.size = Vector2(1320, 252)
	if _theme:
		panel.add_theme_stylebox_override("panel", _theme.washi_panel())
	_root.add_child(panel)
	# 姓名牌（朱红小签，面板左上）
	_name_strip = ColorRect.new()
	_name_strip.position = Vector2(36, 16)
	_name_strip.size = Vector2(150, 40)
	panel.add_child(_name_strip)
	_name_label = _mk_label(Vector2(36, 20), 22, "paper_100")
	panel.add_child(_name_label)
	# 正文（打字机）
	_text_label = _mk_label(Vector2(48, 70), 26, "ink_900")
	_text_label.size = Vector2(1224, 160)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(_text_label)
	# 翻页提示 ▼（呼吸闪烁）
	_hint_label = _mk_label(Vector2(1252, 210), 22, "gold_500")
	_hint_label.text = "▼"
	panel.add_child(_hint_label)
	var blink: Tween = _hint_label.create_tween().set_loops()
	blink.tween_property(_hint_label, "modulate:a", 0.15, 0.5)
	blink.tween_property(_hint_label, "modulate:a", 1.0, 0.5)
	# 分支按钮盒（面板上方的屏幕居中）
	_choices_box = VBoxContainer.new()
	_choices_box.position = Vector2(cw * 0.5 - 320, ch - 560)
	_choices_box.size = Vector2(640, 240)
	_choices_box.add_theme_constant_override("separation", 14)
	_root.add_child(_choices_box)

func _mk_label(pos: Vector2, sz: int, color_key: String) -> Label:
	var l := Label.new()
	l.position = pos
	var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", sz)
	if _theme:
		l.add_theme_color_override("font_color", _theme.color(color_key))
	return l

func _show_node(node: Dictionary, node_id: String) -> void:
	# 立绘：换边/换图（滑入 + 说话者提亮，另一方压暗）
	_update_portrait(String(node.get("side", "left")),
		String(node.get("portrait", "")))
	# 姓名牌
	var speaker_color := String(node.get("color", "vermilion_500"))
	_name_label.text = String(node.get("name", ""))
	if _theme:
		_name_strip.color = _theme.color(speaker_color)
		_name_label.add_theme_color_override("font_color",
			Color(_theme.color("paper_100")))
	# 打字机正文（逐字定时器驱动：不依赖 _process，无头截图同样推进）
	var full: String = node.get("text", "")
	_text_label.text = full
	_text_label.visible_characters = 0
	_hint_label.visible = false
	_typing = true
	_advance = false
	var total := full.length()
	for i in range(total):
		if not _typing:
			break
		_text_label.visible_characters = i + 1
		var ch := full.substr(i, 1)
		var delay := 1.0 / TYPE_SPEED
		if PAUSE_CHARS.contains(ch):
			delay += 0.09
		await get_tree().create_timer(delay).timeout
	_typing = false
	_text_label.visible_characters = -1
	# 分支：弹按钮等选择；否则等翻页（快进键不算翻页，需再按一次）
	var choices: Array = node.get("choices", [])
	if not choices.is_empty():
		_show_choices(choices)
		if _auto and not _pause_at_choice:
			await get_tree().create_timer(0.35).timeout
			_pick_choice(String(choices[0].get("next", "")))
		while _waiting_choice and _active:
			await get_tree().process_frame
	else:
		_hint_label.visible = true
		if _auto:
			await get_tree().create_timer(0.18).timeout
			return
		await _wait_advance()

## 等一次翻页输入（_unhandled_input 置 _advance，事件驱动天然消抖）
func _wait_advance() -> void:
	_advance = false
	while _active and not _advance:
		await get_tree().process_frame
	_advance = false

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	var is_advance: bool = event.is_action_pressed("ui_accept") \
		or (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT)
	# 数字键选分支（1-9，echo 过滤长按重复）
	if _waiting_choice and event is InputEventKey and event.pressed and not event.echo:
		var k: int = int(event.keycode) - KEY_1
		if k >= 0 and k < _choices_box.get_child_count():
			var btn := _choices_box.get_child(k) as Button
			if btn:
				btn.pressed.emit()
			get_viewport().set_input_as_handled()
			return
	if not is_advance:
		return
	if _typing:
		# 打字中：本次按键只快进不翻页
		_typing = false
		_text_label.visible_characters = -1
	elif not _waiting_choice:
		_advance = true
	get_viewport().set_input_as_handled()

func _show_choices(choices: Array) -> void:
	_waiting_choice = true
	_choice_next = ""
	for i in range(choices.size()):
		var c: Dictionary = choices[i]
		var btn := Button.new()
		btn.text = "%d  ·  %s" % [i + 1, String(c.get("text", ""))]
		btn.custom_minimum_size = Vector2(640, 56)
		btn.focus_mode = Control.FOCUS_NONE
		var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
		if f:
			btn.add_theme_font_override("font", f)
		btn.add_theme_font_size_override("font_size", 24)
		if _theme:
			btn.add_theme_color_override("font_color", _theme.color("ink_900"))
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(_theme.color("paper_100"), 0.92)
			sb.set_border_width_all(2)
			sb.border_color = _theme.color("gold_500")
			sb.set_corner_radius_all(6)
			btn.add_theme_stylebox_override("normal", sb)
			var sbh := sb.duplicate() as StyleBoxFlat
			sbh.bg_color = Color(_theme.color("gold_500"), 0.28)
			btn.add_theme_stylebox_override("hover", sbh)
		var nxt := String(c.get("next", ""))
		btn.pressed.connect(func() -> void:
			_pick_choice(nxt))
		_choices_box.add_child(btn)

func _pick_choice(next: String) -> void:
	_choice_next = next
	_waiting_choice = false
	_hide_choices()

func _hide_choices() -> void:
	for b in _choices_box.get_children():
		b.queue_free()

## 立绘管理：每侧一个封面裁切图，说话侧提亮、另一侧压暗；换图滑入
func _update_portrait(side: String, portrait_path: String) -> void:
	if portrait_path.is_empty():
		return
	for s in ["left", "right"]:
		var speaking: bool = (s == side)
		var entry: Dictionary = _portraits.get(s, {})
		if entry.is_empty():
			entry = _make_portrait(s)
			_portraits[s] = entry
		var ctrl: PortraitView = entry.get("ctrl")
		if speaking and entry.get("path", "") != portrait_path:
			var tex: Texture2D = PngLoader.load_texture(portrait_path)
			entry["tex"] = tex
			entry["path"] = portrait_path
			ctrl.tex = tex
			ctrl.queue_redraw()
		# 旧 tween 先杀，避免同属性叠帧
		var old: Tween = entry.get("tw")
		if old and old.is_valid():
			old.kill()
		# 提亮/压暗 + 滑入
		var tw: Tween = ctrl.create_tween().set_parallel()
		entry["tw"] = tw
		tw.tween_property(ctrl, "modulate:a", 1.0 if speaking else 0.45, 0.25)
		tw.tween_property(ctrl, "modulate:v", 1.0 if speaking else 0.7, 0.25)
		if speaking and ctrl.modulate.a < 0.9:
			var home: Vector2 = ctrl.get_meta("home")
			ctrl.position = home + Vector2(0, 36)
			tw.tween_property(ctrl, "position", home, 0.35)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _make_portrait(side: String) -> Dictionary:
	var cw := float(_theme.canvas("base_width")) if _theme else 1920.0
	var ch := float(_theme.canvas("base_height")) if _theme else 1080.0
	var ctrl := PortraitView.new()
	ctrl.size = PORTRAIT_SIZE
	# UI 最顶层：立绘沉一层（z=-1），对话面板/文字/选项始终压在立绘之上
	ctrl.z_index = -1
	var home := Vector2(48, ch - 300 - PORTRAIT_SIZE.y + 40)
	if side == "right":
		home.x = cw - 48 - PORTRAIT_SIZE.x
	ctrl.position = home
	ctrl.set_meta("home", home)
	ctrl.modulate.a = 0.0
	_root.add_child(ctrl)
	return {"ctrl": ctrl, "tex": null, "path": "", "tw": null}

## 封面裁切立绘（同 stage_scene.CoverImage 思路：等比铺满裁边）
class PortraitView extends Control:
	var tex: Texture2D = null
	func _draw() -> void:
		if tex == null:
			return
		var tw := float(tex.get_width())
		var th := float(tex.get_height())
		var s: float = maxf(size.x / maxf(tw, 1.0), size.y / maxf(th, 1.0))
		var w := tw * s
		var h := th * s
		draw_texture_rect(tex, Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h), false)
