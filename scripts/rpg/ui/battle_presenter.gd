# 纯投影：只读模型、目录与解析器事件，不持有第二套战斗计算。
class_name RpgBattlePresenter
extends RefCounted
const Resolver = preload("res://scripts/rpg/effect_resolver.gd")
static var presentation: Dictionary = {}

static func presentation_name(actor: Dictionary, definition: Dictionary) -> String:
	if presentation.is_empty(): presentation = JSON.parse_string(FileAccess.get_file_as_string("res://data/rpg/presentation.json"))
	return presentation.get("enemy_labels", {}).get(actor.class_id, definition.get("name", actor.class_id)) if actor.side == "enemy" else definition.get("name", actor.class_id)

const BASIC_NAMES := {"attack_physical": "物理普攻", "attack_magic": "中性魔攻", "defend": "防御", "item": "道具"}
const TARGET_SHORT := {"self": "自身", "other_ally": "队友", "single_ally": "单友", "all_allies": "全友", "single_enemy": "单敌", "all_enemies": "全敌", "fallen_ally": "倒地"}
const TARGET_NAMES := {"self": "自身", "other_ally": "其他队员", "single_ally": "一名队员", "all_allies": "全体队员", "single_enemy": "一名敌人", "all_enemies": "全体敌人", "fallen_ally": "倒地队员"}
const CLOCK_NAMES := {"target_slot": "行动", "round_snapshot": "轮序", "next_owner_slot": "至下次行动"}

static func present(state: Dictionary, catalog: RefCounted, display_actor_id: String = "") -> Dictionary:
	var actors: Array[Dictionary] = []
	var ids: Array = state.get("actors", {}).keys()
	ids.sort()
	for id in ids:
		var actor: Dictionary = state.actors[id]
		var definition: Dictionary = catalog.get_definition("classes" if actor.side == "player" else "enemies", actor.class_id)
		var statuses: Array[String] = []
		for status in actor.statuses:
			statuses.append("%s %s%s" % [catalog.get_definition("statuses", status.id).get("name", status.id), clock_text(status.clock, status.remaining), ""])
		var intent: Dictionary = actor.intent.duplicate(true)
		if not intent.is_empty():
			intent["name"] = ability_name(intent.ability_id, catalog)
			intent["text"] = intent_text(intent, actor, state, catalog)
		actors.append({"actor_id": id, "side": actor.side, "class_id": actor.class_id, "name": presentation_name(actor, definition), "label": actor_name(actor, catalog), "hp": actor.hp, "max_hp": actor.stats.hp, "mp": actor.mp, "max_mp": actor.stats.mp, "shield": actor.shield.get("amount", 0), "shield_remaining": actor.shield.get("remaining", 0), "statuses": statuses, "intent": intent, "level": actor.level, "active": id == state.get("active_actor_id", "")})
	var active: Dictionary = state.get("actors", {}).get(display_actor_id if not display_actor_id.is_empty() else state.get("active_actor_id", ""), {})
	var skills: Array[Dictionary] = []
	var basic: Array[String] = ["attack_physical", "defend", "item"]
	if not active.is_empty() and active.side == "player":
		for skill_id in catalog.get_definition("classes", active.class_id).skill_ids:
			var definition: Dictionary = Resolver.ability_for(active, {"kind": "skill", "ability_id": skill_id}, catalog)
			skills.append({"id": skill_id, "name": definition.name, "mp_cost": definition.mp_cost, "cooldown": definition.cooldown, "target_label": TARGET_NAMES.get(definition.target_rule, definition.target_rule), "target_short": TARGET_SHORT.get(definition.target_rule, ""), "effects": definition.effects.duplicate(true)})
		if active.class_id in ["mage", "healer", "controller"]: basic.push_front("attack_magic")
	return {"round": state.get("round", 0), "active_actor_id": state.get("active_actor_id", ""), "queue": state.get("queue", []).duplicate(), "queue_index": state.get("queue_index", 0), "actors": actors, "commands": {"skills": skills, "basic": basic}, "inventory": state.get("inventory", {}).duplicate(), "outcome": state.get("outcome", ""), "danger": danger_markers(state, catalog)}

