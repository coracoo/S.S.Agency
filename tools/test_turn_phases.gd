# 回合阶段机 + 意图锁定 单测:无头跑 SceneTree
# 验证:阶段流转顺序、turn:phase_changed 广播、锁定计划不受 AI 输入变化影响、打断判定
# 用法: Godot --path <项目> --script res://tools/test_turn_phases.gd
extends SceneTree

var _phase_events: Array = []
var _failed: bool = false

func _initialize() -> void:
	Card.load_cards()
	UnitFactory.load_templates()
	StatusEffectManager.load_defs()
	var state := GameState.new()
	state.init_battle(state.player_spawn_defs, state.enemy_spawn_defs)
	print("STEP: battle inited")
	# turn_manager.gd 引用 EventBus,必须运行时动态 load(autoload 已注册后)
	var tm_class: GDScript = load("res://scripts/core/turn_manager.gd")
	var tm = tm_class.new(state)
	var bus = root.get_node_or_null("EventBus")
	_assert(bus != null, "EventBus autoload 可用")
	bus.on("turn:phase_changed", func(data): _phase_events.append(data))
	print("STEP: turn manager created, phase events subscribed")

	# ---- 阶段流转:GDD §三 player → intent → enemy → environment → spirit → player ----
	tm.set_phase("intent")
	_assert(tm.phase == "intent", "阶段切到 intent(意图预览)")
	_assert(state.current_turn == "intent", "current_turn 同步 intent")
	tm.set_phase("enemy")
	tm.set_phase("environment")
	tm.set_phase("spirit")
	tm.set_phase("player")
	_assert(tm.phase == "player", "阶段回到 player")
	_assert(_phase_events.size() == 5, "turn:phase_changed 广播 5 次")
	if _phase_events.size() == 5:
		var seq = []
		for ev in _phase_events:
			seq.append(str(ev.get("to", "")))
		_assert(seq == ["intent", "enemy", "environment", "spirit", "player"], "阶段流转顺序符合 GDD")
		_assert(str(_phase_events[0].get("from", "")) == "player", "首个事件 from=player")
		_assert(str(_phase_events[1].get("from", "")) == "intent", "enemy 事件 from=intent")
	# 同阶段重复切换不广播
	tm.set_phase("player")
	_assert(_phase_events.size() == 5, "同阶段重复 set_phase 不广播")

	# ---- 意图锁定:锁定后改变 AI 输入,本回合执行不受影响 ----
	state.current_turn = "player"
	state.team_ap = 6
	# ai_controller.gd 引用 EventBus,必须运行时动态 load(同 turn_manager)
	var ai_class: GDScript = load("res://scripts/core/ai_controller.gd")
	var ai = ai_class.new(state.map, state.all_units)
	var active_enemies = []
	for e in state.enemies:
		if e.is_alive:
			e.start_turn()
			active_enemies.append(e)
	var ctx = {
		"map": state.map,
		"players": state.get_alive_units("player"),
		"all_units": state.all_units,
		"noise_events": [],
		"spirit_density": state.spirit_density,
		"turn": state.turn_count,
	}
	var plan: Dictionary = ai.generate_turn_plan(active_enemies, ctx)
	var locked_queue: Array = ai.flatten_plan_actions(plan)
	_assert(not locked_queue.is_empty(), "AI 生成锁定动作队列非空")
	var snapshot: Array = locked_queue.duplicate(true)
	# 锁定后:玩家单位全部移到远处 + 加噪音 + 灵气拉满(AI 输入剧变)
	for p in state.players:
		if p.unit.is_alive:
			state.map.set_occupant(p.unit.position, null)
			p.unit.position = Vector2i(13, 9)
			state.map.set_occupant(p.unit.position, p.unit.id)
	# 阶段 3 起纸人有 sightRange,远处玩家不可见会走巡逻;把一名玩家放进纸人视野,确保重新生成的计划必然变化
	var effigy = null
	for e in active_enemies:
		if e.template_id == "paper_effigy" and e.is_alive:
			effigy = e
			break
	if effigy != null:
		var near_p = state.get_alive_units("player")[0]
		var near_pos = effigy.position + Vector2i(0, 1)
		if state.map.is_occupied(near_pos) or not state.map.is_walkable(near_pos):
			near_pos = effigy.position + Vector2i(1, 0)
		state.map.set_occupant(near_p.position, null)
		near_p.position = near_pos
		state.map.set_occupant(near_pos, near_p.id)
	state.noise_events.append({"pos": Vector2i(0, 0), "volume": 5, "source_id": "test", "source_type": "test", "duration": 1})
	state.modify_spirit_density(8)
	# 锁定队列是数据快照,不受输入变化影响
	_assert(str(locked_queue) == str(snapshot), "锁定队列内容不受 AI 输入变化影响")
	# 重新生成计划则不同(证明输入确实变了,锁定是有意义的)
	var plan2: Dictionary = ai.generate_turn_plan(active_enemies, ctx)
	var queue2: Array = ai.flatten_plan_actions(plan2)
	_assert(str(queue2) != str(snapshot), "重新生成的计划与锁定快照不同(输入已变)")

	# ---- 打断判定:is_action_executable ----
	if locked_queue.size() > 0:
		var act: Dictionary = locked_queue[0]
		var chk: Dictionary = ai.is_action_executable(act, state)
		_assert(bool(chk.get("ok", false)), "正常锁定动作可执行")
		var act_unit = state.get_unit_by_id(str(act.get("unit_id", "")))
		_assert(act_unit != null, "动作单位存在")
		if act_unit != null:
			# 死亡打断
			act_unit.current_hp = 0
			chk = ai.is_action_executable(act, state)
			_assert(not bool(chk.get("ok", true)) and str(chk.get("reason", "")) == "dead", "单位死亡 → dead 打断")
			act_unit.current_hp = act_unit.max_hp
			# 恐惧打断(非恐惧逃逸动作)
			var old_state: String = act_unit.ai_state
			act_unit.ai_state = "fear"
			chk = ai.is_action_executable(act, state)
			var expect_fear_block: bool = str(act.get("intent_style", "")) != "fear"
			if expect_fear_block:
				_assert(not bool(chk.get("ok", true)) and str(chk.get("reason", "")) == "fear", "锁定后恐惧 → fear 打断")
			else:
				_assert(bool(chk.get("ok", false)), "恐惧逃逸动作不被恐惧打断")
			act_unit.ai_state = old_state
		# 不存在单位 id → dead
		chk = ai.is_action_executable({"type": "move", "unit_id": "ghost_none", "target_pos": Vector2i(0, 0)}, state)
		_assert(not bool(chk.get("ok", true)) and str(chk.get("reason", "")) == "dead", "单位不存在 → dead 打断")

	if _failed:
		printerr("TEST_TURN_PHASES: 存在失败断言")
		quit(1)
	else:
		print("TEST_TURN_PHASES: 全部断言通过")
		quit(0)

func _assert(cond: bool, what: String) -> void:
	if cond:
		print("  [PASS] ", what)
	else:
		printerr("  [FAIL] ", what)
		_failed = true
