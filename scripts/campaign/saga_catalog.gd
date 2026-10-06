# 后六章只读取批准剧情导出；状态规则与场景表现共用同一登记。
class_name CampaignSagaCatalog
extends RefCounted
const State = preload("res://scripts/rpg/battle_state.gd")
const DATA_PATH := "res://data/campaign/saga.json"
const SCENE_PATH := "res://scenes/campaign/saga.tscn"
const ENDING_PATH := "res://scenes/campaign/saga_ending.tscn"
const LAYOUT_ID := "saga_regions_v1"
const SHOP := {"healing_potion": 18, "mana_potion": 22, "revival_potion": 45}
static var _document: Dictionary = {}
static var _scenes: Dictionary = {}
static var _chapters: Dictionary = {}

static func data() -> Dictionary:
	if _document.is_empty() and FileAccess.file_exists(DATA_PATH):
		var value = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if value is Dictionary and value.get("schema_version") == 1:
			_document = value
			for definition in _document.get("chapters", []):
				var metadata: Dictionary = definition.duplicate()
				metadata.erase("scenes")
				_chapters[int(definition.id)] = metadata
				for entry in definition.get("scenes", []): _scenes[str(entry.id)] = entry
	return _document

static func chapter(id: int) -> Dictionary:
	for definition in data().get("chapters", []):
		if int(definition.id) == id: return definition.duplicate(true)
	return {}

static func metadata(id: int) -> Dictionary:
	data()
	return _chapters.get(id, {}).duplicate(true)

static func scene(id: String) -> Dictionary:
	data()
	return _scenes.get(id, {}).duplicate(true)

static func chapter_for(id: String) -> int:
	return int(id.substr(1, 1)) if id.length() > 2 and id.begins_with("C") else 0

static func initial(resolution: String) -> Dictionary:
	var flags: Dictionary = data().get("flags", {}).duplicate(true)
	flags["resolution"] = resolution
	flags["first_chapter_sendoff"] = resolution == "sendoff"
	return {"version": 1, "chapter": 2, "max_chapter": 2, "scene": str(metadata(2).get("entry", "C2-01")), "active_scene": "", "completed": [], "choices": {}, "flags": flags, "battles": [], "battle_encounters": {}, "ending": "", "coins": 120, "transactions": [], "events": [], "retry": {}, "navigation": [], "cursors": {"2": str(metadata(2).get("entry", "C2-01"))}}

static func context(saga: Dictionary) -> Dictionary:
	var flags: Dictionary = saga.get("flags", {}).duplicate(true)
	if not saga.get("retry", {}).is_empty():
		flags["battle_retry_pending"] = true
		flags["retry_stage"] = int(saga.retry.get("stage", 0))
	for id in saga.get("completed", []): flags["done:" + str(id)] = true
	for id in saga.get("battles", []): flags["battle:" + str(id)] = true
	for id in saga.get("choices", {}): flags["choice:" + str(id)] = saga.choices[id]
	return flags

static func matches(requirements: Dictionary, flags: Dictionary) -> bool:
	for key in requirements:
		var actual: Variant = flags.get(key, false)
		var expected: Variant = requirements[key]
		if typeof(actual) != typeof(expected) and not ((actual is int or actual is float) and (expected is int or expected is float)): return false
		if actual != expected: return false
	return true

static func visible_lines(lines: Array, saga: Dictionary) -> Array:
	var result: Array = []
	var flags := context(saga)
	for line in lines:
		if line is Dictionary and matches(line.get("when", {}), flags): result.append(line.duplicate(true))
	return result

static func choice(id: String, choice_id: String) -> Dictionary:
	for option in scene(id).get("choices", []):
		if str(option.id) == choice_id: return option.duplicate(true)
	return {}

static func encounter(id: String, selected_choice: String = "") -> String:
	var entry := scene(id)
	var option := choice(id, selected_choice)
	return str(option.get("encounter_id", entry.get("encounter_id", "")))

