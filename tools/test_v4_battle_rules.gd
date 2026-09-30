# V4 战斗结算契约单测（GDD §6.2 / 代码实施方案 A 期出口）
# 用法: Godot --path <项目> --script res://tools/test_v4_battle_rules.gd
extends SceneTree

var _failed := false

func _initialize() -> void:
	_test_fire_one_hop_snapshot()
	_test_fire_snapshot_order_independent()
	_test_intent_priority()
	_test_intent_per_enemy_structure()
	_test_attack_resolution_sources()
	_test_fail_priority()
	_test_target_validation()
	_test_phase_b_mechanics()
	_test_phase_b_deck_building()
	_test_phase_b_artifacts()
	_test_phase_c_ritual()
	_test_phase_d_progress_save()
	if _failed:
		printerr("FAIL: v4 battle rules")
		quit(1)
	else:
		print("PASS: v4 battle rules (all contracts)")
		quit(0)

func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  ok - " + msg)
	else:
		_failed = true
		printerr("  ASSERT FAIL - " + msg)

# ---------- 火势：快照一跳 ----------
func _test_fire_one_hop_snapshot() -> void:
	print("STEP: fire spread snapshot (GDD §6.2 火势按开始快照扩散一跳)")
	# A-B-C 链：A 燃烧 → 只有 B 点燃，C 不受影响（即使 B 已在本跳被点燃）
	var states := {"A": "burning", "B": "idle", "C": "idle"}
	var adjacent := {"A": ["B"], "B": ["A", "C"], "C": ["B"]}
	var res: Dictionary = BattleRulesV4.fire_spread_snapshot(states, adjacent)
	_assert(res["changed"].has("B") and not res["changed"].has("C"),
		"链式 3 槽：A 燃 → B 点燃、C 不点燃（只跳一跳）")
	# 旧实现的顺序蔓延会让 B 在本 pass 继续点燃 C —— 本断言即契约差异
	_assert(states["C"] == "idle", "C 在本回合保持 idle")
	# 双向邻接不回传：B idle 时 A 燃，B 燃；下一步 B 燃也不重新「点燃」A
	var s2 := {"A": "burning", "B": "idle"}
	var r2: Dictionary = BattleRulesV4.fire_spread_snapshot(s2, {"A": ["B"], "B": ["A"]})
	_assert(r2["changed"].keys() == ["B"], "双向邻接：只点燃空闲的 B")
	# 无空闲邻接：不变化
	var s3 := {"A": "burning", "B": "sealed"}
	var r3: Dictionary = BattleRulesV4.fire_spread_snapshot(s3, {"A": ["B"], "B": []})
	_assert(r3["changed"].is_empty(), "邻接非空闲（sealed）不蔓延")

# 同一场景不同槽遍历顺序 → 同样结果
func _test_fire_snapshot_order_independent() -> void:
	print("STEP: fire spread order independence")
	var adj := {"a": ["b", "c"], "b": ["a", "d"], "c": ["a", "d"], "d": ["b", "c"]}
	var st1 := {"a": "burning", "b": "idle", "c": "idle", "d": "idle"}
	var st2 := {"d": "idle", "c": "idle", "b": "idle", "a": "burning"} # 不同遍历序
	var r1: Dictionary = BattleRulesV4.fire_spread_snapshot(st1, adj)
	var r2: Dictionary = BattleRulesV4.fire_spread_snapshot(st2, adj)
	_assert(r1["changed"].keys().size() == 2 and r2["changed"].keys().size() == 2,
		"双源同图：两跳各点燃 2 槽（b、c），d 不点燃")
	_assert(not r1["changed"].has("d") and not r2["changed"].has("d"),
		"遍历顺序不改变蔓延结果（d 两种序都不燃）")

