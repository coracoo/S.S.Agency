# 敌方原图的表现分类。只读已接受指令，不推导命中、伤害或修改敌人规则。
extends RefCounted
const RANGED_ACTORS := ["saga_anchor_left", "saga_anchor_right"]
const RANGED_ABILITIES := ["saga_paper_bind", "saga_anchor_left_strike", "saga_anchor_right_strike", "saga_banner_release", "saga_repair_left", "saga_repair_right"]

static func resolve(enemy_id: String, command: Dictionary, ability: Dictionary = {}) -> Dictionary:
	var kind := str(command.get("kind", "attack_physical"))
	var ability_id := str(command.get("ability_id", ""))
	var damage_type := str(ability.get("damage_type", "magic" if kind == "attack_magic" else "physical"))
	var element := str(ability.get("element", "neutral"))
	if kind in ["defend", "item"] or (kind == "skill" and damage_type == "none"):
		return {"style":"cast", "effect_id":"", "effect_form":"", "tint":Color("c8d7f0")}
	if damage_type == "magic":
		var effect_id := "firebolt" if element == "fire" else ("ice_arrow" if element == "ice" else "magic_break")
		var tint := Color("ffd19c") if element == "fire" else (Color("b9eaff") if element == "ice" else Color("d8b7fa"))
		return {"style":"cast", "effect_id":effect_id, "effect_form":"homura_mage" if effect_id != "magic_break" else "controller", "tint":tint}
	if ability_id in RANGED_ABILITIES or (kind == "attack_physical" and enemy_id in RANGED_ACTORS):
		return {"style":"ranged", "effect_id":"hunt", "effect_form":"mint", "tint":Color("edce99")}
	return {"style":"melee", "effect_id":"ambush", "effect_form":"mint", "tint":Color("f6cab8")}
