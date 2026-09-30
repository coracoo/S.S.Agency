class_name GameStateV2
extends RefCounted
## 卡牌战中央数据模型 v2
##
## 由旧 game_state.gd 改造：删除 map/noise/spirit_density/player_spawn_defs/enemy_spawn_defs
## 等所有格子/噪音/灵气密度相关字段。保留 players(含 deck/hand)/enemies/qi(旧 AP)/turn 流程/胜负判定。
##
## 新增 combo_engine 实例，作为出牌结算后的连锁触发器。

signal turn_start(who: String)
signal turn_end(who: String)
signal unit_damaged(unit)
signal unit_healed(unit)
signal unit_died(unit)
signal qi_changed(current: int, max_val: int)
signal hand_changed()
signal battle_won()
signal battle_lost()

var balance: Dictionary
var players: Array = []  # Array of { unit, deck, hand, inventory }
var enemies: Array = []  # Array of UnitV2
var all_units: Array = []

var current_turn: String = "player"
var turn_count: int = 0
var qi: int = 0       # 灵气（出牌资源，旧版叫 AP）
var max_qi: int = 3

var combo_engine: ComboEngine
var intent_ai: EnemyIntentAI
var enemy_intents: Dictionary = {}  # enemy_id → intent dict（玩家回合显示给玩家看的"敌人意图"）


func _init() -> void:
	balance = JsonLoader.load_file("res://data/v2/balance.json")
	if balance.is_empty():
		balance = {}
	max_qi = int(balance.get("maxQi", 3))
	combo_engine = ComboEngine.new()
	intent_ai = EnemyIntentAI.new()


## 初始化一场战斗
## [param player_template_ids] 出战玩家模板 id（如 ["rinne", "mint"]）
## [param enemy_template_ids] 敌人模板 id
func init_battle(player_template_ids: Array, enemy_template_ids: Array) -> void:
	players.clear()
	enemies.clear()
	all_units.clear()
	enemy_intents.clear()

	var units_data = _load_units_data()
	var enemies_data = _load_enemies_data()

	for tid in player_template_ids:
		var tmpl = units_data.get(tid, {})
		if tmpl.is_empty():
			push_error("GameStateV2: missing player template " + tid)
			continue
		var unit = UnitV2.new(tmpl, tid)
		var deck = Deck.new(tmpl.get("starting_deck", []))
		# 地图拾取的卡牌（card_* 旗标）并入牌池（探索→战斗的资源投入闭环）
		for flag_name in NarrativeState.flags:
			var fname = str(flag_name)
			if fname.begins_with("card_") and bool(NarrativeState.flags[flag_name]):
				var card_id = fname.substr(5)
				if not CardV2.get_card(card_id).is_empty():
					deck.add_card_to_pool(card_id)
		var hand = HandV2.new(int(balance.get("maxHandSize", 5)))
		players.append({
			"unit": unit,
			"deck": deck,
			"hand": hand,
			"inventory": Inventory.new()
		})
		all_units.append(unit)

	for tid in enemy_template_ids:
		var tmpl = enemies_data.get(tid, {})
		if tmpl.is_empty():
			push_error("GameStateV2: missing enemy template " + tid)
			continue
		var unit = UnitV2.new(tmpl, tid)
		enemies.append(unit)
		all_units.append(unit)


func _load_units_data() -> Dictionary:
	var data = JsonLoader.load_file("res://data/v2/units.json")
	if not (data is Dictionary):
		return {}
	var result = {}
	for u in data.get("units", []):
		if u is Dictionary and u.has("id"):
			result[u.id] = u
	return result


func _load_enemies_data() -> Dictionary:
	var data = JsonLoader.load_file("res://data/v2/enemies.json")
	if not (data is Dictionary):
		return {}
	var result = {}
	for e in data.get("enemies", []):
		if e is Dictionary and e.has("id"):
			result[e.id] = e
	return result


# ===== 回合流程 =====

