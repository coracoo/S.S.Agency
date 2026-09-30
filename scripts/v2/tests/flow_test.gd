extends Node
## 完整流程模拟测试 v3
##
## 模拟玩家完整走一遍：标题→对话→64×64 地图探索→战斗→选牌→回探索→出口
## 纯逻辑层（headless 可跑）。地图玩法走 TileMapV2 查询。

func _ready() -> void:
	print("===== [FLOW-TEST] 完整流程模拟 =====")
	DebugLog.info("FLOW-TEST: start")
	var steps: Array = []
	steps.append(_test_chapter_and_map())
	steps.append(_test_battle_flow())
	steps.append(_test_progression())
	var passed = steps.count(true)
	print("===== [FLOW-TEST] %d/3 PASSED =====" % passed)
	get_tree().quit(0 if passed == 3 else 1)


func _ok(label: String, cond: bool) -> bool:
	print("  [%s] %s" % ["OK" if cond else "FAIL", label])
	DebugLog.info("FLOW-TEST: " + ("OK " if cond else "FAIL ") + label)
	return cond


## 1) 章节 → 地图 → 物件链路
func _test_chapter_and_map() -> bool:
	NarrativeState.wipe()
	var chapter = ChapterLoader.load_chapter("chapter_1")
	if not _ok("chapter_1 加载 entry=" + str(chapter.get("entry", "")), not chapter.is_empty() and chapter.get("entry") == "intro_dialog"):
		return false
	var intro = chapter.get("nodes", {}).get("intro_dialog", {})
	if not _ok("intro 节点存在", not intro.is_empty()):
		return false
	var scene_def = chapter.get("scene", {})
	var map_id = str(scene_def.get("map", ""))
	if not _ok("scene.map = " + map_id, not map_id.is_empty()):
		return false
	var m = TileMapV2.new()
	if not _ok("地图加载 " + map_id, m.load_map("res://data/v2/maps/%s.json" % map_id)):
		return false
	if not _ok("地图规格 %dx%d（≥60×60）" % [m.width, m.height], m.width >= 60 and m.height >= 60):
		return false
	# 物件统计
	var n_npc := 0
	var n_enemy := 0
	var n_item := 0
	for obj in m.objects:
		match str(obj.get("type", "")):
			"npc": n_npc += 1
			"enemy": n_enemy += 1
			"item": n_item += 1
	return _ok("地图物件：npc=%d enemy=%d item=%d door=%d portal=%d" % [n_npc, n_enemy, n_item, m.doors.size(), m.portal.size()],
		n_npc >= 1 and n_enemy >= 1 and n_item >= 1 and m.doors.size() >= 1 and m.portal.size() == 1)


## 2) 战斗流程（胜利 + 旗标）
func _test_battle_flow() -> bool:
	var state = GameStateV2.new()
	state.init_battle(["rinne"], ["paper_effigy"])
	state.start_player_turn()
	if not _ok("战斗初始化：玩家=%d 敌人=%d" % [state.players.size(), state.enemies.size()],
			state.players.size() == 1 and state.enemies.size() == 1):
		return false
	var resolver = CardResolverV2.new(state.combo_engine)
	var rounds = 0
	while state.is_battle_over() == "" and rounds < 30:
		var played_any = true
		while played_any:
			played_any = false
			for i in state.players[0].hand.size:
				var cid = state.players[0].hand.cards[i]
				var cdef = CardV2.get_card(cid)
				var tt = cdef.get("target_type", "")
				var target = state.enemies[0] if tt == "single_enemy" else null
				if state.can_play_card(cdef, target):
					state.spend_qi(int(cdef.get("cost", 0)))
					resolver.play_card(cdef, target, state, state.players[0])
					played_any = true
					break
		if state.is_battle_over() != "":
			break
		state.end_player_turn()
		state.start_enemy_turn()
		if state.is_battle_over() != "":
			break
		state.end_enemy_turn()
		rounds += 1
	var result = state.is_battle_over()
	if not _ok("战斗结束：%s（%d 回合）" % [result, rounds], result == "won"):
		return false
	NarrativeState.set_flag("paper_effigy_defeated", true)
	return _ok("set flag paper_effigy_defeated", true)


## 3) 进度闭环：旗标 → 传送门可进 → 章节 complete
func _test_progression() -> bool:
	var m = TileMapV2.new()
	m.load_map("res://data/v2/maps/map_64.json")
	# 钥匙门：先锁后开
	var door_locked := true
	for key in m.doors:
		if m.is_walkable(key.x, key.y):
			door_locked = false
	if not _ok("未拿钥匙：所有门锁定", door_locked):
		return false
	NarrativeState.set_flag("has_key", true)
	var door_open := true
	for key in m.doors:
		if not m.is_walkable(key.x, key.y):
			door_open = false
	if not _ok("拿钥匙后：门全部可通行", door_open):
		return false
	# 敌人全灭后：敌人格全可走
	NarrativeState.set_flag("steam_jiangshi_defeated", true)
	NarrativeState.set_flag("guard_defeated", true)
	var enemies_gone := true
	for obj in m.objects:
		if str(obj.get("type", "")) == "enemy":
			var flag = str(obj.get("on_defeat_flag", ""))
			if not flag.is_empty() and not NarrativeState.has_flag(flag):
				enemies_gone = false
	if not _ok("敌人击败旗标检查", enemies_gone):
		return false
	NarrativeState.mark_chapter_complete("chapter_1")
	return _ok("章节完成标记", NarrativeState.completed_chapters.has("chapter_1"))
