# 后六章状态事务。视图只请求操作，不自行修改剧情/货币/奖励。
class_name CampaignSagaProgress
extends RefCounted
const Saga = preload("res://scripts/campaign/saga_catalog.gd")

static func continue_run(model: RefCounted) -> Dictionary:
	var saved: Dictionary = model.safe_snapshot()
	if not model._outside() or saved.get("schema_version") != 2 or saved.has("saga") or saved.get("story_phase") != "complete" or saved.get("night") != 5:
		return model._fail("请先完成第一章结案，再沿山路下山")
	var candidate := saved.duplicate(true)
	candidate["saga"] = Saga.initial(str(saved.resolution))
	candidate.world = Saga.initial_world(2)
	candidate.night = candidate.world.night
	candidate.scene_id = candidate.world.scene_id
	candidate.world_history[candidate.world.scene_id] = candidate.world.duplicate(true)
	candidate.story_phase = "exploration"
	candidate.chapter_complete = false
	candidate.phase = "exploration"
	candidate.next_encounter_id = ""
	candidate.return_scene = Saga.SCENE_PATH
	return model._commit(candidate)

static func begin_scene(model: RefCounted, world: Dictionary, id: String) -> Dictionary:
	if not _safe_world(model, world): return model._fail("当前场次与安全探索记录不符")
	var saved: Dictionary = model.safe_snapshot()
	if not saved.saga.active_scene.is_empty() and saved.saga.active_scene != id: return model._fail("请先完成当前互动，再调查别处")
	if not Saga.available(saved.saga, id) and saved.saga.active_scene != id: return model._fail("这段记录尚未开放或已经完成")
	var candidate := saved.duplicate(true)
	candidate.world = world.duplicate(true)
	if candidate.saga.active_scene != id: _activate(candidate, id)
	_sync(candidate)
	return model._commit(candidate)

static func select_choice(model: RefCounted, world: Dictionary, id: String, choice_id: String) -> Dictionary:
	if not _safe_world(model, world): return model._fail("当前选择与已保存场次不符")
	var saved: Dictionary = model.safe_snapshot()
	if saved.saga.active_scene != id: return model._fail("选择不属于当前互动")
	var option := Saga.choice(id, choice_id)
	if option.is_empty() or not Saga.matches(option.get("requires", {}), Saga.context(saved.saga)): return model._fail("这个选项的条件尚未完成")
	# 已确认选择不能在战前重启后改选以撤销责任或重掷遭遇。
	if not str(world.get("story_choice", "")).is_empty():
		return model._unchanged() if saved.saga.choices[id] == choice_id else model._fail("本场已确认选择，请继续当前方案")
	var candidate := saved.duplicate(true)
	candidate.saga.choices[id] = choice_id
	candidate.world = world.duplicate(true)
	candidate.world.story_choice = choice_id
	candidate.world.story_encounter = Saga.encounter_for_saga(candidate.saga, id)
	_sync(candidate)
	return model._commit(candidate)

