# 唯一效果管线；预览只在深复制上运行本管线，绝不访问引擎 RNG。
class_name RpgEffectResolver
extends RefCounted

const Damage = preload("res://scripts/rpg/damage_rules.gd")
const Status = preload("res://scripts/rpg/status_rules.gd")
const Boss = preload("res://scripts/rpg/boss_policy.gd")

static func ability_for(source: Dictionary, command: Dictionary, catalog: RefCounted) -> Dictionary:
	match command.get("kind", ""):
		"skill":
			var ability: Dictionary = catalog.skill_for(source, command.get("ability_id", "")) if source.side == "player" else catalog.get_definition("abilities", command.get("ability_id", ""))
			if Boss.is_committed_release(source, command.get("ability_id", "")):
				ability["target_rule"] = "committed_enemies"
				if source.boss.charge_valid:
					for effect in ability.effects:
						if effect.type == "damage": effect.coefficient = float(source.boss.committed_coefficient)
			return ability
		"item": return catalog.get_definition("items", command.get("ability_id", ""))
		"defend":
			return {"id": "defend", "target_rule": "self", "mp_cost": 0, "cooldown": 0, "effects": [{"type": "apply_status", "status_id": "defend", "magnitude": 0.4, "duration": 1, "clock": "next_owner_slot"}]}
		"attack_physical", "attack_magic":
			var magical: bool = command.kind == "attack_magic"
			return {"id": command.kind, "target_rule": "single_enemy", "mp_cost": 0, "cooldown": 0, "effects": [{"type": "damage", "damage_type": "magic" if magical else "physical", "element": "neutral", "coefficient": 0.65 if magical else 1.0, "single_direct": true, "can_crit": source.class_id != "gatekeeper"}]}
	return {}