static func encounter_for_saga(saga: Dictionary, id: String) -> String:
	var entry := scene(id)
	var option := choice(id, str(saga.get("choices", {}).get(id, "")))
	var source := option if option.has("encounter_id") else entry
	if not matches(source.get("encounter_requires", {}), context(saga)): return ""
	return encounter(id, str(saga.get("choices", {}).get(id, "")))

static func eligible_choices(entry: Dictionary, saga: Dictionary) -> Array:
	return entry.get("choices", []).filter(func(option): return matches(option.get("requires", {}), context(saga)))

# 场次可能先选择不战、日后回访再战；不能只看曾经completed就吞掉本次战后正文。
static func awaiting_aftermath(saga: Dictionary, id: String) -> bool:
	if not saga.get("battles", []).has(id): return false
	var actual: String = str(saga.get("battle_encounters", {}).get(id, ""))
	for event in saga.get("events", []):
		if event.get("id") == id and not actual.is_empty() and encounter(id, str(event.get("choice", ""))) == actual: return false
	return true

static func next_scene(entry: Dictionary, saga: Dictionary, option: Dictionary = {}) -> String:
	var source := option if option.has("next") or option.has("next_routes") else entry
	for route in source.get("next_routes", []):
		if matches(route.get("requires", {}), context(saga)): return str(route.get("next", ""))
	return str(source.get("next", entry.get("next", "")))

static func apply_effects(saga: Dictionary, entry: Dictionary, option: Dictionary = {}) -> void:
	for source in [entry, option]:
		for branch in source.get("conditional_effects", []):
			if matches(branch.get("requires", {}), context(saga)):
				saga.flags.merge(branch.get("effects", {}), true)
		saga.flags.merge(source.get("effects", {}), true)
	if entry.has("ending_id"): saga.ending = str(entry.ending_id)
	if option.has("ending_id"): saga.ending = str(option.ending_id)
	if saga.flags.get("ending") is String: saga.ending = saga.flags.ending

static func available(saga: Dictionary, id: String) -> bool:
	var entry := scene(id)
	if entry.is_empty() or chapter_for(id) != int(saga.chapter): return false
	if not matches(entry.get("requires", {}), context(saga)): return false
	if str(entry.get("kind", "main")) in ["main", "ending"]:
		return id == str(saga.get("scene", "")) and (not saga.completed.has(id) or str(entry.get("encounter_id", "")).is_empty())
	return not saga.completed.has(id) or str(entry.get("kind", "")) == "revisit" or bool(entry.get("repeatable", false))

static func chapter_complete(saga: Dictionary, id: int) -> bool:
	var definition := metadata(id)
	if definition.is_empty(): return false
	for required in definition.get("required_scenes", []):
		if not saga.completed.has(required): return false
	var final_id := str(definition.get("exit", ""))
	return not final_id.is_empty() and saga.completed.has(final_id)

static func bounds(id: int) -> Dictionary:
	var resource = load("res://scripts/campaign/saga_world.gd")
	return resource.bounds(id) if resource != null else {"x": [-24.0, 24.0], "z": [-18.0, 18.0], "y": [-1.0, 8.0]}

static func anchors(id: int) -> Dictionary:
	var resource = load("res://scripts/campaign/saga_world.gd")
	return resource.anchors(id) if resource != null else {"spawn": [0.0, 0.04, 0.0]}

static func initial_world(id: int) -> Dictionary:
	var spawn: Array = anchors(id).get("spawn", [0.0, 0.04, 0.0])
	return {"world_version": 3, "map_layout": LAYOUT_ID, "space": "3d", "night": id + 4, "scene_id": "night_%d" % (id + 4), "scene_path": SCENE_PATH, "position": spawn.duplicate(), "facing": 1, "return_anchor": "spawn", "event_flags": {}, "resolved": {}, "dlg_fired": {}, "player_x": spawn[0], "spirit": 2, "party_index": 0, "exit_prompted": false, "story_scene": "", "story_choice": "", "story_encounter": ""}

