# 十六视觉形态的纯事件策略；不访问 Node/纹理，不结算数值，也不修改传入状态。
# context_from_result 必须在 submit 后使用真正的 submit 前快照及当时 catalog.skill_for 派生值。
# begin/consume/finish 与现 caster policy 并列；loader已校验声明，正式renderer仍须独立接线验收。
extends RefCounted

const Forms = preload("res://scripts/rpg/dual_form.gd")
const SKILLS := {
	"rinne": ["heavy_slash", "armor_break", "sweep", "battle_spirit"],
	"homura_sword": ["heavy_slash", "armor_break", "sweep", "battle_spirit"],
	"guard": ["cover", "shield_bash", "iron_wall", "taunt"],
	"mint": ["mark", "hunt", "ambush", "smoke_screen"]
}
const CONTRACT_ID := "physical_skill_visual_v1"
const CONTRACT_VERSION := 1
const MAX_ACTIONS := 64
const MAX_LAYERS := 256
const MAX_HISTORY := 1024
var _battle_id := ""
var _actions: Dictionary = {}
var _closed: Dictionary = {}
var _retired: Dictionary = {}
var _layers: Dictionary = {}
var _latest: Dictionary = {}
var _dead: Dictionary = {}
var _alive: Dictionary = {}
var _seen: Dictionary = {}
var _cover_consumed: Dictionary = {}
var _sequence_floor := 0
var _highest_sequence := 0
var _closed_revision_floor := -1
var _retirement_full := false

static func _form(actor: Dictionary) -> String:
	match str(actor.get("identity_id", "")):
		"rinne": return "rinne" if Forms.active_class(actor) == "swordsman" else ""
		"homura": return "homura_sword" if Forms.enabled(actor) and Forms.active_class(actor) == "swordsman" else ""
		"guard": return "guard" if actor.get("class_id") == "guard" else ""
		"mint": return "mint" if actor.get("class_id") == "ranger" else ""
	return ""

# 只读桥：包含接受边界的事务才可以成为呈现上下文。不能传一个外来条件 bool。
# 非本模块技能也可产生上下文，供后来敌方命令的真实掩护转伤和 finish 使用。
static func context_from_result(before: Dictionary, derived_skill: Dictionary, result: Dictionary) -> Dictionary:
	if not result.get("accepted", false) or not result.get("events") is Array: return {}
	var accepted: Dictionary = {}
	var last_sequence := 0
	for event in result.events:
		if not event is Dictionary or int(event.get("sequence", 0)) <= last_sequence: return {}
		last_sequence = int(event.sequence)
		if event.get("type") == "command_accepted":
			if not accepted.is_empty(): return {}
			accepted = event
	if accepted.is_empty(): return {}
	var command: Dictionary = accepted.get("payload", {}).get("command", {})
	var source: Dictionary = before.get("actors", {}).get(command.get("actor_id", ""), {})
	if source.is_empty() or command.get("command_id", "").is_empty(): return {}
	if command.get("expected_revision", -1) != before.get("revision", -2) or accepted.get("actor_id") != source.get("actor_id"): return {}
	if before.get("active_actor_id") != source.actor_id or int(source.get("hp", 0)) <= 0: return {}
	if int(result.get("revision", -1)) != int(before.revision) + 1: return {}
	var targets: Array = accepted.payload.get("resolved_target_ids", [])
	for target in targets:
		if not before.actors.has(target): return {}
	var context := command.duplicate(true)
	context.source_id = source.actor_id
	context.effect_target_ids = targets.duplicate()
	context.form = _form(source)
	context.variant_key = "%s-%s" % [context.form, command.ability_id] if context.form in ["rinne", "homura_sword"] else str(command.get("ability_id", ""))
	context.accepted_sequence = int(accepted.sequence)
	context.last_sequence = last_sequence
	context.source_side = source.get("side", "")
	context.accepted_command = command.duplicate(true)
	# 不带所有角色隐私/规则数据。仅保留可审计条件证据，精确匹配首项且唯一的伤害。
	var proof := {"schema": 1, "command_id": command.command_id, "revision": before.revision, "source_id": source.actor_id, "resolved_target_ids": targets.duplicate(), "form": context.form, "ability_id": command.get("ability_id", ""), "damage_effect_index": -1, "effect": {}, "refinement_id": "", "target_statuses": {}}
	if derived_skill.get("id") == command.get("ability_id"):
		var effects: Array = derived_skill.get("effects", [])
		var damage_indices: Array = []
		for index in effects.size():
			if effects[index].get("type") == "damage": damage_indices.append(index)
		if damage_indices == [0]:
			proof.damage_effect_index = 0
			proof.effect = effects[0].duplicate(true)
			proof.refinement_id = derived_skill.get("refinement", {}).get("id", "")
			for id in targets: proof.target_statuses[id] = before.actors[id].get("statuses", []).duplicate(true)
	context.precast_evidence = proof
	return context

