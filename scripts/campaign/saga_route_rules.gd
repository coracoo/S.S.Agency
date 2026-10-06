# 同时记录没有推进正文的绕路，才能区别“稳灯后去药库”和伪造游标直接跳过药库。
class_name CampaignSagaRouteRules
extends RefCounted
const Saga = preload("res://scripts/campaign/saga_catalog.gd")

static func validate(saga: Dictionary, prefixes: Array) -> Array[String]:
	if not saga.get("navigation") is Array: return ["后续缺少导航事务记录"]
	var chapter := 2
	var maximum := 2
	var count := 0
	var cursors := {"2": str(Saga.metadata(2).entry)}
	for step in saga.navigation:
		if not step is Dictionary or not step.get("events") is int or not step.get("kind") is String: return ["后续导航记录格式非法"]
		var after_count: int = step.events
		if after_count < count or after_count > count + 1 or after_count >= prefixes.size(): return ["导航与正文事件顺序不符"]
		var before: Dictionary = prefixes[count].duplicate(true)
		var after: Dictionary = prefixes[after_count].duplicate(true)
		if step.kind == "travel":
			if after_count != count or not step.get("destination") is int: return ["地区旅行不能提交正文"]
			var destination: int = step.destination
			if destination < 2 or destination > 7 or destination == chapter: return ["旅行目的地非法"]
			if destination > maximum and (destination != maximum + 1 or not Saga.chapter_complete(after, maximum)): return ["旅行跳过未完成章节"]
			chapter = destination
			maximum = maxi(maximum, chapter)
			if not cursors.has(str(chapter)): cursors[str(chapter)] = str(Saga.metadata(chapter).entry)
			continue
		if step.kind != "scene" or not step.get("id") is String or not step.get("choice") is String: return ["未知导航动作"]
		var id: String = step.id
		var entry := Saga.scene(id)
		if entry.is_empty() or Saga.chapter_for(id) != chapter: return ["正文事件发生在未抵达章节"]
		var option := Saga.choice(id, step.choice)
		if not step.choice.is_empty() and option.is_empty(): return ["导航选择未登记"]
		if after_count == count + 1:
			var event: Dictionary = saga.events[count]
			if event.id != id or event.choice != step.choice: return ["导航与完成场次选择不符"]
			if id == "C7-R04": before.retry = {"stage": int(event.get("retry_stage", 0))}
		if not Saga.matches(entry.get("requires", {}), Saga.context(before)): return ["导航来源未开放"]
		if not option.is_empty() and not Saga.matches(option.get("requires", {}), Saga.context(before)): return ["导航选择不满足条件"]
		var main: bool = str(entry.get("kind", "main")) in ["main", "ending"]
		if main and cursors.get(str(chapter), "") != id: return ["正文事件跳过了已选路线"]
		var next_id := Saga.next_scene(entry, after, option)
		var next_entry := Saga.scene(next_id)
		var detour: bool = main and (next_id == id or (not next_entry.is_empty() and str(next_entry.get("kind", "main")) in ["side", "revisit"]) or (not next_id.is_empty() and Saga.chapter_for(next_id) < chapter))
		if (after_count == count) != detour: return ["绕路与正文完成记录不符"]
		var skipped := 0
		while not next_id.is_empty() and after.completed.has(next_id) and after.battles.has(next_id) and skipped < 10:
			next_id = Saga.next_scene(Saga.scene(next_id), after, Saga.choice(next_id, str(after.choices.get(next_id, ""))))
			next_entry = Saga.scene(next_id)
			skipped += 1
		if not next_id.is_empty() and not Saga.matches(next_entry.get("requires", {}), Saga.context(after)): return ["导航通往未开放场次"]
		if not next_id.is_empty() and Saga.chapter_for(next_id) != chapter:
			var destination := Saga.chapter_for(next_id)
			if destination > maximum and (destination != maximum + 1 or not Saga.chapter_complete(after, chapter)): return ["正文离章缺少前置"]
			if not detour: cursors[str(chapter)] = ""
			chapter = destination
			maximum = maxi(maximum, chapter)
			cursors[str(chapter)] = next_id
		elif not next_id.is_empty() and str(next_entry.get("kind", "main")) in ["main", "ending"]:
			cursors[str(chapter)] = next_id
		elif next_id.is_empty() and main and not detour:
			cursors[str(chapter)] = ""
		count = after_count
	if count != saga.events.size(): return ["正文事件缺少对应导航事务"]
	if chapter != saga.chapter or maximum != saga.max_chapter or cursors != saga.cursors: return ["章节/游标与所选路线的完整记录不符"]
	return []
