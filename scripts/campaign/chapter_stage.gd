# 五夜共用的呈现层。登记/奖励/进度只经ChapterSession提交，不在场景内改模型。
extends Node3D
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Geometry = preload("res://scripts/campaign/chapter_geometry.gd")
const NPCs = preload("res://scripts/campaign/act_one_npcs.gd")
const WorldGeometry = preload("res://scripts/campaign/act_one_geometry.gd")
const Player = preload("res://scripts/exploration_3d/player_controller.gd")
const CameraRig = preload("res://scripts/exploration_3d/camera_rig.gd")
const WorldCamera = preload("res://scripts/campaign/presentation/act_one_camera.gd")
const Layout = preload("res://scripts/campaign/act_one_layout.gd")
const WorldMap = preload("res://scripts/campaign/presentation/act_one_map.gd")
const WorldDepth = preload("res://scripts/campaign/presentation/act_one_depth.gd")
const Dialogue = preload("res://scripts/ui/dialogue_overlay.gd")
const Portraits = preload("res://scripts/characters/identity_portraits.gd")
const Router = preload("res://scripts/rpg/encounter_router.gd")
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
const ThemeData = preload("res://scripts/ui/theme.gd")
@export var night_id := 1
@export var hd2d_experiment := true
var _hd2d_profile: Node3D
var _geometry: Node3D
var _story_markers: Node3D
var _npc_layer: Node3D
var _arrival_checked := false
var config: Dictionary = {}
var player: CharacterBody3D
var camera_rig: Node3D
var controls_enabled := false
var ready_for_play := false
var last_error := ""
var session: RefCounted
var _world: Dictionary = {}
var _mode := "loading"
var _generation := 0
var _closed := false
var _confirm_armed := false
var _transition_busy := false
var _dialogue: CanvasLayer
var _modal: Control
var _modal_buttons: Array[Button] = []
var _hud: Dictionary = {}
var _ui_layer: CanvasLayer
var _modal_layer: CanvasLayer
var _party_panel: CanvasLayer
var _theme: RefCounted
var _tutorial_remaining := 0.0
var _story_definitions: Dictionary = {}
func _ready() -> void:
	_register_input()
	config = Catalog.night(night_id)
	_build_hud()
	session = Session.current
	if session == null:
		_show_error("正式主线会话尚未建立，请从标题开始或继续。", _return_title)
		return
	_geometry = WorldGeometry.build(config)
	add_child(_geometry)
	_refresh_npcs()
	_refresh_story_markers()
	player = Player.new()
	player.name = "Player"
	player.input_enabled = false
	if session.bundle != null: player.shared_definition = session.bundle.get_definition("rinne")
	add_child(player)
	if player.animator.definition.is_empty():
		_show_error("凛音高清素材装配失败，请返回标题重新加载。", _return_title)
		return
	camera_rig = WorldCamera.new()
	camera_rig.name = "CameraRig"
	camera_rig.limits = Vector2(config.bounds.x[0], config.bounds.x[1])
	add_child(camera_rig)
	camera_rig.configure_world(config.bounds)
	player.set_camera_basis(camera_rig.camera.global_basis)
	# 沿用入口参道已验的绘制人物受光与逐脚接地；不套用旧参道的环境光配置。
	player.enable_scene_integration()
	await get_tree().physics_frame
	if _closed or not is_inside_tree(): return
	var world: Dictionary = Router.take_world(Catalog.scene_path(night_id))
	if world.is_empty(): world = session.campaign.safe_snapshot().get("world", {})
	var restored := restore_world(world)
	if not restored.ok:
		_show_error(restored.error, _return_title)
		return
	ready_for_play = true
	set_hd2d_experiment(bool(session.get_meta("hd2d_depth_enabled", hd2d_experiment)))
	_mode = "explore"
	set_controls_enabled(true)
	if not session.get_meta("exploration_tutorial_seen", false):
		_tutorial_remaining = 6.0
		session.set_meta("exploration_tutorial_seen", true)
	_refresh_hud()
	# 仅成功重建后的HUD消费瞬时战果通知；不改剧情、存档或输入模式。
	var unlocked_forms: Array[String] = Router.take_unlocked_forms()
	if unlocked_forms.has("mage"):
		_notice("焰华的法师形态已解锁，可在整备或她行动时自由切换。")
	_start_checkpoint_dialogue.call_deferred()
# 全图沿用同一真实几何。开关只改变景深，不将大地图换回独立小场景。
func set_hd2d_experiment(enabled: bool) -> bool:
	if _closed or camera_rig == null: return false
	if _hd2d_profile == null:
		_hd2d_profile = WorldDepth.new()
		_hd2d_profile.name = "ActOneDepthProfile"
		add_child(_hd2d_profile)
		_hd2d_profile.configure(camera_rig.camera)
	if not _hd2d_profile.set_enabled(enabled): return false
	hd2d_experiment = enabled
	# 仅在当前会话保留视觉选择，战斗/跨夜重建不能偷偷重开；不写故事档。
	if session != null: session.set_meta("hd2d_depth_enabled", enabled)
	if player != null: _hd2d_profile.follow(player.position)
	return true