# ---------- 意图优先级 ----------
func _test_intent_priority() -> void:
	print("STEP: intent priority 眩晕 > 暴走 > 恐惧降级")
	_assert(BattleRulesV4.compute_intent(["attack"], 0, true, true, true) == "stun",
		"眩晕覆盖暴走与恐惧")
	_assert(BattleRulesV4.compute_intent(["pounce"], 0, false, true, true) == "berserk",
		"暴走覆盖恐惧降级")
	_assert(BattleRulesV4.compute_intent(["pounce"], 0, false, false, true) == "attack",
		"恐惧中猛扑降级为 attack")
	_assert(BattleRulesV4.compute_intent(["howl"], 3, false, false, false) == "howl",
		"无覆盖时按 pattern 轮转")
	_assert(BattleRulesV4.compute_intent([], 5, false, false, false) == "attack",
		"空 pattern 缺省 attack")

# ---------- 每敌独立结构 ----------
func _test_intent_per_enemy_structure() -> void:
	print("STEP: per-enemy intent records (GDD §6.1)")
	# 结构契约：compute_intent 对同输入可分别存进每个单位字典，互不影响
	var u1 := {"intent": BattleRulesV4.compute_intent(["attack", "howl"], 1, false, false, false)}
	var u2 := {"intent": BattleRulesV4.compute_intent(["attack", "howl"], 1, true, false, false)}
	_assert(u1["intent"] == "howl" and u2["intent"] == "stun",
		"同波同回合：两敌意图各自独立记录（u1=howl / u2=stun）")
	u1["intent"] = "attack"
	_assert(u2["intent"] == "stun", "改 u1 意图不影响 u2")

# ---------- 攻击结算来源分解 ----------
func _test_attack_resolution_sources() -> void:
	print("STEP: enemy attack resolution with source breakdown")
	var base := {"attack": 6, "spirit_mult": 1.0}
	var r1: Dictionary = BattleRulesV4.resolve_enemy_attack(base)
	_assert(r1["damage"] == 6 and (r1["lines"] as Array).is_empty(), "无修正：6 伤害无飘字")
	var r2: Dictionary = BattleRulesV4.resolve_enemy_attack(
		{"attack": 6, "spirit_mult": 1.3, "obsession": true})
	_assert(r2["damage"] == int(round(6 * 1.3 * 1.5)), "执念暴怒 ×1.5 与灵气档叠乘")
	var r3: Dictionary = BattleRulesV4.resolve_enemy_attack(
		{"attack": 6, "spirit_mult": 1.0, "intent": "berserk"})
	_assert(r3["damage"] == 9, "暴走 ×1.5")
	var r4: Dictionary = BattleRulesV4.resolve_enemy_attack(
		{"attack": 6, "spirit_mult": 1.0, "intent": "pounce", "pounce_mult": 1.8})
	_assert(r4["damage"] == int(round(6 * 1.8)), "猛扑 ×1.8")
	var r5: Dictionary = BattleRulesV4.resolve_enemy_attack(
		{"attack": 6, "spirit_mult": 1.0, "intent": "attack", "has_burning": true,
			"fear_attack_mult": 0.5})
	_assert(r5["damage"] == 3, "遇火恐惧 ×0.5")
	var r6: Dictionary = BattleRulesV4.resolve_enemy_attack(
		{"attack": 6, "spirit_mult": 1.0, "intent": "stun"})
	_assert(r6["damage"] == 0, "眩晕不出手")
	var r7: Dictionary = BattleRulesV4.resolve_enemy_attack(
		{"attack": 6, "spirit_mult": 1.0, "intent": "stun", "stun_skip": true})
	_assert(r7["damage"] == 6 and r7["stun_immune"], "stun_skip：免疫眩晕并按普攻结算")
	# 同一来源只乘一次：obsession 与 berserk intent 同时成立不双计 1.5
	var r8: Dictionary = BattleRulesV4.resolve_enemy_attack(
		{"attack": 8, "spirit_mult": 1.0, "obsession": true, "intent": "berserk"})
	_assert(r8["damage"] == 12, "执念与暴走同源不双乘（8×1.5=12）")

# ---------- 失败优先 ----------
func _test_fail_priority() -> void:
	print("STEP: fail priority (GDD §6.2.4)")
	_assert(BattleRulesV4.evaluate_battle(0, 0) == "lose", "同灭：失败优先")
	_assert(BattleRulesV4.evaluate_battle(0, 3) == "lose", "玩家 0 血即败")
	_assert(BattleRulesV4.evaluate_battle(5, 0) == "win", "敌全灭即胜")
	_assert(BattleRulesV4.evaluate_battle(5, 2) == "ongoing", "双方存活继续")

