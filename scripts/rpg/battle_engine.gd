# 不依赖场景树的权威战斗模型。一次合法确认以副本完成整批效果后原子发布。
class_name RpgBattleEngine
extends RefCounted

const Catalog = preload("res://scripts/rpg/catalog.gd")
const State = preload("res://scripts/rpg/battle_state.gd")
const Commands = preload("res://scripts/rpg/command_rules.gd")
const Resolver = preload("res://scripts/rpg/effect_resolver.gd")
const Status = preload("res://scripts/rpg/status_rules.gd")

var _catalog: RefCounted
var _state: Dictionary = {}
# 策略是进程依赖，绝不进入模型快照；恢复不移除已注册策略。
var _policy: RefCounted
var last_errors: Array[String] = []

func _init(catalog: RefCounted = null) -> void:
	_catalog = catalog
	if _catalog == null:
		_catalog = Catalog.new()
		last_errors = _catalog.load_all()

func set_policy(policy: RefCounted) -> void:
	_policy = policy

func start(setup: Dictionary, seed_value: int) -> Dictionary:
	if not setup.get("actors") is Dictionary or not setup.get("inventory") is Dictionary:
		last_errors = ["setup必须包含actors与inventory字典"]
		return {"started": false, "reasons": last_errors.duplicate(), "events": [], "revision": _state.get("revision", 0)}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var candidate := {"schema_version": 1, "rules_version": _catalog.rules_version, "revision": 0, "seed": seed_value, "rng_state": str(rng.state), "round": 0, "phase": "preparation", "queue": [], "queue_index": 0, "active_actor_id": "", "actors": setup.get("actors", {}).duplicate(true), "inventory": setup.get("inventory", {}).duplicate(true), "outcome": "", "accepted_commands": {}, "slot_token": {}, "event_sequence": 0, "event_log": [], "command_log": []}
	last_errors = State.validate(candidate)
	if not last_errors.is_empty(): return {"started": false, "reasons": last_errors.duplicate(), "events": [], "revision": 0}
	var events: Array[Dictionary] = []
	_policy_events("on_battle_start", [candidate, _catalog], events)
	_append_events(candidate, events)
	last_errors = State.validate(candidate)
	if not last_errors.is_empty(): return {"started": false, "reasons": last_errors.duplicate(), "events": [], "revision": 0}
	_state = candidate
	return {"started": true, "reasons": [], "events": events.duplicate(true), "revision": 0}

func preview(command: Dictionary) -> Dictionary:
	var result := Commands.preview(_state, command, _catalog)
	if result.legal and _policy != null and _policy.has_method("validate_command"):
		var reasons: Array = _policy.call("validate_command", snapshot(), command)
		if not reasons.is_empty():
			result.legal = false
			result.reasons.append_array(reasons)
	return result

func submit(command: Dictionary) -> Dictionary:
	var preview_result := preview(command)
	if not preview_result.legal:
		return {"accepted": false, "reasons": preview_result.reasons, "events": [], "revision": _state.get("revision", 0)}
	var candidate := _state.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.state = candidate.rng_state.to_int()
	var resolved := command.duplicate(true)
	resolved.target_ids = preview_result.effective_target_ids.duplicate()
	var actor: Dictionary = candidate.actors[command.actor_id]
	var events: Array[Dictionary] = []
	candidate.phase = "action_resolution"
	events.append(Resolver.event("command_accepted", actor.actor_id, "", {"command": command.duplicate(true), "resolved_target_ids": resolved.target_ids.duplicate()}))
	var mp_before: int = actor.mp
	var inventory_before: int = candidate.inventory.get(command.ability_id, 0)
	actor.mp -= int(preview_result.mp_cost)
	if command.kind == "item": candidate.inventory[command.ability_id] = inventory_before - 1
	if command.kind == "skill": actor.cooldown_until[command.ability_id] = int(actor.slot_count) + int(preview_result.cooldown) + 1
	events.append(Resolver.event("resources_changed", actor.actor_id, actor.actor_id, {"mp_before": mp_before, "mp_after": actor.mp, "item_id": command.ability_id if command.kind == "item" else "", "inventory_before": inventory_before if command.kind == "item" else 0, "inventory_after": candidate.inventory.get(command.ability_id, 0) if command.kind == "item" else 0, "cooldown_until": actor.cooldown_until.get(command.ability_id, 0)}))
	events.append_array(Resolver.resolve(candidate, resolved, _catalog, rng))
	candidate.rng_state = str(rng.state)
	candidate.revision += 1
	candidate.accepted_commands[command.command_id] = candidate.revision
	candidate.command_log.append(command.duplicate(true))
	_finish_slot(candidate, events, false)
	_policy_events("after_command", [candidate, resolved, _catalog], events)
	_check_outcome(candidate, events)
	_append_events(candidate, events)
	last_errors = State.validate(candidate)
	if not last_errors.is_empty():
		return {"accepted": false, "reasons": last_errors.duplicate(), "events": [], "revision": _state.revision}
	_state = candidate
	return {"accepted": true, "reasons": [], "events": events.duplicate(true), "revision": _state.revision}

