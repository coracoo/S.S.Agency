class_name TurnManager
extends RefCounted

# GDD §三 回合结构 4 阶段:玩家回合 → 敌方意图预览 → 敌方回合 → 环境处理
# spirit 为环境处理的子阶段(灵气结算),不算独立阶段。
const PHASE_PLAYER := "player"
const PHASE_INTENT := "intent"
const PHASE_ENEMY := "enemy"
const PHASE_ENV := "environment"
const PHASE_SPIRIT := "spirit"

var state: GameState
var first_turn: bool = true
var phase: String = PHASE_PLAYER

func _init(s: GameState) -> void:
	state = s

# 阶段切换唯一入口:同步 current_turn 并广播 turn:phase_changed(EventBus)
func set_phase(new_phase: String) -> void:
	if state == null or new_phase == phase:
		return
	var old = phase
	phase = new_phase
	state.current_turn = new_phase
	EventBus.emit("turn:phase_changed", {"from": old, "to": new_phase, "turn": state.turn_count})

func start_player_turn() -> void:
	set_phase(PHASE_PLAYER)
	state.turn_count += 1
	state.clear_old_noise()
	state.clear_skipped_units()

	# Tick turn_start status for player units
	var player_units = []
	for p in state.players:
		if p.unit.is_alive:
			player_units.append(p.unit)
	var ticks = StatusEffectManager.tick_statuses(player_units, "turn_start")
	var skipped = {}
	for tick in ticks:
		if tick.get("damage", 0) > 0:
			state.emit_signal("unit_damaged", tick.unit_id, tick.damage)
		if tick.get("skipped_turn", false):
			skipped[tick.unit_id] = true
			state.mark_unit_skipped(tick.unit_id)

	var balance = state.balance
	state.set_ap(state.max_ap)
	print("Turn %d: AP = %d/%d" % [state.turn_count, state.team_ap, state.max_ap])

	for player in state.players:
		if not player.unit.is_alive:
			continue
		if skipped.get(player.unit.id, false):
			player.unit.remaining_move = 0
			continue
		player.unit.start_turn()
		var draw_count = int(balance.get("handSize", 5)) if first_turn else int(balance.get("drawPerTurn", 2))
		var drawn = player.deck.draw(draw_count)
		var overflow = player.hand.add_cards(drawn)
		if not overflow.is_empty():
			player.deck.discard_many(overflow)
	first_turn = false

	# 恐惧源(GDD §四):诅咒地形格上回合开始 +curseTilePerTurn;百鬼夜行(灵气 10)每回合 +hundredGhostsPerTurn
	var fear_cfg: Dictionary = balance.get("fear", {})
	var curse_fear = int(fear_cfg.get("curseTilePerTurn", 5))
	var hg_fear = int(fear_cfg.get("hundredGhostsPerTurn", 15))
	for player in state.players:
		var u: Unit = player.unit
		if not u.is_alive:
			continue
		if state.map.has_tag(u.position.x, u.position.y, "fear_increase"):
			u.modify_fear(curse_fear)
		if state.spirit_density >= 10:
			u.modify_fear(hg_fear)

	state.emit_signal("turn_start", "player")
	state.emit_signal("hand_changed")
	state.emit_signal("energy_changed", state.team_ap, state.max_ap)

func end_player_turn() -> void:
	state.selected_unit = null
	state.selected_card_index = -1
	# 恐惧回合结算(GDD §四):失控单位降到阈值 60% 并恢复,其余自然下降
	var fear_cfg: Dictionary = state.balance.get("fear", {})
	var recovery = int(fear_cfg.get("turnEndRecovery", -5))
	var factor = float(fear_cfg.get("panicRecoverFactor", 0.6))
	for player in state.players:
		player.unit.apply_turn_end_fear(recovery, factor)
	state.emit_signal("turn_end", "player")

func can_play_card(card_cost: int) -> bool:
	return state.team_ap >= card_cost

func play_card(player: Dictionary, card_index: int) -> bool:
	var card_data = player.hand.get_card(card_index)
	if card_data.is_empty():
		return false
	if not can_play_card(int(card_data.get("cost", 1))):
		return false
	if not state.spend_ap(int(card_data.get("cost", 1))):
		return false
	var card_id = player.hand.remove_card(card_index)
	if card_id != "":
		player.deck.discard_one(card_id)
	state.emit_signal("hand_changed")
	return true