# ---------- 目标校验：错误目标不扣费的前置判定 ----------
func _test_target_validation() -> void:
	print("STEP: target validation (slot eligibility)")
	_assert(not BattleRulesV4.can_afford({"cost": 2}, 1), "AP 不足不可打出")
	_assert(BattleRulesV4.can_afford({"cost": 2}, 2), "AP 足够可打出")
	_assert(BattleRulesV4.slot_targetable({"slot_state": "sealed"}, {"state": "idle", "seal_point": true}),
		"结界符可贴空闲阵眼")
	_assert(not BattleRulesV4.slot_targetable({"slot_state": "sealed"}, {"state": "idle", "seal_point": false}),
		"结界符不能贴非阵眼")
	_assert(BattleRulesV4.slot_targetable({"slot_state": "ringing"}, {"state": "burning", "seal_point": false}),
		"鸣钟可敲燃烧槽（惊焰）")
	_assert(not BattleRulesV4.slot_targetable({"slot_state": "burning"}, {"state": "burning", "seal_point": false}),
		"燃烧卡不能重复点燃燃烧槽")
	_assert(not BattleRulesV4.slot_targetable({"slot_state": "sealed"}, {"state": "targetable", "seal_point": false}),
		"结界符不能贴在「可重新提名」的非阵眼槽")
	_assert(BattleRulesV4.slot_targetable({"slot_state": "burning"}, {"state": "idle", "seal_point": false}),
		"燃烧卡可点空闲槽")

# ---------- B 期：护盾 / 标记 / 整理（GDD §5.3、§5.6） ----------
func _test_phase_b_mechanics() -> void:
	print("STEP: B期 护盾/标记/整理/效果解析 (GDD §5.3 §5.6)")
	# 护盾：先于生命承伤
	var r1: Dictionary = BattleRulesV4.apply_shield(30, 4, 3)
	_assert(r1["hp"] == 30 and r1["shield"] == 1 and r1["absorbed"] == 3,
		"护盾足够：全额吸收，生命不掉")
	var r2: Dictionary = BattleRulesV4.apply_shield(30, 4, 7)
	_assert(r2["hp"] == 27 and r2["shield"] == 0 and r2["through"] == 3,
		"护盾不足：吸收 4 穿透 3")
	var r3: Dictionary = BattleRulesV4.apply_shield(5, 0, 9)
	_assert(r3["hp"] == 0, "无护盾：直接扣血可致死")
	# 标记：上限 3
	_assert(BattleRulesV4.add_marks(2, 1) == 3, "标记叠至 3 层")
	_assert(BattleRulesV4.add_marks(3, 1) == 3, "标记不超 3 层")
	_assert(BattleRulesV4.add_marks(1, -1) == 0, "消耗标记可清零")
	# 追符斩：有标记消耗 1 层 +5；无标记不消耗不加成
	var c1: Dictionary = BattleRulesV4.consume_marks_for_bonus(6, 2, 1, 5)
	_assert(c1["power"] == 11 and c1["consumed"] == 1, "有标记：6+5=11 消耗 1 层")
	var c2: Dictionary = BattleRulesV4.consume_marks_for_bonus(6, 0, 1, 5)
	_assert(c2["power"] == 6 and c2["consumed"] == 0, "无标记：只结算基础 6")
	var c3: Dictionary = BattleRulesV4.consume_marks_for_bonus(6, 1, 2, 5)
	_assert(c3["power"] == 6 and c3["consumed"] == 0, "标记不足 need：不半消耗")
	# 整理：每回合一次 / 1 灵墨 / 无其他可抽不可用
	var t1: Dictionary = BattleRulesV4.can_tidy({"ap": 2, "used": false, "hand": 3, "deck": 5, "discard": 2})
	_assert(t1["ok"], "灵墨足未用过：可整理")
	var t2: Dictionary = BattleRulesV4.can_tidy({"ap": 2, "used": true, "hand": 3, "deck": 5, "discard": 2})
	_assert(not t2["ok"], "本回合已整理：不可用")
	var t3: Dictionary = BattleRulesV4.can_tidy({"ap": 0, "used": false, "hand": 3, "deck": 5, "discard": 2})
	_assert(not t3["ok"], "灵墨 0：不可用不扣费")
	var t4: Dictionary = BattleRulesV4.can_tidy({"ap": 2, "used": false, "hand": 3, "deck": 0, "discard": 0})
	_assert(not t4["ok"], "抽牌堆弃牌堆皆空：不可用（防抽回暂存张）")
	var t5: Dictionary = BattleRulesV4.can_tidy({"ap": 2, "used": false, "hand": 1, "deck": 0, "discard": 0})
	_assert(not t5["ok"], "手牌仅 1 张且两堆空：整理等于抽回自身，禁止")
	# 效果解析归一化
	var fx: Dictionary = BattleRulesV4.parse_effects(
		{"effects": {"shield": 4, "mark": 1, "spirit": -2}})
	_assert(fx["shield"] == 4 and fx["mark"] == 1 and fx["spirit"] == -2 and fx["draw"] == 0,
		"effects 解析：登记键取值、缺省键为 0")
	var fx2: Dictionary = BattleRulesV4.parse_effects({})
	_assert(fx2["shield"] == 0 and fx2["consume_mark"] == 0, "无 effects 卡全 0（旧卡兼容）")