static func definition(night: int) -> Dictionary:
	var id := night - 4
	var entry := metadata(id)
	if entry.is_empty(): return {}
	return {"night": night, "id": "night_%d" % night, "title": "第%s章 · %s" % [["二", "三", "四", "五", "六", "七"][id - 2], entry.title], "scene_path": SCENE_PATH, "map_layout": LAYOUT_ID, "bounds": bounds(id), "anchors": anchors(id), "encounter_id": "", "clue_id": "", "intro": entry.entry, "required_events": [], "interactions": []}

static func validate_world(world: Dictionary) -> Array[String]:
	if not State._plain(world): return ["后续世界仅允许有限JSON值"]
	if not world.get("night") is int or world.night < 6 or world.night > 11: return ["后续章节编号非法"]
	var id: int = world.night - 4
	if metadata(id).is_empty(): return ["后续章节未登记"]
	if not world.get("map_layout") is String or not world.get("world_version") is int or not world.get("space") is String: return ["后续世界版本/地图格式非法"]
	if world.map_layout != LAYOUT_ID or world.world_version != 3 or world.space != "3d": return ["后续世界版本/地图非法"]
	if not world.get("scene_id") is String or not world.get("scene_path") is String: return ["后续路由类型非法"]
	if world.scene_id != "night_%d" % world.night or world.scene_path != SCENE_PATH: return ["后续场景路由非法"]
	var position = world.get("position")
	if not position is Array or position.size() != 3: return ["后续位置缺少三维坐标"]
	for value in position:
		if not (value is int or value is float) or not is_finite(float(value)): return ["后续位置不是有限数值"]
	var limits := bounds(id)
	for index in range(3):
		var axis: String = ["x", "y", "z"][index]
		if position[index] < limits.get(axis, [-1.0, 8.0])[0] or position[index] > limits.get(axis, [-1.0, 8.0])[1]: return ["后续位置越界"]
	if not world.get("facing") is int or not world.facing in [-1, 1] or not anchors(id).has(world.get("return_anchor")): return ["后续朝向/安全锚点非法"]
	for field in ["event_flags", "resolved", "dlg_fired"]:
		if not world.get(field) is Dictionary: return ["后续世界缺少事件字典"]
		for key in world[field]:
			if not key is String or not world[field][key] is bool or world[field][key] != true: return ["后续世界事件格式非法"]
			var root_id: String = str(key).trim_prefix("battle:").trim_prefix("scene:")
			if scene(root_id).is_empty() or chapter_for(root_id) != id: return ["后续世界出现未登记场次"]
	for field in ["story_scene", "story_choice", "story_encounter"]:
		if not world.get(field) is String: return ["后续场次检查点格式非法"]
	if not world.story_scene.is_empty() and (scene(world.story_scene).is_empty() or chapter_for(world.story_scene) != id): return ["后续活动场次不属于本章"]
	if not world.story_choice.is_empty() and choice(world.story_scene, world.story_choice).is_empty(): return ["后续选择未登记"]
	return []

static func battle_patch(world: Dictionary) -> Dictionary:
	var id: String = str(world.get("story_scene", ""))
	return {"patch_version": 3, "encounter_id": str(world.get("story_encounter", "")), "event_flags": {"battle:" + id: true}, "resolved": {id: true}}

static func validate_patch(patch: Dictionary, world: Dictionary) -> Array[String]:
	if not validate_world(world).is_empty(): return ["后续战斗世界非法"]
	var expected := battle_patch(world)
	if expected.encounter_id.is_empty() or patch != expected: return ["后续战果须匹配活动场次与选择"]
	if world.event_flags.has("battle:" + world.story_scene): return ["本场战斗已完成"]
	return []

static func normalize(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	State._int_fields(result, ["version", "chapter", "max_chapter", "coins"])
	if result.get("retry") is Dictionary: State._int_fields(result.retry, ["stage"])
	for step in result.get("navigation", []):
		if step is Dictionary: State._int_fields(step, ["events", "destination"])
	for event in result.get("events", []):
		if event is Dictionary: State._int_fields(event, ["retry_stage"])
	for transaction in result.get("transactions", []):
		if transaction is Dictionary: State._int_fields(transaction, ["count", "cost"])
	return result