# 意图的状态/取消/等待来自解析器预览；准备时只读已承诺释放的目录信息，不推算伤害。
static func intent_text(intent: Dictionary, actor: Dictionary, state: Dictionary, catalog: RefCounted) -> String:
	var targets: Array[String] = []
	for id in intent.get("target_ids", []): targets.append(actor_name(state.actors.get(id, {}), catalog))
	var lines: Array[String] = ["%s → %s" % [ability_name(intent.ability_id, catalog), "/".join(targets)]]
	var effects: Array = intent.get("preview", {}).get("effects", [])
	var release: Dictionary = {}
	var waiting := false
	var cancelled := false
	var empty := false
	var protected_charge := false
	for effect in effects:
		match effect.type:
			"charge_started":
				release = catalog.get_definition("abilities", effect.payload.release_id)
				protected_charge = not effect.payload.interruptible
			"charge_wait": waiting = true
			"boss_idle": cancelled = true
			"charge_empty": empty = true
	# 取消释放仍会保留 locked_targets，不据 locked && !interruptible 猜测保护。
	if cancelled:
		lines.append("释放取消 · 不造成伤害")
		return "\n".join(lines)
	if empty:
		lines.append("锁定目标倒地 · 空放")
		return "\n".join(lines)
	var damage_type: String = release.get("damage_type", intent.get("damage_type", "none"))
	var element: String = release.get("element", intent.get("element", "neutral"))
	lines.append("%s · %s" % [{"physical": "物理", "magic": "魔法", "none": "无直接伤害"}.get(damage_type, damage_type), {"neutral": "中性", "fire": "火属性", "spirit": "灵属性"}.get(element, element)])
	if actor.get("boss", {}).get("charge_valid", false) and not actor.boss.get("charge_interruptible", true): protected_charge = true
	if protected_charge: lines.append("不可打断，建议防御")
	elif intent.get("interruptible", false): lines.append("可打断" + (" · 目标锁定" if intent.get("locked", false) else ""))
	elif intent.get("locked", false): lines.append("目标锁定")
	if waiting: lines.append("继续蓄力 · 等待反应机会")
	var forecast: Array[String] = []
	for value in intent.get("preview", {}).get("damage_ranges", []): forecast.append("%s %d" % [actor_name(state.actors.get(value.target_id, {}), catalog), value.normal])
	if not forecast.is_empty(): lines.append("预计伤害 " + " / ".join(forecast))
	var by_target: Dictionary = {}
	for effect in effects:
		if effect.type not in ["status_applied", "status_refreshed"]: continue
		var status: Dictionary = effect.payload.get("status", effect.payload.get("after", {}))
		var detail := "%s · %s" % [catalog.get_definition("statuses", status.id).get("name", status.id), clock_text(status.clock, int(status.remaining))]
		if not by_target.has(effect.target_id): by_target[effect.target_id] = []
		if not by_target[effect.target_id].has(detail): by_target[effect.target_id].append(detail)
	if not by_target.is_empty():
		var common: Array = by_target.values()[0]
		var actual_ids: Array = by_target.keys()
		var intended_ids: Array = intent.target_ids.duplicate()
		actual_ids.sort()
		intended_ids.sort()
		if actual_ids == intended_ids and by_target.values().all(func(value): return value == common): lines.append("附加：" + " / ".join(common))
		else:
			for id in by_target: lines.append("%s：%s" % [actor_name(state.actors.get(id, {}), catalog), " / ".join(by_target[id])])
	elif waiting or not release.is_empty():
		# 等待机会时解析器没有应用事件，目录只说明未来效果，不伪称已应用。
		var ability: Dictionary = release if not release.is_empty() else catalog.get_definition("abilities", intent.ability_id)
		var status_lines: Array[String] = []
		for effect in ability.get("effects", []):
			if effect.type == "apply_status" and (not release.is_empty() or intent.get("added_statuses", []).has(effect.status_id)):
				status_lines.append("%s · %s" % [catalog.get_definition("statuses", effect.status_id).get("name", effect.status_id), clock_text(effect.clock, int(effect.duration))])
		if not status_lines.is_empty(): lines.append("预计附加：" + " / ".join(status_lines))
	return "\n".join(lines)

static func preview(engine: RefCounted, command: Dictionary) -> Dictionary:
	return engine.preview(command)

static func ability_name(id: String, catalog: RefCounted) -> String:
	return BASIC_NAMES.get(id, catalog.get_definition("items" if catalog.get_definition("abilities", id).is_empty() else "abilities", id).get("name", id))

static func actor_name(actor: Dictionary, catalog: RefCounted) -> String:
	if actor.is_empty(): return "无目标"
	var definition: Dictionary = catalog.get_definition("classes" if actor.side == "player" else "enemies", actor.class_id)
	var pieces: PackedStringArray = actor.actor_id.split("_")
	var suffix: String = pieces[1] if pieces.size() > 1 else actor.actor_id
	return presentation_name(actor, definition) + ("·" + suffix if actor.side == "enemy" else "")

