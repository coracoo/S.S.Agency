# AI 差异化行为单测:巡逻/rage/confused/红衣女/水鬼/僵尸/Boss 两阶段/百鬼夜行
# 用法: Godot --path <项目> --script res://tools/test_ai_behaviors.gd
extends SceneTree

var _state_events: Array = []
var _boss_events: Array = []
var _failed: bool = false

var state: GameState
var ai = null  # AIController(动态 load,因引用 EventBus)

func _initialize() -> void:
	Card.load_cards()
	UnitFactory.load_templates()
	StatusEffectManager.load_defs()
	state = GameState.new()
	state.init_battle(state.player_spawn_defs, state.enemy_spawn_defs)
	var bus = root.get_node_or_null("EventBus")
	_assert(bus != null, "EventBus autoload 可用")
	bus.on("ai:state_changed", func(d): _state_events.append(d))
	bus.on("boss:phase_changed", func(d): _boss_events.append(d))
	var ai_class: GDScript = load("res://scripts/core/ai_controller.gd")
	ai = ai_class.new(state.map, state.all_units)
	print("STEP: battle + ai ready")

	# 工具:全部玩家移远(出任何视野),便于隔离测试
	var players = state.get_alive_units("player")
	for p in players:
		state.map.set_occupant(p.position, null)
		p.position = Vector2i(13, 9)
		state.map.set_occupant(p.position, p.id)

	_test_patrol()
	_test_rage_and_fear_immune()
	_test_confused()
	_test_red_lady()
	_test_water_ghost()
	_test_jiangshi_leap()
	_test_boss_phases()
	_test_hundred_ghosts()

	if _failed:
		printerr("TEST_AI_BEHAVIORS: 存在失败断言")
		quit(1)
	else:
		print("TEST_AI_BEHAVIORS: 全部断言通过")
		quit(0)

func _ctx(turn: int = 1) -> Dictionary:
	return {
		"map": state.map,
		"players": state.get_alive_units("player"),
		"all_units": state.all_units,
		"noise_events": [],
		"spirit_density": state.spirit_density,
		"turn": turn,
	}

func _effigy() -> Unit:
	for e in state.enemies:
		if e.template_id == "paper_effigy" and e.is_alive:
			return e
	return null

# ---- 1. 巡逻:视野内无玩家时沿 patrolPath 循环 ----
func _test_patrol() -> void:
	var e = _effigy()
	_assert(e != null, "找到纸人")
	e.ai_state = "patrol"
	e.start_turn()
	var plan: Dictionary = ai.generate_enemy_plan(e, _ctx())
	_assert(str(plan.get("state", "")) == "patrol", "无视野目标 → patrol 计划")
	var acts: Array = plan.get("actions", [])
	_assert(acts.size() == 1 and str(acts[0].get("intent_style", "")) == "patrol", "巡逻产生巡逻移动动作")
	# 到达路径点后推进游标
	e.position = Vector2i(3, 2)  # patrolPath 第 0 点
	state.map.set_occupant(e.position, e.id)
	e.start_turn()
	var before: int = e.patrol_index
	ai.generate_enemy_plan(e, _ctx())
	_assert(e.patrol_index == before + 1, "到达巡逻点后游标 +1")

# ---- 2. rage:执念威胁触发 + 无视恐惧 + 数回合后冷静 ----
func _test_rage_and_fear_immune() -> void:
	var bus = root.get_node("EventBus")
	_state_events.clear()
	var e = _effigy()
	e.ai_state = "patrol"
	# 棺材被打开 → 执念为 coffin 的灵体进 rage
	bus.emit("coffin:opened", {"map": state.map, "pos": Vector2i(5, 3), "unit_id": "test"})
	_assert(e.ai_state == "rage", "棺材被打开 → 纸人进 rage")
	_assert(e.rage_target_pos == Vector2i(5, 3), "rage 目标=棺材位置")
	var rage_ev := false
	for ev in _state_events:
		if str(ev.get("unit_id", "")) == e.id and str(ev.get("state", "")) == "rage":
			rage_ev = true
	_assert(rage_ev, "广播 ai:state_changed(rage)")
	# rage 无视恐惧:旁边放火也不进 fear
	state.map.add_effect(e.position.x, e.position.y, "fire")
	e.start_turn()
	var plan: Dictionary = ai.generate_enemy_plan(e, _ctx())
	_assert(str(plan.get("state", "")) == "rage", "rage 期间无视火焰恐惧")
	state.map.remove_effect(e.position.x, e.position.y, "fire")
	# rage_turns 耗尽 → 冷静回默认状态
	e.rage_turns = 1
	e.start_turn()
	ai.generate_enemy_plan(e, _ctx())
	_assert(e.ai_state != "rage", "rage 回合耗尽后冷静")
	e.ai_state = "patrol"

