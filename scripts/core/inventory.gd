class_name Inventory
extends RefCounted

const MAX_SLOTS: int = 4

var items: Array = []
var _next_instance_id: int = 1

func _init() -> void:
	pass

func add_item(object_id: String, is_consumable: bool, uses: int = 1) -> bool:
	for item in items:
		if item.get("object_id", "") == object_id and item.get("card_id", "") == "":
			item.uses = int(item.get("uses", 1)) + maxi(1, uses)
			return true
	if items.size() >= MAX_SLOTS:
		return false
	items.append({
		"object_id": object_id,
		"consumable": is_consumable,
		"uses": maxi(1, uses),
		"instance_id": _next_instance_id
	})
	_next_instance_id += 1
	return true

func add_card_item(card_id: String, uses: int = 1) -> bool:
	for item in items:
		if item.get("card_id", "") == card_id:
			item.uses = int(item.get("uses", 1)) + maxi(1, uses)
			return true
	if items.size() >= MAX_SLOTS:
		return false
	items.append({
		"object_id": "",
		"card_id": card_id,
		"consumable": true,
		"uses": maxi(1, uses),
		"instance_id": _next_instance_id
	})
	_next_instance_id += 1
	return true

func remove_item_at(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= items.size():
		return {}
	return items.pop_at(slot_index)

func consume_item_at(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= items.size():
		return {}
	var item = items[slot_index]
	var uses = int(item.get("uses", 1))
	if uses > 1:
		item.uses = uses - 1
		return item.duplicate(true)
	return items.pop_at(slot_index)

func get_item(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= items.size():
		return {}
	return items[slot_index]

func get_size() -> int:
	return items.size()

func is_full() -> bool:
	return items.size() >= MAX_SLOTS

func clear() -> void:
	items.clear()
