class_name EnemyIntentAI
extends RefCounted
## 敌人意图 AI v2
##
## 取代旧 ai_controller.gd（fear/search/chase 状态机+寻路）。
## 新形态：每回合为每个敌人选一个【意图】，意图决定本回合行为（攻击/防御/蓄力/召唤）。
## 敌人不移动，意图靠 intent_profile 配置驱动（见 enemies.json 的 intent_profile 字段）。
##
## 意图类型：
##   attack   - 下回合对某玩家造成 X 点伤害
##   defend   - 本回合获得护盾
##   charge   - 本回合蓄力（不攻击），下回合造成大伤害
##   buff     - 给自己/友军加增益
##   summon   - 召唤援军


## 为一个敌人生成下一回合意图
## [param enemy] 敌人单位（必须带 intent_profile）
## [param players] 玩家单位列表（用于选目标）
## [param turn_count] 当前回合数（影响行为权重，如低血量触发大招）
func generate_intent(enemy: UnitV2, players: Array, turn_count: int) -> Dictionary:
	var profile: Dictionary = enemy.intent_profile
	if profile.is_empty():
		# 无配置：默认攻击
		return _intent_attack(profile.get("attack_damage", 4), _pick_target(players, profile))

	var behaviors: Array = profile.get("behaviors", ["attack"])
	var behavior: String = behaviors.pick_random() if not behaviors.is_empty() else "attack"
	var target: UnitV2 = _pick_target(players, profile)

	match behavior:
		"attack":
			return _intent_attack(profile.get("attack_damage", 4), target)
		"defend":
			return _intent_defend(profile.get("defend_amount", 5))
		"charge":
			return _intent_charge(profile.get("charge_damage", 10), target)
		"buff":
			return _intent_buff(profile.get("buff_tag", "strengthened"), profile.get("buff_duration", 2))
		"summon":
			return _intent_summon(profile.get("summon_id", "paper_effigy"))
		_:
			return _intent_attack(profile.get("attack_damage", 4), target)


## 按优先级选目标。优先级：lowest_hp_player（打最脆的）/ random / highest_threat
func _pick_target(players: Array, profile: Dictionary) -> UnitV2:
	var priority: String = profile.get("target_priority", "lowest_hp_player")
	var alive := []
	for p in players:
		if p is UnitV2 and p.is_alive:
			alive.append(p)
	if alive.is_empty():
		return null
	match priority:
		"lowest_hp_player":
			alive.sort_custom(func(a, b): return a.current_hp < b.current_hp)
			return alive[0]
		"random":
			return alive.pick_random()
		"highest_threat":
			# 简化：threat = 当前 HP（HP 越高越具威胁）
			alive.sort_custom(func(a, b): return a.current_hp > b.current_hp)
			return alive[0]
		_:
			return alive[0]


func _intent_attack(damage: int, target: UnitV2) -> Dictionary:
	return {
		"type": "attack",
		"icon": "sword",
		"amount": damage,
		"target": target,
		"description": "攻击 %d" % damage
	}


func _intent_defend(amount: int) -> Dictionary:
	return {
		"type": "defend",
		"icon": "shield",
		"amount": amount,
		"description": "防御 +%d" % amount
	}


func _intent_charge(damage: int, target: UnitV2) -> Dictionary:
	return {
		"type": "charge",
		"icon": "eye",
		"amount": damage,
		"target": target,
		"description": "蓄力（下回合攻击 %d）" % damage
	}


func _intent_buff(tag: String, duration: int) -> Dictionary:
	return {
		"type": "buff",
		"icon": "buff",
		"tag": tag,
		"duration": duration,
		"description": "强化自身"
	}


func _intent_summon(summon_id: String) -> Dictionary:
	return {
		"type": "summon",
		"icon": "summon",
		"summon_id": summon_id,
		"description": "召唤援军"
	}


## 执行一个意图，返回执行结果字典（供 battle_scene 触发动画与飘字）
## 注意：实际伤害结算走 Unit.take_damage，这里只做调度
func execute_intent(intent: Dictionary, enemy: UnitV2, state: Variant) -> Dictionary:
	match intent.get("type"):
		"attack":
			var target: UnitV2 = intent.get("target", null)
			if target and target.is_alive:
				var dmg = target.take_damage(int(intent.get("amount", 0)))
				return {"kind": "attacked", "target": target, "damage": dmg}
		"defend":
			enemy.add_shield(int(intent.get("amount", 0)))
			return {"kind": "defended", "amount": int(intent.get("amount", 0))}
		"charge":
			# 蓄力：本回合不做伤害，下回合通过 generate_intent 读取 stored_charge
			enemy.set_meta("stored_charge", intent)
			return {"kind": "charged", "amount": int(intent.get("amount", 0))}
		"buff":
			enemy.apply_tag(intent.get("tag", ""), int(intent.get("duration", 1)))
			return {"kind": "buffed", "tag": intent.get("tag", "")}
	return {"kind": "noop"}
