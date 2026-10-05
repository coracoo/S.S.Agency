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
signal portrait_failed(message: String)
signal choice_failed(message: String)
# 分支切换前同步提交选择；失败时停留原选项，不进入未保存分支。
var choice_guard: Callable = Callable()
var portrait_provider: Callable = Callable()
var portrait_error := ""

var advance_action: StringName = &"ui_accept"
var require_release := false
var _advance_armed := true

var _theme = null # UITheme（stage_scene 传入，设计令牌禁硬编码）

var _nodes: Dictionary = {}
var _active := false
var _typing := false
var _advance := false # 翻页信号（_unhandled_input 事件驱动，一次按键只算一次）
var _waiting_choice := false
var _choice_next := ""
var _playing_id := ""
var _phase := ""
var _remaining_delay := 0.0
var _text_index := 0
var _current_choices: Array = []

# 屏幕固定布局（令牌 canvas 基准 1920×1080）
var _portraits: Dictionary = {} # side -> {ctrl, tex, name}
var _name_label: Label = null
var _name_strip: ColorRect = null
var _text_label: Label = null
var _hint_label: Label = null
var _choices_box: VBoxContainer = null
var _root: Control = null

const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")

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
	_advance_armed = not require_release or not Input.is_action_pressed(advance_action)
	_present_node(start_id)
	if _active: await finished

## 结束信号先释放play等待者；不留下跨离场的逐字计时协程。
func abort() -> void:
	var was_active := _active
	_active = false
	_typing = false
	_advance = false
	_phase = ""
	_hide_choices()
	if was_active: finished.emit()

# ---------- 内部 ----------

func _build_layout() -> void:
	var cw := float(_theme.canvas("base_width")) if _theme else 1920.0
	var ch := float(_theme.canvas("base_height")) if _theme else 1080.0
	_root = Control.new()
	_root.size = Vector2(cw, ch)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# 深色底保留场景气氛；面板/装饰忽略鼠标，点击快进仍交给原输入防连按逻辑。
	var panel := Kit.panel(_root, Rect2(cw * 0.5 - 670, ch - 282, 1340, 238))
	panel.name = "DialoguePanel"
	_name_strip = ColorRect.new()
	_name_strip.position = Vector2(30, 28)
	_name_strip.size = Vector2(3, 28)
	_name_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_name_strip)
	_name_label = _mk_label(Vector2(48, 21), 24, "ui_text")
	_name_label.size = Vector2(620, 42)
	panel.add_child(_name_label)
	_text_label = _mk_label(Vector2(48, 78), 28, "ui_text")
	_text_label.size = Vector2(1244, 110)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.add_theme_constant_override("line_spacing", 8)
	panel.add_child(_text_label)
	_hint_label = _mk_label(Vector2(1010, 192), 19, "ui_muted")
	_hint_label.size = Vector2(280, 30)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.text = "E / 点击　继续 ▾" if advance_action == &"approach_interact" else "确认 / 点击　继续 ▾"
	panel.add_child(_hint_label)
	_choices_box = VBoxContainer.new()
	_choices_box.position = Vector2(cw * 0.5 - 360, ch - 554)
	_choices_box.size = Vector2(720, 240)
	_choices_box.add_theme_constant_override("separation", 12)
	_choices_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_choices_box)

func _mk_label(pos: Vector2, sz: int, color_key: String) -> Label:
	var l := Label.new()
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", sz)
	if _theme:
		l.add_theme_color_override("font_color", _theme.color(color_key))
	return l

# 单一逐帧时钟保持原30字/秒与标点停顿，避免free时悬挂嵌套SceneTreeTimer。
func _present_node(node_id: String) -> void:
	if node_id.is_empty() or not _nodes.has(node_id):
		_active = false
		_phase = ""
		finished.emit()
		return
	_playing_id = node_id
	var node: Dictionary = _nodes[node_id]
	_choice_next = ""
	_waiting_choice = false
	_update_portrait(String(node.get("side", "left")), String(node.get("portrait", "")), String(node.get("speaker", "")))
	if portrait_provider.is_valid() and not portrait_error.is_empty(): return
	_name_label.text = String(node.get("name", ""))
	if _theme:
		_name_strip.color = _theme.color("ui_accent_hover")
		_name_label.add_theme_color_override("font_color", _theme.color("ui_text"))
	_text_label.text = node.get("text", "")
	_text_label.visible_characters = 0
	_hint_label.visible = false
	_typing = true
	_advance = false
	_text_index = 0
	_remaining_delay = 0.0
	_current_choices = node.get("choices", [])
	_phase = "typing"
