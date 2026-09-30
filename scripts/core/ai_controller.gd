class_name AIController
extends RefCounted

var map: GameMap
var all_units: Array
# Utility 选点减分表(Boss 阶段 2 畏惧封印阵),规划开始/结束时置空
var _move_avoid: Dictionary = {}

func _init(gmap: GameMap, units: Array) -> void:
	map = gmap
	all_units = units
	# 执念威胁监听:棺材被打开/推动 → 执念为 coffin 的灵体进 rage(GDD §12.4)
	EventBus.on("coffin:opened", _on_obsession_threat)
	EventBus.on("object:pushed", _on_object_pushed_obsession)

func dispose() -> void:
	EventBus.off("coffin:opened", _on_obsession_threat)
	EventBus.off("object:pushed", _on_object_pushed_obsession)

# 进入 rage:直奔执念目标/威胁者,无视恐惧;广播 ai:state_changed
func _enter_rage(enemy: Unit, target_pos: Vector2i, reason: String) -> void:
	enemy.ai_state = "rage"
	enemy.rage_target_pos = target_pos
	enemy.rage_turns = int(enemy.ai_profile.get("rageTurns", 3))
	EventBus.emit("ai:state_changed", {"unit_id": enemy.id, "state": "rage", "reason": reason})

func _on_obsession_threat(data: Dictionary) -> void:
	# coffin:opened {map,pos,unit_id}:威胁者位置优先,其次棺材位置
	_apply_obsession_rage("coffin", data.get("pos", Vector2i(-1, -1)), "coffin_opened")

func _on_object_pushed_obsession(data: Dictionary) -> void:
	if str(data.get("object_id", "")) == "coffin":
		_apply_obsession_rage("coffin", data.get("to", data.get("from", Vector2i(-1, -1))), "coffin_pushed")

func _apply_obsession_rage(obsession_id: String, threat_pos: Vector2i, reason: String) -> void:
	if threat_pos == Vector2i(-1, -1):
		return
	for e in all_units:
		if e == null or not (e is Unit) or not e.is_alive or e.faction != "enemy":
			continue
		if str(e.ai_profile.get("obsession", "")) != obsession_id:
			continue
		_enter_rage(e, threat_pos, reason)

# 百鬼夜行:灵气 10 时所有灵体进 rage(阶段 1 TODO 的正式实现)
func set_all_spirits_rage(targets: Array, reason: String = "hundred_ghosts") -> void:
	for e in all_units:
		if e == null or not (e is Unit) or not e.is_alive or e.faction != "enemy":
			continue
		if not e.tags.has("spirit"):
			continue
		var goal := Vector2i(-1, -1)
		var nearest = _find_nearest(e, targets)
		if nearest != null:
			goal = nearest.position
		_enter_rage(e, goal, reason)

func generate_turn_plan(enemies: Array, context: Dictionary = {}) -> Dictionary:
	var players: Array = context.get("players", [])
	# Boss 两阶段(GDD §六):HP <= phase2HpFrac → 阶段 2,广播 boss:phase_changed
	for enemy in enemies:
		if enemy == null or not enemy.is_alive:
			continue
		if not bool(enemy.ai_profile.get("bossPhases", false)):
			continue
		if enemy.boss_phase == 1 and enemy.current_hp <= int(enemy.max_hp * float(enemy.ai_profile.get("phase2HpFrac", 0.5))):
			enemy.boss_phase = 2
			# 阶段 2:全图追击,无视噪音吸引(脱离 rage 状态字眼,用 chase 全图)
			enemy.ai_state = "chase"
			EventBus.emit("boss:phase_changed", {"unit_id": enemy.id, "phase": 2, "pos": enemy.position})
	# 阶段 1 指挥:每 commandEvery 回合给纸人下 rage 指令(直奔最近玩家)
	for enemy in enemies:
		if enemy == null or not enemy.is_alive or not bool(enemy.ai_profile.get("bossPhases", false)):
			continue
		if enemy.boss_phase != 1:
			continue
		var every = int(enemy.ai_profile.get("commandEvery", 3))
		if every > 0 and int(context.get("turn", 0)) % every == 0:
			for e in enemies:
				if e == null or not e.is_alive or e == enemy:
					continue
				# 指挥对象:带 minion 标签的随从(数据驱动,不写死敌人名)
				if e.tags.has("minion") and e.ai_state != "rage":
					var nearest = _find_nearest(e, players)
					if nearest != null:
						_enter_rage(e, nearest.position, "boss_command")
	var plans = []
	for enemy in enemies:
		if enemy == null or not enemy.is_alive:
			continue
		var plan = generate_enemy_plan(enemy, context)
		plans.append(plan)
	return {
		"turn": int(context.get("turn", 0)),
		"phase": "intent",
		"plans": plans,
		"players": players,
	}

