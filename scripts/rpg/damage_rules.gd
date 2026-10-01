# 纯数值规则：不读取场景、随机数、存档或全局状态，所有乘区最后才取整。
class_name RpgDamageRules
extends RefCounted

static func direct(source: Dictionary, target: Dictionary, effect: Dictionary, modifiers: Dictionary, critical: bool) -> Dictionary:
	var damage_type: String = effect.get("damage_type", "physical")
	var attack_key := "atk" if damage_type == "physical" else "matk"
	var defense_key := "def" if damage_type == "physical" else "mdef"
	var break_id := "armor_break" if damage_type == "physical" else "magic_break"
	var attack := maxf(0.0, float(source.get("stats", {}).get(attack_key, 0)))
	var coefficient := maxf(0.0, float(effect.get("coefficient", 0.0)))
	var raw_defense := maxf(0.0, float(target.get("stats", {}).get(defense_key, 0)))
	var defense_reduction := _strongest(_strength(target, break_id), modifiers.get("defense_reductions", []))
	var effective_defense := maxf(0.0, raw_defense * (1.0 - defense_reduction))
	var defense_factor := 100.0 / (100.0 + effective_defense)
	var base := attack * coefficient * defense_factor
	var element: String = effect.get("element", "neutral")
	var element_factor := _element_factor(target, element)
	var output_bonus := clampf(_strength(source, "battle_spirit") + _sum(modifiers.get("output_bonuses", [])), 0.0, 0.5)
	var weaken := _strongest(_strength(source, "weaken"), modifiers.get("weaken_reductions", []))
	var vulnerability := clampf(_strength(target, "stagger") + _sum(modifiers.get("vulnerability_bonuses", [])), 0.0, 0.25)
	var critical_factor := 1.5 if critical and effect.get("can_crit", true) else 1.0
	var reduction := _strongest(_strength(target, "defend"), modifiers.get("damage_reductions", []))
	var cover := clampf(float(modifiers.get("cover_reduction", 0.0)), 0.0, 1.0)
	var unrounded := base * element_factor * (1.0 + output_bonus) * (1.0 - weaken) * (1.0 + vulnerability) * critical_factor * (1.0 - reduction) * (1.0 - cover)
	return {
		"damage": maxi(1, roundi(unrounded)) if unrounded > 0.0 else 0,
		"factors": {
			"damage_type": damage_type, "attack_stat": attack, "coefficient": coefficient,
			"raw_defense": raw_defense, "defense_reduction": defense_reduction,
			"effective_defense": effective_defense, "defense_factor": defense_factor, "base": base,
			"element": element, "element_factor": element_factor,
			"output_bonus": output_bonus, "output_factor": 1.0 + output_bonus,
			"weaken_reduction": weaken, "weaken_factor": 1.0 - weaken,
			"vulnerability_bonus": vulnerability, "vulnerability_factor": 1.0 + vulnerability,
			"critical_factor": critical_factor, "reduction": reduction, "reduction_factor": 1.0 - reduction,
			"cover_reduction": cover, "cover_factor": 1.0 - cover, "unrounded": unrounded
		}
	}

# 返回状态 snapshot；调用者以 base 作为灼烧 magnitude 比较强弱，不能提前取整。
# output_bonuses 只传适用于持续伤害的增益；战意永远不进入此快照。
static func burn_snapshot(source: Dictionary, effect: Dictionary, modifiers: Dictionary = {}) -> Dictionary:
	var matk := maxf(0.0, float(source.get("stats", {}).get("matk", 0)))
	var coefficient := maxf(0.0, float(effect.get("magnitude", 0.0)))
	var output_bonus := clampf(_sum(modifiers.get("output_bonuses", [])), 0.0, 0.5)
	var weaken := _strongest(_strength(source, "weaken"), modifiers.get("weaken_reductions", []))
	return {"source_matk": matk, "coefficient": coefficient, "output_factor": 1.0 + output_bonus, "weaken_factor": 1.0 - weaken, "base": matk * coefficient * (1.0 + output_bonus) * (1.0 - weaken)}

static func periodic(status: Dictionary, target: Dictionary) -> Dictionary:
	var base := maxf(0.0, float(status.get("magnitude", 0.0)))
	var element_factor := _element_factor(target, "fire")
	var reduction := clampf(_strength(target, "defend"), 0.0, 1.0)
	var unrounded := base * element_factor * (1.0 - reduction)
	return {
		"damage": maxi(0, roundi(unrounded)),
		"factors": {"base": base, "source_snapshot": status.get("snapshot", {}).duplicate(true), "element": "fire", "element_factor": element_factor, "reduction": reduction, "reduction_factor": 1.0 - reduction, "unrounded": unrounded}
	}

static func heal_amount(fixed: float, coefficient: float, matk: float) -> int:
	return maxi(0, roundi(fixed + coefficient * matk))

# 只处理目标本身。战斗引擎另行清理其他角色指向倒地者的掩护关系。
static func absorb(target: Dictionary, amount: int) -> Dictionary:
	var hp_before := maxi(0, int(target.get("hp", 0)))
	var shield_before: Dictionary = target.get("shield", {}).duplicate(true)
	var shield_amount := maxi(0, int(shield_before.get("amount", 0)))
	var absorbed := mini(maxi(0, amount), shield_amount) if hp_before > 0 else 0
	var hp_loss := mini(hp_before, maxi(0, amount - absorbed))
	var removed_statuses: Array = []
	if amount > 0 and hp_before > 0:
		if absorbed > 0:
			target.shield.amount = shield_amount - absorbed
			if target.shield.amount == 0:
				target.shield = {}
		if hp_loss > 0:
			target.hp = hp_before - hp_loss
		if target.hp == 0:
			removed_statuses = target.get("statuses", []).duplicate(true)
			target.statuses = []
			target.shield = {}
			target.intent = {}
			if not target.get("boss", {}).is_empty():
				target.boss["charge_valid"] = false
	return {"absorbed": absorbed, "hp_loss": hp_loss, "defeated": int(target.get("hp", 0)) == 0, "hp_before": hp_before, "hp_after": int(target.get("hp", 0)), "shield_before": shield_before, "shield_after": target.get("shield", {}).duplicate(true), "removed_statuses": removed_statuses}

static func _strength(actor: Dictionary, id: String) -> float:
	var result := 0.0
	for status in actor.get("statuses", []):
		if status.get("id", "") == id and int(status.get("remaining", 0)) > 0:
			result = maxf(result, float(status.get("magnitude", 0.0)))
	return result

static func _element_factor(target: Dictionary, element: String) -> float:
	if element == "neutral":
		return 1.0
	if target.get("weaknesses", []).has(element):
		return 1.25
	if target.get("resistances", []).has(element):
		return 0.75
	return 1.0

static func _sum(values: Array) -> float:
	var result := 0.0
	for value in values:
		result += maxf(0.0, float(value))
	return result

static func _strongest(initial: float, values: Array) -> float:
	var result := initial
	for value in values:
		result = maxf(result, float(value))
	return clampf(result, 0.0, 1.0)
