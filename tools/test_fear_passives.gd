# 恐惧值机制 + 角色环境被动单测(GDD §四/§七)
# 用法: Godot --path <项目> --script res://tools/test_fear_passives.gd
extends SceneTree

var _panic_events: Array = []
var _undying_events: Array = []
var _failed: bool = false

var state: GameState
var turn_manager = null  # TurnManager(动态 load,因引用 EventBus)
var interaction = null   # InteractionSystem

func _initialize() -> void:
	Card.load_cards()
	UnitFactory.load_templates()
	StatusEffectManager.load_defs()
	state = GameState.new()
	state.init_battle(state.player_spawn_defs, state.enemy_spawn_defs)
	var bus = root.get_node_or_null("EventBus")
	_assert(bus != null, "EventBus autoload 可用")
	bus.on("unit:panicked", func(d): _panic_events.append(d))
	bus.on("unit:undying_survived", func(d): _undying_events.append(d))
	var tm_class: GDScript = load("res://scripts/core/turn_manager.gd")
	turn_manager = tm_class.new(state)
	var is_class: GDScript = load("res://scripts/core/interaction_system.gd")
	interaction = is_class.new(state, state.map.objects_data)
	state.set_ap(6)

	_test_fear_thresholds()
	_test_fear_clamp_and_panic()
	_test_turn_end_recovery()
	_test_turn_start_fear_sources()
	_test_rinne_push_distance()
	_test_rinne_heavy_push()
	_test_mint_silent_move()
	_test_homura_free_ignite()
	_test_homura_fire_damage()
	_test_zhongkui_undying()

	if _failed:
		printerr("TEST_FEAR_PASSIVES: 存在失败断言")
		quit(1)
	else:
		print("TEST_FEAR_PASSIVES: 全部断言通过")
		quit(0)

func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("  [PASS] " + msg)
	else:
		_failed = true
		printerr("  [FAIL] " + msg)

func _player(tid: String) -> Unit:
	for p in state.players:
		if p.unit.template_id == tid:
			return p.unit
	return null

func _enemy(tid: String) -> Unit:
	for e in state.enemies:
		if e.template_id == tid and e.is_alive:
			return e
	return null

# ---- 1. 恐惧阈值:units.json 外置,凛音 80/薄荷 50/其他 65 ----
func _test_fear_thresholds() -> void:
	_assert(_player("rinne").fear_threshold == 80, "凛音恐惧阈值 80(高)")
	_assert(_player("mint").fear_threshold == 50, "薄荷恐惧阈值 50(低)")
	_assert(_player("homura").fear_threshold == 65, "焰华恐惧阈值 65")
	_assert(_player("zhongkui").fear_threshold == 65, "钟馗恐惧阈值 65")

# ---- 2. modify_fear clamp + 失控触发(阈值差异) ----
func _test_fear_clamp_and_panic() -> void:
	var rinne = _player("rinne")
	var mint = _player("mint")
	_panic_events.clear()
	# clamp:加到超 100 截断,减到负截断
	rinne.fear = 90
	rinne.modify_fear(50)
	_assert(rinne.fear == 100, "恐惧值 clamp 上限 100")
	rinne.modify_fear(-200)
	_assert(rinne.fear == 0, "恐惧值 clamp 下限 0")
	_assert(rinne.panicked, "凛音 fear≥80 → 失控")
	rinne.panicked = false
	rinne.fear = 0
	# 阈值差异:同样 +55,凛音(80)不失控,薄荷(50)失控
	rinne.modify_fear(55)
	_assert(rinne.fear == 55 and not rinne.panicked, "凛音 fear 55 < 80 → 不失控")
	mint.fear = 0
	mint.panicked = false
	mint.modify_fear(55)
	_assert(mint.panicked, "薄荷 fear 55 ≥ 50 → 失控(阈值低于凛音)")
	var mint_panicked_ev := false
	for ev in _panic_events:
		if str(ev.get("unit_id", "")) == mint.id:
			mint_panicked_ev = true
	_assert(mint_panicked_ev, "失控广播 unit:panicked")
	# 失控中继续加恐惧不重复广播
	var ev_count = _panic_events.size()
	mint.modify_fear(10)
	_assert(_panic_events.size() == ev_count, "失控中不重复广播 panicked")

