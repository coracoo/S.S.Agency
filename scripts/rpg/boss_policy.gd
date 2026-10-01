# Boss进度完全存于模型；策略对象不保存跨槽／跨轮状态。
class_name RpgBossPolicy
extends RefCounted

const Status = preload("res://scripts/rpg/status_rules.gd")
const CYCLE := ["boss_suppress", "boss_pierce_charge", "boss_pierce_release", "boss_quake", "boss_pulse_charge", "boss_pulse_release"]

static func initialize(actor: Dictionary) -> void:
	if actor.boss.has("step"): return
	actor.boss = {"step": 1, "charge_valid": false, "charge_interruptible": true, "charge_interrupted": false, "charge_fallback": false, "locked_targets": [], "opportunity_thresholds": {}, "opportunity_revived_rounds": {}, "committed_coefficient": 0.0, "committed_phase_multiplier": 1.0, "release_id": "", "phase": 1, "pending_phase": 0, "pending_phase_round": -1}

static func plan(state: Dictionary, boss_id: String, catalog: RefCounted) -> Dictionary:
	var actor: Dictionary = state.actors[boss_id]
	initialize(actor)
	var boss: Dictionary = actor.boss
	var ability_id: String = CYCLE[int(boss.step) - 1]
	var definition: Dictionary = catalog.get_definition("abilities", ability_id)
	if (boss.step in [2, 5] and actor.mp < int(definition.mp_cost)) or (boss.step in [3, 6] and boss.charge_fallback):
		return intent("attack_physical", pick(state, boss_id, "highest_hp"), "physical", "neutral", [], false, false, boss_id)
	var targets: Array = []
	var locked: bool = boss.step in [3, 6]
	if locked:
		targets = boss.locked_targets.duplicate()
	elif boss.step in [4, 5]:
		targets = opponents(state, boss_id)
	else:
		targets = pick(state, boss_id, "lowest_hp_ratio" if boss.step == 2 else "highest_hp")
	var statuses: Array = []
	for effect in definition.effects:
		if effect.type == "apply_status": statuses.append(effect.status_id)
	return intent(ability_id, targets, definition.damage_type, definition.element, statuses, boss.step == 2 or (boss.step == 3 and boss.charge_valid), locked, boss_id)

static func intent(ability_id: String, targets: Array, damage_type: String, element: String, statuses: Array, interruptible: bool, locked: bool, actor_id: String) -> Dictionary:
	return {"ability_id": ability_id, "target_ids": targets.duplicate(), "damage_type": damage_type, "element": element, "added_statuses": statuses.duplicate(), "interruptible": interruptible, "locked": locked, "preview": {"actor_id": actor_id}}

static func opponents(state: Dictionary, actor_id: String) -> Array[String]:
	var ids: Array[String] = []
	for id in state.actors:
		if state.actors[id].side != state.actors[actor_id].side and state.actors[id].hp > 0: ids.append(id)
	ids.sort()
	return ids

static func pick(state: Dictionary, actor_id: String, rule: String) -> Array[String]:
	var ids := opponents(state, actor_id)
	for status in state.actors[actor_id].statuses:
		if status.id == "taunt" and int(status.remaining) > 0 and ids.has(status.source_id): return [status.source_id]
	ids.sort_custom(func(a: String, b: String) -> bool:
		var left: Dictionary = state.actors[a]
		var right: Dictionary = state.actors[b]
		var av := float(left.hp) / float(left.stats.hp) if rule == "lowest_hp_ratio" else float(left.stats.atk if rule == "highest_atk" else left.hp)
		var bv := float(right.hp) / float(right.stats.hp) if rule == "lowest_hp_ratio" else float(right.stats.atk if rule == "highest_atk" else right.hp)
		if av == bv: return a < b
		return av < bv if rule == "lowest_hp_ratio" else av > bv)
	if ids.is_empty(): return []
	return [ids[0]]

# 准备费用由引擎原子扣除，此处只记录一次承诺，群体准备不能逐目标重复。
static func start_charge(state: Dictionary, boss_id: String, targets: Array, effect: Dictionary, catalog: RefCounted) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[boss_id]
	initialize(actor)
	var boss: Dictionary = actor.boss
	boss.charge_valid = true
	boss.charge_interruptible = effect.interruptible
	boss.charge_interrupted = false
	boss.charge_fallback = false
	boss.locked_targets = targets.duplicate()
	boss.release_id = effect.release_id
	boss.opportunity_thresholds = {}
	boss.opportunity_revived_rounds = {}
	for id in opponents(state, boss_id):
		boss.opportunity_thresholds[id] = int(state.actors[id].opportunity_count) + 1
		boss.opportunity_revived_rounds[id] = int(state.actors[id].revived_round)
	var release: Dictionary = catalog.get_definition("abilities", effect.release_id)
	for release_effect in release.effects:
		if release_effect.type == "damage":
			boss.committed_coefficient = float(release_effect.coefficient)
			break
	boss.committed_phase_multiplier = phase_multiplier(actor)
	return [_event("charge_started", boss_id, {"release_id": boss.release_id, "locked_targets": targets.duplicate(), "opportunity_thresholds": boss.opportunity_thresholds.duplicate(), "committed_coefficient": boss.committed_coefficient, "committed_phase_multiplier": boss.committed_phase_multiplier, "interruptible": boss.charge_interruptible})]

