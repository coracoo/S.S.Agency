# 噪音/灵气规则效果运行验收(GDD §5.4/§5.5/§12.1,Phase 4 收尾)
# 覆盖:噪音 BFS 衰减(-1/格、穿墙额外 -2、水面放大 +1)、AI 听觉阈值(≥3 search、≥5+fear_noise fear)、
#       灵气变化(击杀 -2/开棺 +5/回合 -1/符纸 -1)、灵气 tier 对移速与伤害的端到端效果
# 用法: Godot --path <项目> --script res://tools/test_noise_spirit_accept.gd
extends SceneTree

var _failed := false
var _noise_events: Array = []
var bus = null          # EventBus autoload(SceneTree 脚本内须用节点引用)

var state: GameState
var ai = null           # AIController(动态 load,引用 EventBus)
var spirit = null       # SpiritSystem(动态 load,引用 EventBus)

func _initialize() -> void:
	Card.load_cards()
	UnitFactory.load_templates()
	StatusEffectManager.load_defs()
	bus = root.get_node_or_null("EventBus")
	_assert(bus != null, "EventBus autoload 可用")
	bus.on("noise:propagated", func(d): _noise_events.append(d))

	_test_noise_bfs()
	_setup_battle()
	_test_ai_hearing()
	_test_spirit_changes()
	_test_spirit_tier_e2e()

	if _failed:
		printerr("TEST_NOISE_SPIRIT_ACCEPT: 存在失败断言")
		quit(1)
	else:
		print("TEST_NOISE_SPIRIT_ACCEPT: 全部断言通过")
		quit(0)

func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  [PASS] " + msg)
	else:
		_failed = true
		printerr("  [FAIL] " + msg)

# ============ A. 噪音 BFS 衰减(5×5 受控小地图) ============

func _make_noise_state() -> GameState:
	# 手写最小地形表:floor 普通 / wall blocking / water liquid
	var terrains = {
		"floor": {"tags": [], "move_cost": 1},
		"wall": {"tags": ["blocking"], "move_cost": 99},
		"water": {"tags": ["liquid"], "move_cost": 1},
	}
	var ground = [
		["floor", "floor", "floor", "floor", "floor"],
		["floor", "wall",  "floor", "floor", "floor"],
		["floor", "floor", "floor", "floor", "floor"],
		["floor", "floor", "water", "water", "floor"],
		["floor", "floor", "floor", "floor", "floor"],
	]
	# objects 层必须给全 5×5(get_tags/is_walkable 直接按坐标索引)
	var objects = []
	for r in range(5):
		var orow = []
		for c in range(5):
			orow.append(null)
		objects.append(orow)
	var gs := GameState.new()
	gs.map = GameMap.new({"cols": 5, "rows": 5, "version": 2, "layers": {"ground": ground, "objects": objects}}, terrains, {}, {})
	return gs

