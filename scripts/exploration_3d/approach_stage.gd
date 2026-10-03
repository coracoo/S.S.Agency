# 正式试玩空间独立于美术预览；预览资产只作为不可操作的背景。
extends Node3D
const World = preload("res://scripts/exploration_3d/world_snapshot.gd")
const Session = preload("res://scripts/exploration_3d/approach_session.gd")
const Player = preload("res://scripts/exploration_3d/player_controller.gd")
const Portraits = preload("res://scripts/characters/identity_portraits.gd")
const Router = preload("res://scripts/rpg/encounter_router.gd")
const Ink = preload("res://scripts/ui/ink_transition.gd")
const PausePanel = preload("res://scripts/exploration_3d/pause_panel.gd")
const Flow = preload("res://scripts/exploration_3d/approach_flow.gd")
const Resolver = preload("res://scripts/exploration_3d/interaction_resolver.gd")
const Dialogue = preload("res://scripts/ui/dialogue_overlay.gd")
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
const ThemeData = preload("res://scripts/ui/theme.gd")
const CameraRig = preload("res://scripts/exploration_3d/camera_rig.gd")
var player: CharacterBody3D
var camera_rig: Node3D
var art_stage: Node3D
var config: Dictionary
var _world: Dictionary = {}
var controls_enabled := false
var ready_for_play := false
var last_error := ""
var flow: Node
var _dialogue: CanvasLayer
var _generation := 0
var _hud_root: Control
var _hud: Dictionary = {}
var _modal_layer: CanvasLayer
var _modal: Control
var _modal_buttons: Array[Button] = []
var _theme: RefCounted
var _resume_mode: StringName = &"explore"
var _title_prompt := false
var _transition_busy := false
var _completion_confirm := false
var _pause_panel: CanvasLayer
func _ready() -> void:
	_register_input()
	config = JSON.parse_string(FileAccess.get_file_as_string("res://data/exploration_3d/approach.json"))
	art_stage = preload("res://scenes/preview/act01_approach_3d.tscn").instantiate()
	add_child(art_stage)
	art_stage.hud.hide()
	art_stage.set_process_unhandled_key_input(false)
	art_stage.hero.current = false
	art_stage.inspection.current = false
	var foreground := art_stage.get_node("Model").find_child("50_Path_Boundary_Front", true, false)
	if foreground is Node3D: foreground.hide()
	# 代理地面与可见石板同界；台阶内使用连续坡面，外圈按真实道路折线封闭。
	_add_floor(Vector3(-4.35, -0.07, 0.7), Vector3(9.5, 0.2, 2.9))
	_add_floor(Vector3(3.658, 1.3686, -0.2), Vector3(7.042, 0.2, 3.8), atan2(2.86, 6.435))
	_add_floor(Vector3(8.255, 2.79, -0.45), Vector3(2.87, 0.2, 3.0))
	for index in range(config.walk_polygon.size()):
		var first: Array = config.walk_polygon[index]
		var second: Array = config.walk_polygon[(index + 1) % config.walk_polygon.size()]
		_add_boundary(Vector2(first[0], first[1]), Vector2(second[0], second[1]))
	_add_floor(Vector3(0.12, 0.52, 1.94), Vector3(1.63, 1.02, 1.62))
	_add_floor(Vector3(7.16, 4.0, -2.25), Vector3(3.54, 2.8, 2.62))
	player = Player.new()
	player.name = "Player"
	player.position = _v(config.anchors.spawn)
	player.input_enabled = false
	if Session.current != null and Session.current.bundle != null:
		player.shared_definition = Session.current.bundle.get_definition("rinne")
	add_child(player)
	if player.animator.definition.is_empty():
		_show_rebuild_error("凛音高清素材未能装配，请重试加载")
		return
	player.enable_scene_integration(art_stage)
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	player.set_camera_basis(camera_rig.camera.global_basis)
	await get_tree().physics_frame
	if not is_inside_tree(): return
	var initial: Dictionary = World.initial(config)
	if Session.current != null:
		initial = Router.take_world(World.SCENE_PATH)
		if initial.is_empty(): initial = Session.current.campaign.safe_snapshot().world
	var restored := restore_world(initial)
	if not restored.ok:
		_show_rebuild_error(restored.error)
		return
	ready_for_play = true
	_build_hud()
	if Session.current != null:
		flow = Flow.new()
		add_child(flow)
		flow.bind(Session.current, self)
		flow.dialogue_requested.connect(_play_dialogue)
		flow.inspection_requested.connect(_show_inspection)
		flow.confirmation_requested.connect(_show_encounter_confirmation)
		flow.exit_requested.connect(_show_exit)
		flow.mode_changed.connect(_mode_changed)
		flow.error_raised.connect(_show_event_error)
		flow.notice_requested.connect(_show_notice)
		flow.encounter_requested.connect(_begin_encounter)
		flow.start()
	else:
		set_controls_enabled(true)
	_refresh_hud()