static func preview_lines(value: Dictionary, state: Dictionary, catalog: RefCounted) -> Array[String]:
	var lines: Array[String] = []
	var targets: Array[String] = []
	for id in value.get("effective_target_ids", []): targets.append(actor_name(state.actors[id], catalog))
	if not targets.is_empty(): lines.append("目标：" + " / ".join(targets))
	for effect in value.get("effects", []):
		var who := actor_name(state.actors.get(effect.target_id, {}), catalog)
		var payload: Dictionary = effect.payload
		match effect.type:
			"damage": lines.append("%s：伤害 %d · 暴击 %d" % [who, payload.normal, payload.critical_damage])
			"healed": lines.append("%s：回复 HP %d（实际 %d）" % [who, payload.amount, payload.actual])
			"mp_restored": lines.append("%s：回复 MP %d（实际 %d）" % [who, payload.amount, payload.actual])
			"shield_applied", "shield_refreshed": lines.append("%s：护盾 %s" % [who, payload.get("shield", payload.get("after", {})).get("amount", payload.get("amount", ""))])
			"status_applied", "status_refreshed":
				var status: Dictionary = payload.get("status", payload.get("after", {}))
				lines.append("%s：%s %s" % [who, catalog.get_definition("statuses", status.get("id", "")).get("name", "状态"), clock_text(status.get("clock", "target_slot"), int(status.get("remaining", 0)))])
			"effect_ignored": lines.append("%s：无效 · %s" % [who, payload.reason])
			"charge_interrupted": lines.append(who + "：打断蓄力")
			"revived": lines.append("%s：复苏 HP %s" % [who, payload.get("hp", payload.get("after", ""))])
			"status_removed": lines.append(who + ("：消耗" if payload.get("reason") == "skill_consumed" else "：移除") + catalog.get_definition("statuses", payload.get("status", {}).get("id", "")).get("name", "状态"))
	for reason in value.get("reasons", []):
		if not lines.has(reason): lines.append(reason)
	return lines

static func event_line(event: Dictionary, state: Dictionary, catalog: RefCounted) -> String:
	var source := actor_name(state.actors.get(event.actor_id, {}), catalog)
	var target := actor_name(state.actors.get(event.target_id, {}), catalog)
	var p: Dictionary = event.payload
	match event.type:
		"damage": return "%s → %s  %s%d" % [source, target, "暴击 " if p.critical else "伤害 ", p.damage]
		"healed": return "%s  HP +%d" % [target, p.actual]
		"mp_restored": return "%s  MP +%d" % [target, p.actual]
		"actor_defeated": return target + " 倒地"
		"charge_started": return "%s 蓄力 · %s" % [source, "可打断" if p.interruptible else "不可打断"]
		"charge_interrupted": return target + " 蓄力被打断"
		"charge_wait": return source + " 继续蓄力 · 等待反应机会"
		"boss_idle": return source + " 释放取消"
		"charge_empty": return source + " 锁定目标倒地 · 空放"
		"boss_phase_started": return source + " 第二阶段 · 速度提升"
		"round_started": return "第 %s 轮" % p.get("round", state.round)
	return ""

static func compact_effect(preview_value: Dictionary, catalog: RefCounted) -> String:
	var parts: Array[String] = []
	for event in preview_value.get("effects", []):
		var payload: Dictionary = event.payload
		var text := ""
		match event.type:
			"damage": text = "伤%d / 暴%d" % [payload.normal, payload.critical_damage]
			"healed": text = "HP +%d" % payload.amount
			"mp_restored": text = "MP +%d" % payload.amount
			"shield_applied": text = "盾 %d · %d行动" % [payload.shield.amount, payload.shield.remaining]
			"status_applied":
				text = status_summary(payload.status.id, payload.status.magnitude, payload.status.clock, payload.status.remaining, catalog)
				if payload.status.id == "burn": text = "灼烧基数 %s · %s" % [payload.status.snapshot.get("base", payload.status.magnitude), clock_text(payload.status.clock, payload.status.remaining)]
			"charge_interrupted": text = "打断蓄力"
			"revived": text = "复苏 HP %d" % payload.hp
			"status_removed": text = "移除负面"
		if not text.is_empty() and not parts.has(text): parts.append(text)
	return " · ".join(parts)

static func clock_text(clock: String, remaining: int) -> String:
	if clock == "next_owner_slot": return "至下次行动"
	return "%d%s" % [remaining, "次轮序" if clock == "round_snapshot" else "次行动"]

