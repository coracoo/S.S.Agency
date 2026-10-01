# 已公布的意图就是下一次命令。只重选倒地目标或响应普通单体挑衅。
class_name RpgEnemyPolicy
extends RefCounted

const Boss = preload("res://scripts/rpg/boss_policy.gd")
const Resolver = preload("res://scripts/rpg/effect_resolver.gd")

func plan(state: Dictionary, enemy_id: String, catalog: RefCounted) -> Dictionary:
	var actor: Dictionary = state.actors[enemy_id]
	if actor.hp <= 0: return {}
	if actor.class_id == "gatekeeper": return Boss.plan(state, enemy_id, catalog)
	var definition: Dictionary = catalog.get_definition("enemies", actor.class_id)
	if definition.is_empty(): return {}
	var ability: Dictionary = {}
	for candidate in definition.abilities:
		if actor.mp < int(candidate.mp_cost) or int(actor.cooldown_until.get(candidate.id, 0)) > int(actor.slot_count) + 1: continue
		if candidate.has("condition") and float(actor.hp) / float(actor.stats.hp) > float(candidate.condition.get("self_hp_ratio_at_most", 1.0)): continue
		ability = candidate
		break
	if ability.is_empty():
		var magical: bool = definition.default_attack == "magic"
		return Boss.intent("attack_magic" if magical else "attack_physical", Boss.pick(state, enemy_id, definition.target_policy), "magic" if magical else "physical", "neutral", [], false, false, enemy_id)
	var targets: Array = [enemy_id] if ability.target_rule == "self" else Boss.pick(state, enemy_id, definition.target_policy)
	var statuses: Array = []
	for effect in ability.effects:
		if effect.type == "apply_status": statuses.append(effect.status_id)
	return Boss.intent(ability.id, targets, ability.damage_type, ability.element, statuses, false, false, enemy_id)

func refresh_target(state: Dictionary, intent: Dictionary) -> Dictionary:
	var refreshed := intent.duplicate(true)
	if intent.is_empty() or intent.locked: return refreshed
	var owner_id: String = intent.get("preview", {}).get("actor_id", "")
	if not state.actors.has(owner_id) or state.actors[owner_id].side != "enemy":
		owner_id = ""
		for id in state.actors:
			if state.actors[id].side == "enemy" and state.actors[id].intent == intent:
				owner_id = id
				break
	if owner_id.is_empty() or intent.target_ids == [owner_id]: return refreshed
	if intent.ability_id in ["boss_quake", "boss_pulse_charge"]:
		refreshed.target_ids = Boss.opponents(state, owner_id)
		return refreshed
	if intent.target_ids.size() != 1: return refreshed
	var actor: Dictionary = state.actors[owner_id]
	var target_id: String = intent.target_ids[0]
	for status in actor.statuses:
		if status.id == "taunt" and int(status.remaining) > 0 and state.actors.has(status.source_id) and state.actors[status.source_id].hp > 0 and state.actors[status.source_id].side != actor.side:
			refreshed.target_ids = [status.source_id]
			return refreshed
	if state.actors.has(target_id) and state.actors[target_id].hp > 0: return refreshed
	var rule := "lowest_hp_ratio"
	if actor.class_id in ["shield_soldier", "gatekeeper"]: rule = "highest_hp"
	if actor.class_id == "gatekeeper" and intent.ability_id == "boss_pierce_charge": rule = "lowest_hp_ratio"
	if actor.class_id == "cultist": rule = "highest_atk"
	refreshed.target_ids = Boss.pick(state, owner_id, rule)
	return refreshed

func on_battle_start(state: Dictionary, catalog: RefCounted) -> Array[Dictionary]:
	return _refresh(state, catalog, "")

func before_round(state: Dictionary, catalog: RefCounted) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for id in _enemy_ids(state):
		if state.actors[id].class_id == "gatekeeper":
			Boss.initialize(state.actors[id])
			events.append_array(Boss.on_round_start(state, id))
	events.append_array(_refresh(state, catalog, ""))
	return events

func before_slot(state: Dictionary, _actor_id: String, catalog: RefCounted) -> Array[Dictionary]:
	return _refresh(state, catalog, "")