func _process(delta: float) -> void:
	if ready_for_play and controls_enabled: camera_rig.follow(player, delta)
	if flow != null:
		if not Input.is_action_pressed("approach_interact") and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): flow.release_confirm()
		for button in _modal_buttons:
			if is_instance_valid(button): button.disabled = not flow.confirm_armed
		if flow.mode == &"explore" and flow.confirm_armed and not _world.event_flags.has("basin_observed"):
			if Resolver.choose(player.global_position, get_interaction_targets(), _world.event_flags) == "basin": flow.request_interaction("basin")
		_refresh_hud()
func _add_floor(location: Vector3, size: Vector3, slope: float = 0.0) -> void:
	var body := StaticBody3D.new()
	body.position = location
	body.rotation.z = slope
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	add_child(body)
func _add_boundary(first: Vector2, second: Vector2) -> void:
	var center := (first + second) * 0.5
	var offset := second - first
	var body := StaticBody3D.new()
	body.position = Vector3(center.x, 3.0, center.y)
	body.rotation.y = -atan2(offset.y, offset.x)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(offset.length() + 0.1, 10, 0.16)
	collision.shape = box
	body.add_child(collision)
	add_child(body)
func export_world() -> Dictionary:
	var result := _world.duplicate(true)
	if result.is_empty(): result = World.initial(config)
	result.position = [player.position.x, player.position.y, player.position.z]
	result.player_x = player.position.x
	result.facing = player.facing
	result.camera = camera_rig.snapshot()
	return result
func restore_world(world: Dictionary) -> Dictionary:
	var errors := World.validate(world)
	if not errors.is_empty(): return {"ok": false, "error": "；".join(errors), "used_fallback": false}
	var location := _v(world.position)
	var fallback := not _position_reachable(location)
	if fallback: location = _v(config.anchors[world.return_anchor])
	set_controls_enabled(false)
	_world = world.duplicate(true)
	player.position = location
	player.velocity = Vector3.ZERO
	player.facing = world.facing
	player.animator.set_motion(0, player.facing)
	camera_rig.restore(world.camera)
	if fallback:
		var camera: Dictionary = world.camera.duplicate(true)
		camera.target = [location.x, location.y + 1.1, location.z]
		camera_rig.restore(camera)
	return {"ok": true, "error": "", "used_fallback": fallback}
func _position_reachable(location: Vector3) -> bool:
	var bounds: Dictionary = config.bounds
	if location.x < bounds.x[0] + 0.22 or location.x > bounds.x[1] - 0.22 or location.z < bounds.z[0] + 0.22 or location.z > bounds.z[1] - 0.22: return false
	var polygon := PackedVector2Array()
	for point in config.walk_polygon: polygon.append(Vector2(point[0], point[1]))
	if not Geometry2D.is_point_in_polygon(Vector2(location.x, location.z), polygon): return false
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(location + Vector3.UP * 0.65, location - Vector3.UP * 0.45)
	ray.exclude = [player.get_rid()]
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < 0.65 or absf(hit.position.y - location.y) > 0.24: return false
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.215
	capsule.height = 1.34
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, location + Vector3.UP * 0.72)
	query.exclude = [player.get_rid()]
	return space.intersect_shape(query, 1).is_empty()
