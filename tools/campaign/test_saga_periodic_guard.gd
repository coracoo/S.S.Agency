# 锁片与出口目标必须同时阻挡直伤和既存持续伤害；状态时间不能因此冻结。
extends "res://tools/campaign/test_saga_battles.gd"
const ReplayCheck = preload("res://scripts/rpg/replay.gd")
func _run() -> void:
	catalog = Catalog.new()
	check(catalog.load_all().is_empty(), "周期门禁回归加载目录")
	rules = load("res://scripts/rpg/saga_boss_rules.gd")
	for test_case in [["saga_c6_11", "saga_nochange_warden", false], ["saga_c7_10", "saga_final_recoil", false], ["saga_c7_10", "saga_relay_recoil", false], ["saga_c6_11", "saga_nochange_warden", true]]:
		_test_guarded_burn(test_case[0], test_case[1], test_case[2])
	print("SAGA_PERIODIC_GUARD_ASSERTIONS:", assertions, " FAILURES:", failures.size())
	quit(0 if failures.is_empty() else 1)
func _test_guarded_burn(encounter_id: String, enemy_class: String, reopen: bool) -> void:
	var setup: Dictionary = _setup(encounter_id)
	if reopen:
		for actor in setup.actors.values():
			if actor.class_id in ["saga_anchor_left", "saga_anchor_right"]: actor.hp = 0
	var engine := BattleEngine.new(catalog); engine.set_policy(Policy.new())
	var start: Dictionary = engine.start(setup, 53)
	check(start.started, "真实周期战斗可启动")
	var initial: Dictionary = engine.snapshot()
	var target := _enemy_id(initial, enemy_class)
	var applied := false
	for opportunity in range(12):
		engine.advance()
		var state: Dictionary = engine.snapshot()
		if not state.outcome.is_empty(): break
		var actor_id: String = state.active_actor_id
		var command: Dictionary = _command(state, actor_id, "defend", "", [actor_id])
		if actor_id == "p_mage" and not applied:
			command = _command(state, actor_id, "skill", "burn_brand", [target])
			var before: Dictionary = engine.snapshot()
			var preview: Dictionary = engine.preview(command)
			check(preview.legal, "灼印确为合法固定技能")
			if not reopen: check(preview.effects.any(func(e): return e.type == "saga_objective_blocked"), "预览明示锁片或出口保护")
			check(_equivalent(before, engine.snapshot()), "受保护灼印预览不修改HP、状态或历史")
			applied = true
		var result: Dictionary = engine.submit(command)
		check(result.accepted, "周期回归使用真实合法行动：" + str(result.reasons))
	var final: Dictionary = engine.snapshot()
	var ticks: Array = []
	var repaired := false
	var feedback := 0
	for event in final.event_log:
		if event.type == "saga_anchor_repaired": repaired = true
		if event.type == "periodic_damage" and event.target_id == target: ticks.append(int(event.payload.damage))
		if event.type == "saga_objective_blocked" and event.target_id == target and event.payload.get("status_id") == "burn": feedback += 1
	check(ticks.size() == 3, "三次灼烧槽照常流逝：" + enemy_class + str(ticks))
	if reopen:
		check(repaired, "巡守按真实号令接回锁片")
		check(ticks.size() == 3 and ticks[0] > 0 and ticks[1] > 0 and ticks[2] == 0, "锁片接回后已存在的灼烧也受保护：" + str(ticks))
		check(feedback == 1, "既存灼烧被挡时发出明确反馈")
	else:
		check(ticks.all(func(amount): return amount == 0), "灼烧不能绕过剧情目标门禁：" + enemy_class + str(ticks))
		check(final.actors[target].hp == initial.actors[target].hp, "受保护Boss不能被持续伤害磨死")
		check(feedback == 3, "每次受保护周期槽都有反馈")
	check(not final.actors[target].statuses.any(func(status): return status.id == "burn"), "保护不暂停灼烧时钟或留下永久状态")
	var commands: Array[Dictionary] = []; commands.assign(final.command_log)
	var events: Array[Dictionary] = []; events.assign(final.event_log.slice(initial.event_log.size()))
	var recording: Dictionary = ReplayCheck.record(initial, commands, events)
	for transported in [false, true]:
		var record: Dictionary = JSON.parse_string(JSON.stringify(recording, "", true, true)) if transported else recording
		var verification: Dictionary = ReplayCheck.verify(record, catalog, Policy.new())
		check(verification.matches, "受保护周期时钟及回补逐事件重放一致：" + str(verification.first_difference))