func _toggle_hd2d_from_hud() -> void:
	if not ready_for_play or _closed or _mode != "explore" or not controls_enabled or _transition_busy or not _confirm_armed: return
	if set_hd2d_experiment(not hd2d_experiment):
		_confirm_armed = false
		_notice("分层景深已开启。" if hd2d_experiment else "分层景深已关闭。")
	_refresh_hud()
func _process(delta: float) -> void:
	if _closed: return
	if _mode == "explore" and controls_enabled: _tutorial_remaining = maxf(0.0, _tutorial_remaining - delta)
	if not Input.is_action_pressed("approach_interact") and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): _confirm_armed = true
	for button in _modal_buttons:
		if is_instance_valid(button): button.disabled = not _confirm_armed or _transition_busy
	if not _modal_buttons.is_empty() and _confirm_armed and not _transition_busy and get_viewport().gui_get_focus_owner() == null:
		_modal_buttons[0].grab_focus()
	if ready_for_play and player != null:
		if controls_enabled and camera_rig != null: camera_rig.follow(player, delta)
		if is_instance_valid(_hd2d_profile): _hd2d_profile.follow(player.position)
		if is_instance_valid(_geometry) and _geometry.has_method("update_visibility"): _geometry.update_visibility(player.position, delta, camera_rig.camera)
		if not _arrival_checked and _mode == "explore" and _intro_area_ready(): _start_checkpoint_dialogue()
	_refresh_hud()
func _unhandled_input(event: InputEvent) -> void:
	if _closed or not ready_for_play: return
	if event is InputEventKey and event.echo: return
	if event.is_action_pressed("approach_pause"):
		get_viewport().set_input_as_handled()
		if _mode == "explore": _open_pause()
		elif _mode in ["pause", "map"]: _resume_explore()
		return
	if event.is_action_pressed("approach_map"):
		get_viewport().set_input_as_handled()
		if _mode == "explore": _open_map()
		elif _mode == "map": _resume_explore()
		return
	if event.is_action_pressed("approach_interact") and controls_enabled and _confirm_armed:
		get_viewport().set_input_as_handled()
		var target := nearest_interaction()
		if not target.is_empty(): request_interaction(str(target.id))
func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled and not _closed
	if player != null: player.set_control_enabled(controls_enabled)
func begin_operation(mode: String) -> bool:
	if _closed or not ready_for_play or _mode not in ["explore", "loading"]: return false
	_generation += 1
	_mode = mode
	_confirm_armed = false
	set_controls_enabled(false)
	return true
func operation_token() -> int:
	return _generation
func callback_valid(token: int) -> bool:
	return not _closed and token == _generation
func shutdown() -> void:
	if _closed: return
	_closed = true
	_generation += 1
	set_controls_enabled(false)
	if is_instance_valid(_dialogue): _dialogue.abort()
func _exit_tree() -> void:
	shutdown()
func export_world() -> Dictionary:
	var world := _world.duplicate(true)
	if player != null:
		world.position = [player.position.x, player.position.y, player.position.z]
		world.facing = player.facing
		if world.has("player_x"): world.player_x = player.position.x
	return world
func restore_world(world: Dictionary) -> Dictionary:
	var errors: Array[String] = Catalog.validate_world(world)
	if not errors.is_empty(): return {"ok": false, "error": "；".join(errors)}
	if int(world.night) != night_id: return {"ok": false, "error": "存档夜晚与当前场景不一致"}
	_world = world.duplicate(true)
	var position := Geometry.vector(world.position)
	var fallback := not _position_reachable(position)
	if fallback: position = Geometry.vector(config.anchors.get(world.get("return_anchor", "spawn"), config.anchors.spawn))
	player.position = position
	player.velocity = Vector3.ZERO
	player.facing = int(world.facing)
	player.animator.set_motion(0, player.facing)
	camera_rig.target = position + Vector3(0, 1.1, 0)
	camera_rig.follow(player, 1.0)
	return {"ok": true, "error": "", "used_fallback": fallback}
func _position_reachable(position: Vector3) -> bool:
	var bounds: Dictionary = config.bounds
	if position.x < bounds.x[0] + 0.23 or position.x > bounds.x[1] - 0.23 or position.z < bounds.z[0] + 0.23 or position.z > bounds.z[1] - 0.23: return false
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 0.7, position - Vector3.UP * 0.5)
	ray.exclude = [player.get_rid()]
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < 0.65 or absf(hit.position.y - position.y) > 0.24: return false
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.215
	capsule.height = 1.34
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, position + Vector3.UP * 0.72)
	query.exclude = [player.get_rid()]
	return space.intersect_shape(query, 1).is_empty()