func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if player != null: player.set_control_enabled(enabled)
func get_interaction_targets() -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	for value in config.targets:
		var target: Dictionary = value.duplicate(true)
		target.position = _v(target.position)
		targets.append(target)
	return targets
static func _v(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])
static func _register_input() -> void:
	var bindings := {"approach_left": KEY_A, "approach_right": KEY_D, "approach_forward": KEY_W, "approach_back": KEY_S, "approach_interact": KEY_E, "approach_pause": KEY_ESCAPE}
	for action in bindings:
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = bindings[action]
		InputMap.action_add_event(action, event)

func get_player_position() -> Vector3:
	return player.global_position
func apply_committed_world(world: Dictionary) -> void:
	_world = world.duplicate(true)
	_refresh_hud()
func _build_hud() -> void:
	_theme = ThemeData.load_theme()
	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	_hud_root = Control.new()
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.size = Vector2(1920, 1080)
	layer.add_child(_hud_root)
	Kit.panel(_hud_root, Rect2(32, 24, 1856, 126))
	_hud.title = Kit.label(_hud_root, "参道篇　／　水钵倒影", Rect2(58, 38, 1000, 48), 32)
	_hud.objective = Kit.label(_hud_root, "", Rect2(58, 92, 1380, 40), 25)
	Kit.button(_hud_root, "暂停 / 保存", Rect2(1460, 46, 186, 72), _open_pause).focus_mode = Control.FOCUS_NONE
	Kit.button(_hud_root, "返回标题", Rect2(1662, 46, 198, 72), _ask_title).focus_mode = Control.FOCUS_NONE
	_hud.prompt = Kit.label(_hud_root, "", Rect2(380, 965, 1160, 70), 30)
	_hud.prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.notice = Kit.label(_hud_root, "", Rect2(350, 190, 1220, 100), 27)
	_hud.notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modal_layer = CanvasLayer.new()
	_modal_layer.layer = 20
	add_child(_modal_layer)
	_pause_panel = PausePanel.new()
	add_child(_pause_panel)
	_pause_panel.save_requested.connect(_save_position)
	_pause_panel.title_requested.connect(_return_title)
	_pause_panel.closed.connect(_resume_pause)
func _refresh_hud() -> void:
	if _hud.is_empty() or _world.is_empty(): return
	var flags: Dictionary = _world.event_flags
	var objective := "靠近水钵，观察冷光"
	if flags.has("approach_complete"): objective = "本段已完成 · 可继续在参道探索"
	elif flags.has("basin_cleared"): objective = "异常已消退 · 前往石阶上方出口"
	elif flags.has("basin_inspected"): objective = "已记录倒影 · 靠近水钵应对异常"
	elif flags.has("basin_observed"): objective = "按 E 调查水钵，记下倒影"
	_hud.objective.text = "目标：%s　　试用编队：凛音 / 薄荷 / 岑照 · L5" % objective
	var prompt := "WASD 移动　/　E 调查　/　Esc 暂停"
	if flow != null and flow.mode != &"explore": prompt = ""
	elif Resolver.choose(player.global_position, get_interaction_targets(), flags) == "basin": prompt = "E　查看水钵记录" if flags.has("basin_inspected") else "E　调查水钵冷光"
	elif Resolver.choose(player.global_position, get_interaction_targets(), flags) == "upper_exit": prompt = "E　参道出口"
	_hud.prompt.text = prompt
	var light := art_stage.get_node_or_null("BasinColdLight")
	if light != null: light.light_energy = 0.16 if flags.has("basin_cleared") else 2.2