# 复活者包含已达旧门槛后再次倒地的成员；每次复活都需要新机会。
static func refresh_opportunities(state: Dictionary, boss_id: String) -> void:
	var boss: Dictionary = state.actors[boss_id].boss
	if not boss.get("charge_valid", false): return
	for id in opponents(state, boss_id):
		var actor: Dictionary = state.actors[id]
		if not boss.opportunity_thresholds.has(id) or boss.opportunity_revived_rounds.get(id, -2) != actor.revived_round:
			boss.opportunity_thresholds[id] = int(actor.opportunity_count) + 1
			boss.opportunity_revived_rounds[id] = int(actor.revived_round)

static func release_mode(state: Dictionary, boss_id: String) -> String:
	var boss: Dictionary = state.actors[boss_id].boss
	if not boss.get("charge_valid", false): return "interrupted" if boss.get("charge_interrupted", false) else "unprepared"
	for id in opponents(state, boss_id):
		var actor: Dictionary = state.actors[id]
		if not boss.opportunity_thresholds.has(id) or boss.opportunity_revived_rounds.get(id, -2) != actor.revived_round or int(actor.opportunity_count) < int(boss.opportunity_thresholds[id]): return "waiting"
	for id in boss.locked_targets:
		if state.actors.has(id) and state.actors[id].hp > 0: return "release"
	return "empty"

static func on_slot_end(state: Dictionary, boss_id: String, skipped: bool) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[boss_id]
	var boss: Dictionary = actor.boss
	var previous: int = boss.step
	if previous in [3, 6] and not skipped and not boss.charge_fallback and release_mode(state, boss_id) == "waiting": return []
	if previous in [2, 5] and skipped:
		_clear_charge(boss)
	elif previous in [2, 5] and not boss.charge_valid:
		boss.charge_fallback = true
	elif previous in [3, 6]:
		_clear_charge(boss)
	boss.step = previous % 6 + 1
	return [_event("boss_step", boss_id, {"previous_step": previous, "step": boss.step, "skipped": skipped})]

static func interrupt(state: Dictionary, boss_id: String) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[boss_id]
	if not Status.immunity(actor, {"type": "interrupt"}).is_empty(): return []
	actor.boss["charge_valid"] = false
	actor.boss["charge_interrupted"] = true
	var source_id: String = state.get("active_actor_id", boss_id)
	if source_id.is_empty(): source_id = boss_id
	var events: Array[Dictionary] = [{"sequence": 0, "type": "charge_interrupted", "actor_id": source_id, "target_id": boss_id, "payload": {}}]
	var applied := Status.apply(actor, {"id": "stagger", "source_id": source_id, "magnitude": 0.2, "clock": "target_slot", "remaining": 1, "generation": 0, "applied_slot": 0, "dispellable": false, "snapshot": {}})
	if applied.applied: events.append(applied.event)
	return events

static func observe_phase(state: Dictionary, boss_id: String) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[boss_id]
	if actor.hp > 0 and actor.hp * 5 <= actor.stats.hp * 2 and actor.boss.phase == 1 and actor.boss.pending_phase == 0:
		actor.boss.pending_phase = 2
		actor.boss.pending_phase_round = int(state.round)
		return [_event("boss_phase_pending", boss_id, {"phase": 2, "round": state.round})]
	return []

static func on_round_start(state: Dictionary, boss_id: String) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[boss_id]
	var events: Array[Dictionary] = []
	if actor.hp > 0 and actor.boss.pending_phase == 2 and int(state.round) > int(actor.boss.pending_phase_round):
		actor.boss.phase = 2
		actor.boss.pending_phase = 0
		actor.boss.pending_phase_round = -1
		actor.stats.spd += 5
		events.append(_event("boss_phase_started", boss_id, {"phase": 2, "round": state.round, "spd": actor.stats.spd, "direct_damage_bonus": 0.2}))
	return events

static func phase_multiplier(actor: Dictionary) -> float:
	return 1.2 if actor.boss.get("phase", 1) == 2 else 1.0

static func is_committed_release(source: Dictionary, ability_id: String) -> bool:
	return source.boss.has("step") and source.boss.step in [3, 6] and ability_id == CYCLE[int(source.boss.step) - 1] and not source.boss.charge_fallback

static func _clear_charge(boss: Dictionary) -> void:
	boss.charge_valid = false
	boss.charge_interruptible = true
	boss.charge_interrupted = false
	boss.charge_fallback = false
	boss.locked_targets = []
	boss.opportunity_thresholds = {}
	boss.opportunity_revived_rounds = {}
	boss.committed_coefficient = 0.0
	boss.committed_phase_multiplier = 1.0
	boss.release_id = ""

static func _event(type: String, actor_id: String, payload: Dictionary) -> Dictionary:
	return {"sequence": 0, "type": type, "actor_id": actor_id, "target_id": actor_id, "payload": payload}