func apply_committed_world(world: Dictionary) -> void:
	_world = world.duplicate(true)
	_refresh_hud()
func nearest_interaction() -> Dictionary:
	if player == null: return {}
	var best: Dictionary = {}
	var distance := INF
	for target in config.get("interactions", []):
		if target.kind == "dialogue" and _world.get("event_flags", {}).get("dialogue:" + str(target.get("dialogue", "")), false): continue
		if target.kind == "ritual" and _world.get("event_flags", {}).get(str(target.id), false): continue
		var separation := player.position.distance_to(Geometry.vector(target.position))
		if separation <= float(target.get("radius", 1.6)) and separation < distance:
			best = target
			distance = separation
	return best
func interaction_dispatch(id: String) -> String:
	for target in config.get("interactions", []):
		if str(target.id) == id: return str(target.kind)
	return ""
func request_interaction(id: String) -> bool:
	if _mode != "explore" or _closed or not ready_for_play or not _confirm_armed: return false
	var target: Dictionary = {}
	for value in config.get("interactions", []):
		if str(value.id) == id: target = value
	if target.is_empty():
		last_error = "未登记的调查点：" + id
		return false
	for requirement in target.get("requires", []):
		if not _world.get("event_flags", {}).get(requirement, false):
			_notice("请先完成：" + _event_label(str(requirement)))
			return false
	match str(target.kind):
		"npc":
			return _open_npc(target)
		"dialogue":
			var root_id := str(target.get("dialogue", ""))
			if _world.event_flags.get("dialogue:" + root_id, false):
				_notice("这段记录已写入手帖。")
				return false
			return _play_root(root_id)
		"battle":
			if _world.event_flags.get("battle:cleared", false):
				if not begin_operation("record"): return false
				var record := clue_record(night_id, str(target.get("clue_id", config.clue_id)))
				_show_modal(str(record.get("name", target.label)), _record_text(record), [{"text": "返回探索", "call": _resume_explore}])
				return true
			var root_id := str(target.get("dialogue", ""))
			if not root_id.is_empty() and not _world.event_flags.get("dialogue:" + root_id, false):
				return _play_root(root_id, _confirm_battle.bind(str(target.get("clue_id", config.clue_id))))
			_confirm_battle(str(target.get("clue_id", config.clue_id)))
			return true
		"ritual":
			var event_id := str(target.get("event_id", target.id))
			if not event_id.begins_with("ritual:"): event_id = "ritual:" + event_id.trim_prefix("ritual_")
			if _world.event_flags.get(event_id, false):
				_notice("这一步已经完成并保存。")
				return false
			if not begin_operation("ritual"): return false
			var record := clue_record(night_id, "coffin_sendoff")
			_show_modal(str(target.label), _record_text(record), [{"text": "确认" + str(target.label), "call": _commit_ritual.bind(event_id)}, {"text": "稍后再做", "call": _resume_explore}])
			return true
		"exit":
			for requirement in config.required_events:
				if not _world.event_flags.get(requirement, false):
					_notice("出口尚未开放。请先完成：" + _event_label(str(requirement)))
					return false
			if not begin_operation("exit"): return false
			_show_modal("本夜记录已齐", "保存当前进度并继续。", [{"text": "进入结案" if night_id == 5 else "前往下一夜", "call": _advance_night}, {"text": "继续调查", "call": _resume_explore}])
			return true
	return false
# 闲谈使用原和纸对白层，但不走主线完成提交，也不拥有遭遇/奖励接口。
func _open_npc(target: Dictionary) -> bool:
	if not begin_operation("npc"): return false
	_close_modal()
	var token := operation_token()
	_dialogue = Dialogue.new(_theme)
	_dialogue.advance_action = &"approach_interact"
	_dialogue.require_release = true
	_dialogue.portrait_provider = func(_speaker: String) -> Dictionary: return _npc_layer.portrait(str(target.id))
	_dialogue.portrait_failed.connect(_portrait_failed)
	add_child(_dialogue)
	_dialogue.finished.connect(_npc_finished.bind(token), CONNECT_ONE_SHOT)
	var speaker_name: String = str(target.label).split("·")[-1]
	_dialogue.play({"npc_line": {"speaker": str(target.id), "name": speaker_name, "side": "left", "text": str(target.body), "next": ""}}, "npc_line")
	return true
func _npc_finished(token: int) -> void:
	if not callback_valid(token) or not is_inside_tree(): return
	if is_instance_valid(_dialogue): _dialogue.queue_free()
	_dialogue = null
	_resume_explore()
func _refresh_npcs() -> void:
	var party: Array = session.campaign.safe_snapshot().party
	config.interactions = config.interactions.filter(func(target): return target.kind != "npc")
	config.interactions.append_array(NPCs.definitions(night_id, party))
	if _npc_layer == null:
		_npc_layer = NPCs.build(night_id, party)
		add_child(_npc_layer)
	else:
		_npc_layer.refresh_night(night_id, party)
