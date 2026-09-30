# 关卡流程单测(GDD §八):三阶段推进/侦查巡逻/惊醒灵气/Boss 逃脱/教学触发器
# 用法: Godot --path <项目> --script res://tools/test_level_flow.gd
extends SceneTree

var _escape_events: Array = []
var _failed: bool = false

var state: GameState
var ai = null
var director = null   # LevelDirector(动态 load,引用 EventBus)

func _initialize() -> void:
	Card.load_cards()
	UnitFactory.load_templates()
	StatusEffectManager.load_defs()
	state = GameState.new()
	state.init_battle(state.player_spawn_defs, state.enemy_spawn_defs)
	var bus = root.get_node_or_null("EventBus")
	_assert(bus != null, "EventBus autoload 可用")
	bus.on("boss:escaped", func(d): _escape_events.append(d))
	var ai_class: GDScript = load("res://scripts/core/ai_controller.gd")
	ai = ai_class.new(state.map, state.all_units)
	var ld_class: GDScript = load("res://scripts/core/level_director.gd")
	director = ld_class.new(state)

	_test_stage_machine()
	_test_recon_patrol()
	_test_alert_spirit_gain()
	_test_escape_config()
	_test_boss_escape_plan()
	_test_boss_escaped_report()
	_test_tutorial_triggers()

	if _failed:
		printerr("TEST_LEVEL_FLOW: 存在失败断言")
		quit(1)
	else:
		print("TEST_LEVEL_FLOW: 全部断言通过")
		quit(0)

func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  [PASS] " + msg)
	else:
		_failed = true
		printerr("  [FAIL] " + msg)

func _ctx(extra: Dictionary = {}) -> Dictionary:
	var c = {
		"map": state.map,
		"players": state.get_alive_units("player"),
		"all_units": state.all_units,
		"noise_events": [],
		"spirit_density": state.spirit_density,
		"turn": 1,
		"level_stage": state.level_stage,
	}
	for k in extra:
		c[k] = extra[k]
	return c

func _effigy() -> Unit:
	for e in state.enemies:
		if e.template_id == "paper_effigy" and e.is_alive:
			return e
	return null

func _boss() -> Unit:
	for e in state.enemies:
		if e.template_id == "coffin_lord" and e.is_alive:
			return e
	return null

# ---- 1. 三阶段阶段机:回合边界 ----
func _test_stage_machine() -> void:
	_assert(director.stage_id_for_turn(1) == "recon", "回合 1 → 侦查")
	_assert(director.stage_id_for_turn(3) == "recon", "回合 3 → 侦查")
	_assert(director.stage_id_for_turn(4) == "alert", "回合 4 → 惊醒")
	_assert(director.stage_id_for_turn(6) == "alert", "回合 6 → 惊醒")
	_assert(director.stage_id_for_turn(7) == "decisive", "回合 7 → 决战")
	_assert(director.stage_id_for_turn(15) == "decisive", "回合 15 → 决战")

# ---- 2. 侦查期:纸人强制巡逻不追击;决战期恢复追击 ----
func _test_recon_patrol() -> void:
	var e = _effigy()
	_assert(e != null, "找到纸人")
	# 隔离恐惧干扰(出生点附近有 seal 格)
	e.ai_profile = e.ai_profile.duplicate()
	e.ai_profile["fearRange"] = 0
	# 玩家放进纸人视野(sightRange 5)
	var player = state.get_alive_units("player")[0]
	state.map.set_occupant(player.position, null)
	player.position = e.position + Vector2i(0, 2)
	state.map.set_occupant(player.position, player.id)
	e.start_turn()
	state.level_stage = "recon"
	var plan: Dictionary = ai.generate_enemy_plan(e, _ctx())
	_assert(str(plan.get("state", "")) == "patrol", "侦查期:玩家在视野内仍巡逻(reason=%s)" % str(plan.get("reason", "")))
	e.start_turn()
	state.level_stage = "decisive"
	var plan2: Dictionary = ai.generate_enemy_plan(e, _ctx())
	_assert(str(plan2.get("state", "")) != "patrol", "决战期:视野内玩家 → 追击/攻击(state=%s)" % str(plan2.get("state", "")))
	# 清理
	state.map.set_occupant(player.position, null)
	player.position = Vector2i(0, 7)
	state.map.set_occupant(player.position, player.id)

# ---- 3. 惊醒期:on_player_turn_start 灵气增益与阶段切换标记 ----
func _test_alert_spirit_gain() -> void:
	var d2 = load("res://scripts/core/level_director.gd").new(state)
	var r1: Dictionary = d2.on_player_turn_start(1)
	_assert(not bool(r1.get("changed", true)), "回合 1 初次进入不算切换")
	_assert(int(r1.get("spirit_gain", -1)) == 0, "侦查期无灵气增益")
	var r4: Dictionary = d2.on_player_turn_start(4)
	_assert(bool(r4.get("changed", false)) and str(r4.get("from", "")) == "recon" and str(r4.get("stage", "")) == "alert", "回合 4 切换 recon→alert")
	_assert(int(r4.get("spirit_gain", 0)) == 2, "惊醒期灵气 +2/回合")
	var r5: Dictionary = d2.on_player_turn_start(5)
	_assert(not bool(r5.get("changed", true)) and int(r5.get("spirit_gain", 0)) == 2, "回合 5 同阶段仍 +2 不重复切换")
	var r7: Dictionary = d2.on_player_turn_start(7)
	_assert(bool(r7.get("changed", false)) and str(r7.get("stage", "")) == "decisive", "回合 7 切换 alert→decisive")
	_assert(int(r7.get("spirit_gain", -1)) == 0, "决战期无灵气增益")