# 自动 advance 可返回多命令；调用方先按 command_accepted 分割为单命令窗口。
# 这里只读 roster 的 actor_id/side，不冒充某次施法前快照，也不产生精准证明。
# 专供已有真实掩护的后续敌方反应；不能用此上下文 begin 玩家十六形态技能。
static func context_from_enemy_events(roster: Dictionary, event_window: Array) -> Dictionary:
	var accepted: Dictionary = {}; var previous := 0
	for event in event_window:
		if not event is Dictionary or int(event.get("sequence", 0)) <= previous: return {}
		previous = int(event.sequence)
		if event.get("type") == "command_accepted":
			if not accepted.is_empty(): return {}
			accepted = event
	if accepted.is_empty(): return {}
	var command: Dictionary = accepted.get("payload", {}).get("command", {})
	var source: Dictionary = roster.get(command.get("actor_id", ""), {})
	if source.get("side") != "enemy" or source.get("actor_id") != accepted.get("actor_id") or command.get("command_id", "").is_empty(): return {}
	var context := command.duplicate(true)
	context.source_id = source.actor_id; context.source_side = "enemy"
	context.form = ""; context.variant_key = ""
	context.effect_target_ids = accepted.payload.get("resolved_target_ids", []).duplicate()
	context.accepted_sequence = int(accepted.sequence); context.last_sequence = previous
	context.accepted_command = command.duplicate(true)
	return context

static func _frames(values: Array) -> Array:
	var result: Array = []
	for value in values:
		if not value is int and not value is float: return []
		if float(value) != int(value) or int(value) < 1 or int(value) > 16: return []
		result.append(int(value))
	return result

# 返回完整有限身份；共享规则ID必须明确具体形态。
static func contract_identity(form: String, skill: String) -> Dictionary:
	if not SKILLS.get(form, []).has(skill): return {}
	return {"id": CONTRACT_ID, "version": CONTRACT_VERSION, "form": form, "ability_id": skill, "variant_key": "%s-%s" % [form, skill] if form in ["rinne", "homura_sword"] else skill}

static func _spec(phase: String, event_type: String, lifetime: String = "action", status_id: String = "", start_phase: String = "") -> Dictionary:
	return {"phase": phase, "event_type": event_type, "lifetime": lifetime, "status_id": status_id, "start_phase": start_phase, "placement": "target_body", "target": "event_target", "cue": "impact"}

