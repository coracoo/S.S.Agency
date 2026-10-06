# 仅供隔离E2E：从公开预览挑选真实合法指令，不改HP、RNG、行动机会或胜负。
extends RefCounted
const Resolver = preload("res://scripts/rpg/effect_resolver.gd")
static func _command(state: Dictionary, actor_id: String, kind: String, ability_id: String = "", targets: Array = []) -> Dictionary:
	return {"command_id": "saga_test_%d_%s" % [state.revision, actor_id], "expected_revision": int(state.revision), "actor_id": actor_id, "kind": kind, "ability_id": ability_id, "target_ids": targets.duplicate()}
static func choose(state: Dictionary, engine: RefCounted, catalog: RefCounted) -> Dictionary:
	var actor: Dictionary = state.actors[state.active_actor_id]
	var options: Array = [["attack_physical", ""], ["attack_magic", ""], ["defend", ""]]
	for id in actor.skill_ids: options.append(["skill", id])
	for id in state.inventory: options.append(["item", id])
	var best: Dictionary = {}; var best_score := -INF
	for option in options:
		var base := _command(state, actor.actor_id, option[0], option[1])
		var ability: Dictionary = Resolver.ability_for(actor, base, catalog)
		if ability.is_empty(): continue
		var targets: Array = [[]]
		if not ability.target_rule in ["self", "all_allies", "all_enemies"]:
			targets = []
			for id in state.actors:
				var possible: Dictionary = state.actors[id]
				var ally: bool = possible.side == actor.side
				var rule: String = ability.target_rule
				if rule == "single_enemy" and (ally or possible.hp <= 0): continue
				if rule in ["single_ally", "other_ally"] and (not ally or possible.hp <= 0 or (rule == "other_ally" and id == actor.actor_id)): continue
				if rule == "fallen_ally" and (not ally or possible.hp > 0): continue
				targets.append([id])
		for target in targets:
			var command: Dictionary = base.duplicate(true); command.target_ids = target
			var preview: Dictionary = engine.preview(command)
			if not preview.legal: continue
			var score := -float(preview.mp_cost) * 0.6 - float(preview.item_cost) * 10
			for event in preview.effects:
				var subject: Dictionary = state.actors.get(event.target_id, {})
				match event.type:
					"damage":
						score += mini(int(event.payload.normal), int(subject.hp) + int(subject.shield.get("amount", 0)))
						if int(event.payload.normal) >= int(subject.hp) + int(subject.shield.get("amount", 0)): score += 60
					"saga_reflected": score -= float(event.payload.damage) * 3.0
					"charge_interrupted": score += 85
					"healed":
						if subject.side == "player" and float(subject.hp) / subject.stats.hp < 0.72: score += event.payload.actual * 2.0
					"revived": score += 260
					"mp_restored":
						if subject.mp <= 8 and subject.class_id in ["mage", "healer"]: score += 90
					"status_applied":
						var status: Dictionary = event.payload.status
						if subject.side == "enemy" and status.id == "stun" and not subject.statuses.any(func(s): return s.id == "stun"): score += 22
						if status.id == "defend": score += 4
			if score > best_score: best_score = score; best = command
	return best
