extends RefCounted

const Fixtures = preload("res://tools/rpg/fixtures.gd")
const BASE := {
	"guard": [320, 30, 42, 18, 50, 30, 20], "swordsman": [240, 40, 60, 20, 30, 25, 35],
	"ranger": [180, 45, 54, 22, 20, 20, 50], "mage": [170, 80, 18, 65, 15, 35, 28],
	"healer": [210, 75, 20, 55, 25, 40, 25], "controller": [200, 65, 26, 52, 22, 32, 40]
}
const GROWTH := {
	"guard": [24, 2, 3, 1, 3, 2, 1], "swordsman": [18, 3, 5, 1, 2, 2, 1],
	"ranger": [14, 3, 4, 1, 1, 1, 2], "mage": [12, 6, 1, 5, 1, 2, 1],
	"healer": [16, 5, 1, 4, 2, 3, 1], "controller": [15, 5, 2, 4, 1, 2, 2]
}

static func run() -> Array[String]:
	Fixtures.assertion_count = 0
	var failures: Array[String] = []
	for script in ["catalog", "actor_factory", "battle_state"]:
		if not FileAccess.file_exists("res://scripts/rpg/%s.gd" % script):
			failures.append("未实现模型：" + script)
	if not failures.is_empty():
		return failures
	var Catalog = load("res://scripts/rpg/catalog.gd")
	var Factory = load("res://scripts/rpg/actor_factory.gd")
	var State = load("res://scripts/rpg/battle_state.gd")
	var catalog = Catalog.new()
	var load_errors: Array[String] = catalog.load_all()
	Fixtures.expect(load_errors.is_empty(), "正式数据校验通过：" + str(load_errors), failures)
	if not load_errors.is_empty():
		return failures
	_test_tables(catalog, failures)
	Fixtures.expect(catalog.get_ids("classes").size() == 6, "六个唯一职业", failures)
	Fixtures.expect(catalog.get_ids("skills").size() == 24, "24 个唯一技能", failures)
	var factory = Factory.new(catalog)
	var all_skills: Array[String] = []
	for class_id in BASE:
		var definition: Dictionary = catalog.get_definition("classes", class_id)
		Fixtures.expect(definition.skill_ids.size() == 4, class_id + " 恰有四个卡位", failures)
		for skill_id in definition.skill_ids:
			Fixtures.expect(not all_skills.has(skill_id), "技能不跨职业重复：" + skill_id, failures)
			all_skills.append(skill_id)
		for level in [1, 5, 10]:
			var stats: Dictionary = factory.stats_for(class_id, level, Fixtures.STANDARD_EQUIPMENT)
			Fixtures.expect(stats.size() == 7, class_id + " 七项属性", failures)
			for index in range(7):
				var key: String = Fixtures.STAT_KEYS[index]
				Fixtures.expect(stats.get(key) == BASE[class_id][index] + (level - 5) * GROWTH[class_id][index], "%s L%d %s 基准成长" % [class_id, level, key], failures)
	Fixtures.expect(factory.stats_for("guard", 5, {}) == {"hp": 300, "mp": 25, "atk": 37, "matk": 13, "def": 45, "mdef": 25, "spd": 20}, "无装备先扣标准属性", failures)
	for level in [0, 11]:
		Fixtures.expect(factory.create("guard", "hero", level, {}).is_empty(), "非法等级拒绝创建", failures)
	Fixtures.expect(factory.create("unknown", "hero", 5, {}).is_empty(), "缺职业引用拒绝", failures)
	Fixtures.expect(factory.create("guard", "", 5, {}).is_empty(), "空永久 ID 拒绝", failures)
	Fixtures.expect(factory.create("guard", "hero", 5, {"weapon": "missing"}).is_empty(), "缺装备引用拒绝", failures)
	Fixtures.expect(factory.create("guard", "hero", 5, {"weapon": "standard_armor"}).is_empty(), "装备槽错配拒绝", failures)
	var actor: Dictionary = factory.create("guard", "hero", 5, Fixtures.STANDARD_EQUIPMENT)
	Fixtures.expect(actor.skill_ids.size() == 4 and actor.hp == 320 and actor.mp == 30, "完整角色初始满资源", failures)
	for level in [1, 2, 3]:
		Fixtures.expect(factory.unlocked_skill_ids("guard", level).size() == mini(level + 1, 4), "按等级开放固定技能", failures)
	var state: Dictionary = Fixtures.state(actor)
	Fixtures.expect(State.validate(state).is_empty(), "合法快照通过", failures)
	for mutate in [
		func(s): s.inventory.healing_potion = -1,
		func(s): s.actors.hero.hp = 321,
		func(s): s.actors.hero.mp = -1,
		func(s): s.actors.hero.level = 11,
		func(s): s.actors.hero.actor_id = "other",
		func(s): s.queue = ["hero", "hero"],
		func(s): s.rng_state = 9223372036854775807,
		func(s): s.actors.hero.intent = {"node": RefCounted.new()},
		func(s): s.inventory.healing_potion = 1.5,
		func(s): s.queue = ["missing"],
		func(s): s.phase = "bogus",
		func(s): s.schema_version = 2,
		func(s): s.actors.hero.equipment.weapon = "missing",
		func(s): s.actors.hero.cooldown_until = {"missing": 2},
		func(s): s.actors.hero.skill_ids[0] = "missing",
		func(s): s.active_actor_id = "hero"; s.phase = "action_selection",
		func(s): s.actors.hero.stats.hp = "320",
		func(s): s.rng_state = "9223372036854775808",
		func(s): s.actors.hero.class_id = 5,
		func(s): s.actors.hero.skill_ids = 5; s.actors.hero.cooldown_until = {"cover": 1}
	]:
		var invalid: Dictionary = state.duplicate(true)
		mutate.call(invalid)
		var before := invalid.duplicate(true)
		Fixtures.expect(not State.validate(invalid).is_empty(), "非法快照被拒绝", failures)
		Fixtures.expect(invalid == before, "校验不静默修复输入", failures)
	# 审查 I1：目录决定状态固定元数据，实例只改变合法运行期数值。
	for row in [["not_a_status", "target_slot", true], ["burn", "round_snapshot", true], ["awake", "target_slot", true]]:
		var invalid: Dictionary = state.duplicate(true)
		invalid.actors.hero.statuses = [{
			"id": row[0], "source_id": "hero", "magnitude": 0.2,
			"clock": row[1], "remaining": 2, "generation": 1,
			"applied_slot": 0, "dispellable": row[2], "snapshot": {}
		}]
		var before := invalid.duplicate(true)
		Fixtures.expect(not State.validate(invalid).is_empty(), "拒绝未知状态／目录元数据冲突：" + row[0], failures)
		Fixtures.expect(invalid == before, "状态校验不改写输入：" + row[0], failures)
	var valid_status_state: Dictionary = state.duplicate(true)
	valid_status_state.actors.hero.statuses = [{
		"id": "burn", "source_id": "hero", "magnitude": 0.35,
		"clock": "target_slot", "remaining": 4, "generation": 7,
		"applied_slot": 0, "dispellable": true, "snapshot": {"matk": 55}
	}]
	Fixtures.expect(State.validate(valid_status_state).is_empty(), "合法状态运行期幅度／时长保持灵活", failures)
	var copy: Dictionary = catalog.get_definition("classes", "guard")
	copy.base_stats.hp = 1
	Fixtures.expect(catalog.get_definition("classes", "guard").base_stats.hp == 320, "目录返回深复制", failures)
	for scenario in [
		["duplicate", "classes", func(d): d.definitions.append(d.definitions[0].duplicate(true))],
		["missing_ref", "classes", func(d): d.definitions[0].skill_ids[0] = "missing"],
		["bad_target", "skills", func(d): d.definitions[0].target_rule = "bogus"],
		["bad_element", "skills", func(d): d.definitions[0].element = "water"],
		["bad_cd", "skills", func(d): d.definitions[0].cooldown = -1],
		["bad_unlock", "skills", func(d): d.definitions[0].unlock_level = 11],
		["bad_clock", "statuses", func(d): d.definitions[0].clock = "wall_time"],
		["bad_direct", "skills", func(d): d.definitions[0].single_direct = true],
		["bad_effect_ref", "skills", func(d): d.definitions[0].effects[0].status_id = "missing"],
		["fractional_cost", "skills", func(d): d.definitions[0].mp_cost = 0.5],
		["enemy_attack", "enemies", func(d): d.definitions[0].default_attack = "bogus"],
		["enemy_policy", "enemies", func(d): d.definitions[0].target_policy = "bogus"],
		["boss_cycle", "enemies", func(d): d.definitions[5].boss.cycle[0] = "missing"],
		["condition", "skills", func(d): d.definitions[9].effects[0].condition = "random_dodge"],
		["branch_cost", "skills", func(d): d.definitions[0].branches.economy["6"].mp_cost = -1],
		["base_hp", "classes", func(d): d.definitions[0].base_stats.hp = 0],
		["enemy_ref", "encounters", func(d): d.definitions[0].enemy_ids[0] = "missing"],
		["item_stock", "items", func(d): d.definitions[0].initial_stock = -1],
		["version", "items", func(d): d.rules_version = "future"],
		["effects", "skills", func(d): d.definitions[0].effects = {}],
		["class_id", "classes", func(d): d.definitions[0].id = "unexpected"],
		["hunt_missing_status", "skills", func(d): d.definitions[9].effects[0].erase("status_id")],
		["hunt_missing_coefficient", "skills", func(d): d.definitions[9].effects[0].erase("conditional_coefficient")],
		["ambush_missing_coefficient", "skills", func(d): d.definitions[10].effects[0].erase("conditional_coefficient")],
		["orphan_coefficient", "skills", func(d): d.definitions[4].effects[0].conditional_coefficient = 2.0],
		["hunt_bad_status", "skills", func(d): d.definitions[9].effects[0].status_id = "missing"],
		["hunt_negative_coefficient", "skills", func(d): d.definitions[9].effects[0].conditional_coefficient = -0.1]
	]:
		var bad_catalog = Catalog.new()
		var path := Fixtures.write_catalog_copy(scenario[0], scenario[1], scenario[2])
		Fixtures.expect(not bad_catalog.load_all(path).is_empty(), "目录拒绝：" + scenario[0], failures)
		for kind in ["classes", "skills", "statuses", "enemies", "items", "equipment", "encounters", "abilities"]:
			Fixtures.expect(bad_catalog.get_ids(kind).is_empty() and bad_catalog.get_all(kind).is_empty(), "失败不暴露半加载数据：" + kind, failures)
		Fixtures.expect(bad_catalog.get_definition("skills", "hunt").is_empty(), "失败技能查询为空", failures)
	var config := ConfigFile.new()
	config.load("res://project.godot")
	Fixtures.expect(not config.has_section_key("gui", "theme/custom"), "删除失效 v2 主题引用", failures)
	print("DATA_ASSERTIONS:", Fixtures.assertion_count)
	return failures


