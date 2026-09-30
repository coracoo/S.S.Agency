# 封印击杀判定 + 灵气密度效果 单测:无头跑 SceneTree
# 验证:四条件判定、AP 扣除、seal:activated 广播、即死生效、灵气 tier 移速/伤害修正
# 用法: Godot --path <项目> --script res://tools/test_seal.gd
extends SceneTree

var _seal_events: Array = []
var _died_events: Array = []
var _failed: bool = false

func _initialize() -> void:
	Card.load_cards()
	UnitFactory.load_templates()
	StatusEffectManager.load_defs()
	var state := GameState.new()
	state.init_battle(state.player_spawn_defs, state.enemy_spawn_defs)
	print("STEP: battle inited, density=", state.spirit_density)
	state.current_turn = "player"
	state.team_ap = 6
	# 同 test_pull:spirit_system.gd 引用 EventBus,必须运行时动态 load
	var spirit_class: GDScript = load("res://scripts/core/spirit_system.gd")
	var spirit = spirit_class.new(state)
	spirit.track_enemies(state.enemies)
	var bus = root.get_node_or_null("EventBus")
	_assert(bus != null, "EventBus autoload 可用")
	bus.on("seal:activated", func(data): _seal_events.append(data))
	state.unit_died.connect(func(uid): _died_events.append(uid))
	print("STEP: spirit system created, events subscribed")

	var boss: Unit = null
	var paper: Unit = null
	for e in state.enemies:
		if e.template_id == "coffin_lord":
			boss = e
		elif e.template_id == "paper_effigy" and paper == null:
			paper = e
	_assert(boss != null and paper != null, "找到棺材主与纸人")
	print("STEP: boss=", boss.id, " pos=", boss.position, " str=", boss.stats.strength)

	# ---- 灵气 tier 效果(移速/伤害修正,GDD §5.6) ----
	# 初始 density=2 → weak:纸人(weak 档 scope=minion)移速 3-1=2,伤害倍率 1.0
	_assert(spirit.get_tier() == "weak", "初始 tier 为 weak(density=2)")
	_assert(paper.stats.move_range == 2, "weak:纸人移速 -1(3→2)")
	_assert(paper.stats.strength == 4, "weak:纸人伤害不变")
	# 提升到 6 → reinforced:伤害 ×1.3(4→5),移速恢复
	spirit.modify_density(4, "test")
	_assert(state.spirit_density == 6, "灵气提升到 6")
	_assert(spirit.get_tier() == "reinforced", "tier 变为 reinforced")
	_assert(paper.stats.strength == 5, "reinforced:纸人伤害 ×1.3(4→5)")
	_assert(paper.stats.move_range == 3, "reinforced:纸人移速恢复 3")
	_assert(boss.stats.strength == 10, "reinforced:棺材主伤害 ×1.3(8→10)")
	# 提升到 8 → rage:伤害 ×1.5(4→6 / 8→12),简易版代替额外行动
	spirit.modify_density(2, "test")
	_assert(spirit.get_tier() == "rage", "tier 变为 rage")
	_assert(paper.stats.strength == 6, "rage:纸人伤害 ×1.5(4→6)")
	_assert(boss.stats.strength == 12, "rage:棺材主伤害 ×1.5(8→12)")
	# 降回 6 → reinforced,强度回落
	spirit.modify_density(-2, "test")
	_assert(paper.stats.strength == 5, "降回 reinforced:纸人伤害回落 5")

	# ---- 封印判定(GDD §5.5 四条件) ----
	# 条件未齐:无阵眼
	_assert(not spirit.check_seal_activation(boss), "无阵眼时不可封印")
	# 摆 3 个阵眼:seal 格 (1,3)/(3,0)/(3,6) 放 talisman(直接写地图,不走事件避免灵气 -1)
	for p in [Vector2i(1, 3), Vector2i(3, 0), Vector2i(3, 6)]:
		state.map.add_effect(p.x, p.y, "talisman")
	_assert(spirit.get_activated_seal_points().size() == 3, "阵眼激活 3 个")
	# boss 在 (5,3):不在三角阵区内也不相邻 → 仍不可封印
	_assert(not spirit.check_seal_activation(boss), "目标不在阵区时不可封印")
	var st: Dictionary = spirit.get_seal_status(boss)
	_assert(int(st.get("met", 0)) == 3, "条件达成 3/4(阵眼+灵气+灵体,缺阵区)")
	# 把 boss 移到 (2,3):与阵眼 (1,3) 相邻
	state.map.set_occupant(boss.position, null)
	boss.position = Vector2i(2, 3)
	state.map.set_occupant(boss.position, boss.id)
	_assert(spirit.check_seal_activation(boss), "四条件齐备可封印")
	st = spirit.get_seal_status(boss)
	_assert(int(st.get("met", 0)) == 4, "条件达成 4/4")
	# 多边形判定:补齐 6 阵眼,(5,3) 在六边形包围区域内
	for p in [Vector2i(6, 0), Vector2i(9, 3), Vector2i(6, 6)]:
		state.map.add_effect(p.x, p.y, "talisman")
	var six_points: Array = spirit.get_activated_seal_points()
	_assert(six_points.size() == 6, "阵眼激活 6 个")
	_assert(spirit.is_target_in_seal_region(Vector2i(5, 3), six_points), "(5,3) 在六阵眼多边形内")
	_assert(not spirit.is_target_in_seal_region(Vector2i(13, 9), six_points), "(13,9) 在多边形外")

	# ---- 执行封印:AP + 事件 + 即死 ----
	var ap_before: int = state.team_ap
	_assert(state.spend_ap(1), "封印扣 1 AP")
	_assert(spirit.activate_seal(boss), "activate_seal 返回 true")
	_assert(not boss.is_alive, "目标立即死亡")
	_assert(state.map.get_occupant_id(Vector2i(2, 3)) == "", "目标占位已清空")
	_assert(state.team_ap == ap_before - 1, "AP 扣除 1")
	_assert(_seal_events.size() == 1, "seal:activated 广播 1 次")
	if _seal_events.size() == 1:
		var ev: Dictionary = _seal_events[0]
		_assert(ev.get("method", "") == "seal", "事件 method=seal")
		_assert(ev.get("target_id", "") == boss.id, "事件 target_id 正确")
		_assert(ev.get("target_pos") == Vector2i(2, 3), "事件 target_pos 正确")
		_assert((ev.get("points", []) as Array).size() == 6, "事件携带 6 个阵眼")
	_assert(_died_events.has(boss.id), "unit_died 信号已发")

	# ---- 失败路径:条件不满足不杀不广播 ----
	var alive_paper: Unit = null
	for e in state.enemies:
		if e.template_id == "paper_effigy" and e.is_alive:
			alive_paper = e
			break
	_assert(alive_paper != null, "找到存活纸人")
	# 移到阵区外 (13,9):6 阵眼激活后敌占区大多在六边形内,须显式移出
	state.map.set_occupant(alive_paper.position, null)
	alive_paper.position = Vector2i(13, 9)
	state.map.set_occupant(alive_paper.position, alive_paper.id)
	_assert(not spirit.check_seal_activation(alive_paper), "阵区外纸人不可封印")
	_assert(not spirit.activate_seal(alive_paper), "条件不满足 activate_seal 返回 false")
	_assert(alive_paper.is_alive, "失败封印不击杀")
	_assert(_seal_events.size() == 1, "失败封印不广播事件")
	# 灵气 < 6:即使目标在阵区也不可封印
	spirit.modify_density(-4, "test")  # 6→2
	_assert(state.spirit_density == 2, "灵气降到 2")
	state.map.set_occupant(alive_paper.position, null)
	alive_paper.position = Vector2i(2, 3)
	state.map.set_occupant(alive_paper.position, alive_paper.id)
	_assert(not spirit.check_seal_activation(alive_paper), "灵气不足时在阵区也不可封印")
	_assert(not spirit.activate_seal(alive_paper), "灵气不足 activate_seal 返回 false")
	_assert(_seal_events.size() == 1, "仍无额外广播")

	if _failed:
		printerr("TEST_SEAL: 存在失败断言")
		quit(1)
	else:
		print("TEST_SEAL: 全部断言通过")
		quit(0)

func _assert(cond: bool, what: String) -> void:
	if cond:
		print("  [PASS] ", what)
	else:
		printerr("  [FAIL] ", what)
		_failed = true