# 有限绑定表；每一帧都引用登记过的 phase_groups。绝不修改原 manifest 或放宽为任意成功层。
static func bindings(form: String, skill: String, groups: Dictionary) -> Dictionary:
	if not SKILLS.get(form, []).has(skill): return {}
	var specs: Array[Dictionary] = []
	var cast_phase := "cast_sweep" if groups.has("cast_sweep") else "cast"
	var cast := _spec(cast_phase, "command_accepted"); cast.target = "source"; cast.cue = "start"; cast.placement = "caster_body"; specs.append(cast)
	if groups.has("travel") or groups.has("sound_travel"):
		var travel := _spec("travel" if groups.has("travel") else "sound_travel", "command_accepted")
		travel.cue = "launch"; travel.placement = "projectile"; specs.append(travel)
	match skill:
		"heavy_slash":
			specs.append(_spec("contact_damage", "damage"))
			if form == "rinne":
				var precision := _spec("conditional_precision", "damage"); precision.requires_precision = true
				precision.precast_evidence = {"schema": 1, "source": "before_snapshot_and_catalog_skill_for", "refinement_id": "rinne_swordsman", "damage_effect_index": 0, "unique_damage_effect": true, "condition": "target_has_status", "status_id": "armor_break", "original_target_matches": true}
				specs.append(precision)
		"armor_break":
			specs.append(_spec("contact_damage", "damage"))
			specs.append(_spec("armor_break_status", "status_applied", "status", "armor_break"))
			specs.append(_spec("conditional_weaken" if form == "rinne" else "conditional_burn", "status_applied", "status", "weaken" if form == "rinne" else "burn"))
		"sweep":
			specs.append(_spec("contact_damage", "damage"))
			if form == "rinne":
				specs.append(_spec("conditional_slow", "status_applied", "status", "slow"))
				var consumed := _spec("armor_break_consumed", "status_removed", "action", "armor_break"); consumed.reason = "skill_consumed"; specs.append(consumed)
			else: specs.append(_spec("conditional_armor_break", "status_applied", "status", "armor_break"))
		"battle_spirit":
			specs.append(_spec("battle_spirit_status", "status_applied", "status", "battle_spirit", "battle_spirit_apply"))
			if form == "homura_sword": specs.append(_spec("conditional_shield", "shield_applied", "shield"))
		"cover":
			var link := _spec("cover_link", "status_applied", "status", "cover"); link.placement = "cover_link"; specs.append(link)
			specs.append(_spec("cover_status", "status_applied", "status", "cover"))
		"shield_bash":
			specs.append(_spec("damage_recovery", "damage"))
			specs.append(_spec("charge_interrupt", "charge_interrupted"))
			specs.append(_spec("weaken_status", "status_applied", "status", "weaken"))
		"iron_wall", "smoke_screen":
			specs.append(_spec("shield_sustain", "shield_applied", "shield", "", "shield_apply"))
			if skill == "iron_wall":
				var cleanse := _spec("cleanse", "status_removed"); cleanse.reason = "cleanse"; specs.append(cleanse)
			else: specs.append(_spec("battle_spirit", "status_applied", "status", "battle_spirit"))
		"taunt":
			specs.append(_spec("taunt_status", "status_applied", "status", "taunt"))
			specs.append(_spec("conditional_weaken", "status_applied", "status", "weaken"))
		"mark": specs.append(_spec("mark_sustain", "status_applied", "status", "mark", "mark_apply"))
		"hunt":
			specs.append(_spec("damage_recovery", "damage"))
			var consumed := _spec("mark_consumed", "status_removed", "action", "mark"); consumed.reason = "skill_consumed"; specs.append(consumed)
			var refund := _spec("mp_refund", "mp_restored"); refund.target = "source"; refund.placement = "caster_body"; refund.positive_actual = true; specs.append(refund)
		"ambush":
			specs.append(_spec("damage_recovery", "damage"))
			specs.append(_spec("mark_apply_sustain", "status_applied", "status", "mark"))
	if groups.has("recovery"):
		var recovery := _spec("recovery", "status_applied" if skill == "battle_spirit" else "damage", "action", "battle_spirit" if skill == "battle_spirit" else "")
		recovery.target = "source"; recovery.placement = "caster_body"; recovery.cue = "recovery"; specs.append(recovery)
	var expected_phases: Dictionary = {}
	for spec in specs:
		expected_phases[spec.phase] = true
		if not spec.start_phase.is_empty(): expected_phases[spec.start_phase] = true
	if skill == "cover": expected_phases["cover_redirected"] = true
	if groups.size() != expected_phases.size(): return {}
	var all_frames: Dictionary = {}
	for phase in groups:
		if not expected_phases.has(phase) or not groups[phase] is Dictionary: return {}
		var group: Dictionary = groups[phase]
		if group.get("binding") not in ["unbound", "physical_skill_visual_v1"]: return {}
		if not group.get("activation_frames") is Array or not group.get("loop_frames") is Array: return {}
		var raw: Array = group.activation_frames + group.loop_frames
		var normalized := _frames(raw)
		if raw.is_empty() or raw.size() != normalized.size(): return {}
		for frame in normalized:
			if all_frames.has(frame): return {}
			all_frames[frame] = true
	if all_frames.size() != 16: return {}
	var result: Dictionary = {}
	for spec in specs:
		if not groups.has(spec.phase) or not spec.start_phase.is_empty() and not groups.has(spec.start_phase): return {}
		var group: Dictionary = groups[spec.phase]
		if not group.get("activation_frames") is Array or not group.get("loop_frames") is Array: return {}
		spec.activation_frames = _frames(group.activation_frames)
		spec.loop_frames = _frames(group.loop_frames)
		spec.phase_segments = []
		if not spec.start_phase.is_empty():
			var initial: Dictionary = groups[spec.start_phase]
			spec.activation_frames = _frames(initial.get("activation_frames", [])) + spec.activation_frames
			spec.phase_segments.append({"phase": spec.start_phase, "frames": _frames(initial.get("activation_frames", []))})
		spec.phase_segments.append({"phase": spec.phase, "frames": _frames(group.activation_frames), "loop_frames": _frames(group.loop_frames)})
		result[spec.phase] = spec
	return result

