# 测试专用连续阶段策略。只读公开属性、意图和合法预览；不读取未来RNG或修改模型。
extends RefCounted
const Base = preload("res://tools/campaign/loadout_battle_strategy.gd")
const Boss = preload("res://scripts/rpg/saga_boss_rules.gd")

static func ranked(state: Dictionary, engine: RefCounted, catalog: RefCounted, scene_id: String) -> Array:
	var candidates: Array = Base.ranked(state,engine,catalog)
	var source: Dictionary = state.actors[state.active_actor_id]
	var interrupt_needed:bool=state.actors.values().any(func(actor):return actor.side=="enemy" and actor.hp>0 and actor.get("saga",{}).get("kind","") in ["voice","banner","lamp","warden","bearer"])
	var recovery_possible:bool=int(state.inventory.get("healing_potion",0))+int(state.inventory.get("moxa_roll",0))>0
	for ally in state.actors.values():
		if ally.side!="player" or ally.hp<=0:continue
		for skill_id in ["heal","group_heal"]:
			if ally.skill_ids.has(skill_id) and ally.mp>=int(catalog.skill_for(ally,skill_id).mp_cost):recovery_possible=true
	var result: Array = []
	for entry in candidates:
		var command: Dictionary = entry.command
		var preview: Dictionary = engine.preview(command)
		var rejected := false
		for id in command.target_ids:
			if state.actors[id].side=="enemy" and Boss.blocked(state,state.actors[id]): rejected=true
		if rejected: continue
		# 连战前已知要面对三阶段：首阶段不用魔力药，后段根据实际核心技能需求消耗。
		if command.kind=="item" and command.ability_id=="mana_potion":
			if scene_id=="C7-05": continue
		var reasons: Array[String] = []
		# 用公开伤害量校准机会成本；过度节灵会让法师满MP只普攻，反而拉长消耗战。
		var score := -float(preview.mp_cost)*4.2-float(preview.item_cost)*16.0
		var interrupted := false
		for event in preview.effects:
			var target: Dictionary = state.actors.get(event.target_id,{})
			if target.is_empty(): continue
			var weight := 1.35 if Base._commander(target) else 1.0
			# 三阶段低资源时先消掉一份持续攻击，不能只因击倒首领会散兵就忽略纸兵成本。
			if target.class_id=="saga_paper_soldier":
				var papers: Array = state.actors.values().filter(func(a):return a.class_id=="saga_paper_soldier" and a.hp>0)
				weight=2.1 if papers.size()>=2 and target.actor_id==papers[0].actor_id else .65
			match event.type:
				"damage":
					var damage := mini(int(event.payload.normal),int(target.hp)+int(target.shield.get("amount",0)))
					score+=float(damage)*weight
					if int(event.payload.normal)>=int(target.hp)+int(target.shield.get("amount",0)): score+=300.0 if Base._commander(target) else 35.0
				"saga_reflected": score-=float(event.payload.damage)*5.0
				"charge_interrupted":
					interrupted=true; score+=185.0; reasons.append("打断公开号令窗口")
				"healed":
					if target.side=="player":
						var incoming := Base._incoming(state,target.actor_id)
						var urgency := 5.0 if target.hp<=incoming+15 else (2.4 if float(target.hp)/float(target.stats.hp)<.55 else .35)
						score+=float(event.payload.actual)*urgency
				"shield_applied":
					if target.side=="player":
						var increase := maxi(0,int(event.payload.shield.amount)-int(event.payload.get("previous",{}).get("amount",0)))
						score+=minf(float(increase),Base._incoming(state,target.actor_id))*(3.0 if target.hp<=Base._incoming(state,target.actor_id)+25 else .45)
				"revived": score+=430.0
				"mp_restored":
					var threshold := 22 if target.skill_ids.has("group_heal") else (15 if target.skill_ids.has("heal") else (18 if target.skill_ids.has("firebolt") else 8))
					if target.mp<threshold:
						score+=float(event.payload.actual)*4.0+80.0
						reasons.append("连续阶段保留核心回复或打断")
				"status_applied":
					var status: Dictionary = event.payload.status
					var previous: Dictionary = event.payload.get("previous",{})
					if target.side=="enemy":
						match status.id:
							"burn":
								var extra := maxf(0,float(status.magnitude)*int(status.remaining)-float(previous.get("magnitude",0))*int(previous.get("remaining",0)))
								score+=minf(extra,float(target.hp))*1.15*weight
							"stun":
								if previous.is_empty():
									var danger := 0.0
									for range_row in target.get("intent",{}).get("preview",{}).get("damage_ranges",[]):
										if state.actors[range_row.target_id].hp<=float(range_row.normal)+10: danger+=float(range_row.normal)
									score+=danger*1.4
							"weaken":
								if previous.is_empty(): score+=float(status.magnitude)*mini(2,int(status.remaining))*float(target.stats.matk+target.stats.atk)*(1.5 if Base._commander(target) else .5)
							"magic_break", "armor_break":
								if previous.is_empty(): score+=12.0*weight
							"slow":
								if previous.is_empty(): score+=12.0*weight
					else:
						if status.id=="defend": score+=Base._incoming(state,target.actor_id)*float(status.magnitude)*(1.1 if recovery_possible and target.hp<Base._incoming(state,target.actor_id)+30 else .12)
						if status.id=="battle_spirit" and previous.is_empty(): score+=float(target.stats.atk)*float(status.magnitude)*2.0
		if command.kind=="skill" and command.ability_id=="shield_bash" and not interrupted: score-=80.0
		if command.kind=="skill" and command.ability_id=="seal" and interrupted and not command.target_ids.is_empty() and Base._cheaper_interrupt_available(state,source,state.actors[command.target_ids[0]],catalog): score-=140.0
		if interrupt_needed and command.kind=="skill" and command.ability_id!="shield_bash" and source.skill_ids.has("shield_bash") and source.mp-int(preview.mp_cost)<int(catalog.skill_for(source,"shield_bash").mp_cost)*2: score-=70.0
		result.append({"command":command,"score":score,"reasons":reasons,"mp_cost":preview.mp_cost,"item_cost":preview.item_cost})
	result.sort_custom(func(a,b):return a.score>b.score)
	return result
