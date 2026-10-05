# 唯一玩家入口；三维背景没有玩家、对白、输入或进度脚本。
extends Node3D
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
const TitleAtmosphere = preload("res://scripts/campaign/title_atmosphere.gd")
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
var _root: Control
var _status: Label
var _buttons: Array[Button] = []
var _busy := false
var _generation := 0
var _replace_panel: Control
var _session: RefCounted
var _cancel_button: Button
var _entered_scene := false
func _ready() -> void:
	if Session.current != null: Session.current.close()
	add_child(TitleAtmosphere.build())
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.4
	camera.position = Vector3(0, 5.4, 12.0)
	add_child(camera)
	camera.look_at(Vector3(0.7, 1.3, 0))
	camera.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	_root = Control.new()
	_root.size = Vector2(1920, 1080)
	layer.add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.06, 0.065, 0.4)
	shade.size = _root.size
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	Kit.panel(_root, Rect2(1080, 212, 650, 692))
	Kit.muted(Kit.label(_root, "五 夜 · 巡 山", Rect2(1124, 256, 560, 36), 23))
	Kit.label(_root, "逢魔退治帖", Rect2(1118, 303, 560, 104), 70)
	Kit.muted(Kit.label(_root, "第一章 · 棺女", Rect2(1124, 414, 560, 55), 28))
	_buttons.append(Kit.button(_root, "开始新游戏", Rect2(1124, 514, 560, 74), _request_new, true))
	_buttons.append(Kit.button(_root, "继续游戏", Rect2(1124, 608, 560, 66), _continue))
	_buttons.append(Kit.button(_root, "退出游戏", Rect2(1124, 694, 560, 66), func(): get_tree().quit()))
	_status = Kit.muted(Kit.label(_root, "从上山路启程，循着灯火探明五夜旧事。", Rect2(1124, 798, 560, 66), 21))
	_cancel_button = Kit.button(_root, "取消加载", Rect2(1490, 798, 194, 62), _cancel_loading)
	_cancel_button.focus_mode = Control.FOCUS_ALL
	_cancel_button.hide()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for button in _buttons: button.focus_mode = Control.FOCUS_ALL
	_buttons[0].grab_focus()
func _request_new() -> void:
	if _busy: return
	if FileAccess.file_exists(Catalog.SAVE_PATH): _confirm_replace()
	else: _launch_new(false)
func _confirm_replace() -> void:
	if is_instance_valid(_replace_panel): return
	for button in _buttons: button.focus_mode = Control.FOCUS_NONE
	_replace_panel = Control.new()
	_replace_panel.size = Vector2(1920, 1080)
	_root.add_child(_replace_panel)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.76)
	shade.size = _replace_panel.size
	_replace_panel.add_child(shade)
	Kit.panel(_replace_panel, Rect2(480, 322, 960, 436))
	Kit.label(_replace_panel, "替换正式主线存档？", Rect2(528, 358, 864, 64), 38)
	var body := Kit.label(_replace_panel, "当前五夜主线进度将被新游戏替换。确认后才写入，取消会保留当前存档。", Rect2(528, 452, 864, 96), 27)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Kit.button(_replace_panel, "替换并开始", Rect2(528, 606, 410, 74), _launch_new.bind(true), true).focus_mode = Control.FOCUS_ALL
	var keep := Kit.button(_replace_panel, "保留存档", Rect2(982, 606, 410, 74), _cancel_replace)
	keep.focus_mode = Control.FOCUS_ALL
	keep.grab_focus()
func _cancel_replace() -> void:
	if _busy: return
	if is_instance_valid(_replace_panel): _replace_panel.queue_free()
	_replace_panel = null
	for button in _buttons: button.focus_mode = Control.FOCUS_ALL
	_buttons[0].grab_focus()
func _launch_new(replace_confirmed: bool) -> void:
	if _busy: return
	_set_busy(true)
	_generation += 1
	var token := _generation
	_session = Session.new()
	var started: Dictionary = _session.start_new(replace_confirmed)
	if not started.get("ok", false):
		_failed(str(started.get("error", "新游戏未能建立")))
		return
	await _prepare_and_enter(started, token)
func _continue() -> void:
	if _busy: return
	_set_busy(true)
	_generation += 1
	var token := _generation
	_session = Session.new()
	var resumed: Dictionary = _session.resume()
	if not resumed.get("ok", false):
		_failed(str(resumed.get("error", "继续游戏失败")))
		return
	await _prepare_and_enter(resumed, token)
func _prepare_and_enter(result: Dictionary, token: int) -> void:
	_status.text = "正在装配高清人物素材……"
	var prepared: Dictionary = await _session.prepare_assets()
	if token != _generation or not is_inside_tree(): return
	if not prepared.get("ok", false):
		_failed(str(prepared.get("error", "人物素材加载失败")))
		return
	var path := str(result.get("next_scene", result.get("battle_scene", "")))
	if path.is_empty(): path = str(result.get("world", {}).get("scene_path", ""))
	_entered_scene = true
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		_entered_scene = false
		_failed("主线场景未能加载：" + path)
func _set_busy(value: bool) -> void:
	_busy = value
	if _cancel_button != null: _cancel_button.visible = value
	if _status != null: _status.size.x = 348 if value else 560
	for button in _buttons:
		button.disabled = value
		button.focus_mode = Control.FOCUS_ALL if not is_instance_valid(_replace_panel) else Control.FOCUS_NONE
	if value: _cancel_button.grab_focus()
	elif not is_instance_valid(_replace_panel): _buttons[0].grab_focus()
	if is_instance_valid(_replace_panel):
		for child in _replace_panel.get_children():
			if child is Button: child.disabled = value
func _cancel_loading() -> void:
	if not _busy: return
	_generation += 1
	if _session != null: _session.close()
	_session = null
	_status.text = "加载已取消；最近成功保存的主线记录仍可继续。"
	if is_instance_valid(_replace_panel): _replace_panel.queue_free()
	_replace_panel = null
	_set_busy(false)
func _failed(message: String) -> void:
	if _session != null: _session.close()
	_status.text = message
	if is_instance_valid(_replace_panel): _replace_panel.queue_free()
	_replace_panel = null
	_set_busy(false)
func _exit_tree() -> void:
	_generation += 1
	if _busy and not _entered_scene and _session != null: _session.close()
