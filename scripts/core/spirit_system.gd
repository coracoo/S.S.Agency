class_name SpiritSystem
extends RefCounted

const TIER_WEAK_MAX := 2
const TIER_NORMAL_MIN := 3
const TIER_REINFORCED_MIN := 6
const TIER_RAGE_MIN := 8
const TIER_HUNDRED_GHOSTS := 10

# GDD §5.6 灵气密度效果表。damage_mult 为灵体伤害倍率(以基础 strength 为底),
# rage 的"每回合额外行动"按任务约定简化为伤害 +50%;
# hundred_ghosts 的"所有灵体进 rage"已实现:battle_scene 监听 tier_changed 调 AIController.set_all_spirits_rage()。
const TIER_EFFECTS := {
	"weak": {
		"move_delta": -1,
		"damage_mult": 1.0,
		"player_turn_damage": 0,
		"label": "灵体虚弱",
		"scope": "minion",
	},
	"normal": {
		"move_delta": 0,
		"damage_mult": 1.0,
		"player_turn_damage": 0,
		"label": "正常",
		"scope": "all",
	},
	"reinforced": {
		"move_delta": 0,
		"damage_mult": 1.3,
		"player_turn_damage": 0,
		"label": "灵体强化",
		"scope": "all",
	},
	"rage": {
		"move_delta": 0,
		"damage_mult": 1.5,
		"player_turn_damage": 0,
		"label": "暴走",
		"scope": "all",
	},
	"hundred_ghosts": {
		"move_delta": 0,
		"damage_mult": 1.5,
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

# ============ 封印击杀判定(GDD §5.5) ============

const SEAL_MIN_POINTS := 3
const SEAL_MIN_DENSITY := 6

# 阵眼 = seal 地形(tag seal_point)且格上有 talisman 效果(tag seal_component)
func get_activated_seal_points() -> Array:
	var points: Array = []
	if _state == null or _state.map == null:
		return points
	var map = _state.map
	for row in range(map.rows):
		for col in range(map.cols):
			if not map.has_tag(col, row, "seal_point"):
				continue
			for eff in map.get_effects(col, row):
				if eff.type == "talisman":
					points.append(Vector2i(col, row))
					break
	return points

# 阵眼包围区域判定(简化版,写死两种可靠判据):
# 1) 射线法点-in-多边形:以全部已激活阵眼为顶点(按绕质心角度排序),目标在多边形内即算;
# 2) 邻接:目标与任一已激活阵眼曼哈顿距离 <= 1(站在阵眼上或贴着阵眼)。
# 不做凸包/面积比等复杂判定,避免边界数值不稳定。
func is_target_in_seal_region(target_pos: Vector2i, points: Array) -> bool:
	if points.is_empty():
		return false
	for p in points:
		if absi(target_pos.x - p.x) + absi(target_pos.y - p.y) <= 1:
			return true
	if points.size() < 3:
		return false
	# 绕质心排序得到简单多边形
	var cx := 0.0
	var cy := 0.0
	for p in points:
		cx += p.x
		cy += p.y
	cx /= points.size()
	cy /= points.size()
	var sorted = points.duplicate()
	sorted.sort_custom(func(a, b): return atan2(a.y - cy, a.x - cx) < atan2(b.y - cy, b.x - cx))
	# 射线法:向右发射线,统计与多边形边的交叉数,奇数=内部
	var inside := false
	var n = sorted.size()
	var tx = target_pos.x + 0.5
	var ty = target_pos.y + 0.5
	for i in range(n):
		var a = sorted[i]
		var b = sorted[(i + 1) % n]
		var ax = a.x + 0.5
		var ay = a.y + 0.5
		var bx = b.x + 0.5
		var by = b.y + 0.5
		if (ay > ty) != (by > ty):
			var x_cross = ax + (ty - ay) / (by - ay) * (bx - ax)
			if tx < x_cross:
				inside = not inside
	return inside

# 封印条件明细,供 hover tooltip 显示"封印条件 n/4"
func get_seal_status(target_unit: Unit) -> Dictionary:
	var points = get_activated_seal_points()
	var density_ok = _state != null and _state.spirit_density >= SEAL_MIN_DENSITY
	var points_ok = points.size() >= SEAL_MIN_POINTS
	var in_region = target_unit != null and is_target_in_seal_region(target_unit.position, points)
	var spirit_ok = target_unit != null and target_unit.faction == "enemy"
	var met = int(points_ok) + int(density_ok) + int(in_region) + int(spirit_ok)
	return {
		"ok": points_ok and density_ok and in_region and spirit_ok,
		"points": points.size(),
		"points_ok": points_ok,
		"density_ok": density_ok,
		"in_region": in_region,
		"spirit_ok": spirit_ok,
		"met": met,
		"total": 4,
	}

func check_seal_activation(target_unit: Unit) -> bool:
	return bool(get_seal_status(target_unit).get("ok", false))

# 执行封印:广播 seal:activated(先发事件,FX 需要阵眼/目标位置),随后目标即死。
# AP 由调用方(battle_scene)在执行前扣除;此处只负责判定+击杀+事件。
func activate_seal(target_unit: Unit) -> bool:
	if _state == null or target_unit == null or not target_unit.is_alive:
		return false
	var points = get_activated_seal_points()
	if not bool(get_seal_status(target_unit).get("ok", false)):
		return false
	EventBus.emit("seal:activated", {
		"map": _state.map,
		"target_id": target_unit.id,
		"target_pos": target_unit.position,
		"points": points,
		"method": "seal",
	})
	# 即死:伤害取足够大,走 take_damage 让 died/hp_changed 信号正常触发
	target_unit.take_damage(target_unit.current_hp + target_unit.shield + 999, "magic")
	if not target_unit.is_alive:
		_state.map.set_occupant(target_unit.position, null)
		_state.emit_signal("unit_died", target_unit.id)
	return true

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
	var dmg_mult = float(eff.get("damage_mult", 1.0))
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
			# 伤害修正直接落在 strength 上,ai_controller/_calc_damage 均实时读取,无需另接结算
			e.stats.strength = maxi(1, roundi(float(base.strength) * dmg_mult))
		else:
			e.stats.strength = int(base.strength)

func _on_effect_added(data: Dictionary) -> void:
	if data.get("effect", "") == "talisman":
		modify_density(-1, "talisman_placed")

func _on_coffin_opened(_data: Dictionary) -> void:
	modify_density(5, "coffin_opened")