func generate_enemy_plan(enemy: Unit, context: Dictionary = {}) -> Dictionary:
	var players: Array = context.get("players", [])
	var actions = []
	_update_ai_state(enemy, context)
	var behavior = _get_behavior(enemy)
	var reason = "default"
	var plan_state = enemy.ai_state

	# ---- 0. confused:随机移动,回合数耗尽后恢复(GDD §12.4) ----
	if enemy.confused_turns > 0:
		enemy.confused_turns -= 1
		var wander = _random_move_action(enemy)
		if not wander.is_empty():
			actions.append(wander)
		if enemy.confused_turns <= 0:
			enemy.ai_state = str(enemy.ai_profile.get("defaultState", "patrol"))
			EventBus.emit("ai:state_changed", {"unit_id": enemy.id, "state": enemy.ai_state, "reason": "confused_recovered"})
		return _make_enemy_plan(enemy, "confused", behavior, "talisman_confused", actions)

	# ---- 0.5 符纸混乱触发:灵体站在 talisman 格上 → confused(GDD:被符纸影响) ----
	if enemy.tags.has("spirit") and map.has_tag(enemy.position.x, enemy.position.y, "talisman"):
		enemy.confused_turns = 2
		enemy.ai_state = "confused"
		EventBus.emit("ai:state_changed", {"unit_id": enemy.id, "state": "confused", "reason": "talisman"})
		return _make_enemy_plan(enemy, "confused", behavior, "talisman_confused", actions)

	# ---- 0.8 关卡侦查期:带 minion 标签的敌人强制巡逻不追击(GDD §八 三阶段流程) ----
	if str(context.get("level_stage", "")) == "recon" and enemy.tags.has("minion"):
		var recon_patrol = _patrol_action(enemy)
		if not recon_patrol.is_empty():
			actions.append(recon_patrol)
		return _make_enemy_plan(enemy, "patrol", behavior, "level_recon", actions)

	# ---- 1. rage:无视恐惧,直奔执念目标/威胁者;rage_turns 耗尽后冷静 ----
	if enemy.ai_state == "rage":
		enemy.rage_turns -= 1
		if enemy.rage_turns <= 0:
			enemy.ai_state = str(enemy.ai_profile.get("defaultState", "patrol"))
			enemy.rage_target_pos = Vector2i(-1, -1)
			EventBus.emit("ai:state_changed", {"unit_id": enemy.id, "state": enemy.ai_state, "reason": "rage_calmed"})
			# 冷静后本回合按正常流程继续规划(不 return)
		else:
			var goal = enemy.rage_target_pos
			var nearest_p = _find_nearest(enemy, players)
			if goal == Vector2i(-1, -1) and nearest_p != null:
				goal = nearest_p.position
			var rage_atk = _find_attack_target_from_pos(enemy, players, behavior, enemy.position)
			if rage_atk != null:
				actions.append(_make_attack_action(enemy, enemy.position, rage_atk, behavior))
			elif goal != Vector2i(-1, -1) and enemy.position != goal:
				var rage_mt = _move_toward_pos(enemy, goal, enemy.move_range)
				if rage_mt != null:
					var rage_path = Pathfinding.find_path(map, enemy.position, rage_mt)
					if rage_path.size() >= 2:
						actions.append(_make_move_action(enemy, enemy.position, rage_mt, rage_path, "rage"))
			return _make_enemy_plan(enemy, "rage", behavior, "obsession", actions)

	# ---- 2. fear:逃离恐惧源 ----
	if enemy.ai_state == "fear":
		var fear_pos = _find_nearest_tagged_cell(enemy, enemy.ai_profile.get("fearTags", []), int(enemy.ai_profile.get("fearRange", 3)))
		var escape_pos = _move_away_from_pos(enemy, fear_pos) if fear_pos != Vector2i(-1, -1) else null
		if escape_pos != null:
			var escape_path = Pathfinding.find_path(map, enemy.position, escape_pos)
			if escape_path.size() >= 2:
				actions.append(_make_move_action(enemy, enemy.position, escape_pos, escape_path, "fear"))
		reason = "fear_source" if fear_pos != Vector2i(-1, -1) else "fear"
		return _make_enemy_plan(enemy, plan_state, behavior, reason, actions)

	# ---- 3. 红衣女:静止→被注视→瞬移到注视者背后攻击(GDD §四) ----
	if bool(enemy.ai_profile.get("teleportWhenWatched", false)):
		var watcher = _find_watcher(enemy, players)
		if watcher == null:
			# 无注视时完全静止(背对她安全)
			return _make_enemy_plan(enemy, "idle_watch", behavior, "not_watched", actions)
		var tp_dest = _find_teleport_dest(enemy, watcher)
		if tp_dest != null:
			actions.append({
				"type": "teleport", "unit_id": enemy.id,
				"from": enemy.position, "to": tp_dest,
				"target_id": watcher.id, "target_pos": watcher.position,
				"attack_kind": behavior,
			})
			actions.append(_make_attack_action(enemy, tp_dest, watcher, behavior))
		return _make_enemy_plan(enemy, "teleport", behavior, "watched", actions)

	# ---- 4. search:被噪音吸引 ----
	if enemy.ai_state == "search" and enemy.search_target != Vector2i(-1, -1):
		var search_pos = _move_toward_pos(enemy, enemy.search_target, enemy.move_range)
		if search_pos != null:
			var search_path = Pathfinding.find_path(map, enemy.position, search_pos)
			if search_path.size() >= 2:
				actions.append(_make_move_action(enemy, enemy.position, search_pos, search_path, "search"))
		enemy.search_turns -= 1
		if enemy.search_turns <= 0 or enemy.position == enemy.search_target:
			enemy.ai_state = enemy.ai_profile.get("defaultState", "patrol")
		reason = "noise"
		return _make_enemy_plan(enemy, plan_state, behavior, reason, actions)

	# ---- 5. 水鬼拖拽:相邻玩家 → 拉入水中(GDD §四) ----
	if bool(enemy.ai_profile.get("dragAdjacent", false)):
		var drag_target = _find_adjacent_player(enemy, players)
		if drag_target != null:
			var drag_dest = _find_drag_dest(enemy)
			if drag_dest != null:
				actions.append({
					"type": "drag", "unit_id": enemy.id,
					"from": enemy.position,
					"target_id": drag_target.id, "target_pos": drag_dest,
					"attack_kind": behavior,
				})
				return _make_enemy_plan(enemy, "drag", behavior, "drag", actions)

	# ---- 5.9 棺材主逃脱(GDD §八):逃脱激活(决战期+灵气低于封印阈值)时向最近门格移动 ----
	var escape_info: Dictionary = context.get("level_escape", {})
	if bool(enemy.ai_profile.get("bossPhases", false)) and bool(escape_info.get("active", false)):
		var door: Vector2i = escape_info.get("door", Vector2i(-1, -1))
		if door != Vector2i(-1, -1):
			# 不用 _move_toward_pos(它要求严格更近):被包围绕行时曼哈顿距离可能不减,但仍是进展
			var reachable = Pathfinding.get_reachable_tiles(map, enemy.position, enemy.move_range)
			var esc_best = null
			var esc_best_d = 1 << 30
			for pos in reachable:
				if pos == enemy.position:
					continue
				var d = _manhattan(pos, door)
				if d < esc_best_d:
					esc_best_d = d
					esc_best = pos
			if esc_best != null:
				var esc_path = Pathfinding.find_path(map, enemy.position, esc_best)
				if esc_path.size() >= 2:
					actions.append(_make_move_action(enemy, enemy.position, esc_best, esc_path, "escape"))
		return _make_enemy_plan(enemy, "escape", behavior, "boss_escape", actions)

	# ---- 6. chase/attack(含 Boss 阶段差异、僵尸跳跃、水鬼离水变弱) ----
	var target = _find_target(enemy, players, behavior)
	if target == null:
		# 视野内无目标 → 沿巡逻路径循环(GDD:巡逻→发现→追击)
		var patrol = _patrol_action(enemy)
		if not patrol.is_empty():
			actions.append(patrol)
			return _make_enemy_plan(enemy, "patrol", behavior, "patrol", actions)
		return _make_enemy_plan(enemy, plan_state, behavior, "no_target", actions)

	# Boss 阶段 1:固守棺材旁,只在攻击范围内出手,不追击
	if bool(enemy.ai_profile.get("bossPhases", false)) and enemy.boss_phase == 1:
		var hold_atk = _find_attack_target_from_pos(enemy, players, behavior, enemy.position)
		if hold_atk != null:
			actions.append(_make_attack_action(enemy, enemy.position, hold_atk, behavior))
		return _make_enemy_plan(enemy, "defend", behavior, "boss_phase1", actions)

	# 水鬼离水 >weakAwayRange 格:移速/伤害减半(GDD §四)
	var move_budget = enemy.move_range
	var weakened := false
	if bool(enemy.ai_profile.get("waterLurk", false)):
		weakened = _is_away_from_home(enemy)
		if weakened:
			move_budget = maxi(1, enemy.move_range / 2)

	# Boss 阶段 2 畏惧封印阵:避开激活阵眼相邻格(Utility 减分)
	_move_avoid = {}
	if bool(enemy.ai_profile.get("fearSealPoints", false)) and enemy.boss_phase >= 2:
		_move_avoid = _compute_seal_avoid()

	# 僵尸直线跳跃:同排/列且距离 >= leapRange+1 时跳 2 格(可越 1 格低矮物体)
	if bool(enemy.ai_profile.get("leapMove", false)):
		var leap = _make_leap_action(enemy, target)
		if not leap.is_empty():
			actions.append(leap)
			var leap_atk = _find_attack_target_from_pos(enemy, players, behavior, leap.get("to", enemy.position))
			if leap_atk != null:
				var leap_act = _make_attack_action(enemy, leap.get("to", enemy.position), leap_atk, behavior)
				if weakened:
					leap_act["damage_mult"] = 0.5
				actions.append(leap_act)
			return _make_enemy_plan(enemy, "chase", behavior, "leap", actions)

	var move_target = _find_move_target(enemy, target, behavior)
	var attack_from = enemy.position
	if move_target != null:
		var move_path = Pathfinding.find_path(map, enemy.position, move_target)
		if move_path.size() >= 2:
			actions.append(_make_move_action(enemy, enemy.position, move_target, move_path, "move"))
			attack_from = move_target

	var attack_target = _find_attack_target_from_pos(enemy, players, behavior, attack_from)
	if attack_target != null:
		var atk_act = _make_attack_action(enemy, attack_from, attack_target, behavior)
		if weakened:
			atk_act["damage_mult"] = 0.5
		actions.append(atk_act)
		plan_state = "attack" if attack_from == enemy.position else "chase"
		enemy.ai_state = plan_state
	else:
		plan_state = "chase"
		enemy.ai_state = plan_state
	reason = "target_visible"
	_move_avoid = {}
	return _make_enemy_plan(enemy, plan_state, behavior, reason, actions)

