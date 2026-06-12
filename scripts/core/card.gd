class_name Card
extends RefCounted

static var _all_cards: Dictionary = {}

static func load_cards() -> void:
	var data = JsonLoader.load_file("res://data/cards.json")
	if not (data is Dictionary) or not data.has("cards") or not (data.cards is Array):
		return
	for c in data.cards:
		_all_cards[c.id] = c

static func get_card(card_id: String) -> Dictionary:
	if _all_cards.is_empty():
		load_cards()
	return _all_cards.get(card_id, {})

static func get_all_ids() -> Array:
	if _all_cards.is_empty():
		load_cards()
	return _all_cards.keys()
