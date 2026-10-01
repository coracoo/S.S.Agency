# 显式启用的新模式会话，不注册autoload；只把现有战斗触发映射到RPG遭遇。
class_name RpgEncounterRouter
extends RefCounted

const Catalog = preload("res://scripts/rpg/catalog.gd")
const Campaign = preload("res://scripts/rpg/campaign.gd")
const Battle = preload("res://scripts/rpg/battle_engine.gd")
const Policy = preload("res://scripts/rpg/enemy_policy.gd")
const Replay = preload("res://scripts/rpg/replay.gd")
static var session: RefCounted = null
var campaign: RefCounted
var engine: RefCounted = null
var last_error := ""
var _catalog: RefCounted
var _setup: Dictionary = {}
var _initial: Dictionary = {}
var _return_world: Dictionary = {}
var _ritual_context: Dictionary = {}

func _init(campaign_model: RefCounted = null, catalog: RefCounted = null) -> void:
	_catalog = catalog
	if _catalog == null:
		_catalog = Catalog.new()
		_catalog.load_all()
	campaign = campaign_model if campaign_model != null else Campaign.new(_catalog)

static func activate(router: RefCounted) -> void:
	session = router

static func enabled() -> bool:
	return session != null

static func clear_session() -> void:
	session = null

static func take_world(scene_path: String) -> Dictionary:
	if session == null or session._return_world.get("scene_path", "") != scene_path: return {}
	var world: Dictionary = session._return_world.duplicate(true)
	session._return_world = {}
	return world

func supports(source_scene: String, battle_scene: String, pending_clue_id: String = "") -> bool:
	return not _route(source_scene, battle_scene, pending_clue_id).is_empty()

func begin(source_scene: String, battle_scene: String, world: Dictionary, pending_clue_id: String = "") -> Dictionary:
	var route := _route(source_scene, battle_scene, pending_clue_id)
	if route.is_empty(): return {"ok": false, "handled": false, "error": "未映射战斗，沿用现有入口"}
	if world.get("scene_path") != source_scene: return _failure("来源场景与世界快照不符")
	var patch: Dictionary = {}
	if not pending_clue_id.is_empty(): patch["resolved"] = {pending_clue_id: true}
	var started: Dictionary = campaign.begin_battle(route.encounter_id, world, patch)
	if not started.ok: return started
	_setup = started.duplicate(true)
	_initial = {}
	engine = null
	started["handled"] = true
	started["battle_scene"] = "res://scenes/rpg/battle.tscn"
	return started

func open_preparation(world: Dictionary) -> Dictionary:
	var saved: Dictionary = campaign.save_exploration(world)
	if not saved.ok: return saved
	_return_world = {}
	saved["next_scene"] = "res://scenes/rpg/launcher.tscn"
	return saved

func resume_exploration() -> Dictionary:
	var safe: Dictionary = campaign.snapshot()
	if not campaign.can_use_outside_items() or safe.get("world", {}).is_empty(): return _failure("当前没有可返回的安全探索世界")
	_return_world = safe.world.duplicate(true)
	return {"ok": true, "error": "", "next_scene": safe.world.scene_path}

func supports_ritual(source_scene: String, ritual_scene: String, clue_id: String = "") -> bool:
	return not _route(source_scene, ritual_scene, clue_id, "ritual_routes").is_empty()

func begin_ritual(source_scene: String, ritual_scene: String, world: Dictionary, clue_id: String = "") -> Dictionary:
	var route := _route(source_scene, ritual_scene, clue_id, "ritual_routes")
	if route.is_empty(): return _failure("未登记的仪式入口")
	if world.get("scene_path") != source_scene or not world.get("resolved") is Dictionary: return _failure("仪式世界与来源不符")
	var candidate := world.duplicate(true)
	# 旧舞台在特写落幕/进入仪式时标记送行线索，不改成RPG胜负奖励。
	candidate.resolved[route.clue_id] = true
	var saved: Dictionary = campaign.begin_ritual(candidate)
	if not saved.ok: return saved
	_ritual_context = {"scene_path": ritual_scene, "source_scene": source_scene}
	_return_world = {}
	engine = null
	_initial = {}
	_setup = {}
	saved["scene_path"] = ritual_scene
	return saved

func ritual_active(ritual_scene: String) -> bool:
	return _ritual_context.get("scene_path", "") == ritual_scene and campaign.snapshot().get("phase") == "ritual"

func finish_ritual(ritual_scene: String) -> Dictionary:
	if not ritual_active(ritual_scene): return _failure("仪式返回上下文不符")
	var saved: Dictionary = campaign.finish_ritual()
	if not saved.ok: return saved
	_return_world = saved.world.duplicate(true)
	saved["next_scene"] = _ritual_context.source_scene
	_ritual_context = {}
	return saved