func _test_noise_bfs() -> void:
	var gs = _make_noise_state()
	var ns_class: GDScript = load("res://scripts/core/noise_system.gd")
	var ns = ns_class.new(gs)
	_noise_events.clear()

	# 铃铛音量 6 @ (2,2):直线衰减 / 穿墙衰减
	var ev: Dictionary = ns.create_noise(Vector2i(2, 2), 6, "test_bell", "bell")
	var nm: Dictionary = ev.get("noise_map", {})
	_assert(int(nm.get(Vector2i(2, 2), -1)) == 6, "原点音量 = 6")
	_assert(int(nm.get(Vector2i(3, 2), -1)) == 5, "相邻格每格 -1 → 5")
	_assert(int(nm.get(Vector2i(4, 2), -1)) == 4, "两格 -2 → 4")
	_assert(int(nm.get(Vector2i(2, 0), -1)) == 4, "无障碍两格 = 4(穿墙对照)")
	_assert(int(nm.get(Vector2i(1, 1), -1)) == 2, "穿墙格:5-3=2(基础 -1 + 额外 -2)")
	_assert(_noise_events.size() == 1, "noise:propagated 已广播 1 次")
	if _noise_events.size() == 1:
		_assert(int(_noise_events[0].get("volume", 0)) == 6, "广播事件音量 = 6")
		_assert(_noise_events[0].get("origin", Vector2i(-1, -1)) == Vector2i(2, 2), "广播事件原点正确")

	# 水面放大 +1:音量 3 @ (1,3),右邻两格为 water(liquid)
	var ev2: Dictionary = ns.create_noise(Vector2i(1, 3), 3, "test_water", "bell")
	var nm2: Dictionary = ev2.get("noise_map", {})
	_assert(int(nm2.get(Vector2i(2, 3), -1)) == 3, "水面格衰减 -0 → 3(放大 +1)")
	_assert(int(nm2.get(Vector2i(3, 3), -1)) == 3, "连续水面仍 = 3")
	_assert(int(nm2.get(Vector2i(4, 3), -1)) == 2, "离开水面恢复 -1 → 2")
	ns.dispose()

# ============ B. AI 听觉阈值(GDD §12.1:≥3 search,≥5+fear_noise fear) ============

func _setup_battle() -> void:
	state = GameState.new()
	state.init_battle(state.player_spawn_defs, state.enemy_spawn_defs)
	var ai_class: GDScript = load("res://scripts/core/ai_controller.gd")
	ai = ai_class.new(state.map, state.all_units)
	var sp_class: GDScript = load("res://scripts/core/spirit_system.gd")
	spirit = sp_class.new(state)
	# 玩家全部移远,隔离视野/攻击干扰
	for p in state.get_alive_units("player"):
		state.map.set_occupant(p.position, null)
		p.position = Vector2i(13, 9)
		state.map.set_occupant(p.position, p.id)

func _effigy() -> Unit:
	for e in state.enemies:
		if e.template_id == "paper_effigy" and e.is_alive:
			return e
	return null

func _noise_ctx(vol: int, src: Vector2i, heard_val: int) -> Dictionary:
	var e = _effigy()
	return {
		"map": state.map,
		"players": state.get_alive_units("player"),
		"all_units": state.all_units,
		"noise_events": [{"pos": src, "volume": vol, "noise_map": {e.position: heard_val}}],
		"spirit_density": state.spirit_density,
		"turn": 1,
	}

func _plain_ctx() -> Dictionary:
	return {
		"map": state.map,
		"players": state.get_alive_units("player"),
		"all_units": state.all_units,
		"noise_events": [],
		"spirit_density": state.spirit_density,
		"turn": 1,
	}

func _test_ai_hearing() -> void:
	var e = _effigy()
	_assert(e != null, "找到纸人")
	e.ai_profile = e.ai_profile.duplicate()
	e.ai_profile["fearRange"] = 0  # 隔离地形恐惧,专测噪音阈值
	var src := Vector2i(8, 5)
	# B1: 铃铛音量 4(≥3)→ search
	e.ai_state = "patrol"
	var plan: Dictionary = ai.generate_enemy_plan(e, _noise_ctx(4, src, 2))
	_assert(str(plan.get("state", "")) == "search", "音量 4 ≥3 → 纸人 search")
	_assert(str(plan.get("reason", "")) == "noise", "search 原因 = noise")
	_assert(e.search_target == src, "search 目标 = 噪音源")
	# B2: 推物体音量 2(<3)→ 不吸引
	e.ai_state = "patrol"
	var plan2: Dictionary = ai.generate_enemy_plan(e, _noise_ctx(2, src, 1))
	_assert(str(plan2.get("state", "")) != "search", "音量 2 <3 → 不进 search")
	_assert(str(plan2.get("reason", "")) != "noise", "音量 2 → 非噪音驱动")
	# B3: 爆燃音量 5 + fear_noise 0.6(≥0.5)→ fear(纸人怕"大声",GDD §12.1)
	e.ai_state = "patrol"
	var plan3: Dictionary = ai.generate_enemy_plan(e, _noise_ctx(5, src, 3))
	_assert(str(plan3.get("state", "")) == "fear", "音量 5 ≥5 + fear_noise 高 → fear")

