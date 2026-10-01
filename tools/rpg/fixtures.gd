# 夹具只写隔离后的临时 user://，不清理旧存档。
extends RefCounted

static var assertion_count: int = 0

const STAT_KEYS := ["hp", "mp", "atk", "matk", "def", "mdef", "spd"]
const STANDARD_EQUIPMENT := {"weapon": "standard_weapon", "armor": "standard_armor", "accessory": "standard_accessory"}

static func expect(condition: bool, message: String, failures: Array[String]) -> void:
	assertion_count += 1
	if not condition:
		failures.append(message)

static func write_catalog_copy(tag: String, file_name: String = "", edit: Callable = Callable()) -> String:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1":
		return ""
	var root := "user://rpg_tests/" + tag
	DirAccess.make_dir_recursive_absolute(root)
	for kind in ["classes", "skills", "statuses", "enemies", "items", "equipment", "encounters"]:
		var document = JSON.parse_string(FileAccess.get_file_as_string("res://data/rpg/%s.json" % kind))
		if kind == file_name and edit.is_valid():
			edit.call(document)
		var file := FileAccess.open(root + "/" + kind + ".json", FileAccess.WRITE)
		file.store_string(JSON.stringify(document))
	return root

static func state(actor: Dictionary) -> Dictionary:
	return {
		"schema_version": 1, "rules_version": "rpg-0.1", "revision": 0,
		"seed": 7, "rng_state": "9223372036854775807", "round": 0,
		"phase": "preparation", "queue": [], "queue_index": 0,
		"active_actor_id": "", "actors": {actor.actor_id: actor},
		"inventory": {"healing_potion": 3, "mana_potion": 1, "revival_potion": 1, "cleansing_powder": 1},
		"outcome": "", "accepted_commands": {}
	}

static func actor(class_id: String, actor_id: String) -> Dictionary:
	var Factory = load("res://scripts/rpg/actor_factory.gd")
	return Factory.new().create(class_id, actor_id, 5, STANDARD_EQUIPMENT)

static func status(id: String, magnitude: float, remaining: int, source_id: String, snapshot: Dictionary = {}) -> Dictionary:
	var Catalog = load("res://scripts/rpg/catalog.gd")
	var catalog = Catalog.new()
	catalog.load_all()
	var definition: Dictionary = catalog.get_definition("statuses", id)
	return {
		"id": id, "source_id": source_id, "magnitude": magnitude,
		"clock": definition.get("clock", "target_slot"), "remaining": remaining,
		"generation": 0, "applied_slot": 0,
		"dispellable": definition.get("dispellable", false), "snapshot": snapshot.duplicate(true)
	}

static func shield(amount: int, remaining: int, source_id: String) -> Dictionary:
	return {"amount": amount, "source_id": source_id, "clock": "target_slot", "remaining": remaining, "generation": 0, "applied_slot": 0}

static func find_status(actor: Dictionary, id: String) -> Dictionary:
	for current in actor.get("statuses", []):
		if current.get("id", "") == id:
			return current
	return {}

static func enemy(enemy_id: String, actor_id: String, level: int = 5) -> Dictionary:
	var Catalog = load("res://scripts/rpg/catalog.gd")
	var catalog = Catalog.new()
	catalog.load_all()
	var definition: Dictionary = catalog.get_definition("enemies", enemy_id)
	var actor := actor("guard", actor_id)
	actor.side = "enemy"
	actor.class_id = enemy_id
	actor.level = level
	actor.stats = definition.base_stats.duplicate(true)
	for key in STAT_KEYS:
		actor.stats[key] = maxi(1 if key == "hp" else 0, int(actor.stats[key]) + level - 5) if key == "spd" else maxi(1 if key == "hp" else 0, roundi(float(actor.stats[key]) * (1.0 + 0.1 * (level - 5))))
	actor.hp = actor.stats.hp
	actor.mp = actor.stats.mp
	actor.equipment = {}
	actor.skill_ids = []
	for ability in definition.abilities:
		actor.skill_ids.append(ability.id)
	actor.weaknesses = definition.weaknesses.duplicate()
	actor.resistances = definition.resistances.duplicate()
	return actor