# ---- 3. 回合结束:失控降到阈值 60% 并恢复,未失控自然 -5 ----
func _test_turn_end_recovery() -> void:
	var mint = _player("mint")
	# mint 当前 panicked=true(继承上一测试),fear=65
	mint.apply_turn_end_fear(-5, 0.6)
	_assert(not mint.panicked, "回合结束 → 失控恢复")
	_assert(mint.fear == int(mint.fear_threshold * 0.6), "失控恢复后 fear = 阈值×0.6(%d)" % int(mint.fear_threshold * 0.6))
	# 未失控单位自然恢复
	var homura = _player("homura")
	homura.panicked = false
	homura.fear = 20
	homura.apply_turn_end_fear(-5, 0.6)
	_assert(homura.fear == 15, "未失控单位回合结束自然 -5")

# ---- 4. 回合开始恐惧源:百鬼夜行 +15、诅咒地形 +5(经 turn_manager) ----
func _test_turn_start_fear_sources() -> void:
	var mint = _player("mint")
	mint.fear = 0
	mint.panicked = false
	# 百鬼夜行:灵气 10 → 回合开始 +15
	state.spirit_density = 10
	turn_manager.start_player_turn()
	_assert(mint.fear == 15, "百鬼夜行(灵气 10)回合开始 +15(实得 %d)" % mint.fear)
	state.spirit_density = 0
	# 诅咒地形(fear_increase 标签):把薄荷挪到诅咒格再开回合
	var curse_cell = Vector2i(-1, -1)
	for y in range(state.map.rows):
		for x in range(state.map.cols):
			if state.map.has_tag(x, y, "fear_increase"):
				curse_cell = Vector2i(x, y)
	if curse_cell.x < 0:
		print("  [SKIP] 本图无诅咒地形格,跳过 curseTilePerTurn 断言")
		return
	state.map.set_occupant(mint.position, null)
	mint.position = curse_cell
	state.map.set_occupant(curse_cell, mint.id)
	mint.fear = 0
	turn_manager.start_player_turn()
	_assert(mint.fear == 5, "诅咒地形格上回合开始 +5(实得 %d)" % mint.fear)

# ---- 5. 凛音「重心稳」:推动距离 +1(推 2 格) ----
func _test_rinne_push_distance() -> void:
	# 找水平 4 连可走且无物体的空地:角色在 0,物体在 1,落点候选 2/3
	var spot = _find_open_line(4)
	_assert(spot.size() == 4, "找到四连空位用于推距测试")
	if spot.size() != 4:
		return
	var rinne = _player("rinne")
	state.map.set_occupant(rinne.position, null)
	rinne.position = spot[0]
	state.map.set_occupant(spot[0], rinne.id)
	state.map.set_object(spot[1].x, spot[1].y, "brazier")
	var dir: Vector2i = spot[1] - spot[0]
	state.set_ap(6)
	_assert(interaction.push(rinne, dir), "凛音推火盆成功")
	_assert(state.map.get_object(spot[2].x, spot[2].y) == "" and state.map.get_object(spot[3].x, spot[3].y) == "brazier", "凛音推动 2 格(落点 +2)")
	# 对照:焰华(无特性)同样布局只能推 1 格
	state.map.set_object(spot[3].x, spot[3].y, null)
	state.map.set_occupant(spot[0], null)
	var homura = _player("homura")
	state.map.set_occupant(homura.position, null)
	homura.position = spot[0]
	state.map.set_occupant(spot[0], homura.id)
	state.map.set_object(spot[1].x, spot[1].y, "brazier")
	state.set_ap(6)
	_assert(interaction.push(homura, dir), "焰华推火盆成功")
	_assert(state.map.get_object(spot[2].x, spot[2].y) == "brazier", "焰华只推 1 格(落点 +1)")
	# 清理
	state.map.set_object(spot[2].x, spot[2].y, null)
	state.map.set_occupant(spot[0], null)
	homura.position = Vector2i(0, 6)
	state.map.set_occupant(homura.position, homura.id)

