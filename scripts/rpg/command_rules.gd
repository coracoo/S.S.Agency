# 所有确认前检查集中于只读预览；目标/效果从目录推导，不信任客户端效果。
class_name RpgCommandRules
extends RefCounted

const Forms = preload("res://scripts/rpg/dual_form.gd")
const Resolver = preload("res://scripts/rpg/effect_resolver.gd")
const State = preload("res://scripts/rpg/battle_state.gd")

static func preview(state: Dictionary, command: Dictionary, catalog: RefCounted) -> Dictionary:
	var reasons: Array[String] = []
	var result := {"legal": false, "reasons": reasons, "effective_target_ids": [], "mp_cost": 0, "item_cost": 0, "cooldown": 0, "effects": [], "damage_ranges": [], "revision": state.get("revision", 0)}
	if not _valid_command(command):
		reasons.append("指令结构非法")
		return result
	if not State.validate(state).is_empty():
		reasons.append("战斗状态非法")
		return result
	if state.phase != "action_selection" or not state.outcome.is_empty() or command.actor_id != state.active_actor_id:
		reasons.append("当前不是该角色的选择机会")
	if command.expected_revision != state.revision:
		reasons.append("预览已过期，请重新选择")
	if state.accepted_commands.has(command.command_id):
		reasons.append("该指令已经执行")
	if not state.actors.has(command.actor_id):
		reasons.append("角色不存在")
		return result
	var source: Dictionary = state.actors[command.actor_id]
	if source.hp <= 0:
		reasons.append("倒地角色不能行动")
	if command.kind == "switch_form":
		var reason := Forms.switch_reason(source, command.form_id)
		if not reason.is_empty(): reasons.append(reason)
		result["form_id"] = command.form_id
		result.legal = reasons.is_empty()
		return result
	var ability := Resolver.ability_for(source, command, catalog)
	if ability.is_empty():
		reasons.append("技能或道具不存在")
		return result
	if command.kind == "skill":
		if not source.skill_ids.has(command.ability_id): reasons.append("该角色没有此技能")
		if source.level < int(ability.get("unlock_level", 1)): reasons.append("技能尚未解锁")
		if int(source.cooldown_until.get(command.ability_id, 0)) > int(source.slot_count): reasons.append("技能冷却中")
		result.mp_cost = int(ability.get("mp_cost", 0))
		result.cooldown = int(ability.get("cooldown", 0))
		if source.mp < result.mp_cost: reasons.append("MP不足")
	elif command.kind == "item":
		result.item_cost = 1
		if source.side != "player": reasons.append("敌方不可使用队伍库存")
		if int(state.inventory.get(command.ability_id, 0)) < 1: reasons.append("道具库存不足")
	elif not command.ability_id.is_empty():
		reasons.append("基础指令不接受技能ID")
	if command.kind == "attack_magic" and source.side == "player" and not Forms.active_class(source) in ["mage", "healer", "controller"]:
		reasons.append("该职业没有魔法普攻")
	var targets := _targets(state, source, ability.target_rule, command.target_ids, reasons)
	result.effective_target_ids = targets.duplicate()
	if not reasons.is_empty():
		return result
	var resolved := command.duplicate(true)
	resolved.target_ids = targets
	var simulation := state.duplicate(true)
	var events := Resolver.resolve(simulation, resolved, catalog, null)
	result.effects = events.duplicate(true)
	var any_effect := false
	var pure_control := true
	for effect in ability.effects:
		if not effect.type in ["apply_status", "interrupt"]: pure_control = false
	for item in events:
		if item.type == "effect_ignored":
			reasons.append(item.payload.reason)
		else:
			any_effect = true
		if item.type == "damage":
			result.damage_ranges.append({"target_id": item.target_id, "original_target_id": item.payload.original_target_id, "normal": item.payload.normal, "critical": item.payload.critical_damage, "critical_chance": 0.05 if item.payload.can_crit else 0.0})
	# 附带无效控制只展示原因；纯控制至少有一个真正有效的施加或打断。
	if pure_control and not any_effect:
		if reasons.is_empty(): reasons.append("没有可生效目标")
		return result
	result.legal = true
	return result

static func _targets(state: Dictionary, source: Dictionary, rule: String, requested: Array, reasons: Array[String]) -> Array[String]:
	if rule == "committed_enemies":
		var locked: Array = source.boss.locked_targets
		if requested != locked: reasons.append("蓄力释放必须保留原锁定目标")
		var committed: Array[String] = []
		for id in locked:
			if not state.actors.has(id) or state.actors[id].side == source.side: reasons.append("蓄力目标引用非法")
			else: committed.append(id)
		return committed
	var candidates: Array[String] = []
	for id in state.actors:
		var actor: Dictionary = state.actors[id]
		var ally: bool = actor.side == source.side
		var valid := false
		match rule:
			"self": valid = id == source.actor_id and actor.hp > 0
			"other_ally": valid = ally and id != source.actor_id and actor.hp > 0
			"single_ally", "all_allies": valid = ally and actor.hp > 0
			"single_enemy", "all_enemies": valid = not ally and actor.hp > 0
			"fallen_ally": valid = ally and actor.hp == 0
		if valid: candidates.append(id)
	candidates.sort()
	if rule in ["all_allies", "all_enemies", "self"]:
		var sorted := requested.duplicate()
		sorted.sort()
		if not requested.is_empty() and sorted != candidates: reasons.append("目标集合与技能规则不符")
		if candidates.is_empty(): reasons.append("没有合法目标")
		return candidates
	if requested.size() != 1 or not candidates.has(requested[0]):
		reasons.append("请选择一个合法目标")
		return []
	return [requested[0]]

static func _valid_command(command: Dictionary) -> bool:
	if command.get("kind") is String and command.kind == "switch_form": return Forms.valid_switch_command(command)
	if command.size() != 6:
		return false
	for key in ["command_id", "actor_id", "kind", "ability_id"]:
		if not command.get(key) is String: return false
	if command.command_id.is_empty() or command.actor_id.is_empty() or not command.kind in ["attack_physical", "attack_magic", "defend", "skill", "item"]:
		return false
	if not command.get("expected_revision") is int or not command.get("target_ids") is Array:
		return false
	for id in command.target_ids:
		if not id is String: return false
	return true