# 掩护受击反应与状态施加分离；引用同一登记组，不另造帧映射。
static func reaction_bindings(form: String, skill: String, groups: Dictionary) -> Dictionary:
	if form != "guard" or skill != "cover" or bindings(form, skill, groups).is_empty(): return {}
	var group: Dictionary = groups.cover_redirected
	if not group.loop_frames.is_empty(): return {}
	return {"cover_redirected": {"phase": "cover_redirected", "event_type": "cover_redirected", "requires": "same_accepted_enemy_command_and_immediately_preceding_cover_consumed", "lifetime": "action", "activation_frames": _frames(group.activation_frames), "loop_frames": [], "target": "actual_guard", "endpoints": ["actual_guard", "original_target_id"]}}

func begin_action(context: Dictionary, battle_id: String, phase_groups: Dictionary) -> bool:
	var key := _action_key(context, battle_id)
	if key.is_empty() or context.get("kind") != "skill" or context.get("source_side") != "player": return false
	if context.get("actor_id") != context.get("source_id") or context.get("source_id", "").is_empty(): return false
	if not _valid_range(context) or not _coherent_context(context) or int(context.get("expected_revision", -1)) <= _closed_revision_floor: return false
	var form := str(context.get("form", "")); var skill := str(context.get("ability_id", ""))
	var variant := "%s-%s" % [form, skill] if form in ["rinne", "homura_sword"] else skill
	if context.get("variant_key") != variant: return false
	var contract := bindings(form, skill, phase_groups)
	if contract.is_empty() or _retirement_full or _retired.has(battle_id) or not _battle_id.is_empty() and _battle_id != battle_id: return false
	if _actions.has(key) or _closed.has(key) or _actions.size() >= MAX_ACTIONS: return false
	_battle_id = battle_id
	_actions[key] = {"context": context.duplicate(true), "bindings": contract, "groups": phase_groups.duplicate(true)}
	return true

func consume(event: Dictionary, context: Dictionary, battle_id: String) -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	if battle_id != _battle_id or _battle_id.is_empty(): return intents
	var sequence := int(event.get("sequence", 0))
	if sequence <= _sequence_floor or _seen.has(sequence): return intents
	var kind := str(event.get("type", "")); var target := str(event.get("target_id", ""))
	var payload: Dictionary = event.get("payload", {})
	var key := _action_key(context, battle_id)
	var action := _matched_action(context, key)
	# 错误已登记 context 不能抢占序号；生命周期即使来自不支持的下一招也必须维护。
	if not action.is_empty() and not _in_range(sequence, action.context): return intents
	if _actions.has(key) and action.is_empty(): return intents
	if not context.is_empty() and not _coherent_context(context): return intents
	if not action.is_empty() and not _belongs(event, action.context): return intents
	_remember(sequence)
	if kind != "cover_redirected": _cover_consumed.erase(sequence - 1)
	if kind == "outcome": return clear()
	if kind == "saga_cancelled": return cancel_action(context, battle_id)
	if kind == "cover_redirected": return _redirect(event, context)
	if kind == "actor_defeated":
		_defeat(target, sequence, intents); return intents
	if kind == "revived":
		if int(payload.get("hp", 0)) > 0 and sequence > int(_latest.get(_state_key(target, "__life__"), 0)):
			_latest[_state_key(target, "__life__")] = sequence; _dead.erase(target)
		return intents
	if kind in ["damage", "periodic_damage", "saga_reflected"]: _absorption(target, payload.get("absorption", {}), sequence, intents)
	if kind in ["status_removed", "shield_removed"]:
		var value: Dictionary = payload.get("status" if kind == "status_removed" else "shield", {})
		var status_id := str(value.get("id", "")) if kind == "status_removed" else "shield"
		if kind == "status_removed" and status_id == "cover" and payload.get("reason") == "cover_consumed": _remember_cover(event, context, value)
		_remove_state(target, status_id, value, sequence, intents)
	if kind in ["status_tick", "shield_tick"]:
		var value: Dictionary = payload.get("status" if kind == "status_tick" else "shield", {})
		_update_state(target, str(value.get("id", "")) if kind == "status_tick" else "shield", value, sequence, intents)
		return intents
	if kind in ["status_applied", "status_refreshed", "shield_applied", "shield_refreshed"]:
		var shield_change := kind.begins_with("shield")
		var value: Dictionary = payload.get("shield" if shield_change else "status", {})
		var status_id := "shield" if shield_change else str(value.get("id", ""))
		if value.is_empty() or sequence <= int(_latest.get(_state_key(target, status_id), 0)) or sequence <= int(_latest.get(_state_key(target, "__life__"), 0)) or _dead.has(target): return intents
		_alive[target] = maxi(int(_alive.get(target, 0)), sequence)
		var prior := _state_layers(target, status_id)
		# 真刷新必增 generation；重标序号的同代施加不能重播激活或退回旧剩余量。
		if not prior.is_empty() and _same_origin(prior[0].value, value):
			_latest[_state_key(target, status_id)] = sequence
			return intents
		if action.is_empty():
			var existing := _state_layers(target, status_id)
			if not existing.is_empty() and not _same_origin(existing[0].value, value): _erase_state(target, status_id, intents)
			_latest[_state_key(target, status_id)] = sequence
			return intents
	if action.is_empty() or _dead.has(target) and kind != "damage": return intents
	if sequence < int(_latest.get(_state_key(target, "__life__"), 0)): return intents
	var state_started: Dictionary = {}
	for spec in action.bindings.values():
		if not _matches(spec, event): continue
		if spec.get("requires_precision", false) and not _precision(action.context, event): continue
		var visual_targets: Array = action.context.effect_target_ids if kind == "command_accepted" and spec.get("target") != "source" else [action.context.source_id if spec.get("target") == "source" else target]
		for visual_target in visual_targets:
			if str(visual_target).is_empty(): continue
			var status_id := "shield" if spec.lifetime == "shield" else str(spec.status_id)
			var state_key := _state_key(str(visual_target), status_id)
			var value: Dictionary = payload.get("shield" if spec.lifetime == "shield" else "status", {}) if spec.lifetime != "action" else payload
			if spec.lifetime != "action":
				if value.is_empty() or value.get("source_id") != action.context.source_id or int(value.get("generation", 0)) <= 0: continue
				if int(value.get("amount", 0) if spec.lifetime == "shield" else value.get("remaining", 0)) <= 0: continue
				if not state_started.has(state_key):
					_erase_state(str(visual_target), status_id, intents)
					_latest[state_key] = sequence; state_started[state_key] = true
			var layer_key := JSON.stringify([_battle_id, key if spec.lifetime == "action" else state_key, action.context.variant_key, spec.phase, visual_target])
			if _layers.has(layer_key) or _layers.size() >= MAX_LAYERS: continue
			var intent := _intent(action.context, spec, key, layer_key, str(visual_target), value, sequence)
			if status_id == "cover":
				intent.linked_target_id = str(value.get("snapshot", {}).get("target_id", ""))
				intent.endpoints = [intent.source_id, intent.linked_target_id]
				intent.reaction_group = action.groups.get("cover_redirected", {}).duplicate(true)
				if intent.linked_target_id.is_empty() or intent.linked_target_id == intent.source_id or _dead.has(intent.linked_target_id): continue
				_alive[intent.linked_target_id] = maxi(int(_alive.get(intent.linked_target_id, 0)), sequence)
			if status_id == "taunt": intent.facing_actor_id = str(action.context.source_id)
			_layers[layer_key] = intent.duplicate(true); intents.append(intent)
	return intents

