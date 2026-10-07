# 后六章机制只写战斗快照；同一管线供预览、确认、重放使用，不改玩家身份与共享资源。
class_name RpgSagaBossRules
extends RefCounted
const Status = preload("res://scripts/rpg/status_rules.gd")
const Damage = preload("res://scripts/rpg/damage_rules.gd")
const KINDS := {"saga_borrowed_voice": "voice", "saga_backshore_general": "banner", "saga_joined_mirror": "mirror", "saga_hundredhand_lamp": "lamp", "saga_nochange_warden": "warden", "saga_master_mirror": "master_mirror", "saga_lamp_bearer": "bearer", "saga_exit_recoil": "exit", "saga_relay_recoil": "relay", "saga_final_recoil": "recoil"}
const MEMORIES := ["physical", "magic", "guard", "heal", "control"]
const RUNTIME_KEYS := ["version", "kind", "step", "phase", "memory", "pending_memory", "interrupted", "repairs"]
static func is_actor(actor: Dictionary) -> bool:
	return actor.get("side") == "enemy" and KINDS.has(actor.get("class_id", ""))
static func initialize(actor: Dictionary) -> void:
	if not is_actor(actor) or actor.has("saga"): return
	actor["saga"] = {"version": 1, "kind": KINDS[actor.class_id], "step": 0, "phase": 1, "memory": "physical", "pending_memory": "physical", "interrupted": false, "repairs": 0}
