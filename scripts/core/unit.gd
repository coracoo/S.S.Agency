class_name Unit
extends RefCounted

var id: String
var template_id: String
var name: String
var faction: String  # "player" or "enemy"
var color: Color

var max_hp: int
var current_hp: int
var position: Vector2i

var stats: Dictionary = {}
var shield: int = 0
var remaining_move: int = 0
var status_effects: Array = []
var facing: Vector2i = Vector2i.DOWN
var ai_profile: Dictionary = {}
var traits: Array = []
var ai_state: String = "idle"
var search_target: Vector2i = Vector2i(-1, -1)
var search_turns: int = 0
static var _id_counter: int = 0

signal hp_changed(unit: Unit)
signal died(unit: Unit)

func _init(data: Dictionary, tid: String, pos: Vector2i) -> void:
	template_id = tid
	_id_counter += 1
	id = "%s_%d_%d" % [tid, Time.get_ticks_msec(), _id_counter]
	name = data.get("name", "Unknown")
	faction = data.get("faction", "enemy")

	var c = data.get("color", 0xFFFFFFFF)
	if c is String:
		color = Color.from_string(c, Color.WHITE)
	else:
		var raw = c if c is int else int(c)
		var ca = (raw >> 24) & 0xFF
		var cr = (raw >> 16) & 0xFF
		var cg = (raw >> 8) & 0xFF
		var cb = raw & 0xFF
		color = Color(cr / 255.0, cg / 255.0, cb / 255.0, ca / 255.0)
	ai_profile = data.get("aiProfile", {})
	traits = data.get("traits", []).duplicate(true)
	ai_state = ai_profile.get("defaultState", "idle")

	var s = data.get("stats", {})
	stats = {
		"hp": s.get("hp", 30),
		"strength": s.get("strength", 5),
		"intelligence": s.get("intelligence", 3),
		"defense": s.get("defense", 3),
		"magic_resist": s.get("magicResist", 2),
		"speed": s.get("speed", 3),
		"move_range": s.get("moveRange", 3),
	}
	max_hp = stats.hp
	current_hp = max_hp
	position = pos
	remaining_move = stats.move_range
	facing = Vector2i.RIGHT if faction == "player" else Vector2i.LEFT

var is_alive: bool:
	get = _get_is_alive

func _get_is_alive() -> bool:
	return current_hp > 0

var move_range: int:
	get = _get_move_range

func _get_move_range() -> int:
	return stats.move_range

var can_move: bool:
	get = _get_can_move

func _get_can_move() -> bool:
	return remaining_move > 0

func start_turn() -> void:
	remaining_move = stats.move_range

func spend_move(steps: int) -> void:
	remaining_move = maxi(0, remaining_move - steps)

func take_damage(amount: int, damage_type: String = "physical", attacker_pos: Vector2i = Vector2i(-1, -1)) -> int:
	var was_alive = is_alive
	var defense = stats.get("defense", 0)
	var magic_resist = stats.get("magic_resist", 2)
	var mitigation = 0
	if damage_type == "magic":
		mitigation = int(magic_resist * 0.3)
	else:
		mitigation = int(defense * 0.5)
	var direction_mod = 1.0
	if attacker_pos != Vector2i(-1, -1):
		direction_mod = get_defense_modifier(attacker_pos)
	var final_amount = maxi(1, int((amount - mitigation) * direction_mod))
	var absorbed = mini(shield, final_amount)
	shield -= absorbed
	var remaining = final_amount - absorbed
	current_hp = maxi(0, current_hp - remaining)
	hp_changed.emit(self)
	if was_alive and current_hp <= 0:
		died.emit(self)
	return remaining

func heal(amount: int) -> int:
	if not is_alive:
		return 0
	var healed = mini(amount, max_hp - current_hp)
	current_hp += healed
	hp_changed.emit(self)
	return healed

func add_shield(amount: int) -> void:
	shield += amount

func move_to(pos: Vector2i, dir: Vector2i = Vector2i.ZERO) -> void:
	if dir != Vector2i.ZERO:
		facing = dir
	elif pos != position:
		var diff = pos - position
		if absi(diff.x) >= absi(diff.y):
			facing = Vector2i.RIGHT if diff.x > 0 else Vector2i.LEFT
		else:
			facing = Vector2i.DOWN if diff.y > 0 else Vector2i.UP
	position = pos

func get_defense_modifier(attacker_pos: Vector2i) -> float:
	var attack_dir = attacker_pos - position
	var card_dir := Vector2i.ZERO
	if absi(attack_dir.x) >= absi(attack_dir.y):
		card_dir = Vector2i.RIGHT if attack_dir.x > 0 else Vector2i.LEFT
	else:
		card_dir = Vector2i.DOWN if attack_dir.y > 0 else Vector2i.UP
	if card_dir == facing:
		return 1.0
	if card_dir == -facing:
		return 0.5
	return 0.75