# ---- 6. 凛音「重心稳」:可推重物(heavy),其他角色不可 ----
func _test_rinne_heavy_push() -> void:
	var custom_objects = {
		"stone_block": {"pushable": true, "push_over": false, "tags": ["heavy", "blocking"], "interact": ["push"]}
	}
	var is_class: GDScript = load("res://scripts/core/interaction_system.gd")
	var heavy_interaction = is_class.new(state, custom_objects)
	var spot = _find_open_line(3)
	_assert(spot.size() == 3, "找到三连空位用于重物测试")
	if spot.size() != 3:
		return
	var dir: Vector2i = spot[1] - spot[0]
	# 焰华推重物 → 失败
	var homura = _player("homura")
	state.map.set_occupant(homura.position, null)
	homura.position = spot[0]
	state.map.set_occupant(spot[0], homura.id)
	state.map.set_object(spot[1].x, spot[1].y, "stone_block")
	state.set_ap(6)
	_assert(not heavy_interaction.push(homura, dir), "焰华推重物(heavy)→ 失败")
	# 凛音推重物 → 成功
	state.map.set_occupant(spot[0], null)
	var rinne = _player("rinne")
	state.map.set_occupant(rinne.position, null)
	rinne.position = spot[0]
	state.map.set_occupant(spot[0], rinne.id)
	state.set_ap(6)
	_assert(heavy_interaction.push(rinne, dir), "凛音推重物(heavy)→ 成功")
	# 清理
	state.map.set_object(spot[2].x, spot[2].y, null)
	state.map.set_object(spot[1].x, spot[1].y, null)
	state.map.set_occupant(spot[0], null)
	rinne.position = Vector2i(1, 6)
	state.map.set_occupant(rinne.position, rinne.id)

# ---- 7. 薄荷「无声步」:移动噪音 0,其他角色按 balance 配置 ----
func _test_mint_silent_move() -> void:
	_assert(state.move_noise_volume(_player("mint")) == 0, "薄荷移动噪音 = 0(无声步)")
	_assert(state.move_noise_volume(_player("rinne")) == 2, "凛音移动噪音 = 2(balance 配置)")

# ---- 8. 焰华「火焰亲和」:ignite 互动不耗 AP ----
func _test_homura_free_ignite() -> void:
	var homura = _player("homura")
	# 找相邻双空地:焰华站一格,火盆放相邻格
	var spot = _find_open_line(2)
	_assert(spot.size() == 2, "找到双连空位用于点火测试")
	if spot.size() != 2:
		return
	state.map.set_occupant(homura.position, null)
	homura.position = spot[0]
	state.map.set_occupant(spot[0], homura.id)
	state.map.set_object(spot[1].x, spot[1].y, "brazier")
	state.set_ap(3)
	var ap_before = state.team_ap
	_assert(interaction.interact(homura, spot[1], "ignite"), "焰华点燃火盆成功")
	_assert(state.team_ap == ap_before, "焰华点燃不耗 AP(AP %d→%d)" % [ap_before, state.team_ap])
	# 对照:凛音点燃耗 1 AP
	state.map.set_object(spot[1].x, spot[1].y, null)
	state.map.set_occupant(spot[0], null)
	var rinne = _player("rinne")
	state.map.set_occupant(rinne.position, null)
	rinne.position = spot[0]
	state.map.set_occupant(spot[0], rinne.id)
	state.map.set_object(spot[1].x, spot[1].y, "brazier")
	state.set_ap(3)
	_assert(interaction.interact(rinne, spot[1], "ignite"), "凛音点燃火盆成功")
	_assert(state.team_ap == 2, "凛音点燃耗 1 AP(AP→%d)" % state.team_ap)
	# 清理
	state.map.set_object(spot[1].x, spot[1].y, null)
	state.map.set_occupant(spot[0], null)
	rinne.position = Vector2i(1, 6)
	state.map.set_occupant(rinne.position, rinne.id)

