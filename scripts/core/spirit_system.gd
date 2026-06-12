class_name SpiritSystem
extends RefCounted

const TIER_WEAK_MAX := 2
const TIER_NORMAL_MIN := 3
const TIER_REINFORCED_MIN := 6
const TIER_RAGE_MIN := 8
const TIER_HUNDRED_GHOSTS := 10

const TIER_EFFECTS := {
	"weak": {
		"move_delta": -1,
		"strength_delta": 0,
		"player_turn_damage": 0,
		"label": "灵体虚弱",
		"scope": "minion",
	},
	"normal": {
		"move_delta": 0,
		"strength_delta": 0,
		"player_turn_damage": 0,
		"label": "正常",
		"scope": "all",
	},
	"reinforced": {
		"move_delta": 0,
		"strength_delta": 2,
		"player_turn_damage": 0,
		"label": "灵体强化",
		"scope": "all",
	},
	"rage": {
		"move_delta": 1,
		"strength_delta": 3,
		"player_turn_damage": 0,
		"label": "暴走",
		"scope": "all",
	},
	"hundred_ghosts": {
		"move_delta": 2,
		"strength_delta": 4,
		"player_turn_damage": 2,
		"label": "百鬼夜行",
		"scope": "all",
	},
}

var _state: GameState
var _enemies: Array = []
var _base_stats: Dictionary = {}
var _processed_deaths: Dictionary = {}
var _last_tier: String = ""

signal density_changed(new_density: int, old_density: int, tier: String, source: String)
signal tier_changed(new_tier: String, old_tier: String)

func _init(game_state: GameState) -> void:
	_state = game_state
	_last_tier = get_tier()
	EventBus.on("effect:added", _on_effect_added)
	EventBus.on("coffin:opened", _on_coffin_opened)

func dispose() -> void:
	EventBus.off("effect:added", _on_effect_added)
	EventBus.off("coffin:opened", _on_coffin_opened)

func get_tier() -> String:
	if _state == null:
		return "normal"
	var d = _state.spirit_density
	if d >= TIER_HUNDRED_GHOSTS:
		return "hundred_ghosts"
	if d >= TIER_RAGE_MIN:
		return "rage"
	if d >= TIER_REINFORCED_MIN:
		return "reinforced"
	if d >= TIER_NORMAL_MIN:
		return "normal"
	return "weak"

func get_tier_color() -> Color:
	match get_tier():
		"weak":
			return Color(0.4, 0.85, 0.45, 0.7)
		"normal":
			return Color(0.95, 0.95, 0.55, 0.75)
		"reinforced":
			return Color(1.0, 0.6, 0.2, 0.9)
		"rage":
			return Color(1.0, 0.25, 0.2, 0.95)
		"hundred_ghosts":
			return Color(0.75, 0.2, 1.0, 1.0)
	return Color.WHITE

func get_tier_label() -> String:
	return TIER_EFFECTS.get(get_tier(), TIER_EFFECTS["normal"]).get("label", "")

func track_enemies(enemies: Array) -> void:
	for e in enemies:
		if e == null:
			continue
		if not _base_stats.has(e.id):
			_base_stats[e.id] = {
				"move": e.stats.move_range,
				"strength": e.stats.strength,
			}
	_enemies = enemies
	_apply_tier_effects()

func on_unit_died(unit_id: String) -> void:
	if _state == null:
		return
	if _processed_deaths.has(unit_id):
		return
	_processed_deaths[unit_id] = true
	var unit = _state.get_unit_by_id(unit_id)
	if unit == null:
		_base_stats.erase(unit_id)
		return
	if unit.faction == "enemy":
		_base_stats.erase(unit_id)
		modify_density(-2, "enemy_killed")
	elif unit.faction == "player":
		modify_density(3, "player_killed")

func on_coffin_opened() -> void:
	modify_density(5, "coffin_opened")

func modify_density(delta: int, source: String = "") -> int:
	if _state == null:
		return 0
	var old = _state.spirit_density
	_state.modify_spirit_density(delta)
	var new = _state.spirit_density
	if new != old:
		density_changed.emit(new, old, get_tier(), source)
	var new_tier = get_tier()
	if new_tier != _last_tier:
		var old_tier = _last_tier
		_last_tier = new_tier
		_apply_tier_effects()
		tier_changed.emit(new_tier, old_tier)
	return new

func can_activate_seal() -> bool:
	if _state == null:
		return false
	var d = _state.spirit_density
	return d >= TIER_REINFORCED_MIN and d < TIER_RAGE_MIN

func apply_turn_end_effect() -> void:
	if _state == null:
		return
	var tier = get_tier()
	var dmg = int(TIER_EFFECTS.get(tier, {}).get("player_turn_damage", 0))
	if dmg <= 0:
		return
	for p in _state.players:
		if p == null or p.unit == null or not p.unit.is_alive:
			continue
		p.unit.take_damage(dmg)
		_state.emit_signal("unit_damaged", p.unit.id, dmg)
		if not p.unit.is_alive:
			_state.map.set_occupant(p.unit.position, null)
			_state.emit_signal("unit_died", p.unit.id)

func _apply_tier_effects() -> void:
	var tier = get_tier()
	var eff = TIER_EFFECTS.get(tier, {})
	var move_delta = int(eff.get("move_delta", 0))
	var str_delta = int(eff.get("strength_delta", 0))
	var scope = str(eff.get("scope", "all"))
	for e in _enemies:
		if e == null or not e.is_alive:
			continue
		var base = _base_stats.get(e.id)
		if base == null:
			continue
		var apply_move = scope == "all" or (scope == "minion" and e.template_id == "paper_effigy")
		var apply_str = scope == "all"
		if apply_move:
			e.stats.move_range = maxi(1, int(base.move) + move_delta)
		else:
			e.stats.move_range = int(base.move)
		if apply_str:
			e.stats.strength = maxi(1, int(base.strength) + str_delta)
		else:
			e.stats.strength = int(base.strength)

func _on_effect_added(data: Dictionary) -> void:
	if data.get("effect", "") == "talisman":
		modify_density(-1, "talisman_placed")

func _on_coffin_opened(_data: Dictionary) -> void:
	modify_density(5, "coffin_opened")
