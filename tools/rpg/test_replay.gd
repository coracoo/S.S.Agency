# 重放必须逐事件一致，预览、恢复与JSON编码不影响单一RNG。
extends RefCounted
const F = preload("res://tools/rpg/fixtures.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Helpers = preload("res://tools/rpg/test_engine.gd")

static func run() -> Array[String]:
	F.assertion_count = 0
	var failures: Array[String] = []
	for script in ["battle_engine", "replay"]:
		F.expect(FileAccess.file_exists("res://scripts/rpg/%s.gd" % script), "未实现重放：" + script, failures)
	if not failures.is_empty():
		return failures
	var Engine = load("res://scripts/rpg/battle_engine.gd")
	var Replay = load("res://scripts/rpg/replay.gd")
	var catalog = Catalog.new()
	catalog.load_all()
	var a = Helpers._new_engine(Engine, [F.actor("swordsman", "sword"), F.enemy("hound", "enemy")], 99)
	var b = Engine.new()
	var initial: Dictionary = a.snapshot()
	b.restore(initial)
	var commands: Array[Dictionary] = []
	var events: Array[Dictionary] = []
	for index in range(8):
		var next_events: Array = a.advance()
		F.expect(next_events == b.advance(), "同seed轮序和槽事件相同", failures)
		events.append_array(next_events)
		if not a.snapshot().outcome.is_empty(): break
		var state: Dictionary = a.snapshot()
		var target := "enemy" if state.active_actor_id == "sword" else "sword"
		var command: Dictionary = Helpers._command(a, "attack_physical", "", [target])
		for iteration in range(index + 1): b.preview(command)
		var result: Dictionary = a.submit(command)
		var other: Dictionary = b.submit(command)
		F.expect(result == other and a.snapshot() == b.snapshot(), "插入任意次预览不改命令事件或RNG", failures)
		commands.append(command)
		events.append_array(result.events)
	var recording: Dictionary = Replay.record(initial, commands, events)
	F.expect(Replay.verify(recording, catalog).matches, "规范重放逐事件匹配", failures)
	var json_verification: Dictionary = Replay.verify(JSON.parse_string(JSON.stringify(recording, "", true, true)), catalog)
	F.expect(json_verification.matches, "JSON记录往返仍重放一致", failures)
	var microscopic := 0.000000000000001
	F.expect(not Replay._same_json_value(_float_steps(microscopic, 2), microscopic, true), "非真实运输的两ULP人为变化拒绝", failures)
	F.expect(not Replay._same_json_value(microscopic, _float_steps(microscopic, 3), true), "非真实运输的三ULP人为变化拒绝", failures)
	# 实战seed572907568中的暴击采样；从bit构造以免字面量解析先丢精度。
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_s64(0, 4578730391304667136)
	var original_roll := bytes.decode_double(0)
	var transported_roll: float = JSON.parse_string(JSON.stringify(original_roll, "", true, true))
	F.expect(PackedFloat64Array([transported_roll]).to_byte_array().decode_s64(0) == 4578730391304667132, "Godot4.6.3单次full_precision运输4ULP最小复现", failures)
	F.expect(Replay._same_json_value(transported_roll, original_roll, true), "只接受严格匹配真实单次运输的浮点", failures)
	F.expect(not Replay._same_json_value(transported_roll, original_roll, false), "内存记录不允许任何运输偏差", failures)
	for delta in [-1, 1]: F.expect(not Replay._same_json_value(_float_steps(transported_roll, delta), original_roll, true), "运输结果邻近一ULP不得混入：%d" % delta, failures)
	for delta in [-3, 3, 4]: F.expect(not Replay._same_json_value(_float_steps(original_roll, delta), original_roll, true), "其他三/四ULP伪改拒绝：%d" % delta, failures)
	var exact_changed := recording.duplicate(true)
	exact_changed.events[0].payload.effective_spd = _float_steps(exact_changed.events[0].payload.effective_spd, 1)
	F.expect(not Replay.verify(exact_changed, catalog).matches, "未经过JSON的内存记录严格逐位一致", failures)
	var modified := recording.duplicate(true)
	modified.commands[0].kind = "defend"
	modified.commands[0].target_ids = []
	var verification: Dictionary = Replay.verify(modified, catalog)
	F.expect(not verification.matches and verification.first_difference.get("event_index", -1) >= 0, "改一条输入能指出第一不同事件", failures)
	modified = recording.duplicate(true)
	modified.commands[0].kind = "defend"
	modified.commands[0].target_ids = []
	modified.commands[1].expected_revision = 999
	var first_command_index := 0
	for i in range(recording.events.size()):
		if recording.events[i].type == "command_accepted":
			first_command_index = i
			break
	F.expect(Replay.verify(modified, catalog).first_difference.event_index == first_command_index, "后续命令失败不得遮盖此前第一个不同事件", failures)
	modified = recording.duplicate(true)
	modified.events[0].payload.effective_spd += 0.000000001
	F.expect(not Replay.verify(modified, catalog).matches, "逐事件校验不能掩盖小量浮点篡改", failures)
	modified = recording.duplicate(true)
	modified.seed += 1
	F.expect(not Replay.verify(modified, catalog).matches, "记录seed与初始快照seed必须一致", failures)
	modified = recording.duplicate(true)
	modified.rules_version = "future"
	F.expect(not Replay.verify(modified, catalog).matches, "拒绝未来规则版本重放", failures)
	var boss = Helpers._selection(Engine, F.enemy("gatekeeper", "boss"), [F.actor("guard", "a"), F.actor("healer", "b")])
	var rng_before: String = boss.snapshot().rng_state
	var result: Dictionary = boss.submit(Helpers._command(boss, "skill", "boss_quake"))
	F.expect(result.accepted and boss.snapshot().rng_state == rng_before, "Boss禁暴击不抽随机", failures)
	var sword = Helpers._selection(Engine, F.actor("swordsman", "sword"), [F.enemy("hound", "a"), F.enemy("hound", "b")])
	var rng := RandomNumberGenerator.new()
	rng.state = sword.snapshot().rng_state.to_int()
	var first := rng.randf()
	var second := rng.randf()
	result = sword.submit(Helpers._command(sword, "skill", "sweep"))
	var draws: Array = []
	for event in result.events:
		if event.type == "damage": draws.append(event.payload.critical_roll)
	F.expect(draws == [first, second] and sword.snapshot().rng_state == str(rng.state), "群攻各目标独立一次5%抽样按ID排序", failures)
	# 测试策略只返回明确的防御命令，用于验证插件接点；生产没有默认AI。
	var scripted = Helpers._new_engine(Engine, [F.actor("guard", "guard"), F.enemy("hound", "enemy")], 17)
	var policy := ExplicitDefendPolicy.new()
	scripted.set_policy(policy)
	var scripted_initial: Dictionary = scripted.snapshot()
	var scripted_events: Array[Dictionary] = []
	scripted_events.append_array(scripted.advance())
	F.expect(scripted.snapshot().active_actor_id == "guard", "注册策略经统一submit处理敌槽后停玩家", failures)
	var scripted_result: Dictionary = scripted.submit(Helpers._command(scripted, "defend"))
	scripted_events.append_array(scripted_result.events)
	scripted_events.append_array(scripted.advance())
	var scripted_commands: Array[Dictionary] = []
	scripted_commands.assign(scripted.snapshot().command_log)
	var scripted_record: Dictionary = Replay.record(scripted_initial, scripted_commands, scripted_events)
	F.expect(Replay.verify(scripted_record, catalog, ExplicitDefendPolicy.new()).matches, "附加同策略后逐条重演含自动命令的日志不双执行", failures)
	F.expect(preload("res://scripts/rpg/battle_state.gd").validate(scripted.snapshot()).is_empty(), "策略对象不进入JSON状态", failures)
	print("RPG replay 断言：", F.assertion_count)
	return failures

static func _float_steps(value: float, steps: int) -> float:
	var bytes := PackedFloat64Array([value]).to_byte_array()
	bytes.encode_s64(0, bytes.decode_s64(0) + steps)
	return bytes.decode_double(0)

class ExplicitDefendPolicy:
	extends RefCounted
	func choose_command(state: Dictionary, _catalog: RefCounted) -> Dictionary:
		return {"command_id": "policy_%d" % state.revision, "expected_revision": state.revision, "actor_id": state.active_actor_id, "kind": "defend", "ability_id": "", "target_ids": []}
	func before_round(state: Dictionary, _catalog: RefCounted) -> Array[Dictionary]:
		return [{"sequence": 0, "type": "policy_round", "actor_id": "", "target_id": "", "payload": {"round": state.round}}]
	func after_command(_state: Dictionary, command: Dictionary, _catalog: RefCounted) -> Array[Dictionary]:
		return [{"sequence": 0, "type": "policy_command", "actor_id": command.actor_id, "target_id": "", "payload": {}}]
