# 终战补给规则由已提交胜利与原重试事件派生，不新增奖励或隐式恢复。
class_name CampaignSupplyRules
extends RefCounted

const FINAL_SCENES := ["C7-10", "C7-11", "C7-12", "C7-13"]

static func stage_for(scene_id: String) -> int:
	if scene_id == "C7-05": return 1
	if scene_id == "C7-06": return 2
	return 3 if scene_id in FINAL_SCENES else 0

static func restricted(saved: Dictionary) -> bool:
	if saved.get("schema_version") != 3 or not saved.get("saga") is Dictionary: return false
	var saga: Dictionary = saved.saga
	var battles: Array = saga.get("battles", [])
	if not battles.has("C7-05") or not str(saga.get("ending", "")).is_empty(): return false
	for scene_id in FINAL_SCENES:
		if battles.has(scene_id): return false
	# 败北返场使用原C7-R04整备窗口；选完对白之后仍可准备，直到该阶段获胜。
	# 不回填历史补给限制，也不把旧档已有资源清空。
	if not saga.get("retry", {}).is_empty(): return false
	var next_stage := 3 if battles.has("C7-06") else 2
	for index in range(saga.get("events", []).size() - 1, -1, -1):
		var event: Dictionary = saga.events[index]
		if event.id == "C7-R04": return int(event.get("retry_stage", 0)) != next_stage
	return true

static func reason(saved: Dictionary) -> String:
	if not restricted(saved): return ""
	return "终战正在延续：请使用携带的药物并调整装配。阶段之间不提供歇脚恢复与采购；若败北，可按原路径返回整备。"

static func battle_notice(saved: Dictionary, scene_id: String) -> String:
	if stage_for(scene_id) == 0: return ""
	if restricted(saved): return reason(saved)
	return "应战前可歇脚、采购并调整装配。本阶段获胜后，剩余生命、灵力与药物会带入下一阶段；已赢得的阶段不会重复发奖。"