# 常驻按钮显示目录基础效果；确切对象的伤害只在选定目标预览显示。
static func ability_summary(slot: Dictionary, preview_value: Dictionary, catalog: RefCounted) -> String:
	var parts: Array[String] = []
	for effect in slot.get("effects", []):
		var text := ""
		match effect.type:
			"damage":
				text = "%d%%%s" % [roundi(float(effect.coefficient) * 100), "魔攻" if effect.damage_type == "magic" else "物攻"]
				if effect.has("condition"):
					text += "；%s%d%%" % ["标记时" if effect.condition == "target_has_status" else "本轮目标未获行动槽时", roundi(float(effect.conditional_coefficient) * 100)]
			"consume_status": text = "消耗标记"
			"apply_status": text = status_summary(effect.status_id, effect.magnitude, effect.clock, effect.duration, catalog)
			"interrupt": text = "打断蓄力"
			"shield", "heal":
				for event in preview_value.get("effects", []):
					if effect.type == "shield" and event.type == "shield_applied":
						text = "盾%d·%s" % [event.payload.shield.amount, clock_text(event.payload.shield.clock, event.payload.shield.remaining)]
					if effect.type == "heal" and event.type == "healed": text = "HP +%d" % event.payload.amount
				if text.is_empty(): text = "%s + %s×%s" % [effect.fixed, effect.stat.to_upper(), effect.coefficient]
			"cleanse": text = "移除负面状态"
		if not text.is_empty() and not parts.has(text): parts.append(text)
	return " · ".join(parts)

# 标记／眩晕／挑衅是布尔状态，幅度1不是概率；灼烧目录幅度是MATK快照系数。
static func status_summary(id: String, magnitude: float, clock: String, remaining: int, catalog: RefCounted) -> String:
	var amount := "" if id in ["mark", "stun", "awake", "taunt"] else "%d%%" % roundi(magnitude * 100)
	if id == "burn": amount += "魔攻"
	return "%s%s·%s" % [catalog.get_definition("statuses", id).get("name", id), amount, clock_text(clock, remaining)]

# 只显示已经成功蓄力的承诺；倒地不重新选人，打断后立即移除危险标记。
static func danger_markers(state: Dictionary, catalog: RefCounted) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array = state.get("actors", {}).keys()
	ids.sort()
	for id in ids:
		var actor: Dictionary = state.actors[id]
		var boss: Dictionary = actor.get("boss", {})
		if actor.hp <= 0 or not boss.get("charge_valid", false): continue
		var release: Dictionary = catalog.get_definition("abilities", boss.get("release_id", ""))
		result.append({"actor_id": id, "target_ids": boss.get("locked_targets", []).duplicate(), "area": release.get("target_rule") == "all_enemies", "interruptible": boss.get("charge_interruptible", true)})
	return result

# 成长界面明确标为未来等级预览，只改临时副本，不升级或写角色。
static func branch_preview(actor: Dictionary, branch_id: String, catalog: RefCounted) -> String:
	if branch_id.is_empty(): return "无分支 · 保持基础四技能\nL6可选择一条分支；L9强化同一分支"
	var lines: Array[String] = ["%s分支预览（不改变当前等级/资源）" % {"economy": "节约", "duration": "持续", "power": "强度"}.get(branch_id, branch_id)]
	for level in [6, 9]:
		var projected := actor.duplicate(true)
		projected.level = level
		projected.branch = {"id": branch_id}
		for id in actor.skill_ids:
			var base: Dictionary = catalog.get_definition("skills", id)
			if not base.get("branches", {}).has(branch_id): continue
			var effective: Dictionary = catalog.skill_for(projected, id)
			lines.append("L%d · %s　MP%d · CD%d　%s" % [level, effective.name, effective.mp_cost, effective.cooldown, ability_summary(effective, {}, catalog)])
	return "\n".join(lines)

# 四卡第二行保留关键效果；长条件和状态幅度的完整说明留在同源tooltip与预览。
static func card_summary(slot: Dictionary, preview_value: Dictionary, catalog: RefCounted) -> String:
	var effects: Array = slot.get("effects", [])
	var has_damage: bool = effects.any(func(effect): return effect.type == "damage")
	if not has_damage and effects.size() == 1: return ability_summary(slot, preview_value, catalog)
	var parts: Array[String] = []
	for effect in effects:
		match effect.type:
			"damage":
				parts.append("%d%%%s" % [roundi(effect.coefficient * 100), "魔攻" if effect.damage_type == "magic" else "物攻"])
				if effect.has("condition"):
					parts.append("%s%d%%" % ["标记" if effect.condition == "target_has_status" else "先手", roundi(effect.conditional_coefficient * 100)])
			"apply_status":
				parts.append("%s%d%s" % [catalog.get_definition("statuses", effect.status_id).name, effect.duration, "轮序" if effect.clock == "round_snapshot" else "槽"])
			"interrupt": parts.append("打断")
	return " · ".join(parts)
