# 装配测试仅经 Python 隔离入口运行；独立目录适配器读取真实数据，避免接线先后影响纯规则。
extends SceneTree

class DataCatalog extends RefCounted:
	var definitions: Dictionary = {}
	func _init() -> void:
		for kind in ["classes", "skills", "equipment"]:
			definitions[kind] = {}
			var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rpg/" + kind + ".json"))
			for row in data.definitions: definitions[kind][row.id] = row
		if FileAccess.file_exists("res://data/rpg/loadout_equipment.json"):
			var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rpg/loadout_equipment.json"))
			for row in data.definitions: definitions.equipment[row.id] = row
	func get_definition(kind: String, id: String) -> Dictionary:
		return definitions.get(kind, {}).get(id, {}).duplicate(true)

var rules: GDScript
var catalog: RefCounted
var assertions := 0
var failures: Array[String] = []

func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1":
		printerr("FAIL: 请通过隔离 Python 入口运行装配测试")
		quit(1)
		return
	_expect(FileAccess.file_exists("res://scripts/rpg/loadout_rules.gd"), "无等级装配必须有可运行的派生规则")
	if failures.is_empty():
		rules = load("res://scripts/rpg/loadout_rules.gd")
		catalog = DataCatalog.new()
		_test_defaults()
		_test_cross_class()
		_test_validation()
		_test_dual_form()
		_test_passive_and_visuals()
		_test_visual_assets()
	print("RPG_LOADOUTS: %d assertions, %d failures" % [assertions, failures.size()])
	for failure in failures: printerr("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)

func _actor(class_id: String = "swordsman") -> Dictionary:
	var actor := {"class_id": class_id, "actor_id": "p_" + class_id, "side": "player", "equipment": rules.starting_equipment(class_id), "build": rules.default_build(class_id)}
	if class_id == "mage":
		actor.merge({"identity_id": "homura", "dual_form_version": 1, "form_id": "sword", "active_class_id": "swordsman", "unlocked_forms": ["sword", "mage"]})
	var result: Dictionary = rules.derive(actor, catalog)
	actor.stats = result.stats.duplicate(true)
	actor.skill_ids = result.skill_ids.duplicate()
	return actor

func _test_defaults() -> void:
	var owned: Dictionary = rules.initial_cards()
	_expect(owned.size() == 26, "初始收藏拥有24主动与2入门被动")
	for class_id in ["guard", "swordsman", "ranger", "mage", "healer", "controller"]:
		var actor := _actor(class_id)
		var before := actor.duplicate(true)
		var result: Dictionary = rules.derive(actor, catalog)
		_expect(result.ok, "默认装配合法：" + class_id + str(result.errors))
		_expect(actor == before, "派生不修改角色：" + class_id)
		_expect(result.skill_ids.size() == 4 and result.capacity.active_used <= 10, "默认四卡在容量内：" + class_id)
		_expect(result.stats.size() == 7, "派生严格输出七属性：" + class_id)
		for key in result.stats: _expect(result.stats[key] is int, "属性为整值：" + class_id + key)
		_expect(rules.validate_actor(actor, catalog, owned).is_empty(), "已拥有默认装配通过完整校验：" + class_id)
	var empty := _actor()
	empty.build.active.default = []
	var result: Dictionary = rules.derive(empty, catalog)
	_expect(result.ok and result.skill_ids.is_empty() and result.capacity.active_used == 0, "空主动组保留基础行动且合法")
	_expect(result.stats == {"hp": 240, "mp": 40, "atk": 62, "matk": 18, "def": 30, "mdef": 25, "spd": 35}, "固定裸值叠加起始装备产生可人工复算属性")
	_expect(not rules.has_data({"skill_ids": []}) and rules.has_data({"build": null}), "build存在即进入新规则，损坏build不能回落旧规则")
	_expect(rules.default_build("unknown").is_empty(), "未知身份不给隐式默认装配")
	_expect(rules.starting_equipment("unknown").is_empty(), "未知身份不给隐式起始装备")

func _test_cross_class() -> void:
	var actor := _actor("healer")
	actor.build.active.default = ["firebolt", "slow", "heal"]
	var result: Dictionary = rules.derive(actor, catalog)
	_expect(result.ok and result.skill_ids == ["firebolt", "slow", "heal"], "治疗身份可用法器准备跨职业火弹和缓速")
	actor.build.active.default = ["heavy_slash"]
	_expect(not rules.derive(actor, catalog).ok, "法铃缺刃标签时拒绝剑技")
	actor.equipment.weapon = "training_blade"
	_expect(rules.derive(actor, catalog).ok, "同一治疗身份换刀后可准备剑技")
	actor.equipment.weapon = "exorcism_sword"
	_expect(rules.derive(actor, catalog).ok, "旧退邪剑登记刃标签")
	actor.equipment.weapon = "standard_weapon"
	_expect(not rules.derive(actor, catalog).ok, "旧标准武器按身份标签，不万能放行")
	actor.build.active.default = ["heal"]
	_expect(rules.derive(actor, catalog).ok, "旧标准武器兼容原身份技能")
	catalog.definitions.equipment["unmapped_weapon"] = {"id": "unmapped_weapon", "slot": "weapon", "stats": {"atk": 5}}
	actor.equipment.weapon = "unmapped_weapon"
	_expect(not rules.derive(actor, catalog).ok, "目录已知而标签未登记的武器仍拒绝")
	catalog.definitions.equipment.erase("unmapped_weapon")

func _test_validation() -> void:
	var invalid: Array = []
	var base := _actor()
	for bad_build in [null, {}, {"version": 2, "active": {"default": []}, "passive": []}, {"version": 1.0, "active": {"default": []}, "passive": []}, {"version": 1, "active": {"default": []}, "passive": [], "extra": true}, {"version": 1, "active": {"default": [], "mage": []}, "passive": []}]:
		var actor := base.duplicate(true)
		actor.build = bad_build
		invalid.append(actor)
	for ids in [["heavy_slash", "heavy_slash"], ["unknown"], ["steady_breath"], ["heavy_slash", "armor_break", "sweep", "battle_spirit", "cover"], [12]]:
		var actor := base.duplicate(true)
		actor.build.active.default = ids
		invalid.append(actor)
	var over := _actor("mage")
	over.build.active.sword = ["heavy_slash", "sweep", "flame_wave", "ice_arrow"]
	invalid.append(over)
	for ids in [["steady_breath", "steady_breath"], ["heavy_slash"], ["unknown"], ["steady_breath", "light_step", "force_channel"], ["iron_oath", "sustained_rite"]]:
		var actor := base.duplicate(true)
		actor.build.passive = ids
		invalid.append(actor)
	for equipment in [{"weapon": "unknown"}, {"weapon": "standard_armor"}, {"weapon": 12}, {"weapon": "training_blade", "extra": "standard_armor"}]:
		var actor := base.duplicate(true)
		actor.equipment = equipment
		invalid.append(actor)
	for actor in invalid:
		var before: Dictionary = actor.duplicate(true)
		_expect(not rules.derive(actor, catalog).ok, "非法构筑拒绝：" + str(actor))
		_expect(actor == before, "非法派生同样只读")
	for key in ["level", "xp"]:
		var actor := base.duplicate(true)
		actor[key] = 1
		_expect(not rules.validate_actor(actor, catalog).is_empty(), "无等级角色拒绝字段：" + key)
	var tampered := base.duplicate(true)
	tampered.stats.atk += 1
	_expect(not rules.validate_actor(tampered, catalog).is_empty(), "伪造派生属性不能读档")
	tampered = base.duplicate(true)
	tampered.skill_ids = []
	_expect(not rules.validate_actor(tampered, catalog).is_empty(), "伪造派生技能不能读档")
	_expect(not rules.validate_actor(base, catalog, {}).is_empty(), "无收藏拒绝已装卡")
	var owned: Dictionary = rules.initial_cards()
	owned.heavy_slash = 0
	_expect(not rules.validate_actor(base, catalog, owned).is_empty(), "零持有量不能解锁卡")
	owned.heavy_slash = 1.5
	_expect(not rules.validate_actor(base, catalog, owned).is_empty(), "非整数持有量不能解锁卡")

func _test_dual_form() -> void:
	var actor := _actor("mage")
	var sword: Dictionary = rules.derive(actor, catalog)
	actor.form_id = "mage"
	actor.active_class_id = "mage"
	var magic: Dictionary = rules.derive(actor, catalog)
	_expect(magic.ok and magic.skill_ids == ["firebolt", "flame_wave", "ice_arrow", "burn_brand"], "当前法形态使用自己的已装组")
	_expect(sword.stats == magic.stats, "切形态共用身份基础属性，不改变生命灵力或速度")
	actor.build.active.sword = ["hunt"]
	_expect(not rules.derive(actor, catalog).ok, "备用剑形态非法也必须拒绝")
	actor = _actor("mage")
	actor.form_id = "other"
	_expect(not rules.derive(actor, catalog).ok, "未登记形态拒绝")
	actor = _actor("mage")
	actor.build.passive = ["light_step"]
	var first: Dictionary = rules.derive(actor, catalog)
	actor.form_id = "mage"
	actor.active_class_id = "mage"
	var second: Dictionary = rules.derive(actor, catalog)
	_expect(first.capacity.passive_used == second.capacity.passive_used and second.capacity.passive_used == 2, "双形态共享同一被动容量")
	var owned: Dictionary = rules.initial_cards()
	owned.erase("firebolt")
	actor = _actor("mage")
	_expect(not rules.validate_actor(actor, catalog, owned).is_empty(), "备用法形态也检查收藏")

func _test_passive_and_visuals() -> void:
	var actor := _actor()
	actor.build.passive = ["steady_breath", "light_step"]
	var result: Dictionary = rules.derive(actor, catalog)
	_expect(result.ok and result.capacity.passive_used == 4, "被动容量边界四点合法")
	var original: Dictionary = rules.derive(_actor(), catalog)
	_expect(result.stats.mp == original.stats.mp + 4 and result.stats.spd == original.stats.spd + 2 and result.stats.def == original.stats.def - 2, "被动明确以防御换速度，以速度换灵力")
	var modifiers: Dictionary = rules.skill_modifiers(actor, "heavy_slash")
	_expect(modifiers.mp_cost_add == -1 and modifiers.cooldown_add == 0 and modifiers.coefficient_add == 0.0 and modifiers.duration_add == 0, "已准备技能获得节灵词条")
	_expect(rules.skill_modifiers(actor, "firebolt").mp_cost_add == 0, "未装技能不能借被动取得派生效果")
	var cards: Array = rules.all_cards()
	var passive_count := 0
	for item in cards:
		if item.type == "passive": passive_count += 1
		else:
			var skill: Dictionary = catalog.get_definition("skills", item.id)
			_expect(not skill.is_empty(), "主动卡使用既有技能定义：" + item.id)
			_expect(not rules.visual_form(actor, item.id).is_empty(), "跨身份技能有合法视觉形态：" + item.id)
	_expect(passive_count >= 6, "至少六种被动可供后续收藏")
	var copy: Dictionary = rules.card("heavy_slash")
	copy.name = "已改动"
	_expect(rules.card("heavy_slash").name != "已改动", "卡片查询不能修改全局定义")
	_expect(rules.card("missing").is_empty() and rules.visual_form(actor, "missing").is_empty(), "未知卡和未知视觉均不猜测默认")
	_expect(rules.visual_form(actor, "heavy_slash") == "rinne", "跨身份共享剑技默认凛音变体")
	var homura := _actor("mage")
	_expect(rules.visual_form(homura, "heavy_slash") == "homura_sword", "焰华剑形态使用本人剑技变体")
	homura.form_id = "mage"
	_expect(rules.visual_form(homura, "heavy_slash") == "rinne", "焰华术形态跨装剑技仍选合法普通剑变体")
	for passive_id in ["force_channel", "iron_oath", "sustained_rite", "swift_cast"]:
		actor = _actor()
		actor.build.passive = [passive_id]
		var derived: Dictionary = rules.derive(actor, catalog)
		_expect(derived.ok, "后续被动具备合法属性及容量：" + passive_id)
		var mods: Dictionary = rules.skill_modifiers(actor, "heavy_slash")
		for key in ["mp_cost_add", "cooldown_add", "duration_add"]:
			_expect(mods[key] is int, "整数技能词条不变成浮点：" + passive_id + key)
		if passive_id == "force_channel": _expect(is_equal_approx(mods.coefficient_add, 0.15) and mods.mp_cost_add == 1, "强引以额外消耗换系数")
		if passive_id == "sustained_rite": _expect(mods.duration_add == 1 and mods.mp_cost_add == 1, "延仪以额外消耗换持续时间")
		if passive_id == "swift_cast": _expect(mods.cooldown_add == -1 and mods.mp_cost_add == 1, "疾咏以额外消耗换冷却")

func _test_visual_assets() -> void:
	# 所有身份逐卡跨装，确认派生合法并指向已有批准图集；这不是GPU或人工GUI验收。
	var verified: Dictionary = {}
	var weapon_for := {"blade": "training_blade", "shield": "training_guard_blade", "bow": "training_bow", "focus": "training_focus_blade", "bell": "training_bell", "sigil": "training_sigil"}
	for class_id in ["guard", "swordsman", "ranger", "mage", "healer", "controller"]:
		for form in (["sword", "mage"] if class_id == "mage" else ["default"]):
			for definition in rules.all_cards():
				if definition.type != "active": continue
				var actor := _actor(class_id)
				for key in actor.build.active: actor.build.active[key] = []
				actor.build.active[form] = [definition.id]
				if class_id == "mage": actor.form_id = form
				actor.equipment.weapon = weapon_for[definition.weapon_tags[0]]
				_expect(rules.derive(actor, catalog).ok, "身份满足标签即可跨装：%s/%s/%s" % [class_id, form, definition.id])
				var visual: String = rules.visual_form(actor, definition.id)
				var variant: String = visual + "-" + definition.id if visual in ["rinne", "homura_sword"] else definition.id
				if verified.has(variant): continue
				verified[variant] = true
				var path := "res://assets/effects/imagegen_spells/" + variant + "/manifest.json"
				_expect(FileAccess.file_exists(path), "跨职业变体已有清单：" + variant)
				if not FileAccess.file_exists(path): continue
				var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
				_expect(manifest.get("skill_id") == definition.id and manifest.get("form_id", visual) == visual, "视觉变体与技能/形态一致：" + variant)
				var atlas: String = "res://assets/effects/imagegen_spells/" + manifest.runtime_atlas
				_expect(FileAccess.get_sha256(atlas) == manifest.runtime_atlas_sha256, "跨职业图集原字节符合清单：" + variant)
	_expect(verified.size() == 28, "六身份与焰华双形态覆盖24技能的28图集变体")