# ============ C. 灵气变化公式(GDD §12.2) ============

func _test_spirit_changes() -> void:
	state.spirit_density = 5
	var e = _effigy()
	spirit.on_unit_died(e.id)
	_assert(state.spirit_density == 3, "击杀灵体 -2 → 3")
	bus.emit("coffin:opened", {"map": state.map, "pos": Vector2i(0, 0), "unit_id": "test"})
	_assert(state.spirit_density == 8, "棺材开启 +5 → 8")
	spirit.modify_density(-1, "turn_tick")
	_assert(state.spirit_density == 7, "每回合自然衰减 -1 → 7")
	bus.emit("effect:added", {"map": state.map, "pos": Vector2i(1, 1), "effect": "talisman"})
	_assert(state.spirit_density == 6, "符纸净化 -1 → 6")

# ============ D. 灵气 tier 端到端:移速/伤害结算输入 ============

func _test_spirit_tier_e2e() -> void:
	var e = _effigy()
	var base_move: int = e.stats.move_range
	var base_str: int = e.stats.strength
	# 当前灵气 6(reinforced):track 后立即应用 tier 效果
	spirit.track_enemies(state.enemies)
	_assert(e.stats.strength == roundi(float(base_str) * 1.3), "灵气 6 强化:strength %d→%d(×1.3)" % [base_str, e.stats.strength])
	# 灵气 8(rage):×1.5
	spirit.modify_density(2, "test")
	_assert(state.spirit_density == 8, "灵气 → 8 暴走")
	_assert(e.stats.strength == roundi(float(base_str) * 1.5), "暴走:strength %d→%d(×1.5)" % [base_str, e.stats.strength])
	# 灵气 0(weak):纸人(minion)移速 -1,强度回基准
	spirit.modify_density(-8, "test")
	_assert(state.spirit_density == 0, "灵气 → 0 虚弱")
	_assert(e.stats.move_range == base_move - 1, "虚弱:纸人移速 %d→%d(-1)" % [base_move, e.stats.move_range])
	_assert(e.stats.strength == base_str, "虚弱:strength 回 %d" % base_str)

	# 端到端:虚弱移速 2 时,chase 计划单步移动距离 ≤ 2(原 3)
	var p: Unit = state.get_alive_units("player")[0]
	var placed := false
	for off in [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3)]:
		var cand: Vector2i = e.position + off
		if state.map.in_bounds(cand) and state.map.is_walkable(cand):
			state.map.set_occupant(p.position, null)
			p.position = cand
			state.map.set_occupant(cand, p.id)
			placed = true
			break
	_assert(placed, "摆放玩家到纸人视野内(距离 3)")
	e.ai_state = "chase"
	var plan4: Dictionary = ai.generate_enemy_plan(e, _plain_ctx())
	var mv = null
	for a in plan4.get("actions", []):
		if str(a.get("type", "")) == "move":
			mv = a
			break
	_assert(mv != null, "chase 计划产生移动动作")
	if mv != null:
		var dist: int = absi(int(mv.to.x) - e.position.x) + absi(int(mv.to.y) - e.position.y)
		_assert(dist <= 2, "虚弱移速 2 → 移动距离 %d ≤ 2(端到端生效)" % dist)

	# 灵气回 3(normal):移速/强度恢复
	spirit.modify_density(3, "test")
	_assert(state.spirit_density == 3, "灵气回 3 正常")
	_assert(e.stats.move_range == base_move, "正常:移速恢复 %d" % base_move)
	_assert(e.stats.strength == base_str, "正常:strength 恢复 %d" % base_str)
	spirit.dispose()