func _intro_area_ready() -> bool:
	if player == null: return false
	if night_id == 1: return true
	var arrival := Geometry.vector(config.anchors.spawn)
	return Vector2(player.position.x - arrival.x, player.position.z - arrival.z).length() <= 6.0
func _start_checkpoint_dialogue() -> void:
	if _closed or _mode != "explore": return
	var state: Dictionary = session.campaign.safe_snapshot()
	# 已提交的结案/战后检查点必须原地恢复；区域门槛只约束首次抵达开场。
	if str(state.get("story_phase", "")) == "ending":
		_arrival_checked = true
		_play_case(str(state.get("resolution", "")))
	elif night_id == 5 and _world.event_flags.get("battle:cleared", false) and not _world.event_flags.get("dialogue:hd5", false):
		_arrival_checked = true
		_play_root("hd5")
	elif _intro_area_ready():
		_arrival_checked = true
		if not str(config.get("intro", "")).is_empty() and not _world.event_flags.get("dialogue:" + str(config.intro), false):
			_play_root(str(config.intro))
static func dialogue_nodes(id: int) -> Dictionary:
	var names := ["test_approach", "corridor_act", "night3_procession", "night4_mirror", "honden_act"]
	if id < 1 or id > 5: return {}
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogues.json"))
	var nodes: Dictionary = source.stages[names[id - 1]].nodes.duplicate(true)
	# 仅呈现副本改变触发顺序，正文与数据编辑源保持原样。
	if id == 5: nodes.hd4.next = ""
	return nodes
func _play_root(root_id: String, afterward: Callable = Callable()) -> bool:
	if not begin_operation("dialogue"): return false
	_close_modal()
	var token := operation_token()
	_dialogue = Dialogue.new(_theme)
	_dialogue.advance_action = &"approach_interact"
	_dialogue.require_release = true
	_dialogue.portrait_provider = _dialogue_portrait
	_dialogue.portrait_failed.connect(_portrait_failed)
	add_child(_dialogue)
	_dialogue.finished.connect(_root_finished.bind(root_id, token, afterward), CONNECT_ONE_SHOT)
	_dialogue.play(dialogue_nodes(night_id), root_id)
	return true
func _root_finished(root_id: String, token: int, afterward: Callable) -> void:
	if not callback_valid(token) or not is_inside_tree(): return
	if is_instance_valid(_dialogue): _dialogue.queue_free()
	_dialogue = null
	_commit_dialogue(root_id, afterward)
func _commit_dialogue(root_id: String, afterward: Callable) -> void:
	var saved: Dictionary = session.commit_event(export_world(), "dialogue:" + root_id)
	if not saved.get("ok", false):
		_show_error(str(saved.get("error", "保存失败")), _commit_dialogue.bind(root_id, afterward))
		return
	apply_committed_world(saved.world)
	_resume_explore()
	if afterward.is_valid(): afterward.call()
func _dialogue_portrait(speaker: String) -> Dictionary:
	var identity := Portraits.identity_for_speaker(speaker)
	# 小夜用已交付半身图；棺守空肖像明确清除，不套用薄荷。
	if speaker == "sayo": return {"ok": true, "texture": load("res://assets/chars/portraits/sayo_half.png"), "key": "sayo:half"}
	if identity.is_empty(): return {"ok": true, "empty": true, "key": "empty:" + speaker}
	if session == null or session.bundle == null: return {"ok": false, "error": "当前人物素材会话已失效"}
	var definition: Dictionary = session.bundle.get_definition(identity)
	if definition.is_empty():
		if not _story_definitions.has(identity): _story_definitions[identity] = Portraits.load_idle_definition(identity)
		definition = _story_definitions[identity]
	return Portraits.from_definition(definition, identity, "portrait")
func _portrait_failed(message: String) -> void:
	_generation += 1
	if is_instance_valid(_dialogue): _dialogue.abort()
	if is_instance_valid(_dialogue): _dialogue.queue_free()
	_dialogue = null
	_show_error(message, _return_title)
func _confirm_battle(clue_id: String) -> void:
	if not begin_operation("confirmation"): return
	var record := clue_record(night_id, clue_id)
	_show_modal(str(record.get("name", "应对异象")), _record_text(record), [{"text": "进入战斗", "call": _begin_battle.bind(clue_id)}, {"text": "暂不应战", "call": _resume_explore}])
static func clue_record(id: int, clue_id: String) -> Dictionary:
	return Catalog.clue(id, clue_id)
static func _record_text(record: Dictionary) -> String:
	return str(record.get("hint", "")) + "\n\n" + str(record.get("resolve_text", ""))