# ---------- B 期：构筑合法性（GDD §5.2） ----------
func _test_phase_b_deck_building() -> void:
	print("STEP: B期 构筑合法性/费用分布 (GDD §5.2)")
	# 最小卡库：主战卡 a1/a2、支援卡 s1、通用卡 g1、独特卡 u1（tags unique）
	var lib := {
		"a1": {"id": "a1", "name": "主甲", "cost": 1, "owner": "rinne"},
		"a2": {"id": "a2", "name": "主乙", "cost": 2, "owner": "rinne"},
		"a3": {"id": "a3", "name": "主丙", "cost": 1, "owner": "rinne"},
		"s1": {"id": "s1", "name": "援甲", "cost": 1, "owner": "mint"},
		"s2": {"id": "s2", "name": "援乙", "cost": 2, "owner": "mint"},
		"s3": {"id": "s3", "name": "援丙", "cost": 1, "owner": "mint"},
		"s4": {"id": "s4", "name": "援丁", "cost": 2, "owner": "mint"},
		"g1": {"id": "g1", "name": "通甲", "cost": 3, "owner": "generic"},
		"g2": {"id": "g2", "name": "通乙", "cost": 3, "owner": "generic"},
		"g3": {"id": "g3", "name": "通丙", "cost": 4, "owner": "generic"},
		"u1": {"id": "u1", "name": "独一", "cost": 2, "owner": "rinne",
			"tags": ["unique"]},
	}
	var d16: Array = []
	for i in 2:
		d16.append("a1")
	for i in 2:
		d16.append("a2")
	for i in 2:
		d16.append("a3") # 主战合计 6
	for i in 2:
		d16.append("s1")
	for i in 2:
		d16.append("s2") # 支援合计 4
	for i in 2:
		d16.append("g1")
	for i in 2:
		d16.append("g2")
	for i in 2:
		d16.append("g3") # 通用合计 6 = 16
	_assert((BattleRulesV4.validate_deck(d16, "rinne", "mint", lib) as Array).is_empty(),
		"16 张/主战 6/支援 4：合法")
	# 数量不是 16
	var d15: Array = d16.duplicate()
	d15.pop_back()
	var e15: Array = BattleRulesV4.validate_deck(d15, "rinne", "mint", lib)
	_assert(not e15.is_empty(), "15 张：不合法")
	# 主战不足 6（其余全部合规，只触发主战一条）
	var dmain: Array = []
	for i in 2:
		dmain.append("a1")
	for i in 2:
		dmain.append("a2")
	dmain.append("a3") # 主战 5
	for i in 2:
		dmain.append("s1")
	for i in 2:
		dmain.append("s2")
	dmain.append("s3") # 支援 5
	for i in 2:
		dmain.append("g1")
	for i in 2:
		dmain.append("g2")
	for i in 2:
		dmain.append("g3") # 通用 6 = 16
	var emain: Array = BattleRulesV4.validate_deck(dmain, "rinne", "mint", lib)
	_assert(emain.size() == 1 and String(emain[0]).contains("主战"),
		"主战仅 5：唯一错误是主战不足（其余合规）")
	# 支援超 6（其余合规，只触发支援一条）
	var dsup: Array = []
	for i in 2:
		dsup.append("a1")
	for i in 2:
		dsup.append("a2")
	for i in 2:
		dsup.append("a3")
	dsup.append("u1") # 主战 7（u1 独特 1 张，仍合规）
	for i in 2:
		dsup.append("s1")
	for i in 2:
		dsup.append("s2")
	for i in 2:
		dsup.append("s3")
	dsup.append("s4") # 支援 7
	for i in 2:
		dsup.append("g1") # 通用 2 = 16
	var esup: Array = BattleRulesV4.validate_deck(dsup, "rinne", "mint", lib)
	_assert(esup.size() == 1 and String(esup[0]).contains("支援"),
		"支援 7 张超上限：唯一错误是支援超限")
	# 同一卡最多 2 张
	var ddup: Array = []
	for i in 16:
		ddup.append("a1")
	var edup: Array = BattleRulesV4.validate_deck(ddup, "rinne", "mint", lib)
	_assert(not edup.is_empty(), "同一卡 16 张：超重复上限")
	# 升级分支合计占同一上限（base_id 归并）
	var lib2: Dictionary = lib.duplicate()
	lib2["a1b"] = {"id": "a1b", "name": "主甲·改", "cost": 1, "owner": "rinne",
		"base_id": "a1"}
	var dbr: Array = ["a1", "a1", "a1b"] # base a1 合计 3
	_assert(not (BattleRulesV4.validate_deck(dbr, "rinne", "mint", lib2) as Array).is_empty(),
		"升级分支与本体合计 3 张：仍受 2 张上限约束")
	# 独特卡最多 1
	var du: Array = ["u1", "u1"]
	for i in 14:
		du.append("a1")
	_assert(not (BattleRulesV4.validate_deck(du, "rinne", "mint", lib) as Array).is_empty(),
		"独特卡 2 张：不合法")
	# 未知卡
	var dunknown: Array = d16.duplicate()
	dunknown[0] = "ghost"
	_assert(not (BattleRulesV4.validate_deck(dunknown, "rinne", "mint", lib) as Array).is_empty(),
		"含未知卡 id：不合法")
	# 费用分布
	var curve: Dictionary = BattleRulesV4.deck_cost_curve(d16, lib)
	_assert(int(curve.get("1", 0)) == 6 and int(curve.get("2", 0)) == 4
		and int(curve.get("3", 0)) == 4 and int(curve.get("4", 0)) == 2,
		"费用分布：1/2/3/4 灵墨 = 6/4/4/2 张")
	# 卡库扫描：真实 battles 目录 10 卡 + 预组合法性
	var real_lib: Dictionary = CardLibraryV4.load_library()
	_assert(real_lib.size() >= 10, "卡库扫描：>=10 种卡（实得 %d）" % real_lib.size())
	var preset: Array = [
		"slash", "slash", "guard", "guard", "chase_slash", "chase_slash",
		"ignite", "ignite", "bell", "bell", "seal", "seal", "seal2", "seal2",
		"amulet", "amulet"]
	_assert((BattleRulesV4.validate_deck(preset, "rinne", "mint", real_lib) as Array).is_empty(),
		"预组 16 张对真实卡库合法（主战 6/支援 2/通用 8）")
	var resolved: Array = CardLibraryV4.resolve_ids(preset, real_lib)
	_assert(resolved.size() == 16, "预组 id 全量解析为卡定义")