static func resolve(state: Dictionary, command: Dictionary, catalog: RefCounted, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var source: Dictionary = state.actors[command.actor_id]
	var ability := ability_for(source, command, catalog)
	var committed := Boss.is_committed_release(source, command.get("ability_id", ""))
	if committed:
		var mode := Boss.release_mode(state, source.actor_id)
		if mode != "release":
			var type := "charge_wait" if mode == "waiting" else ("charge_empty" if mode == "empty" else "boss_idle")
			return [event(type, source.actor_id, source.actor_id, {"reason": mode, "step": source.boss.step, "locked_targets": source.boss.locked_targets.duplicate()})]
	for effect in ability.get("effects", []):
		if effect.type == "charge": return Boss.start_charge(state, source.actor_id, command.target_ids, effect, catalog)
	for original_id in command.target_ids:
		var target_id: String = original_id
		var cover_reduction := 0.0
		var redirected := false
		for effect in ability.get("effects", []):
			if effect.type == "damage" and redirected:
				target_id = original_id
			var target: Dictionary = state.actors[target_id]
			if effect.type != "revive" and int(target.hp) <= 0:
				continue
			match effect.type:
				"damage":
					# 只检查原单体命中一次；附带负面沿实际承伤者继续，不递归转伤。
					if not redirected and source.side == "enemy" and effect.get("single_direct", false):
						var cover := cover_for(state, target_id)
						if not cover.is_empty():
							target_id = cover.owner_id
							target = state.actors[target_id]
							cover_reduction = float(cover.status.magnitude)
							_remove_status(target, "cover", events, "cover_consumed", source.actor_id)
							events.append(event("cover_redirected", source.actor_id, target_id, {"original_target_id": original_id, "cover_reduction": cover_reduction}))
					redirected = true
					# 阶段加成只传一次；蓄力用承诺阶段，战意与虚弱仍由伤害模型读取。
					var phase_multiplier := float(source.boss.committed_phase_multiplier) if committed else Boss.phase_multiplier(source)
					var modifiers := {"cover_reduction": cover_reduction, "output_bonuses": [phase_multiplier - 1.0]}
					var damage_effect: Dictionary = effect.duplicate(true)
					if effect.get("condition") == "target_has_status" and target.statuses.any(func(status): return status.id == effect.status_id):
						damage_effect.coefficient = effect.conditional_coefficient
					elif effect.get("condition") == "target_no_slot_this_round" and int(target.get("last_slot_round", 0)) != int(state.round):
						damage_effect.coefficient = effect.conditional_coefficient
					var normal := Damage.direct(source, target, damage_effect, modifiers, false)
					var critical_result := Damage.direct(source, target, damage_effect, modifiers, true)
					var roll = null
					var critical := false
					if rng != null and effect.get("can_crit", true):
						roll = rng.randf()
						critical = roll < 0.05
					var calculation: Dictionary = critical_result if critical else normal
					var absorption := Damage.absorb(target, calculation.damage)
					events.append(event("damage", source.actor_id, target_id, {"original_target_id": original_id, "damage": calculation.damage, "factors": calculation.factors, "critical": critical, "can_crit": effect.get("can_crit", true), "critical_roll": roll, "normal": normal.damage, "critical_damage": critical_result.damage, "absorption": absorption}))
					if absorption.defeated:
						events.append(event("actor_defeated", source.actor_id, target_id, {"removed_statuses": absorption.removed_statuses, "shield_before": absorption.shield_before}))
						events.append_array(cleanup_defeated(state, target_id))
					cover_reduction = 0.0
				"consume_status":
					_remove_status(target, effect.status_id, events, "skill_consumed", source.actor_id)
				"apply_status":
					var owner: Dictionary = source if effect.status_id == "cover" else target
					var snapshot: Dictionary = {"target_id": original_id} if effect.status_id == "cover" else {}
					var magnitude := float(effect.magnitude)
					if effect.status_id == "burn":
						snapshot = Damage.burn_snapshot(source, effect)
						magnitude = float(snapshot.base)
					var definition: Dictionary = catalog.get_definition("statuses", effect.status_id)
					var status := {"id": effect.status_id, "source_id": source.actor_id, "magnitude": magnitude, "clock": definition.clock, "remaining": int(effect.duration), "generation": 0, "applied_slot": 0, "dispellable": definition.dispellable, "snapshot": snapshot}
					var applied := Status.apply(owner, status)
					if applied.applied:
						events.append(applied.event)
					else:
						events.append(event("effect_ignored", source.actor_id, owner.actor_id, {"effect": effect.duplicate(true), "reason": applied.reason}))
				"shield":
					var amount := roundi(float(effect.fixed) + float(effect.coefficient) * float(source.stats[effect.stat]))
					var applied := Status.apply_shield(target, {"amount": amount, "source_id": source.actor_id, "clock": effect.clock, "remaining": int(effect.duration)})
					if applied.applied:
						events.append(applied.event)
					else:
						events.append(event("effect_ignored", source.actor_id, target_id, {"effect": effect.duplicate(true), "reason": applied.reason}))
				"heal", "restore_hp", "restore_mp":
					var resource := "mp" if effect.type == "restore_mp" else "hp"
					var amount := int(effect.get("fixed", 0))
					if effect.type == "heal":
						amount = Damage.heal_amount(float(effect.fixed), float(effect.coefficient), float(source.stats[effect.stat]))
					var before := int(target[resource])
					target[resource] = mini(int(target.stats[resource]), before + amount)
					events.append(event("healed" if resource == "hp" else "mp_restored", source.actor_id, target_id, {"resource": resource, "before": before, "after": target[resource], "amount": amount, "actual": int(target[resource]) - before}))
				"revive":
					if int(target.hp) == 0:
						target.hp = maxi(1, roundi(float(target.stats.hp) * float(effect.fraction)))
						target.revived_round = int(state.round)
						events.append(event("revived", source.actor_id, target_id, {"hp": target.hp, "mp": target.mp, "round": state.round}))
				"cleanse": events.append_array(Status.cleanse(target))
				"interrupt":
					var reason := Status.immunity(target, effect)
					if reason.is_empty():
						events.append_array(Boss.interrupt(state, target_id))
					else:
						events.append(event("effect_ignored", source.actor_id, target_id, {"effect": effect.duplicate(true), "reason": reason}))
	return events

static func cover_for(state: Dictionary, target_id: String) -> Dictionary:
	var ids: Array = state.actors.keys()
	ids.sort()
	for id in ids:
		var actor: Dictionary = state.actors[id]
		if actor.hp <= 0 or actor.side != state.actors[target_id].side or id == target_id:
			continue
		for status in actor.statuses:
			if status.id == "cover" and status.snapshot.get("target_id", "") == target_id:
				return {"owner_id": id, "status": status.duplicate(true)}
	return {}

static func cleanup_defeated(state: Dictionary, defeated_id: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ids: Array = state.actors.keys()
	ids.sort()
	for id in ids:
		var actor: Dictionary = state.actors[id]
		for status in actor.statuses.duplicate():
			if status.id == "cover" and (id == defeated_id or status.snapshot.get("target_id", "") == defeated_id):
				_remove_status(actor, "cover", events, "linked_actor_defeated", defeated_id)
	return events

static func event(type: String, actor_id: String, target_id: String, payload: Dictionary) -> Dictionary:
	return {"sequence": 0, "type": type, "actor_id": actor_id, "target_id": target_id, "payload": payload}

static func _remove_status(actor: Dictionary, id: String, events: Array[Dictionary], reason: String, source_id: String) -> void:
	for index in range(actor.statuses.size() - 1, -1, -1):
		if actor.statuses[index].id == id:
			var removed: Dictionary = actor.statuses[index]
			actor.statuses.remove_at(index)
			events.append(event("status_removed", source_id, actor.actor_id, {"status": removed.duplicate(true), "reason": reason}))