func _begin_battle(clue_id: String) -> void:
	_transition_busy = true
	var started: Dictionary = session.begin_encounter(export_world(), clue_id)
	if not started.get("ok", false):
		_transition_busy = false
		_show_error(str(started.get("error", "战前保存失败")), _begin_battle.bind(clue_id))
		return
	_go_scene(str(started.get("battle_scene", "res://scenes/rpg/battle.tscn")))
func _commit_ritual(event_id: String) -> void:
	var saved: Dictionary = session.commit_event(export_world(), event_id)
	if not saved.get("ok", false):
		_show_error(str(saved.get("error", "仪式保存失败")), _commit_ritual.bind(event_id))
		return
	apply_committed_world(saved.world)
	_resume_explore()
	_notice(_event_label(event_id) + "已完成 · 已保存")
func _advance_night() -> void:
	_transition_busy = true
	var advanced: Dictionary = session.advance_night(export_world())
	if not advanced.get("ok", false):
		_transition_busy = false
		_show_error(str(advanced.get("error", "跨夜保存失败")), _advance_night)
		return
	apply_committed_world(advanced.world)
	if night_id == 5:
		_transition_busy = false
		_close_modal()
		_mode = "explore"
		_play_case("")
	else: _switch_story_world(advanced.world)
# 时间推进沿用同一玩家、相机和物理世界，位置已由模型事务原样保存。
func _switch_story_world(world: Dictionary) -> void:
	_generation += 1
	night_id = int(world.night)
	config = Catalog.night(night_id)
	apply_committed_world(world)
	_arrival_checked = false
	_refresh_npcs()
	_refresh_story_markers()
	_resume_explore()
	_notice("本夜记录已保存。可沿石径继续探索，也可返回已到过的区域。")
	_start_checkpoint_dialogue.call_deferred()
func _refresh_story_markers() -> void:
	if is_instance_valid(_story_markers):
		remove_child(_story_markers)
		_story_markers.queue_free()
	_story_markers = Node3D.new()
	_story_markers.name = "InteractionMarkers"
	add_child(_story_markers)
	for target in config.get("interactions", []):
		if target.kind == "npc": continue
		var marker := Node3D.new()
		marker.name = "Anchor_" + str(target.id).replace(":", "_")
		marker.position = Geometry.vector(target.position)
		_story_markers.add_child(marker)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.27
		torus.outer_radius = 0.32
		ring.mesh = torus
		ring.position.y = 0.035
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("b79e69")
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = material
		marker.add_child(ring)
func _play_case(resolution: String) -> void:
	if not begin_operation("ending"): return
	_close_modal()
	var token := operation_token()
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cases/night_patrol.json"))
	_dialogue = Dialogue.new(_theme)
	_dialogue.advance_action = &"approach_interact"
	_dialogue.require_release = true
	_dialogue.portrait_provider = _dialogue_portrait
	_dialogue.choice_guard = _save_resolution
	_dialogue.choice_failed.connect(_notice)
	_dialogue.portrait_failed.connect(_portrait_failed)
	add_child(_dialogue)
	_dialogue.finished.connect(_case_finished.bind(token), CONNECT_ONE_SHOT)
	var start := "e_send" if resolution == "sendoff" else "e_seal" if resolution == "seal_monitoring" else "t1"
	_dialogue.play(content.nodes, start)
func _save_resolution(next_id: String) -> Dictionary:
	var resolution := "sendoff" if next_id == "e_send" else "seal_monitoring" if next_id == "e_seal" else ""
	if resolution.is_empty(): return {"ok": false, "error": "未登记的结局分支"}
	var saved: Dictionary = session.choose_resolution(export_world(), resolution)
	if saved.get("ok", false): apply_committed_world(saved.world)
	else: last_error = str(saved.get("error", "选择保存失败"))
	return saved
func _case_finished(token: int) -> void:
	if not callback_valid(token) or not is_inside_tree(): return
	if is_instance_valid(_dialogue): _dialogue.queue_free()
	_dialogue = null
	_finish_ending()
func _finish_ending() -> void:
	_transition_busy = true
	var finished: Dictionary = session.finish_ending(export_world())
	if not finished.get("ok", false):
		_transition_busy = false
		_show_error(str(finished.get("error", "结局保存失败")), _finish_ending)
		return
	_go_scene(str(finished.get("next_scene", "res://scenes/campaign/ending.tscn")))