func start_player_turn() -> void:
	current_turn = "player"
	turn_count += 1
	qi = int(balance.get("qiPerTurn", 3))
	qi_changed.emit(qi, max_qi)
	# 抽牌
	var draw_n = int(balance.get("drawOnNewTurn", 2))
	if turn_count == 1:
		draw_n = int(balance.get("drawPerTurn", 5))
	for p in players:
		if not p.unit.is_alive:
			continue
		var drawn = p.deck.draw(draw_n)
		for cid in drawn:
			p.hand.add_card(cid)
	# 重置护盾（每回合开始护盾清零，StS 式）
	if bool(balance.get("shield_decay_at_turn_end", true)):
		for u in all_units:
			if u is UnitV2:
				u.shield = 0
	# 生成敌人意图（供玩家看到下回合威胁）
	_generate_enemy_intents()
	hand_changed.emit()
	turn_start.emit("player")


func end_player_turn() -> void:
	turn_end.emit("player")
	# 弃手牌
	for p in players:
		if not p.unit.is_alive:
			continue
		p.deck.discard_many(p.hand.cards)
		p.hand.clear()
	# 回合结束时单位 tag 计时
	for u in all_units:
		if u is UnitV2:
			u.tick_tags()
	current_turn = "enemy"
	turn_start.emit("enemy")


func start_enemy_turn() -> void:
	_execute_enemy_intents()
	end_enemy_turn()


func end_enemy_turn() -> void:
	turn_end.emit("enemy")
	current_turn = "player"
	start_player_turn()


# ===== 出牌 =====

## 轻量校验：回合与灵气是否够（不含目标校验——选牌阶段用）
func can_afford(card_def: Dictionary) -> bool:
	return current_turn == "player" and qi >= int(card_def.get("cost", 0))


func can_play_card(card_def: Dictionary, target: UnitV2 = null) -> bool:
	if current_turn != "player":
		return false
	if qi < int(card_def.get("cost", 0)):
		return false
	var tt: String = card_def.get("target_type", "single_enemy")
	if tt == "single_enemy" and (target == null or not target.is_alive or target.faction != "enemy"):
		return false
	if tt == "single_ally" and (target == null or not target.is_alive or target.faction != "player"):
		return false
	return true


func spend_qi(amount: int) -> void:
	qi = maxi(0, qi - amount)
	qi_changed.emit(qi, max_qi)


# ===== 敌人意图 =====

func _generate_enemy_intents() -> void:
	enemy_intents.clear()
	var player_units = []
	for p in players:
		player_units.append(p.unit)
	for e in enemies:
		if e is UnitV2 and e.is_alive:
			# 优先消耗蓄力
			if e.has_meta("stored_charge"):
				enemy_intents[e.id] = e.get_meta("stored_charge")
				e.remove_meta("stored_charge")
			else:
				enemy_intents[e.id] = intent_ai.generate_intent(e, player_units, turn_count)


func _execute_enemy_intents() -> void:
	for e in enemies:
		if not (e is UnitV2) or not e.is_alive:
			continue
		var intent = enemy_intents.get(e.id, {})
		if intent.is_empty():
			continue
		intent_ai.execute_intent(intent, e, self)


# ===== 查询 =====

func get_unit_by_id(uid: String) -> UnitV2:
	for u in all_units:
		if u.id == uid:
			return u
	return null


func get_player_for_unit(uid: String) -> Dictionary:
	for p in players:
		if p.unit.id == uid:
			return p
	return {}


func get_alive_enemies() -> Array:
	var r = []
	for e in enemies:
		if e is UnitV2 and e.is_alive:
			r.append(e)
	return r


func get_alive_players() -> Array:
	var r = []
	for p in players:
		if p.unit.is_alive:
			r.append(p.unit)
	return r


func is_battle_over() -> String:
	if get_alive_enemies().is_empty():
		return "won"
	if get_alive_players().is_empty():
		return "lost"
	return ""