func after_command(state: Dictionary, command: Dictionary, catalog: RefCounted) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var actor: Dictionary = state.actors[command.actor_id]
	if actor.side == "enemy" and actor.class_id == "gatekeeper": events.append_array(Boss.on_slot_end(state, actor.actor_id, false))
	events.append_array(_refresh(state, catalog, actor.actor_id if actor.side == "enemy" else ""))
	return events

func after_skipped_slot(state: Dictionary, actor_id: String, catalog: RefCounted) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var actor: Dictionary = state.actors[actor_id]
	if actor.side == "enemy" and actor.class_id == "gatekeeper": events.append_array(Boss.on_slot_end(state, actor_id, true))
	events.append_array(_refresh(state, catalog, actor_id if actor.side == "enemy" else ""))
	return events

func choose_command(state: Dictionary, _catalog: RefCounted) -> Dictionary:
	var actor: Dictionary = state.actors.get(state.active_actor_id, {})
	if actor.is_empty() or actor.side != "enemy" or actor.intent.is_empty(): return {}
	return command_for(state, actor.actor_id, actor.intent)

func validate_command(state: Dictionary, command: Dictionary) -> Array[String]:
	var actor: Dictionary = state.actors.get(command.get("actor_id", ""), {})
	if actor.get("side", "") != "enemy" or actor.get("intent", {}).is_empty(): return []
	var committed := command_for(state, actor.actor_id, actor.intent)
	if command.get("kind") != committed.kind or command.get("ability_id") != committed.ability_id or command.get("target_ids") != committed.target_ids:
		return ["敌方必须执行已公开的指令与目标"]
	return []

static func command_for(state: Dictionary, actor_id: String, intent: Dictionary) -> Dictionary:
	var basic: bool = intent.ability_id in ["attack_physical", "attack_magic"]
	return {"command_id": "enemy_%s_%d_%d" % [actor_id, state.actors[actor_id].slot_count, state.revision], "expected_revision": int(state.revision), "actor_id": actor_id, "kind": intent.ability_id if basic else "skill", "ability_id": "" if basic else intent.ability_id, "target_ids": intent.target_ids.duplicate()}

func _refresh(state: Dictionary, catalog: RefCounted, replan_id: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for id in _enemy_ids(state):
		var actor: Dictionary = state.actors[id]
		if actor.hp <= 0:
			actor.intent = {}
			continue
		if actor.class_id == "gatekeeper":
			Boss.initialize(actor)
			Boss.refresh_opportunities(state, id)
			events.append_array(Boss.observe_phase(state, id))
		if actor.intent.is_empty() or id == replan_id:
			actor.intent = plan(state, id, catalog)
		else:
			actor.intent = refresh_target(state, actor.intent)
		if actor.intent.is_empty(): continue
		# 可打断性随真实蓄力状态刷新；取消后不保留旧的可打断标记。
		if actor.class_id == "gatekeeper": actor.intent.interruptible = Boss.plan(state, id, catalog).interruptible
		# 预览使用解析器副本，不伪造选择阶段或绕过权威token验证。
		var command := command_for(state, id, actor.intent)
		var simulation := state.duplicate(true)
		var resolved := Resolver.resolve(simulation, command, catalog, null)
		var ranges: Array = []
		var reasons: Array = []
		for item in resolved:
			if item.type == "damage": ranges.append({"target_id": item.target_id, "original_target_id": item.payload.original_target_id, "normal": item.payload.normal, "critical": item.payload.critical_damage, "critical_chance": 0.05 if item.payload.can_crit else 0.0})
			if item.type == "effect_ignored": reasons.append(item.payload.reason)
		actor.intent.preview = {"actor_id": id, "effects": resolved, "damage_ranges": ranges, "reasons": reasons}
		# 每个规则接点发布刷新，事件数量不依赖JSON浮点往返后的缓存相等性。
		events.append(Resolver.event("intent_updated", id, id, {"intent": actor.intent.duplicate(true)}))
	return events

static func _enemy_ids(state: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for id in state.actors:
		if state.actors[id].side == "enemy": ids.append(id)
	ids.sort()
	return ids
