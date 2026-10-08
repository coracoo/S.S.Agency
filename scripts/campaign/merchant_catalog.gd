# 神秘商人纯目录与账本重放；不持有会话、不写盘、不修改输入快照。
class_name CampaignMerchantCatalog
extends RefCounted
const Saga = preload("res://scripts/campaign/saga_catalog.gd")
const Routes = preload("res://scripts/campaign/saga_route_rules.gd")
const Threats = preload("res://scripts/rpg/strategy_encounters.gd")
const Loadouts = preload("res://scripts/rpg/loadout_rules.gd")
const DATA_PATH := "res://data/campaign/mysterious_merchant.json"
const RECEIPT_INTS := ["id", "price_version", "quantity", "unit_price", "cost", "stock_before", "stock_after", "chapter", "event_count", "battle_count", "supply_transaction_count", "navigation_count"]
const STORY_FIELDS := ["world_version", "map_layout", "space", "night", "scene_id", "scene_path", "event_flags", "resolved", "dlg_fired", "story_scene", "story_choice", "story_encounter"]
static var _document: Dictionary = {}

static func initial() -> Dictionary:
	return {"version": 1, "purchases": []}

static func _data() -> Dictionary:
	if _document.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if not parsed is Dictionary or parsed.get("version") != 1 or not parsed.get("products") is Array or not parsed.get("chapters") is Dictionary: return {}
		for row in parsed.products:
			if not row is Dictionary: return {}
			for field in ["price_version", "price", "stock", "unlock_chapter"]:
				var value: Variant = row.get(field)
				if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floor(float(value)): return {}
				row[field] = int(value)
		_document = parsed
	return _document

static func _products(catalog: RefCounted) -> Dictionary:
	var result: Dictionary = {}
	if catalog == null or not catalog.has_method("get_definition"): return result
	for row in _data().get("products", []):
		if not row.get("id") is String or not row.get("item_id") is String or not row.get("kind") in ["gear", "card"] or not row.get("unlock_event") is String: return {}
		if row.id != "%s_%s_v1" % [row.kind, row.item_id] or result.has(row.id) or row.price_version != 1 or row.price <= 0 or row.stock != 1 or row.unlock_chapter < 2 or row.unlock_chapter > 7: return {}
		var item: Dictionary = catalog.get_definition("equipment", row.item_id) if row.kind == "gear" else Loadouts.card(row.item_id)
		if item.is_empty() or not item.get("name") is String or (row.kind == "card" and item.get("type") != "passive"): return {}
		if not row.unlock_event.is_empty() and Saga.chapter_for(row.unlock_event) != row.unlock_chapter: return {}
		result[row.id] = row
	return result

static func _ledger_errors(saved: Dictionary) -> Array[String]:
	var value: Variant = saved.get("merchant")
	if not value is Dictionary or value.size() != 2 or not value.has_all(["version", "purchases"]): return ["商人账本字段缺失或含未知字段"]
	if not value.version is int or value.version != 1: return ["未知或非法商人版本，保留原档"]
	if not value.purchases is Array or value.purchases.size() > _data().get("products", []).size(): return ["商人购买记录类型或数量非法"]
	for row in value.purchases:
		if not row is Dictionary or row.size() != RECEIPT_INTS.size() + 1 or not row.has_all(RECEIPT_INTS) or not row.get("product") is String: return ["商人流水字段缺失或含未知字段"]
		for field in RECEIPT_INTS:
			if not row[field] is int or row[field] < 0: return ["商人流水须为非负整数：" + field]
	return []

# -1显式表示坏账本，不能把未知/缺失数据当成零消费后继续保存。
static func spent(saved: Dictionary) -> int:
	if not _ledger_errors(saved).is_empty(): return -1
	var total := 0
	for row in saved.merchant.purchases:
		if row.cost > 100000: return -1
		total += row.cost
	return total