func finish_action(context: Dictionary, battle_id: String) -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	var key := _action_key(context, battle_id)
	if battle_id != _battle_id or key.is_empty(): return intents
	var action := _matched_action(context, key)
	if _actions.has(key) and action.is_empty(): return intents
	if not _coherent_context(context): return intents
	for candidate in _layers.values():
		if candidate.action_key == key and candidate.has("trigger_actor_id") and candidate.trigger_actor_id != context.get("source_id"): return intents
	for layer_key in _layers.keys():
		var layer: Dictionary = _layers[layer_key]
		if layer.action_key != key: continue
		if layer.lifetime == "action": _erase(layer_key, intents)
		elif not layer.activation_frames.is_empty():
			layer.activation_frames = []
			for segment in layer.phase_segments: segment.frames = []
			intents.append(_operation(layer, "update"))
	if not action.is_empty(): _actions.erase(key)
	for sequence in _cover_consumed.keys():
		if _cover_consumed[sequence].command_id == context.get("command_id"): _cover_consumed.erase(sequence)
	if _valid_range(context):
		_closed[key] = int(context.get("expected_revision", -1))
		if _closed.size() > MAX_HISTORY:
			var oldest: String = _closed.keys()[0]
			_closed_revision_floor = maxi(_closed_revision_floor, int(_closed[oldest])); _closed.erase(oldest)
	return intents
func cancel_action(context: Dictionary, battle_id: String) -> Array[Dictionary]:
	# 取消只封闭呈现；已真实施加的状态不能被渲染撤销。
	return finish_action(context, battle_id)
