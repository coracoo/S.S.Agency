# 纯状态时钟。所有 generation 保存于角色快照，复制／恢复不依赖进程全局计数。
class_name RpgStatusRules
extends RefCounted

const Damage = preload("res://scripts/rpg/damage_rules.gd")
const CLEANSE_IDS := ["burn", "weaken", "armor_break", "magic_break", "slow", "mark", "taunt", "stun"]
const TARGET_SLOT_IDS := ["armor_break", "magic_break", "battle_spirit", "mark", "weaken", "burn", "stun", "awake", "taunt", "stagger"]

# 输入为已构造的 Status 实例；返回 applied/change/reason/status/previous/event。
# 更弱效果完全不写入；同强度只延长时长，刷新后的 generation 避免本槽立刻减少。
static func apply(actor: Dictionary, status: Dictionary) -> Dictionary:
	if not _valid_status(status):
		return _ignored("状态实例非法")
	var reason := immunity(actor, {"type": "apply_status", "status_id": status.id})
	if not reason.is_empty():
		return _ignored(reason)
	var index := _index(actor, status.id)
	var previous: Dictionary = actor.statuses[index].duplicate(true) if index >= 0 else {}
	if not previous.is_empty() and float(status.magnitude) < float(previous.magnitude):
		return _ignored("现有同名状态更强", previous)
	var current := status.duplicate(true)
	current.magnitude = float(status.magnitude)
	if not previous.is_empty() and float(status.magnitude) == float(previous.magnitude):
		current.remaining = maxi(int(previous.remaining), int(status.remaining))
	current["generation"] = _next_generation(actor)
	current["applied_slot"] = int(actor.get("slot_count", 0))
	if index < 0:
		actor.statuses.append(current)
	else:
		actor.statuses[index] = current
	var change := "added" if previous.is_empty() else ("refreshed" if float(status.magnitude) == float(previous.magnitude) else "replaced")
	return {"applied": true, "change": change, "reason": "", "status": current.duplicate(true), "previous": previous, "event": _event("status_applied", actor, {"change": change, "status": current.duplicate(true), "previous": previous}, current.source_id)}

# 护盾是 actor.shield 的唯一总量；按当前剩余量比较，不按最初施加量比较。
# 同量或更强的新盾使用新盾时长，较弱／零量不延长旧盾。
static func apply_shield(actor: Dictionary, shield: Dictionary) -> Dictionary:
	if int(actor.get("hp", 0)) <= 0:
		return _ignored("目标已倒地")
	if not _valid_shield(shield):
		return _ignored("护盾实例非法或无有效护盾")
	var previous: Dictionary = actor.get("shield", {}).duplicate(true)
	if int(shield.amount) < int(previous.get("amount", 0)):
		return _ignored("现有护盾剩余量更强", previous)
	var current := shield.duplicate(true)
	current["generation"] = _next_generation(actor)
	current["applied_slot"] = int(actor.get("slot_count", 0))
	actor.shield = current
	var change := "added" if previous.is_empty() else ("refreshed" if int(shield.amount) == int(previous.amount) else "replaced")
	return {"applied": true, "change": change, "reason": "", "shield": current.duplicate(true), "previous": previous, "event": _event("shield_applied", actor, {"change": change, "shield": current.duplicate(true), "previous": previous}, current.source_id)}