func generate_intents(turn_plan: Dictionary) -> Array:
	var intents = []
	for plan in turn_plan.get("plans", []):
		for action in plan.get("actions", []):
			var kind = action.get("type", "")
			if kind == "move":
				intents.append({
					"type": "move",
					"unit_id": plan.get("unit_id", ""),
					"from": action.get("from", Vector2i(-1, -1)),
					"to": action.get("to", Vector2i(-1, -1)),
					"path": action.get("path", []),
					"intent_style": action.get("intent_style", "move"),
					"state": plan.get("state", ""),
				})
			elif kind == "attack":
				intents.append({
					"type": "attack",
					"unit_id": plan.get("unit_id", ""),
					"from": action.get("from", Vector2i(-1, -1)),
					"to": action.get("to", Vector2i(-1, -1)),
					"target_id": action.get("target_id", ""),
					"behavior": action.get("attack_kind", plan.get("behavior", "melee")),
					"state": plan.get("state", ""),
				})
			elif kind == "drag":
				# 拖拽:红箭头指向目标玩家(语义=攻击)
				intents.append({
					"type": "attack",
					"unit_id": plan.get("unit_id", ""),
					"from": action.get("from", Vector2i(-1, -1)),
					"to": action.get("target_pos", Vector2i(-1, -1)),
					"target_id": action.get("target_id", ""),
					"behavior": action.get("attack_kind", plan.get("behavior", "melee")),
					"state": plan.get("state", ""),
				})
			# teleport 不单独出意图:紧随的 attack 动作已从落点画出攻击箭头
	return intents

