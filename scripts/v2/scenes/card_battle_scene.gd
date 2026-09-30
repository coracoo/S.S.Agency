extends Control
## 卡牌战斗场景 v2
##
## 立绘对峙式 StS 布局。本版本实现完整交互闭环：
##   点手牌 → 高亮 → 点敌人立绘 → 出牌 → 灵气扣除 → 伤害飘字 → 受击动画
##   → 结束回合 → 敌人逐个执行意图（带节奏感飘字）→ 胜负判定 → 选牌奖励 / 回对话
##
## 视觉反馈用 Tween（modulate 闪烁/前冲）+ 飘字层，不依赖粒子系统。
## 卡牌池单位视图用 signal 自动刷新 HP，不需要整体重建。

const CombatantView = preload("res://scripts/v2/ui/combatant_view.gd")
const CardView = preload("res://scripts/v2/ui/card_view.gd")
const FloatingTextLayer = preload("res://scripts/v2/ui/floating_text_layer.gd")
const RewardScreen = preload("res://scenes/v2/reward.tscn")

@onready var enemy_zone: HBoxContainer = $EnemyZone
@onready var player_zone: HBoxContainer = $PlayerZone
@onready var hand_zone: HBoxContainer = $HandZone
@onready var qi_label: Label = $QiLabel
@onready var end_turn_btn: Button = $EndTurnBtn
@onready var battle_log: RichTextLabel = $BattleLog
@onready var turn_indicator: Label = $TurnIndicator

var state: GameStateV2
var resolver: CardResolverV2
var chapter_id: String = ""
var battle_node_id: String = ""

var _selected_hand_index: int = -1
var _floating_layer: FloatingTextLayer
var _enemy_views: Dictionary = {}  # unit_id → CombatantView
var _player_views: Dictionary = {}  # unit_id → CombatantView
var _busy: bool = false  # 动画/敌人回合进行中，禁用输入


func _ready() -> void:
	CardV2.load_cards()
	# 构建飘字层（放最上层）
	_floating_layer = FloatingTextLayer.new()
	_floating_layer.name = "FloatingLayer"
	add_child(_floating_layer)
	move_child(_floating_layer, -1)

	chapter_id = GameBridge.chapter_id_for_battle
	battle_node_id = GameBridge.battle_node_id
	var enemy_ids = GameBridge.enemy_ids.duplicate()
	# 兜底：直接启动战斗场景时（测试用），默认一个敌人
	if enemy_ids.is_empty():
		enemy_ids = ["paper_effigy"]
		DebugLog.info("BATTLE: direct launch, default enemy=paper_effigy")
	# 注意：不清 GameBridge.pending_defeat_flag（_on_battle_won 时还要用）
	GameBridge.battle_result = ""

	state = GameStateV2.new()
	state.init_battle(["rinne"], enemy_ids)
	resolver = CardResolverV2.new(state.combo_engine)

	state.qi_changed.connect(_on_qi_changed)
	state.battle_won.connect(_on_battle_won)
	state.battle_lost.connect(_on_battle_lost)

	end_turn_btn.pressed.connect(_on_end_turn_pressed)
	turn_indicator.text = "玩家回合"

	state.start_player_turn()
	_refresh_hand()
	_refresh_qi()
	_build_combatants()
	DebugLog.info("BATTLE_READY: enemies=" + str(state.enemies.size()) + " hand=" + str(state.players[0].hand.size) + " qi=" + str(state.qi))
	# 仅 headless 下跑 E2E 信号链自测（真实按钮信号→处理函数→出牌），窗口模式绝不触发
	if DisplayServer.get_name() == "headless":
		call_deferred("_schedule_e2e_test")


func _schedule_e2e_test() -> void:
	var timer = Timer.new()
	timer.wait_time = 0.5
	timer.one_shot = true
	timer.timeout.connect(_e2e_step1_press_card)
	add_child(timer)
	timer.start()


## E2E 步骤 1：通过真实 CardView._on_pressed() 触发 clicked 信号链，选一张单体攻击牌
func _e2e_step1_press_card() -> void:
	var hand = state.players[0].hand
	var enemy = state.enemies[0]
	var pressed_idx := -1
	for i in hand.size:
		var cdef = CardV2.get_card(hand.cards[i])
		if cdef.get("target_type", "") == "single_enemy" and state.can_play_card(cdef, enemy):
			pressed_idx = i
			break
	if pressed_idx < 0:
		DebugLog.info("BATTLE_E2E: FAIL no playable single_enemy card")
		get_tree().quit(1)
		return
	var view = hand_zone.get_child(pressed_idx)
	var hp_before = enemy.current_hp
	DebugLog.info("BATTLE_E2E: pressing card idx=%d via real signal" % pressed_idx)
	view._on_pressed()  # 真实信号路径：clicked → _on_hand_card_clicked
	# 步骤 2：延迟后点敌人（真实 CombatantView 信号）
	var t2 = Timer.new()
	t2.wait_time = 0.3
	t2.one_shot = true
	t2.timeout.connect(_e2e_step2_click_enemy.bind(enemy, hp_before))
	add_child(t2)
	t2.start()


