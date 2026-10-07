# 纯事件→呈现意图；不访问Node/纹理、不计算伤害，也不从技能文案猜测效果。
# 调用方只在command_accepted后注册动作；event_layers来自已验证的图集清单。
# finish/cancel均封闭动作并结束E约束的激活，但保留已提交的模型状态。
# saga_cancelled在模型结算前发出，所以不会有该指令的新状态；离场必须clear。
# clear封闭当前battle_id；下一次呈现必须使用新的战场/呈现代次。
# 序号窗口保留最近1024项；更早乱序事件直接舍弃，不因去重缓存淘汰而重新生效。
extends RefCounted

const ABILITIES := ["heal", "group_heal", "cleanse", "holy_shield", "weaken", "slow", "seal", "magic_break"]
const MAX_ACTIONS := 64
const MAX_LAYERS := 256
const MAX_HISTORY := 1024
var _battle_id := ""
var _actions: Dictionary = {}
var _closed: Dictionary = {}
var _retired_battles: Dictionary = {}
var _layers: Dictionary = {}
var _seen: Dictionary = {}
var _latest: Dictionary = {}
var _dead: Dictionary = {}
var _sequence_floor := 0
var _highest_sequence := 0

func begin_action(context: Dictionary, battle_id: String, event_layers: Dictionary) -> bool:
	var key := _action_key(context, battle_id)
	var source := str(context.get("source_id", ""))
	var ability := str(context.get("ability_id", ""))
	if key.is_empty() or source.is_empty() or context.get("kind") != "skill" or ability not in ABILITIES or event_layers.is_empty(): return false
	if _retired_battles.has(battle_id) or not _battle_id.is_empty() and battle_id != _battle_id: return false
	if _actions.has(key) or _closed.has(key) or _actions.size() >= MAX_ACTIONS: return false
	if context.has("actor_id") and context.actor_id != source: return false
	_battle_id = battle_id
	var targets: Array = context.get("effect_target_ids", context.get("resolved_target_ids", context.get("target_ids", []))).duplicate()
	_actions[key] = {"source_id": source, "ability_id": ability, "targets": targets, "event_layers": event_layers.duplicate(true), "cleanse_targets": {}, "counts": {}}
	return true