# ---------- B 期：器物效果（GDD §7：明确触发上限） ----------
func _test_phase_b_artifacts() -> void:
	print("STEP: B期 器物效果取值/费用折扣 (GDD §7)")
	var inkstone := {"id": "inkstone", "name": "聚灵砚",
		"effect": {"first_turn_ap": 1, "shield_bonus": 99}, "limit": 1}
	# 上限内取值 / 达到上限归零 / 无该键归零 / 空器物归零
	_assert(BattleRulesV4.artifact_value(inkstone, "first_turn_ap", 0) == 1,
		"上限内：first_turn_ap 取 1")
	_assert(BattleRulesV4.artifact_value(inkstone, "first_turn_ap", 1) == 0,
		"已达上限（1/1）：归零")
	_assert(BattleRulesV4.artifact_value(inkstone, "seal_cost_discount", 0) == 0,
		"器物无该效果键：取 0")
	_assert(BattleRulesV4.artifact_value({}, "first_turn_ap", 0) == 0,
		"空器物（不带）：恒 0")
	# 高上限器物多次触发
	var ward := {"id": "ward", "name": "守心佩", "effect": {"shield_bonus": 2}, "limit": 99}
	_assert(BattleRulesV4.artifact_value(ward, "shield_bonus", 3) == 2,
		"limit 99：第 4 次仍生效")
	# 结界符费用折扣：下限 1 防免费
	_assert(BattleRulesV4.artifact_seal_cost(2, 1) == 1, "2 灵墨结界符 -1 = 1")
	_assert(BattleRulesV4.artifact_seal_cost(1, 1) == 1, "1 灵墨结界符 -1 钳到下限 1")
	_assert(BattleRulesV4.artifact_seal_cost(2, 0) == 2, "无折扣原样返回")

