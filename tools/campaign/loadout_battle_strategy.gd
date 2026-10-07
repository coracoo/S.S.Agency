# 测试专用：读取公开意图与预览评估持续收益、有限补给和指挥者优先级，不改变模型。
extends RefCounted
const Resolver = preload("res://scripts/rpg/effect_resolver.gd")

static func choose(state: Dictionary, engine: RefCounted, catalog: RefCounted) -> Dictionary:
	var options := ranked(state, engine, catalog)
	return options[0].command.duplicate(true) if not options.is_empty() else {}

static func ranked(state: Dictionary, engine: RefCounted, catalog: RefCounted) -> Array:
	var actor: Dictionary = state.actors[state.active_actor_id]
	var options: Array = [["attack_physical", ""], ["attack_magic", ""], ["defend", ""]]
	for id in actor.skill_ids: options.append(["skill", id])
	for id in state.inventory:
		if int(state.inventory[id]) > 0: options.append(["item", id])
	var candidates: Array = []
	for option in options:
		var base := {"command_id": "loadout_tactic_%d_%s" % [state.revision, actor.actor_id], "expected_revision": int(state.revision), "actor_id": actor.actor_id, "kind": option[0], "ability_id": option[1], "target_ids": []}
		var ability: Dictionary = Resolver.ability_for(actor, base, catalog)
		if ability.is_empty(): continue
		var groups: Array = [[]]
		if not ability.target_rule in ["self", "all_allies", "all_enemies"]:
			groups = []
			for id in state.actors:
				var target: Dictionary = state.actors[id]
				var ally: bool = target.side == actor.side
				match ability.target_rule:
					"single_enemy":
						if ally or target.hp <= 0: continue
					"single_ally", "other_ally":
						if not ally or target.hp <= 0 or (ability.target_rule == "other_ally" and id == actor.actor_id): continue
					"fallen_ally":
						if not ally or target.hp > 0: continue
					_: continue
				groups.append([id])
		for targets in groups:
			var command := base.duplicate(true)
			command.target_ids = targets
			var preview: Dictionary = engine.preview(command)
			if not preview.legal: continue
			var reasons: Array[String] = []
			var interrupts := false
			var score := -float(preview.mp_cost) * 1.5 - float(preview.item_cost) * 10.0
			for event in preview.effects:
				var target: Dictionary = state.actors.get(event.target_id, {})
				if target.is_empty(): continue
				match event.type:
					"damage":
						var damage := mini(int(event.payload.normal), int(target.hp) + int(target.shield.get("amount", 0)))
						score += damage * _target_weight(state, target)
						if int(event.payload.normal) >= int(target.hp) + int(target.shield.get("amount", 0)):
							score += 500 if _commander(target) else 18
							reasons.append("击倒指挥者可令补位纸兵散去" if _commander(target) else "收尾目标")
					"saga_reflected": score -= float(event.payload.damage) * 4.0
					"charge_interrupted":
						interrupts = true
						score += 190
						reasons.append("公开意图处于可打断窗口，阻断号令/回补")
					"healed":
						if target.side == "player":
							var incoming := _incoming(state, target.actor_id)
							var urgency := 3.8 if target.hp <= incoming + 25 else (2.3 if float(target.hp) / target.stats.hp < 0.55 else 0.7)
							score += event.payload.actual * urgency
					"shield_applied":
						if target.side == "player":
							var increase := maxi(0, int(event.payload.shield.amount) - int(event.payload.get("previous", {}).get("amount", 0)))
							score += minf(increase, _incoming(state, target.actor_id)) * (2.2 if target.hp <= _incoming(state, target.actor_id) + 20 else 0.7)
					"revived":
						score += 420
						reasons.append("有限复苏恢复行动人数")
					"mp_restored":
						var threshold := 22 if target.skill_ids.has("heal") else (18 if target.skill_ids.has("firebolt") else (8 if target.skill_ids.has("shield_bash") else 4))
						if target.mp < threshold and int(event.payload.actual) >= 12:
							score += event.payload.actual * 4.0 + (100 if target.skill_ids.has("shield_bash") and target.mp < 7 else 35)
							if target.skill_ids.has("heal") and target.mp < 13: score += 100
							reasons.append("有限法力药保留打断/回复/主攻预算")
					"status_applied": score += _status_score(state, actor, target, event.payload.status, event.payload.get("previous", {}), reasons)
			# 保留两次打断预算；非窗口盾击不因附带短虚弱被误当成高效输出。
			if command.kind == "skill" and command.ability_id == "shield_bash" and not interrupts: score -= 100
			if command.kind == "skill" and command.ability_id == "seal" and interrupts and not targets.is_empty() and _cheaper_interrupt_available(state, actor, state.actors[targets[0]], catalog):
				score -= 160
				reasons.append("另一队员能在目标行动前用更便宜盾击接手")
			if command.kind == "skill" and command.ability_id != "shield_bash" and actor.skill_ids.has("shield_bash"):
				var interrupt_cost: int = catalog.skill_for(actor, "shield_bash").get("mp_cost", 0)
				if actor.mp - int(preview.mp_cost) < interrupt_cost * 2: score -= 90
			candidates.append({"command": command, "score": score, "reasons": reasons, "mp_cost": preview.mp_cost, "item_cost": preview.item_cost})
	candidates.sort_custom(func(a, b): return a.score > b.score)
	return candidates

