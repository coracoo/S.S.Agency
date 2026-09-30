class_name CardV2
extends RefCounted
## 卡牌静态仓库 v2
##
## 从 res://data/v2/cards.json 加载。与旧 Card 类并存，互不影响（v2 战斗用 CardV2）。

static var _all_cards: Dictionary = {}
static var _loaded: bool = false


static func load_cards() -> void:
	_all_cards.clear()
	var data = JsonLoader.load_file("res://data/v2/cards.json")
	if not (data is Dictionary):
		push_error("CardV2: failed to load cards.json")
		_loaded = true
		return
	for c in data.get("cards", []):
		if c is Dictionary and c.has("id"):
			_all_cards[c.id] = c.duplicate(true)
	_loaded = true


static func get_card(card_id: String) -> Dictionary:
	if not _loaded:
		load_cards()
	return _all_cards.get(card_id, {}).duplicate(true)


static func get_all_ids() -> Array:
	if not _loaded:
		load_cards()
	return _all_cards.keys()


static func get_all_cards() -> Array:
	if not _loaded:
		load_cards()
	return _all_cards.values()
