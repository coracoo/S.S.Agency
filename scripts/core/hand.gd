class_name Hand
extends RefCounted

var card_ids: Array = []
var max_size: int

func _init(max_sz: int = 10) -> void:
	max_size = max_sz

func add_cards(ids: Array) -> Array:
	var overflow = []
	for id in ids:
		if card_ids.size() < max_size:
			card_ids.append(id)
		else:
			overflow.append(id)
	return overflow

func get_card(index: int) -> Dictionary:
	if index < 0 or index >= card_ids.size():
		return {}
	return Card.get_card(card_ids[index])

func remove_card(index: int) -> String:
	if index < 0 or index >= card_ids.size():
		return ""
	var id = card_ids[index]
	card_ids.remove_at(index)
	return id

var size: int:
	get = _get_size

func _get_size() -> int:
	return card_ids.size()
