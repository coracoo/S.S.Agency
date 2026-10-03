# 入口只协调试玩会话；读取失败不会自动新开，资源失败沿用同一安全档。
class_name ApproachTrialMenu
extends Control
const Session = preload("res://scripts/exploration_3d/approach_session.gd")
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
const TITLE_SCENE := "res://scenes/v3/title.tscn"
const WORLD_SCENE := "res://scenes/exploration_3d/approach.tscn"
const BATTLE_SCENE := "res://scenes/rpg/battle.tscn"
var session: RefCounted
var busy := false
var confirmation_pending := false
var retry_available := false
var last_error := ""
var last_response: Dictionary = {}
var _pending_navigation: Dictionary = {}
var _generation := 0
var _leaving := false
var _loading_progress := ""
var _canvas: Control
var _hud: Dictionary = {}

func bind(value: RefCounted) -> void:
	session = value

func _ready() -> void:
	if session == null: session = Session.new()
	_build()
	get_viewport().size_changed.connect(_resize_canvas)
	_resize_canvas()
	_render()
	_hud.new.grab_focus()

func start_new(replace_confirmed: bool) -> Dictionary:
	if busy or _leaving: return _failure("正在进入试玩，请稍候")
	if replace_confirmed and not confirmation_pending: return _report(_failure("请先选择新开试玩，再明确确认替换"))
	if not replace_confirmed and confirmation_pending: return last_response.duplicate(true)
	if session == null: session = Session.new()
	var result: Dictionary = session.start_new(replace_confirmed)
	confirmation_pending = result.get("needs_confirmation", false)
	if not result.ok:
		_report(result)
		if confirmation_pending and not _hud.is_empty(): _hud.cancel.grab_focus()
		return result
	confirmation_pending = false
	return await _prepare_and_enter(result)

func continue_trial() -> Dictionary:
	if busy or _leaving: return _failure("正在进入试玩，请稍候")
	if confirmation_pending: return _failure("请先取消覆盖确认")
	if session == null: session = Session.new()
	var result: Dictionary = session.resume()
	if not result.ok: return _report(result)
	return await _prepare_and_enter(result)

func cancel_overwrite() -> void:
	if busy or not confirmation_pending: return
	confirmation_pending = false
	last_error = ""
	last_response = {}
	_render()
	if not _hud.is_empty(): _hud.new.grab_focus()

func retry_loading() -> Dictionary:
	if busy or _leaving: return _failure("正在加载，请稍候")
	if not retry_available or _pending_navigation.is_empty(): return _report(_failure("没有可重试的载入"))
	return await _prepare_and_enter(_pending_navigation.duplicate(true))

func cancel_loading() -> void:
	_generation += 1
	if session != null: session.close()
	busy = false
	retry_available = false
	confirmation_pending = false
	_pending_navigation.clear()
	_loading_progress = ""
	last_error = ""
	last_response = {"ok": false, "error": "加载已取消", "cancelled": true}
	_render()

func return_title() -> void:
	if _leaving: return
	cancel_loading()
	var result := _navigate_to(TITLE_SCENE)
	if not result.ok: _report(result)

func _prepare_and_enter(result: Dictionary) -> Dictionary:
	_generation += 1
	var generation := _generation
	busy = true
	retry_available = false
	last_error = ""
	_pending_navigation = result.duplicate(true)
	_loading_progress = "正在准备凛音、薄荷、岑照的高清资源……"
	_render()
	# 资源由Session持有，菜单只订阅进度；关闭后旧await不得换场景。
	var bundle: RefCounted = session.bundle
	if bundle != null and not bundle.progress.is_connected(_on_progress): bundle.progress.connect(_on_progress)
	var loaded: Dictionary = await session.prepare_assets()
	if bundle != null and bundle.progress.is_connected(_on_progress): bundle.progress.disconnect(_on_progress)
	if generation != _generation: return {"ok": false, "error": "加载已取消", "cancelled": true}
	busy = false
	if not loaded.ok:
		retry_available = true
		_report(loaded)
		if not _hud.is_empty(): _hud.retry.grab_focus()
		return loaded
	var entered := _navigate_to(str(result.get("next_scene", "")))
	if not entered.ok:
		retry_available = true
		return _report(entered)
	_pending_navigation.clear()
	last_response = result.duplicate(true)
	last_error = ""
	_render()
	return result