func _e2e_step2_click_enemy(enemy, hp_before: int) -> void:
	DebugLog.info("BATTLE_E2E: selected_idx=%d" % _selected_hand_index)
	var enemy_view = _enemy_views.get(enemy.id)
	enemy_view.target_selected.emit(enemy)  # 真实信号路径 → _on_enemy_targeted → _do_play_card
	var t3 = Timer.new()
	t3.wait_time = 0.8
	t3.one_shot = true
	t3.timeout.connect(_e2e_step3_verify.bind(enemy, hp_before))
	add_child(t3)
	t3.start()


func _e2e_step3_verify(enemy, hp_before: int) -> void:
	var dropped = enemy.current_hp < hp_before
	DebugLog.info("BATTLE_E2E: %s (hp %d -> %d)" % ["PASS" if dropped else "FAIL", hp_before, enemy.current_hp])
	get_tree().quit(0 if dropped else 1)


func _build_combatants() -> void:
	# 敌人
	for c in enemy_zone.get_children():
		c.queue_free()
	_enemy_views.clear()
	for e in state.enemies:
		if not (e is UnitV2):
			continue
		var view = CombatantView.new()
		view.setup(e, "enemy", state.enemy_intents.get(e.id, {}))
		view.target_selected.connect(_on_enemy_targeted)
		enemy_zone.add_child(view)
		_enemy_views[e.id] = view
		view.play_idle_breath()
	# 玩家
	for c in player_zone.get_children():
		c.queue_free()
	_player_views.clear()
	for p in state.players:
		var view = CombatantView.new()
		view.setup(p.unit, "player", {})
		player_zone.add_child(view)
		_player_views[p.unit.id] = view
		view.play_idle_breath()


func _refresh_hand() -> void:
	for c in hand_zone.get_children():
		c.queue_free()
	if state.players.is_empty():
		return
	var hand = state.players[0].hand
	for i in hand.size:
		var card_id = hand.cards[i]
		var card_def = CardV2.get_card(card_id)
		var card_view = CardView.new()
		card_view.setup(card_def, i, i == _selected_hand_index)
		# 灵气不足的牌灰显（不能在此用带目标校验的 can_play_card——会把攻击牌全部误灰显）
		if not state.can_afford(card_def):
			card_view.modulate.a = 0.5
		# 注意：clicked 信号本身携带 index（CardView._on_pressed emit _index），
		# 不能再 .bind(i)——多传参数会导致 Godot 静默调用失败（点击无响应的真凶）
		card_view.clicked.connect(_on_hand_card_clicked)
		hand_zone.add_child(card_view)


func _refresh_qi() -> void:
	qi_label.text = "灵气 %d / %d" % [state.qi, state.max_qi]


func _refresh_enemy_intents() -> void:
	for e in state.enemies:
		if e is UnitV2 and _enemy_views.has(e.id):
			_enemy_views[e.id].set_intent(state.enemy_intents.get(e.id, {}))


# ===== 玩家输入 =====

func _on_qi_changed(cur: int, mx: int) -> void:
	qi_label.text = "灵气 %d / %d" % [cur, mx]
	_refresh_hand()  # 灵气变化可能导致某些牌变灰显


func _on_hand_card_clicked(index: int) -> void:
	DebugLog.info("BATTLE: hand card clicked idx=" + str(index) + " busy=" + str(_busy))
	if _busy:
		return
	if state.players.is_empty():
		return
	var hand = state.players[0].hand
	if index < 0 or index >= hand.size:
		DebugLog.info("BATTLE: invalid index")
		return
	var card_def = CardV2.get_card(hand.cards[index])
	# 选牌阶段只校验灵气/回合（single_* 牌的目标校验在 _do_play_card 拿到具体目标后进行）
	if not state.can_afford(card_def):
		DebugLog.info("BATTLE: cannot afford (qi=" + str(state.qi) + " cost=" + str(card_def.get("cost", 0)) + ")")
		_show_log("灵气不足")
		return
	var tt = card_def.get("target_type", "single_enemy")
	DebugLog.info("BATTLE: card=" + str(card_def.get("id", "")) + " target_type=" + tt)
	if tt == "single_enemy" or tt == "single_ally":
		_selected_hand_index = index if _selected_hand_index != index else -1
		_refresh_hand()
		if _selected_hand_index >= 0:
			_show_log("选择目标（点敌方/友方立绘）…")
	else:
		_do_play_card(index, null)


