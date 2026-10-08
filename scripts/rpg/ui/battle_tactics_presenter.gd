# 只读战术简报：意图、反射与目标门禁直接来自权威规则，不猜伤害或隐藏随机数。
class_name RpgBattleTacticsPresenter
extends RefCounted
const Presenter = preload("res://scripts/rpg/ui/battle_presenter.gd")
const TurnOrder = preload("res://scripts/rpg/turn_order.gd")
const SagaBoss = preload("res://scripts/rpg/saga_boss_rules.gd")
const ELEMENT_NAMES := {"neutral":"中性","fire":"火","ice":"冰","lightning":"雷","spirit":"灵"}

static func describe(snapshot: Dictionary, catalog: RefCounted, encounter: Dictionary = {}) -> String:
	# SagaBoss.hint会为缺少运行态的旧敌初始化默认值，因此所有读取限于此深副本。
	var state := snapshot.duplicate(true)
	if state.get("actors",{}).is_empty(): return "当前没有可查看的战场。"
	var lines: Array[String] = []
	var objective: String = str(encounter.get("objective",""))
	if not objective.is_empty(): lines.append("本场目标\n" + objective + "\n")
	lines.append("本轮行动顺序")
	var committed := TurnOrder.committed_speeds(state)
	for index in state.get("queue",[]).size():
		var id: String = state.queue[index]
		var actor: Dictionary = state.actors[id]
		var marker := "当前" if index == int(state.get("queue_index",0)) else ("已过" if index < int(state.get("queue_index",0)) else "待行动")
		if actor.hp <= 0: marker="已倒地 · 跳过"
		elif int(actor.get("revived_round",-1)) == int(state.get("round",0)) and index >= int(state.get("queue_index",0)): marker="本轮复起 · 跳过"
		var speed := " · 本轮速度 " + _speed(float(committed[id])) if committed.has(id) else ""
		lines.append("%d. %s · %s%s" % [index+1,Presenter.actor_name(actor,catalog),marker,speed])
	lines.append("\n下轮速度推演")
	var next := TurnOrder.forecast(state)
	var entries: Array[String] = []
	for id in next.queue:
		entries.append("%s %s" % [Presenter.actor_name(state.actors[id],catalog),_speed(float(next.effective_speeds[id]))])
	lines.append(" → ".join(entries))
	lines.append("按当前存活与状态推算；不预判后续伤亡、召回、净化或阶段变化。迟滞不插改本轮已排好的顺序；同速我方先行，同阵营沿固定顺序，每轮每人一次基础行动。")
	lines.append("\n敌方意图与窗口")
	var ids: Array = state.actors.keys()
	ids.sort()
	for id in ids:
		var actor: Dictionary = state.actors[id]
		if actor.side != "enemy" or actor.hp <= 0: continue
		lines.append("\n【%s】HP %d/%d · 基础速度 %s" % [Presenter.actor_name(actor,catalog),actor.hp,actor.stats.hp,_speed(float(actor.stats.spd))])
		lines.append("基础物防 %d · 基础术防 %d；状态修正后的收益见行动预览。" % [actor.stats.def,actor.stats.mdef])
		if SagaBoss.blocked(state,actor): lines.append("当前受联动保护：伤害无效，先处理前置目标。")
		if SagaBoss.reflecting(actor,{"damage_type":"physical"}): lines.append("当前反射物理伤害；确认前留意反伤与倒地风险。")
		if SagaBoss.reflecting(actor,{"damage_type":"magic"}): lines.append("当前反射术法伤害；确认前留意反伤与倒地风险。")
		var can_interrupt: bool = SagaBoss.can_interrupt(actor) if SagaBoss.is_actor(actor) else bool(actor.get("boss",{}).get("charge_valid",false)) and bool(actor.get("boss",{}).get("charge_interruptible",false))
		if can_interrupt: lines.append("当前打断窗口已开；选择具备打断效果的技能。眩晕免疫不等于打断免疫。")
		var intent: Dictionary = actor.get("intent",{})
		if not intent.is_empty(): lines.append(Presenter.intent_text(intent,actor,state,catalog))
		elif SagaBoss.is_actor(actor): lines.append(SagaBoss.hint(state,id))
		else: lines.append("下一次意图尚未公开。")
		for property in ["weaknesses","resistances"]:
			var names: Array[String] = []
			for element in actor.get(property,[]): names.append(str(ELEMENT_NAMES.get(element,element)))
			if not names.is_empty(): lines.append(("弱点：" if property=="weaknesses" else "抗性：")+"、".join(names))
	lines.append("\n队伍资源与装配")
	for id in ids:
		var actor: Dictionary = state.actors[id]
		if actor.side != "player": continue
		lines.append("%s · HP %d/%d · MP %d/%d · 装配速度 %s" % [Presenter.actor_name(actor,catalog),actor.hp,actor.stats.hp,actor.mp,actor.stats.mp,_speed(float(actor.stats.spd))])
		if actor.get("build") is Dictionary: lines.append(Presenter.loadout_summary(actor,catalog))
	var items: Array[String] = []
	for id in catalog.get_ids("items"):
		var count: int = int(state.get("inventory",{}).get(id,0))
		if count>0: items.append("%s×%d" % [str(catalog.get_definition("items",id).get("name",id)),count])
	lines.append("\n携带道具：" + ("、".join(items) if not items.is_empty() else "已用尽"))
	lines.append("\n查看不消耗行动，也不会清除已选技能或目标。技能是否有效、伤害与反伤，以确认前的实时预览为准。")
	return "\n".join(lines)

static func _speed(value: float) -> String:
	return str(int(value)) if value == floor(value) else "%.1f" % value