# 独立首测也可采用campaign.begin_battle的返回值，不需要编造探索世界。
func adopt_battle(started: Dictionary) -> Dictionary:
	if not started.get("ok", false) or not started.get("setup") is Dictionary: return _failure("没有有效战前设置")
	var safe: Dictionary = campaign.safe_snapshot()
	if safe.get("pending_battle", {}).get("battle_id") != started.get("battle_id"): return _failure("设置不属于当前队伍战斗")
	_setup = started.duplicate(true)
	engine = null
	_initial = {}
	return {"ok": true, "error": ""}

func create_engine() -> RefCounted:
	if engine != null: return engine
	if _setup.is_empty():
		last_error = "尚未准备遭遇"
		return null
	var candidate := Battle.new(_catalog)
	candidate.set_policy(Policy.new())
	var started: Dictionary = candidate.start(_setup.setup, _setup.seed)
	if not started.started:
		last_error = "；".join(started.reasons)
		return null
	engine = candidate
	_initial = candidate.snapshot()
	last_error = ""
	return engine

func capture_replay(battle_engine: RefCounted) -> Dictionary:
	if _initial.is_empty() or battle_engine != engine: return {}
	var current: Dictionary = battle_engine.snapshot()
	var commands: Array[Dictionary] = []
	for command in current.command_log.slice(_initial.command_log.size()): commands.append(command.duplicate(true))
	var events: Array[Dictionary] = []
	for event in current.event_log:
		if event.sequence > _initial.event_sequence: events.append(event.duplicate(true))
	return Replay.record(_initial, commands, events)

func result_from_engine() -> Dictionary:
	if engine == null or _setup.is_empty(): return {}
	var current: Dictionary = engine.snapshot()
	if current.outcome.is_empty(): return {}
	var roster: Array[Dictionary] = []
	for id in campaign.safe_snapshot().party: roster.append(current.actors[id].duplicate(true))
	var victory: bool = current.outcome == "victory"
	return {"battle_id": _setup.battle_id, "outcome": current.outcome, "roster": roster, "inventory": current.inventory.duplicate(true), "xp": _setup.xp if victory else 0, "story_patch": _setup.story_patch.duplicate(true) if victory else {}, "replay": capture_replay(engine)}

func finish(result: Dictionary) -> Dictionary:
	var applied: Dictionary = campaign.apply_result(result)
	if not applied.ok or applied.already_applied or result.get("outcome") != "victory": return applied
	var world: Dictionary = campaign.safe_snapshot().world
	_return_world = world.duplicate(true)
	applied["world"] = world.duplicate(true)
	applied["next_scene"] = applied.story_patch.get("next_scene", world.get("scene_path", "res://scenes/rpg/launcher.tscn"))
	return applied

func retry() -> Dictionary:
	var started: Dictionary = campaign.retry_battle()
	if not started.ok: return started
	adopt_battle(started)
	return started

# 从标题继续只采用持久安全档；不把失败战斗或临时视图写回存档。
func load_safe_run() -> Dictionary:
	var loaded: Dictionary = campaign.load_run()
	if not loaded.ok: return loaded
	engine = null
	_initial = {}
	_setup = {}
	_ritual_context = {}
	var safe: Dictionary = campaign.safe_snapshot()
	loaded["pending_battle"] = not safe.pending_battle.is_empty()
	if loaded.pending_battle:
		var retried: Dictionary = campaign.retry_battle()
		if not retried.ok: return retried
		adopt_battle(retried)
		_return_world = {}
		loaded["next_scene"] = "res://scenes/rpg/battle.tscn"
	else:
		_return_world = safe.world.duplicate(true)
		loaded["next_scene"] = safe.get("return_scene", "")
		if loaded.next_scene.is_empty(): loaded.next_scene = safe.world.get("scene_path", "res://scenes/rpg/launcher.tscn")
	return loaded

func _route(source: String, battle: String, clue: String, route_field: String = "scene_routes") -> Dictionary:
	for encounter in _catalog.get_all("encounters"):
		for route in encounter.get(route_field, []):
			if route.source_scene == source and route.battle_scene == battle and (route.get("clue_id", "") == clue or (route_field == "ritual_routes" and clue.is_empty())):
				return {"encounter_id": encounter.id, "clue_id": route.get("clue_id", "")}
	return {}

func _failure(message: String) -> Dictionary:
	last_error = message
	return {"ok": false, "handled": true, "error": message}