# ---- 4. 逃脱配置:门格/激活条件/倒计时 ----
func _test_escape_config() -> void:
	var doors = director.door_cells()
	_assert(doors.has(Vector2i(0, 0)) and doors.has(Vector2i(9, 0)), "门格识别 (0,0) 与 (9,0)")
	_assert(director.escape_active(9, 2), "回合 9 + 灵气 2 → 逃脱激活")
	_assert(not director.escape_active(9, 7), "灵气 ≥6(封印威胁)→ 不激活")
	_assert(not director.escape_active(6, 2), "回合 6 未到 startTurn → 不激活")
	_assert(director.escape_countdown(7) == 2, "回合 7 倒计时 = 2")
	_assert(director.escape_countdown(9) <= 0, "回合 9 倒计时 ≤0(已开始)")
	_assert(director.nearest_door(Vector2i(5, 3)) == Vector2i(9, 0), "棺材主 (5,3) 最近门 = (9,0)")

# ---- 5. Boss 逃脱计划:激活时向门移动 ----
func _test_boss_escape_plan() -> void:
	var boss = _boss()
	_assert(boss != null, "找到棺材主")
	boss.ai_profile = boss.ai_profile.duplicate()
	boss.ai_profile["fearRange"] = 0
	boss.start_turn()
	var door = director.nearest_door(boss.position)
	var ctx_e = _ctx({"level_escape": {"active": true, "door": door}, "turn": 9})
	state.level_stage = "decisive"
	var plan: Dictionary = ai.generate_enemy_plan(boss, ctx_e)
	_assert(str(plan.get("state", "")) == "escape", "逃脱激活 → escape 计划(state=%s)" % str(plan.get("state", "")))
	var has_escape_move := false
	for a in plan.get("actions", []):
		if a.get("type") == "move" and str(a.get("intent_style", "")) == "escape":
			has_escape_move = true
	_assert(has_escape_move, "逃脱计划含 escape 移动动作")
	# 未激活时不逃:回退到正常计划
	boss.start_turn()
	var ctx_n = _ctx({"level_escape": {"active": false, "door": door}, "turn": 9})
	var plan2: Dictionary = ai.generate_enemy_plan(boss, ctx_n)
	_assert(str(plan2.get("state", "")) != "escape", "未激活 → 非 escape 计划")

# ---- 6. Boss 到门格 → 失败广播 + 文案 + is_battle_over ----
func _test_boss_escaped_report() -> void:
	var boss = _boss()
	_escape_events.clear()
	_assert(not director.report_boss_escaped(), "Boss 不在门格 → 不触发逃脱")
	state.map.set_occupant(boss.position, null)
	boss.position = Vector2i(0, 0)
	state.map.set_occupant(boss.position, boss.id)
	_assert(director.report_boss_escaped(), "Boss 到门格 → 触发逃脱")
	_assert(state.lose_reason == "escaped", "lose_reason = escaped")
	_assert(state.is_battle_over() == "lost", "is_battle_over → lost(lose_reason 优先)")
	_assert(_escape_events.size() == 1, "广播 boss:escaped")
	if _escape_events.size() > 0:
		var reason = str(_escape_events[0].get("reason_text", ""))
		_assert(reason.find("逃脱") >= 0, "失败文案含「逃脱」:%s" % reason)
	# 清理
	state.map.set_occupant(boss.position, null)
	boss.position = Vector2i(5, 3)
	state.map.set_occupant(boss.position, boss.id)
	state.lose_reason = ""

# ---- 7. 教学触发器:回合/事件/灵气 + 一次性 ----
func _test_tutorial_triggers() -> void:
	var tut = load("res://scripts/core/tutorial_director.gd").new()
	var t1 = tut.check_turn(1)
	_assert(t1.size() == 1 and str(t1[0].get("id", "")) == "move_ap", "回合 1 → 移动教学")
	_assert(tut.check_turn(1).is_empty(), "同一提示不重复(一次性)")
	_assert(tut.check_turn(2).size() == 1, "回合 2 → 推物体教学")
	_assert(tut.check_turn(3).size() == 1, "回合 3 → 铃铛教学")
	_assert(tut.check_turn(4).is_empty(), "回合 4 无回合触发提示")
	var ev1 = tut.check_event("object:pushed", {"object_id": "brazier"})
	_assert(ev1.size() == 1 and str(ev1[0].get("id", "")) == "fire_spread", "首次推物体 → 火焰蔓延教学")
	_assert(tut.check_event("object:pushed", {"object_id": "brazier"}).is_empty(), "事件提示不重复")
	_assert(tut.check_spirit(3).is_empty(), "灵气 3 未达阈值")
	var sp1 = tut.check_spirit(4)
	_assert(sp1.size() == 1 and str(sp1[0].get("id", "")) == "seal_hint", "灵气 ≥4 → 封印教学")
	_assert(tut.check_spirit(6).is_empty(), "灵气提示不重复")
	_assert(tut.shown_count() == 5, "5 条提示全部触发过")