static func _safe(saved: Dictionary) -> bool:
	if saved.get("schema_version") != 3 or not saved.get("schema_version") is int or not saved.get("saga") is Dictionary: return false
	var saga: Dictionary = saved.saga
	return saved.get("phase") == "exploration" and saved.get("story_phase") == "exploration" and saved.get("pending_battle") is Dictionary and saved.pending_battle.is_empty() and saga.get("active_scene") == "" and saga.get("retry") is Dictionary and saga.retry.is_empty() and saga.get("ending") == ""

static func _appears(saga: Dictionary) -> bool:
	if not saga.get("chapter") is int or not saga.get("completed") is Array or not saga.get("battles") is Array: return false
	if saga.battles.has("C7-05"): return false
	var location: Dictionary = _data().get("chapters", {}).get(str(saga.chapter), {})
	return not location.is_empty() and (str(location.event).is_empty() or saga.completed.has(location.event))

static func presence(saved: Dictionary) -> bool:
	return _ledger_errors(saved).is_empty() and _safe(saved) and _appears(saved.saga)

static func anchor(saved: Dictionary) -> Vector3:
	if not saved.get("saga") is Dictionary or not saved.saga.get("chapter") is int: return Vector3.ZERO
	var location: Dictionary = _data().get("chapters", {}).get(str(saved.saga.chapter), {})
	if location.is_empty(): return Vector3.ZERO
	var anchors: Dictionary = Saga.definition(saved.saga.chapter + 4).get("anchors", {})
	var point: Array = anchors.get(location.anchor, [])
	if point.size() != 3: return Vector3.ZERO
	return Vector3(point[0], point[1], point[2]) + Vector3(location.offset[0], location.offset[1], location.offset[2])

static func _unlocked(product: Dictionary, saga: Dictionary) -> bool:
	return int(saga.get("max_chapter", 0)) >= product.unlock_chapter if product.unlock_event.is_empty() else saga.get("completed", []).has(product.unlock_event)

static func offers(saved: Dictionary, catalog: RefCounted) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not saved.get("saga") is Dictionary or not validate(saved, catalog).is_empty(): return result
	var sold: Dictionary = {}
	for purchase in saved.merchant.purchases: sold[purchase.product] = int(sold.get(purchase.product, 0)) + purchase.quantity
	for product in _products(catalog).values():
		var item: Dictionary = catalog.get_definition("equipment", product.item_id) if product.kind == "gear" else Loadouts.card(product.item_id)
		var description := str(item.get("summary", ""))
		if product.kind == "gear":
			var details: Array[String] = []
			var names := {"hp": "生命", "mp": "灵力", "atk": "攻击", "matk": "术攻", "def": "防御", "mdef": "术防", "spd": "速度"}
			for stat in item.get("stats", {}): details.append("%s%+d" % [names.get(stat, stat), int(item.stats[stat])])
			description = "、".join(details) + "。" + str(item.get("summary", "装备后按武器与容量规则装配技能。"))
		else: description += " 被动容量 %d。" % int(item.capacity_cost)
		result.append({"id": product.id, "kind": product.kind, "item_id": product.item_id, "name": item.name, "price": product.price, "stock": product.stock - int(sold.get(product.id, 0)), "unlocked": _unlocked(product, saved.saga), "owned":product.kind=="card" and int(saved.get("cards",{}).get(product.item_id,0))>0,"description": description})
	return result

