# 三种公开、确定的启发式；只调用只读预览，不模拟未来、不读取随机状态。
class_name RpgStrategyPolicies
extends RefCounted
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Resolver = preload("res://scripts/rpg/effect_resolver.gd")
const IDS := ["direct_damage", "defensive_counter", "control_burst"]
var last_decision: Dictionary = {}
var _catalog: RefCounted

func _init(catalog: RefCounted = null) -> void:
	_catalog = catalog
	if _catalog == null:
		_catalog = Catalog.new()
		_catalog.load_all()

func choose(policy_id: String, state: Dictionary, engine: RefCounted) -> Dictionary:
	last_decision = {}
	if not IDS.has(policy_id) or state.get("phase") != "action_selection": return {}
	var actor: Dictionary = state.actors.get(state.active_actor_id, {})
	if actor.is_empty() or actor.side != "player": return {}
	var options: Array[Dictionary] = []
	for kind in ["attack_physical", "attack_magic", "defend"]:
		_add_candidates(options, state, engine, kind, "")
	for id in actor.skill_ids: _add_candidates(options, state, engine, "skill", id)
	var items: Array = state.inventory.keys()
	items.sort()
	for id in items: _add_candidates(options, state, engine, "item", id)
	var best: Dictionary = {}
	var best_score := -INF
	for option in options:
		var rated := _score(policy_id, state, option.command, option.preview)
		# 同分保持枚举顺序：基础动作、固定四技能、字典序道具/目标。
		if float(rated.score) > best_score:
			best_score = rated.score
			best = option.command
			last_decision = {"round": state.round, "actor_id": actor.actor_id, "command": best.duplicate(true), "reason": rated.reason, "score": best_score, "preview": option.preview.duplicate(true)}
	return best.duplicate(true)

func _add_candidates(options: Array[Dictionary], state: Dictionary, engine: RefCounted, kind: String, id: String) -> void:
	var command := {"command_id": "sweep_%d_%s" % [state.revision, state.active_actor_id], "expected_revision": int(state.revision), "actor_id": state.active_actor_id, "kind": kind, "ability_id": id, "target_ids": []}
	var ability := Resolver.ability_for(state.actors[state.active_actor_id], command, _catalog)
	if ability.is_empty(): return
	var targets: Array = [[]]
	if not ability.target_rule in ["self", "all_allies", "all_enemies"]:
		targets = []
		var ids: Array = state.actors.keys()
		ids.sort()
		for target in ids: targets.append([target])
	for target in targets:
		var candidate := command.duplicate(true)
		candidate.target_ids = target
		var preview: Dictionary = engine.preview(candidate)
		if preview.legal: options.append({"command": candidate, "preview": preview})

func _score(policy: String, state: Dictionary, command: Dictionary, preview: Dictionary) -> Dictionary:
	var score := -float(preview.mp_cost) * 0.7 - float(preview.item_cost) * 12.0
	var reasons: Array[String] = []
	var defensive := policy == "defensive_counter"
	var control := policy == "control_burst"
	for effect in preview.effects:
		var target: Dictionary = state.actors.get(effect.target_id, {})
		var payload: Dictionary = effect.payload
		match effect.type:
			"damage":
				var actual := mini(int(payload.normal), int(target.hp) + int(target.shield.get("amount", 0)))
				score += actual
				if int(payload.normal) >= int(target.hp) + int(target.shield.get("amount", 0)): score += 60
				reasons.append("公开非暴击伤害%d" % actual)
			"revived":
				score += 220
				reasons.append("复苏倒地队员")
			"healed":
				var ratio := float(target.hp) / float(target.stats.hp)
				var threshold := 0.65 if defensive else 0.35
				if ratio <= threshold:
					score += float(payload.actual) * (2.2 if defensive else 2.0)
					reasons.append("低血治疗%d" % payload.actual)
			"mp_restored":
				if target.mp <= 8 and target.class_id in ["healer", "mage", "controller"]:
					score += 70
					reasons.append("施法者MP不足")
			"charge_interrupted":
				score += 240 if defensive or control else 0
				reasons.append("打断已公开蓄力")
			"status_applied", "status_refreshed":
				var status: Dictionary = payload.get("status", payload.get("after", {}))
				var status_id: String = status.get("id", "")
				if target.side == "enemy" and control:
					var weights := {"mark": 80, "stun": 95, "slow": 45, "weaken": 50, "armor_break": 45, "magic_break": 50, "burn": 42}
					# 不为了得分无限刷新仍在生效的铺垫。
					if not target.statuses.any(func(current): return current.id == status_id): score += weights.get(status_id, 0)
					reasons.append("控制/铺垫：" + status_id)
				if defensive and status_id == "defend":
					var incoming := _incoming(state, command.actor_id)
					if incoming > float(target.hp) * 0.35: score += incoming * 1.5
					if _locked_threat(state, command.actor_id): score += 100
				if defensive and status_id == "cover":
					var protected: String = status.get("snapshot", {}).get("target_id", "")
					if _incoming(state, protected) > 0 and float(state.actors[protected].hp) / float(state.actors[protected].stats.hp) < 0.5: score += 70
			"shield_applied", "shield_refreshed":
				if defensive and (_incoming(state, effect.target_id) > 0 or _locked_threat(state, effect.target_id)):
					var shield: Dictionary = payload.get("shield", payload.get("after", {}))
					score += mini(int(shield.get("amount", 0)), maxi(0, int(target.stats.hp) - int(target.hp))) * 1.3
					reasons.append("护盾响应公开威胁")
			"status_removed":
				if payload.get("reason") == "cleanse":
					score += 45 if defensive else 15
					reasons.append("清除负面")
	if reasons.is_empty(): reasons.append("无有效高优先级效果，保留合法基础候选")
	return {"score": score, "reason": "；".join(reasons)}

static func _incoming(state: Dictionary, target_id: String) -> float:
	var amount := 0.0
	for actor in state.actors.values():
		if actor.side != "enemy" or actor.hp <= 0: continue
		for damage in actor.intent.get("preview", {}).get("damage_ranges", []):
			if damage.target_id == target_id: amount += float(damage.normal)
	return amount

static func _locked_threat(state: Dictionary, target_id: String) -> bool:
	for actor in state.actors.values():
		if actor.side == "enemy" and actor.hp > 0 and actor.intent.get("locked", false) and actor.intent.get("target_ids", []).has(target_id) and not actor.intent.get("interruptible", false):
			# 只响应当前意图明确存在的蓄力/释放，不读Boss内部步骤或未来行动。
			for event in actor.intent.get("preview", {}).get("effects", []):
				if event.type in ["charge_started", "charge_wait", "damage"]: return true
	return false