func plan_turn(enemies: Array, players: Array) -> Array:
	var turn_plan = generate_turn_plan(enemies, {"players": players})
	return flatten_plan_actions(turn_plan)

func flatten_plan_actions(turn_plan: Dictionary) -> Array:
	var actions = []
	for plan in turn_plan.get("plans", []):
		var unit_id = str(plan.get("unit_id", ""))
		for action in plan.get("actions", []):
			if action.get("type", "") == "move":
				actions.append({
					"type": "move",
					"unit_id": unit_id,
					"target_pos": action.get("to", Vector2i(-1, -1)),
					"path": action.get("path", []),
					"intent_style": action.get("intent_style", "move"),
					"leap": bool(action.get("leap", false)),
				})
			elif action.get("type", "") == "attack":
				actions.append({
					"type": "attack",
					"unit_id": unit_id,
					"target_id": action.get("target_id", ""),
					"target_pos": action.get("to", Vector2i(-1, -1)),
					"attack_kind": action.get("attack_kind", plan.get("behavior", "melee")),
					"damage_mult": float(action.get("damage_mult", 1.0)),
				})
			elif action.get("type", "") == "teleport":
				actions.append({
					"type": "teleport",
					"unit_id": unit_id,
					"target_pos": action.get("to", Vector2i(-1, -1)),
					"target_id": action.get("target_id", ""),
				})
			elif action.get("type", "") == "drag":
				actions.append({
					"type": "drag",
					"unit_id": unit_id,
					"target_id": action.get("target_id", ""),
					"target_pos": action.get("target_pos", Vector2i(-1, -1)),
					"attack_kind": action.get("attack_kind", plan.get("behavior", "melee")),
				})
	return actions