# ---------- C 期：回合仪式（GDD §八《回廊守灯》） ----------
func _test_phase_c_ritual() -> void:
	print("STEP: C期 仪式稳定度/目标评估/前提链 (GDD §8.3)")
	# 稳定度衰减与钳 0
	var d1: Dictionary = BattleRulesV4.ritual_decay(4, 1)
	_assert(d1["lamp"] == 3 and not d1["lamp_out"], "稳定度 4-1=3，灯未灭")
	var d2: Dictionary = BattleRulesV4.ritual_decay(1, 1)
	_assert(d2["lamp"] == 0 and d2["lamp_out"], "稳定度 1-1=0，灯灭标记")
	var d3: Dictionary = BattleRulesV4.ritual_decay(0, 1)
	_assert(d3["lamp"] == 0, "稳定度已 0 不扣成负数")
	# 添灯钳上限
	_assert(BattleRulesV4.ritual_add_fuel(5, 2, 6) == 6, "添灯 5+2 钳到上限 6")
	_assert(BattleRulesV4.ritual_add_fuel(2, 3, 6) == 5, "灯油 2+3=5 未超上限")
	# 目标评估：回合未满继续；灯灭立即失败；主战倒下立即失败
	var objs := {
		"identify": {"name": "辨认来者", "done": true},
		"place": {"name": "安放旧物", "done": true},
		"guide": {"name": "引路", "done": true},
	}
	var e1: Dictionary = BattleRulesV4.ritual_evaluate(3, 30, objs, 3, 6)
	_assert(e1["result"] == "ongoing", "第 3 回合全完成也要撑到第 6 回合结算")
	var e2: Dictionary = BattleRulesV4.ritual_evaluate(3, 30, objs, 6, 6)
	_assert(e2["result"] == "win", "第 6 回合结束：灯亮+存活+目标全完成=成功")
	var e3: Dictionary = BattleRulesV4.ritual_evaluate(0, 30, objs, 4, 6)
	_assert(e3["result"] == "lose" and (e3["missing"] as Array).has("引灯熄灭"),
		"灯灭：立即失败并指出原因")
	var e4: Dictionary = BattleRulesV4.ritual_evaluate(3, 0, objs, 4, 6)
	_assert(e4["result"] == "lose", "主战倒下：立即失败")
	var objs_miss := {
		"identify": {"name": "辨认来者", "done": true},
		"place": {"name": "安放旧物", "done": false},
		"guide": {"name": "引路", "done": false},
	}
	var e5: Dictionary = BattleRulesV4.ritual_evaluate(3, 30, objs_miss, 6, 6)
	_assert(e5["result"] == "lose" and (e5["missing"] as Array).size() == 2,
		"第 6 回合缺两项：失败并列出缺项（安放旧物/引路）")
	# 前提链 + 回合窗口
	var identify := {"id": "identify", "min_turn": 3, "requires": []}
	var place := {"id": "place", "requires": ["identify"]}
	var guide := {"id": "guide", "min_turn": 5, "requires": ["place"]}
	var a1: Dictionary = BattleRulesV4.ritual_objective_available(identify, {"turn": 2, "done": {}})
	_assert(not a1["ok"], "第 2 回合：辨认时机未到")
	var a2: Dictionary = BattleRulesV4.ritual_objective_available(identify, {"turn": 3, "done": {}})
	_assert(a2["ok"], "第 3 回合（第三次叩门后）：可辨认")
	var a3: Dictionary = BattleRulesV4.ritual_objective_available(place, {"turn": 3, "done": {}})
	_assert(not a3["ok"] and String(a3["reason"]).contains("需要先完成"),
		"未辨认先安放：拒绝并说明前提")
	var a4: Dictionary = BattleRulesV4.ritual_objective_available(place,
		{"turn": 3, "done": {"identify": true}})
	_assert(a4["ok"], "已辨认：可安放")
	var a5: Dictionary = BattleRulesV4.ritual_objective_available(guide,
		{"turn": 4, "done": {"identify": true, "place": true}})
	_assert(not a5["ok"], "第 4 回合：引路时机未到（须第 5 回合起）")
	var a6: Dictionary = BattleRulesV4.ritual_objective_available(guide,
		{"turn": 5, "done": {"identify": true, "place": true}})
	_assert(a6["ok"], "第 5 回合且已安放：可引路")

