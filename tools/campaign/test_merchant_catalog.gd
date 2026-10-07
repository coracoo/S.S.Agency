# 纯目录/账本测试；先由Python核验隔离user目录，不写玩家存档。
extends SceneTree
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Saga = preload("res://scripts/campaign/saga_catalog.gd")
const Threats = preload("res://scripts/rpg/strategy_encounters.gd")
const Loadouts = preload("res://scripts/rpg/loadout_rules.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL: ", message)
func _finish() -> void:
	print("MERCHANT_CATALOG: %d assertions, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
func _run() -> void:
	check(ResourceLoader.exists("res://scripts/campaign/merchant_catalog.gd"), "神秘商人纯目录模块存在")
	if not failures.is_empty(): _finish(); return
	var Merchant = load("res://scripts/campaign/merchant_catalog.gd")
	var catalog := Catalog.new()
	check(catalog.load_all().is_empty(), "真实装备/卡目录可加载")
	var saved := _fixture()
	saved.merchant = Merchant.initial()
	check(Merchant.validate(saved, catalog).is_empty(), "真实七章事件/导航夹具与空商人账本合法")
	var offers: Array = Merchant.offers(saved, catalog)
	check(offers.size() == 10, "六件真实装备与四张已登记被动卡")
	var prices := {"iron_amulet": 80, "swift_tachi": 180, "ranger_garb": 120, "bead_bracelet": 80, "monk_kesa": 140, "spirit_bell": 180, "force_channel": 140, "iron_oath": 120, "sustained_rite": 140, "swift_cast": 160}
	for offer in offers:
		check(offer.stock == 1 and offer.unlocked and offer.price > 0 and not offer.description.is_empty(), "首轮商品有限库存/价格/说明：" + offer.id)
		check(offer.price == prices.get(offer.item_id, -1), "货架价格符合批准设计：" + offer.id)
		check(not (catalog.get_definition("equipment", offer.item_id) if offer.kind == "gear" else Loadouts.card(offer.item_id)).is_empty(), "商品为真实物品而非剧情物证：" + offer.id)
	var first := {"schema_version": 3, "merchant": Merchant.initial()}
	check(Merchant.validate(first, catalog).is_empty() and not Merchant.presence(first) and Merchant.spent(first) == 0, "首章只允许合法空账本，商人尚未出现")
	var early := _fixture("C2-12"); early.merchant = Merchant.initial()
	check(not Merchant.presence(early), "C2危机解除前不出现")
	var opened := _fixture("C2-13"); opened.merchant = Merchant.initial()
	check(Merchant.presence(opened), "C2-13提交后在安全探索出现")
	for offer in Merchant.offers(opened, catalog):
		check(offer.unlocked == (offer.item_id in ["iron_amulet", "swift_tachi"]), "商品按实际已完成批次解锁：" + offer.id)
	for trigger in ["C3-08", "C4-10", "C5-13", "C6-12", ""]:
		var state := _fixture(trigger); state.merchant = Merchant.initial()
		check(Merchant.presence(state), "各章安全事件后出现：" + trigger)
		var available := 0
		for offer in Merchant.offers(state, catalog):
			if offer.unlocked: available += 1
		check(available == {3: 3, 4: 5, 5: 7, 6: 9, 7: 10}[state.saga.chapter], "装备/被动按章批次开放且不重置旧货：" + trigger)
		var point: Vector3 = Merchant.anchor(state)
		var World = load("res://scripts/campaign/saga_world.gd")
		var walkable := false
		for rect in World._rects(state.saga.chapter):
			if rect.grow(-0.4).has_point(Vector2(point.x, point.z)): walkable = true
		check(walkable, "商人锚位于可步行地面且距边界有胶囊余量：" + trigger)
	var world: Dictionary = _at_merchant(opened, Merchant)
	var before: Dictionary = opened.duplicate(true)
	var bought: Dictionary = Merchant.preview(opened, world, "gear_iron_amulet_v1", 1, catalog)
	check(bought.ok, "真实货物购买预览合法：" + str(bought.get("error")))
	if not bought.ok: _finish(); return
	check(opened == before, "购买预览不修改输入安全档")
	check(bought.candidate.saga.coins == opened.saga.coins - 80 and bought.candidate.gear.iron_amulet == int(opened.gear.get("iron_amulet", 0)) + 1, "候选同时扣款并增加真实装备")
	check(Merchant.spent(bought.candidate) == 80 and Merchant.validate(bought.candidate, catalog).is_empty(), "完整购买账本可独立重放")
	check(bought.receipt.unit_price == _offer(Merchant.offers(opened, catalog), "gear_iron_amulet_v1").price, "展示价格与实际扣款同表")
	check(not Merchant.preview(bought.candidate, world, "gear_iron_amulet_v1", 1, catalog).ok, "再次购买不突破全局库存")
	for bad_count in [0, -1, 2, 1.0, true, "1"]:
		check(not Merchant.preview(opened, world, "gear_iron_amulet_v1", bad_count, catalog).ok, "数量严格整数且不可超过库存：" + str(bad_count))
	check(not Merchant.preview(opened, world, "shared_mirror_shard", 1, catalog).ok, "不可出售剧情物证")
	check(not Merchant.preview(opened, world, "card_force_channel_v1", 1, catalog).ok, "未来批次未解锁不可买")
	var far: Dictionary = world.duplicate(true); far.position[0] += 8.0
	check(not Merchant.preview(opened, far, "gear_iron_amulet_v1", 1, catalog).ok, "远离实地摊点不能购买")
	var forged_world: Dictionary = world.duplicate(true); forged_world.event_flags["scene:C2-14"] = true
	check(not Merchant.preview(opened, forged_world, "gear_iron_amulet_v1", 1, catalog).ok, "外部world不能伪造安全故事检查点")
	for field in ["active_scene", "retry"]:
		var busy: Dictionary = opened.duplicate(true)
		busy.saga[field] = "C2-14" if field == "active_scene" else {"scene": "C7-05", "stage": 1}
		check(not Merchant.presence(busy) and not Merchant.preview(busy, world, "gear_iron_amulet_v1", 1, catalog).ok, "互动/败北阶段不出现：" + field)
	var pending: Dictionary = opened.duplicate(true); pending.pending_battle = {"battle_id": "pending"}
	check(not Merchant.presence(pending) and not Merchant.preview(pending, world, "gear_iron_amulet_v1", 1, catalog).ok, "战前安全档有待决战斗时不交易")
	pending = opened.duplicate(true); pending.phase = "defeat"
	check(not Merchant.presence(pending), "失败表现阶段不以探索旧world强开商人")
	var poor: Dictionary = opened.duplicate(true)
	# 通过真实普通补给扣款构造余额不足，不能凭空改coin制造合法档。
	while poor.saga.coins >= 18:
		poor.saga.transactions.append({"item": "healing_potion", "count": 1, "cost": 18}); poor.saga.coins -= 18
	check(Merchant.validate(poor, catalog).is_empty() and not Merchant.preview(poor, world, "gear_iron_amulet_v1", 1, catalog).ok, "合法补给消费后银钱不足拒绝")
	_test_corruption(Merchant, bought.candidate, catalog)
	# 把早期购买保留到七章；既有库存不因后续剧情/休息重置。
	var late: Dictionary = saved.duplicate(true)
	late.merchant = bought.candidate.merchant.duplicate(true); late.saga.coins -= 80
	late.gear.iron_amulet = int(late.gear.get("iron_amulet", 0)) + 1
	check(Merchant.validate(late, catalog).is_empty() and _offer(Merchant.offers(late, catalog), "gear_iron_amulet_v1").stock == 0, "跨章仍是一份全局库存")
	var revisited: Dictionary = late.duplicate(true)
	revisited.saga.chapter = 2; revisited.saga.scene = revisited.saga.cursors["2"]
	revisited.saga.navigation.append({"kind": "travel", "destination": 2, "events": revisited.saga.events.size()})
	revisited.world = Saga.initial_world(2); revisited.night = 6; revisited.scene_id = revisited.world.scene_id
	check(Merchant.validate(revisited, catalog).is_empty() and Merchant.presence(revisited), "真实导航回访旧章仍在安全摊点出现")
	check(_offer(Merchant.offers(revisited, catalog), "gear_iron_amulet_v1").stock == 0 and _offer(Merchant.offers(revisited, catalog), "card_swift_cast_v1").unlocked, "回访旧章保留已实际解锁的后期批次与售罄库存")
	var future: Dictionary = late.duplicate(true)
	future.merchant.purchases[0].battle_count = future.saga.battles.size()
	check(not Merchant.validate(future, catalog).is_empty(), "不得回填未来战斗数量支付早期购买")
	var early_overdraft: Dictionary = late.duplicate(true)
	early_overdraft.saga.transactions = poor.saga.transactions.duplicate(true)
	early_overdraft.saga.coins -= opened.saga.coins - poor.saga.coins
	early_overdraft.merchant.purchases[0].supply_transaction_count = poor.saga.transactions.size()
	var overdraft_errors: Array = Merchant.validate(early_overdraft, catalog)
	check(early_overdraft.saga.coins > 0 and not overdraft_errors.is_empty() and str(overdraft_errors).contains("未来"), "最终余额充足仍不能以未来收益弥补购买当时透支")
	var invented: Dictionary = late.duplicate(true)
	invented.merchant.purchases[0].chapter = 7
	check(not Merchant.validate(invented, catalog).is_empty(), "购买章节必须来自当时导航前缀")
	var closed: Dictionary = late.duplicate(true); closed.saga.battles.append("C7-05")
	check(not Merchant.presence(closed), "C7-05首胜后商人全局离场")
	closed.saga.chapter = 2
	check(not Merchant.presence(closed), "终战首胜后回旧章也不重现")
	var card: Dictionary = Merchant.preview(saved, _at_merchant(saved, Merchant), "card_swift_cast_v1", 1, catalog)
	check(card.ok and card.candidate.cards.swift_cast == int(saved.cards.get("swift_cast", 0)) + 1 and card.receipt.cost == 160, "已登记疾咏被动卡按第七章价格进入收藏")
	check(card.ok and Merchant.validate(card.candidate, catalog).is_empty(), "卡片账本保存与校验一致")
	if card.ok:
		var detour: Dictionary = card.candidate.duplicate(true)
		detour.saga.navigation.append({"kind": "scene", "id": "C7-01", "choice": "c", "events": detour.saga.events.size()})
		detour.saga.active_scene = "C7-R02"
		detour.merchant.purchases[0].navigation_count = detour.saga.navigation.size()
		check(str(Merchant.validate(detour, catalog)).contains("互动"), "历史购买切点不能处于绕路自动打开的互动")
	_finish()

func _test_corruption(Merchant: Script, state: Dictionary, catalog: RefCounted) -> void:
	for key in ["id", "price_version", "quantity", "unit_price", "cost", "stock_before", "stock_after", "chapter", "event_count", "battle_count", "supply_transaction_count", "navigation_count"]:
		for wrong in [true, 1.0, "1", -1]:
			var broken := state.duplicate(true); broken.merchant.purchases[0][key] = wrong
			check(not Merchant.validate(broken, catalog).is_empty(), "流水严格类型/范围：%s/%s" % [key, str(wrong)])
	for field in ["version", "purchases"]:
		var broken := state.duplicate(true); broken.merchant.erase(field)
		check(not Merchant.validate(broken, catalog).is_empty(), "缺失商人根字段拒绝：" + field)
	for target in ["root", "receipt"]:
		var broken := state.duplicate(true)
		if target == "root": broken.merchant.extra = true
		else: broken.merchant.purchases[0].extra = true
		check(not Merchant.validate(broken, catalog).is_empty(), "未知商人字段拒绝：" + target)
	var wrong_price := state.duplicate(true); wrong_price.merchant.purchases[0].unit_price = 79; wrong_price.merchant.purchases[0].cost = 79; wrong_price.saga.coins += 1
	check(not Merchant.validate(wrong_price, catalog).is_empty(), "改单价和余额仍无法伪造价格版本")
	var repeated := state.duplicate(true); repeated.merchant.purchases.append(repeated.merchant.purchases[0].duplicate(true)); repeated.merchant.purchases[1].id = 2; repeated.saga.coins -= 80
	check(not Merchant.validate(repeated, catalog).is_empty(), "重复流水即使改顺序id仍超过有限库存")
	var absent := state.duplicate(true); absent.erase("merchant")
	check(not Merchant.validate(absent, catalog).is_empty(), "缺扩展坏档不得隐式初始化")
	var unknown := state.duplicate(true); unknown.merchant.version = 99
	check(not Merchant.validate(unknown, catalog).is_empty(), "未知版本明确拒绝")
	for wrong in [1.0, true, "1"]:
		unknown = state.duplicate(true); unknown.merchant.version = wrong
		check(not Merchant.validate(unknown, catalog).is_empty() and Merchant.spent(unknown) == -1, "商人根版本严格整型，坏账本不按零消费处理")

func _offer(offers: Array, id: String) -> Dictionary:
	for offer in offers:
		if offer.id == id: return offer
	return {}
func _at_merchant(saved: Dictionary, Merchant: Script) -> Dictionary:
	var world: Dictionary = saved.world.duplicate(true)
	var point: Vector3 = Merchant.anchor(saved)
	world.position = [point.x, point.y, point.z]; world.player_x = point.x
	return world

func _fixture(stop_after: String = "") -> Dictionary:
	var original: Dictionary = Catalog._integerize(JSON.parse_string(FileAccess.get_file_as_string("res://tools/campaign/fixtures/loadout-schema2-chapter7.json")))
	var result: Dictionary = original.duplicate(true)
	result.schema_version = 3; result.erase("level"); result.erase("xp"); result.cards = Loadouts.initial_cards(); result.merchant = {"version": 1, "purchases": []}
	var replay := Saga.initial("sendoff")
	for step in original.saga.navigation:
		var event_count: int = replay.events.size()
		if int(step.events) > event_count:
			var event: Dictionary = original.saga.events[event_count]
			if not event.choice.is_empty(): replay.choices[event.id] = event.choice
			var encounter := Saga.encounter_for_saga(replay, event.id)
			if not encounter.is_empty():
				replay.battles.append(event.id); replay.battle_encounters[event.id] = encounter; replay.coins += int(Threats.rewards(encounter).coins)
			Saga.apply_effects(replay, Saga.scene(event.id), Saga.choice(event.id, event.choice))
			if not replay.completed.has(event.id): replay.completed.append(event.id)
			replay.events.append(event.duplicate(true))
		replay.navigation.append(step.duplicate(true))
		if step.kind == "travel":
			replay.chapter = step.destination
			if not replay.cursors.has(str(step.destination)): replay.cursors[str(step.destination)] = str(Saga.metadata(step.destination).entry)
		else:
			var entry := Saga.scene(step.id)
			var next := Saga.next_scene(entry, replay, Saga.choice(step.id, step.choice))
			if not next.is_empty() and Saga.chapter_for(next) != replay.chapter:
				if step.events > event_count: replay.cursors[str(replay.chapter)] = ""
				replay.chapter = Saga.chapter_for(next); replay.cursors[str(replay.chapter)] = next
			elif not next.is_empty() and Saga.scene(next).get("kind", "main") in ["main", "ending"]: replay.cursors[str(replay.chapter)] = next
			elif next.is_empty() and entry.get("kind", "main") in ["main", "ending"]: replay.cursors[str(replay.chapter)] = ""
		replay.max_chapter = maxi(replay.chapter, replay.max_chapter)
		if not stop_after.is_empty() and replay.completed.has(stop_after): break
	replay.scene = replay.cursors[str(replay.chapter)]
	result.saga = replay
	result.night = replay.chapter + 4; result.world = Saga.initial_world(replay.chapter); result.scene_id = result.world.scene_id
	result.world_history[result.scene_id] = result.world.duplicate(true)
	return result