func _play_dialogue(start_id: String) -> void:
	_close_modal()
	_generation += 1
	var generation := _generation
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogues.json")).stages.test_approach
	_dialogue = Dialogue.new(_theme)
	_dialogue.advance_action = &"approach_interact"
	_dialogue.require_release = true
	_dialogue.portrait_provider = _dialogue_portrait
	_dialogue.portrait_failed.connect(_portrait_failed)
	add_child(_dialogue)
	# 结束信号绑定到场景生命周期，避免离场时跨节点协程互相等待。
	_dialogue.finished.connect(_dialogue_finished.bind(start_id, generation), CONNECT_ONE_SHOT)
	_dialogue.play(content.nodes, start_id)
func _dialogue_finished(start_id: String, generation: int) -> void:
	if generation != _generation or not is_inside_tree() or flow == null: return
	if is_instance_valid(_dialogue): _dialogue.queue_free()
	_dialogue = null
	flow.finish_dialogue(start_id)
func _dialogue_portrait(speaker: String) -> Dictionary:
	var identity := Portraits.identity_for_speaker(speaker)
	if Session.current == null or Session.current.bundle == null: return {"ok": false, "error": "当前人物素材会话已失效"}
	return Portraits.from_definition(Session.current.bundle.get_definition(identity), identity, "portrait")
func _portrait_failed(message: String) -> void:
	_generation += 1
	if is_instance_valid(_dialogue): _dialogue.abort()
	_show_rebuild_error(message)
func _show_inspection() -> void:
	var clue: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/clues/test_approach.json")).clues[0]
	var flags: Dictionary = _world.event_flags
	var actions: Array[Dictionary] = []
	if not flags.has("basin_inspected"):
		actions = [{"text": "记下线索", "call": flow.finish_inspection}, {"text": "稍后再看", "call": flow.cancel_inspection}]
	elif not flags.has("basin_cleared"):
		actions = [{"text": "应对异常", "call": flow.request_encounter_confirmation}, {"text": "继续探索", "call": flow.cancel_inspection}]
	else:
		actions = [{"text": "继续探索", "call": flow.cancel_inspection}]
	_show_panel(clue.name, clue.hint + "\n\n" + clue.resolve_text, actions)
func _show_encounter_confirmation() -> void:
	_show_panel("应对水钵中的异常？", "将进入独立三人回合战斗。战前状态成功保存后才会转场；可以取消并继续探索。", [{"text": "确认进入战斗", "call": flow.confirm_encounter}, {"text": "取消", "call": flow.cancel_inspection}])
func _show_exit() -> void:
	_completion_confirm = not _world.event_flags.has("approach_complete")
	if not _completion_confirm:
		_show_panel("参道篇已完成", "当前仍可在参道探索，或返回标题。", [{"text": "返回标题", "call": _ask_title}, {"text": "继续探索", "call": flow.cancel_inspection}])
		return
	_show_panel("参道出口", "水钵的异常已经平息。确认完成本段后，可返回标题；回廊与本殿将在后续段落开放。", [{"text": "完成参道篇", "call": complete_segment}, {"text": "继续探索", "call": flow.cancel_inspection}])
func complete_segment() -> Dictionary:
	if Session.current == null or flow == null or flow.mode != &"inspect" or not _completion_confirm or not _world.event_flags.has("basin_cleared") or Resolver.choose(player.global_position, get_interaction_targets(), _world.event_flags) != "upper_exit": return {"ok": false, "error": "需在已解除异常的出口确认完成"}
	var result: Dictionary = Session.current.commit_event(export_world(), "approach_complete")
	if not result.ok:
		_show_panel("本段尚未保存完成", result.error, [{"text": "重试保存", "call": complete_segment}, {"text": "继续探索", "call": flow.cancel_inspection}])
		return result
	_completion_confirm = false
	apply_committed_world(Session.current.campaign.safe_snapshot().world)
	flow.set_mode(&"complete")
	_show_panel("参道篇 · 完成", "异常已平息，案件进度已安全保存。\n感谢体验。后续回廊与本殿尚未在本试玩中开放。", [{"text": "返回标题", "call": _return_title}, {"text": "留在参道", "call": _resume_pause}])
	return result
