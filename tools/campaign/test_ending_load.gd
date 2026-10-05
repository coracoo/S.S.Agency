# 每次实际加载结尾脚本并进入场景树，避免只检查资源存在漏掉导出解析错误。
extends SceneTree
var failures: Array[String] = []
var assertions := 0
class DisplayCampaign extends RefCounted:
	var state: Dictionary = {}
	func safe_snapshot() -> Dictionary: return state.duplicate(true)
class DisplaySession extends RefCounted:
	var campaign: RefCounted
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1":
		printerr("FAIL: ending checks require verified user isolation")
		quit(2)
		return
	call_deferred("_run")
func expect(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: ", description)
func _run() -> void:
	var packed: PackedScene = load("res://scenes/campaign/ending.tscn")
	expect(packed != null, "结尾PackedScene实际可加载")
	if packed == null:
		quit(1)
		return
	var first: Node = packed.instantiate()
	var script: Script = first.get_script()
	expect(script != null and script.can_instantiate(), "结尾生产脚本有效可实例化")
	first.free()
	if script == null or not script.can_instantiate():
		quit(1)
		return
	var Session = load("res://scripts/campaign/chapter_session.gd")
	var previous: RefCounted = Session.current
	for test_case in [{"state": {}, "headline": "正式完成记录尚未提交", "body": "请从标题继续正式主线，完成结局演出与存档。"}, {"state": {"story_phase": "complete", "chapter_complete": true, "resolution": "sendoff"}, "headline": "第一章 · 五夜 · 结案", "body": "案件状态：已结案。"}, {"state": {"story_phase": "complete", "chapter_complete": true, "resolution": "seal_monitoring"}, "headline": "第一章 · 五夜 · 续监", "body": "案件状态：续监。"}]:
		var model := DisplayCampaign.new()
		model.state = test_case.state
		var session := DisplaySession.new()
		session.campaign = model
		Session.current = session
		var ending: Node = packed.instantiate()
		root.add_child(ending)
		await process_frame
		var text := _label_text(ending)
		expect(text.contains(str(test_case.headline)), "结尾印章：" + str(test_case.headline))
		expect(text.contains(str(test_case.body)), "结尾状态与正式分支一致")
		ending.free()
	Session.current = previous
	print("CAMPAIGN_ENDING_LOAD_ASSERTIONS:", assertions)
	quit(0 if failures.is_empty() else 1)
func _label_text(node: Node) -> String:
	var result: String = node.text + "\n" if node is Label else ""
	for child in node.get_children(): result += _label_text(child)
	return result