# ---- 3. confused:灵体站符纸格 → 随机移动 2 回合后恢复 ----
func _test_confused() -> void:
	var e = _effigy()
	e.ai_state = "patrol"
	e.confused_turns = 0
	state.map.add_effect(e.position.x, e.position.y, "talisman")
	e.start_turn()
	var plan: Dictionary = ai.generate_enemy_plan(e, _ctx())
	_assert(str(plan.get("state", "")) == "confused", "灵体站符纸格 → confused")
	_assert(e.confused_turns == 2, "confused 持续 2 回合")
	_state_events.clear()
	e.start_turn()
	ai.generate_enemy_plan(e, _ctx())
	_assert(e.confused_turns == 1, "confused 第 1 次规划后剩 1 回合")
	e.start_turn()
	ai.generate_enemy_plan(e, _ctx())
	_assert(e.confused_turns == 0, "confused 第 2 次规划后结束")
	_assert(e.ai_state == "patrol", "confused 恢复默认状态")
	var rec_ev := false
	for ev in _state_events:
		if str(ev.get("reason", "")) == "confused_recovered":
			rec_ev = true
	_assert(rec_ev, "广播 confused_recovered")
	state.map.remove_effect(e.position.x, e.position.y, "talisman")

# ---- 4. 红衣女:被注视瞬移 / 背对安全 ----
func _test_red_lady() -> void:
	var lady = UnitFactory.create("red_lady", Vector2i(0, 5))
	state.map.set_occupant(lady.position, lady.id)
	var player = state.get_alive_units("player")[0]
	state.map.set_occupant(player.position, null)
	player.position = Vector2i(0, 7)  # 红衣女正下方 2 格
	state.map.set_occupant(player.position, player.id)
	player.facing = Vector2i.UP  # 面朝她
	lady.start_turn()
	var plan: Dictionary = ai.generate_enemy_plan(lady, _ctx())
	var acts: Array = plan.get("actions", [])
	var has_tp := false
	var has_atk := false
	for a in acts:
		if a.get("type") == "teleport":
			has_tp = true
		if a.get("type") == "attack":
			has_atk = true
	_assert(has_tp and has_atk, "被注视 → 瞬移+攻击")
	if has_tp:
		var dest: Vector2i = acts[0].get("to")
		_assert(absi(dest.x - player.position.x) + absi(dest.y - player.position.y) == 1, "瞬移落点与注视者相邻")
	# 背对她 → 完全静止
	player.facing = Vector2i.DOWN
	lady.start_turn()
	var plan2: Dictionary = ai.generate_enemy_plan(lady, _ctx())
	_assert((plan2.get("actions", []) as Array).is_empty(), "背对/无人注视 → 静止不动")
	_assert(str(plan2.get("state", "")) == "idle_watch", "未注视状态 idle_watch")
	state.map.set_occupant(lady.position, null)