func _show_panel(title: String, body: String, actions: Array[Dictionary]) -> void:
	_close_modal()
	_modal = Kit.panel(_modal_layer, Rect2(380, 270, 1160, 540), true)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	Kit.label(_modal, title, Rect2(52, 34, 1056, 70), 38, true)
	var label := Kit.label(_modal, body, Rect2(52, 128, 1056, 244), 29, true)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var width := (1056.0 - maxf(0, actions.size() - 1) * 22) / maxf(1, actions.size())
	for index in range(actions.size()):
		var button := Kit.button(_modal, actions[index].text, Rect2(52 + index * (width + 22), 414, width, 80), actions[index].call, index == 0)
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = flow != null and not flow.confirm_armed
		_modal_buttons.append(button)
func _close_modal() -> void:
	_modal_buttons.clear()
	if is_instance_valid(_modal):
		_modal.hide()
		_modal.queue_free()
	_modal = null
func _mode_changed(mode: StringName) -> void:
	if mode == &"explore": _close_modal()
	_refresh_hud()
func _show_notice(message: String) -> void:
	if not _hud.is_empty(): _hud.notice.text = message
func _show_event_error(message: String, event_id: String) -> void:
	last_error = message
	_show_panel("尚未保存", message + "\n原进度未改动。请重试保存，或返回标题后从上次成功保存的位置继续。", [{"text": "重试保存", "call": _retry_event.bind(event_id)}, {"text": "返回标题", "call": _ask_title}])
func _retry_event(event_id: String) -> void:
	if event_id == "basin_inspected": flow.finish_inspection()
	else: flow.finish_dialogue("a1" if event_id == "approach_entered" else "h1")
func _open_pause() -> void:
	if flow == null or flow.mode != &"explore": return
	flow.set_mode(&"pause")
	_pause_panel.open(World.normalize(JSON.parse_string(JSON.stringify(export_world(), "", true, true))) != Session.current.campaign.safe_snapshot().world)
func _save_position() -> void:
	if Session.current == null: return
	var result: Dictionary = Session.current.save_world(export_world())
	last_error = result.error
	if result.ok:
		apply_committed_world(Session.current.campaign.safe_snapshot().world)
		_show_notice("当前位置已保存。")
	if is_instance_valid(_pause_panel): _pause_panel.show_save_result(result)
func _resume_pause() -> void:
	if _title_prompt:
		_cancel_title()
		return
	if flow != null: flow.set_mode(&"explore")
func _ask_title() -> void:
	if flow == null or _title_prompt: return
	if flow.mode in [&"transition", &"battle", &"returning"]: return
	_title_prompt = true
	_resume_mode = flow.mode
	flow.set_mode(&"pause")
	if is_instance_valid(_dialogue): _dialogue.set_process_unhandled_input(false)
	_show_panel("返回标题？", "已保存的案件进度会保留。尚未保存的位置和未读完的对白不会保留。", [{"text": "返回标题", "call": _return_title}, {"text": "取消", "call": _cancel_title}])
func _cancel_title() -> void:
	_title_prompt = false
	_close_modal()
	flow.set_mode(_resume_mode)
	if is_instance_valid(_dialogue):
		_dialogue._advance_armed = false
		_dialogue.set_process_unhandled_input(true)
	elif _resume_mode == &"inspect": _show_inspection()
	elif _resume_mode == &"pause":
		flow.set_mode(&"explore")
		_open_pause()
