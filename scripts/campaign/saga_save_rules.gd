# 验证后六章完整事务记录，拒绝篡改分支、跳章与重复奖励。
class_name CampaignSagaSaveRules
extends RefCounted
const Routes = preload("res://scripts/campaign/saga_route_rules.gd")
const Saga = preload("res://scripts/campaign/saga_catalog.gd")
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
const Forms = preload("res://scripts/rpg/dual_form.gd")
const State = preload("res://scripts/rpg/battle_state.gd")

static func validate(saved: Dictionary, catalog: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var saga = saved.get("saga")
	if not saga is Dictionary: return ["后续进度不是字典"]
	for field in ["version", "chapter", "max_chapter", "coins"]:
		if not saga.get(field) is int: return ["后续整数数据非法：" + field]
	if saga.version != 1: return ["未知后续进度版本，保留原档"]
	if saga.chapter < 2 or saga.chapter > 7 or saga.max_chapter < saga.chapter or saga.max_chapter > 7: return ["后续到达章节非法"]
	for field in ["scene", "active_scene", "ending"]:
		if not saga.get(field) is String: return ["后续场次数据非法：" + field]
	for field in ["completed", "battles", "transactions", "events"]:
		if not saga.get(field) is Array: return ["后续历史格式非法：" + field]
	for field in ["choices", "flags", "cursors", "battle_encounters", "retry"]:
		if not saga.get(field) is Dictionary: return ["后续字典非法：" + field]
	if not saved.get("resolution") in ["sendoff", "seal_monitoring"]: return ["后续进度缺少首章处理记录"]
	if saved.get("campaign_id") != Chapters.PROFILE_ID or saved.get("case_status") != ("closed" if saved.resolution == "sendoff" else "monitoring"): errors.append("后续进度改写了首章责任")
	if saved.get("story_phase") not in ["exploration", "complete"] or saved.get("chapter_complete") != (saved.get("story_phase") == "complete"): errors.append("后续完成状态不符")
	if not saved.get("world") is Dictionary or not Saga.validate_world(saved.world).is_empty(): return ["后续当前世界非法"]
	if saved.world.night != saga.chapter + 4 or saved.get("night") != saved.world.night or saved.get("scene_id") != saved.world.scene_id: errors.append("后续章节与地图不符")
	if saved.world.get("story_encounter") != (Saga.encounter_for_saga(saga, saga.active_scene) if not saga.active_scene.is_empty() else ""): errors.append("后续有效遭遇与场次条件不符")
	if saved.world.story_scene != saga.active_scene or saved.world.story_choice != str(saga.choices.get(saga.active_scene, "")): errors.append("后续活动场次与地图检查点不符")
	if not saga.scene.is_empty() and (Saga.scene(saga.scene).is_empty() or Saga.chapter_for(saga.scene) != saga.chapter): errors.append("后续主线场次不属于当前章节")
	if not saga.active_scene.is_empty() and (Saga.scene(saga.active_scene).is_empty() or Saga.chapter_for(saga.active_scene) != saga.chapter): errors.append("后续互动不属于当前章节")
	if not saved.get("world_history") is Dictionary: return ["后续缺少地区检查点"]
	if saved.world_history.size() != saga.max_chapter + 4: errors.append("后续历史数量与到达章节不符")
	for night in range(1, saga.max_chapter + 5):
		var world = saved.world_history.get("night_%d" % night)
		if not world is Dictionary or not Chapters.validate_world(world).is_empty() or world.get("night") != night:
			errors.append("后续地区历史非法：%d" % night)
			continue
		if night <= 5 and not Chapters.complete(world): errors.append("后续进度缺少五夜完成历史")
		if night >= 6:
			var expected_events := {}; var expected_dialogue := {}; var expected_resolved := {}
			for id in saga.completed:
				if Saga.chapter_for(str(id)) == night - 4: expected_events["scene:" + str(id)] = true; expected_dialogue[id] = true
			for id in saga.battles:
				if Saga.chapter_for(str(id)) == night - 4: expected_events["battle:" + str(id)] = true; expected_resolved[id] = true
			if world.event_flags != expected_events or world.dlg_fired != expected_dialogue or world.resolved != expected_resolved: errors.append("后续地区事件镜像与事务来源不符")
		if night == saved.world.night and world != saved.world: errors.append("后续当前世界与历史不一致")
	for id in range(2, saga.max_chapter):
		if not Saga.chapter_complete(saga, id): errors.append("后续跳过未完成章节：%d" % id)
	var replay := Saga.initial(saved.resolution)
	var prefixes: Array = [replay.duplicate(true)]
	var seen: Array = []
	var replay_choices := {}
	for event in saga.events:
		if not event is Dictionary or not event.get("id") is String or not event.get("choice") is String: return ["后续完成事件记录非法"]
		if event.id == "C7-R04": replay.retry = {"stage": int(event.get("retry_stage", 0))}
		var entry := Saga.scene(event.id)
		if entry.is_empty(): return ["后续完成事件未登记"]
		if Saga.chapter_for(event.id) > saga.max_chapter: errors.append("完成事件超出已开放章节")
		for prior in range(2, Saga.chapter_for(event.id)):
			if not Saga.chapter_complete(replay, prior): errors.append("事件当时尚未完成前章")
		if not Saga.matches(entry.get("requires", {}), Saga.context(replay)): errors.append("后续完成事件缺少前置：" + event.id)
		var option := Saga.choice(event.id, event.choice)
		if not event.choice.is_empty() and option.is_empty(): errors.append("完成事件选择未登记")
		if not Saga.eligible_choices(entry, replay).is_empty() and option.is_empty(): errors.append("后续完成事件缺少有效选择：" + event.id)
		if not option.is_empty() and not Saga.matches(option.get("requires", {}), Saga.context(replay)): errors.append("后续已选方案缺少条件：" + event.id)
		if seen.has(event.id) and not str(entry.get("encounter_id", "")).is_empty(): errors.append("后续战斗场次重复提交：" + event.id)
		if not seen.has(event.id): seen.append(event.id)
		if not event.choice.is_empty(): replay_choices[event.id] = event.choice
		replay.choices = replay_choices.duplicate(true)
		var required_encounter := Saga.encounter_for_saga(replay, event.id)
		if not required_encounter.is_empty() and saga.battle_encounters.get(event.id, "") != required_encounter: errors.append("本次场次前置要求真实战斗胜利：" + event.id)
		if not required_encounter.is_empty() and saga.battle_encounters.get(event.id, "") == required_encounter and not replay.battles.has(event.id): replay.battles.append(event.id)
		Saga.apply_effects(replay, entry, option)
		if not replay.completed.has(event.id): replay.completed.append(event.id)
		replay.retry = {}
		prefixes.append(replay.duplicate(true))
	errors.append_array(Routes.validate(saga, prefixes))
	if not saga.retry.is_empty():
		if not saga.retry.get("stage") is int or saga.retry.stage < 1 or saga.retry.stage > 3 or not saga.retry.get("scene") is String or not saga.retry.scene in ["C7-05", "C7-06", "C7-10", "C7-11", "C7-12", "C7-13"] or saga.active_scene != "C7-R04": errors.append("后续败北整备记录非法")
	if saga.completed != seen: errors.append("后续完成列表与事务历史不符")
	if saga.flags != replay.flags or saga.ending != replay.ending: errors.append("后续状态/结局与已完成事件不符")
	for key in saga.choices:
		if not key is String or not saga.choices[key] is String or Saga.choice(key, saga.choices[key]).is_empty(): errors.append("后续选择引用非法")
		elif key != saga.active_scene and replay_choices.get(key, "") != saga.choices[key]: errors.append("后续选择缺少完成记录")
	for id in replay_choices:
		if id != saga.active_scene and saga.choices.get(id, "") != replay_choices[id]: errors.append("已完成选择记录缺失或改变")
	var current_context := Saga.context(saga)
	if not saga.active_scene.is_empty():
		var active := Saga.scene(saga.active_scene)
		if not Saga.matches(active.get("requires", {}), current_context): errors.append("活动场次缺少开放前置")
		if str(active.get("kind", "main")) in ["main", "ending"] and saga.active_scene != saga.scene: errors.append("活动主线与游标不符")
		var selected := Saga.choice(saga.active_scene, str(saga.choices.get(saga.active_scene, "")))
		if not selected.is_empty() and not Saga.matches(selected.get("requires", {}), current_context): errors.append("活动选择缺少条件")
	if saga.flags.get("resolution") != saved.resolution or saga.flags.get("first_chapter_sendoff") != (saved.resolution == "sendoff"): errors.append("首章送行事实不可改变")
	if saga.cursors.size() != saga.max_chapter - 1 or saga.cursors.get(str(saga.chapter)) != saga.scene: errors.append("后续主线游标数量/当前章不符")
	for key in saga.cursors:
		if not key is String or not key.is_valid_int() or int(key) < 2 or int(key) > saga.max_chapter or not saga.cursors[key] is String: errors.append("后续游标格式非法")
		elif not saga.cursors[key].is_empty() and (Saga.scene(saga.cursors[key]).is_empty() or Saga.chapter_for(saga.cursors[key]) != int(key)): errors.append("后续游标指向别章")
	for key in saga.cursors:
		if not saga.cursors[key] is String: continue
		var cursor: String = saga.cursors[key]
		if cursor.is_empty():
			if not Saga.chapter_complete(saga, int(key)): errors.append("未完成章节不可清空主线游标")
		elif not Saga.matches(Saga.scene(cursor).get("requires", {}), current_context): errors.append("主线游标缺少前置")
	if saga.battle_encounters.size() != saga.battles.size(): errors.append("后续胜利来源与战斗列表不符")
	var total_xp := 280
	var expected_coins := 120
	var seen_battles: Array = []
	for id in saga.battles:
		if not id is String or seen_battles.has(id): return ["后续战斗列表非法/重复"]
		seen_battles.append(id)
		var encounter_id: String = str(saga.battle_encounters.get(id, ""))
		var entry := Saga.scene(id)
		var possible: Array = [str(entry.get("encounter_id", ""))]
		for option in entry.get("choices", []): possible.append(str(option.get("encounter_id", "")))
		if not possible.has(encounter_id): return ["后续胜利遭遇与场次来源不符"]
		var encounter: Dictionary = catalog.get_definition("encounters", encounter_id)
		if encounter_id.is_empty() or encounter.is_empty(): return ["后续战斗未登记"]
		if not saga.completed.has(id) and saga.active_scene != id: errors.append("后续战胜记录不属于已完成或当前场次")
		total_xp += int(encounter.xp)
		expected_coins += 25 + int(encounter.xp) / 5
	for transaction in saga.transactions:
		if not transaction is Dictionary or not transaction.get("item") is String or not transaction.get("count") is int or not transaction.get("cost") is int: return ["后续交易记录非法"]
		if not Saga.SHOP.has(transaction.item) or transaction.count < 1 or transaction.count > 9 or transaction.cost != Saga.SHOP.get(transaction.item, 0) * transaction.count: return ["后续交易数量/价格非法"]
		expected_coins -= transaction.cost
	if saga.coins < 0 or saga.coins != expected_coins: errors.append("后续钱数与战斗/交易记录不符")
	var level := 5
	while level < 10 and total_xp >= 100 * level:
		total_xp -= 100 * level
		level += 1
	if level == 10: total_xp = 0
	if saved.get("level") != level or saved.get("xp") != total_xp: errors.append("后续等级/经验与遭遇记录不符")
	var applied = saved.get("applied_battle_ids")
	var pending = saved.get("pending_battle")
	if not applied is Array or not pending is Dictionary: return ["后续战斗持久字段非法"]
	if applied.size() != 5 + saga.battles.size() or saved.get("battle_counter") != applied.size() + (0 if pending.is_empty() else 1): errors.append("后续战斗计数与胜利记录不符")
	for index in range(applied.size()):
		if applied[index] != saved.run_id + ":" + str(index + 1): errors.append("后续已提交战斗ID顺序非法")
	if not pending.is_empty():
		if pending.get("battle_id") != saved.run_id + ":" + str(saved.battle_counter) or not pending.get("seed") is int or pending.seed != int(str(pending.get("battle_id", "")).hash()): errors.append("后续战前ID/种子非法")
		if pending.get("encounter_id") != str(saved.world.get("story_encounter", "")): errors.append("后续战前遭遇与活动场次不符")
	if saved.get("next_encounter_id") != "": errors.append("后续遭遇由场次登记，不能缓存任意下一场")
	var completed: bool = saved.get("story_phase") == "complete"
	if completed and (saga.chapter != 7 or saga.ending.is_empty() or not saga.scene.is_empty()): errors.append("终章尚未达到完成结局")
	var expected_return: String = Saga.ENDING_PATH if completed else Saga.SCENE_PATH
	if saved.get("return_scene") != expected_return and not (not pending.is_empty() and saved.get("return_scene") == ""): errors.append("后续返回入口与完成记录不符")
	for actor_id in Chapters.BINDINGS:
		var actor: Dictionary = saved.roster.get(actor_id, {})
		if actor.get("identity_id") != Chapters.BINDINGS[actor_id].identity_id: errors.append("后续人物身份非法")
		if actor_id == "p_mage":
			errors.append_array(Forms.validate(actor, catalog))
			if actor.get("unlocked_forms") != Forms.UNLOCKED_FORMS: errors.append("后续焰华解锁记录非法")
		elif actor.get("form_id") != Chapters.BINDINGS[actor_id].form_id: errors.append("后续人物形态非法")
	return errors