func clear() -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	for key in _layers.keys(): _erase(key, intents)
	if not _battle_id.is_empty():
		_retired[_battle_id] = true
		_retirement_full = _retired.size() >= MAX_HISTORY
	_actions.clear(); _closed.clear(); _latest.clear(); _dead.clear(); _alive.clear(); _seen.clear(); _cover_consumed.clear()
	_battle_id = ""; _sequence_floor = 0; _highest_sequence = 0; _closed_revision_floor = -1
	return intents

# remove 返回后再查询本集合，可保留严格下一事件需要的 cover 原图，避免释放后立即重解码。
# 只读键集合不分配纹理；renderer 仍负责自己的纹理预算及动作 E 清理。
func retained_variant_keys() -> Array[String]:
	var keys: Dictionary = {}
	for action in _actions.values(): keys[action.context.variant_key] = true
	for layer in _layers.values(): keys[layer.variant_key] = true
	for proof in _cover_consumed.values(): keys[proof.layer.variant_key] = true
	var result: Array[String] = []
	for key in keys: result.append(str(key))
	result.sort()
	return result

func _intent(context: Dictionary, spec: Dictionary, action_key: String, layer_key: String, target: String, value: Dictionary, sequence: int) -> Dictionary:
	return {"op": "spawn" if spec.lifetime == "action" else "upsert", "battle_id": _battle_id, "action_key": action_key, "layer_key": layer_key, "ability_id": context.ability_id, "form": context.form, "variant_key": context.variant_key, "phase": spec.phase, "source_id": context.source_id, "target_id": target, "placement": spec.placement, "cue": spec.cue, "lifetime": spec.lifetime, "status_id": "shield" if spec.lifetime == "shield" else spec.status_id, "activation_frames": spec.activation_frames.duplicate(), "loop_frames": spec.loop_frames.duplicate(), "phase_segments": spec.get("phase_segments", []).duplicate(true), "value": value.duplicate(true), "event_sequence": sequence}
func _action_key(context: Dictionary, battle: String) -> String:
	return JSON.stringify([battle, context.command_id]) if not battle.is_empty() and not str(context.get("command_id", "")).is_empty() else ""
func _state_key(target: String, id: String) -> String: return JSON.stringify([_battle_id, target, id])
static func _coherent_context(context: Dictionary) -> bool:
	var accepted: Dictionary = context.get("accepted_command", {})
	if accepted.is_empty() or context.get("source_id") != accepted.get("actor_id"): return false
	for field in ["command_id", "expected_revision", "actor_id", "kind", "ability_id", "target_ids"]:
		if context.get(field) != accepted.get(field): return false
	return true
static func _valid_range(context: Dictionary) -> bool: return int(context.get("accepted_sequence", 0)) > 0 and int(context.get("last_sequence", 0)) >= int(context.get("accepted_sequence", 0))
static func _in_range(sequence: int, context: Dictionary) -> bool: return sequence >= int(context.get("accepted_sequence", 0)) and sequence <= int(context.get("last_sequence", -1))
func _matched_action(context: Dictionary, key: String) -> Dictionary:
	if not _actions.has(key): return {}
	var expected: Dictionary = _actions[key].context
	for field in ["command_id", "expected_revision", "source_id", "actor_id", "ability_id", "kind", "form", "variant_key", "accepted_sequence", "last_sequence", "effect_target_ids"]:
		if context.get(field) != expected.get(field): return {}
	return _actions[key]
func _belongs(event: Dictionary, context: Dictionary) -> bool:
	var kind := str(event.get("type", "")); var target := str(event.get("target_id", "")); var actor := str(event.get("actor_id", ""))
	var payload: Dictionary = event.get("payload", {})
	if kind in ["status_tick", "shield_tick", "shield_removed", "actor_defeated", "revived", "periodic_damage", "saga_reflected", "outcome"]: return true
	if kind == "status_removed":
		if payload.get("reason") == "cleanse": return context.effect_target_ids.has(target) and actor in [target, str(context.source_id)]
		if payload.get("reason") == "skill_consumed": return context.effect_target_ids.has(target) and actor == context.source_id
		return true
	if kind == "command_accepted": return actor == context.source_id and payload.get("command", {}).get("command_id") == context.command_id
	if kind in ["damage", "charge_interrupted", "mp_restored", "status_applied", "status_refreshed", "shield_applied", "shield_refreshed"]:
		if actor != context.source_id: return false
		if kind == "mp_restored": return target == context.source_id
		if kind.begins_with("status") or kind.begins_with("shield"):
			var value: Dictionary = payload.get("shield" if kind.begins_with("shield") else "status", {})
			if value.get("source_id") != context.source_id: return false
			if value.get("id") == "cover": return context.ability_id == "cover" and target == context.source_id and context.effect_target_ids.has(value.get("snapshot", {}).get("target_id"))
		return context.effect_target_ids.has(target)
	return true