func _open_map() -> void:
	if not begin_operation("map"): return
	_close_modal()
	var canvas_size: Vector2 = get_viewport().get_visible_rect().size
	_modal = Control.new()
	_modal.name = "ActOneMapModal"
	_modal.size = canvas_size
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_layer.add_child(_modal)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.018, 0.035, 0.82)
	shade.size = canvas_size
	_modal.add_child(shade)
	Kit.panel(_modal, Rect2(40, 94, canvas_size.x - 80, canvas_size.y - 188))
	Kit.label(_modal, "第一幕 · 寺域全图", Rect2(80, 122, 1100, 58), 36)
	Kit.label(_modal, "白点：当前位置　金环：本夜调查　青点：可交谈人物　/　沿石径自由往返", Rect2(80, 186, canvas_size.x - 160, 42), 24)
	var map_view := WorldMap.new()
	map_view.name = "WorldMapView"
	map_view.position = Vector2(80, 248)
	map_view.size = Vector2(canvas_size.x - 160, canvas_size.y - 398)
	map_view.player_position = player.position
	map_view.definition = config.duplicate(true)
	map_view.world = _world.duplicate(true)
	map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(map_view)
	var button := Kit.button(_modal, "返回行走 [M]", Rect2(canvas_size.x - 330, 126, 250, 62), _modal_action.bind(_resume_explore, operation_token()))
	button.focus_mode = Control.FOCUS_ALL
	button.disabled = true
	_modal_buttons.append(button)
func _open_pause() -> void:
	if not begin_operation("pause"): return
	_show_pause_menu()
func _show_pause_menu() -> void:
	_show_modal("暂停夜巡", "WASD 移动 · E 调查 · M 地图。释放移动键后可继续行走。", [{"text": "继续探索", "call": _resume_explore}, {"text": "编队 / 形态 / 道具", "call": _open_party}, {"text": "保存当前位置", "call": _save_position}, {"text": "景深：开" if hd2d_experiment else "景深：关", "call": _toggle_depth_from_pause}, {"text": "返回标题", "call": _ask_title}])
func _toggle_depth_from_pause() -> void:
	if _closed or not ready_for_play or _mode != "pause" or _transition_busy: return
	set_hd2d_experiment(not hd2d_experiment)
	_show_pause_menu()
func _open_party() -> void:
	var saved: Dictionary = session.save_world(export_world())
	if not saved.get("ok", false):
		_show_error(str(saved.get("error", "整备前保存失败")), _open_party)
		return
	apply_committed_world(saved.world)
	_close_modal()
	_mode = "party"
	var script: Script = load("res://scripts/campaign/party_panel.gd")
	if script == null:
		_show_error("编队界面未能加载。", _open_party)
		return
	_party_panel = script.new()
	add_child(_party_panel)
	_party_panel.closed.connect(_party_closed, CONNECT_ONE_SHOT)
	_party_panel.open(session)
func _party_closed() -> void:
	if _closed: return
	if is_instance_valid(_party_panel): _party_panel.queue_free()
	_party_panel = null
	apply_committed_world(session.campaign.safe_snapshot().world)
	_refresh_npcs()
	_resume_explore()
func _save_position() -> void:
	var saved: Dictionary = session.save_world(export_world())
	if not saved.get("ok", false):
		_show_error(str(saved.get("error", "位置保存失败")), _save_position)
		return
	apply_committed_world(saved.world)
	_resume_explore()
	_notice("当前位置与队伍已保存。")
func _ask_title() -> void:
	if _closed or _transition_busy or _mode == "title": return
	var previous_mode := _mode
	if _mode == "explore" and not begin_operation("title"): return
	_mode = "title"
	set_controls_enabled(false)
	if is_instance_valid(_dialogue):
		_dialogue.set_process(false)
		_dialogue.set_process_unhandled_input(false)
	_show_modal("返回标题", "保存当前位置后返回标题。尚未结束的演出从最近检查点继续。", [{"text": "保存并返回", "call": _save_and_title}, {"text": "继续夜巡", "call": _cancel_title.bind(previous_mode)}])
func _cancel_title(previous_mode: String) -> void:
	_close_modal()
	if _closed: return
	if is_instance_valid(_dialogue):
		_mode = previous_mode
		_dialogue.set_process(true)
		_dialogue.set_process_unhandled_input(true)
		_dialogue._advance_armed = false
		set_controls_enabled(false)
	elif previous_mode == "pause":
		_mode = "explore"
		_open_pause()
	else: _resume_explore()
func _save_and_title() -> void:
	var saved: Dictionary = session.save_world(export_world())
	if not saved.get("ok", false):
		_show_error(str(saved.get("error", "存档未能写入")), _save_and_title)
		return
	_return_title()
func _return_title() -> void:
	if session != null: session.close()
	_go_scene("res://scenes/campaign/title.tscn")
func _go_scene(path: String) -> void:
	if _closed: return
	_transition_busy = true
	set_controls_enabled(false)
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		_transition_busy = false
		_show_error("场景切换失败：" + path, _go_scene.bind(path))
	else: shutdown()
func _resume_explore() -> void:
	_close_modal()
	if _closed: return
	_mode = "explore"
	_transition_busy = false
	_confirm_armed = false
	set_controls_enabled(true)