func consume(event: Dictionary, context: Dictionary, battle_id: String) -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	if _battle_id.is_empty() or battle_id != _battle_id: return intents
	var sequence := int(event.get("sequence", 0))
	if sequence <= _sequence_floor or _seen.has(sequence): return intents
	var kind := str(event.get("type", ""))
	var target := str(event.get("target_id", ""))
	var payload: Dictionary = event.get("payload", {})
	var key := _action_key(context, battle_id)
	var action := _matched_action(context, key)
	# 消费错误context不得占用真实事件序号。无context只允许维护已经存在的持续层。
	if not context.is_empty() and context.get("ability_id") in ABILITIES:
		if action.is_empty():
			var changes_existing := false
			if kind in ["status_applied", "status_refreshed", "shield_applied", "shield_refreshed"]:
				var shield_change := kind.begins_with("shield")
				var value: Dictionary = payload.get("shield" if shield_change else "status", {})
				changes_existing = _layers.has(_state_key(target, "shield" if shield_change else str(value.get("id", ""))))
			if not changes_existing and kind not in ["status_tick", "shield_tick", "status_removed", "shield_removed", "actor_defeated", "revived", "damage", "periodic_damage", "saga_reflected", "outcome"]: return intents
			# 纹理预算等原因可令当前动作未注册；真实吸收/刷新/移除仍维护此前的状态。
		elif not _belongs(event, action): return intents
	if kind == "saga_cancelled":
		if action.is_empty(): return intents
		_remember_sequence(sequence)
		return cancel_action(context, battle_id)
	_remember_sequence(sequence)
	if kind == "outcome": return clear()
	if kind == "actor_defeated":
		if sequence <= int(_latest.get(_state_key(target, "__life__"), 0)): return intents
		_stamp(_state_key(target, "__life__"), sequence)
		_dead[target] = sequence
		_remove_actor_states(target, sequence, intents)
		return intents
	if kind == "revived" and int(payload.get("hp", 0)) > 0:
		if sequence > int(_latest.get(_state_key(target, "__life__"), 0)):
			_stamp(_state_key(target, "__life__"), sequence)
			_dead.erase(target)
		return intents
	if kind in ["damage", "periodic_damage", "saga_reflected"]:
		_absorption(target, payload.get("absorption", {}), sequence, intents)
	if kind in ["status_removed", "shield_removed"]:
		var value: Dictionary = payload.get("status" if kind == "status_removed" else "shield", {})
		var status_id := str(value.get("id", "")) if kind == "status_removed" else "shield"
		_remove_state(target, status_id, value, sequence, intents)
	if kind in ["status_tick", "shield_tick"]:
		var value: Dictionary = payload.get("status" if kind == "status_tick" else "shield", payload.get("after", {}))
		_update_state(target, str(value.get("id", "")) if kind == "status_tick" else "shield", value, sequence, intents)
		return intents
	if kind in ["status_applied", "status_refreshed", "shield_applied", "shield_refreshed"]:
		var is_shield := kind.begins_with("shield")
		var value: Dictionary = payload.get("shield" if is_shield else "status", {})
		var status_id := "shield" if is_shield else str(value.get("id", ""))
		var state_key := _state_key(target, status_id)
		if sequence <= int(_latest.get(state_key, 0)) or sequence <= int(_latest.get(_state_key(target, "__life__"), 0)) or _dead.has(target): return intents
		# 未登记能力刷新同名状态时，不沿用另一招/另一施法者的图。tick不能新造层。
		if action.is_empty():
			if _layers.has(state_key) and not _same_origin(_layers[state_key].value, value): _erase_layer(state_key, intents)
			_stamp(state_key, sequence)
			return intents
	if action.is_empty() or _dead.has(target) and kind != "damage": return intents
	if sequence < int(_latest.get(_state_key(target, "__life__"), 0)): return intents
	if kind == "status_removed" and payload.get("reason") == "cleanse" and not payload.get("status", {}).is_empty():
		action.cleanse_targets[target] = sequence
	for name in action.event_layers:
		var spec: Dictionary = action.event_layers[name]
		if not _matches(spec, event): continue
		if spec.has("requires_event") and not action.cleanse_targets.has(target): continue
		var visual_target := str(action.source_id) if spec.get("target") == "source" else target
		var lifetime := str(spec.get("lifetime", "action"))
		var status_id := "shield" if lifetime == "shield" else str(spec.get("status_id", ""))
		var layer_key := _state_key(visual_target, status_id) if lifetime != "action" else JSON.stringify([_battle_id, key, str(name), visual_target])
		if lifetime == "action" and _layers.has(layer_key): continue
		if int(spec.get("max_instances_per_action", 0)) > 0 and int(action.counts.get(name, 0)) >= int(spec.max_instances_per_action): continue
		if not _layers.has(layer_key) and _layers.size() >= MAX_LAYERS: continue
		var value: Dictionary = payload.get("shield" if lifetime == "shield" else "status", {}) if lifetime != "action" else payload
		if lifetime != "action":
			if value.is_empty() or str(value.get("source_id", "")) != action.source_id: continue
			if sequence <= int(_latest.get(layer_key, 0)): continue
			if lifetime == "shield" and int(value.get("amount", 0)) <= 0: continue
			if lifetime == "status" and int(value.get("remaining", 0)) <= 0: continue
			_stamp(layer_key, sequence)
		var intent := {"op": "spawn" if lifetime == "action" else "upsert", "layer_key": layer_key, "ability_id": action.ability_id, "phase": str(spec.phase), "source_id": action.source_id, "target_id": visual_target, "placement": str(spec.placement), "lifetime": lifetime, "activation_frames": spec.get("activation_frames", []).duplicate(), "loop_frames": spec.get("loop_frames", []).duplicate(), "value": value.duplicate(true), "action_key": key, "status_id": status_id, "battle_id": battle_id}
		_layers[layer_key] = intent.duplicate(true)
		action.counts[name] = int(action.counts.get(name, 0)) + 1
		intents.append(intent)
	return intents

