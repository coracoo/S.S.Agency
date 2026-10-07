# 七形态专精沿既有四卡执行；断言真实费用、状态、预览与重放，不用展示字符串代替机制。
extends RefCounted
const F = preload("res://tools/rpg/fixtures.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const BattleEngine = preload("res://scripts/rpg/battle_engine.gd")
const Forms = preload("res://scripts/rpg/dual_form.gd")
const State = preload("res://scripts/rpg/battle_state.gd")
const Status = preload("res://scripts/rpg/status_rules.gd")
const Replay = preload("res://scripts/rpg/replay.gd")
const Presenter = preload("res://scripts/rpg/ui/battle_presenter.gd")
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
const H = preload("res://tools/rpg/test_engine.gd")
const CASES := [
	["rinne", "swordsman", "heavy_slash", 9, 0, "armor_break", 1.8, "破隙"],
	["mint", "ranger", "ambush", 8, 2, "mark", 0.0, "追踪"],
	["guard", "guard", "shield_bash", 8, 2, "weaken", 0.0, "震慑"],
	["homura", "swordsman", "armor_break", 9, 2, "burn", 0.0, "引火"],
	["homura", "mage", "firebolt", 11, 0, "burn", 1.7, "续焰"],
	["healer", "healer", "heal", 14, 1, "shield", 0.0, "护生"],
	["controller", "controller", "magic_break", 9, 1, "weaken", 1.0, "解咒"]
]

static func run() -> Array[String]:
	F.assertion_count = 0
	var failures: Array[String] = []
	var catalog := Catalog.new()
	F.expect(catalog.load_all().is_empty(), "专精目录合法加载", failures)
	F.expect(catalog.get_ids("skills").size() == 24, "保留24基础技能", failures)
	F.expect(catalog.get_ids("refinements").size() == 7, "七形态各有一项个人专精", failures)
	for row in CASES:
		_test_definition(catalog, row, failures)
		_test_execution(catalog, row, failures)
	_test_branches(catalog, failures)
	_test_form_isolation(catalog, failures)
	_test_cross_form_combo(catalog, failures)
	_test_existing_effect_priority(catalog, failures)
	_test_validation(failures)
	print("RPG 专精断言：", F.assertion_count)
	return failures

static func _actor(catalog: RefCounted, row: Array) -> Dictionary:
	var actor := F.actor("mage" if row[0] == "homura" else row[1], "p_mage" if row[0] == "homura" else "p_" + row[1])
	actor["identity_id"] = row[0]
	if row[0] == "homura":
		Forms.initialize(actor, catalog)
		actor.unlocked_forms = ["sword", "mage"]
		Forms.apply(actor, "sword" if row[1] == "swordsman" else "mage", catalog)
	return actor

static func _test_definition(catalog: RefCounted, row: Array, failures: Array[String]) -> void:
	var actor := _actor(catalog, row)
	var before := actor.duplicate(true)
	var skill: Dictionary = catalog.skill_for(actor, row[2])
	F.expect([skill.mp_cost, skill.cooldown] == [row[3], row[4]], row[0] + row[1] + " 专精费用/CD", failures)
	F.expect(skill.name.contains(row[7]) and skill.get("refinement", {}).get("unlock_level") == 3, row[0] + " 专精名称及L3开放", failures)
	F.expect(actor == before and actor.skill_ids.size() == 4, "查询专精不改变角色或四卡", failures)
	actor.level = 2
	F.expect(catalog.skill_for(actor, row[2]) == catalog.get_definition("skills", row[2]), row[0] + " L2维持基础技能", failures)
	var anonymous := F.actor(row[1], "anonymous")
	F.expect(catalog.skill_for(anonymous, row[2]) == catalog.get_definition("skills", row[2]), row[0] + " 旧无身份角色不被重写", failures)
	actor = before
	var model: Dictionary = Presenter.present(F.state(actor), catalog, actor.actor_id)
	var slot: Dictionary = {}
	for current in model.commands.skills:
		if current.id == row[2]: slot = current
	F.expect(slot.get("refinement", {}).get("name", "") == row[7], "四卡投影带个人专精说明", failures)
	var detail := Presenter.ability_summary(slot, {}, catalog)
	Kit.init()
	var card_line := str(slot.get("target_short", "")) + " · " + Presenter.card_summary(slot, {}, catalog)
	F.expect(Kit.font.get_string_size(card_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x <= 268, "专精卡片二行在真实字体最小字号不溢出：%s %.1f %s" % [row[7], Kit.font.get_string_size(card_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x, card_line], failures)
	F.expect(detail.contains(row[7]), "技能tooltip说明专精", failures)
	F.expect(Presenter.branch_preview(actor, "", catalog).contains(row[7]), "整备职业指引展示当前专精", failures)
	if float(row[6]) > 0:
		F.expect(detail.contains(catalog.get_definition("statuses", row[5]).name), "条件摘要显示实际状态，不能全写标记", failures)

static func _test_execution(catalog: RefCounted, row: Array, failures: Array[String]) -> void:
	var actor := _actor(catalog, row)
	var enemy := F.enemy("hound", "enemy")
	enemy.stats.hp = 3000
	enemy.hp = 3000
	if float(row[6]) > 0:
		Status.apply(enemy, F.status(row[5], 0.25 if row[5] != "burn" else 5.0, 3, actor.actor_id))
	var ally := F.actor("guard", "ally")
	ally.hp = 50
	var engine = H._selection(BattleEngine, actor, [enemy, ally])
	var target_id := "ally" if row[0] == "healer" else "enemy"
	var command := H._command(engine, "skill", row[2], [target_id])
	var before: Dictionary = engine.snapshot()
	var preview: Dictionary = engine.preview(command)
	F.expect(preview.legal and preview.mp_cost == row[3] and preview.cooldown == row[4], "真实预览采用专精费用/CD：" + row[7], failures)
	for repeat in 3: engine.preview(command)
	F.expect(engine.snapshot() == before, "重复预览不修改资源/状态/RNG/日志：" + row[7], failures)
	if float(row[6]) > 0:
		var skill: Dictionary = catalog.skill_for(before.actors[actor.actor_id], row[2])
		F.expect(is_equal_approx(float(skill.effects[0].get("conditional_coefficient", 0)), row[6]), "条件伤害系数：" + row[7], failures)
		var without: Dictionary = before.duplicate(true)
		without.actors.enemy.statuses = []
		engine.restore(without)
		F.expect(preview.damage_ranges[0].normal > engine.preview(command).damage_ranges[0].normal, "协同状态切实提高伤害：" + row[7], failures)
		engine.restore(before)
	var low: Dictionary = before.duplicate(true)
	low.actors[actor.actor_id].mp = int(row[3]) - 1
	engine.restore(low)
	F.expect(not engine.submit(command).accepted and engine.snapshot() == low, "专精MP不足严格零副作用：" + row[7], failures)
	engine.restore(before)
	var invalid := command.duplicate(true)
	invalid.target_ids = ["missing"]
	F.expect(not engine.submit(invalid).accepted and engine.snapshot() == before, "非法目标零副作用：" + row[7], failures)
	var result: Dictionary = engine.submit(command)
	F.expect(result.accepted, "专精实战提交成功：" + row[7], failures)
	if not result.accepted: return
	var after: Dictionary = engine.snapshot()
	F.expect(after.actors[actor.actor_id].mp == before.actors[actor.actor_id].mp - int(row[3]), "只扣实际专精MP一次：" + row[7], failures)
	F.expect(after.actors[actor.actor_id].cooldown_until[row[2]] == before.actors[actor.actor_id].slot_count + int(row[4]) + 1, "CD按本人行动槽：" + row[7], failures)
	F.expect(not engine.submit(command).accepted and engine.snapshot() == after, "重复确认无二次收益/消耗：" + row[7], failures)
	F.expect(State.validate(after).is_empty(), "不增存档字段仍是合法快照：" + row[7], failures)
	for event in preview.effects:
		if event.type == "damage":
			var actual := H._event(result.events, "damage")
			F.expect(actual.payload.damage in [event.payload.normal, event.payload.critical_damage], "实战伤害属于预览精确区间：" + row[7], failures)
		elif event.type in ["status_applied", "shield_applied", "healed"]:
			F.expect(result.events.any(func(value): return value.type == event.type and value.target_id == event.target_id and value.payload == event.payload), "新增效果预览/实战精确相同：" + row[7] + event.type, failures)
	match row[7]:
		"追踪": F.expect(F.find_status(after.actors.enemy, "mark").get("remaining") == 2, "奇袭实加2槽标记", failures)
		"震慑": F.expect(F.find_status(after.actors.enemy, "weaken").get("remaining") == 1 and is_equal_approx(F.find_status(after.actors.enemy, "weaken").get("magnitude", 0.0), 0.2), "盾击实加1槽20%虚弱", failures)
		"引火": F.expect(F.find_status(after.actors.enemy, "burn").get("remaining") == 2 and is_equal_approx(F.find_status(after.actors.enemy, "burn").get("snapshot", {}).get("source_matk", 0.0), float(actor.stats.matk)), "剑形灼烧真实快照MATK并维持2槽", failures)
		"护生": F.expect(after.actors.ally.shield.get("amount") == 19 and after.actors.ally.shield.get("remaining") == 1, "治疗实加19盾/1槽且回复86HP", failures)
	var commands: Array[Dictionary] = [command]
	var events: Array[Dictionary] = []
	events.assign(result.events)
	var recording := Replay.record(before, commands, events)
	F.expect(Replay.verify(recording, catalog).matches, "专精重放逐事件相同：" + row[7], failures)
	F.expect(Replay.verify(JSON.parse_string(JSON.stringify(recording, "", true, true)), catalog).matches, "专精JSON重放逐事件相同：" + row[7], failures)
	if int(row[4]) > 0:
		H._next_actor(engine, actor.actor_id, failures)
		var cooldown_before: Dictionary = engine.snapshot()
		F.expect(not engine.submit(H._command(engine, "skill", row[2], [target_id])).accepted and engine.snapshot() == cooldown_before, "冷却中不收费/不加效果：" + row[7], failures)
		for step in int(row[4]):
			engine.submit(H._command(engine, "defend"))
			H._next_actor(engine, actor.actor_id, failures)
		F.expect(engine.preview(H._command(engine, "skill", row[2], [target_id])).legal, "足额行动槽后专精重新可用：" + row[7], failures)

static func _test_branches(catalog: RefCounted, failures: Array[String]) -> void:
	for index in [0, 4, 5]:
		var actor := _actor(catalog, CASES[index])
		actor.level = 9
		actor.branch = {"id": "economy"}
		var skill: Dictionary = catalog.skill_for(actor, CASES[index][2])
		F.expect(skill.mp_cost == {0: 6, 4: 8, 5: 11}[index], "专精附加费用在L9节约分支后计算", failures)
		actor.branch = {"id": "power"}
		skill = catalog.skill_for(actor, CASES[index][2])
		if index != 5: F.expect(is_equal_approx(skill.effects[0].get("conditional_coefficient", 0.0), 2.1 if index == 0 else 2.0), "专精增量在强度分支后派生", failures)
		else: F.expect(skill.effects[0].fixed == 44 and skill.effects.size() == 2, "苏合强度分支保留44固定治疗与护盾", failures)

static func _test_form_isolation(catalog: RefCounted, failures: Array[String]) -> void:
	var actor := _actor(catalog, CASES[3])
	F.expect(not catalog.skill_for(actor, "armor_break").get("refinement", {}).is_empty(), "焰华剑形独立专精", failures)
	F.expect(catalog.skill_for(actor, "firebolt").is_empty(), "剑形不能施放法形技能", failures)
	Forms.apply(actor, "mage", catalog)
	F.expect(not catalog.skill_for(actor, "firebolt").get("refinement", {}).is_empty(), "焰华法形独立专精", failures)
	F.expect(catalog.skill_for(actor, "armor_break").is_empty(), "法形不能施放剑形技能", failures)
	var wrong := F.actor("swordsman", "wrong")
	wrong["identity_id"] = "homura"
	F.expect(catalog.skill_for(wrong, "armor_break") == catalog.get_definition("skills", "armor_break"), "伪焰华无双形态合法标识不获得专精", failures)

static func _test_validation(failures: Array[String]) -> void:
	var source := "res://data/rpg/character_refinements.json"
	F.expect(FileAccess.file_exists(source), "专精独立JSON存在，不污染XLSX导出数据", failures)
	if not FileAccess.file_exists(source): return
	for row in [
		["version", func(d): d.schema_version = 99],
		["missing_form", func(d): d.definitions.pop_back()],
		["duplicate", func(d): d.definitions.append(d.definitions[0].duplicate(true))],
		["wrong_skill", func(d): d.definitions[0].skill_id = "firebolt"],
		["bad_cost", func(d): d.definitions[0].mp_cost_add = -1],
		["fractional_cost", func(d): d.definitions[0].mp_cost_add = 0.5],
		["bad_status", func(d): d.definitions[0].damage_condition.status_id = "missing"],
		["bad_effect", func(d): d.definitions[1].extra_effects[0].duration = 0],
		["unknown_field", func(d): d.definitions[0].free_mp = true]
	]:
		var path := F.write_catalog_copy("refinement_" + row[0])
		var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source))
		row[1].call(document)
		var file := FileAccess.open(path.path_join("character_refinements.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(document))
		file.close()
		var catalog := Catalog.new()
		F.expect(not catalog.load_all(path).is_empty(), "拒绝非法专精配置：" + row[0], failures)
		F.expect(catalog.get_ids("skills").is_empty() and catalog.get_ids("refinements").is_empty(), "专精加载失败不发布部分目录", failures)

	var broken_path := F.write_catalog_copy("refinement_bad_base", "skills", func(d): d.definitions[4].effects = {})
	var source_copy := FileAccess.open(broken_path.path_join("character_refinements.json"), FileAccess.WRITE)
	source_copy.store_string(FileAccess.get_file_as_string(source))
	source_copy.close()
	var broken := Catalog.new()
	F.expect(not broken.load_all(broken_path).is_empty() and broken.get_ids("skills").is_empty(), "基础技能已非法时专精派生必须停止，不能造成运行期异常", failures)

static func _test_cross_form_combo(catalog: RefCounted, failures: Array[String]) -> void:
	var homura := _actor(catalog, CASES[3])
	var enemy := F.enemy("hound", "enemy")
	enemy.stats.hp = 3000
	enemy.hp = 3000
	var engine = H._selection(BattleEngine, homura, [enemy])
	var initial: Dictionary = engine.snapshot()
	F.expect(engine.submit(H._command(engine, "skill", "armor_break", ["enemy"])).accepted, "实战剑形先用引火", failures)
	H._next_actor(engine, "p_mage", failures)
	var before_switch: Dictionary = engine.snapshot()
	F.expect(F.find_status(before_switch.actors.enemy, "burn").get("remaining") == 1, "下一行动时火种仍保留1槽", failures)
	var switch_command := H._command(engine, "switch_form")
	switch_command["form_id"] = "mage"
	F.expect(engine.submit(switch_command).accepted, "实战切法形保留当前行动", failures)
	var switched: Dictionary = engine.snapshot()
	F.expect(switched.actors.p_mage.mp == before_switch.actors.p_mage.mp and switched.actors.p_mage.cooldown_until == before_switch.actors.p_mage.cooldown_until and switched.actors.p_mage.slot_count == before_switch.actors.p_mage.slot_count, "专精切形不刷新MP/CD/槽", failures)
	var command := H._command(engine, "skill", "firebolt", ["enemy"])
	var preview: Dictionary = engine.preview(command)
	F.expect(is_equal_approx(H._event(preview.effects, "damage").payload.factors.coefficient, 1.7), "引火→续焰组合真实采用170%术攻", failures)
	F.expect(engine.submit(command).accepted and engine.snapshot().actors.p_mage.mp == homura.mp - 9 - 11, "两形态联合连招真实共耗20MP", failures)
	var snapshot: Dictionary = engine.snapshot()
	var commands: Array[Dictionary] = []
	commands.assign(snapshot.command_log)
	var events: Array[Dictionary] = []
	events.assign(snapshot.event_log.slice(initial.event_log.size()))
	F.expect(Replay.verify(Replay.record(initial, commands, events), catalog).matches, "跨形态完整连招包括对方行动逐事件重放", failures)

static func _test_existing_effect_priority(catalog: RefCounted, failures: Array[String]) -> void:
	var homura := _actor(catalog, CASES[3])
	var enemy := F.enemy("hound", "enemy")
	Status.apply(enemy, F.status("burn", 13.0, 3, "other", {"base": 13.0}))
	var engine = H._selection(BattleEngine, homura, [enemy])
	var burn: Dictionary = F.find_status(engine.snapshot().actors.enemy, "burn")
	F.expect(engine.submit(H._command(engine, "skill", "armor_break", ["enemy"])).accepted, "已有强灼烧时破甲攻击仍可执行", failures)
	F.expect(F.find_status(engine.snapshot().actors.enemy, "burn") == burn, "弱火种不降级/延长已有强灼烧", failures)
	var healer := _actor(catalog, CASES[5])
	var ally := F.actor("guard", "ally")
	ally.hp = 50
	ally.shield = F.shield(100, 2, "other")
	engine = H._selection(BattleEngine, healer, [ally, F.enemy("hound", "enemy")])
	var shield: Dictionary = engine.snapshot().actors.ally.shield.duplicate(true)
	F.expect(engine.submit(H._command(engine, "skill", "heal", ["ally"])).accepted, "已有强盾时仍可治疗", failures)
	F.expect(engine.snapshot().actors.ally.hp == 136 and engine.snapshot().actors.ally.shield == shield, "护生真实治疗86且不覆盖或延长强盾", failures)
