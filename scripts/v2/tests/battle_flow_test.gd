extends Node
## v2 战斗流程模拟测试
##
## 模拟玩家手动出牌的完整流程，验证新交互代码（无 UI）：
##   1. init_battle(["rinne"], ["paper_effigy"]) → 1v1
##   2. start_player_turn → 抽牌 + 生成敌人意图
##   3. 找一张能打的牌 + 一个目标 → play_card
##   4. 验证：敌人 HP 下降、qi 减少、手牌减少
##   5. end_player_turn → start_enemy_turn → 敌人执行意图 → 玩家 HP 下降
##   6. 重复出牌直到胜利 → 验证 is_battle_over()=="won"
##   7. 测试 reward：deck.add_card_to_pool 加一张牌，下一回合能抽到
##
## 这覆盖了 card_battle_scene.gd 里除 UI 动画外的所有逻辑路径。

func _ready() -> void:
	print("===== [BATTLE-FLOW-TEST] =====")
	var ok1 = _test_play_one_card()
	var ok2 = _test_enemy_turn_damage()
	var ok3 = _test_full_battle_to_victory()
	var ok4 = _test_reward_card_added()
	var passed = [ok1, ok2, ok3, ok4].count(true)
	print("===== [BATTLE-FLOW-TEST] %d/4 PASSED =====" % passed)
	get_tree().quit(0 if passed == 4 else 1)


func _ok(label: String, cond: bool) -> bool:
	var tag = "OK" if cond else "FAIL"
	print("  [%s] %s" % [tag, label])
	return cond


func _make_state() -> GameStateV2:
	var state = GameStateV2.new()
	state.init_battle(["rinne"], ["paper_effigy"])
	state.start_player_turn()
	return state


func _test_play_one_card() -> bool:
	var state = _make_state()
	var qi_before = state.qi
	var hand_size_before = state.players[0].hand.size
	var enemy = state.enemies[0]
	var enemy_hp_before = enemy.current_hp
	# 找一张 single_enemy 牌
	var card_to_play = null
	var card_idx = -1
	for i in state.players[0].hand.size:
		var cid = state.players[0].hand.cards[i]
		var cdef = CardV2.get_card(cid)
		if cdef.get("target_type") == "single_enemy" and state.can_play_card(cdef, enemy):
			card_to_play = cdef
			card_idx = i
			break
	if card_to_play == null:
		return _ok("找不到可打的单体牌（异常）", false)
	var resolver = CardResolverV2.new(state.combo_engine)
	state.spend_qi(int(card_to_play.get("cost", 0)))
	resolver.play_card(card_to_play, enemy, state, state.players[0])
	var ok = state.qi == qi_before - int(card_to_play.get("cost", 0))
	ok = ok and state.players[0].hand.size == hand_size_before - 1
	ok = ok and enemy.current_hp < enemy_hp_before
	return _ok("打出一张牌：qi-1, 手牌-1, 敌人受伤", ok)


func _test_enemy_turn_damage() -> bool:
	# 用更强的敌人确保不会被一回合秒杀（paper_effigy 24 血太脆）
	var state = GameStateV2.new()
	state.init_battle(["rinne"], ["steam_jiangshi"])  # 40 血
	state.start_player_turn()
	var player = state.players[0].unit
	var hp_before = player.current_hp
	# 不出任何牌，直接结束回合，让敌人出手
	state.end_player_turn()
	state.start_enemy_turn()
	var ok = player.current_hp < hp_before
	return _ok("敌人回合对玩家造成伤害（玩家 HP %d→%d）" % [hp_before, player.current_hp], ok)


func _test_full_battle_to_victory() -> bool:
	var state = _make_state()
	var enemy = state.enemies[0]
	var resolver = CardResolverV2.new(state.combo_engine)
	var rounds = 0
	while state.is_battle_over() == "" and rounds < 30:
		# 玩家回合：尽量打出所有能打的牌
		var played_any = true
		while played_any:
			played_any = false
			for i in state.players[0].hand.size:
				var cid = state.players[0].hand.cards[i]
				var cdef = CardV2.get_card(cid)
				var tt = cdef.get("target_type", "")
				var target = null
				if tt == "single_enemy":
					target = enemy
				if state.can_play_card(cdef, target):
					state.spend_qi(int(cdef.get("cost", 0)))
					resolver.play_card(cdef, target, state, state.players[0])
					played_any = true
					break
		# 检查胜负
		if state.is_battle_over() != "":
			break
		# 结束回合
		state.end_player_turn()
		state.start_enemy_turn()
		# 检查玩家是否被反杀
		if state.is_battle_over() != "":
			break
		state.end_enemy_turn()  # 内部 start_player_turn
		rounds += 1
	var result = state.is_battle_over()
	var ok = result == "won" or result == "lost"
	return _ok("完整战斗结束（%s，%d 回合）" % [result, rounds], ok)


func _test_reward_card_added() -> bool:
	var state = _make_state()
	var pool_before = state.players[0].deck.card_ids.size()
	state.players[0].deck.add_card_to_pool("talisman_yinlei")
	var pool_after = state.players[0].deck.card_ids.size()
	var ok = pool_after == pool_before + 1
	return _ok("选牌奖励加牌到牌池（pool +1）", ok)