# 锁定计划的可执行性检查(GDD §三:敌方回合按预览执行,除非被打断)。
# 返回 {"ok": bool, "reason": String}:dead=单位已死亡,fear=锁定后被恐惧打断。
func is_action_executable(action: Dictionary, game_state: GameState) -> Dictionary:
	var enemy = game_state.get_unit_by_id(str(action.get("unit_id", "")))
	if enemy == null or not enemy.is_alive:
		return {"ok": false, "reason": "dead"}
	# 锁定后进入恐惧(火焰/糯米等地形规则触发)且该动作不是恐惧逃逸 → 打断
	if enemy.ai_state == "fear" and str(action.get("intent_style", "")) != "fear":
		return {"ok": false, "reason": "fear"}
	return {"ok": true, "reason": ""}

# 红衣女注视判定:玩家在 watchRange 内且 facing 正对红衣女 → 返回注视者
func _find_watcher(enemy: Unit, players: Array) -> Unit:
	var watch_range = int(enemy.ai_profile.get("watchRange", 5))
	for p in players:
		if p == null or not p.is_alive:
			continue
		var d = _manhattan(p.position, enemy.position)
		if d == 0 or d > watch_range:
			continue
		var diff = enemy.position - p.position
		var dir := Vector2i.ZERO
		if absi(diff.x) >= absi(diff.y):
			dir = Vector2i.RIGHT if diff.x > 0 else Vector2i.LEFT
		else:
			dir = Vector2i.DOWN if diff.y > 0 else Vector2i.UP
		if dir == p.facing:
			return p
	return null

# 瞬移落点:优先注视者背后,其次任意相邻可行走空格
func _find_teleport_dest(enemy: Unit, watcher: Unit) -> Variant:
	var behind = watcher.position - watcher.facing
	if map.in_bounds(behind) and map.is_walkable(behind) and not map.is_occupied(behind):
		return behind
	for n in map.get_neighbors(watcher.position):
		if map.is_walkable(n) and not map.is_occupied(n):
			return n
	return null

# 水鬼拖拽落点:优先相邻水域格;只有一格水时返回自身格(与玩家换位,把玩家拉进水里)
func _find_drag_dest(enemy: Unit) -> Variant:
	var home_tags: Array = enemy.ai_profile.get("homeTags", ["liquid"])
	for n in map.get_neighbors(enemy.position):
		if not map.is_walkable(n) or map.is_occupied(n):
			continue
		for tag in home_tags:
			if map.has_tag(n.x, n.y, str(tag)):
				return n
	for tag in home_tags:
		if map.has_tag(enemy.position.x, enemy.position.y, str(tag)):
			return enemy.position
	return null

