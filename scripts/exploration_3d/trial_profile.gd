# 身份和技能职业分离；本段只有三个试用角色，不定义正式入队。
class_name ApproachTrialProfile
extends RefCounted
const World = preload("res://scripts/exploration_3d/world_snapshot.gd")
const SAVE_PATH := "user://rpg_v1/approach_3d_01.json"
const ID := "approach_3d_v1"
const CLASS_IDS: Array[String] = ["swordsman", "ranger", "guard"]
const PARTY := ["p_swordsman", "p_ranger", "p_guard"]
const BINDINGS := {"p_swordsman": {"identity_id": "rinne", "form_id": "rinne"}, "p_ranger": {"identity_id": "mint", "form_id": "mint"}, "p_guard": {"identity_id": "guard", "form_id": "guard"}}
static func make(world: Dictionary) -> Dictionary:
	return {"id": ID, "bindings": BINDINGS.duplicate(true), "world": world.duplicate(true)}
static func validate(profile: Dictionary) -> Array[String]:
	if profile.get("id") != ID or profile.get("bindings") != BINDINGS: return ["试玩身份配置不符"]
	for key in profile:
		if not key in ["id", "bindings", "world"]: return ["未知试玩配置字段"]
	if profile.has("world"):
		if not profile.world is Dictionary: return ["试玩世界必须是字典"]
		return World.validate(profile.world)
	return []