static func complete_scene(model: RefCounted, world: Dictionary, id: String) -> Dictionary:
	if not _safe_world(model, world): return model._fail("互动完成记录与安全档不符")
	var saved: Dictionary = model.safe_snapshot()
	if saved.saga.active_scene != id: return model._fail("完成记录不属于当前互动")
	var entry := Saga.scene(id)
	var option := Saga.choice(id, str(saved.saga.choices.get(id, "")))
	if not Saga.eligible_choices(entry, saved.saga).is_empty() and option.is_empty(): return model._fail("请先选择本场处理方式")
	var encounter_id: String = str(world.get("story_encounter", ""))
	if not encounter_id.is_empty() and not saved.saga.battles.has(id): return model._fail("本场尚未赢得战斗，不能提交战后救援或奖励")
	var candidate := saved.duplicate(true)
	candidate.world = world.duplicate(true)
	var selected_choice: String = str(candidate.saga.choices.get(id, ""))
	var next_id := Saga.next_scene(entry, candidate.saga, option)
	var next_entry := Saga.scene(next_id)
	var main: bool = str(entry.get("kind", "main")) in ["main", "ending"]
	# 返回方案、自我循环和支线整备不是主线完成，避免“先救人”被记录成已经离城。
	var detour: bool = main and (next_id == id or (not next_entry.is_empty() and str(next_entry.get("kind", "main")) in ["side", "revisit"]) or (not next_id.is_empty() and Saga.chapter_for(next_id) < int(candidate.saga.chapter)))
	if not detour:
		Saga.apply_effects(candidate.saga, entry, option)
		var record := {"id": id, "choice": str(candidate.saga.choices.get(id, ""))}
		if id == "C7-R04": record["retry_stage"] = int(candidate.saga.retry.get("stage", 0))
		candidate.saga.events.append(record)
		if not candidate.saga.completed.has(id): candidate.saga.completed.append(id)
		candidate.world.event_flags["scene:" + id] = true
		candidate.world.dlg_fired[id] = true
		next_id = Saga.next_scene(entry, candidate.saga, option)
		next_entry = Saga.scene(next_id)
	else:
		_restore_historical_choice(candidate.saga, id)
	if id == "C7-R04": candidate.saga.retry = {}
	# 已赢得的终战阶段不重打；返回整备再入厅时沿登记路线跳过持久胜利。
	var skipped := 0
	while not next_id.is_empty() and candidate.saga.completed.has(next_id) and candidate.saga.battles.has(next_id) and skipped < 10:
		next_id = Saga.next_scene(Saga.scene(next_id), candidate.saga, Saga.choice(next_id, str(candidate.saga.choices.get(next_id, ""))))
		next_entry = Saga.scene(next_id)
		skipped += 1
	if not next_id.is_empty() and not Saga.matches(next_entry.get("requires", {}), Saga.context(candidate.saga)): return model._fail("后续互动尚未开放，请先完成本章当前调查")
	if not candidate.saga.choices.has(id): _restore_historical_choice(candidate.saga, id)
	_activate(candidate, "")
	if not next_id.is_empty() and Saga.chapter_for(next_id) != int(candidate.saga.chapter):
		var destination := Saga.chapter_for(next_id)
		if destination > int(candidate.saga.max_chapter) and not Saga.chapter_complete(candidate.saga, int(candidate.saga.chapter)):
			return model._fail("尚有必需调查或责任交接未完成，不能离章")
		if not detour:
			candidate.saga.scene = ""
			candidate.saga.cursors[str(candidate.saga.chapter)] = ""
		_move(candidate, destination, next_id)
	elif not next_id.is_empty():
		if str(next_entry.get("kind", "main")) in ["main", "ending"]:
			candidate.saga.scene = next_id
			candidate.saga.cursors[str(candidate.saga.chapter)] = next_id
		else: _activate(candidate, next_id)
	elif main and not detour:
		candidate.saga.scene = ""
		candidate.saga.cursors[str(candidate.saga.chapter)] = ""
	candidate.saga.navigation.append({"kind": "scene", "id": id, "choice": selected_choice, "events": candidate.saga.events.size()})
	if candidate.saga.chapter == 7 and not candidate.saga.ending.is_empty() and candidate.saga.scene.is_empty():
		candidate.story_phase = "complete"
		candidate.chapter_complete = true
		candidate.return_scene = Saga.ENDING_PATH
	else: candidate.return_scene = Saga.SCENE_PATH
	_sync(candidate)
	return model._commit(candidate)

static func _restore_historical_choice(saga: Dictionary, id: String) -> void:
	saga.choices.erase(id)
	for event in saga.events:
		if event.id == id and not str(event.choice).is_empty(): saga.choices[id] = event.choice

static func _activate(candidate: Dictionary, id: String) -> void:
	candidate.saga.active_scene = id
	if not id.is_empty() and candidate.saga.completed.has(id): candidate.saga.choices.erase(id)
	candidate.world.story_scene = id
	candidate.world.story_choice = str(candidate.saga.choices.get(id, ""))
	candidate.world.story_encounter = Saga.encounter_for_saga(candidate.saga, id) if not id.is_empty() else ""