func _find_adjacent_player(enemy: Unit, players: Array) -> Unit:
	for p in players:
		if p == null or not p.is_alive:
			continue
		if _manhattan(p.position, enemy.position) == 1:
			return p
	return null

# 水鬼离水判定:weakAwayRange 格内无 homeTags 地形 → 变弱
func _is_away_from_home(enemy: Unit) -> bool:
	var home_tags: Array = enemy.ai_profile.get("homeTags", ["liquid"])
	var away = int(enemy.ai_profile.get("weakAwayRange", 2))
	for dy in range(-away, away + 1):
		for dx in range(-away, away + 1):
			if absi(dx) + absi(dy) > away:
				continue
			var pos = enemy.position + Vector2i(dx, dy)
			if not map.in_bounds(pos):
				continue
			for tag in home_tags:
				if map.has_tag(pos.x, pos.y, str(tag)):
					return false
	return true

# 僵尸直线跳跃:同排/列、距离 >= leapRange+1,跳 2 格;
# 中间格只要不是阻挡地形/无单位即可越过(物体视为"低矮物体",GDD §四)
func _make_leap_action(enemy: Unit, target: Unit) -> Dictionary:
	var leap_range = int(enemy.ai_profile.get("leapRange", 2))
	var diff = target.position - enemy.position
	if diff.x != 0 and diff.y != 0:
		return {}
	var dist = _manhattan(enemy.position, target.position)
	if dist < leap_range + 1:
		return {}
	var dir := Vector2i(signi(diff.x), 0) if diff.x != 0 else Vector2i(0, signi(diff.y))
	var dest = enemy.position + dir * leap_range
	var mid = enemy.position + dir
	if not map.in_bounds(dest) or not map.is_walkable(dest) or map.is_occupied(dest):
		return {}
	# 中间格只看地形级阻挡(墙);物体视为可跃过的"低矮物体"(GDD §四)
	var mid_terrain: Dictionary = map.terrains_data.get(map.get_terrain(mid.x, mid.y), {})
	if not map.in_bounds(mid) or int(mid_terrain.get("move_cost", 1)) >= 99 or mid_terrain.get("tags", []).has("blocking") or map.is_occupied(mid):
		return {}
	if enemy.remaining_move < 1:
		return {}
	return {
		"type": "move", "unit_id": enemy.id,
		"from": enemy.position, "to": dest,
		"path": [enemy.position, dest],
		"intent_style": "leap", "leap": true,
	}

# confused 随机游走:随机相邻可行走格
func _random_move_action(enemy: Unit) -> Dictionary:
	var options = []
	for n in map.get_neighbors(enemy.position):
		if map.is_walkable(n) and not map.is_occupied(n):
			options.append(n)
	if options.is_empty():
		return {}
	var dest = options[randi() % options.size()]
	return _make_move_action(enemy, enemy.position, dest, [enemy.position, dest], "confused")

# 巡逻:沿 patrolPath 路径点循环,到点即取下一点
func _patrol_action(enemy: Unit) -> Dictionary:
	var pts: Array = enemy.ai_profile.get("patrolPath", [])
	if pts.is_empty():
		return {}
	var idx = enemy.patrol_index % pts.size()
	var wp = Vector2i(int(pts[idx][0]), int(pts[idx][1]))
	if enemy.position == wp:
		enemy.patrol_index += 1
		idx = enemy.patrol_index % pts.size()
		wp = Vector2i(int(pts[idx][0]), int(pts[idx][1]))
	var mt = _move_toward_pos(enemy, wp, enemy.move_range)
	if mt == null:
		return {}
	var path = Pathfinding.find_path(map, enemy.position, mt)
	if path.size() < 2:
		return {}
	return _make_move_action(enemy, enemy.position, mt, path, "patrol")

# 激活阵眼(seal_point + talisman)及其相邻格 → Boss 阶段 2 的 Utility 减分表
func _compute_seal_avoid() -> Dictionary:
	var avoid := {}
	for row in range(map.rows):
		for col in range(map.cols):
			if not map.has_tag(col, row, "seal_point"):
				continue
			var activated := false
			for eff in map.get_effects(col, row):
				if eff.type == "talisman":
					activated = true
					break
			if not activated:
				continue
			var cell := Vector2i(col, row)
			avoid[cell] = true
			for n in map.get_neighbors(cell):
				avoid[n] = true
	return avoid

