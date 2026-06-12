class_name Deck
extends RefCounted

var card_ids: Array = []
var draw_pile: Array = []
var discard_pile: Array = []

func _init(ids: Array) -> void:
	card_ids = ids.duplicate()
	draw_pile = ids.duplicate()
	_shuffle()

func _shuffle() -> void:
	draw_pile.shuffle()

func draw(count: int) -> Array:
	var result = []
	for i in count:
		if draw_pile.is_empty():
			_reshuffle()
		if draw_pile.is_empty():
			break
		result.append(draw_pile.pop_front())
	return result

func discard_one(card_id: String) -> void:
	discard_pile.append(card_id)

func discard_many(ids: Array) -> void:
	for id in ids:
		discard_one(id)

func _reshuffle() -> void:
	draw_pile.append_array(discard_pile)
	discard_pile.clear()
	_shuffle()

func add_card_to_pool(card_id: String) -> void:
	card_ids.append(card_id)
	var insert_at = randi() % (draw_pile.size() + 1)
	draw_pile.insert(insert_at, card_id)

var draw_count: int:
	get = _get_draw_count

func _get_draw_count() -> int:
	return draw_pile.size()

var discard_count: int:
	get = _get_discard_count

func _get_discard_count() -> int:
	return discard_pile.size()
