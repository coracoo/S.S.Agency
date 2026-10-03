# 暂停只发出操作意图，舞台负责保存、退出和恢复唯一输入状态。
class_name ApproachPausePanel
extends CanvasLayer
signal save_requested
signal title_requested
signal closed
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
var busy := false
var confirmation_pending := false
var has_unsaved_position := true
var last_error := ""
var _leaving := false
var _escape_armed := false
var _notice := ""
var _canvas: Control
var _hud: Dictionary = {}

func _ready() -> void:
	layer = 50
	_build()
	get_viewport().size_changed.connect(_resize_canvas)
	_resize_canvas()
	hide()

func open(unsaved_position: bool = true) -> void:
	has_unsaved_position = unsaved_position
	busy = false
	confirmation_pending = false
	_leaving = false
	_escape_armed = false
	last_error = ""
	_notice = ""
	show()
	_render()
	if not _hud.is_empty(): _hud.resume.grab_focus()

func set_busy(value: bool) -> void:
	busy = value
	_render()

func request_save() -> void:
	if not visible or busy or confirmation_pending or _leaving: return
	busy = true
	last_error = ""
	_notice = "正在保存当前位置……"
	_render()
	save_requested.emit()

func show_save_result(result: Dictionary) -> void:
	busy = false
	if result.get("ok", false):
		has_unsaved_position = false
		last_error = ""
		_notice = "当前位置已保存。"
	else:
		last_error = str(result.get("error", "保存失败，请重试"))
		_notice = ""
	_render()
	if visible and not _hud.is_empty(): _hud.save.grab_focus()

func show_error(message: String) -> void:
	busy = false
	_leaving = false
	confirmation_pending = false
	last_error = message
	_notice = ""
	_render()

func request_title() -> void:
	if not visible or busy or _leaving: return
	if has_unsaved_position:
		confirmation_pending = true
		_render()
		if not _hud.is_empty(): _hud.cancel.grab_focus()
	else:
		_leave()

func confirm_leave() -> void:
	if not visible or busy or _leaving or not confirmation_pending: return
	_leave()

func cancel_leave() -> void:
	if busy or _leaving: return
	confirmation_pending = false
	_render()
	if not _hud.is_empty(): _hud.resume.grab_focus()

func close() -> void:
	if not visible or busy or _leaving: return
	confirmation_pending = false
	hide()
	closed.emit()

func _leave() -> void:
	_leaving = true
	confirmation_pending = false
	_render()
	title_requested.emit()

func _process(_delta: float) -> void:
	if visible and not Input.is_physical_key_pressed(KEY_ESCAPE): _escape_armed = true

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not _escape_armed or not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_ESCAPE: return
	# closed 的宿主回调可能立即移除场景，先消费按键再通知。
	get_viewport().set_input_as_handled()
	if confirmation_pending: cancel_leave()
	else: close()

func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.025, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	_canvas = Control.new()
	_canvas.size = Vector2(1920, 1080)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	Kit.panel(_canvas, Rect2(555, 228, 810, 624))
	Kit.label(_canvas, "参道 · 暂停", Rect2(610, 268, 700, 70), 44)
	_hud.status = Kit.label(_canvas, "", Rect2(610, 364, 700, 138), 25)
	_hud.status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.save = Kit.button(_canvas, "保存当前位置", Rect2(610, 528, 700, 66), request_save, true)
	_hud.resume = Kit.button(_canvas, "返回游戏", Rect2(610, 623, 336, 64), close)
	_hud.title = Kit.button(_canvas, "返回标题", Rect2(974, 623, 336, 64), request_title)
	_hud.confirm = Kit.button(_canvas, "放弃未保存位置，返回标题", Rect2(610, 528, 700, 66), confirm_leave, true)
	_hud.cancel = Kit.button(_canvas, "取消，继续暂停", Rect2(610, 623, 700, 64), cancel_leave)
	Kit.label(_canvas, "存档只保存已提交进度和安全位置。", Rect2(610, 752, 700, 38), 21)

func _render() -> void:
	if _hud.is_empty(): return
	for key in ["save", "resume", "title"]: _hud[key].visible = not confirmation_pending
	_hud.confirm.visible = confirmation_pending
	_hud.cancel.visible = confirmation_pending
	for key in ["save", "resume", "title", "confirm", "cancel"]: _hud[key].disabled = busy or _leaving
	if confirmation_pending:
		_hud.status.text = "当前位置尚未保存。返回标题后将从上次成功保存的位置继续，未保存的移动会丢失。是否返回？"
	elif not last_error.is_empty():
		_hud.status.text = last_error + "\n原存档保持不变，可重试保存或返回游戏。"
	elif not _notice.is_empty():
		_hud.status.text = _notice
	else:
		_hud.status.text = "探索已暂停。可以保存当前位置，或返回游戏继续调查。"

func _resize_canvas() -> void:
	if _canvas == null: return
	var viewport_size := get_viewport().get_visible_rect().size
	var factor := minf(viewport_size.x / 1920.0, viewport_size.y / 1080.0)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (viewport_size - Vector2(1920, 1080) * factor) * 0.5
