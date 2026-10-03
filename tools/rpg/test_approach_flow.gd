extends RefCounted
const F = preload("res://tools/rpg/fixtures.gd")
const A = preload("res://tools/rpg/approach_fixtures.gd")
const Session = preload("res://scripts/exploration_3d/approach_session.gd")
const Overlay = preload("res://scripts/ui/dialogue_overlay.gd")
class StageStub extends Node:
	var world := A.world()
	var controls := true
	var intent := Vector2.ONE
	func export_world() -> Dictionary: return world.duplicate(true)
	func apply_committed_world(value: Dictionary) -> void: world = value.duplicate(true)
	func set_controls_enabled(value: bool) -> void:
		controls = value
		if not value: intent = Vector2.ZERO
	func get_player_position() -> Vector3: return Vector3(world.position[0], world.position[1], world.position[2])
	func get_interaction_targets() -> Array[Dictionary]:
		return [{"id": "basin", "position": get_player_position(), "radius": 2.0, "priority": 10, "requires": ["approach_entered"]}, {"id": "upper_exit", "position": get_player_position() + Vector3.RIGHT * 10, "radius": 1.0, "priority": 20}]
static func run() -> Array[String]:
	var failures: Array[String] = []
	for file in ["interaction_resolver", "approach_flow"]:
		F.expect(FileAccess.file_exists("res://scripts/exploration_3d/%s.gd" % file), "缺少输入剧情接口：" + file, failures)
	if not failures.is_empty(): return failures
	var Resolver = load("res://scripts/exploration_3d/interaction_resolver.gd")
	var Flow = load("res://scripts/exploration_3d/approach_flow.gd")
	var targets: Array[Dictionary] = [{"id": "b", "position": Vector3.LEFT, "radius": 2.0, "priority": 2}, {"id": "a", "position": Vector3.RIGHT, "radius": 2.0, "priority": 2}, {"id": "locked", "position": Vector3.ZERO, "radius": 1.0, "priority": 0, "requires": ["basin_cleared"]}]
	F.expect(Resolver.choose(Vector3.ZERO, targets, {}) == "a", "同距同优先级按稳定 ID", failures)
	targets[0].priority = 1
	F.expect(Resolver.choose(Vector3.ZERO, targets, {}) == "b" and Resolver.choose(Vector3(10, 0, 0), targets, {}) == "", "优先级与三维距离", failures)
	var store := A.FailingStore.new()
	var session := Session.new(store, "user://rpg_v1/tests/flow.json")
	F.expect(session.start_new(false).ok, "流程会话建立", failures)
	var stage := StageStub.new()
	stage.world = session.campaign.safe_snapshot().world
	var flow = Flow.new()
	flow.bind(session, stage)
	var begins := [0]
	flow.encounter_requested.connect(func(_world): begins[0] += 1)
	flow.start()
	F.expect(flow.mode == &"dialogue" and not stage.controls and stage.intent == Vector2.ZERO, "入场对白锁移动并清意图", failures)
	F.expect(not flow.request_interaction("basin").ok, "对话拒绝调查输入穿透", failures)
	store.fail = true
	F.expect(not flow.finish_dialogue("a1").ok and not stage.world.event_flags.has("approach_entered") and flow.mode == &"dialogue", "对白保存失败保留原状态可重试", failures)
	store.fail = false
	F.expect(flow.finish_dialogue("a1").ok and flow.mode == &"explore", "入场提交后开放探索", failures)
	F.expect(not flow.request_interaction("basin").ok, "切层确认键必须先松开", failures)
	flow.release_confirm()
	F.expect(flow.request_interaction("basin").ok and flow.mode == &"dialogue", "水钵先观察对白", failures)
	F.expect(flow.finish_dialogue("h1").ok, "观察完成单独标记", failures)
	flow.release_confirm()
	F.expect(flow.request_interaction("basin").ok and flow.mode == &"inspect", "E 只打开调查记录", failures)
	store.fail = true
	F.expect(not flow.finish_inspection().ok and not stage.world.event_flags.has("basin_inspected") and begins[0] == 0, "调查写失败不开放战斗", failures)
	store.fail = false
	F.expect(flow.finish_inspection().ok and begins[0] == 0 and flow.mode == &"explore", "读完调查不自动开战", failures)
	flow.release_confirm()
	flow.request_interaction("basin")
	F.expect(flow.mode == &"inspect", "调查记录可重读", failures)
	flow.release_confirm()
	F.expect(flow.request_encounter_confirmation().ok and begins[0] == 0, "应对异常先确认", failures)
	flow.cancel_inspection()
	F.expect(flow.mode == &"explore" and begins[0] == 0, "取消确认可继续探索", failures)
	flow.release_confirm()
	flow.request_interaction("basin")
	flow.release_confirm()
	flow.request_encounter_confirmation()
	F.expect(not flow.confirm_encounter().ok, "新确认层拒绝旧长按 E", failures)
	flow.release_confirm()
	F.expect(flow.confirm_encounter().ok and not flow.confirm_encounter().ok and begins[0] == 1 and flow.mode == &"transition", "只创建一次遭遇请求", failures)
	flow.shutdown()
	F.expect(not flow.finish_dialogue("h1").ok and not stage.controls, "退出后的旧对白回调无效", failures)
	flow.free()
	stage.free()
	session.close()
	await _test_overlay(failures)
	await _test_title_cancel(failures)
	await _test_dialogue_chains(failures)
	var nodes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogues.json")).stages.test_approach.nodes
	F.expect(nodes.h3.choices.size() == 2 and nodes.h4a.next == "h5" and nodes.h4b.next == "h5", "原两支观察汇流未改", failures)
	return failures
