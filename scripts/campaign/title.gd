# 唯一玩家入口；三维背景没有玩家、对白、输入或进度脚本。
extends Node3D
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
const TitleAtmosphere = preload("res://scripts/campaign/title_atmosphere.gd")
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
const Art = preload("res://scripts/campaign/presentation/night_menu_art.gd")
var _root: Control
var _menu: Control
var _shade: ColorRect
var _replace_card: Panel
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
	layer.add_child(_root)
	_shade = ColorRect.new()
	_shade.color = Color(0.025, 0.06, 0.065, 0.4)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_shade)
	_menu = Control.new()
	_menu.size = Vector2(700, 842)
	_root.add_child(_menu)
	Art.panel(_menu, Rect2(0, 0, 700, 842)).name = "TitlePanel"
	var eyebrow := Kit.label(_menu, "五 夜 · 巡 山", Rect2(60, 56, 580, 36), 23)
	eyebrow.add_theme_color_override("font_color", Color("d8c4a0"))
	Kit.label(_menu, "逢魔退治帖", Rect2(54, 111, 592, 104), 70)
	Kit.label(_menu, "第一章 · 棺女", Rect2(60, 224, 580, 48), 28).add_theme_color_override("font_color", Color("d8c4a0"))
	_buttons.append(Art.button(_menu, "开始新游戏", Rect2(60, 312, 580, 80), _request_new, true))
	_buttons.append(Art.button(_menu, "继续游戏", Rect2(60, 408, 580, 80), _continue))
	_buttons.append(Art.button(_menu, "退出游戏", Rect2(60, 504, 580, 80), func(): get_tree().quit()))
	Art.panel(_menu, Rect2(48, 612, 604, 172), true).name = "TitleNotice"
	_status = Kit.label(_menu, "从上山路启程，循着灯火探明五夜旧事。", Rect2(76, 638, 548, 120), 22)
	_status.add_theme_color_override("font_color", Color("e3d8bf"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cancel_button = Art.button(_menu, "取消加载", Rect2(76, 688, 548, 72), _cancel_loading)
	_cancel_button.focus_mode = Control.FOCUS_ALL
	_cancel_button.hide()
	for button in _buttons: button.focus_mode = Control.FOCUS_ALL
	get_viewport().size_changed.connect(_layout)
	_layout()
	_buttons[0].grab_focus()
func _layout() -> void:
	if _root == null: return
	_root.size = get_viewport().get_visible_rect().size
	_shade.size = _root.size
	_menu.position = Vector2(_root.size.x - 840, (_root.size.y - _menu.size.y) * 0.5)
	if is_instance_valid(_replace_panel):
		_replace_panel.size = _root.size
		_replace_panel.get_child(0).size = _root.size
		var origin := (_root.size - Vector2(1020, 488)) * 0.5
		_replace_card.position = origin
		for child in _replace_panel.get_children():
			if child.has_meta("card_offset"): child.position = origin + child.get_meta("card_offset")
func _request_new() -> void:
	if _busy: return
	if FileAccess.file_exists(Catalog.SAVE_PATH): _confirm_replace()
	else: _launch_new(false)
func _confirm_replace() -> void:
	if is_instance_valid(_replace_panel): return
	for button in _buttons: button.focus_mode = Control.FOCUS_NONE
	_replace_panel = Control.new()
	_root.add_child(_replace_panel)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.76)
	_replace_panel.add_child(shade)
	_replace_card = Art.panel(_replace_panel, Rect2(0, 0, 1020, 488))
	_replace_card.name = "ReplaceSavePanel"
	var heading := Kit.label(_replace_panel, "替换正式主线存档？", Rect2(0, 0, 904, 64), 38)
	heading.set_meta("card_offset", Vector2(58, 50))
	var body := Kit.label(_replace_panel, "当前五夜主线进度将被新游戏替换。确认后才写入，取消会保留当前存档。", Rect2(0, 0, 904, 132), 27)
	body.set_meta("card_offset", Vector2(58, 146))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var replace := Art.button(_replace_panel, "替换并开始", Rect2(0, 0, 432, 84), _launch_new.bind(true), true)
	replace.set_meta("card_offset", Vector2(58, 340))
	var keep := Art.button(_replace_panel, "保留存档", Rect2(0, 0, 432, 84), _cancel_replace)
	keep.set_meta("card_offset", Vector2(530, 340))
	for pair in [[replace, keep], [keep, replace]]:
		pair[0].focus_mode = Control.FOCUS_ALL
		for direction in ["next", "previous", "neighbor_left", "neighbor_right", "neighbor_top", "neighbor_bottom"]:
			pair[0].set("focus_" + direction, pair[0].get_path_to(pair[1]))
	_layout()
	keep.grab_focus()
func _cancel_replace() -> void:
	if _busy: return
	if is_instance_valid(_replace_panel): _replace_panel.queue_free()
	_replace_panel = null
	for button in _buttons: button.focus_mode = Control.FOCUS_ALL
	_buttons[0].grab_focus()
func _launch_new(replace_confirmed: bool) -> void:
	if _busy: return
	# 确认后先收起遮罩，取消加载必须仍可点击。
	if is_instance_valid(_replace_panel): _cancel_replace()
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
	if _status != null:
		# 先换短加载文案，再缩高度，避免沿用上次多行错误的最小高度。
		if value: _status.text = "正在装配高清人物素材……"
		_status.position.y = 632 if value else 638
		_status.size = Vector2(548, 44 if value else 120)
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