static func _test_tables(catalog: RefCounted, failures: Array[String]) -> void:
	# 费用、CD、目标、系数逐项绑定已评审表，不只验证目录内部自洽。
	var skills := {
		"cover": [6, 0, "other_ally", 0.0], "shield_bash": [6, 2, "single_enemy", 0.7],
		"iron_wall": [10, 2, "self", 0.0], "taunt": [4, 1, "single_enemy", 0.0],
		"heavy_slash": [8, 0, "single_enemy", 1.5], "armor_break": [7, 1, "single_enemy", 1.0],
		"sweep": [12, 1, "all_enemies", 0.85], "battle_spirit": [6, 2, "self", 0.0],
		"mark": [4, 0, "single_enemy", 0.0], "hunt": [8, 0, "single_enemy", 1.3],
		"ambush": [7, 1, "single_enemy", 1.0], "smoke_screen": [8, 2, "self", 0.0],
		"firebolt": [10, 0, "single_enemy", 1.4], "flame_wave": [18, 1, "all_enemies", 0.8],
		"ice_arrow": [10, 1, "single_enemy", 1.1], "burn_brand": [8, 1, "single_enemy", 0.3],
		"heal": [12, 1, "single_ally", 0.0], "group_heal": [22, 2, "all_allies", 0.0],
		"cleanse": [6, 0, "single_ally", 0.0], "holy_shield": [10, 1, "single_ally", 0.0],
		"weaken": [8, 0, "single_enemy", 0.0], "slow": [10, 1, "all_enemies", 0.0],
		"seal": [12, 2, "single_enemy", 0.0], "magic_break": [8, 1, "single_enemy", 0.6]
	}
	for id in skills:
		var skill: Dictionary = catalog.get_definition("skills", id)
		Fixtures.expect([skill.mp_cost, skill.cooldown, skill.target_rule] == skills[id].slice(0, 3), id + " 技能费用／CD／目标", failures)
		var coefficient := 0.0
		for effect in skill.effects:
			if effect.type == "damage":
				coefficient = float(effect.coefficient)
		Fixtures.expect(is_equal_approx(coefficient, skills[id][3]), id + " 基础伤害系数", failures)
	var status_effects := {
		"cover": [0, "cover", 0.3, 1, "next_owner_slot"], "taunt": [0, "taunt", 1.0, 2, "target_slot"],
		"armor_break": [1, "armor_break", 0.25, 2, "target_slot"], "battle_spirit": [0, "battle_spirit", 0.4, 2, "target_slot"],
		"mark": [0, "mark", 1.0, 3, "target_slot"], "ice_arrow": [1, "slow", 0.3, 1, "round_snapshot"],
		"burn_brand": [1, "burn", 0.2, 3, "target_slot"], "weaken": [0, "weaken", 0.2, 2, "target_slot"],
		"slow": [0, "slow", 0.3, 2, "round_snapshot"], "seal": [0, "stun", 1.0, 1, "target_slot"],
		"magic_break": [1, "magic_break", 0.25, 2, "target_slot"]
	}
	for id in status_effects:
		var expected: Array = status_effects[id]
		var effect: Dictionary = catalog.get_definition("skills", id).effects[expected[0]]
		Fixtures.expect(effect.type == "apply_status" and effect.status_id == expected[1] and is_equal_approx(effect.magnitude, expected[2]) and effect.duration == expected[3] and effect.clock == expected[4], id + " 状态幅度／时长／效果顺序", failures)
	for row in [["heal", "heal", 20, 1.2, "matk"], ["group_heal", "heal", 10, 0.6, "matk"], ["iron_wall", "shield", 30, 0.8, "def"], ["smoke_screen", "shield", 20, 0.6, "atk"], ["holy_shield", "shield", 20, 0.8, "matk"]]:
		var effect: Dictionary = catalog.get_definition("skills", row[0]).effects[0]
		Fixtures.expect(effect.type == row[1] and effect.fixed == row[2] and is_equal_approx(effect.coefficient, row[3]) and effect.stat == row[4], row[0] + " 固定项／系数／取值属性", failures)
	Fixtures.expect(catalog.get_definition("skills", "hunt").effects[0].conditional_coefficient == 2.8, "标记猎杀 2.8", failures)
	Fixtures.expect(catalog.get_definition("skills", "ambush").effects[0].conditional_coefficient == 1.5, "先手奇袭 1.5", failures)
	Fixtures.expect(catalog.get_definition("statuses", "awake").dispellable == false, "清醒不可驱散", failures)
	Fixtures.expect(catalog.get_definition("statuses", "stagger").clock == "target_slot", "失衡到释放槽结束", failures)
	var enemies := {
		"hound": [180, 0, 45, 10, 20, 15, 40], "shield_soldier": [240, 18, 40, 18, 40, 25, 18],
		"fire_spirit": [190, 40, 15, 50, 15, 30, 32], "cultist": [210, 40, 35, 45, 20, 30, 26],
		"elite_shield_soldier": [360, 24, 52, 25, 45, 30, 24], "gatekeeper": [780, 60, 60, 45, 30, 30, 30]
	}
	for id in enemies:
		var enemy: Dictionary = catalog.get_definition("enemies", id)
		for index in range(7):
			Fixtures.expect(enemy.base_stats[Fixtures.STAT_KEYS[index]] == enemies[id][index], id + " 敌人五级属性", failures)
		for ability in enemy.abilities:
			Fixtures.expect(catalog.get_definition("abilities", ability.id) == ability, ability.id + " 统一技能查询", failures)
			if id == "gatekeeper":
				for effect in ability.effects:
					if effect.type == "damage":
						Fixtures.expect(not effect.can_crit, "Boss 直接伤害不暴击", failures)
	for row in [["healing_potion", 3, "restore_hp", 80], ["mana_potion", 1, "restore_mp", 20], ["revival_potion", 1, "revive", 0.3], ["cleansing_powder", 1, "cleanse", 0]]:
		var item: Dictionary = catalog.get_definition("items", row[0])
		Fixtures.expect(item.initial_stock == row[1] and item.effects[0].type == row[2], row[0] + " 固定库存／效果", failures)
		if row[2] == "revive":
			Fixtures.expect(item.effects[0].fraction == row[3] and item.effects[0].preserve_mp, "复苏 30% 并保留 MP", failures)
		elif row[2] != "cleanse":
			Fixtures.expect(item.effects[0].fixed == row[3], row[0] + " 回复量", failures)
	Fixtures.expect(catalog.get_definition("encounters", "slice_1").enemy_ids == ["hound", "shield_soldier"], "首战固定敌人", failures)
	Fixtures.expect(catalog.get_definition("encounters", "slice_2").enemy_ids == ["hound", "cultist"] and catalog.get_definition("encounters", "slice_2").rest_after, "次战之后休息", failures)
	for row in [["slice_1", 40], ["slice_2", 40], ["slice_boss", 120]]:
		Fixtures.expect(catalog.get_definition("encounters", row[0]).xp == row[1], row[0] + " 固定经验", failures)