static func preview(saved: Dictionary, world: Dictionary, offer_id: String, count: Variant, catalog: RefCounted) -> Dictionary:
	var errors := validate(saved, catalog)
	if not errors.is_empty(): return _failure("；".join(errors))
	if not presence(saved): return _failure("商人当前不在安全探索区域")
	if not count is int or count < 1: return _failure("购买数量须为正整数")
	if not saved.get("world") is Dictionary or not Saga.validate_world(world).is_empty(): return _failure("商人交易世界检查点非法")
	for field in STORY_FIELDS:
		if saved.world.get(field) != world.get(field): return _failure("商人交易与安全故事检查点不符")
	var point := Vector3(world.position[0], world.position[1], world.position[2])
	if point.distance_to(anchor(saved)) > float(_data().get("interaction_distance", 2.6)): return _failure("请走到神秘商人摊点附近")
	var selected: Dictionary = {}
	for offer in offers(saved, catalog):
		if offer.id == offer_id: selected = offer
	if selected.is_empty(): return _failure("商人没有这件商品")
	if not selected.unlocked: return _failure("这批商品尚未开放")
	if selected.get("owned",false):return _failure("这张卡已收录，可供多名队员准备，无需重复购买")
	if count > selected.stock: return _failure("本周目这件商品已经售罄或数量不足")
	var cost: int = selected.price * count
	if saved.saga.coins < cost: return _failure("银钱不足")
	var candidate := saved.duplicate(true)
	var receipt := {"id": candidate.merchant.purchases.size() + 1, "product": offer_id, "price_version": 1, "quantity": count, "unit_price": selected.price, "cost": cost, "stock_before": selected.stock, "stock_after": selected.stock - count, "chapter": saved.saga.chapter, "event_count": saved.saga.events.size(), "battle_count": saved.saga.battles.size(), "supply_transaction_count": saved.saga.transactions.size(), "navigation_count": saved.saga.navigation.size()}
	candidate.merchant.purchases.append(receipt)
	candidate.saga.coins -= cost
	var inventory: Dictionary = candidate.gear if selected.kind == "gear" else candidate.cards
	inventory[selected.item_id] = int(inventory.get(selected.item_id, 0)) + count
	candidate.world = world.duplicate(true)
	if candidate.get("world_history") is Dictionary: candidate.world_history[world.scene_id] = world.duplicate(true)
	errors = validate(candidate, catalog)
	if not errors.is_empty(): return _failure("候选交易校验失败：" + "；".join(errors))
	return {"ok": true, "error": "", "candidate": candidate, "receipt": receipt.duplicate(true)}

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "candidate": {}, "receipt": {}}

static func validate(saved: Dictionary, catalog: RefCounted) -> Array[String]:
	var errors := _ledger_errors(saved)
	if not errors.is_empty(): return errors
	if not saved.get("schema_version") is int or saved.schema_version != 3: return ["商人扩展只属于正式schema3"]
	var products := _products(catalog)
	if products.is_empty() or products.size() != _data().get("products", []).size(): return ["商人目录缺失、商品未知或配置非法"]
	if not saved.has("saga"): return [] if saved.merchant.purchases.is_empty() else ["首章不能有后续商人购买"]
	var history := _history(saved, catalog)
	if not history.ok: return [history.error]
	for field in ["gear", "cards"]:
		if not saved.get(field) is Dictionary: return ["购买缺少真实装备/卡片库存"]
	var spent_total := 0
	var stocks: Dictionary = {}
	var acquired := {"gear": {}, "cards": {}}
	var previous := {"event_count": 0, "battle_count": 0, "supply_transaction_count": 0, "navigation_count": 0}
	for index in saved.merchant.purchases.size():
		var row: Dictionary = saved.merchant.purchases[index]
		var product: Dictionary = products.get(row.product, {})
		if product.is_empty() or row.id != index + 1 or row.quantity != 1 or row.price_version != product.price_version or row.unit_price != product.price or row.cost != row.quantity * product.price: return ["商人流水顺序、商品、数量或价格版本不符"]
		for field in previous:
			if row[field] < previous[field]: return ["商人流水历史前缀不能倒退：" + field]
		if row.event_count >= history.prefixes.size() or row.battle_count > saved.saga.battles.size() or row.supply_transaction_count >= history.supply_costs.size() or row.navigation_count >= history.navigation.size(): return ["商人流水引用了未来或不存在的历史"]
		var prefix: Dictionary = history.prefixes[row.event_count].duplicate(true)
		var navigation: Dictionary = history.navigation[row.navigation_count]
		if navigation.events != row.event_count or navigation.chapter != row.chapter or row.battle_count != prefix.battles.size(): return ["商人购买时机与真实事件/战斗/地区前缀不符"]
		if not navigation.active_scene.is_empty(): return ["商人购买发生在绕路自动进入的互动期间"]
		prefix.chapter = row.chapter; prefix.max_chapter = navigation.maximum
		if not _appears(prefix) or not _unlocked(product, prefix): return ["购买发生在商人离场或商品尚未解锁时"]
		var stock_before: int = int(stocks.get(row.product, product.stock))
		if row.stock_before != stock_before or row.stock_after != stock_before - row.quantity or row.stock_after < 0: return ["商人全局库存记录不符或重复购买"]
		stocks[row.product] = row.stock_after
		var money: int = 120 + int(history.income[row.battle_count]) - int(history.supply_costs[row.supply_transaction_count]) - spent_total
		if row.cost > money: return ["购买当时银钱不足，不能使用未来胜利收益"]
		spent_total += row.cost
		var kind := "gear" if product.kind == "gear" else "cards"
		acquired[kind][product.item_id] = int(acquired[kind].get(product.item_id, 0)) + row.quantity
		for field in previous: previous[field] = row[field]
	for field in acquired:
		for item_id in acquired[field]:
			if not saved[field].get(item_id) is int or saved[field][item_id] < acquired[field][item_id]: return ["商人取得的物品在库存中缺失：" + item_id]
	var expected_money: int = 120 + int(history.income[-1]) - int(history.supply_costs[-1]) - spent_total
	if saved.saga.coins != expected_money or expected_money < 0: return ["银钱与胜利、普通补给和商人流水不符"]
	return []

