# 分组遵守失败数组契约；显式加载，不依赖全局类缓存。
extends SceneTree

const SUITES := ["data", "rules", "engine", "replay", "ai", "campaign", "ui", "roster", "approach", "acceptance"]

func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1":
		printerr("FAIL: 请通过 tools/rpg/run_checks.py 运行隔离测试")
		quit(1)
		return
	var suite := "all"
	var arguments := OS.get_cmdline_user_args()
	for index in range(arguments.size()):
		if arguments[index] == "--suite" and index + 1 < arguments.size():
			suite = arguments[index + 1]
	if suite != "all" and not SUITES.has(suite):
		printerr("FAIL: 未知测试组：", suite)
		quit(1)
		return
	var failures: Array[String] = []
	var count := 0
	for name in SUITES:
		if suite != "all" and name != suite and not (suite == "engine" and name == "replay"):
			continue
		var path := "res://tools/rpg/test_%s.gd" % name
		if not FileAccess.file_exists(path):
			if suite != "all":
				failures.append("尚未实现测试组：" + name)
			continue
		var test_script = load(path)
		if test_script == null or not test_script.has_method("run"):
			failures.append("无法加载测试组：" + name)
			continue
		var results: Array = await test_script.run()
		failures.append_array(results)
		count += 1
		print("%s: %s" % ["PASS" if results.is_empty() else "FAIL", name])
	if count == 0:
		failures.append("没有执行任何测试")
	for failure in failures:
		printerr("ASSERT FAIL: ", failure)
	print("RPG 测试组：%d，失败：%d" % [count, failures.size()])
	quit(0 if failures.is_empty() else 1)