func finish_action(context: Dictionary, battle_id: String) -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	var key := _action_key(context, battle_id)
	if battle_id != _battle_id or _matched_action(context, key).is_empty(): return intents
	for layer_key in _layers.keys():
		var layer: Dictionary = _layers[layer_key]
		if layer.action_key != key: continue
		if layer.lifetime == "action": _erase_layer(layer_key, intents)
		elif not layer.activation_frames.is_empty():
			layer.activation_frames = []
			intents.append(_operation(layer, "update"))
	_closed[key] = {"source_id": _actions[key].source_id, "ability_id": _actions[key].ability_id}
	_actions.erase(key)
	if _closed.size() > MAX_HISTORY: _closed.erase(_closed.keys()[0])
	return intents

func cancel_action(context: Dictionary, battle_id: String) -> Array[Dictionary]:
	# 渲染取消不撤销模型事务。finish已封闭动作；保留真实status/shield供后续时钟移除。
	return finish_action(context, battle_id)

func clear() -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	for key in _layers.keys(): _erase_layer(key, intents)
	if not _battle_id.is_empty():
		_retired_battles[_battle_id] = true
		if _retired_battles.size() > MAX_HISTORY: _retired_battles.erase(_retired_battles.keys()[0])
	_actions.clear(); _closed.clear(); _seen.clear(); _latest.clear(); _dead.clear()
	_battle_id = ""; _sequence_floor = 0; _highest_sequence = 0
	return intents

func _action_key(context: Dictionary, battle_id: String) -> String:
	var command := str(context.get("command_id", ""))
	return "" if command.is_empty() or battle_id.is_empty() else JSON.stringify([battle_id, command])
func _state_key(target: String, status_id: String) -> String:
	return JSON.stringify([_battle_id, target, status_id])
func _matched_action(context: Dictionary, key: String) -> Dictionary:
	if not _actions.has(key): return {}
	var action: Dictionary = _actions[key]
	return action if _identity_matches(context, action) else {}
func _identity_matches(context: Dictionary, action: Dictionary) -> bool:
	return context.get("source_id") == action.source_id and context.get("ability_id") == action.ability_id and context.get("kind") == "skill" and context.get("actor_id", action.source_id) == action.source_id
func _belongs(event: Dictionary, action: Dictionary) -> bool:
	var kind := str(event.get("type", ""))
	var target := str(event.get("target_id", ""))
	var actor := str(event.get("actor_id", ""))
	var payload: Dictionary = event.get("payload", {})
	if kind in ["status_tick", "shield_tick", "status_removed", "shield_removed", "actor_defeated", "periodic_damage", "saga_reflected", "round_snapshot", "slot_ended", "outcome"]:
		if kind == "status_removed" and payload.get("reason") == "cleanse": return action.targets.has(target) and actor in [target, str(action.source_id)]
		return true
	if kind in ["healed", "mp_restored", "damage", "status_applied", "status_refreshed", "shield_applied", "shield_refreshed", "charge_interrupted", "effect_ignored"]:
		if actor != action.source_id: return false
		if kind in ["status_applied", "status_refreshed", "shield_applied", "shield_refreshed"]:
			var value: Dictionary = payload.get("shield" if kind.begins_with("shield") else "status", {})
			if value.get("source_id") != action.source_id: return false
		return target == action.source_id if kind == "mp_restored" else action.targets.has(target)
	return actor == action.source_id or actor.is_empty()
func _matches(spec: Dictionary, event: Dictionary) -> bool:
	var kind := str(event.get("type", ""))
	if kind == "status_refreshed": kind = "status_applied"
	if kind == "shield_refreshed": kind = "shield_applied"
	if spec.get("event_type") != kind: return false
	var payload: Dictionary = event.get("payload", {})
	if spec.has("positive_payload") and int(payload.get(spec.positive_payload, 0)) <= 0: return false
	if spec.has("status_id") and payload.get("status", {}).get("id") != spec.status_id: return false
	for field in spec.get("payload_equals", {}):
		if payload.get(field) != spec.payload_equals[field]: return false
	if kind == "status_removed" and payload.get("status", {}).is_empty(): return false
	return true
