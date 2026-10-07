# 个人专精是既有技能的只读派生，不新增卡位、资源池或存档字段。
class_name RpgCharacterRefinements
extends RefCounted
const Forms = preload("res://scripts/rpg/dual_form.gd")
const BINDINGS := {
	"rinne_swordsman": ["rinne", "swordsman", "heavy_slash"],
	"mint_ranger": ["mint", "ranger", "ambush"],
	"guard_guard": ["guard", "guard", "shield_bash"],
	"homura_swordsman": ["homura", "swordsman", "armor_break"],
	"homura_mage": ["homura", "mage", "firebolt"],
	"healer_healer": ["healer", "healer", "heal"],
	"controller_controller": ["controller", "controller", "magic_break"]
}

static func for_actor(actor: Dictionary, definitions: Dictionary) -> Dictionary:
	if actor.get("side") != "player": return {}
	if actor.get("identity_id") == "homura" and not Forms.enabled(actor): return {}
	var id := str(actor.get("identity_id", "")) + "_" + Forms.active_class(actor)
	return definitions.get(id, {}).duplicate(true)

# 先完成L6/L9分支，再以当前系数追加条件收益，避免覆盖已选分支。
static func apply(skill: Dictionary, refinement: Dictionary) -> Dictionary:
	var result := skill.duplicate(true)
	result.mp_cost += int(refinement.mp_cost_add)
	result.cooldown += int(refinement.cooldown_add)
	result.name += "·" + refinement.name
	result["refinement"] = refinement.duplicate(true)
	var condition: Dictionary = refinement.damage_condition
	if not condition.is_empty():
		for effect in result.effects:
			if effect.type != "damage": continue
			effect["condition"] = "target_has_status"
			effect["status_id"] = condition.status_id
			effect["conditional_coefficient"] = float(effect.coefficient) + float(condition.coefficient_add)
	result.effects.append_array(refinement.extra_effects.duplicate(true))
	return result

# L4/L5技法仍派生同一个技能ID，冷却键与卡位不变；不在角色快照保存副本。
static func apply_technique(skill: Dictionary, technique: Dictionary) -> Dictionary:
	var result := skill.duplicate(true)
	result.mp_cost += int(technique.mp_cost_add)
	result.cooldown += int(technique.cooldown_add)
	result.name += "·" + technique.name
	result["technique"] = technique.duplicate(true)
	result.effects.append_array(technique.extra_effects.duplicate(true))
	return result
