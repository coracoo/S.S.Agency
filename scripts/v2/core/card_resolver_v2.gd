class_name CardResolverV2
extends RefCounted
## 卡牌效果执行器 v2
##
## 由旧 card_resolver.gd 改造：删除 get_valid_targets 里的格子/方向/距离语义
## （adjacent_enemy/enemy_in_range/direction/area_3x3/tile_in_range 全删）。
## target 类型只剩：self / single_enemy / single_ally / all_enemies / all_allies。
##
## 删除 effects 里的 move_to/pull/retreat/push_unit/create_noise。
## 保留：deal_damage / heal / gain_shield / apply_status / apply_tag / draw_cards / gain_qi / lifesteal。
##
## 出牌后调用 combo_engine.try_trigger，由 combo 引擎决定是否触发连锁。

var combo_engine: ComboEngine


func _init(ce: ComboEngine = null) -> void:
	combo_engine = ce if ce != null else ComboEngine.new()


## 解析卡牌的 target_type，返回合法的目标单位列表
func get_valid_targets(card_def: Dictionary, state: GameStateV2) -> Array:
	var tt: String = card_def.get("target_type", "single_enemy")
	match tt:
		"self":
			# 返回玩家方主控（默认第一个存活玩家）
			var ps = state.get_alive_players()
			return ps.slice(0, 1)
		"single_enemy":
			return state.get_alive_enemies()
		"single_ally":
			return state.get_alive_players()
		"all_enemies":
			return state.get_alive_enemies()
		"all_allies":
			return state.get_alive_players()
		_:
			return []


## 打出一张牌
## [param card_def] 卡牌定义（来自 data/v2/cards.json）
## [param target] 目标单位（target_type=self/all_* 时可传 null 或忽略）
## [param state] 战斗状态
## [param player_entry] 玩家数据 { unit, deck, hand }
## 返回结算结果字典（供 UI 播放动画/飘字）
func play_card(card_def: Dictionary, target: UnitV2, state: GameStateV2, player_entry: Dictionary) -> Dictionary:
	var tt: String = card_def.get("target_type", "single_enemy")
	var targets: Array = _resolve_targets(tt, target, state)
	var card_tags: Array = card_def.get("tags", [])

	var result := {
		"card_id": card_def.get("id", ""),
		"targets": targets,
		"effects_applied": [],
		"combos_triggered": []
	}

	# 1. 应用卡牌自身的 effects
	for effect in card_def.get("effects", []):
		var applied = _apply_effect(effect, targets, state, player_entry)
		result.effects_applied.append_array(applied)

	# 2. 触发 combo 引擎（对每个主目标尝试）
	if combo_engine != null and not targets.is_empty():
		var context := {
			"players": state.get_alive_players(),
			"enemies": state.get_alive_enemies()
		}
		for primary in targets:
			if primary is UnitV2:
				var combo_results = combo_engine.try_trigger(card_tags, primary, context)
				result.combos_triggered.append_array(combo_results)

	# 3. 弃牌（从手牌移到弃牌堆）
	var card_id = card_def.get("id", "")
	if not card_id.is_empty() and player_entry.has("hand"):
		player_entry.hand.remove_card(card_id)
	if player_entry.has("deck"):
		player_entry.deck.discard_one(card_id)

	return result


func _resolve_targets(target_type: String, explicit_target: UnitV2, state: GameStateV2) -> Array:
	match target_type:
		"self":
			var ps = state.get_alive_players()
			return ps.slice(0, 1) if not ps.is_empty() else []
		"single_enemy", "single_ally":
			return [explicit_target] if explicit_target != null else []
		"all_enemies":
			return state.get_alive_enemies()
		"all_allies":
			return state.get_alive_players()
		_:
			return []


func _apply_effect(effect: Dictionary, targets: Array, state: GameStateV2, player_entry: Dictionary) -> Array:
	var applied: Array = []
	var type: String = effect.get("type", "")
	match type:
		"deal_damage":
			var amount = int(effect.get("amount", 0))
			var dmg_type = effect.get("damage_type", "physical")
			for t in targets:
				if t is UnitV2 and t.is_alive:
					var actual = t.take_damage(amount, dmg_type)
					applied.append({ "kind": "damage", "target": t, "amount": actual })
		"heal":
			var amount = int(effect.get("amount", 0))
			for t in targets:
				if t is UnitV2 and t.is_alive:
					var actual = t.heal(amount)
					applied.append({ "kind": "heal", "target": t, "amount": actual })
		"gain_shield":
			var amount = int(effect.get("amount", 0))
			for t in targets:
				if t is UnitV2 and t.is_alive:
					t.add_shield(amount)
					applied.append({ "kind": "shield", "target": t, "amount": amount })
		"apply_tag":
			var tag = effect.get("tag", "")
			var dur = int(effect.get("duration", 1))
			for t in targets:
				if t is UnitV2 and t.is_alive:
					t.apply_tag(tag, dur)
					applied.append({ "kind": "tag", "target": t, "tag": tag })
		"draw_cards":
			var n = int(effect.get("amount", 1))
			if player_entry.has("hand") and player_entry.has("deck"):
				var drawn = player_entry.deck.draw(n)
				for cid in drawn:
					player_entry.hand.add_card(cid)
				applied.append({ "kind": "draw", "amount": drawn.size() })
		"gain_qi":
			# qi 由 GameStateV2 管，这里只记录意图，实际加 qi 由调用方决定
			applied.append({ "kind": "gain_qi", "amount": int(effect.get("amount", 1)) })
		"lifesteal":
			var amount = int(effect.get("amount", 0))
			if player_entry.has("unit") and player_entry.unit is UnitV2:
				player_entry.unit.heal(amount)
				applied.append({ "kind": "heal", "target": player_entry.unit, "amount": amount })
	return applied