func _on_enemy_targeted(enemy) -> void:
	DebugLog.info("BATTLE: enemy targeted, selected_idx=" + str(_selected_hand_index))
	if _busy or _selected_hand_index < 0:
		return
	_do_play_card(_selected_hand_index, enemy)


## 实际执行打牌：hand_index 是手牌索引，target 是目标单位（可空）
func _do_play_card(hand_index: int, target) -> void:
	DebugLog.info("BATTLE: do_play_card idx=" + str(hand_index) + " target=" + str(target))
	if state.players.is_empty():
		return
	var hand = state.players[0].hand
	if hand_index < 0 or hand_index >= hand.size:
		_show_log("无效手牌")
		return
	var card_id = hand.cards[hand_index]
	var card_def = CardV2.get_card(card_id)
	if not state.can_play_card(card_def, target):
		_show_log("灵气不足或目标无效")
		_selected_hand_index = -1
		_refresh_hand()
		return

	_busy = true
	state.spend_qi(int(card_def.get("cost", 0)))
	_selected_hand_index = -1
	_refresh_hand()

	var result = resolver.play_card(card_def, target, state, state.players[0])
	await _play_out_card_result(result, card_def)

	_busy = false
	var over = state.is_battle_over()
	if over == "won":
		state.battle_won.emit()
	elif over == "lost":
		state.battle_lost.emit()


## 把一张牌的结算结果以动画形式呈现出来（伤害/治疗飘字 + 受击动画 + combo 提示）
func _play_out_card_result(result: Dictionary, card_def: Dictionary) -> void:
	# 玩家施法立绘前冲
	if not state.players.is_empty():
		var pv = _player_views.get(state.players[0].unit.id)
		if pv != null:
			pv.play_attack(-1)  # 向左冲（攻击敌人方向）

	await get_tree().create_timer(0.10).timeout

	# 逐个 effect 应用飘字
	for applied in result.get("effects_applied", []):
		var kind = applied.get("kind", "")
		var tgt = applied.get("target", null)
		var amount = int(applied.get("amount", 0))
		if tgt == null:
			continue
		var view = _enemy_views.get(tgt.id) if tgt.faction == "enemy" else _player_views.get(tgt.id)
		if view == null:
			continue
		match kind:
			"damage":
				view.play_hit()
				_floating_layer.show_above(view, "-%d" % amount, Color(1, 0.3, 0.3))
			"heal":
				view.play_heal()
				_floating_layer.show_above(view, "+%d" % amount, Color(0.4, 1, 0.4))
			"shield":
				_floating_layer.show_above(view, "+%d 护盾" % amount, Color(0.5, 0.75, 1))
			"tag":
				_floating_layer.show_above(view, "[%s]" % applied.get("tag", ""), Color(0.5, 1, 0.5), true)

	await get_tree().create_timer(0.15).timeout

	# combo 触发提示（屏幕中央大字）
	for c in result.get("combos_triggered", []):
		var combo_name = c.get("combo_name", "")
		if combo_name.is_empty():
			continue
		var center = size * 0.5
		_floating_layer.show_text(center - Vector2(80, 0), "【%s 触发！】" % combo_name, Color(0.8, 0.5, 0.1), true)
		_show_log("【%s 触发！】" % combo_name)
		# combo 影响的目标也飘字
		for tgt in c.get("affected_targets", []):
			if tgt == null:
				continue
			var view = _enemy_views.get(tgt.id) if tgt.faction == "enemy" else _player_views.get(tgt.id)
			if view != null:
				view.play_hit()
		await get_tree().create_timer(0.4).timeout


# ===== 结束回合 / 敌人回合 =====

func _on_end_turn_pressed() -> void:
	if _busy:
		return
	_busy = true
	_selected_hand_index = -1
	turn_indicator.text = "敌人回合"
	end_turn_btn.disabled = true
	state.end_player_turn()
	_refresh_hand()
	await get_tree().create_timer(0.3).timeout
	await _execute_enemy_turn_async()
	# 敌人回合结束 → 玩家回合
	state.end_enemy_turn()  # 内部会调 start_player_turn
	turn_indicator.text = "玩家回合"
	end_turn_btn.disabled = false
	_busy = false
	_refresh_hand()
	_refresh_enemy_intents()
	# 检查胜负（敌人可能因某状态自杀或玩家被全灭）
	var over = state.is_battle_over()
	if over == "won":
		state.battle_won.emit()
	elif over == "lost":
		state.battle_lost.emit()


