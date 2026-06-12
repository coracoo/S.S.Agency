class_name TurnManager
extends RefCounted

var state: GameState
var first_turn: bool = true

func _init(s: GameState) -> void:
	state = s

func start_player_turn() -> void:
	state.current_turn = "player"
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

	state.emit_signal("turn_start", "player")
	state.emit_signal("hand_changed")
	state.emit_signal("energy_changed", state.team_ap, state.max_ap)

func end_player_turn() -> void:
	state.selected_unit = null
	state.selected_card_index = -1
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