static func _matches(spec: Dictionary, event: Dictionary) -> bool:
	var kind := str(event.get("type", ""))
	if kind == "status_refreshed": kind = "status_applied"
	if kind == "shield_refreshed": kind = "shield_applied"
	if kind != spec.event_type: return false
	var payload: Dictionary = event.get("payload", {})
	if not spec.status_id.is_empty() and payload.get("status", {}).get("id") != spec.status_id: return false
	if spec.has("reason") and payload.get("reason") != spec.reason: return false
	if kind == "status_removed" and payload.get("status", {}).is_empty(): return false
	if kind == "mp_restored" and int(payload.get("actual", 0)) <= 0: return false
	return true
static func _precision(context: Dictionary, event: Dictionary) -> bool:
	if context.get("form") != "rinne" or context.get("ability_id") != "heavy_slash" or event.get("type") != "damage": return false
	var proof: Dictionary = context.get("precast_evidence", {})
	for pair in [["command_id", "command_id"], ["revision", "expected_revision"], ["source_id", "source_id"], ["resolved_target_ids", "effect_target_ids"], ["form", "form"], ["ability_id", "ability_id"]]:
		if proof.get(pair[0]) != context.get(pair[1]): return false
	if proof.get("schema") != 1 or proof.get("damage_effect_index") != 0 or proof.get("refinement_id") != "rinne_swordsman": return false
	var effect: Dictionary = proof.get("effect", {})
	if effect.get("type") != "damage" or effect.get("condition") != "target_has_status" or effect.get("status_id") != "armor_break": return false
	var target := str(event.get("target_id", ""))
	if event.get("payload", {}).get("original_target_id") != target or not context.effect_target_ids.has(target): return false
	return proof.get("target_statuses", {}).get(target, []).any(func(status): return status.get("id") == "armor_break")
