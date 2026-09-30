class_name UnitV2
extends RefCounted
## 单位 v2
##
## 由旧 unit.gd 改造：删除 position/facing/remaining_move/move_to/get_defense_modifier 等
## 所有格子/移动/方向相关字段与逻辑。保留 HP/stats/shield/status/tags/take_damage/heal。
##
## 新增：
##   - tags 字段 + has_tag/apply_tag/remove_tag（combo 引擎依赖）
##   - intent_profile（敌人意图 AI 配置，玩家单位为空）
##   - sprites（数据驱动美术路径，告别旧版文件名约定）

signal hp_changed(unit)
signal died(unit)

var id: String
var template_id: String
var name: String
var faction: String  # "player" or "enemy"
var color: Color

var max_hp: int
var current_hp: int
var stats: Dictionary = {}
var shield: int = 0
var status_effects: Array = []  # 复用旧 StatusEffectManager 的状态结构

var tags: Dictionary = {}  # tag 名 → 剩余回合数（-1 表示永久）
var intent_profile: Dictionary = {}
var sprites: Dictionary = {}  # { battle, portrait }
var animation_profile: String = "breath"  # breath / float / stiff
var facing_mode: String = "flip"  # flip / four_dir

static var _id_counter: int = 0


func _init(data: Dictionary, tid: String) -> void:
	template_id = tid
	_id_counter += 1
	id = "%s_%d_%d" % [tid, Time.get_ticks_msec(), _id_counter]
	name = data.get("name", "Unknown")
	faction = data.get("faction", "enemy")

	var c = data.get("color", "#FFFFFFFF")
	if c is String:
		color = Color.from_string(c, Color.WHITE)
	else:
		var raw = int(c)
		var ca = (raw >> 24) & 0xFF
		var cr = (raw >> 16) & 0xFF
		var cg = (raw >> 8) & 0xFF
		var cb = raw & 0xFF
		color = Color(cr / 255.0, cg / 255.0, cb / 255.0, ca / 255.0)

	intent_profile = data.get("intent_profile", {})
	sprites = data.get("sprites", {})
	animation_profile = data.get("animation_profile", "breath")
	facing_mode = data.get("facing_mode", "flip")

	var s = data.get("stats", {})
	stats = {
		"hp": s.get("hp", 30),
		"strength": s.get("strength", 5),
		"intelligence": s.get("intelligence", 3),
		"defense": s.get("defense", 3),
		"magic_resist": s.get("magicResist", 2)
	}
	max_hp = stats.hp
	current_hp = max_hp

	for tag in data.get("tags", []):
		tags[tag] = -1  # 永久标签（如 jiangshi/undead/daoist）


var is_alive: bool:
	get: return current_hp > 0


## 受伤。返回实际扣除的 HP（不含护盾吸收部分）。
## 旧版带 attacker_pos 用于方向减伤，已删除。
func take_damage(amount: int, damage_type: String = "physical") -> int:
	var was_alive = is_alive
	var mitigation = 0
	if damage_type == "magic":
		mitigation = int(stats.get("magic_resist", 2) * 0.3)
	else:
		mitigation = int(stats.get("defense", 3) * 0.5)
	var final_amount = maxi(1, amount - mitigation)
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


# ===== Tag 系统（combo 引擎依赖）=====

func has_tag(tag: String) -> bool:
	return tags.has(tag) and tags[tag] != 0


## 施加临时 tag（duration 回合后自动消失）。永久 tag（duration=-1）不受影响。
func apply_tag(tag: String, duration: int = -1) -> void:
	if duration == -1:
		tags[tag] = -1
		return
	# 已有永久 tag：不覆盖为临时
	if tags.has(tag) and tags[tag] == -1:
		return
	var cur = int(tags.get(tag, 0))
	tags[tag] = maxi(cur, duration)


func remove_tag(tag: String) -> void:
	tags.erase(tag)


## 回合结束时，所有临时 tag 剩余回合 -1，归零则移除
func tick_tags() -> void:
	var to_remove: Array = []
	for tag in tags:
		var d = int(tags[tag])
		if d > 0:
			d -= 1
			if d <= 0:
				to_remove.append(tag)
			else:
				tags[tag] = d
	for tag in to_remove:
		tags.erase(tag)