func _same_origin(first: Dictionary, second: Dictionary) -> bool:
	return int(first.get("generation", -1)) == int(second.get("generation", -2)) and first.get("source_id") == second.get("source_id")
func _update_state(target: String, status_id: String, value: Dictionary, sequence: int, intents: Array[Dictionary]) -> void:
	var key := _state_key(target, status_id)
	if target.is_empty() or status_id.is_empty() or sequence <= int(_latest.get(key, 0)): return
	if not _layers.has(key):
		_stamp(key, sequence)
		return
	if not _same_origin(_layers[key].value, value):
		# 新代时钟先于其apply到达：撤掉已过时的旧来源，不从tick猜新技能。
		if int(value.get("generation", -1)) > int(_layers[key].value.get("generation", -1)):
			_stamp(key, sequence)
			_erase_layer(key, intents)
		return
	_stamp(key, sequence)
	if status_id == "shield" and int(value.get("amount", 0)) <= 0:
		_erase_layer(key, intents)
		return
	_layers[key].value = value.duplicate(true)
	intents.append(_operation(_layers[key], "update"))
func _remove_state(target: String, status_id: String, value: Dictionary, sequence: int, intents: Array[Dictionary]) -> void:
	if target.is_empty() or status_id.is_empty(): return
	var key := _state_key(target, status_id)
	if sequence <= int(_latest.get(key, 0)): return
	if _layers.has(key) and not value.is_empty() and not _same_origin(_layers[key].value, value):
		if int(value.get("generation", -1)) <= int(_layers[key].value.get("generation", -1)): return
	_stamp(key, sequence)
	_erase_layer(key, intents)
func _remove_actor_states(target: String, sequence: int, intents: Array[Dictionary]) -> void:
	for key in _layers.keys():
		if _layers[key].target_id == target and _layers[key].lifetime != "action" and sequence > int(_latest.get(key, 0)):
			_stamp(key, sequence)
			_erase_layer(key, intents)
	if _dead.size() > MAX_HISTORY: _dead.erase(_dead.keys()[0])
func _absorption(target: String, absorption: Dictionary, sequence: int, intents: Array[Dictionary]) -> void:
	if absorption.has("shield_after"):
		var after: Dictionary = absorption.shield_after
		if after.is_empty(): _remove_state(target, "shield", absorption.get("shield_before", {}), sequence, intents)
		else: _update_state(target, "shield", after, sequence, intents)
	for removed in absorption.get("removed_statuses", []):
		if removed is Dictionary: _remove_state(target, str(removed.get("id", "")), removed, sequence, intents)
	if absorption.get("defeated", false) and sequence > int(_latest.get(_state_key(target, "__life__"), 0)):
		_stamp(_state_key(target, "__life__"), sequence)
		_dead[target] = sequence
		_remove_actor_states(target, sequence, intents)
func _erase_layer(key: String, intents: Array[Dictionary]) -> void:
	if not _layers.has(key): return
	intents.append(_operation(_layers[key], "remove"))
	_layers.erase(key)
func _operation(layer: Dictionary, op: String) -> Dictionary:
	var result := layer.duplicate(true)
	result.op = op
	return result
func _remember_sequence(sequence: int) -> void:
	_highest_sequence = maxi(_highest_sequence, sequence)
	_sequence_floor = maxi(_sequence_floor, _highest_sequence - MAX_HISTORY)
	_seen[sequence] = true
	for old in _seen.keys():
		if int(old) <= _sequence_floor: _seen.erase(old)
	for key in _latest.keys():
		if int(_latest[key]) <= _sequence_floor and not _layers.has(key): _latest.erase(key)
func _stamp(key: String, sequence: int) -> void:
	_latest[key] = sequence
	if _latest.size() > MAX_HISTORY:
		var oldest: String = _latest.keys()[0]
		for candidate in _latest:
			if int(_latest[candidate]) < int(_latest[oldest]): oldest = candidate
		_sequence_floor = maxi(_sequence_floor, int(_latest[oldest]))
		_latest.erase(oldest)