static func validate(actor: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not actor.has("saga"):
		if is_actor(actor) and actor.get("intent") is Dictionary and not actor.intent.is_empty(): errors.append("已公布意图的Saga敌人缺少机制快照")
		return errors
	if not is_actor(actor) or not actor.saga is Dictionary: return ["Saga机制只能属于登记敌人"]
	var saga: Dictionary = actor.saga
	if actor.get("intent") is Dictionary and not actor.intent.is_empty() and actor.get("skill_ids") is Array:
		if not actor.skill_ids.has(actor.intent.get("ability_id")): errors.append("Saga意图不属于当前敌人的固定能力")
	if saga.size() != RUNTIME_KEYS.size(): errors.append("Saga机制字段不完整")
	for key in saga:
		if not key in RUNTIME_KEYS: errors.append("Saga机制含未知字段")
	if not saga.get("version") is int or saga.get("version") != 1 or saga.get("kind") != KINDS[actor.class_id]: errors.append("Saga机制版本或敌人归属非法")
	if not saga.get("step") is int or saga.get("step", -1) < 0 or saga.get("step", 6) > 5: errors.append("Saga机制步骤非法")
	if not saga.get("phase") is int or not saga.get("phase") in [1, 2, 3]: errors.append("Saga镜面阶段非法")
	for key in ["memory", "pending_memory"]:
		if not saga.get(key) in MEMORIES: errors.append("Saga回放行动非法")
	if not saga.get("interrupted") is bool: errors.append("Saga打断标记非法")
	if not saga.get("repairs") is int or saga.get("repairs", -1) < 0 or saga.get("repairs", 3) > 2: errors.append("Saga回补计数非法")
	return errors
static func normalize(actor: Dictionary) -> void:
	if not actor.get("saga") is Dictionary: return
	for key in ["version", "step", "phase", "repairs"]:
		var value = actor.saga.get(key)
		if value is float and is_finite(value) and value == floor(value): actor.saga[key] = int(value)
static func plan(state: Dictionary, actor_id: String, catalog: RefCounted) -> Dictionary:
	var actor: Dictionary = state.actors[actor_id]
	initialize(actor)
	var saga: Dictionary = actor.saga
	var ability_id := ""
	match saga.kind:
		"voice": ability_id = "saga_voice_rush" if actor.hp * 5 <= actor.stats.hp * 2 and saga.step == 2 else "saga_voice_" + saga.memory
		"banner": ability_id = ["saga_banner_raise", "saga_banner_release", "saga_banner_sweep"][saga.step % 3]
		"mirror": ability_id = ["saga_mirror_edge", "saga_mirror_water", "saga_mirror_open"][saga.phase - 1]
		"lamp": ability_id = ["saga_lamp_mark", "saga_lamp_drain", "saga_lamp_open"][saga.step % 3]
		"warden": ability_id = ["saga_repair_left_prepare", "saga_repair_left", "saga_warden_sweep", "saga_repair_right_prepare", "saga_repair_right", "saga_warden_sweep"][saga.step]
		"master_mirror": ability_id = ["saga_master_shallow", "saga_master_deep", "saga_master_open"][saga.phase - 1]
		"bearer": ability_id = ["saga_master_raise", "saga_master_command", "saga_master_erosion"][saga.step % 3]
		"exit": ability_id = "saga_exit_crash"
		"relay": ability_id = "saga_relay_wave"
		"recoil": ability_id = "saga_final_pressure"
	var definition: Dictionary = catalog.get_definition("abilities", ability_id)
	var targets: Array = []
	if definition.target_rule == "self": targets = [actor_id]
	elif definition.target_rule == "all_enemies": targets = opponents(state, actor_id)
	else: targets = pick(state, actor_id)
	var statuses: Array = []
	for effect in definition.effects:
		if effect.type == "apply_status": statuses.append(effect.status_id)
	return {"ability_id": ability_id, "target_ids": targets, "damage_type": definition.damage_type, "element": definition.element, "added_statuses": statuses, "interruptible": can_interrupt(actor), "locked": false, "preview": {"actor_id": actor_id, "hint": hint(state, actor_id)}}
static func opponents(state: Dictionary, actor_id: String) -> Array:
	var ids: Array = []
	for id in state.actors:
		if state.actors[id].side != state.actors[actor_id].side and state.actors[id].hp > 0: ids.append(id)
	ids.sort()
	return ids
static func pick(state: Dictionary, actor_id: String) -> Array:
	var ids := opponents(state, actor_id)
	for status in state.actors[actor_id].statuses:
		if status.id == "taunt" and status.remaining > 0 and ids.has(status.source_id): return [status.source_id]
	ids.sort_custom(func(a, b):
		var left := float(state.actors[a].hp) / float(state.actors[a].stats.hp)
		var right := float(state.actors[b].hp) / float(state.actors[b].stats.hp)
		return a < b if is_equal_approx(left, right) else left < right)
	return [] if ids.is_empty() else [ids[0]]
static func can_interrupt(actor: Dictionary) -> bool:
	if not is_actor(actor) or not actor.get("saga") is Dictionary or actor.hp <= 0 or actor.saga.interrupted: return false
	match actor.saga.kind:
		"voice": return not actor.saga.memory in ["guard", "heal"]
		"banner", "lamp", "bearer": return actor.saga.step % 3 == 1
		"warden": return actor.saga.step in [1, 4]
	return false
static func interrupt(state: Dictionary, target_id: String, source_id: String) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[target_id]
	if not can_interrupt(actor): return []
	actor.saga.interrupted = true
	var events: Array[Dictionary] = [{"sequence": 0, "type": "charge_interrupted", "actor_id": source_id, "target_id": target_id, "payload": {"text": "号令被打断，下一次回放／吸取／回补失效。"}}]
	var applied := Status.apply(actor, {"id": "stagger", "source_id": source_id, "magnitude": 0.2, "clock": "target_slot", "remaining": 1, "generation": 0, "applied_slot": 0, "dispellable": false, "snapshot": {}})
	if applied.applied: events.append(applied.event)
	return events
static func on_round_start(state: Dictionary, actor_id: String) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[actor_id]
	initialize(actor)
	if actor.hp <= 0: return []
	var previous: int = actor.saga.phase
	if actor.saga.kind in ["mirror", "master_mirror"]:
		actor.saga.phase = (maxi(1, int(state.round)) - 1) % 3 + 1
		actor.intent = {}
	elif actor.saga.kind == "voice":
		actor.saga.memory = actor.saga.pending_memory
		actor.intent = {}
		if int(state.round) > 1: return [_event("saga_voice_replay", actor_id, {"memory": actor.saga.memory, "text": "借声客开始回放上一轮最后的行动。"})]
	if actor.saga.phase != previous:
		return [_event("saga_phase", actor_id, {"phase": actor.saga.phase, "text": hint(state, actor_id)})]
	return []
static func after_command(state: Dictionary, command: Dictionary, catalog: RefCounted) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[command.actor_id]
	var events: Array[Dictionary] = []
	if actor.side == "player":
		for enemy in state.actors.values():
			if enemy.get("class_id") == "saga_borrowed_voice" and enemy.has("saga"):
				var current := _memory(actor, command, catalog)
				if current == "guard" and enemy.saga.memory in ["physical", "magic"]:
					events.append(_event("saga_voice_guarded", enemy.actor_id, {"text": "攻后转守：防护接住了即将回来的旧动作。"}))
				elif current in ["physical", "magic"] and enemy.saga.memory == "guard":
					events.append(_event("saga_voice_exploited", enemy.actor_id, {"text": "借声客仍在回放防守，现在可以改变攻势。"}))
				elif current in ["physical", "magic"] and current == enemy.saga.pending_memory and state.get("command_log", []).size() > 1:
					events.append(_event("saga_voice_repeated", enemy.actor_id, {"text": "相同攻势又被记下；可在下一轮转守或控制打断。"}))
				enemy.saga.pending_memory = current
	elif is_actor(actor):
		events.append_array(on_slot_end(state, actor.actor_id, false))
	# 背岸将和执灯纸躯倒下后，补位纸兵失去号令；并非把全场居民当敌人。
	for enemy in state.actors.values():
		if enemy.get("class_id") in ["saga_backshore_general", "saga_lamp_bearer"] and enemy.hp == 0:
			for support in state.actors.values():
				if support.class_id == "saga_paper_soldier" and support.hp > 0:
					support.hp = 0; support.statuses = []; support.shield = {}; support.intent = {}
					events.append(_event("saga_support_dismissed", support.actor_id, {"text": "旧号令已断，纸兵散去；撤离口保持通行。"}))
	return events
static func on_slot_end(state: Dictionary, actor_id: String, skipped: bool) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[actor_id]
	initialize(actor)
	var interrupted: bool = actor.saga.interrupted or (skipped and can_interrupt(actor))
	actor.saga.step = (int(actor.saga.step) + 1) % (6 if actor.saga.kind == "warden" else 3)
	actor.saga.interrupted = false
	return [_event("saga_step", actor_id, {"step": actor.saga.step, "interrupted": interrupted, "text": "控制打断了号令，趁空隙处理目标。" if interrupted else hint(state, actor_id)})]
static func _memory(actor: Dictionary, command: Dictionary, catalog: RefCounted) -> String:
	if command.kind == "defend": return "guard"
	if command.kind == "item": return "heal"
	if command.kind == "attack_magic": return "magic"
	if command.kind == "attack_physical": return "physical"
	# 借声记录基础24卡的主动作类别，不统计本次收益；专精/技法的返MP、回春、附盾
	# 不能把控制/战意改写成治疗/防守。此路径仅由上方player分支调用。
	var ability: Dictionary = catalog.get_definition("skills", command.ability_id)
	for effect in ability.get("effects", []):
		if effect.type in ["heal", "restore_hp", "restore_mp", "revive"]: return "heal"
		if effect.type == "damage": return "magic" if effect.damage_type == "magic" else "physical"
		if effect.type == "shield" or (effect.type == "apply_status" and effect.get("status_id") in ["defend", "cover"]): return "guard"
	return "control"
# 返回true代表本次已被控制取消。预览用副本调用，不能悄悄恢复号令。
static func cancelled(actor: Dictionary) -> bool:
	return is_actor(actor) and actor.get("saga", {}).get("interrupted", false)
static func modifiers(state: Dictionary, source: Dictionary, target: Dictionary, effect: Dictionary) -> Dictionary:
	if source.side != "player" or not is_actor(target): return {}
	initialize(target)
	if blocked(state, target): return {"damage_reductions": [1.0]}
	if target.saga.kind in ["mirror", "master_mirror"]:
		if reflecting(target, effect): return {"damage_reductions": [0.8]}
		if target.saga.phase == 3: return {"vulnerability_bonuses": [0.25]}
	if target.saga.kind == "lamp" and target.saga.step % 3 == 2: return {"vulnerability_bonuses": [0.25]}
	return {}
static func blocked(state: Dictionary, target: Dictionary) -> bool:
	match target.get("class_id", ""):
		"saga_nochange_warden": return _alive(state, ["saga_anchor_left", "saga_anchor_right"])
		"saga_relay_recoil": return _alive(state, ["saga_exit_recoil"])
		"saga_final_recoil": return _alive(state, ["saga_exit_recoil", "saga_relay_recoil"])
	return false
static func _alive(state: Dictionary, classes: Array) -> bool:
	for actor in state.actors.values():
		if actor.class_id in classes and actor.hp > 0: return true
	return false
static func reflecting(target: Dictionary, effect: Dictionary) -> bool:
	if not target.get("saga", {}).get("kind", "") in ["mirror", "master_mirror"]: return false
	return (target.saga.phase == 1 and effect.damage_type == "physical") or (target.saga.phase == 2 and effect.damage_type == "magic")
static func after_damage(state: Dictionary, source_id: String, target_id: String, effect: Dictionary, dealt: int, normal_dealt: int = -1, critical_dealt: int = -1) -> Array[Dictionary]:
	var source: Dictionary = state.actors[source_id]
	var target: Dictionary = state.actors[target_id]
	if source.side != "player" or not is_actor(target): return []
	if target.hp == 0 and target.saga.kind in ["exit", "relay", "recoil"]:
		var descriptions := {"exit": "出口反冲已压住，外侧接应可以通过；现在处理分流。", "relay": "中段分流完成，最后余压失去保护；可以关闭内圈。", "recoil": "最后余压卸下，出口与分流目标均已完成。"}
		return [_event("saga_objective_completed", target_id, {"objective": target.saga.kind, "text": descriptions[target.saga.kind]})]
	if blocked(state, target): return [_event("saga_objective_blocked", target_id, {"text": hint(state, target_id)})]
	if not reflecting(target, effect) or dealt <= 0: return []
	var amount := dealt * 2
	# 两种公开风险均从当前承伤者/护盾的深副本求值；真实资源只由下面一次absorb扣除。
	var normal_reflected := (normal_dealt if normal_dealt >= 0 else dealt) * 2
	var critical_reflected := (critical_dealt if critical_dealt >= 0 else dealt) * 2
	var normal_absorption := Damage.absorb(source.duplicate(true), normal_reflected)
	var critical_absorption := Damage.absorb(source.duplicate(true), critical_reflected)
	var absorption := Damage.absorb(source, amount)
	var events: Array[Dictionary] = [{"sequence": 0, "type": "saga_reflected", "actor_id": target_id, "target_id": source_id, "payload": {"damage": amount, "absorption": absorption, "normal": normal_reflected, "critical_damage": critical_reflected, "normal_hp_loss": normal_absorption.hp_loss, "critical_hp_loss": critical_absorption.hp_loss, "defeat_normal": normal_absorption.defeated, "defeat_critical": critical_absorption.defeated, "text": "镜面反射%s；换攻击类型或防守等待脱面。" % ("刀光" if effect.damage_type == "physical" else "术法")}}]
	if absorption.defeated: events.append(_event("actor_defeated", source_id, {"reason": "mirror_reflection"}))
	return events
static func after_ability(state: Dictionary, actor_id: String, ability: Dictionary, resolved: Array) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[actor_id]
	if not is_actor(actor) or actor.hp <= 0: return []
	var events: Array[Dictionary] = []
	var action: String = ability.get("saga_action", "")
	if action == "lamp_drain":
		var loss := 0
		for item in resolved:
			if item.type == "damage": loss += int(item.payload.absorption.hp_loss)
		var before: int = actor.hp
		actor.hp = mini(actor.stats.hp, actor.hp + roundi(loss * 0.5))
		var shield := Status.apply_shield(actor, {"amount": 25 + roundi(loss * 0.4), "source_id": actor_id, "clock": "target_slot", "remaining": 1})
		if shield.applied: events.append(shield.event)
		events.append(_event("saga_lamp_drained", actor_id, {"healed": actor.hp - before, "text": "灯母借吸取补回%d生命并罩灯；下次灯印后可打断。" % (actor.hp - before)}))
	elif action == "banner_release":
		for support in state.actors.values():
			if support.class_id == "saga_paper_soldier" and support.hp == 0:
				support.hp = maxi(1, roundi(support.stats.hp * 0.45)); support.revived_round = int(state.round)
				events.append(_event("saga_support_returned", support.actor_id, {"text": "纸兵依旧令补位；击断举旗者即可停止。"}))
	elif action in ["repair_left", "repair_right"]:
		var class_id := "saga_anchor_left" if action == "repair_left" else "saga_anchor_right"
		if actor.saga.repairs < 2:
			for anchor in state.actors.values():
				if anchor.class_id == class_id and anchor.hp == 0:
					anchor.hp = maxi(1, roundi(anchor.stats.hp * 0.35)); anchor.revived_round = int(state.round)
					actor.saga.repairs += 1
					events.append(_event("saga_anchor_repaired", anchor.actor_id, {"text": "旧锁片被接回，重新隔离这一侧；纸手余力%d次。" % (2 - actor.saga.repairs)}))
	return events
static func hint(state: Dictionary, actor_id: String) -> String:
	var actor: Dictionary = state.actors[actor_id]
	initialize(actor)
	if actor.saga.interrupted: return "号令已打断，本次行动失效；趁窗口处理目标。"
	match actor.saga.kind:
		"voice": return "回放上一轮最后行动；攻后转守，控制可打断。" if actor.hp * 5 > actor.stats.hp * 2 else "纸躯将扑灯；保护低血队员，守住撤人窗口。"
		"banner", "bearer": return "举旗／举灯后可盾击或眩晕打断补位；击败号令者即散纸兵。"
		"mirror", "master_mirror": return ["刀光面：物理反射。用术法，或防守等第三轮脱面。", "水纹面：术法反射。用物理，或防守等下一轮脱面。", "脱面：背扣暴露，所有伤害提高25%。"][actor.saga.phase - 1]
		"lamp": return ["灯印后将吸取；准备盾击／眩晕打断。", "吸取可打断，否则补血补罩；也可用护盾降低吸取。", "灯罩散开，伤害提高25%；抓住输出窗口。"][actor.saga.step % 3]
		"warden": return "左右锁片尚在，胸牌不受伤；先隔离两侧，留控制打断回补。" if blocked(state, actor) else "两侧已隔离，胸牌暴露；即将回补时可盾击打断。"
		"exit": return "先压住堵门反冲，稳住可退出的通道。"
		"relay": return "出口未稳，先处理堵门反冲。" if blocked(state, actor) else "外侧已能接应，现在压住中段反冲以完成分流。"
		"recoil": return "先稳出口，再分流中段；不能直接削空主镜跳过目标。" if blocked(state, actor) else "出口与中段均已稳住，可以卸去最后余压。"
	return ""
static func _event(type: String, actor_id: String, payload: Dictionary) -> Dictionary:
	return {"sequence": 0, "type": type, "actor_id": actor_id, "target_id": actor_id, "payload": payload}
