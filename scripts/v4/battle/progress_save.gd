class_name ProgressSaveV4
extends RefCounted
## V4 成长存档（GDD §9.1 成长 / §5.2 新卡进入收藏 / D 期完整单元闭环）。
## 存 user://progress.json：{unlocked_cards:[], unlocked_artifacts:[], cases_done:[]}
## 解锁规则（唯一判定点）：卡/器物 def 的 unlock 字段为空或 "start" → 初始可用；
## 其余（如案件 id）必须出现在本档对应列表里。无档时按初始可用判定。

const PATH := "user://progress.json"

static func load_progress() -> Dictionary:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {"unlocked_cards": [], "unlocked_artifacts": [], "cases_done": []}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		var p: Dictionary = parsed
		p["unlocked_cards"] = p.get("unlocked_cards", [])
		p["unlocked_artifacts"] = p.get("unlocked_artifacts", [])
		p["cases_done"] = p.get("cases_done", [])
		return p
	return {"unlocked_cards": [], "unlocked_artifacts": [], "cases_done": []}

static func save_progress(p: Dictionary) -> bool:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(p, "\t"))
	return true

## 卡是否已在收藏（def: 卡库卡定义；看 unlock 字段）
static func is_card_unlocked(def: Dictionary) -> bool:
	var u := String(def.get("unlock", ""))
	if u.is_empty() or u == "start":
		return true
	return (load_progress().get("unlocked_cards", []) as Array).has(u) \
		or (load_progress().get("unlocked_cards", []) as Array).has(def.get("id", ""))

static func is_artifact_unlocked(def: Dictionary) -> bool:
	var u := String(def.get("unlock", ""))
	if u.is_empty() or u == "start":
		return true
	var p: Dictionary = load_progress()
	return (p.get("unlocked_artifacts", []) as Array).has(u) \
		or (p.get("unlocked_artifacts", []) as Array).has(def.get("id", ""))

## 授予案件奖励（幂等：已解锁的不重复添加）。返回 {cards:[新解锁卡id], artifacts:[...]}
static func grant(case_id: String, rewards: Dictionary) -> Dictionary:
	var p := load_progress()
	var new_cards: Array = []
	for cid in (rewards.get("cards", []) as Array):
		if not (p["unlocked_cards"] as Array).has(cid):
			p["unlocked_cards"].append(cid)
			new_cards.append(cid)
	var new_artifacts: Array = []
	for aid in (rewards.get("artifacts", []) as Array):
		if not (p["unlocked_artifacts"] as Array).has(aid):
			p["unlocked_artifacts"].append(aid)
			new_artifacts.append(aid)
	if not (p["cases_done"] as Array).has(case_id):
		p["cases_done"].append(case_id)
	save_progress(p)
	return {"cards": new_cards, "artifacts": new_artifacts}

static func is_case_done(case_id: String) -> bool:
	return (load_progress().get("cases_done", []) as Array).has(case_id)