func _make_enemy_plan(enemy: Unit, plan_state: String, behavior: String, reason: String, actions: Array) -> Dictionary:
	return {
		"unit_id": enemy.id,
		"template_id": enemy.template_id,
		"state": plan_state,
		"behavior": behavior,
		"reason": reason,
		"actions": actions,
	}

func _make_move_action(enemy: Unit, from_pos: Vector2i, to_pos: Vector2i, path: Array, intent_style: String) -> Dictionary:
	return {
		"type": "move",
		"unit_id": enemy.id,
		"from": from_pos,
		"to": to_pos,
		"path": path,
		"intent_style": intent_style,
	}

func _make_attack_action(enemy: Unit, from_pos: Vector2i, target: Unit, behavior: String) -> Dictionary:
	return {
		"type": "attack",
		"unit_id": enemy.id,
		"from": from_pos,
		"to": target.position,
		"target_id": target.id,
		"attack_kind": behavior,
	}

func _update_ai_state(enemy: Unit, context: Dictionary = {}) -> void:
	# rage 期间无视恐惧与噪音(GDD §12.4)
	if enemy.ai_state == "rage":
		return
	# Boss 阶段 2:全图追击,无视噪音吸引
	var ignore_noise = bool(enemy.ai_profile.get("bossPhases", false)) and enemy.boss_phase >= 2
	var fear_tags = enemy.ai_profile.get("fearTags", [])
	var fear_range = int(enemy.ai_profile.get("fearRange", 0))
	if fear_range > 0 and not fear_tags.is_empty():
		if _find_nearest_tagged_cell(enemy, fear_tags, fear_range) != Vector2i(-1, -1):
			enemy.ai_state = "fear"
			return
	if not ignore_noise:
		for noise in context.get("noise_events", []):
			var pos: Vector2i = noise.get("pos", Vector2i(-1, -1))
			var volume = int(noise.get("volume", 0))
			var hearing = int(enemy.ai_profile.get("noiseHearing", 0))
			var noise_map: Dictionary = noise.get("noise_map", {})
			var propagated_value = int(noise_map.get(enemy.position, 0))
			var heard_by_map = propagated_value > 0 and propagated_value <= volume and propagated_value + hearing >= volume
			var heard_by_fallback = pos != Vector2i(-1, -1) and _manhattan(enemy.position, pos) <= mini(volume, hearing)
			if hearing > 0 and (heard_by_map or heard_by_fallback):
				# GDD §12.1 阈值:音量 ≥5 且 fear_noise 高(≥0.5)→ 巨响恐惧;音量 ≥3 → 吸引 Search
				if volume >= 5 and float(enemy.ai_profile.get("fear_noise", 0.0)) >= 0.5:
					enemy.ai_state = "fear"
					return
				if volume >= 3:
					enemy.ai_state = "search"
					enemy.search_target = pos
					enemy.search_turns = 2
					return
	if enemy.ai_state == "fear":
		enemy.ai_state = enemy.ai_profile.get("defaultState", "patrol")

func _get_behavior(enemy: Unit) -> String:
	var configured = enemy.ai_profile.get("behavior", "")
	if configured != "":
		return configured
	var tid = enemy.template_id
	if tid.find("archer") >= 0:
		return "ranged"
	if tid.find("knight") >= 0:
		return "tank"
	if tid.find("mage") >= 0:
		return "mage"
	return "melee"

func _find_target(enemy: Unit, players: Array, behavior: String) -> Unit:
	# 视野限制(GDD:巡逻→发现→追击):超出 sightRange 的玩家不可见
	var sight = int(enemy.ai_profile.get("sightRange", 99))
	var alive = []
	for p in players:
		if p.is_alive and _manhattan(enemy.position, p.position) <= sight:
			alive.append(p)
	if alive.is_empty():
		return null

	if behavior == "mage":
		var best = alive[0]
		for p in alive:
			if p.current_hp < best.current_hp:
				best = p
		return best
	return _find_nearest(enemy, alive)

func _find_move_target(enemy: Unit, target: Unit, behavior: String) -> Variant:
	var dist = _manhattan(enemy.position, target.position)

	if behavior == "ranged":
		if dist >= 3 and dist <= 4:
			return null
		if dist > 4:
			return _move_toward(enemy, target, maxi(1, dist - 3))
		return _move_away(enemy, target)

	if behavior == "mage":
		if dist >= 2 and dist <= 3:
			return null
		if dist > 3:
			return _move_toward(enemy, target, maxi(1, dist - 2))
		return _move_away(enemy, target)

	if dist <= 1:
		return null
	return _move_toward(enemy, target, enemy.move_range)

