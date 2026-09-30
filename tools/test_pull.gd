# pull(拉)逻辑单测:无头跑 SceneTree,验证物体/角色位置、AP 扣除、EventBus 广播
# 用法: Godot --path <项目> --script res://tools/test_pull.gd
extends SceneTree

var _pull_events: Array = []

func _initialize() -> void:
	Card.load_cards()
	UnitFactory.load_templates()
	StatusEffectManager.load_defs()
	var state := GameState.new()
	state.init_battle(state.player_spawn_defs, state.enemy_spawn_defs)
	print("STEP: battle inited")
	state.current_turn = "player"
	state.team_ap = 6
	# 主 --script 的编译期依赖图不含 autoload,interaction_system.gd 引用 EventBus,
	# 必须运行时动态 load(此时 autoload 已注册),不能写 InteractionSystem.new()
	var inter_class: GDScript = load("res://scripts/core/interaction_system.gd")
	var inter = inter_class.new(state, state.map.objects_data)
	print("STEP: interaction system created")
	# 主 --script 编译早于 autoload 注册,EventBus 只能运行时按节点获取
	var bus = root.get_node_or_null("EventBus")
	_assert(bus != null, "EventBus autoload 可用")
	bus.on("object:pulled", func(data): _pull_events.append(data))
	print("STEP: event subscribed")

	var unit: Unit = state.players[0].unit
	print("STEP: unit=", unit.id, " pos=", unit.position)
	# 找一格三连空位:(x-1,y) 后退位、(x,y) 站位、(x+1,y) 放物体,均可走且无占位
	var spot := Vector2i(-1, -1)
	for y in range(state.map.rows):
		for x in range(1, state.map.cols - 1):
			var c := Vector2i(x, y)
			var back := Vector2i(x - 1, y)
			var front := Vector2i(x + 1, y)
			if not state.map.is_walkable(c) or not state.map.is_walkable(back) or not state.map.is_walkable(front):
				continue
			if state.map.is_occupied(c) or state.map.is_occupied(back) or state.map.is_occupied(front):
				continue
			if state.map.get_object(c.x, c.y) != "" or state.map.get_object(back.x, back.y) != "" or state.map.get_object(front.x, front.y) != "":
				continue
			spot = c
			break
		if spot.x >= 0:
			break
	_assert(spot.x >= 0, "找到可用的三连空位")

	# 布置:单位移到 spot,物体(water_barrel,pushable)放 front
	state.map.set_occupant(unit.position, null)
	unit.position = spot
	state.map.set_occupant(spot, unit.id)
	var front := spot + Vector2i(1, 0)
	state.map.set_object(front.x, front.y, "water_barrel")
	var ap_before: int = state.team_ap

	var ok: bool = inter.pull(unit, Vector2i(1, 0))
	_assert(ok, "pull 返回 true")
	_assert(state.map.get_object(spot.x, spot.y) == "water_barrel", "物体被拉到角色原位")
	_assert(state.map.get_object(front.x, front.y) == "", "物体原位置已清空")
	_assert(unit.position == spot - Vector2i(1, 0), "角色后退 1 格")
	_assert(state.map.get_occupant_id(unit.position) == unit.id, "角色占位已更新到后退位")
	_assert(state.team_ap == ap_before - 1, "AP 扣除 1")
	_assert(_pull_events.size() == 1, "object:pulled 事件广播 1 次")
	if _pull_events.size() == 1:
		var ev: Dictionary = _pull_events[0]
		_assert(ev.get("object_id") == "water_barrel", "事件 object_id 正确")
		_assert(ev.get("to") == spot, "事件 to 为角色原位")
		_assert(ev.get("unit_to") == unit.position, "事件 unit_to 为角色后退位")

	# 反向 pull(方向不合法)应失败且不扣 AP
	var ap_mid: int = state.team_ap
	_assert(not inter.pull(unit, Vector2i(2, 0)), "非相邻方向 pull 返回 false")
	_assert(state.team_ap == ap_mid, "失败 pull 不扣 AP")

	print("TEST_PULL: 全部断言通过")
	quit(0)

func _assert(cond: bool, what: String) -> void:
	if cond:
		print("  [PASS] ", what)
	else:
		printerr("  [FAIL] ", what)
		quit(1)