# ---------- D期 成长存档：解锁规则与奖励授予（GDD §9.1 / §5.2） ----------
func _test_phase_d_progress_save() -> void:
	print("STEP: D期 进度存档：解锁判定/结案授予/幂等 (GDD §9.1)")
	# 测前清理，避免污染玩家真实进度；测后再清一次
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ProgressSaveV4.PATH))
	# 解锁规则：unlock 空或 start → 初始可用；其余须已解锁
	_assert(ProgressSaveV4.is_card_unlocked({"id": "a", "unlock": ""}), "unlock 空：初始可用")
	_assert(ProgressSaveV4.is_card_unlocked({"id": "b", "unlock": "start"}), "unlock=start：初始可用")
	_assert(not ProgressSaveV4.is_card_unlocked({"id": "c", "unlock": "night_patrol"}),
		"unlock=案件 id 且无档：未解锁")
	_assert(not ProgressSaveV4.is_artifact_unlocked({"id": "x", "unlock": "night_patrol"}),
		"器物同规则：未解锁")
	# 授予：结案后对应卡/器物解锁 + 案件登记
	var g1: Dictionary = ProgressSaveV4.grant("night_patrol",
		{"cards": ["soul_pin", "soul_candle"], "artifacts": ["ash_sachet"]})
	_assert((g1["cards"] as Array).size() == 2 and (g1["artifacts"] as Array).size() == 1,
		"结案授予：2 卡 + 1 器物新解锁")
	_assert(ProgressSaveV4.is_card_unlocked({"id": "soul_pin", "unlock": "night_patrol"}),
		"授予后可按案件 id 解锁判定")
	_assert(ProgressSaveV4.is_card_unlocked({"id": "soul_pin", "unlock": "soul_pin"}),
		"授予后也可按卡 id 自身解锁判定")
	_assert(ProgressSaveV4.is_case_done("night_patrol"), "案件已登记结案")
	_assert(not ProgressSaveV4.is_case_done("other_case"), "其他案件未结案")
	# 幂等：重复授予不重复添加
	var g2: Dictionary = ProgressSaveV4.grant("night_patrol",
		{"cards": ["soul_pin"], "artifacts": ["ash_sachet"]})
	_assert((g2["cards"] as Array).is_empty() and (g2["artifacts"] as Array).is_empty(),
		"重复授予：无新增（幂等）")
	var p: Dictionary = ProgressSaveV4.load_progress()
	_assert((p["unlocked_cards"] as Array).count("soul_pin") == 1, "卡 id 在档中只出现一次")
	# 测后清理，恢复「无进度」初始态
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ProgressSaveV4.PATH))
	_assert(not ProgressSaveV4.is_case_done("night_patrol"), "清理后回到无档初始态")