func _build_hud() -> void:
	_theme = ThemeData.load_theme()
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 8
	add_child(_ui_layer)
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(root)
	# 无整幅面板，场所与当前目标浮于角落；探索只保留地图/暂停。
	var information := Kit.panel(root, Rect2(28, 20, 590, 78))
	information.name = "NightInformation"
	information.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_hud.title = Kit.muted(Kit.label(root, "", Rect2(42, 22, 226, 28), 20))
	_hud.region = Kit.muted(Kit.label(root, "", Rect2(282, 22, 310, 28), 20))
	_hud.objective = Kit.label(root, "", Rect2(42, 56, 590, 36), 24)
	_hud.objective.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for label in [_hud.title, _hud.region, _hud.objective]:
		label.add_theme_color_override("font_outline_color", Kit.color("ui_ink"))
		label.add_theme_constant_override("outline_size", 5)
	_hud.map = Kit.button(root, "地图 [M]", Rect2(1610, 26, 132, 48), _open_map)
	_hud.pause = Kit.button(root, "暂停 [Esc]", Rect2(1754, 26, 136, 48), _open_pause)
	for tool in [_hud.map, _hud.pause]:
		tool.focus_mode = Control.FOCUS_NONE
		tool.add_theme_font_size_override("font_size", 20)
		Kit.quiet_button(tool)
	_hud.prompt_panel = Kit.panel(root, Rect2(648, 983, 624, 54))
	_hud.prompt = Kit.label(root, "", Rect2(666, 992, 588, 34), 23)
	_hud.prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.notice = Kit.label(root, "", Rect2(400, 148, 1120, 70), 25)
	_hud.notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.notice.add_theme_color_override("font_outline_color", Kit.color("ui_ink"))
	_hud.notice.add_theme_constant_override("outline_size", 6)
	_modal_layer = CanvasLayer.new()
	_modal_layer.layer = 22
	add_child(_modal_layer)
func _refresh_hud() -> void:
	if _hud.is_empty(): return
	_ui_layer.visible = _mode == "explore"
	_hud.title.text = str(config.get("title", "第一幕 · 寺域")).split("·")[0].strip_edges()
	if _hud.has("region") and player != null:
		var names := {"approach": "上山参道", "forecourt": "山门前庭", "corridor": "回廊", "procession": "纸棺庭", "mirror": "镜殿", "honden": "本殿", "central_court": "寺中庭院", "north_walk": "镜殿侧径", "south_walk": "纸棺侧径"}
		_hud.region.text = str(names.get(Layout.region_at(player.position), "寺间石径"))
	if _hud.has("map"): _hud.map.disabled = not ready_for_play or _closed or _mode != "explore" or not controls_enabled or _transition_busy
	var pending: Array[String] = []
	for id in config.get("required_events", []):
		if not _world.get("event_flags", {}).get(id, false): pending.append(_event_label(str(id)))
	var navigation := _navigation_target()
	_hud.objective.text = str(navigation.label) if not str(navigation.label).is_empty() else "回到本夜记事点"
	_hud.objective.tooltip_text = "本夜记事：" + " / ".join(pending)
	_hud.prompt.text = ""
	_hud.prompt.modulate.a = 1.0
	_hud.prompt_panel.modulate.a = 1.0
	if controls_enabled:
		var target := nearest_interaction()
		if not target.is_empty():
			_hud.prompt.add_theme_color_override("font_color", Kit.color("ui_focus"))
			_hud.prompt.text = "E  ·  与" + str(target.label) + "交谈" if target.kind == "npc" else "E  ·  " + str(target.label)
		elif _tutorial_remaining > 0.0:
			_hud.prompt.text = "WASD 行走　·　E 调查　·　M 地图"
			_hud.prompt.add_theme_color_override("font_color", Kit.color("ui_muted"))
			_hud.prompt.modulate.a = minf(1.0, _tutorial_remaining / 1.5)
			_hud.prompt_panel.modulate.a = _hud.prompt.modulate.a
	_hud.prompt_panel.visible = not _hud.prompt.text.is_empty()
func _navigation_target() -> Dictionary:
	var point: Vector3
	var label := ""
	if not _world.get("event_flags", {}).has("dialogue:" + str(config.get("intro", ""))):
		point = Geometry.vector(config.anchors.spawn)
		label = "本夜记述"
	else:
		for target in config.get("interactions", []):
			if target.kind == "npc": continue
			if target.kind == "dialogue" and _world.get("event_flags", {}).has("dialogue:" + str(target.dialogue)): continue
			if target.kind == "battle" and _world.get("event_flags", {}).has("battle:cleared"): continue
			if target.kind == "ritual" and _world.get("event_flags", {}).has(str(target.id)): continue
			var available := true
			for requirement in target.get("requires", []):
				if not _world.get("event_flags", {}).has(requirement): available = false
			if not available: continue
			point = Geometry.vector(target.position)
			label = str(target.label)
			break
	return {"point": point, "label": label}