# 只重放目录与不可变历史，不调用SaveStore/SagaSaveRules，避免主校验接入后形成依赖环。
static func _history(saved: Dictionary, catalog: RefCounted) -> Dictionary:
	var saga: Variant = saved.get("saga")
	if not saga is Dictionary: return _failure("后续进度格式非法")
	for field in ["version", "chapter", "max_chapter", "coins"]:
		if not saga.get(field) is int: return _failure("后续历史整数格式非法：" + field)
	if saga.version != 1 or saga.chapter < 2 or saga.chapter > saga.max_chapter or saga.max_chapter > 7 or saga.coins < 0: return _failure("后续历史版本/章节/银钱非法")
	for field in ["events", "battles", "transactions", "navigation", "completed"]:
		if not saga.get(field) is Array: return _failure("后续历史列表非法：" + field)
	for field in ["battle_encounters", "flags", "cursors", "choices"]:
		if not saga.get(field) is Dictionary: return _failure("后续历史字典非法：" + field)
	if not saved.get("resolution") in ["sendoff", "seal_monitoring"]: return _failure("商人历史缺少首章结案来源")
	var replay := Saga.initial(saved.resolution)
	var prefixes: Array = [replay.duplicate(true)]
	for event in saga.events:
		if not event is Dictionary or not event.get("id") is String or not event.get("choice") is String: return _failure("商人历史事件格式非法")
		var entry := Saga.scene(event.id)
		if entry.is_empty(): return _failure("商人历史事件未登记")
		for chapter in range(2, Saga.chapter_for(event.id)):
			if not Saga.chapter_complete(replay, chapter): return _failure("商人历史跳过前章完成条件")
		if event.id == "C7-R04": replay.retry = {"stage": int(event.get("retry_stage", 0))}
		if not Saga.matches(entry.get("requires", {}), Saga.context(replay)): return _failure("商人历史事件缺少当时前置：" + event.id)
		var option := Saga.choice(event.id, event.choice)
		if (not event.choice.is_empty() and option.is_empty()) or (not Saga.eligible_choices(entry, replay).is_empty() and option.is_empty()) or (not option.is_empty() and not Saga.matches(option.get("requires", {}), Saga.context(replay))): return _failure("商人历史选择未在当时开放")
		if replay.completed.has(event.id) and not str(entry.get("encounter_id", "")).is_empty(): return _failure("商人历史战斗场次重复提交")
		if not event.choice.is_empty(): replay.choices[event.id] = event.choice
		var encounter := Saga.encounter_for_saga(replay, event.id)
		if not encounter.is_empty():
			if saga.battle_encounters.get(event.id) != encounter: return _failure("商人历史事件缺少当时真实战斗")
			if not replay.battles.has(event.id): replay.battles.append(event.id)
			if saga.battles.slice(0, replay.battles.size()) != replay.battles: return _failure("商人历史胜利顺序与事件来源不符")
		Saga.apply_effects(replay, entry, option)
		if not replay.completed.has(event.id): replay.completed.append(event.id)
		replay.retry = {}
		prefixes.append(replay.duplicate(true))
	if replay.completed != saga.completed or replay.flags != saga.flags: return _failure("商人解锁事实与事件重放不符")
	var route_errors := Routes.validate(saga, prefixes)
	if not route_errors.is_empty(): return _failure("；".join(route_errors))
	var income: Array[int] = [0]
	var seen: Array[String] = []
	for battle in saga.battles:
		if not battle is String or seen.has(battle): return _failure("商人收益来源重复或非法")
		seen.append(battle)
		var encounter: Variant = saga.battle_encounters.get(battle)
		if not encounter is String or catalog.get_definition("encounters", encounter).is_empty(): return _failure("商人收益没有真实遭遇来源")
		if not replay.battles.has(battle):
			if battle != saga.get("active_scene") or Saga.encounter_for_saga(saga, battle) != encounter: return _failure("商人收益不能来自未来或未经完成的场次")
		var rewards := Threats.rewards(encounter)
		if not rewards.get("coins") is int or rewards.coins < 0: return _failure("商人收益缺少明确银钱奖励")
		income.append(income[-1] + rewards.coins)
	if saga.battle_encounters.size() != seen.size(): return _failure("商人收益遭遇映射数量不符")
	var supply_costs: Array[int] = [0]
	for transaction in saga.transactions:
		if not transaction is Dictionary or not transaction.get("item") is String or not transaction.get("count") is int or not transaction.get("cost") is int: return _failure("普通补给流水格式非法")
		if not Saga.SHOP.has(transaction.item) or transaction.count < 1 or transaction.count > 9 or transaction.cost != Saga.SHOP[transaction.item] * transaction.count: return _failure("普通补给价格/数量非法")
		supply_costs.append(supply_costs[-1] + transaction.cost)
	return {"ok": true, "error": "", "prefixes": prefixes, "income": income, "supply_costs": supply_costs, "navigation": _navigation_states(saga, prefixes)}

# Routes.validate已检验原始导航合法性；这里仅投影各个购买切点的实际章和事件数。
static func _navigation_states(saga: Dictionary, prefixes: Array) -> Array:
	var result: Array = [{"chapter": 2, "maximum": 2, "events": 0, "active_scene": ""}]
	var chapter := 2; var maximum := 2
	for step in saga.navigation:
		var active_scene := ""
		if step.kind == "travel": chapter = step.destination
		else:
			var after: Dictionary = prefixes[step.events]
			var next := Saga.next_scene(Saga.scene(step.id), after, Saga.choice(step.id, step.choice))
			var skipped := 0
			while not next.is_empty() and after.completed.has(next) and after.battles.has(next) and skipped < 10:
				next = Saga.next_scene(Saga.scene(next), after, Saga.choice(next, str(after.choices.get(next, "")))); skipped += 1
			if not next.is_empty() and Saga.chapter_for(next) != chapter: chapter = Saga.chapter_for(next)
			elif not next.is_empty() and not str(Saga.scene(next).get("kind", "main")) in ["main", "ending"]: active_scene = next
		maximum = maxi(maximum, chapter)
		result.append({"chapter": chapter, "maximum": maximum, "events": step.events, "active_scene": active_scene})
	return result
