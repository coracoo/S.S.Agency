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
# AI 差异化状态(GDD §12.4):rage=执念被威胁直奔目标无视恐惧;confused=符纸影响随机移动
var rage_target_pos: Vector2i = Vector2i(-1, -1)
var rage_turns: int = 0
var confused_turns: int = 0
# 巡逻路径游标(aiProfile.patrolPath)与 Boss 阶段(1/2)
var patrol_index: int = 0
var boss_phase: int = 1
var tags: Array = []
# 恐惧值(GDD §四):0-100,≥阈值失控 1 回合;阈值外置 units.json stats.fearThreshold
var fear: int = 0
var fear_threshold: int = 65
var panicked: bool = false
# 钟馗「镇邪体魄」:每场战斗限 1 次,致命伤留 1 HP
var undying_used: bool = false
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
	tags = data.get("tags", []).duplicate()
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
	fear_threshold = int(s.get("fearThreshold", 65))
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
	# 钟馗「镇邪体魄」:本次伤害致死且未用过 → 留 1 HP 不死(每场战斗限 1 次)
	if was_alive and remaining >= current_hp and has_trait("spirit_body") and not undying_used:
		undying_used = true
		current_hp = 1
		hp_changed.emit(self)
		_bus_emit("unit:undying_survived", {"unit_id": id, "pos": position})
		return remaining
	current_hp = maxi(0, current_hp - remaining)
	hp_changed.emit(self)
	if was_alive and current_hp <= 0:
		died.emit(self)
	return remaining

# 特性查询:traits 为 [{id,name,description}],按 id 匹配
func has_trait(trait_id: String) -> bool:
	for t in traits:
		if t is Dictionary and str(t.get("id", "")) == trait_id:
			return true
	return false

# 恐惧值增减(GDD §四):clamp 0-100;升过阈值触发失控(本回合不可操作)
func modify_fear(delta: int) -> void:
	if not is_alive or delta == 0:
		return
	var old = fear
	fear = clampi(fear + delta, 0, 100)
	_bus_emit("unit:fear_changed", {"unit_id": id, "fear": fear, "delta": fear - old, "pos": position})
	if fear >= fear_threshold and not panicked:
		panicked = true
		_bus_emit("unit:panicked", {"unit_id": id, "pos": position, "fear": fear})

# 回合结束恐惧结算(turn_manager 调用):失控单位恐惧降到阈值 60% 并恢复;其余自然下降
func apply_turn_end_fear(natural_recovery: int, panic_factor: float) -> void:
	if not is_alive:
		return
	if panicked:
		panicked = false
		fear = clampi(int(fear_threshold * panic_factor), 0, 100)
		_bus_emit("unit:fear_changed", {"unit_id": id, "fear": fear, "delta": 0, "pos": position, "recovered": true})
	elif natural_recovery != 0:
		modify_fear(natural_recovery)

# EventBus 动态获取:unit.gd 为 class_name 静态依赖,编译期 autoload 未注册,不能直接写 EventBus 标识符;
# 且 --script 模式下绝对路径 /root/* 不可用,必须用相对路径
static func _bus_emit(event_name: String, data: Dictionary) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var bus = tree.root.get_node_or_null("EventBus")
	if bus != null:
		bus.emit(event_name, data)

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
