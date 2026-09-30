class_name HandV2
extends RefCounted
## 手牌容器 v2
##
## 与旧 Hand 并存（v2 战斗专用）。字段命名更直观（cards 而非 card_ids）。
## 提供按 card_id 移除（出牌后弃牌用）和 clear（回合结束弃手牌用）。

var cards: Array = []  # Array of card_id (String)
var max_size: int


func _init(max_sz: int = 5) -> void:
	max_size = max_sz


func add_card(card_id: String) -> bool:
	if cards.size() >= max_size:
		return false
	cards.append(card_id)
	return true


func add_cards(ids: Array) -> Array:
	var overflow = []
	for id in ids:
		if cards.size() < max_size:
			cards.append(id)
		else:
			overflow.append(id)
	return overflow


func remove_card(card_id: String) -> bool:
	var idx = cards.find(card_id)
	if idx < 0:
		return false
	cards.remove_at(idx)
	return true


func has_card(card_id: String) -> bool:
	return cards.has(card_id)


func clear() -> void:
	cards.clear()


var size: int:
	get: return cards.size()