func _navigation_hint() -> String:
	var target := _navigation_target()
	var label := str(target.label)
	var point: Vector3 = target.point
	if label.is_empty() or player == null: return "WASD 自由行走 / E 调查 / Esc 整备"
	var delta := Vector2(point.x - player.position.x, point.z - player.position.z)
	var direction := ("→" if delta.x > 0 else "←") if absf(delta.x) >= absf(delta.y) else ("↓" if delta.y > 0 else "↑")
	return "WASD 自由行走　%s %s · %d米　/ E 调查" % [direction, label, roundi(delta.length())]
func _notice(message: String) -> void:
	if not _hud.is_empty(): _hud.notice.text = message
func _show_error(message: String, retry: Callable) -> void:
	last_error = message
	set_controls_enabled(false)
	_mode = "error"
	_transition_busy = false
	_show_modal("进度尚未提交", message, [{"text": "重试", "call": retry}, {"text": "返回标题（保留最近存档）", "call": _return_title}])
func _show_modal(title: String, body: String, actions: Array) -> void:
	_close_modal()
	_confirm_armed = false
	var canvas_size: Vector2 = get_viewport().get_visible_rect().size
	_modal = Control.new()
	_modal.size = canvas_size
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_layer.add_child(_modal)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.018, 0.035, 0.7)
	shade.size = canvas_size
	_modal.add_child(shade)
	var panel_width: float = minf(1080.0, canvas_size.x - 64.0)
	var content_width: float = panel_width - 88.0
	var panel: Panel = Kit.panel(_modal, Rect2(0, 0, panel_width, 100))
	var scroll := ScrollContainer.new()
	scroll.name = "ModalBodyScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.clip_contents = true
	_modal.add_child(scroll)
	# 先以真实字体和可用宽度排版。预留滚动条宽度，避免出现滚动条后再次挤窄换行。
	var label: Label = Kit.label(scroll, body, Rect2(0, 0, content_width - 20.0, 0), 26)
	label.name = "ModalBody"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var paragraph := TextParagraph.new()
	paragraph.width = content_width - 20.0
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	paragraph.add_string(body, label.get_theme_font("font"), 26)
	var line_count: int = paragraph.get_line_count()
	var text_height: float = maxf(112.0, paragraph.get_size().y + maxf(0.0, line_count - 1.0) * label.get_theme_constant("line_spacing"))
	label.custom_minimum_size = Vector2(content_width - 20.0, text_height)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var buttons_height: float = maxf(0.0, actions.size() * 80.0 - 16.0)
	var fixed_height: float = 98.0 + 20.0 + buttons_height + 32.0
	var body_height: float = minf(text_height, maxf(96.0, canvas_size.y - 64.0 - fixed_height))
	var height: float = fixed_height + body_height
	var top: float = (canvas_size.y - height) * 0.5
	var left: float = (canvas_size.x - panel_width) * 0.5
	panel.position = Vector2(left, top)
	panel.size = Vector2(panel_width, height)
	Kit.label(_modal, title, Rect2(left + 44, top + 28, content_width, 58), 36)
	scroll.position = Vector2(left + 44, top + 98)
	scroll.size = Vector2(content_width, body_height)
	var token := operation_token()
	for index in range(actions.size()):
		var action: Dictionary = actions[index]
		var button := Kit.button(_modal, str(action.text), Rect2(left + 44, top + 118 + body_height + index * 80, content_width, 64), _modal_action.bind(action.call, token), index == 0)
		button.focus_mode = Control.FOCUS_ALL
		button.disabled = true
		_modal_buttons.append(button)
func _modal_action(action: Callable, token: int) -> void:
	if not callback_valid(token) or not _confirm_armed or _transition_busy: return
	_confirm_armed = false
	for button in _modal_buttons:
		if is_instance_valid(button): button.disabled = true
	if action.is_valid(): action.call()
func _close_modal() -> void:
	if is_instance_valid(_modal): _modal.queue_free()
	_modal = null
	_modal_buttons.clear()
static func _event_label(id: String) -> String:
	var names := {"dialogue:a1": "参道记述", "dialogue:r1": "祖母与顾家旧事", "dialogue:h1": "水钵倒影", "dialogue:c1": "送行钟记述", "dialogue:p1": "抬棺队列", "dialogue:p3": "棺中轻叩", "dialogue:m1": "铜镜与小夜", "dialogue:hd1": "叩门应答", "dialogue:hd5": "棺守让路", "battle:cleared": "应对异象", "ritual:identify": "辨认来者", "ritual:place": "安放旧物", "ritual:guide": "引路"}
	return str(names.get(id, id))
static func _register_input() -> void:
	var bindings := {"approach_left": KEY_A, "approach_right": KEY_D, "approach_forward": KEY_W, "approach_back": KEY_S, "approach_interact": KEY_E, "approach_pause": KEY_ESCAPE, "approach_map": KEY_M}
	for action in bindings:
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = bindings[action]
		InputMap.action_add_event(action, key)
