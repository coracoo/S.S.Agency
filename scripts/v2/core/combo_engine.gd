class_name ComboEngine
extends RefCounted
## 卡牌 combo 引擎 v2
##
## 由旧 terrain_system.gd 改造而来，保留"事件触发→规则匹配→结果应用"的规则模拟器骨架，
## 去掉所有 map/pos/格子语义。trigger 基于 [Unit] 上的 tag 和卡牌的 tag。
##
## 例：对带 [wet] 标签的目标打出带 [lightning] 标签的牌 → 触发电流链 → 蔓延到所有 [wet] 敌人。
##
## 重入保护与待处理队列沿用旧设计（_processing + _pending），避免连锁中再次连锁导致死循环。

signal combo_triggered(combo_id: String, primary_target, affected_targets: Array)

var _combos: Array = []
var _processing: bool = false
var _pending: Array = []  # 待处理的触发请求队列


func _init() -> void:
	load_combos("res://data/v2/combos.json")


func load_combos(path: String) -> void:
	_combos.clear()
	var data = JsonLoader.load_file(path)
	if not (data is Dictionary):
		push_error("ComboEngine: failed to load " + path)
		return
	var arr = data.get("combos", [])
	if not (arr is Array):
		return
	for c in arr:
		if c is Dictionary and c.has("id") and c.has("trigger") and c.has("result"):
			_combos.append(c.duplicate(true))


## 检查并触发 combo。
## [param card_tags] 当前打出卡牌的标签数组（如 ["talisman","lightning"]）
## [param primary_target] 主要目标单位
## [param context] 战斗上下文（含 players/enemies 列表，用于 spread 蔓延查询）
func try_trigger(card_tags: Array, primary_target, context: Dictionary) -> Array:
	var request := {
		"card_tags": card_tags.duplicate(),
		"primary_target": primary_target,
		"context": context
	}
	_pending.append(request)
	if _processing:
		# 递归触发：排队，由当前处理循环结束后消费
		return []
	return _drain_pending()


func _drain_pending() -> Array:
	_processing = true
	var all_results: Array = []
	while not _pending.is_empty():
		var req = _pending.pop_front()
		all_results.append_array(_process_one(req))
	_processing = false
	return all_results


func _process_one(req: Dictionary) -> Array:
	# primary_target 类型不注解（避免 Unit/UnitV2 类型歧义）
	# 主目标可以是任意带 has_tag() 方法的对象
	var card_tags: Array = req.get("card_tags", [])
	var primary = req.get("primary_target", null)
	var context: Dictionary = req.get("context", {})
	var results: Array = []
	for combo in _combos:
		if not _conditions_met(combo.trigger, card_tags, primary):
			continue
		var affected := _resolve_spread(combo.result, primary, context)
		results.append({
			"combo_id": combo.get("id", ""),
			"combo_name": combo.get("name", ""),
			"primary_target": primary,
			"affected_targets": affected,
			"effects": combo.result
		})
		combo_triggered.emit(combo.get("id", ""), primary, affected)
	return results


func _conditions_met(trigger: Dictionary, card_tags: Array, target) -> bool:
	if target == null:
		return false
	var required_card_tag = trigger.get("card_tag", "")
	if required_card_tag != "" and not card_tags.has(required_card_tag):
		return false
	var required_target_tag = trigger.get("target_tag", "")
	if required_target_tag != "" and not target.has_tag(required_target_tag):
		return false
	return true


## 解析 result 数组里的 spread 字段，返回该 combo 影响到的目标单位列表
func _resolve_spread(result: Array, primary, context: Dictionary) -> Array:
	# spread 可能出现在多个 result 项里，取并集；这里简化为遍历每个 result 项的 spread
	var affected: Array = [primary]
	var players: Array = context.get("players", [])
	var enemies: Array = context.get("enemies", [])
	for r in result:
		var spread: String = r.get("spread", "primary")
		if spread == "primary" or spread == "":
			continue
		elif spread == "all_enemies":
			for e in enemies:
				if e != null and e.is_alive and not affected.has(e):
					affected.append(e)
		elif spread == "all_players":
			for p in players:
				if p != null and p.is_alive and not affected.has(p):
					affected.append(p)
		elif spread.begins_with("enemies_with_tag:"):
			var tag = spread.substr("enemies_with_tag:".length())
			for e in enemies:
				if e != null and e.is_alive and e.has_tag(tag) and not affected.has(e):
					affected.append(e)
		elif spread.begins_with("players_with_tag:"):
			var tag = spread.substr("players_with_tag:".length())
			for p in players:
				if p != null and p.is_alive and p.has_tag(tag) and not affected.has(p):
					affected.append(p)
	return affected
