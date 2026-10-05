# 无效道具必须在只读预览阶段拒绝，提交不能消耗库存或行动。
extends SceneTree

const F = preload("res://tools/rpg/fixtures.gd")
const Battle = preload("res://scripts/rpg/battle_engine.gd")
const Status = preload("res://scripts/rpg/status_rules.gd")

var failures: Array[String] = []

func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1":
		printerr("FAIL: 请通过隔离 Python 入口运行道具效果测试")
		quit(1)
		return
	F.assertion_count = 0
	_test_ineffective_items()
	_test_effective_recovery()
	_test_effective_cleanse()
	_test_revival()
	print("RPG_ITEM_EFFECTIVENESS_ASSERTIONS: ", F.assertion_count)
	for failure in failures:
		printerr("FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)

func _engine(target: Dictionary) -> RefCounted:
	var source := F.actor("healer", "source")
	source.stats.spd = 999
	var engine := Battle.new()
	var result := engine.start({"actors": {"source": source, "target": target, "enemy": F.enemy("hound", "enemy")}, "inventory": F.state(source).inventory}, 73)
	F.expect(result.started, "测试战斗合法启动：" + str(result.reasons), failures)
	engine.advance(false)
	F.expect(engine.snapshot().active_actor_id == "source", "道具测试保留行动者的选择机会", failures)
	return engine

func _command(engine: RefCounted, item_id: String, target_id: String = "target") -> Dictionary:
	var state: Dictionary = engine.snapshot()
	return {"command_id": "item_%s_%d" % [item_id, state.revision], "expected_revision": state.revision, "actor_id": state.active_actor_id, "kind": "item", "ability_id": item_id, "target_ids": [target_id]}

func _expect_rejected(engine: RefCounted, item_id: String, reason: String, target_id: String = "target") -> void:
	var before: Dictionary = engine.snapshot()
	var command := _command(engine, item_id, target_id)
	var preview: Dictionary = engine.preview(command)
	F.expect(not preview.legal, "预览拒绝无效道具：" + item_id, failures)
	F.expect(preview.reasons.has(reason), "无效道具给出明确原因：" + reason, failures)
	F.expect(engine.snapshot() == before, "无效道具预览完全只读：" + item_id, failures)
	var result: Dictionary = engine.submit(command)
	F.expect(not result.accepted, "提交拒绝无效道具：" + item_id, failures)
	F.expect(result.reasons == preview.reasons and result.events.is_empty(), "拒绝提交保留预览原因且不产生事件：" + item_id, failures)
	F.expect(engine.snapshot() == before, "拒绝提交保持完整状态、库存、行动、RNG与日志：" + item_id, failures)
	F.expect(engine.preview(_command(engine, "revival_potion", "source")).legal == false, "拒绝后仍校验倒地目标规则", failures)

func _test_ineffective_items() -> void:
	for item_id in ["healing_potion", "mana_potion", "cleansing_powder"]:
		var reason: String = {"healing_potion": "目标HP已满", "mana_potion": "目标MP已满", "cleansing_powder": "目标没有可净化的负面状态"}[item_id]
		var target := F.actor("guard", "target")
		# 另一种资源有缺口，也不能让无效恢复获得行动资格。
		if item_id == "healing_potion": target.mp = 0
		if item_id == "mana_potion": target.hp = 1
		var engine := _engine(target)
		_expect_rejected(engine, item_id, reason)
		_expect_rejected(_engine(target), item_id, reason, "source")
	var buffed := F.actor("guard", "target")
	Status.apply(buffed, F.status("battle_spirit", 0.4, 3, "target"))
	Status.apply(buffed, F.status("awake", 1.0, 3, "target"))
	_expect_rejected(_engine(buffed), "cleansing_powder", "目标没有可净化的负面状态")

func _expect_accepted(engine: RefCounted, item_id: String) -> Dictionary:
	var before: Dictionary = engine.snapshot()
	var command := _command(engine, item_id)
	F.expect(engine.preview(command).legal, "有效道具预览合法：" + item_id, failures)
	F.expect(engine.snapshot() == before, "有效道具预览完全只读：" + item_id, failures)
	var result: Dictionary = engine.submit(command)
	F.expect(result.accepted, "有效道具提交成功：" + item_id, failures)
	var after: Dictionary = engine.snapshot()
	F.expect(after.inventory[item_id] == before.inventory[item_id] - 1, "有效道具恰好扣一库存：" + item_id, failures)
	F.expect(after.revision == before.revision + 1 and after.queue_index == before.queue_index + 1 and after.phase == "action_end", "有效道具恰好结束一次行动：" + item_id, failures)
	F.expect(after.rng_state == before.rng_state, "有效道具不抽取随机数：" + item_id, failures)
	F.expect(not engine.submit(command).accepted and engine.snapshot() == after, "有效道具重复提交不再消耗：" + item_id, failures)
	return after

func _test_effective_recovery() -> void:
	for resource in ["hp", "mp"]:
		var item_id := "healing_potion" if resource == "hp" else "mana_potion"
		var amount := 80 if resource == "hp" else 20
		for missing in [1, amount + 1]:
			var target := F.actor("guard", "target")
			target[resource] -= missing
			var expected: int = mini(target.stats[resource], target[resource] + amount)
			var after := _expect_accepted(_engine(target), item_id)
			F.expect(after.actors.target[resource] == expected, "道具按实际缺口恢复且不溢出：%s／%d" % [resource, missing], failures)

func _test_effective_cleanse() -> void:
	var target := F.actor("guard", "target")
	Status.apply(target, F.status("weaken", 0.2, 3, "enemy"))
	Status.apply(target, F.status("battle_spirit", 0.4, 3, "target"))
	var after := _expect_accepted(_engine(target), "cleansing_powder")
	F.expect(F.find_status(after.actors.target, "weaken").is_empty(), "净化粉实际移除可净化负面", failures)
	F.expect(not F.find_status(after.actors.target, "battle_spirit").is_empty(), "净化粉保留正面状态", failures)

func _test_revival() -> void:
	var target := F.actor("guard", "target")
	target.hp = 0
	target.mp = 7
	target.cooldown_until["iron_wall"] = 5
	var after := _expect_accepted(_engine(target), "revival_potion")
	F.expect(after.actors.target.hp == roundi(float(target.stats.hp) * 0.3), "复苏药恢复30%生命", failures)
	F.expect(after.actors.target.mp == 7 and after.actors.target.cooldown_until.iron_wall == 5, "复苏药保留MP与冷却", failures)
	F.expect(after.actors.target.revived_round == after.round, "复苏药保留本轮禁止再行动规则", failures)
	_expect_rejected(_engine(F.actor("guard", "target")), "revival_potion", "请选择一个合法目标")