func _navigate_to(path: String) -> Dictionary:
	if path not in [WORLD_SCENE, BATTLE_SCENE, TITLE_SCENE]: return _failure("试玩目标场景不受支持，安全存档仍保留")
	# 离树调用仍提供完整结果，实际界面只有成功切场景才移交会话所有权。
	if not is_inside_tree(): return {"ok": true, "error": "", "next_scene": path}
	_leaving = true
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		_leaving = false
		return _failure("场景载入失败（%d），安全存档仍保留。可重试载入或返回标题。" % error)
	return {"ok": true, "error": "", "next_scene": path}

func _report(result: Dictionary) -> Dictionary:
	last_response = result.duplicate(true)
	last_error = str(result.get("error", ""))
	_render()
	return result

func _on_progress(completed: int, total: int) -> void:
	if not busy or _leaving: return
	_loading_progress = "正在准备高清人物资源…… %d / %d" % [completed, total]
	_render()

func _build() -> void:
	_canvas = Control.new()
	_canvas.size = Vector2(1920, 1080)
	add_child(_canvas)
	var backdrop := ColorRect.new()
	backdrop.color = Kit.color("ink_900")
	backdrop.size = _canvas.size
	_canvas.add_child(backdrop)
	Kit.panel(_canvas, Rect2(420, 135, 1080, 810))
	Kit.label(_canvas, "参道篇试玩", Rect2(500, 185, 900, 90), 54)
	Kit.label(_canvas, "调查水钵的倒影 · 一段可保存的参道故事", Rect2(504, 280, 880, 50), 25)
	var detail := Kit.label(_canvas, "固定试用队伍：凛音 · 薄荷 · 岑照\nWASD 移动　E 调查　Esc 暂停\n使用独立试玩存档；不影响原卡牌模式和 RPG 试作进度。", Rect2(504, 345, 880, 132), 23)
	detail.add_theme_color_override("font_color", Kit.color("paper_300"))
	_hud.status = Kit.label(_canvas, "", Rect2(504, 480, 880, 115), 23)
	_hud.status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.new = Kit.button(_canvas, "新开试玩", Rect2(504, 610, 424, 66), func(): await start_new(false), true)
	_hud.continue_button = Kit.button(_canvas, "继续试玩", Rect2(952, 610, 444, 66), func(): await continue_trial())
	_hud.retry = Kit.button(_canvas, "重试载入", Rect2(504, 610, 892, 66), func(): await retry_loading(), true)
	_hud.confirm = Kit.button(_canvas, "确认替换并新开", Rect2(504, 610, 424, 66), func(): await start_new(true), true)
	_hud.cancel = Kit.button(_canvas, "取消，保留进度", Rect2(952, 610, 444, 66), cancel_overwrite)
	_hud.back = Kit.button(_canvas, "返回标题", Rect2(504, 716, 892, 66), return_title)
	Kit.label(_canvas, "完成本段后仍可继续回到参道；后续场景尚未开放。", Rect2(504, 844, 900, 44), 21)

func _render() -> void:
	if _hud.is_empty(): return
	_hud.new.visible = not confirmation_pending and not retry_available
	_hud.continue_button.visible = not confirmation_pending and not retry_available
	_hud.confirm.visible = confirmation_pending
	_hud.cancel.visible = confirmation_pending
	_hud.retry.visible = retry_available
	for key in ["new", "continue_button", "confirm", "cancel", "retry"]: _hud[key].disabled = busy or _leaving
	_hud.back.disabled = _leaving
	_hud.back.text = "取消加载，返回标题" if busy else "返回标题"
	if busy:
		_hud.status.text = _loading_progress
	elif confirmation_pending:
		_hud.status.text = "已有参道试玩进度。新开将替换这一个试玩存档，此操作无法撤销。是否确认替换？"
	elif not last_error.is_empty():
		_hud.status.text = last_error + ("\n可以重试载入，或返回标题后继续同一安全存档。" if retry_available else "\n原存档保持不变。")
	else:
		_hud.status.text = "选择新开试玩，或从上次成功保存的位置继续。"

func _resize_canvas() -> void:
	if _canvas == null: return
	var viewport_size := get_viewport_rect().size
	var factor := minf(viewport_size.x / 1920.0, viewport_size.y / 1080.0)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (viewport_size - Vector2(1920, 1080) * factor) * 0.5

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		# 切场景立即移除当前节点，必须在离场前消费这次按键。
		get_viewport().set_input_as_handled()
		if confirmation_pending: cancel_overwrite()
		else: return_title()

func _exit_tree() -> void:
	_generation += 1
	if not _leaving and session != null: session.close()

func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
