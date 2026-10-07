# 永久回收册只读派生：没有领取状态；源存档仍由正式Store完整校验。
class_name CampaignRecoveryCatalog
extends RefCounted

const DATA_PATH := "res://data/campaign/enemy_recoveries.json"
const PROFILE_ID := "five_night_3d_v1"
static var _entries: Dictionary = {}
static var _enemy_entries: Dictionary = {}

static func entry(id: String) -> Dictionary:
	var raw: Dictionary = _data().get(id, {})
	# 此接口没有存档上下文，永远不给出受剧情门禁保护的链接正文。
	return _present(raw, {}, {}, false) if not raw.is_empty() else {}

static func earned(saved: Dictionary, catalog: RefCounted) -> Array[Dictionary]:
	var context := _sources(saved, catalog)
	if not context.ok: return []
	var rows: Array[Dictionary] = []
	var seen: Dictionary = {}
	for source in context.sources:
		for enemy_id in source.enemy_ids:
			if seen.has(enemy_id): continue
			seen[enemy_id] = true
			rows.append(_present(_data()[_enemy_entries[enemy_id]], saved, source, false))
	return rows

static func preview_new(saved: Dictionary, encounter_id: String, catalog: RefCounted) -> Array[Dictionary]:
	var context := _sources(saved, catalog)
	if not context.ok: return []
	var pending: Dictionary = saved.pending_battle
	if not pending.is_empty() and pending.encounter_id != encounter_id: return []
	var source := _encounter_source(encounter_id, catalog)
	if source.is_empty(): return []
	# 未开战时只是下一提交序号的预测；preview标记不能当作已获记录。
	source.battle_id = pending.battle_id if not pending.is_empty() else saved.run_id + ":" + str(saved.applied_battle_ids.size() + 1)
	var seen: Dictionary = {}
	for committed in context.sources:
		for enemy_id in committed.enemy_ids: seen[enemy_id] = true
	var rows: Array[Dictionary] = []
	for enemy_id in source.enemy_ids:
		if seen.has(enemy_id): continue
		seen[enemy_id] = true
		rows.append(_present(_data()[_enemy_entries[enemy_id]], saved, source, true))
	return rows

static func _sources(saved: Dictionary, catalog: RefCounted) -> Dictionary:
	var rejected := {"ok": false, "sources": []}
	if _data().is_empty() or catalog == null or not catalog.has_method("get_definition"): return rejected
	if not saved.get("schema_version") is int or not saved.schema_version in [2, 3] or saved.get("campaign_id") != PROFILE_ID: return rejected
	if not saved.get("run_id") is String or saved.run_id.is_empty(): return rejected
	if not saved.get("world_history") is Dictionary or not saved.get("applied_battle_ids") is Array or not saved.get("pending_battle") is Dictionary or not saved.get("battle_counter") is int: return rejected
	var sources: Array[Dictionary] = []
	var gap := false
	for night in range(1, 6):
		var world = saved.world_history.get("night_%d" % night)
		if world == null:
			gap = true
			continue
		if not world is Dictionary or world.get("night") != night or not world.get("event_flags") is Dictionary: return rejected
		if not world.event_flags.has("battle:cleared"):
			gap = true
			continue
		if not world.event_flags["battle:cleared"] is bool or not world.event_flags["battle:cleared"] or gap: return rejected
		var source := _encounter_source("campaign_night_%d" % night, catalog)
		if source.is_empty(): return rejected
		sources.append(source)
	if saved.has("saga"):
		var saga = saved.saga
		if sources.size() != 5 or not saga is Dictionary or not saga.get("battles") is Array or not saga.get("battle_encounters") is Dictionary or not saga.get("completed") is Array: return rejected
		if saga.battles.size() != saga.battle_encounters.size(): return rejected
		var seen: Dictionary = {}
		# battles的持久顺序是胜利顺序；completed可能含暂缓/绕路，不能拿它回填未来战果。
		for scene_id in saga.battles:
			if not scene_id is String or seen.has(scene_id) or not saga.battle_encounters.get(scene_id) is String: return rejected
			seen[scene_id] = true
			var source := _encounter_source(saga.battle_encounters[scene_id], catalog)
			if source.is_empty() or source.scene_id != scene_id or source.chapter < 2: return rejected
			sources.append(source)
	var applied: Array = saved.applied_battle_ids
	if applied.size() != sources.size() or saved.battle_counter != applied.size() + (0 if saved.pending_battle.is_empty() else 1): return rejected
	for index in applied.size():
		if not applied[index] is String or applied[index] != saved.run_id + ":" + str(index + 1): return rejected
		sources[index]["battle_id"] = applied[index]
	if not saved.pending_battle.is_empty():
		var pending: Dictionary = saved.pending_battle
		if pending.get("battle_id") != saved.run_id + ":" + str(applied.size() + 1) or not pending.get("encounter_id") is String: return rejected
		if _encounter_source(pending.encounter_id, catalog).is_empty(): return rejected
	return {"ok": true, "sources": sources}