# ---- 9. 焰华「火焰亲和」:火系卡伤害 ×1.5 ----
func _test_homura_fire_damage() -> void:
	var card = Card.get_card("homura_ignite")  # value 6 magic + burn + fire 地形
	_assert(not card.is_empty(), "找到灼烧卡")
	var target = _enemy("paper_effigy")
	_assert(target != null, "找到纸人靶子")
	if target == null:
		return
	var homura = _player("homura")
	var r1: Dictionary = CardResolver.play_card(card, homura, target.position, state.map, state.all_units, state)
	var dmg_homura = int(r1.get("affected_units", [{}])[0].get("damage", 0))
	_assert(dmg_homura == 9, "焰华火系卡伤害 6×1.5=9(实得 %d)" % dmg_homura)
	# 对照:钟馗(无特性)同卡伤害 6
	var target2 = _enemy("paper_effigy")
	if target2 == null:
		print("  [SKIP] 第二个纸人已被击杀,跳过对照")
		return
	var zhongkui = _player("zhongkui")
	var r2: Dictionary = CardResolver.play_card(card, zhongkui, target2.position, state.map, state.all_units, state)
	var dmg_zk = int(r2.get("affected_units", [{}])[0].get("damage", 0))
	_assert(dmg_zk == 6, "钟馗同卡伤害 6 无加成(实得 %d)" % dmg_zk)

# ---- 10. 钟馗「镇邪体魄」:致命伤留 1 HP(限 1 次) ----
func _test_zhongkui_undying() -> void:
	_undying_events.clear()
	var zk = UnitFactory.create("zhongkui", Vector2i(0, 0))
	var hp_before = zk.current_hp
	zk.take_damage(9999)
	_assert(zk.is_alive and zk.current_hp == 1, "钟馗致命伤留 1 HP(HP %d→%d)" % [hp_before, zk.current_hp])
	_assert(zk.undying_used, "镇邪体魄标记已用")
	_assert(_undying_events.size() == 1, "广播 unit:undying_survived")
	# 第二次致命伤 → 正常死亡
	zk.take_damage(9999)
	_assert(not zk.is_alive, "镇邪体魄仅 1 次,再次致命 → 死亡")
	# 对照:凛音无此特性直接死亡
	var rinne2 = UnitFactory.create("rinne", Vector2i(0, 0))
	rinne2.take_damage(9999)
	_assert(not rinne2.is_alive, "凛音无镇邪体魄 → 直接死亡")

# 工具:在地图内找 n 连水平/垂直可走、无单位、无物体的格子序列
func _find_open_line(n: int) -> Array:
	for y in range(state.map.rows):
		for x in range(state.map.cols - n + 1):
			var line = []
			var ok = true
			for i in range(n):
				var c = Vector2i(x + i, y)
				if not state.map.is_walkable(c) or state.map.is_occupied(c) or state.map.get_object(c.x, c.y) != "":
					ok = false
					break
				line.append(c)
			if ok:
				return line
	for x in range(state.map.cols):
		for y in range(state.map.rows - n + 1):
			var line = []
			var ok = true
			for i in range(n):
				var c = Vector2i(x, y + i)
				if not state.map.is_walkable(c) or state.map.is_occupied(c) or state.map.get_object(c.x, c.y) != "":
					ok = false
					break
				line.append(c)
			if ok:
				return line
	return []
