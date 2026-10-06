extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(1); return
	var path := "res://scripts/campaign/saga_battle_narrator.gd"
	if not ResourceLoader.exists(path): failures.append("真实战斗事件需连接原文战中提示")
	else:
		var narrator = load(path)
		var line := {"speaker":"薄荷", "text":"浅面朝这边了，先别用刀硬碰！", "event":{"type":"intent_updated", "requires":{"intent.ability_id":"saga_mirror_edge"}}, "once_per_battle":true}
		var state := {"party":["p_swordsman", "p_ranger", "p_guard"], "saga":{"flags":{}, "completed":[], "choices":{}, "battles":[]}}
		var seen := {}
		var event := {"type":"intent_updated", "actor_id":"enemy", "target_id":"", "payload":{"intent":{"ability_id":"saga_mirror_edge"}}}
		if narrator.select([line], event, state, seen) != ["薄荷：浅面朝这边了，先别用刀硬碰！"]: failures.append("匹配真实意图才播相应提示")
		if not narrator.select([line], event, state, seen).is_empty(): failures.append("同场提示不应每轮刷屏")
		seen.clear(); event.payload.intent.ability_id="different"
		if not narrator.select([line], event, state, seen).is_empty(): failures.append("反射类型不匹配时不误播")
	for failure in failures: printerr("FAIL: ", failure)
	print("SAGA_NARRATION: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