func _state_layers(target: String, id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for layer in _layers.values():
		if layer.lifetime != "action" and layer.target_id == target and layer.status_id == id: result.append(layer)
	return result
static func _same_origin(first: Dictionary, second: Dictionary) -> bool:
	return first.get("source_id") == second.get("source_id") and int(first.get("generation", -1)) == int(second.get("generation", -2))
func _erase_state(target: String, id: String, intents: Array[Dictionary]) -> void:
	for layer in _state_layers(target, id): _erase(layer.layer_key, intents)
func _remove_state(target: String, id: String, value: Dictionary, sequence: int, intents: Array[Dictionary]) -> void:
	var key := _state_key(target, id)
	if target.is_empty() or id.is_empty() or sequence <= int(_latest.get(key, 0)): return
	var current := _state_layers(target, id)
	if not current.is_empty() and not value.is_empty() and not _same_origin(current[0].value, value) and int(value.get("generation", -1)) <= int(current[0].value.get("generation", -1)): return
	_latest[key] = sequence; _erase_state(target, id, intents)
func _update_state(target: String, id: String, value: Dictionary, sequence: int, intents: Array[Dictionary]) -> void:
	var key := _state_key(target, id)
	if target.is_empty() or id.is_empty() or sequence <= int(_latest.get(key, 0)): return
	_alive[target] = maxi(int(_alive.get(target, 0)), sequence)
	var current := _state_layers(target, id)
	if current.is_empty(): _latest[key] = sequence; return
	if not _same_origin(current[0].value, value):
		if int(value.get("generation", -1)) > int(current[0].value.get("generation", -1)):
			_latest[key] = sequence; _erase_state(target, id, intents)
		return
	_latest[key] = sequence
	if id == "shield" and int(value.get("amount", 0)) <= 0: _erase_state(target, id, intents); return
	for layer in current:
		layer.value = value.duplicate(true); intents.append(_operation(layer, "update"))
func _defeat(target: String, sequence: int, intents: Array[Dictionary]) -> void:
	var key := _state_key(target, "__life__")
	if target.is_empty() or sequence <= int(_latest.get(key, 0)) or sequence < int(_alive.get(target, 0)): return
	_latest[key] = sequence; _dead[target] = sequence
	for layer_key in _layers.keys():
		var layer: Dictionary = _layers[layer_key]
		if layer.lifetime != "action" and (layer.target_id == target or layer.get("linked_target_id") == target):
			_latest[_state_key(layer.target_id, layer.status_id)] = maxi(sequence, int(_latest.get(_state_key(layer.target_id, layer.status_id), 0))); _erase(layer_key, intents)
func _absorption(target: String, absorption: Dictionary, sequence: int, intents: Array[Dictionary]) -> void:
	if absorption.has("defeated") and not absorption.defeated: _alive[target] = maxi(int(_alive.get(target, 0)), sequence)
	if absorption.has("shield_after"):
		if absorption.shield_after.is_empty(): _remove_state(target, "shield", absorption.get("shield_before", {}), sequence, intents)
		else: _update_state(target, "shield", absorption.shield_after, sequence, intents)
	for status in absorption.get("removed_statuses", []):
		if status is Dictionary: _remove_state(target, str(status.get("id", "")), status, sequence, intents)
	if absorption.get("defeated", false): _defeat(target, sequence, intents)
func _remember_cover(event: Dictionary, context: Dictionary, value: Dictionary) -> void:
	var sequence := int(event.sequence); var target := str(event.target_id)
	if not _valid_range(context) or not _in_range(sequence, context) or context.get("source_side") != "enemy" or event.actor_id != context.get("source_id"): return
	var current := _state_layers(target, "cover")
	if current.is_empty() or not _same_origin(current[0].value, value) or sequence <= int(_latest.get(_state_key(target, "cover"), 0)): return
	var layer: Dictionary = current[0]
	var groups: Dictionary = {}
	# 状态跨施法动作存活，因此反应素材引用随状态携带，不依赖已退役动作。
	groups = layer.get("reaction_group", {})
	if groups.is_empty(): return
	_cover_consumed[sequence] = {"layer": layer.duplicate(true), "value": value.duplicate(true), "sequence": sequence, "enemy_id": str(event.actor_id), "command_id": str(context.command_id), "last_sequence": int(context.last_sequence), "group": groups}
func _redirect(event: Dictionary, context: Dictionary) -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	var sequence := int(event.sequence); var previous := sequence - 1
	if not _cover_consumed.has(previous) or not _valid_range(context) or not _in_range(sequence, context): return intents
	var proof: Dictionary = _cover_consumed[previous]
	_cover_consumed.erase(previous)
	var original := str(event.get("payload", {}).get("original_target_id", ""))
	if context.get("source_side") != "enemy" or context.get("source_id") != proof.enemy_id or event.get("actor_id") != proof.enemy_id or context.get("command_id") != proof.command_id or int(context.last_sequence) != int(proof.last_sequence): return intents
	if event.get("target_id") != proof.layer.target_id or original != proof.value.get("snapshot", {}).get("target_id"): return intents
	var key := _action_key(context, _battle_id)
	if _closed.has(key) or _dead.has(str(event.target_id)) or _dead.has(original) or _layers.size() >= MAX_LAYERS: return intents
	var intent: Dictionary = proof.layer.duplicate(true)
	intent.op = "spawn"; intent.phase = "cover_redirected"; intent.lifetime = "action"; intent.status_id = ""; intent.placement = "target_body"; intent.cue = "impact"
	intent.activation_frames = _frames(proof.group.get("activation_frames", [])); intent.loop_frames = []
	intent.phase_segments = [{"phase": "cover_redirected", "frames": intent.activation_frames.duplicate()}]
	intent.action_key = key; intent.layer_key = JSON.stringify([_battle_id, key, "cover_redirected", event.target_id, previous])
	intent.event_sequence = sequence; intent.trigger_actor_id = event.actor_id; intent.linked_target_id = original; intent.endpoints = [event.target_id, original]
	intent.value = event.payload.duplicate(true)
	_layers[intent.layer_key] = intent.duplicate(true); intents.append(intent)
	return intents
func _erase(key: String, intents: Array[Dictionary]) -> void:
	if not _layers.has(key): return
	intents.append(_operation(_layers[key], "remove")); _layers.erase(key)
static func _operation(layer: Dictionary, op: String) -> Dictionary:
	var result := layer.duplicate(true); result.op = op; return result
func _remember(sequence: int) -> void:
	_highest_sequence = maxi(_highest_sequence, sequence); _sequence_floor = maxi(_sequence_floor, _highest_sequence - MAX_HISTORY)
	_seen[sequence] = true
	for old in _seen.keys():
		if int(old) <= _sequence_floor: _seen.erase(old)
	for old in _cover_consumed.keys():
		if int(old) < sequence - 1: _cover_consumed.erase(old)
	for key in _latest.keys():
		if int(_latest[key]) <= _sequence_floor: _latest.erase(key)
	for actor in _alive.keys():
		if int(_alive[actor]) <= _sequence_floor: _alive.erase(actor)
	for actor in _dead.keys():
		if int(_dead[actor]) <= _sequence_floor: _dead.erase(actor)