# ---- 5. 水鬼:相邻拖拽入水 + 离水变弱 ----
func _test_water_ghost() -> void:
	# 找水域格及相邻可行走陆格(本图水域在 (7,1),单格水走换位拖拽)
	var water := Vector2i(-1, -1)
	var shore := Vector2i(-1, -1)
	for y in range(state.map.rows):
		for x in range(state.map.cols):
			if state.map.get_terrain(x, y) != "water":
				continue
			for n in state.map.get_neighbors(Vector2i(x, y)):
				if state.map.is_walkable(n) and not state.map.is_occupied(n) and state.map.get_terrain(n.x, n.y) != "water":
					water = Vector2i(x, y)
					shore = n
					break
			if water.x >= 0:
				break
		if water.x >= 0:
			break
	_assert(water.x >= 0, "找到水域+相邻陆格")
	var ghost = UnitFactory.create("water_ghost", water)
	state.map.set_occupant(water, ghost.id)
	# 隔离恐惧干扰:水鬼 fearTags 含 seal_point,水域 (7,1) 离阵眼 (6,0) 曼哈顿=2 恰在 fearRange 内,
	# 会被重置为 fear 而抢先于拖拽;单测清掉 fearRange 专注测本特性
	ghost.ai_profile = ghost.ai_profile.duplicate()
	ghost.ai_profile["fearRange"] = 0
	var player = state.get_alive_units("player")[0]
	state.map.set_occupant(player.position, null)
	player.position = shore
	state.map.set_occupant(shore, player.id)
	ghost.start_turn()
	var plan: Dictionary = ai.generate_enemy_plan(ghost, _ctx())
	var acts: Array = plan.get("actions", [])
	var drag: Dictionary = {}
	for a in acts:
		if a.get("type") == "drag":
			drag = a
	_assert(not drag.is_empty(), "相邻玩家 → 拖拽动作")
	if not drag.is_empty():
		_assert(str(drag.get("target_id", "")) == player.id, "拖拽目标正确")
		var dest: Vector2i = drag.get("target_pos")
		_assert(state.map.has_tag(dest.x, dest.y, "liquid"), "拖拽落点为水域")
	# 离水变弱:找一个离水 >2 格的可行走格,玩家放其攻击范围内
	state.map.set_occupant(ghost.position, null)
	var far_cell := Vector2i(-1, -1)
	for y in range(state.map.rows):
		for x in range(state.map.cols):
			var c := Vector2i(x, y)
			if not state.map.is_walkable(c) or state.map.is_occupied(c):
				continue
			ghost.position = c
			if ai._is_away_from_home(ghost):
				far_cell = c
				break
		if far_cell.x >= 0:
			break
	_assert(far_cell.x >= 0, "找到离水变弱格")
	ghost.position = far_cell
	state.map.set_occupant(far_cell, ghost.id)
	state.map.set_occupant(player.position, null)
	# 玩家放 dist=3:ranged 最优距离,不移动直接攻击,必出带 damage_mult 的 attack
	player.position = far_cell + Vector2i(0, 3)
	if not state.map.in_bounds(player.position) or not state.map.is_walkable(player.position):
		player.position = far_cell + Vector2i(1, 2)
	if not state.map.in_bounds(player.position) or not state.map.is_walkable(player.position):
		player.position = far_cell + Vector2i(2, 1)
	state.map.set_occupant(player.position, player.id)
	_assert(ai._is_away_from_home(ghost), "离水 >2 格判定为变弱")
	ghost.start_turn()
	var plan2: Dictionary = ai.generate_enemy_plan(ghost, _ctx())
	var weak_atk := false
	for a in plan2.get("actions", []):
		if a.get("type") == "attack" and abs(float(a.get("damage_mult", 1.0)) - 0.5) < 0.01:
			weak_atk = true
	_assert(weak_atk, "离水攻击伤害 ×0.5")
	state.map.set_occupant(ghost.position, null)

# ---- 6. 僵尸:直线跳跃越障 ----
func _test_jiangshi_leap() -> void:
	# 找一行三连空位:僵尸 (x,y) → 中间 (x+1,y) 放物体 → 玩家 (x+3,y)
	var spot := Vector2i(-1, -1)
	for y in range(state.map.rows):
		for x in range(1, state.map.cols - 4):
			var ok := true
			for i in range(4):
				var c := Vector2i(x + i, y)
				if not state.map.is_walkable(c) or state.map.is_occupied(c):
					ok = false
					break
			if ok:
				spot = Vector2i(x, y)
				break
		if spot.x >= 0:
			break
	_assert(spot.x >= 0, "找到四连空位")
	var jiang = UnitFactory.create("jiangshi", spot)
	state.map.set_occupant(spot, jiang.id)
	# 中间格放可推物体(视为低矮物体,可跳过)
	state.map.set_object(spot.x + 1, spot.y, "water_barrel")
	var player = state.get_alive_units("player")[0]
	state.map.set_occupant(player.position, null)
	player.position = spot + Vector2i(3, 0)
	state.map.set_occupant(player.position, player.id)
	jiang.start_turn()
	var plan: Dictionary = ai.generate_enemy_plan(jiang, _ctx())
	var leap: Dictionary = {}
	for a in plan.get("actions", []):
		if a.get("type") == "move" and bool(a.get("leap", false)):
			leap = a
	_assert(not leap.is_empty(), "同排距离3 → 直线跳跃")
	if not leap.is_empty():
		_assert(leap.get("to") == spot + Vector2i(2, 0), "跳跃落点为 +2 格")
	# 不同排/列不跳
	state.map.set_occupant(player.position, null)
	player.position = spot + Vector2i(3, 1)
	state.map.set_occupant(player.position, player.id)
	jiang.start_turn()
	var plan2: Dictionary = ai.generate_enemy_plan(jiang, _ctx())
	var leap2 := false
	for a in plan2.get("actions", []):
		if bool(a.get("leap", false)):
			leap2 = true
	_assert(not leap2, "非直线不跳跃")
	state.map.set_object(spot.x + 1, spot.y, null)
	state.map.set_occupant(jiang.position, null)

