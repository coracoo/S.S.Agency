# 真实轮序与界面条件推演共用排序；不在界面维护第二套速度公式。
class_name RpgTurnOrder
extends RefCounted
const Status = preload("res://scripts/rpg/status_rules.gd")

static func from_snapshots(actors: Dictionary, snapshots: Array) -> Dictionary:
	var speeds := {}
	var queue: Array[String] = []
	for item in snapshots:
		queue.append(str(item.target_id))
		speeds[item.target_id] = float(item.payload.effective_spd)
	queue.sort_custom(func(a: String, b: String) -> bool:
		if speeds[a] != speeds[b]: return speeds[a] > speeds[b]
		if actors[a].side != actors[b].side: return actors[a].side == "player"
		return a < b)
	return {"queue":queue,"effective_speeds":speeds}

static func forecast(state: Dictionary) -> Dictionary:
	# 只回答“按当前存活者及状态”的下轮排序，不预言本轮剩余行动、召回和阶段变更。
	# 两次状态时钟均只作用于深副本；真实remaining、generation、RNG和日志不变。
	var actors: Dictionary = state.get("actors",{}).duplicate(true)
	Status.end_round(actors)
	return from_snapshots(actors,Status.begin_round(actors))

static func committed_speeds(state: Dictionary) -> Dictionary:
	var events: Array = state.get("event_log",[])
	for index in range(events.size()-1,-1,-1):
		var item: Dictionary = events[index]
		if item.get("type") == "round_queue" and item.get("payload",{}).get("round") == state.get("round"):
			return item.payload.get("effective_speeds",{}).duplicate(true)
	return {}
