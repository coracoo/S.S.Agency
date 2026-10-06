# 反射预览必须由同一伤害模型给出穿盾扣血和致死可能，不能靠UI另算。
extends "res://tools/campaign/test_saga_battles.gd"
const ReplayCheck = preload("res://scripts/rpg/replay.gd")
func _run() -> void:
	catalog = Catalog.new(); check(catalog.load_all().is_empty(), "反射回归目录加载")
	for shield_amount in [5, 100]: _test_reflection(shield_amount)
	print("SAGA_REFLECTION_PREVIEW_ASSERTIONS:", assertions, " FAILURES:", failures.size())
	quit(0 if failures.is_empty() else 1)
func _test_reflection(shield_amount: int) -> void:
	var setup: Dictionary = _setup("saga_c4_09")
	setup.actors.p_guard.stats.spd = 100
	setup.actors.p_guard.hp = 12
	setup.actors.p_guard.shield = Fixture.shield(shield_amount, 3, "p_guard")
	var engine := BattleEngine.new(catalog); engine.set_policy(Policy.new())
	check(engine.start(setup, 17).started, "带护盾反射战斗真实启动")
	var initial: Dictionary = engine.snapshot()
	engine.advance(false)
	var before: Dictionary = engine.snapshot()
	var target := _enemy_id(before, "saga_joined_mirror")
	var command := _command(before, "p_guard", "attack_physical", "", [target])
	var preview: Dictionary = engine.preview(command)
	check(preview.legal, "反射风险不擅自剥夺合法行动")
	var reflection: Dictionary = {}
	for event in preview.effects:
		if event.type == "saga_reflected": reflection = event.payload
	var complete := true
	for field in ["normal", "critical_damage", "normal_hp_loss", "critical_hp_loss", "defeat_normal", "defeat_critical"]: complete = complete and reflection.has(field)
	check(complete, "反射预览具备普通/暴击返伤、穿盾HP损失和KO风险")
	if not complete: return
	check(_equivalent(before, engine.snapshot()), "两次反射模拟不修改真实护盾或HP")
	check(reflection.normal > 0 and reflection.critical_damage > reflection.normal, "暴击反射区别于普通反射")
	if shield_amount == 5:
		check(reflection.normal_hp_loss == 11 and reflection.critical_hp_loss == 12, "普通反射破5盾扣11HP；暴击可耗尽12HP")
		check(not reflection.defeat_normal and reflection.defeat_critical, "低血玩家能在确认前知道暴击反射可能KO")
	else:
		check(reflection.normal_hp_loss == 0 and reflection.critical_hp_loss == 0, "足量当前护盾同时挡住两种反射")
		check(not reflection.defeat_normal and not reflection.defeat_critical, "不会忽略护盾而误报KO")
	var result: Dictionary = engine.submit(command)
	check(result.accepted, "风险确认后真实行动正常执行")
	var actual: Dictionary = {}
	var crit := false
	for event in result.events:
		if event.type == "damage": crit = event.payload.critical
		if event.type == "saga_reflected": actual = event.payload
	check(actual.get("absorption", {}).get("hp_loss") == reflection.critical_hp_loss if crit else actual.get("absorption", {}).get("hp_loss") == reflection.normal_hp_loss, "实际只吸收一次反射并等于对应预览")
	var final: Dictionary = engine.snapshot()
	check(final.actors.p_guard.hp == int(actual.absorption.hp_after), "预览模拟未额外扣血")
	var commands: Array[Dictionary] = []; commands.assign(final.command_log)
	var events: Array[Dictionary] = []; events.assign(final.event_log.slice(initial.event_log.size()))
	var recording: Dictionary = ReplayCheck.record(initial, commands, events)
	for transported in [false, true]:
		var record: Dictionary = JSON.parse_string(JSON.stringify(recording, "", true, true)) if transported else recording
		var verification: Dictionary = ReplayCheck.verify(record, catalog, Policy.new())
		check(verification.matches, "反射预测字段不破坏逐事件重放：" + str(verification.first_difference))