func _process(delta: float) -> void:
	if not _active: return
	if _phase == "typing":
		if _typing:
			_remaining_delay -= delta
			while _remaining_delay <= 0 and _text_index < _text_label.text.length():
				var character := _text_label.text.substr(_text_index, 1)
				_text_index += 1
				_text_label.visible_characters = _text_index
				_remaining_delay += 1.0 / TYPE_SPEED + (0.09 if PAUSE_CHARS.contains(character) else 0.0)
		if not _typing or _text_index >= _text_label.text.length():
			_typing = false
			_text_label.visible_characters = -1
			if not _current_choices.is_empty():
				_show_choices(_current_choices)
				_phase = "choice"
				_remaining_delay = 0.35
			else:
				_hint_label.visible = true
				_phase = "wait"
				_remaining_delay = 0.18
		return
	if _phase == "choice":
		if _auto and not _pause_at_choice:
			_remaining_delay -= delta
			if _remaining_delay <= 0: _pick_choice(String(_current_choices[0].get("next", "")))
		if not _waiting_choice: _complete_current()
	elif _phase == "wait":
		if _auto: _remaining_delay -= delta
		if _advance or (_auto and _remaining_delay <= 0):
			_advance = false
			_complete_current()
func _complete_current() -> void:
	var id := _playing_id
	advanced.emit(id)
	if not _active: return
	var next: String = _choice_next if not _choice_next.is_empty() else String(_nodes[id].get("next", ""))
	_present_node(next)

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if require_release:
		if event.is_action_released(advance_action) or (event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			_advance_armed = true
			return
		if not _advance_armed: return
	if event is InputEventKey and event.echo: return
	var is_advance: bool = event.is_action_pressed(advance_action) \
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
	if require_release: _advance_armed = false
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
		var btn := Kit.button(_choices_box, "%d  ·  %s" % [i + 1, String(c.get("text", ""))], Rect2(0, 0, 720, 62))
		btn.custom_minimum_size = Vector2(720, 62)
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var nxt := String(c.get("next", ""))
		btn.pressed.connect(func() -> void:
			_pick_choice(nxt))

func _pick_choice(next: String) -> void:
	if not _active or not _waiting_choice: return
	if choice_guard.is_valid():
		var result: Dictionary = choice_guard.call(next)
		if not result.get("ok", false):
			choice_failed.emit(str(result.get("error", "选择未能保存，请重试")))
			return
	_choice_next = next
	_waiting_choice = false
	_hide_choices()

func _hide_choices() -> void:
	for b in _choices_box.get_children():
		b.queue_free()

## 立绘管理：每侧一个封面裁切图，说话侧提亮、另一侧压暗；换图滑入
func _update_portrait(side: String, portrait_path: String, speaker: String = "") -> void:
	var supplied: Dictionary = {}
	var key := portrait_path
	if portrait_provider.is_valid():
		supplied = portrait_provider.call(speaker)
		if supplied.get("ok", false) and supplied.get("empty", false):
			_clear_portrait(side)
			portrait_error = ""
			return
		if not supplied.get("ok", false) or not supplied.get("texture") is Texture2D:
			portrait_error = str(supplied.get("error", "人物立绘尚未就绪"))
			var previous: Dictionary = _portraits.get(side, {})
			if not previous.is_empty():
				previous.tex = null
				previous.ctrl.tex = null
				previous.ctrl.queue_redraw()
			portrait_failed.emit(portrait_error)
			abort()
			return
		key = supplied.get("key", "identity:" + speaker)
		portrait_error = ""
	elif portrait_path.is_empty():
		_clear_portrait(side)
		return
	for s in ["left", "right"]:
		var speaking: bool = (s == side)
		var entry: Dictionary = _portraits.get(s, {})
		if entry.is_empty():
			entry = _make_portrait(s)
			_portraits[s] = entry
		var ctrl: PortraitView = entry.get("ctrl")
		if speaking and entry.get("path", "") != key:
			var tex: Texture2D = supplied.texture if portrait_provider.is_valid() else PngLoader.load_texture(portrait_path)
			entry["tex"] = tex
			entry["path"] = key
			ctrl.tex = tex
			ctrl.flip_h = portrait_provider.is_valid() and side == "right"
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

func _clear_portrait(side: String) -> void:
	var entry: Dictionary = _portraits.get(side, {})
	if entry.is_empty(): return
	var tween: Tween = entry.get("tw")
	if tween != null and tween.is_valid(): tween.kill()
	entry.tex = null
	entry.path = ""
	entry.ctrl.tex = null
	entry.ctrl.modulate.a = 0.0
	entry.ctrl.queue_redraw()

func _make_portrait(side: String) -> Dictionary:
	var cw := float(_theme.canvas("base_width")) if _theme else 1920.0
	var ch := float(_theme.canvas("base_height")) if _theme else 1080.0
	var ctrl := PortraitView.new()
	ctrl.size = PORTRAIT_SIZE
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var flip_h := false
	func _draw() -> void:
		if tex == null:
			return
		if flip_h: draw_set_transform(Vector2(size.x, 0), 0.0, Vector2(-1, 1))
		var tw := float(tex.get_width())
		var th := float(tex.get_height())
		var s: float = maxf(size.x / maxf(tw, 1.0), size.y / maxf(th, 1.0))
		var w := tw * s
		var h := th * s
		draw_texture_rect(tex, Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h), false)