static func _test_overlay(failures: Array[String]) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	if not InputMap.has_action("approach_interact"): InputMap.add_action("approach_interact")
	var overlay = Overlay.new()
	tree.root.add_child(overlay)
	F.expect(overlay.advance_action == &"ui_accept" and not overlay.require_release, "旧对白默认输入保持", failures)
	overlay.advance_action = &"approach_interact"
	overlay.require_release = true
	overlay._active = true
	overlay._typing = false
	overlay._advance_armed = false
	var press := InputEventAction.new()
	press.action = &"approach_interact"
	press.pressed = true
	overlay._unhandled_input(press)
	F.expect(not overlay._advance, "对白锁止继承的按下", failures)
	var release := InputEventAction.new()
	release.action = &"approach_interact"
	release.pressed = false
	overlay._unhandled_input(release)
	overlay._unhandled_input(press)
	F.expect(overlay._advance, "对白松开后下一次按下推进", failures)
	overlay.abort()
	overlay.queue_free()
	await tree.process_frame

static func _test_title_cancel(failures: Array[String]) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var session := Session.new(null, "user://rpg_v1/tests/flow_title_cancel.json")
	F.expect(session.start_new(false).ok, "真实场景标题取消夹具", failures)
	F.expect((await session.prepare_assets()).ok, "真实对白先加载新版立绘", failures)
	var stage = load("res://scenes/exploration_3d/approach.tscn").instantiate()
	tree.root.add_child(stage)
	for index in range(5):
		await tree.physics_frame
		await tree.process_frame
	F.expect(stage.flow.mode == &"dialogue", "真实入场对白开始", failures)
	stage._ask_title()
	stage._ask_title() # 顶部 HUD 连点不能覆盖原对白恢复状态。
	var escape := InputEventAction.new()
	escape.action = &"approach_pause"
	escape.pressed = true
	stage._unhandled_input(escape)
	F.expect(stage.flow.mode == &"dialogue" and not stage.controls_enabled and stage._dialogue.is_processing_unhandled_input(), "对白中标题确认按Esc恢复对白，不能开放移动", failures)
	stage.queue_free()
	await tree.process_frame
	await tree.create_timer(0.2).timeout
	session.close()

static func _test_dialogue_chains(failures: Array[String]) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var nodes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogues.json")).stages.test_approach.nodes
	for path in [["a1", 0, "a5"], ["h1", 0, "h4a"], ["h1", 1, "h4b"]]:
		var overlay = Overlay.new()
		tree.root.add_child(overlay)
		var visited: Array = []
		overlay.advanced.connect(func(id): visited.append(id))
		var completed := [false]
		_wait_dialogue(overlay, nodes, path[0], completed)
		for index in range(150):
			if not overlay._active: break
			if overlay._typing: overlay._typing = false
			elif overlay._waiting_choice: overlay._pick_choice(nodes[overlay._playing_id].choices[path[1]].next)
			else: overlay._advance = true
			await tree.process_frame
		F.expect(completed[0] and visited.has(path[2]) and (visited.back() == "a5" if path[0] == "a1" else visited.back() == "h5"), "真实Overlay读完原节点链：" + str(path), failures)
		overlay.queue_free()
		await tree.process_frame
	var aborted = Overlay.new()
	tree.root.add_child(aborted)
	var cancelled := [false]
	_wait_dialogue(aborted, nodes, "a1", cancelled)
	aborted.abort()
	F.expect(cancelled[0], "abort同步释放旧await调用而不遗留逐字计时器", failures)
	aborted.queue_free()
	await tree.process_frame
static func _wait_dialogue(overlay: Node, nodes: Dictionary, start: String, completed: Array) -> void:
	await overlay.play(nodes, start)
	completed[0] = true