## 敌人回合：逐个敌人执行意图，每个之间留间隔，带飘字与攻击动画
func _execute_enemy_turn_async() -> void:
	var players_alive = state.get_alive_players()
	for e in state.enemies:
		if not (e is UnitV2) or not e.is_alive:
			continue
		var intent = state.enemy_intents.get(e.id, {})
		if intent.is_empty():
			continue
		await _execute_single_enemy_intent(e, intent)
		# 攻击间隔
		await get_tree().create_timer(0.3).timeout
		# 检查玩家是否全灭
		if state.get_alive_players().is_empty():
			break


func _execute_single_enemy_intent(enemy, intent: Dictionary) -> void:
	var enemy_view = _enemy_views.get(enemy.id)
	# 敌人攻击前冲
	if enemy_view != null and intent.get("type") == "attack":
		enemy_view.play_attack(1)  # 向右冲（攻击玩家方向）
	await get_tree().create_timer(0.15).timeout

	var exec_result = state.intent_ai.execute_intent(intent, enemy, state)
	var kind = exec_result.get("kind", "")
	match kind:
		"attacked":
			var target = exec_result.get("target", null)
			var dmg = int(exec_result.get("damage", 0))
			if target != null:
				var tv = _player_views.get(target.id)
				if tv != null:
					tv.play_hit()
					_floating_layer.show_above(tv, "-%d" % dmg, Color(1, 0.3, 0.3))
		"defended":
			var amt = int(exec_result.get("amount", 0))
			if enemy_view != null:
				_floating_layer.show_above(enemy_view, "+%d 护盾" % amt, Color(0.5, 0.75, 1))
		"charged":
			var amt = int(exec_result.get("amount", 0))
			if enemy_view != null:
				_floating_layer.show_above(enemy_view, "蓄力中…（下回合 %d）" % amt, Color(1, 0.6, 0.2), true)
		"buffed":
			if enemy_view != null:
				_floating_layer.show_above(enemy_view, "强化！", Color(0.8, 0.5, 1))
	await get_tree().create_timer(0.2).timeout


# ===== 胜负 =====

func _on_battle_won() -> void:
	_busy = true
	end_turn_btn.disabled = true
	turn_indicator.text = "胜利！"
	_show_log("胜利！")
	_floating_layer.show_text(size * 0.5 - Vector2(60, 0), "胜 利", Color(0.8, 0.6, 0.2), true)
	# 若来自探索，set pending_defeat_flag
	var defeat_flag = GameBridge.pending_defeat_flag
	await get_tree().create_timer(1.0).timeout
	# 弹出选牌奖励
	var reward = RewardScreen.instantiate()
	add_child(reward)
	var existing = []
	if not state.players.is_empty():
		existing = state.players[0].deck.card_ids.duplicate()
	reward.setup(existing)
	var picked_id = await reward.picked
	if not picked_id.is_empty() and not state.players.is_empty():
		state.players[0].deck.add_card_to_pool(picked_id)
		_show_log("获得卡牌：%s" % CardV2.get_card(picked_id).get("name", picked_id))
	reward.queue_free()
	await get_tree().create_timer(0.3).timeout
	# 决定回哪里：若有 pending_defeat_flag，来自 explore；否则回 dialog 节点
	if not defeat_flag.is_empty():
		NarrativeState.set_flag(defeat_flag, true)
		# 回探索（继续探索流程）
		GameBridge.battle_result = ""  # 清状态
		GameBridge.pending_defeat_flag = ""
		SceneRouter.go_explore(chapter_id)
	else:
		# 旧路径：回 dialog 渲染 on_victory 节点
		GameBridge.battle_result = "victory"
		SceneRouter.go_dialog(chapter_id, battle_node_id)


func _on_battle_lost() -> void:
	_busy = true
	end_turn_btn.disabled = true
	turn_indicator.text = "战败…"
	_show_log("战败…")
	_floating_layer.show_text(size * 0.5 - Vector2(60, 0), "战 败", Color(1, 0.3, 0.3), true)
	await get_tree().create_timer(1.2).timeout
	var defeat_flag = GameBridge.pending_defeat_flag
	if not defeat_flag.is_empty():
		# 来自 explore 的战斗失败：直接进 ending（不死敌人复活，玩家死亡）
		GameBridge.pending_defeat_flag = ""
		SceneRouter.go_ending("defeat")
	else:
		GameBridge.battle_result = "defeat"
		SceneRouter.go_dialog(chapter_id, battle_node_id)


func _show_log(msg: String) -> void:
	battle_log.text += msg + "\n"