func advance(allow_automatic: bool = true) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if _state.is_empty() or not _state.outcome.is_empty(): return events
	while true:
		if _state.phase == "action_selection":
			var actor: Dictionary = _state.actors[_state.active_actor_id]
			if not allow_automatic or actor.side == "player" or _policy == null or not _policy.has_method("choose_command"):
				break
			var command: Dictionary = _policy.call("choose_command", snapshot(), _catalog)
			if command.is_empty(): break
			# 先发布自动槽事件，统一submit再独立分配事件序号。
			_append_events(_state, events)
			var submitted := submit(command)
			if not submitted.accepted: return events
			var remaining := advance(allow_automatic)
			events.append_array(submitted.events)
			events.append_array(remaining)
			return events
		if _check_outcome(_state, events): break
		if _state.phase in ["preparation", "round_end"]:
			_begin_round(events)
		if _state.queue_index >= _state.queue.size():
			events.append_array(Status.end_round(_state.actors))
			events.append(Resolver.event("round_ended", "", "", {"round": _state.round}))
			_state.phase = "round_end"
			continue
		var id: String = _state.queue[_state.queue_index]
		var actor: Dictionary = _state.actors[id]
		if int(actor.get("last_slot_round", 0)) == int(_state.round):
			last_errors = ["本轮已开始的行动槽不可再次进入"]
			break
		if actor.hp <= 0 or actor.revived_round == _state.round:
			events.append(Resolver.event("slot_skipped", id, id, {"reason": "defeated" if actor.hp <= 0 else "revived_this_round", "round": _state.round}))
			_state.queue_index += 1
			continue
		_state.active_actor_id = id
		_state.slot_token = Status.begin_slot(actor)
		actor["last_slot_round"] = int(_state.round)
		events.append(Resolver.event("slot_started", id, id, {"slot_count": actor.slot_count, "round": _state.round}))
		events.append_array(_state.slot_token.events)
		if actor.hp <= 0:
			events.append(Resolver.event("actor_defeated", id, id, {"reason": "slot_start_damage"}))
			events.append_array(Resolver.cleanup_defeated(_state, id))
		if _state.slot_token.defeated or _state.slot_token.stunned:
			events.append(Resolver.event("slot_skipped", id, id, {"reason": "defeated" if _state.slot_token.defeated else "stunned", "round": _state.round}))
			_finish_slot(_state, events, true)
			continue
		actor.opportunity_count += 1
		_state.phase = "action_selection"
		events.append(Resolver.event("action_opportunity", id, id, {"opportunity_count": actor.opportunity_count, "slot_count": actor.slot_count}))
		_policy_events("before_slot", [_state, id, _catalog], events)
	_append_events(_state, events)
	return events.duplicate(true)

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func restore(saved: Dictionary) -> void:
	var candidate := State.normalize_snapshot(saved)
	last_errors = State.validate(candidate)
	for field in ["slot_token", "event_sequence", "event_log", "command_log"]:
		if not candidate.has(field): last_errors.append("引擎快照缺少字段：" + field)
	if last_errors.is_empty(): _state = candidate

