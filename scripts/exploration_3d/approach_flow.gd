# 唯一输入状态；只协调剧情事务，不持有第二份队员资源。
extends Node
signal encounter_requested(world: Dictionary)
signal dialogue_requested(node_id: String)
signal inspection_requested
signal confirmation_requested
signal exit_requested
signal mode_changed(mode: StringName)
signal error_raised(message: String, pending_event: String)
signal notice_requested(message: String)
const Resolver = preload("res://scripts/exploration_3d/interaction_resolver.gd")
const MODES := [&"explore", &"dialogue", &"inspect", &"pause", &"transition", &"battle", &"returning", &"complete"]
var mode: StringName = &"returning"
var confirm_armed := false
var generation := 0
var _session: RefCounted
var _stage: Node
var _live := false
var _dialogue_id := ""
var _confirmation_open := false
func bind(session: RefCounted, stage: Node) -> void:
	_session = session
	_stage = stage
	_live = true
	generation += 1
	set_mode(&"returning")
func start() -> void:
	if not _live: return
	if not _flags().has("approach_entered"):
		_open_dialogue("a1")
	else:
		set_mode(&"explore")
func set_mode(value: StringName) -> void:
	if not MODES.has(value): return
	mode = value
	confirm_armed = false
	if _stage != null: _stage.set_controls_enabled(_live and mode == &"explore")
	mode_changed.emit(mode)
func release_confirm() -> void:
	if _live: confirm_armed = true
func request_interaction(id: String) -> Dictionary:
	if not _live or mode != &"explore" or not confirm_armed: return _fail("当前输入尚未开放")
	if id.is_empty() or Resolver.choose(_stage.get_player_position(), _stage.get_interaction_targets(), _flags()) != id: return _fail("交互点不在可达范围内")
	confirm_armed = false
	if id == "basin":
		if not _flags().has("basin_observed"):
			_open_dialogue("h1")
		else:
			_confirmation_open = false
			set_mode(&"inspect")
			inspection_requested.emit()
	elif id == "upper_exit":
		if not _flags().has("basin_cleared"):
			notice_requested.emit("先调查水钵，并处理其中的异常。")
		else:
			set_mode(&"inspect")
			exit_requested.emit()
	return _ok()
func finish_dialogue(node_id: String) -> Dictionary:
	if not _live or mode != &"dialogue" or node_id != _dialogue_id: return _fail("对白已经失效")
	var event_id := "approach_entered" if node_id == "a1" else "basin_observed"
	var result := _commit_event(event_id)
	if result.ok:
		_dialogue_id = ""
		set_mode(&"explore")
	return result
func finish_inspection() -> Dictionary:
	if not _live or mode != &"inspect" or _confirmation_open: return _fail("当前不是调查记录")
	var result := _ok()
	if not _flags().has("basin_inspected"): result = _commit_event("basin_inspected")
	if result.ok: set_mode(&"explore")
	return result
func request_encounter_confirmation() -> Dictionary:
	if not _live or mode != &"inspect" or not confirm_armed or not _flags().has("basin_inspected") or _flags().has("basin_cleared"): return _fail("尚不能应对异常")
	_confirmation_open = true
	confirm_armed = false
	confirmation_requested.emit()
	return _ok()
func confirm_encounter() -> Dictionary:
	if not _live or mode != &"inspect" or not confirm_armed or not _confirmation_open or not _flags().has("basin_inspected") or _flags().has("basin_cleared"): return _fail("遭遇确认无效或重复")
	_confirmation_open = false
	set_mode(&"transition")
	encounter_requested.emit(_stage.export_world())
	return _ok()
func cancel_inspection() -> void:
	if not _live or mode != &"inspect": return
	_confirmation_open = false
	set_mode(&"explore")
func shutdown() -> void:
	_live = false
	generation += 1
	confirm_armed = false
	if _stage != null: _stage.set_controls_enabled(false)
func _open_dialogue(node_id: String) -> void:
	_dialogue_id = node_id
	set_mode(&"dialogue")
	dialogue_requested.emit(node_id)
func _flags() -> Dictionary:
	return _session.campaign.safe_snapshot().get("world", {}).get("event_flags", {})
func _commit_event(event_id: String) -> Dictionary:
	var result: Dictionary = _session.commit_event(_stage.export_world(), event_id)
	if result.ok:
		_stage.apply_committed_world(_session.campaign.safe_snapshot().world)
	else:
		error_raised.emit(result.error, event_id)
	return result
func _ok() -> Dictionary: return {"ok": true, "error": ""}
func _fail(message: String) -> Dictionary: return {"ok": false, "error": message}
