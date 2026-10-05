# 六职业、有效分支与编队契约；夹具与存档只运行于隔离目录。
extends RefCounted
const F = preload("res://tools/rpg/fixtures.gd")
const T = preload("res://tools/rpg/test_engine.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Battle = preload("res://scripts/rpg/battle_engine.gd")
const Status = preload("res://scripts/rpg/status_rules.gd")
const Factory = preload("res://scripts/rpg/actor_factory.gd")
const Campaign = preload("res://scripts/rpg/campaign.gd")
const Store = preload("res://scripts/rpg/save_store.gd")
const Resolver = preload("res://scripts/rpg/effect_resolver.gd")
const Boss = preload("res://scripts/rpg/boss_policy.gd")
const Presenter = preload("res://scripts/rpg/ui/battle_presenter.gd")

static func run() -> Array[String]:
	F.assertion_count = 0
	var failures: Array[String] = []
	var catalog := Catalog.new()
	F.expect(catalog.load_all().is_empty(), "正式目录加载", failures)
	_test_ranger(catalog, failures)
	_test_mage_controller(catalog, failures)
	_test_control(catalog, failures)
	_test_branches(catalog, failures)
	_test_party_progression(catalog, failures)
	_test_presenter(catalog, failures)
	await _test_roster_controls(catalog, failures)
	await _test_danger_markers(catalog, failures)
	await _test_card_bounds(catalog, failures)
	await _test_low_level_cards(catalog, failures)
	print("RPG roster 断言：", F.assertion_count)
	return failures

static func _engine(class_id: String, enemies: Array = []):
	if enemies.is_empty(): enemies = [F.enemy("shield_soldier", "e_1")]
	return T._selection(Battle, F.actor(class_id, "p_active"), enemies)

static func _preview(engine, skill: String, targets: Array = ["e_1"]) -> Dictionary:
	return engine.preview(T._command(engine, "skill", skill, targets))

static func _test_ranger(catalog, failures: Array[String]) -> void:
	var engine = _engine("ranger")
	var mark := _preview(engine, "mark")
	F.expect(mark.legal and mark.damage_ranges.is_empty() and mark.mp_cost == 4, "标记仅准备动作无直接伤害、4MP", failures)
	F.expect(engine.submit(T._command(engine, "skill", "mark", ["e_1"])).accepted, "标记可提交", failures)
	T._next_actor(engine, "p_active", failures)
	var before: Dictionary = engine.snapshot()
	var hunt := _preview(engine, "hunt")
	F.expect(hunt.legal and hunt.mp_cost == 8, "标记猎杀合法且两行动总12MP", failures)
	if hunt.legal:
		F.expect(is_equal_approx(float(T._event(hunt.effects, "damage").payload.factors.coefficient), 2.8), "标记+猎杀两行动系数只有2.8", failures)
		F.expect(not T._event(hunt.effects, "status_removed").is_empty(), "猎杀预览明确消耗标记", failures)
		F.expect(" / ".join(Presenter.preview_lines(hunt, before, catalog)).contains("消耗猎物标记"), "猎杀预览点名消耗猎物标记", failures)
		F.expect(engine.snapshot() == before, "条件预览不消耗标记或RNG", failures)
		F.expect(engine.submit(T._command(engine, "skill", "hunt", ["e_1"])).accepted, "标记猎杀真实提交", failures)
		F.expect(F.find_status(engine.snapshot().actors.e_1, "mark").is_empty(), "猎杀实际消耗标记", failures)
	engine = _engine("ranger")
	hunt = _preview(engine, "hunt")
	F.expect(hunt.legal, "无标记猎杀合法", failures)
	if hunt.legal: F.expect(T._event(hunt.effects, "damage").payload.factors.coefficient == 1.3, "无标记猎杀1.3", failures)
	F.expect(Presenter.ability_summary(catalog.get_definition("skills", "ambush"), {}, catalog).contains("本轮目标未获行动槽"), "奇袭完整说明明确行动槽条件", failures)
	var ambush := _preview(engine, "ambush")
	F.expect(ambush.legal, "未获得槽的目标可奇袭", failures)
	if ambush.legal: F.expect(T._event(ambush.effects, "damage").payload.factors.coefficient == 1.5, "尚未获得槽奇袭1.5", failures)
	# 真实眩晕跳槽：未执行指令但已经获得本轮行动槽，必须只用1.0。
	var target := F.enemy("hound", "e_1")
	target.stats.spd = 1000
	Status.apply(target, F.status("stun", 1.0, 1, "p_active"))
	engine = _engine("ranger", [target])
	F.expect(engine.snapshot().actors.e_1.slot_count == 1 and engine.snapshot().actors.e_1.opportunity_count == 0, "奇袭夹具为真实眩晕跳槽", failures)
	ambush = _preview(engine, "ambush")
	F.expect(ambush.legal, "已跳槽目标奇袭仍合法", failures)
	if ambush.legal: F.expect(T._event(ambush.effects, "damage").payload.factors.coefficient == 1.0, "奇袭看槽不看成功指令或机会", failures)
	var smoke := _preview(engine, "smoke_screen", [])
	F.expect(smoke.legal and T._event(smoke.effects, "shield_applied").payload.shield.amount == 52, "烟幕20+0.6ATK取整为52", failures)
	F.expect(T._event(smoke.effects, "shield_applied").payload.shield.remaining == 2, "烟幕持续两个自身槽", failures)

static func _test_mage_controller(catalog, failures: Array[String]) -> void:
	for row in [["firebolt", 10, 0, 1.4, "fire"], ["flame_wave", 18, 1, 0.8, "fire"], ["ice_arrow", 10, 1, 1.1, "ice"], ["burn_brand", 8, 1, 0.3, "fire"]]:
		var engine = _engine("mage", [F.enemy("shield_soldier", "e_1"), F.enemy("hound", "e_2")])
		var preview := _preview(engine, row[0], [] if row[0] == "flame_wave" else ["e_1"])
		F.expect(preview.legal and preview.mp_cost == row[1] and preview.cooldown == row[2], row[0] + "费用CD可执行", failures)
		var damage := T._event(preview.effects, "damage")
		F.expect(damage.payload.factors.coefficient == row[3] and catalog.get_definition("skills", row[0]).element == row[4], row[0] + "准确系数与元素", failures)
		F.expect(preview.damage_ranges.size() == (2 if row[0] == "flame_wave" else 1), row[0] + "准确目标数量", failures)
		F.expect(engine.submit(T._command(engine, "skill", row[0], [] if row[0] == "flame_wave" else ["e_1"])).accepted, row[0] + "实际提交", failures)
		var target: Dictionary = engine.snapshot().actors.e_1
		if row[0] == "ice_arrow":
			F.expect(F.find_status(target, "slow").remaining == 1, "冰缓下一次快照", failures)
			var actors := {"e_1": target}
			F.expect(T._event(Status.begin_round(actors), "round_snapshot").payload.speed_reduction == 0.3, "冰缓准确30%", failures)
			Status.end_round(actors)
			F.expect(F.find_status(target, "slow").is_empty(), "冰缓仅一次快照", failures)
		if row[0] == "burn_brand":
			var burn := F.find_status(target, "burn")
			F.expect(burn.remaining == 3 and burn.snapshot.base == 13, "灼印三次、快照0.2MATK=13", failures)
			F.expect(Presenter.compact_effect(preview, catalog).contains("灼烧基数 13") and not Presenter.compact_effect(preview, catalog).contains("1300%"), "实际灼烧快照基数不误投影为目录百分比", failures)
	var engine = _engine("controller", [F.enemy("shield_soldier", "e_1"), F.enemy("hound", "e_2")])
	var weaken := _preview(engine, "weaken")
	F.expect(weaken.legal and T._event(weaken.effects, "status_applied").payload.status.magnitude == 0.2 and T._event(weaken.effects, "status_applied").payload.status.remaining == 2, "虚弱20%两槽", failures)
	var slow := _preview(engine, "slow", [])
	F.expect(slow.legal and slow.effective_target_ids == ["e_1", "e_2"] and T._event(slow.effects, "status_applied").payload.status.remaining == 2, "群缓30%两次快照", failures)
	var magic_break := _preview(engine, "magic_break")
	F.expect(magic_break.legal and magic_break.effects[0].type == "damage" and magic_break.effects[1].type == "status_applied", "破魔先伤害后状态", failures)
	F.expect(magic_break.effects[0].payload.factors.coefficient == 0.6 and magic_break.effects[1].payload.status.magnitude == 0.25 and magic_break.effects[1].payload.status.remaining == 2, "破魔0.6与25%两槽", failures)

static func _test_control(catalog, failures: Array[String]) -> void:
	var enemy := F.enemy("gatekeeper", "e_1")
	Boss.initialize(enemy)
	Status.apply(enemy, F.status("awake", 1.0, 2, "e_1"))
	var engine = _engine("controller", [enemy])
	var before: Dictionary = engine.snapshot()
	var seal := _preview(engine, "seal")
	F.expect(not seal.legal and seal.reasons.has("清醒期间免疫眩晕"), "清醒且无蓄力时纯控全部无效拒绝", failures)
	F.expect(not engine.submit(T._command(engine, "skill", "seal", ["e_1"])).accepted and engine.snapshot() == before, "无效控制不收费不记CD不耗槽或RNG", failures)
	var charge_state := {"actors": {"e_1": enemy, "p_active": F.actor("controller", "p_active")}}
	Boss.start_charge(charge_state, "e_1", ["p_active"], {"release_id": "boss_pierce_release", "interruptible": true}, catalog)
	enemy.boss.step = 3
	engine = _engine("controller", [enemy])
	seal = _preview(engine, "seal")
	F.expect(seal.legal and seal.reasons.has("清醒期间免疫眩晕") and not T._event(seal.effects, "charge_interrupted").is_empty(), "清醒独立允许打断并说明眩晕无效", failures)
	Boss.start_charge(charge_state, "e_1", ["p_active"], {"release_id": "boss_pulse_release", "interruptible": false}, catalog)
	enemy.boss.step = 6
	engine = _engine("controller", [enemy])
	seal = _preview(engine, "seal")
	F.expect(not seal.legal and seal.reasons.has("当前蓄力不可打断"), "脉冲保护期封缄免费拒绝", failures)
	# 群体软控制没有天生免疫；已有更强缓速使该目标新效果无效。
	var first := F.enemy("hound", "e_1")
	var second := F.enemy("hound", "e_2")
	Status.apply(first, F.status("slow", 0.5, 3, "p_active"))
	Status.apply(second, F.status("slow", 0.5, 3, "p_active"))
	engine = _engine("controller", [first, second])
	before = engine.snapshot()
	F.expect(not _preview(engine, "slow", []).legal, "范围纯控全部无效拒绝", failures)
	F.expect(engine.snapshot() == before, "全无效群控预览只读", failures)
	second.statuses = []
	engine = _engine("controller", [first, second])
	var partial := _preview(engine, "slow", [])
	F.expect(partial.legal and partial.effects.filter(func(e): return e.type == "effect_ignored").size() == 1, "部分有效群控保留逐目标拒绝原因", failures)
	F.expect(engine.submit(T._command(engine, "skill", "slow", [])).accepted, "部分群控可提交", failures)
	F.expect(F.find_status(engine.snapshot().actors.e_1, "slow").magnitude == 0.5 and F.find_status(engine.snapshot().actors.e_2, "slow").magnitude == 0.3, "部分群控只改变有效目标", failures)

static func _test_branches(catalog, failures: Array[String]) -> void:
	var root := F.write_catalog_copy("branch_zero_duration", "skills", func(doc):
		for skill in doc.definitions:
			if skill.id == "mark": skill.branches.duration["6"].duration = 0)
	F.expect(not Catalog.new().load_all(root).is_empty(), "目录拒绝分支duration=0", failures)
	F.expect(catalog.has_method("skill_for"), "目录提供有效技能skill_for", failures)
	if not catalog.has_method("skill_for"): return
	var rows := [["guard", "cover", "economy", "mp_cost", 4, 3], ["guard", "cover", "power", "magnitude", 0.4, 0.45], ["swordsman", "heavy_slash", "economy", "mp_cost", 6, 5], ["swordsman", "heavy_slash", "power", "coefficient", 1.65, 1.8], ["ranger", "mark", "duration", "duration", 4, 5], ["ranger", "hunt", "power", "conditional_coefficient", 3.0, 3.2], ["mage", "firebolt", "economy", "mp_cost", 8, 7], ["mage", "firebolt", "power", "coefficient", 1.55, 1.7], ["healer", "heal", "economy", "mp_cost", 10, 9], ["healer", "heal", "power", "fixed", 32, 44], ["controller", "weaken", "economy", "mp_cost", 6, 5], ["controller", "weaken", "power", "magnitude", 0.25, 0.3]]
	for row in rows:
		for level in [6, 8, 9, 10]:
			var actor := Factory.new(catalog).create(row[0], "p_active", level, F.STANDARD_EQUIPMENT)
			actor.branch = {"id": row[2]}
			var base: Dictionary = catalog.get_definition("skills", row[1])
			var skill: Dictionary = catalog.call("skill_for", actor, row[1])
			var actual = skill.get(row[3]) if row[3] == "mp_cost" else skill.effects[0].get(row[3])
			F.expect(is_equal_approx(float(actual), float(row[4 if level < 9 else 5])), "%s %s L%d准确数值" % [row[0], row[2], level], failures)
			F.expect(skill.cooldown == base.cooldown and actor.skill_ids.size() == 4, "分支不改CD和卡位", failures)
			if row[2] != "economy": F.expect(skill.mp_cost == base.mp_cost, "强度或持续分支不兼得节约", failures)
			skill.effects[0]["fixed"] = 9999
			F.expect(catalog.get_definition("skills", row[1]) == base, "有效技能深复制不污染目录", failures)
			var resolved := Resolver.ability_for(actor, {"kind": "skill", "ability_id": row[1]}, catalog)
			F.expect(resolved == catalog.call("skill_for", actor, row[1]), "解析器真实调用有效分支", failures)
			var enemy := F.enemy("shield_soldier", "e_1")
			var ally := F.actor("guard", "p_ally")
			ally.hp = 1
			if row[1] == "hunt": Status.apply(enemy, F.status("mark", 1.0, 3, "p_active"))
			var engine = T._selection(Battle, actor, [enemy, ally])
			var targets := ["p_ally"] if row[1] in ["cover", "heal"] else ["e_1"]
			var command: Dictionary = T._command(engine, "skill", row[1], targets)
			var preview: Dictionary = engine.preview(command)
			F.expect(preview.legal and preview.mp_cost == resolved.mp_cost, "有效分支真实预览费用", failures)
			var event: Dictionary = T._event(preview.effects, "damage")
			if row[3] in ["coefficient", "conditional_coefficient"]: F.expect(event.payload.factors.coefficient == actual, "分支真实伤害乘区", failures)
			if row[3] == "fixed": F.expect(T._event(preview.effects, "healed").payload.amount == roundi(actual + 1.2 * actor.stats.matk), "分支固定治疗进入真实公式", failures)
			F.expect(engine.submit(command).accepted and engine.snapshot().actors.p_active.mp == actor.mp - preview.mp_cost, "分支实际提交只扣准确MP", failures)
			F.expect(engine.snapshot().actors.p_active.cooldown_until[row[1]] == 2 + base.cooldown, "分支实际CD不变", failures)
	var ranger := Factory.new(catalog).create("ranger", "p_active", 9, F.STANDARD_EQUIPMENT)
	for branch in ["duration", "power"]:
		ranger.branch = {"id": branch}
		F.expect(catalog.call("skill_for", ranger, "mark").effects[0].duration == (5 if branch == "duration" else 3), "狩猎二选一标记时长", failures)
		F.expect(catalog.call("skill_for", ranger, "hunt").effects[0].conditional_coefficient == (3.2 if branch == "power" else 2.8), "狩猎二选一猎杀强度", failures)

static func _test_party_progression(catalog, failures: Array[String]) -> void:
	var factory := Factory.new(catalog)
	for class_id in Catalog.CLASS_IDS:
		for level in range(1, 11):
			F.expect(factory.unlocked_skill_ids(class_id, level).size() == mini(4, level + 1), "四槽等级解锁：%s L%d" % [class_id, level], failures)
	var campaign := Campaign.new(catalog, Store.new(catalog), "user://rpg_v1/roster_combinations.json")
	var classes: Array[String] = ["guard", "swordsman", "healer"]
	F.expect(campaign.new_run(classes, 6).ok, "隔离六级编队夹具", failures)
	var count := 0
	for a in range(6):
		for b in range(a + 1, 6):
			for c in range(b + 1, 6):
				var ids: Array[String] = ["p_" + Catalog.CLASS_IDS[a], "p_" + Catalog.CLASS_IDS[b], "p_" + Catalog.CLASS_IDS[c]]
				F.expect(campaign.set_party(ids).ok and campaign.snapshot().party == ids, "20种六选三持久化", failures)
				count += 1
	F.expect(count == 20, "六选三恰20种无序组合", failures)
	var duplicate: Array[String] = ["p_guard", "p_guard", "p_mage"]
	F.expect(not campaign.set_party(duplicate).ok, "重复队员拒绝", failures)
	F.expect(campaign.set_branch("p_ranger", "duration").ok and campaign.set_branch("p_ranger", "power").ok, "免费改选分支", failures)
	F.expect(campaign.snapshot().roster.p_ranger.branch == {"id": "power"}, "同角色只保存一分支", failures)
	var corrupt: Dictionary = campaign.snapshot()
	corrupt.roster.p_ranger.branch["duration"] = true
	F.expect(not Store.new(catalog).validate(corrupt).is_empty(), "拒绝混选分支的损坏存档", failures)
	var hp: int = campaign.snapshot().roster.p_guard.hp
	F.expect(campaign.equip("p_guard", "armor", "").ok and campaign.snapshot().roster.p_guard.hp == hp - 20, "卸甲降上限钳制当前HP", failures)
	F.expect(campaign.equip("p_guard", "armor", "standard_armor").ok and campaign.snapshot().roster.p_guard.hp == hp - 20, "重新装备升上限不回血", failures)
	F.expect(not campaign.equip("p_guard", "weapon", "standard_armor").ok and not campaign.equip("p_guard", "ring", "standard_accessory").ok, "仅三槽且槽位匹配", failures)
	F.expect(campaign.begin_battle("slice_1", {}).ok, "开始战斗锁定编队", failures)
	F.expect(not campaign.set_party(classes).ok and not campaign.equip("p_guard", "armor", "").ok and not campaign.set_branch("p_ranger", "duration").ok, "战内三类变更均拒绝", failures)

static func _test_presenter(catalog, failures: Array[String]) -> void:
	var taunt: Dictionary = catalog.get_definition("skills", "taunt")
	var text := Presenter.ability_summary(taunt, {}, catalog)
	F.expect(text.contains("挑衅") and not text.contains("100%") and text.contains("2次行动"), "挑衅布尔语义不显示100%", failures)
	var source := F.enemy("cultist", "e_1")
	var guard := F.actor("guard", "p_guard")
	var sword := F.actor("swordsman", "p_swordsman")
	Status.apply(guard, F.status("cover", 0.3, 1, "p_guard", {"target_id": "p_swordsman"}))
	var state := {"actors": {"e_1": source, "p_guard": guard, "p_swordsman": sword}, "round": 1}
	var ability_id: String = source.skill_ids[0]
	var events := Resolver.resolve(state, {"actor_id": "e_1", "kind": "skill", "ability_id": ability_id, "target_ids": ["p_swordsman"]}, catalog, null)
	var intent := {"ability_id": ability_id, "target_ids": ["p_swordsman"], "damage_type": "magic", "element": "spirit", "preview": {"effects": events, "damage_ranges": []}}
	text = Presenter.intent_text(intent, source, state, catalog)
	F.expect(text.contains("守卫：虚弱") and not text.contains("附加：虚弱"), "掩护后状态落点按真实ID点名守卫", failures)

static func _test_roster_controls(catalog, failures: Array[String]) -> void:
	var Launcher = load("res://scripts/rpg/ui/launcher_view.gd")
	var Router = load("res://scripts/rpg/encounter_router.gd")
	var launcher = Launcher.new()
	var tree: SceneTree = Engine.get_main_loop()
	tree.root.add_child(launcher)
	await tree.process_frame
	F.expect(launcher.available_class_ids.size() == 6, "真实准备界面可选六职业", failures)
	F.expect(launcher.has_method("open_roster"), "编队成长装备实际入口", failures)
	if not launcher.has_method("open_roster"):
		launcher.free()
		return
	var campaign := Campaign.new(catalog, Store.new(catalog), "user://rpg_v1/roster_ui.json")
	var initial: Array[String] = ["guard", "swordsman", "healer"]
	campaign.new_run(initial, 6)
	launcher.open({"router": Router.new(campaign)})
	launcher._hud.roster_notice.pressed.emit()
	F.expect(launcher._roster_panel.visible and launcher._roster_widgets.size() == 6, "按钮打开六人选择控件", failures)
	for id in initial: launcher._roster_widgets[id].toggle.pressed.emit()
	for id in ["ranger", "mage", "controller"]: launcher._roster_widgets[id].toggle.pressed.emit()
	F.expect(campaign.snapshot().party == ["p_guard", "p_swordsman", "p_healer"], "编队草稿未确认不写模型", failures)
	launcher._hud.party_apply.pressed.emit()
	F.expect(campaign.snapshot().party == ["p_ranger", "p_mage", "p_controller"], "六选三按钮确认真实保存", failures)
	F.expect(launcher._cards[0].class_id == "ranger" and launcher._cards[2].class_id == "controller", "更换编队重建立绘与徽记对应职业", failures)
	F.expect(launcher._cards[0].sprite.get_meta("art_id") == "mint" and launcher._cards[2].sprite.get_meta("art_id") == "rinne", "换人实际替换两套素材", failures)
	launcher._roster_widgets.mage.details.pressed.emit()
	launcher._branch_buttons.power.pressed.emit()
	F.expect(campaign.snapshot().roster.p_mage.branch.is_empty(), "分支预览未确认不保存", failures)
	F.expect(launcher._hud.branch_preview.text.contains("155%") and launcher._hud.branch_preview.text.contains("170%"), "分支面板显示L6/L9真实有效数值", failures)
	launcher._hud.branch_apply.pressed.emit()
	F.expect(campaign.snapshot().roster.p_mage.branch == {"id": "power"}, "分支确认走campaign保存", failures)
	launcher._equipment_buttons.armor.pressed.emit()
	var hp: int = campaign.snapshot().roster.p_mage.hp
	F.expect(campaign.snapshot().roster.p_mage.equipment.armor == "", "装备实际按钮可卸标准护甲", failures)
	launcher._equipment_buttons.armor.pressed.emit()
	F.expect(campaign.snapshot().roster.p_mage.equipment.armor == "standard_armor" and campaign.snapshot().roster.p_mage.hp == hp, "装备按钮重新装备不治疗", failures)
	var resumed = Launcher.new()
	resumed.open({"router": Router.new(Campaign.new(catalog, Store.new(catalog), "user://rpg_v1/roster_ui.json"))})
	F.expect(resumed.continue_game().ok, "编队保存后可重新载入", failures)
	F.expect(resumed.selected_class_ids == ["ranger", "mage", "controller"], "继续存档同步新局三人草稿，不暗退默认三职业", failures)
	var reordered: Array[String] = ["p_controller", "p_ranger", "p_mage"]
	F.expect(resumed.set_party(reordered).ok and resumed.selected_class_ids == ["controller", "ranger", "mage"], "外部编队API同步新局草稿", failures)
	resumed.free()
	# 恢复测试会话的最新安全版本，避免故意并发写触发陈旧保护。
	campaign.load_run()
	var started: Dictionary = campaign.begin_battle("slice_1", {})
	F.expect(started.ok, "UI锁定夹具真实开始战斗", failures)
	launcher._render()
	F.expect(launcher._hud.party_apply.disabled and launcher._hud.branch_apply.disabled and launcher._equipment_buttons.armor.disabled, "待战安全档所有成长操作锁定", failures)
	launcher.free()
	Router.clear_session()

static func _test_danger_markers(catalog, failures: Array[String]) -> void:
	var View = load("res://scripts/rpg/ui/battle_view.gd")
	var enemy := F.enemy("gatekeeper", "e_boss")
	var guard := F.actor("guard", "p_guard")
	var mage := F.actor("mage", "p_mage")
	guard.stats.spd = 999
	var actors := {"e_boss": enemy, "p_guard": guard, "p_mage": mage}
	Boss.start_charge({"actors": actors}, "e_boss", ["p_guard"], {"release_id": "boss_pierce_release", "interruptible": true}, catalog)
	enemy.boss.step = 3
	var engine := Battle.new(catalog)
	engine.start({"actors": actors, "inventory": {}}, 41)
	var view = View.new()
	view.bind(engine, null)
	var tree: SceneTree = Engine.get_main_loop()
	tree.root.add_child(view)
	await tree.process_frame
	var model := Presenter.present(engine.snapshot(), catalog)
	F.expect(model.get("danger", []).size() == 1, "Boss危险提示来自有效承诺", failures)
	F.expect(view.get("_danger_layer") != null, "危险标记实际绘制层", failures)
	if view.get("_danger_layer") != null:
		F.expect(view._danger_layer.get_child_count() > 0, "单体承诺实际红线", failures)
		var state: Dictionary = engine.snapshot()
		state.actors.p_guard.hp = 0
		state.actors.p_guard.statuses = []
		state.actors.p_guard.shield = {}
		# 只投影模型，不恢复已死亡活动者的非法选择快照。
		var dead_model := Presenter.present(state, catalog)
		F.expect(dead_model.danger[0].target_ids == ["p_guard"], "危险线不因承诺目标倒地漂移", failures)
		state.actors.e_boss.boss.charge_valid = false
		state.actors.e_boss.boss.charge_interrupted = true
		F.expect(Presenter.present(state, catalog).danger.is_empty(), "取消后清危险提示不保留红线", failures)
		Boss.start_charge(state, "e_boss", ["p_guard", "p_mage"], {"release_id": "boss_pulse_release", "interruptible": false}, catalog)
		state.actors.e_boss.boss.step = 6
		var pulse := Presenter.present(state, catalog)
		F.expect(pulse.danger[0].target_ids == ["p_guard", "p_mage"] and pulse.danger[0].area, "全体范围提示保留原承诺集合", failures)
		view._render_danger(pulse.danger)
		F.expect(view._danger_layer.get_child_count() >= 3, "全体承诺绘制覆盖目标范围与各目标圈", failures)
	view.free()

static func _test_card_bounds(catalog, failures: Array[String]) -> void:
	var View = load("res://scripts/rpg/ui/battle_view.gd")
	var tree: SceneTree = Engine.get_main_loop()
	for class_id in Catalog.CLASS_IDS:
		var engine = _engine(class_id)
		var view = View.new()
		view.bind(engine, null)
		tree.root.add_child(view)
		await tree.process_frame
		for button in view._skill_buttons:
			F.expect(button.size.x <= 336, class_id + "技能按钮不因长文案撑出固定卡位", failures)
			for line in button.text.split("\n"):
				F.expect(button.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x <= button.size.x - 68, class_id + "卡内文案在金色内缘外另留20像素：" + line, failures)
		view.free()

static func _test_low_level_cards(catalog, failures: Array[String]) -> void:
	var View = load("res://scripts/rpg/ui/battle_view.gd")
	var tree: SceneTree = Engine.get_main_loop()
	for class_id in Catalog.CLASS_IDS:
		for level in [1, 2, 3]:
			var actor := Factory.new(catalog).create(class_id, "p_active", level, F.STANDARD_EQUIPMENT)
			var engine = T._selection(Battle, actor, [F.enemy("shield_soldier", "e_1"), F.actor("guard", "p_ally")])
			var view = View.new()
			view.bind(engine, null)
			tree.root.add_child(view)
			await tree.process_frame
			F.expect(view._skill_buttons.size() == 4, "低等级仍固定四卡", failures)
			for index in range(4):
				var locked: bool = [1, 1, 2, 3][index] > level
				F.expect(view._skill_buttons[index].disabled == locked, "L%d %s 第%d卡准确解锁" % [level, class_id, index + 1], failures)
				if locked: F.expect(view._skill_buttons[index].text.contains("尚未解锁"), "锁定卡明确标注原因", failures)
			view.free()