static func _encounter_source(encounter_id: String, catalog: RefCounted) -> Dictionary:
	var encounter: Dictionary = catalog.get_definition("encounters", encounter_id)
	if encounter.is_empty() or not encounter.get("enemy_ids") is Array or encounter.enemy_ids.is_empty(): return {}
	var chapter := 1
	var scene_id := ""
	if encounter_id in ["campaign_night_1", "campaign_night_2", "campaign_night_3", "campaign_night_4", "campaign_night_5"]:
		scene_id = "night_" + encounter_id.trim_prefix("campaign_night_")
	elif encounter_id.begins_with("saga_") and encounter.get("story_scene") is String:
		scene_id = encounter.story_scene
		if scene_id.length() < 5 or not scene_id.begins_with("C") or scene_id[2] != "-": return {}
		chapter = scene_id.substr(1, 1).to_int()
		if chapter < 2 or chapter > 7: return {}
	else: return {}
	for enemy_id in encounter.enemy_ids:
		if not enemy_id is String or not _enemy_entries.has(enemy_id) or catalog.get_definition("enemies", enemy_id).is_empty(): return {}
	return {"encounter_id": encounter_id, "encounter_name": str(encounter.get("name", encounter_id)), "scene_id": scene_id, "chapter": chapter, "enemy_ids": encounter.enemy_ids.duplicate()}

static func _present(raw: Dictionary, saved: Dictionary, source: Dictionary, preview: bool) -> Dictionary:
	var result := raw.duplicate(true)
	result.links = []
	for link in raw.links:
		var unlocked := _link_unlocked(link.gate, saved)
		result.links.append({"scene_id": link.scene_id, "label": link.label if unlocked else "待完成的调查对照", "unlocked": unlocked, "text": link.text if unlocked else ""})
	result["encounter_id"] = source.get("encounter_id", "")
	result["encounter_name"] = source.get("encounter_name", "")
	result["scene_id"] = source.get("scene_id", "")
	result["battle_id"] = source.get("battle_id", "")
	result["chapter"] = source.get("chapter", 0)
	result["preview"] = preview
	if not source.is_empty():
		result.verified_scope = ("尚未取得，仅预览此战胜利后的首次收录。" if preview else "已由持久战斗%s确认%s胜利。" % [source.battle_id, source.encounter_id]) + raw.verified_scope
	return result

static func _link_unlocked(gate: Dictionary, saved: Dictionary) -> bool:
	if gate.has("completed"):
		var saga = saved.get("saga")
		return saga is Dictionary and saga.get("completed") is Array and saga.completed.has(gate.completed)
	var history = saved.get("world_history")
	if not history is Dictionary: return false
	var world = history.get("night_%d" % int(gate.get("night", 0)))
	return world is Dictionary and world.get("event_flags") is Dictionary and world.event_flags.get(gate.get("event", "")) == true

static func _data() -> Dictionary:
	if not _entries.is_empty(): return _entries
	if not FileAccess.file_exists(DATA_PATH): return {}
	var document: Variant = _integerize(JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)))
	if not document is Dictionary or document.get("schema_version") != 1 or document.get("catalog_version") != "enemy-recoveries-1" or not document.get("definitions") is Array or document.definitions.size() != 21: return {}
	var entries: Dictionary = {}
	var enemies: Dictionary = {}
	for row in document.definitions:
		if not row is Dictionary: return {}
		for key in ["id", "enemy_id", "name", "summary", "source", "provenance", "verified_scope"]:
			if not row.get(key) is String or row[key].is_empty(): return {}
		if row.id != "recovery_" + row.enemy_id or entries.has(row.id) or enemies.has(row.enemy_id): return {}
		if row.get("origin") != "new_design_2026_10_08" or row.get("quantity") != 1: return {}
		for key in ["tradable", "consumable", "mainline_key"]:
			if not row.get(key) is bool or row[key]: return {}
		if not row.get("links") is Array: return {}
		for link in row.links:
			if not link is Dictionary or not link.get("gate") is Dictionary: return {}
			for key in ["scene_id", "label", "text"]:
				if not link.get(key) is String or link[key].is_empty(): return {}
			var gate: Dictionary = link.gate
			if gate.has("completed"):
				if gate.size() != 1 or not gate.completed is String or gate.completed != link.scene_id: return {}
			else:
				if gate.size() != 2 or not gate.get("night") is int or gate.night < 1 or gate.night > 5 or not gate.get("event") is String or gate.event.is_empty() or link.scene_id != "night_%d" % gate.night: return {}
		entries[row.id] = row
		enemies[row.enemy_id] = row.id
	_entries = entries
	_enemy_entries = enemies
	return _entries

static func _integerize(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floor(value): return int(value)
	if value is Array:
		var result: Array = []
		for item in value: result.append(_integerize(item))
		return result
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = _integerize(value[key])
		return result
	return value