# 掩护存于守卫拥有者；snapshot.target_id 指向被保护队友。
# begin_slot 负责槽计数、先移除防御／掩护、再灼烧，绝不增加可选命令机会。
static func begin_slot(actor: Dictionary, periodic_damage_allowed: bool = true) -> Dictionary:
	var events: Array[Dictionary] = []
	var token := {"actor_id": actor.get("actor_id", ""), "slot_count": int(actor.get("slot_count", 0)), "begun": false, "ended": false, "status_generations": {}, "shield_generation": -1, "stun_generation": -1, "stunned": false, "defeated": int(actor.get("hp", 0)) <= 0, "events": events}
	if token.defeated:
		return token
	actor.slot_count = int(actor.get("slot_count", 0)) + 1
	token.slot_count = actor.slot_count
	token.begun = true
	var kept: Array = []
	for status in actor.get("statuses", []):
		if status.clock == "next_owner_slot":
			events.append(_event("status_removed", actor, {"status": status.duplicate(true), "reason": "owner_slot_start"}))
		else:
			kept.append(status)
	actor.statuses = kept
	for status in actor.statuses:
		if status.clock == "target_slot" and int(status.remaining) > 0:
			token.status_generations[status.id] = int(status.generation)
	var shield: Dictionary = actor.get("shield", {})
	if not shield.is_empty() and shield.get("clock", "") == "target_slot" and int(shield.get("remaining", 0)) > 0:
		token.shield_generation = int(shield.get("generation", -1))
	var burn := _status(actor, "burn")
	if not burn.is_empty() and int(burn.remaining) > 0:
		var calculation := Damage.periodic(burn, actor)
		# 门禁在每个实际槽首由当前战场重新判断；回补锁片也能挡住已有灼烧，时钟仍照常推进。
		if not periodic_damage_allowed:
			calculation.damage = 0
			calculation.factors["objective_guarded"] = true
			events.append(_event("saga_objective_blocked", actor, {"status_id": "burn", "text": "联动保护仍在，灼烧本槽不造成伤害；持续时间照常消耗。"}, burn.source_id))
		var absorption := Damage.absorb(actor, calculation.damage)
		events.append(_event("periodic_damage", actor, {"status": burn.duplicate(true), "damage": calculation.damage, "factors": calculation.factors, "absorption": absorption}, burn.source_id))
	token.defeated = int(actor.get("hp", 0)) <= 0
	if not token.defeated:
		var stun := _status(actor, "stun")
		if not stun.is_empty() and int(stun.remaining) > 0:
			token.stunned = true
			token.stun_generation = int(stun.generation)
	return token