func _begin_round(events: Array[Dictionary]) -> void:
	_state.phase = "round_start"
	_state.round += 1
	_policy_events("before_round", [_state, _catalog], events)
	var snapshots := Status.begin_round(_state.actors)
	events.append_array(snapshots)
	var speeds: Dictionary = {}
	var queue: Array[String] = []
	for item in snapshots:
		queue.append(item.target_id)
		speeds[item.target_id] = float(item.payload.effective_spd)
	queue.sort_custom(func(a: String, b: String) -> bool:
		if speeds[a] != speeds[b]: return speeds[a] > speeds[b]
		if _state.actors[a].side != _state.actors[b].side: return _state.actors[a].side == "player"
		return a < b)
	_state.queue = queue
	_state.queue_index = 0
	_state.active_actor_id = ""
	_state.phase = "action_end"
	events.append(Resolver.event("round_queue", "", "", {"round": _state.round, "queue": queue.duplicate(), "effective_speeds": speeds}))

func _finish_slot(state: Dictionary, events: Array[Dictionary], skipped: bool) -> void:
	var id: String = state.active_actor_id
	if id.is_empty() or state.slot_token.is_empty(): return
	# 只消费状态中唯一权威 token，再清除；重复命令根本到不了这里。
	events.append_array(Status.end_slot(state.actors[id], state.slot_token))
	if skipped: _policy_events("after_skipped_slot", [state, id, _catalog], events)
	events.append(Resolver.event("slot_ended", id, id, {"slot_count": state.actors[id].slot_count, "round": state.round, "skipped": skipped}))
	state.slot_token = {}
	state.active_actor_id = ""
	state.queue_index += 1
	state.phase = "action_end"

func _check_outcome(state: Dictionary, events: Array[Dictionary]) -> bool:
	if not state.outcome.is_empty(): return true
	var players := false
	var enemies := false
	for actor in state.actors.values():
		if actor.hp > 0:
			if actor.side == "player": players = true
			else: enemies = true
	if players and enemies: return false
	state.outcome = "defeat" if not players else "victory"
	state.phase = "outcome"
	state.active_actor_id = ""
	state.slot_token = {}
	_clear_battle_effects(state, events)
	events.append(Resolver.event("outcome", "", "", {"outcome": state.outcome, "round": state.round}))
	return true

func _policy_events(method: String, arguments: Array, events: Array[Dictionary]) -> void:
	if _policy != null and _policy.has_method(method):
		var generated = _policy.callv(method, arguments)
		if generated is Array: events.append_array(generated)

static func _append_events(state: Dictionary, events: Array[Dictionary]) -> void:
	for item in events:
		state.event_sequence += 1
		item.sequence = state.event_sequence
		state.event_log.append(item.duplicate(true))

static func _clear_battle_effects(state: Dictionary, events: Array[Dictionary]) -> void:
	var ids: Array = state.actors.keys()
	ids.sort()
	for id in ids:
		var actor: Dictionary = state.actors[id]
		for status in actor.statuses:
			events.append(Resolver.event("status_removed", id, id, {"status": status.duplicate(true), "reason": "battle_end"}))
		actor.statuses = []
		if not actor.shield.is_empty():
			events.append(Resolver.event("shield_removed", id, id, {"shield": actor.shield.duplicate(true), "reason": "battle_end"}))
			actor.shield = {}
		if not actor.cooldown_until.is_empty():
			events.append(Resolver.event("cooldowns_cleared", id, id, {"previous": actor.cooldown_until.duplicate(), "reason": "battle_end"}))
			actor.cooldown_until = {}
		actor.intent = {}
		if not actor.boss.is_empty(): actor.boss["charge_valid"] = false