static func _cheaper_interrupt_available(state: Dictionary, source: Dictionary, target: Dictionary, catalog: RefCounted) -> bool:
	for ally in state.actors.values():
		if ally.actor_id == source.actor_id or ally.side != source.side or ally.hp <= 0 or not ally.skill_ids.has("shield_bash"): continue
		var cost: int = catalog.skill_for(ally, "shield_bash").get("mp_cost", 999)
		if ally.mp < cost or int(ally.cooldown_until.get("shield_bash", 0)) > int(ally.slot_count) + 1: continue
		var ally_index: int = state.queue.find(ally.actor_id)
		var target_index: int = state.queue.find(target.actor_id)
		if ally_index > int(state.queue_index) or (ally_index >= 0 and target_index >= 0 and ally_index < target_index): return true
	return false

static func _commander(actor: Dictionary) -> bool:
	return actor.get("class_id") in ["saga_lamp_bearer", "saga_backshore_general"]

static func _target_weight(state: Dictionary, target: Dictionary) -> float:
	if _commander(target): return 2.0
	if target.class_id == "saga_paper_soldier":
		for actor in state.actors.values():
			if _commander(actor) and actor.hp > 0: return 0.5
	return 1.0

static func _incoming(state: Dictionary, actor_id: String) -> float:
	var amount := 0.0
	for enemy in state.actors.values():
		if enemy.side != "enemy" or enemy.hp <= 0 or enemy.get("saga", {}).get("interrupted", false): continue
		for range_row in enemy.get("intent", {}).get("preview", {}).get("damage_ranges", []):
			if range_row.get("target_id") == actor_id: amount += float(range_row.normal)
	return amount

static func _status_score(state: Dictionary, source: Dictionary, target: Dictionary, status: Dictionary, previous: Dictionary, reasons: Array[String]) -> float:
	var magnitude := float(status.magnitude)
	var duration := int(status.remaining)
	if target.side == "enemy":
		var weight := _target_weight(state, target)
		match status.id:
			"burn":
				var extra := maxf(0.0, magnitude * duration - float(previous.get("magnitude", 0)) * int(previous.get("remaining", 0)))
				reasons.append("按未兑现的灼烧持续伤害计分")
				return extra * 1.2 * weight + (25 if source.identity_id == "homura" and source.skill_ids.has("firebolt") and previous.is_empty() else 0)
			"stun":
				if not previous.is_empty() or target.get("saga", {}).get("interrupted", false): return 0
				var expected_damage := 0.0
				for range_row in target.get("intent", {}).get("preview", {}).get("damage_ranges", []): expected_damage += float(range_row.normal)
				return 30.0 + expected_damage * 1.25
			"weaken":
				if not previous.is_empty(): return 0
				reasons.append("计入后续群体伤害减免")
				return magnitude * minf(2.0, duration) * float(target.stats.matk + target.stats.atk) * (1.4 if _commander(target) else 0.6)
			"magic_break", "armor_break":
				if not previous.is_empty(): return 0
				return 8.0 * minf(2.0, duration) * weight
			"slow":
				if not previous.is_empty(): return 0
				return 12.0 * weight
	else:
		if status.id == "defend": return _incoming(state, target.actor_id) * magnitude * (2.4 if target.hp < _incoming(state, target.actor_id) + 30 else 0.4)
		if status.id == "battle_spirit" and previous.is_empty(): return float(target.stats.atk) * magnitude * minf(2, duration) * 1.3
	return 0.0
