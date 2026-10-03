# 所有参道子组共享同一个隔离入口。
extends RefCounted
static func run() -> Array[String]:
	var failures: Array[String] = []
	for group in ["snapshot", "session", "world", "visuals", "flow", "menu", "battle_loop", "portraits", "transition"]:
		var test = load("res://tools/rpg/test_approach_%s.gd" % group)
		if test == null or not test.has_method("run"):
			failures.append("无法加载参道测试组：" + group)
			continue
		var result: Array = await test.run()
		failures.append_array(result)
		print("approach/%s: %s" % [group, "PASS" if result.is_empty() else "FAIL"])
	return failures