func _return_title() -> void:
	var session: RefCounted = Session.current
	var error := get_tree().change_scene_to_file("res://scenes/v3/title.tscn")
	if error != OK:
		last_error = "标题未能打开（%d），当前会话仍保留" % error
		if is_instance_valid(_pause_panel) and _pause_panel.visible:
			_pause_panel.show_error(last_error)
		elif _title_prompt:
			_show_panel("标题未能打开", last_error, [{"text": "重试返回标题", "call": _return_title}, {"text": "取消", "call": _cancel_title}])
		else:
			_show_rebuild_error(last_error)
		return
	if session != null: session.close()
func _unhandled_input(event: InputEvent) -> void:
	if flow == null or not ready_for_play: return
	if is_instance_valid(_pause_panel) and _pause_panel.visible: return
	if event is InputEventKey and event.echo: return
	if event.is_action_pressed("approach_interact") and flow.mode == &"explore":
		flow.request_interaction(Resolver.choose(player.global_position, get_interaction_targets(), _world.event_flags))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("approach_pause"):
		if flow.mode == &"explore": _open_pause()
		elif flow.mode == &"pause": _resume_pause()
		elif flow.mode == &"inspect": flow.cancel_inspection()
		get_viewport().set_input_as_handled()
func _exit_tree() -> void:
	_generation += 1
	if flow != null: flow.shutdown()
	if is_instance_valid(_dialogue): _dialogue.abort()

func _begin_encounter(world: Dictionary) -> void:
	if _transition_busy or Session.current == null: return
	_transition_busy = true
	flow.set_mode(&"transition")
	var started: Dictionary = Session.current.begin_encounter(world)
	if not started.ok:
		_transition_busy = false
		flow.set_mode(&"inspect")
		_show_panel("战前状态尚未保存", started.error + "\n原案件进度保持不变。", [{"text": "重试进战保存", "call": _begin_encounter.bind(world)}, {"text": "继续探索", "call": flow.cancel_inspection}])
		return
	_prepare_battle_scene()
func _prepare_battle_scene() -> void:
	if Session.current == null: return
	_transition_busy = true
	flow.set_mode(&"transition")
	_show_panel("准备进入战斗", "正在确认当前三人的高清素材……", [])
	var generation := _generation
	var session: RefCounted = Session.current
	var prepared: Dictionary = await session.prepare_assets()
	if generation != _generation or not is_inside_tree() or Session.current != session: return
	if not prepared.ok:
		_transition_busy = false
		_show_panel("素材加载未完成", prepared.error + "\n战前状态已经保存，再试不会改变队伍、库存或随机种子。", [{"text": "重试加载", "call": _prepare_battle_scene}, {"text": "返回标题", "call": _return_title}])
		return
	_close_modal()
	Ink.transition(get_tree(), _change_to_battle.bind(generation))
func _change_to_battle(generation: int) -> void:
	if generation != _generation or not is_inside_tree(): return
	flow.set_mode(&"battle")
	var error := get_tree().change_scene_to_file("res://scenes/rpg/battle.tscn")
	if error != OK:
		_transition_busy = false
		flow.set_mode(&"transition")
		_show_panel("战斗场景未能打开", "战前状态保持不变，可重试加载或返回标题。", [{"text": "重试加载", "call": _prepare_battle_scene}, {"text": "返回标题", "call": _return_title}])
func _show_rebuild_error(message: String) -> void:
	last_error = message
	set_controls_enabled(false)
	if _hud_root == null: _build_hud()
	_show_panel("参道恢复未完成", message + "\n安全存档保持不变。", [{"text": "重试恢复", "call": _retry_rebuild}, {"text": "返回标题", "call": _return_title}])
func _retry_rebuild() -> void:
	var generation := _generation
	if Session.current != null:
		var loaded: Dictionary = await Session.current.prepare_assets()
		if generation != _generation or not is_inside_tree(): return
		if not loaded.ok:
			_show_rebuild_error(loaded.error)
			return
	var error := get_tree().reload_current_scene()
	if error != OK: _show_rebuild_error("无法重新打开参道（%d）" % error)