# token 仅可消费一次，且必须匹配拥有者及槽号；新施加或刷新 generation 不扣。
static func end_slot(actor: Dictionary, token: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not token.get("begun", false) or token.get("ended", false) or token.get("actor_id", "") != actor.get("actor_id", "") or int(token.get("slot_count", -1)) != int(actor.get("slot_count", 0)):
		return events
	token.ended = true
	if int(actor.get("hp", 0)) <= 0:
		return events
	var grant_awake := false
	var kept: Array = []
	for status in actor.get("statuses", []):
		if status.clock == "target_slot" and int(token.get("status_generations", {}).get(status.id, -1)) == int(status.generation):
			var previous: Dictionary = status.duplicate(true)
			status.remaining = maxi(0, int(status.remaining) - 1)
			if status.remaining == 0:
				events.append(_event("status_removed", actor, {"status": previous, "reason": "target_slot_end"}))
				if status.id == "stun" and token.get("stunned", false) and int(token.get("stun_generation", -1)) == int(status.generation):
					grant_awake = true
				continue
			events.append(_event("status_tick", actor, {"previous": previous, "status": status.duplicate(true)}))
		kept.append(status)
	actor.statuses = kept
	var shield: Dictionary = actor.get("shield", {})
	if not shield.is_empty() and shield.get("clock", "") == "target_slot" and int(token.get("shield_generation", -1)) == int(shield.get("generation", -2)):
		var previous := shield.duplicate(true)
		shield.remaining = maxi(0, int(shield.get("remaining", 0)) - 1)
		if shield.remaining == 0:
			actor.shield = {}
			events.append(_event("shield_removed", actor, {"shield": previous, "reason": "target_slot_end"}))
		else:
			events.append(_event("shield_tick", actor, {"previous": previous, "shield": shield.duplicate(true)}))
	if grant_awake:
		var result := apply(actor, {"id": "awake", "source_id": actor.actor_id, "magnitude": 1.0, "clock": "target_slot", "remaining": 2, "generation": 0, "applied_slot": actor.slot_count, "dispellable": false, "snapshot": {}})
		if result.applied:
			events.append(result.event)
	return events

# 返回当轮有效速度快照。只在这里消费缓速快照次数；引擎必须用返回值排序。
# remaining=0 的最后一次缓速保留到该轮末，快照记录在 status.snapshot 中。
static func begin_round(actors: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ids: Array = actors.keys()
	ids.sort()
	for id in ids:
		var actor: Dictionary = actors[id]
		if int(actor.get("hp", 0)) <= 0:
			continue
		var reduction := 0.0
		var slow := _status(actor, "slow")
		var generation := -1
		if not slow.is_empty() and int(slow.remaining) > 0:
			reduction = clampf(float(slow.magnitude), 0.0, 1.0)
			generation = int(slow.generation)
			slow.remaining = int(slow.remaining) - 1
			slow.snapshot["round_snapshot_generation"] = generation
		var speed := float(actor.get("stats", {}).get("spd", 0)) * (1.0 - reduction)
		events.append(_event("round_snapshot", actor, {"effective_spd": speed, "speed_reduction": reduction, "slow_generation": generation}))
	return events

static func end_round(actors: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ids: Array = actors.keys()
	ids.sort()
	for id in ids:
		var actor: Dictionary = actors[id]
		if int(actor.get("hp", 0)) <= 0:
			continue
		var kept: Array = []
		for status in actor.get("statuses", []):
			if status.clock == "round_snapshot" and int(status.remaining) == 0 and int(status.snapshot.get("round_snapshot_generation", -1)) == int(status.generation):
				events.append(_event("status_removed", actor, {"status": status.duplicate(true), "reason": "last_snapshot_round_end"}))
			else:
				kept.append(status)
		actor.statuses = kept
	return events

static func cleanse(actor: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var kept: Array = []
	for status in actor.get("statuses", []):
		if CLEANSE_IDS.has(status.get("id", "")) and status.get("dispellable", false):
			events.append(_event("status_removed", actor, {"status": status.duplicate(true), "reason": "cleanse"}))
		else:
			kept.append(status)
	if not events.is_empty():
		actor.statuses = kept
	return events

# 打断与眩晕是独立效果。清醒只拒绝眩晕，不拒绝打断或软控制。
static func immunity(actor: Dictionary, effect: Dictionary) -> String:
	if int(actor.get("hp", 0)) <= 0:
		return "目标已倒地"
	var is_stun: bool = effect.get("status_id", effect.get("id", "")) == "stun"
	var is_interrupt: bool = effect.get("type", "") == "interrupt"
	var boss: Dictionary = actor.get("boss", {})
	var charging: bool = boss.get("charge_valid", false)
	var interruptible: bool = boss.get("charge_interruptible", true)
	if charging and not interruptible:
		if is_stun:
			return "不可打断蓄力期间免疫眩晕"
		if is_interrupt:
			return "当前蓄力不可打断"
	var awake := _status(actor, "awake")
	if is_stun and not awake.is_empty() and int(awake.get("remaining", 0)) > 0:
		return "清醒期间免疫眩晕"
	if is_interrupt and not charging:
		return "目标没有可打断蓄力"
	return ""

static func _next_generation(actor: Dictionary) -> int:
	var current := int(actor.get("status_generation", 0))
	for status in actor.get("statuses", []):
		current = maxi(current, int(status.get("generation", 0)))
	current = maxi(current, int(actor.get("shield", {}).get("generation", 0)))
	actor["status_generation"] = current + 1
	return current + 1

static func _index(actor: Dictionary, id: String) -> int:
	var statuses: Array = actor.get("statuses", [])
	for index in range(statuses.size()):
		if statuses[index].get("id", "") == id:
			return index
	return -1

static func _status(actor: Dictionary, id: String) -> Dictionary:
	var index := _index(actor, id)
	return actor.statuses[index] if index >= 0 else {}

static func _ignored(reason: String, previous: Dictionary = {}) -> Dictionary:
	return {"applied": false, "change": "ignored", "reason": reason, "previous": previous.duplicate(true)}

static func _event(type: String, actor: Dictionary, payload: Dictionary, source_id: String = "") -> Dictionary:
	var id: String = actor.get("actor_id", "")
	return {"sequence": 0, "type": type, "actor_id": source_id if not source_id.is_empty() else id, "target_id": id, "payload": payload}

static func _valid_status(status: Dictionary) -> bool:
	var id = status.get("id")
	var clock := "round_snapshot" if id == "slow" else ("next_owner_slot" if id in ["cover", "defend"] else "target_slot")
	return (id is String and (TARGET_SLOT_IDS.has(id) or id in ["slow", "cover", "defend"]) and status.get("source_id") is String and not status.get("source_id", "").is_empty()
		and (status.get("magnitude") is float or status.get("magnitude") is int) and is_finite(float(status.magnitude)) and float(status.magnitude) >= 0.0
		and status.get("remaining") is int and status.remaining > 0 and status.get("clock") == clock
		and status.get("dispellable") is bool and status.dispellable == CLEANSE_IDS.has(id) and status.get("snapshot") is Dictionary)

static func _valid_shield(shield: Dictionary) -> bool:
	return (shield.get("amount") is int and shield.amount > 0 and shield.get("remaining") is int and shield.remaining > 0
		and shield.get("clock") == "target_slot" and shield.get("source_id") is String and not shield.get("source_id", "").is_empty())