func _find_attack_target_from_pos(enemy: Unit, players: Array, behavior: String, from_pos: Vector2i) -> Unit:
	var targets = []
	var range_limit = _attack_range_for_behavior(behavior)
	for player in players:
		if player == null or not player.is_alive:
			continue
		if behavior == "ranged" or behavior == "mage":
			if _manhattan(player.position, from_pos) <= range_limit:
				targets.append(player)
		elif _manhattan(player.position, from_pos) <= 1:
			targets.append(player)
	if targets.is_empty():
		return null
	var best = targets[0]
	for target in targets:
		if target.current_hp < best.current_hp:
			best = target
	return best

func _attack_range_for_behavior(behavior: String) -> int:
	if behavior == "ranged":
		return 4
	if behavior == "mage":
		return 3
	return 1

func _move_toward(enemy: Unit, target: Unit, max_steps: int) -> Variant:
	return _move_toward_pos(enemy, target.position, max_steps, target)

func _move_toward_pos(enemy: Unit, target_pos: Vector2i, max_steps: int, target_unit: Unit = null) -> Variant:
	max_steps = mini(max_steps, enemy.move_range)
	var reachable = Pathfinding.get_reachable_tiles(map, enemy.position, max_steps)
	if reachable.is_empty():
		return null
	var best_pos = null
	var best_score = -9999.0
	for pos in reachable:
		var score = -float(_manhattan(pos, target_pos))
		# 畏惧封印阵等 Utility 减分(Boss 阶段 2)
		if _move_avoid.has(pos):
			score -= 100.0
		var dist = _manhattan(pos, target_pos)
		if target_unit != null and dist <= 1:
			var atk_dir = target_unit.position - pos
			var card_dir := Vector2i.ZERO
			if absi(atk_dir.x) >= absi(atk_dir.y):
				card_dir = Vector2i.RIGHT if atk_dir.x > 0 else Vector2i.LEFT
			else:
				card_dir = Vector2i.DOWN if atk_dir.y > 0 else Vector2i.UP
			if card_dir == -target_unit.facing:
				score += 5.0
			elif card_dir != target_unit.facing:
				score += 3.0
		if score > best_score:
			best_score = score
			best_pos = pos
	var current_score = -float(_manhattan(enemy.position, target_pos))
	if best_score <= current_score:
		return null
	return best_pos

func _move_away(enemy: Unit, threat: Unit) -> Variant:
	return _move_away_from_pos(enemy, threat.position)

func _move_away_from_pos(enemy: Unit, threat_pos: Vector2i) -> Variant:
	var reachable = Pathfinding.get_reachable_tiles(map, enemy.position, enemy.move_range)
	if reachable.is_empty():
		return null
	var best_pos = null
	var best_dist = 0
	for pos in reachable:
		var d = _manhattan(pos, threat_pos)
		if d > best_dist:
			best_dist = d
			best_pos = pos
	var current_dist = _manhattan(enemy.position, threat_pos)
	if best_dist <= current_dist:
		return null
	return best_pos

func _find_nearest_tagged_cell(enemy: Unit, tags: Array, max_range: int) -> Vector2i:
	for dist in range(0, max_range + 1):
		for dy in range(-dist, dist + 1):
			var max_dx = dist - absi(dy)
			for dx in [-max_dx, max_dx]:
				var pos = enemy.position + Vector2i(dx, dy)
				if not map.in_bounds(pos):
					continue
				for tag in tags:
					if map.has_tag(pos.x, pos.y, tag):
						return pos
	return Vector2i(-1, -1)

func _find_nearest(unit: Unit, targets: Array) -> Unit:
	var best = null
	var best_dist = 9999
	for t in targets:
		if not t.is_alive:
			continue
		var d = _manhattan(unit.position, t.position)
		if d < best_dist:
			best_dist = d
			best = t
	return best

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _update_facing(unit: Unit, target_pos: Vector2i) -> void:
	var diff = target_pos - unit.position
	if diff == Vector2i.ZERO:
		return
	if absi(diff.x) >= absi(diff.y):
		unit.facing = Vector2i.RIGHT if diff.x > 0 else Vector2i.LEFT
	else:
		unit.facing = Vector2i.DOWN if diff.y > 0 else Vector2i.UP
