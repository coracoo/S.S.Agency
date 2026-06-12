class_name UnitFactory
extends RefCounted

static var _templates: Dictionary = {}

static func load_templates() -> void:
	var units = JsonLoader.load_file("res://data/units.json")
	var enemies = JsonLoader.load_file("res://data/enemies.json")
	if units is Dictionary and units.has("units") and units.units is Array:
		for u in units.units:
			_templates[u.id] = u
	if enemies is Dictionary and enemies.has("enemies") and enemies.enemies is Array:
		for e in enemies.enemies:
			_templates[e.id] = e

static func create(template_id: String, pos: Vector2i) -> Unit:
	if _templates.is_empty():
		load_templates()
	var data = _templates.get(template_id, {})
	if data.is_empty():
		push_error("Unknown template: " + template_id)
		return null
	return Unit.new(data, template_id, pos)

static func get_starting_deck(template_id: String) -> Array:
	if _templates.is_empty():
		load_templates()
	var data = _templates.get(template_id, {})
	return data.get("startingDeck", []).duplicate()

static func get_starting_items(template_id: String) -> Array:
	if _templates.is_empty():
		load_templates()
	var data = _templates.get(template_id, {})
	return data.get("startingItems", []).duplicate(true)
