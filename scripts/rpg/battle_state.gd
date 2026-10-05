# 只读硬约束验证：错误返回给调用者，不修复、扣费或推进 RNG。
class_name RpgBattleState
extends RefCounted

const Forms = preload("res://scripts/rpg/dual_form.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
static var _catalog_cache: RefCounted

const STAT_KEYS := ["hp", "mp", "atk", "matk", "def", "mdef", "spd"]
const CLASS_IDS := ["guard", "swordsman", "ranger", "mage", "healer", "controller"]
const PHASES := ["preparation", "round_start", "action_selection", "action_resolution", "action_end", "round_end", "outcome"]
const CLOCKS := ["target_slot", "round_snapshot", "next_owner_slot"]

static func validate(state: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not _plain(state):
		errors.append("快照只能包含 JSON 值，禁止 Node／Resource／非有限数字")
	if state.get("schema_version") != 1 or not state.get("schema_version") is int:
		errors.append("未知状态 schema_version")
	if not state.get("rules_version") is String or state.get("rules_version", "").is_empty():
		errors.append("缺少规则版本")
	for field in ["revision", "round", "queue_index"]:
		if not _natural(state.get(field)):
			errors.append("非法状态计数：" + field)
	if not state.get("seed") is int or not _rng_string(state.get("rng_state")):
		errors.append("seed 必须为整数，rng_state 必须为 64 位十进制字符串")
	if not PHASES.has(state.get("phase")):
		errors.append("未知战斗阶段")
	if not state.get("outcome") in ["", "victory", "defeat"]:
		errors.append("未知战果")
	for field in ["actors", "inventory", "accepted_commands"]:
		if not state.get(field) is Dictionary:
			errors.append("缺状态字典：" + field)
	if not state.get("actors") is Dictionary:
		return errors
	if _catalog_cache == null:
		_catalog_cache = Catalog.new()
		var catalog_errors: Array[String] = _catalog_cache.load_all()
		if not catalog_errors.is_empty():
			errors.append_array(catalog_errors)
	if state.get("rules_version") != _catalog_cache.rules_version:
		errors.append("状态规则版本与目录不符")
	var actors: Dictionary = state.actors
	for id in actors:
		if not id is String or id.is_empty() or not actors[id] is Dictionary:
			errors.append("角色索引非法")
			continue
		_validate_actor(id, actors[id], errors)
	if state.get("inventory") is Dictionary:
		for id in state.inventory:
			if not id is String or id.is_empty() or not _natural(state.inventory[id]):
				errors.append("库存不得为负／小数：" + str(id))
			elif _catalog_cache.get_definition("items", id).is_empty():
				errors.append("库存道具引用缺失：" + id)
	if not state.get("queue") is Array:
		errors.append("队列必须为数组")
	else:
		var seen: Dictionary = {}
		for id in state.queue:
			if not id is String or not actors.has(id) or seen.has(id):
				errors.append("队列重复／缺角色引用：" + str(id))
			seen[id] = true
		if state.get("queue_index") is int and state.queue_index > state.queue.size():
			errors.append("队列索引越界")
	if not state.get("active_actor_id") is String or (not state.get("active_actor_id", "").is_empty() and not actors.has(state.active_actor_id)):
		errors.append("活动角色引用非法")
	if state.get("phase") == "action_selection":
		if not state.get("queue") is Array or not _natural(state.get("queue_index")) or state.queue_index >= state.queue.size() or state.get("active_actor_id") != state.queue[state.queue_index]:
			errors.append("选择阶段活动角色必须对应当前队列槽")
	_validate_policy_fields(state, errors)
	_validate_engine_fields(state, errors)
	_validate_logs(state, errors)
	_validate_slot_consistency(state, errors)
	return errors

static func _validate_actor(id: String, actor: Dictionary, errors: Array[String]) -> void:
	if actor.get("actor_id") != id or not actor.get("side") in ["player", "enemy"]:
		errors.append(id + " 永久 ID／阵营非法")
	if not actor.get("class_id") is String or actor.get("class_id", "").is_empty() or (actor.get("side") == "player" and not CLASS_IDS.has(actor.get("class_id"))):
		errors.append(id + " 职业非法")
	if not actor.get("level") is int or actor.level < 1 or actor.level > 10:
		errors.append(id + " 等级非法")
	var stats = actor.get("stats")
	if not stats is Dictionary or stats.size() != 7:
		errors.append(id + " 七项属性非法")
	else:
		for key in STAT_KEYS:
			if not _natural(stats.get(key)) or (key == "hp" and stats[key] < 1):
				errors.append(id + " 属性非法：" + key)
		for key in ["hp", "mp"]:
			if not _natural(actor.get(key)) or (_natural(stats.get(key)) and actor[key] > stats[key]):
				errors.append(id + " 当前资源越界：" + key)
	for field in ["slot_count", "opportunity_count"]:
		if not _natural(actor.get(field)):
			errors.append(id + " 行动计数非法：" + field)
	if _natural(actor.get("slot_count")) and _natural(actor.get("opportunity_count")) and actor.opportunity_count > actor.slot_count:
		errors.append(id + " 可选机会超过行动槽")
	if not actor.get("revived_round") is int or actor.revived_round < -1:
		errors.append(id + " 复活轮非法")
	for field in ["equipment", "branch", "shield", "cooldown_until", "intent", "boss"]:
		if not actor.get(field) is Dictionary:
			errors.append(id + " 缺角色字典：" + field)
	if actor.get("equipment") is Dictionary:
		for slot in actor.equipment:
			var equipment_id = actor.equipment[slot]
			if not slot in ["weapon", "armor", "accessory"] or not equipment_id is String:
				errors.append(id + " 装备槽／ID 非法")
			elif not equipment_id.is_empty():
				var equipment: Dictionary = _catalog_cache.get_definition("equipment", equipment_id)
				if equipment.is_empty() or equipment.get("slot") != slot:
					errors.append(id + " 装备引用缺失／槽错配")
	if Forms.has_data(actor): errors.append_array(Forms.validate(actor, _catalog_cache))
	var available_skills := Forms.available_skills(actor, _catalog_cache)
	if actor.get("cooldown_until") is Dictionary:
		for skill in actor.cooldown_until:
			if not skill is String or not _natural(actor.cooldown_until[skill]) or not actor.get("skill_ids") is Array or not available_skills.has(skill):
				errors.append(id + " 冷却计数非法")
	if not actor.get("skill_ids") is Array or (actor.get("side") == "player" and actor.skill_ids.size() != 4):
		errors.append(id + " 技能卡位非法")
	else:
		var skills: Dictionary = {}
		for skill in actor.skill_ids:
			if not skill is String or skill.is_empty() or skills.has(skill):
				errors.append(id + " 技能 ID 非法／重复")
			skills[skill] = true
			if _catalog_cache.get_definition("abilities", str(skill)).is_empty():
				errors.append(id + " 技能引用缺失")
		if actor.get("side") == "player":
			var definition: Dictionary = _catalog_cache.get_definition("classes", Forms.active_class(actor))
			if actor.skill_ids != definition.get("skill_ids", []):
				errors.append(id + " 职业固定卡位不符")
	if not actor.get("statuses") is Array:
		errors.append(id + " 状态数组非法")
	else:
		var statuses: Dictionary = {}
		for status in actor.statuses:
			if not status is Dictionary:
				errors.append(id + " 状态结构非法")
				continue
			for field in ["id", "source_id"]:
				if not status.get(field) is String or status.get(field, "").is_empty():
					errors.append(id + " 状态 ID／来源非法")
			if statuses.has(status.get("id")):
				errors.append(id + " 同名状态不得叠层")
			statuses[status.get("id")] = true
			if not status.get("magnitude") is float or not is_finite(status.get("magnitude", NAN)) or status.get("magnitude", -1) < 0 or not CLOCKS.has(status.get("clock")):
				errors.append(id + " 状态强度／时钟非法")
			for field in ["remaining", "generation", "applied_slot"]:
				if not _natural(status.get(field)):
					errors.append(id + " 状态计数非法：" + field)
			if not status.get("dispellable") is bool or not status.get("snapshot") is Dictionary:
				errors.append(id + " 状态快照／驱散性非法")
			var definition: Dictionary = _catalog_cache.get_definition("statuses", str(status.get("id", "")))
			if definition.is_empty():
				errors.append(id + " 状态引用缺失")
			elif status.get("clock") != definition.clock or status.get("dispellable") != definition.dispellable:
				errors.append(id + " 状态时钟／驱散性与目录冲突")
	if actor.get("shield") is Dictionary and not actor.shield.is_empty():
		if not _natural(actor.shield.get("amount")):
			errors.append(id + " 护盾量非法")

static func _natural(value) -> bool:
	return value is int and value >= 0

static func _plain(value) -> bool:
	if value == null or value is bool or value is int or value is String:
		return true
	if value is float:
		return is_finite(value)
	if value is Array:
		for item in value:
			if not _plain(item):
				return false
		return true
	if value is Dictionary:
		for key in value:
			if not key is String or not _plain(value[key]):
				return false
		return true
	return false

static func _rng_string(value) -> bool:
	if not value is String or value.is_empty():
		return false
	var digits: String = value.trim_prefix("-")
	if digits.is_empty() or (digits.length() > 1 and digits.begins_with("0")):
		return false
	for character in digits:
		if character < "0" or character > "9":
			return false
	var limit := "9223372036854775808" if value.begins_with("-") else "9223372036854775807"
	return digits.length() < limit.length() or (digits.length() == limit.length() and digits <= limit)

# JSON解码只规范明确声明的整数位置，小数非法值保留给严格验证器拒绝。
static func normalize_snapshot(saved: Dictionary) -> Dictionary:
	var state := saved.duplicate(true)
	_int_fields(state, ["schema_version", "revision", "seed", "round", "queue_index", "event_sequence"])
	for field in ["inventory", "accepted_commands"]:
		if state.get(field) is Dictionary: _int_fields(state[field], state[field].keys())
	if state.get("actors") is Dictionary:
		for actor in state.actors.values():
			if not actor is Dictionary: continue
			_int_fields(actor, ["level", "hp", "mp", "slot_count", "opportunity_count", "revived_round", "status_generation", "last_slot_round", "dual_form_version"])
			for field in ["stats", "cooldown_until"]:
				if actor.get(field) is Dictionary: _int_fields(actor[field], actor[field].keys())
			if actor.get("boss") is Dictionary:
				_int_fields(actor.boss, ["step", "phase", "pending_phase", "pending_phase_round"])
				for field in ["opportunity_thresholds", "opportunity_revived_rounds"]:
					if actor.boss.get(field) is Dictionary: _int_fields(actor.boss[field], actor.boss[field].keys())
				for field in ["committed_coefficient", "committed_phase_multiplier"]:
					if actor.boss.get(field) is int: actor.boss[field] = float(actor.boss[field])
			if actor.get("intent") is Dictionary: _normalize_log_in_place(actor.intent.get("preview", {}))
			if actor.get("shield") is Dictionary: _int_fields(actor.shield, ["amount", "remaining", "generation", "applied_slot"])
			if actor.get("statuses") is Array:
				for status in actor.statuses:
					if not status is Dictionary: continue
					_int_fields(status, ["remaining", "generation", "applied_slot"])
					if status.get("magnitude") is int: status.magnitude = float(status.magnitude)
					if status.get("snapshot") is Dictionary: _int_fields(status.snapshot, ["round_snapshot_generation"])
	if state.get("slot_token") is Dictionary:
		_int_fields(state.slot_token, ["slot_count", "shield_generation", "stun_generation"])
		if state.slot_token.get("events") is Array: _normalize_log_in_place(state.slot_token.events)
		if state.slot_token.get("status_generations") is Dictionary: _int_fields(state.slot_token.status_generations, state.slot_token.status_generations.keys())
	if state.get("command_log") is Array:
		for command in state.command_log:
			if command is Dictionary: _int_fields(command, ["expected_revision"])
	if state.get("event_log") is Array:
		for item in state.event_log:
			if item is Dictionary: _normalize_log_in_place(item)
	return state

static func _int_fields(value: Dictionary, fields: Array) -> void:
	for field in fields:
		var number = value.get(field)
		if number is float and is_finite(number) and number == floor(number): value[field] = int(number)

static func _validate_engine_fields(state: Dictionary, errors: Array[String]) -> void:
	for actor in state.actors.values():
		if not actor is Dictionary: continue
		for field in ["status_generation", "last_slot_round"]:
			if actor.has(field) and not _natural(actor[field]): errors.append("角色扩展计数非法：" + field)
		var shield = actor.get("shield")
		if shield is Dictionary and not shield.is_empty():
			for field in ["remaining", "generation", "applied_slot"]:
				if not _natural(shield.get(field)): errors.append("护盾计数非法：" + field)
			if shield.get("clock") != "target_slot" or not shield.get("source_id") is String: errors.append("护盾时钟／来源非法")
	# 旧准备态夹具仍可用于纯数据验证；引擎快照一旦带token就必须满足完整协议。
	if state.get("phase") == "action_selection" and not state.has("slot_token"):
		errors.append("选择阶段缺少权威行动槽token")
	if state.has("slot_token"):
		var token = state.slot_token
		if not token is Dictionary:
			errors.append("行动槽token必须为字典")
		elif state.get("phase") == "action_selection":
			var actor: Dictionary = state.actors.get(state.get("active_actor_id", ""), {})
			if token.get("actor_id") != state.get("active_actor_id") or token.get("slot_count") != actor.get("slot_count") or token.get("begun") != true or token.get("ended") != false or token.get("stunned") != false or token.get("defeated") != false:
				errors.append("活动槽token与选择机会不符")
			if not _natural(token.get("slot_count")) or not token.get("status_generations") is Dictionary or not token.get("events") is Array:
				errors.append("行动槽token计数／事件非法")
			for field in ["shield_generation", "stun_generation"]:
				if not token.get(field) is int or token[field] < -1: errors.append("行动槽generation非法")
			if token.get("status_generations") is Dictionary:
				for generation in token.status_generations.values():
					if not _natural(generation): errors.append("行动槽状态generation非法")
				_validate_waiting_generations(actor, token, errors)
		elif not token.is_empty(): errors.append("非选择阶段不得保留活动token")
	if state.get("accepted_commands") is Dictionary:
		for id in state.accepted_commands:
			if not id is String or id.is_empty() or not _natural(state.accepted_commands[id]) or state.accepted_commands[id] < 1 or (state.get("revision") is int and state.accepted_commands[id] > state.revision): errors.append("已执行指令记录非法")
	if state.has("event_sequence") and not _natural(state.event_sequence): errors.append("事件序号非法")
	for field in ["event_log", "command_log"]:
		if state.has(field) and not state[field] is Array: errors.append("日志必须为数组：" + field)

# 事件中的连续乘区仍保持浮点；只有规范列出的离散计数恢复整数。
static func _normalize_log_in_place(value) -> void:
	if value is Dictionary:
		_int_fields(value, ["sequence", "round", "slot_count", "opportunity_count", "slow_generation", "shield_generation", "stun_generation", "remaining", "generation", "applied_slot", "round_snapshot_generation", "expected_revision", "revision", "damage", "normal", "critical_damage", "absorbed", "hp_loss", "hp_before", "hp_after", "shield_before", "shield_after", "mp_before", "mp_after", "inventory_before", "inventory_after", "cooldown_until", "before", "after", "amount", "actual", "hp", "mp"])
		for child in value.values(): _normalize_log_in_place(child)
	elif value is Array:
		for child in value: _normalize_log_in_place(child)

static func _validate_logs(state: Dictionary, errors: Array[String]) -> void:
	if state.get("event_log") is Array:
		if state.get("event_sequence") != state.event_log.size(): errors.append("事件序号与日志长度不符")
		for index in range(state.event_log.size()):
			var item = state.event_log[index]
			if not item is Dictionary:
				errors.append("事件必须为字典")
				continue
			if not item.get("sequence") is int or item.sequence != index + 1: errors.append("事件序号不连续")
			for field in ["type", "actor_id", "target_id"]:
				if not item.get(field) is String: errors.append("事件字符串字段非法")
			if not item.get("payload") is Dictionary: errors.append("事件payload非法")
	if state.get("command_log") is Array:
		if state.get("revision") != state.command_log.size(): errors.append("修订号与执行指令数不符")
		var seen: Dictionary = {}
		for index in range(state.command_log.size()):
			var command = state.command_log[index]
			if not command is Dictionary or not command.get("command_id") is String:
				errors.append("指令日志结构非法")
				continue
			if command.get("kind") is String and command.kind == "switch_form" and not Forms.valid_switch_command(command): errors.append("切换形态日志结构非法")
			var id: String = command.command_id
			if id.is_empty() or seen.has(id) or not state.get("accepted_commands") is Dictionary or state.accepted_commands.get(id) != index + 1: errors.append("执行指令索引不一致")
			seen[id] = true
		if state.get("accepted_commands") is Dictionary and state.accepted_commands.size() != seen.size(): errors.append("执行指令索引含缺失记录")

# 已发布引擎快照的游标必须与本轮已经开始的槽一致；无需重演完整历史。
static func _validate_slot_consistency(state: Dictionary, errors: Array[String]) -> void:
	if not state.has("event_sequence") or not state.get("queue") is Array or not _natural(state.get("queue_index")) or not _natural(state.get("round")):
		return
	var phase = state.get("phase")
	var round_number: int = state.round
	var cursor: int = state.queue_index
	if not phase in ["preparation", "action_selection", "action_end", "round_end", "outcome"]:
		errors.append("快照处于不可恢复的原子结算中间阶段")
	if phase != "action_selection" and state.get("active_actor_id", "") != "":
		errors.append("非选择阶段不得遗留活动角色")
	if state.get("outcome") is String and (phase == "outcome") != (not state.outcome.is_empty()):
		errors.append("终局阶段与战果不符")
	if phase == "preparation":
		if round_number != 0 or not state.queue.is_empty() or cursor != 0: errors.append("准备阶段不得含已开始轮次或队列")
	elif phase != "outcome" and round_number == 0:
		errors.append("行动阶段必须已开始轮次")
	if phase == "round_end" and cursor != state.queue.size(): errors.append("轮末游标必须已消费整轮队列")
	for id in state.actors:
		var actor = state.actors[id]
		if not actor is Dictionary: continue
		var last_round = actor.get("last_slot_round", 0)
		if not _natural(last_round): continue
		if last_round > round_number: errors.append("角色行动槽记录来自未来轮次")
		if round_number > 0 and last_round == round_number and not state.queue.has(id): errors.append("本轮已开始槽的角色不在本轮队列")
	for index in range(state.queue.size()):
		var actor = state.actors.get(state.queue[index])
		if not actor is Dictionary or not _natural(actor.get("hp")): continue
		var begun: bool = round_number > 0 and actor.get("last_slot_round", 0) == round_number
		var waiting: bool = phase == "action_selection" and index == cursor
		if waiting:
			if not begun or actor.hp <= 0 or actor.get("revived_round") == round_number:
				errors.append("选择阶段必须对应本轮已开始且可行动的槽")
		elif index >= cursor and begun:
			errors.append("未消费游标指向本轮已开始的行动槽")
		elif index < cursor and not begun and actor.hp > 0 and actor.get("revived_round") != round_number:
			errors.append("游标越过了尚未开始的存活行动槽")

# 等待期必须保留全部既存代；本槽新增/刷新代只允许旧代标记，避免错误扣时长。
static func _validate_waiting_generations(actor: Dictionary, token: Dictionary, errors: Array[String]) -> void:
	if not _natural(actor.get("slot_count")) or not actor.get("statuses") is Array or not actor.get("shield") is Dictionary:
		return
	var slot: int = actor.slot_count
	var generations: Dictionary = token.status_generations
	var accounted: Dictionary = {}
	for status in actor.statuses:
		if not status is Dictionary or not _natural(status.get("applied_slot")) or not _natural(status.get("generation")) or not _natural(status.get("remaining")):
			continue
		if status.applied_slot > slot: errors.append("状态生效槽来自未来")
		if status.get("clock") != "target_slot" or status.remaining <= 0: continue
		var id = status.get("id")
		if status.applied_slot < slot:
			if generations.get(id) != status.generation: errors.append("等待token缺少或错配既存状态代")
			if id == "stun": errors.append("既存眩晕槽不得进入选择")
		else:
			if generations.has(id) and (not _natural(generations[id]) or generations[id] >= status.generation): errors.append("本槽新增状态不得登记为既存代")
		accounted[id] = true
	for id in generations:
		if not accounted.has(id): errors.append("等待token含无对应状态的额外代")
	if token.get("stun_generation") != -1: errors.append("选择槽不应有已消费眩晕代")
	var shield: Dictionary = actor.shield
	# 灼烧可能在begin_slot中耗尽旧盾；其吸收事件仍保留旧盾的完整代。
	var old_shield: Dictionary = {}
	var burned := false
	if token.get("events") is Array:
		for item in token.events:
			if item is Dictionary and item.get("type") == "periodic_damage" and item.get("payload") is Dictionary and item.payload.get("absorption") is Dictionary:
				var before = item.payload.absorption.get("shield_before")
				if before is Dictionary:
					old_shield = before
					burned = true
					break
	if burned:
		if token.get("shield_generation") != old_shield.get("generation", -1): errors.append("等待token与槽开始灼烧前护盾代不符")
	elif shield.is_empty():
		if token.get("shield_generation") != -1: errors.append("无既存护盾却含护盾代")
	elif _natural(shield.get("applied_slot")) and _natural(shield.get("generation")):
		if shield.applied_slot > slot: errors.append("护盾生效槽来自未来")
		elif shield.applied_slot < slot:
			if token.get("shield_generation") != shield.generation: errors.append("等待token缺少或错配既存护盾代")
		elif token.get("shield_generation") is int and token.shield_generation >= shield.generation:
			errors.append("本槽新增护盾不得登记为既存代")

# 新策略字段也参与恢复验证；旧纯免疫夹具仅有三个通用蓄力标记，保持兼容。
static func _validate_policy_fields(state: Dictionary, errors: Array[String]) -> void:
	for actor in state.actors.values():
		if not actor is Dictionary: continue
		var intent = actor.get("intent")
		if intent is Dictionary and not intent.is_empty():
			if intent.size() != 8: errors.append("意图必须包含固定八字段")
			var ability = intent.get("ability_id")
			if not ability is String or (not ability in ["attack_physical", "attack_magic"] and _catalog_cache.get_definition("abilities", str(ability)).is_empty()): errors.append("意图技能非法")
			if not intent.get("damage_type") in ["none", "physical", "magic"] or not intent.get("element") in ["neutral", "fire", "ice", "lightning", "spirit"]: errors.append("意图伤害类型非法")
			for field in ["locked", "interruptible"]:
				if not intent.get(field) is bool: errors.append("意图布尔字段非法：" + field)
			_validate_actor_references(intent.get("target_ids"), state, errors, "意图目标")
			if not intent.get("added_statuses") is Array: errors.append("意图附加状态非法")
			else:
				for id in intent.added_statuses:
					if not id is String or _catalog_cache.get_definition("statuses", str(id)).is_empty(): errors.append("意图附加状态引用非法")
			if not intent.get("preview") is Dictionary: errors.append("意图预览必须为字典")
			elif intent.preview.has("actor_id") and intent.preview.actor_id != actor.get("actor_id"): errors.append("意图预览拥有者与角色不符")
		var boss = actor.get("boss")
		if not boss is Dictionary or boss.is_empty(): continue
		var runtime := false
		for key in boss:
			if not key in ["charge_valid", "charge_interruptible", "charge_interrupted"]: runtime = true
		if not runtime: continue
		var errors_before := errors.size()
		if actor.get("class_id") != "gatekeeper" or actor.get("side") != "enemy": errors.append("Boss循环只能属于守关者")
		if not boss.get("step") is int or not boss.get("step") in [1, 2, 3, 4, 5, 6]: errors.append("Boss步骤非法")
		if not boss.get("phase") is int or not boss.get("phase") in [1, 2]: errors.append("Boss阶段非法")
		if not boss.get("pending_phase") is int or not boss.get("pending_phase") in [0, 2]: errors.append("Boss预约阶段非法")
		var pending_round = boss.get("pending_phase_round")
		if not pending_round is int or pending_round < -1 or (state.get("round") is int and pending_round > state.round): errors.append("Boss预约轮次非法")
		elif boss.get("pending_phase") is int and ((boss.pending_phase == 0 and pending_round != -1) or (boss.pending_phase == 2 and (pending_round < 0 or boss.get("phase") != 1))): errors.append("Boss预约阶段与轮次不符")
		for field in ["charge_valid", "charge_interruptible", "charge_interrupted", "charge_fallback"]:
			if not boss.get(field) is bool: errors.append("Boss蓄力标记非法：" + field)
		_validate_actor_references(boss.get("locked_targets"), state, errors, "Boss锁定目标", actor.get("side", ""))
		for field in ["opportunity_thresholds", "opportunity_revived_rounds"]:
			if not boss.get(field) is Dictionary:
				errors.append("Boss机会字典非法：" + field)
				continue
			for id in boss[field]:
				var count = boss[field][id]
				if not id is String or not state.actors.get(id) is Dictionary or state.actors[id].get("side") == actor.get("side"):
					errors.append("Boss机会角色引用非法")
				if not count is int or count < (1 if field == "opportunity_thresholds" else -1): errors.append("Boss机会计数非法")
		if boss.get("opportunity_thresholds") is Dictionary and boss.get("opportunity_revived_rounds") is Dictionary:
			var threshold_keys: Array = boss.opportunity_thresholds.keys()
			var revival_keys: Array = boss.opportunity_revived_rounds.keys()
			threshold_keys.sort()
			revival_keys.sort()
			if threshold_keys != revival_keys: errors.append("Boss机会与复活索引不一致")
		if not boss.get("committed_coefficient") is float or boss.get("committed_coefficient", -1.0) < 0.0: errors.append("Boss承诺系数非法")
		if not boss.get("committed_phase_multiplier") is float or not boss.get("committed_phase_multiplier") in [1.0, 1.2]: errors.append("Boss承诺阶段倍率非法")
		if not boss.get("release_id") is String or not boss.get("release_id") in ["", "boss_pierce_release", "boss_pulse_release"]: errors.append("Boss释放ID非法")
		if errors.size() != errors_before: continue
		if boss.charge_valid:
			var expected: String = "boss_pierce_release" if boss.get("step") == 3 else "boss_pulse_release"
			if not boss.get("step") in [3, 6] or boss.get("release_id") != expected or boss.get("charge_interrupted") != false or boss.get("charge_fallback") != false: errors.append("Boss有效蓄力与步骤冲突")
			if boss.get("locked_targets") is Array and boss.locked_targets.is_empty(): errors.append("Boss有效蓄力缺少锁定目标")
			if boss.get("opportunity_thresholds") is Dictionary and boss.opportunity_thresholds.is_empty(): errors.append("Boss有效蓄力缺少反应门槛")
			if boss.get("committed_coefficient") is float and boss.committed_coefficient <= 0.0: errors.append("Boss有效蓄力系数必须为正")
			if boss.get("charge_interruptible") != (boss.get("step") == 3): errors.append("Boss蓄力保护与步骤冲突")
		if boss.get("charge_interrupted") == true and (boss.get("step") != 3 or boss.get("charge_valid") != false): errors.append("Boss打断只能取消穿刺释放")
		if boss.get("charge_fallback") == true and (not boss.get("step") in [3, 6] or boss.get("charge_valid") != false): errors.append("Boss普通攻击替代与步骤冲突")
		if intent is Dictionary and not intent.is_empty():
			var definition: Dictionary = _catalog_cache.get_definition("enemies", "gatekeeper")
			var expected_ability: String = definition.boss.cycle[boss.step - 1]
			var preparing: Dictionary = _catalog_cache.get_definition("abilities", expected_ability)
			if (boss.step in [3, 6] and boss.charge_fallback) or (boss.step in [2, 5] and _natural(actor.get("mp")) and actor.mp < int(preparing.mp_cost)): expected_ability = "attack_physical"
			if intent.get("ability_id") != expected_ability: errors.append("Boss意图技能与循环步骤不符")
			var locked: bool = boss.step in [3, 6] and not boss.charge_fallback
			if not intent.get("locked") is bool or intent.locked != locked: errors.append("Boss意图锁定标记与步骤不符")
			if locked and intent.get("target_ids") != boss.locked_targets: errors.append("Boss意图目标与蓄力承诺不符")

static func _validate_actor_references(value, state: Dictionary, errors: Array[String], label: String, opposing_side: String = "") -> void:
	if not value is Array:
		errors.append(label + "必须为数组")
		return
	var seen: Dictionary = {}
	for id in value:
		if not id is String or not state.actors.get(id) is Dictionary or seen.has(id):
			errors.append(label + "含缺失／重复角色")
		else:
			seen[id] = true
			if not opposing_side.is_empty() and state.actors[id].get("side") == opposing_side: errors.append(label + "阵营错误")