static func _move(candidate: Dictionary, destination: int, cursor: String = "") -> void:
	candidate.world_history[candidate.world.scene_id] = candidate.world.duplicate(true)
	candidate.saga.chapter = destination
	candidate.saga.max_chapter = maxi(destination, int(candidate.saga.max_chapter))
	if not candidate.saga.cursors.has(str(destination)): candidate.saga.cursors[str(destination)] = str(Saga.metadata(destination).entry)
	if not cursor.is_empty(): candidate.saga.cursors[str(destination)] = cursor
	candidate.saga.scene = candidate.saga.cursors[str(destination)]
	var key := "night_%d" % (destination + 4)
	candidate.world = candidate.world_history.get(key, Saga.initial_world(destination)).duplicate(true)
	candidate.night = destination + 4
	candidate.scene_id = candidate.world.scene_id
	_activate(candidate, "")

static func travel(model: RefCounted, world: Dictionary, destination: int) -> Dictionary:
	if not _safe_world(model, world): return model._fail("当前不能离开地区")
	var saved: Dictionary = model.safe_snapshot()
	if destination < 2 or destination > 7 or destination == int(saved.saga.chapter): return model._fail("目的地未登记或已在当前地区")
	if not saved.saga.active_scene.is_empty(): return model._fail("请先完成当前互动，再离开地区")
	if destination > int(saved.saga.max_chapter):
		if destination != int(saved.saga.max_chapter) + 1 or not Saga.chapter_complete(saved.saga, int(saved.saga.max_chapter)):
			return model._fail("前路尚未开放，请完成当前主线与责任交接")
	var candidate := saved.duplicate(true)
	candidate.world = world.duplicate(true)
	_move(candidate, destination)
	candidate.saga.navigation.append({"kind": "travel", "destination": destination, "events": candidate.saga.events.size()})
	candidate.return_scene = Saga.SCENE_PATH
	_sync(candidate)
	return model._commit(candidate)

static func buy(model: RefCounted, world: Dictionary, item_id: String, count: int = 1) -> Dictionary:
	if not _safe_world(model, world) or count < 1 or count > 9: return model._fail("当前不能购买或数量非法")
	if not Saga.SHOP.has(item_id) or model._catalog.get_definition("items", item_id).is_empty(): return model._fail("商店没有这件物品")
	var saved: Dictionary = model.safe_snapshot()
	var cost: int = int(Saga.SHOP[item_id]) * count
	if int(saved.saga.coins) < cost: return model._fail("钱不够，任务灯与必需工具仍由委托提供")
	var candidate := saved.duplicate(true)
	candidate.world = world.duplicate(true)
	candidate.saga.coins -= cost
	candidate.saga.transactions.append({"item": item_id, "count": count, "cost": cost})
	candidate.inventory[item_id] = int(candidate.inventory.get(item_id, 0)) + count
	_sync(candidate)
	return model._commit(candidate)

static func apply_battle(candidate: Dictionary, encounter: Dictionary) -> void:
	var id: String = candidate.world.story_scene
	if not candidate.saga.battles.has(id): candidate.saga.battles.append(id)
	candidate.saga.battle_encounters[id] = str(encounter.id)
	candidate.saga.coins += 25 + int(encounter.get("xp", 0)) / 5
	candidate.next_encounter_id = ""
	candidate.world_history[candidate.world.scene_id] = candidate.world.duplicate(true)

static func _safe_world(model: RefCounted, world: Dictionary) -> bool:
	return model._outside() and model.safe_snapshot().has("saga") and model.safe_snapshot().get("story_phase") == "exploration" and model._chapter_world_ok(world)

static func _sync(candidate: Dictionary) -> void:
	candidate.world_history[candidate.world.scene_id] = candidate.world.duplicate(true)
	candidate.next_encounter_id = ""

static func leave_battle(model: RefCounted) -> Dictionary:
	var saved: Dictionary = model.safe_snapshot()
	if not saved.has("saga") or saved.pending_battle.is_empty() or model._mode != "defeat": return model._fail("仅败北后可以回到战前整备")
	var candidate := saved.duplicate(true)
	var id: String = candidate.saga.active_scene
	candidate.pending_battle = {}
	candidate.battle_counter -= 1
	candidate.phase = "exploration"
	candidate.return_scene = Saga.SCENE_PATH
	if id.begins_with("C7-"):
		var stage := 1 if id == "C7-05" else (2 if id == "C7-06" else 3)
		candidate.saga.retry = {"scene": id, "stage": stage}
		_activate(candidate, "C7-R04")
	_sync(candidate)
	return model._commit(candidate)