# ---- 7. Boss 两阶段 ----
func _test_boss_phases() -> void:
	var boss: Unit = null
	for e in state.enemies:
		if e.template_id == "coffin_lord":
			boss = e
	_assert(boss != null, "找到棺材主")
	# 阶段 1:固守不追击(远玩家在视野外,近玩家也不移动)
	boss.ai_state = "chase"
	boss.start_turn()
	var plan1: Dictionary = ai.generate_enemy_plan(boss, _ctx())
	var has_move1 := false
	for a in plan1.get("actions", []):
		if a.get("type") == "move":
			has_move1 = true
	_assert(not has_move1, "阶段 1 固守不移动")
	# 阶段 1 指挥:turn%3==0 时给 minion 下 rage
	var eff = _effigy()
	eff.ai_state = "patrol"
	_state_events.clear()
	ai.generate_turn_plan([boss, eff], _ctx(3))
	_assert(eff.ai_state == "rage", "阶段 1 指挥:纸人被下 rage 指令")
	eff.ai_state = "patrol"
	eff.rage_turns = 0
	# HP<=50% → 阶段 2 + 广播
	boss.current_hp = int(boss.max_hp * 0.5)
	_boss_events.clear()
	ai.generate_turn_plan([boss], _ctx(4))
	_assert(boss.boss_phase == 2, "HP<=50% → 阶段 2")
	_assert(_boss_events.size() == 1 and int(_boss_events[0].get("phase", 0)) == 2, "广播 boss:phase_changed(2)")
	# 阶段 2:全图追击远处玩家(有移动动作)
	var player = state.get_alive_units("player")[0]
	state.map.set_occupant(player.position, null)
	player.position = Vector2i(9, 7)
	state.map.set_occupant(player.position, player.id)
	boss.start_turn()
	var plan2: Dictionary = ai.generate_enemy_plan(boss, _ctx(5))
	var has_move2 := false
	for a in plan2.get("actions", []):
		if a.get("type") == "move":
			has_move2 = true
	_assert(has_move2, "阶段 2 全图追击(有移动动作)")
	# 阶段 2 畏惧封印阵:激活阵眼后 avoid 表非空
	state.map.add_effect(3, 0, "talisman")
	state.map.add_effect(6, 0, "talisman")
	var avoid: Dictionary = ai._compute_seal_avoid()
	_assert(not avoid.is_empty(), "激活阵眼后生成规避表")
	_assert(avoid.has(Vector2i(3, 0)) and avoid.has(Vector2i(3, 1)), "规避表含阵眼及相邻格")
	boss.current_hp = boss.max_hp
	boss.boss_phase = 1

# ---- 8. 百鬼夜行:所有灵体进 rage ----
func _test_hundred_ghosts() -> void:
	for e in state.enemies:
		if e.is_alive:
			e.ai_state = "patrol"
	ai.set_all_spirits_rage(state.get_alive_units("player"))
	var all_rage := true
	for e in state.enemies:
		if e.is_alive and e.tags.has("spirit") and e.ai_state != "rage":
			all_rage = false
	_assert(all_rage, "百鬼夜行:全部灵体进 rage")

func _assert(cond: bool, what: String) -> void:
	if cond:
		print("  [PASS] ", what)
	else:
		printerr("  [FAIL] ", what)
		_failed = true
