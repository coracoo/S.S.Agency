# The formal chapter registry is the only authority for 3D story and battle routes.
class_name CampaignChapterCatalog
extends RefCounted
const Saga = preload("res://scripts/campaign/saga_catalog.gd")
const State = preload("res://scripts/rpg/battle_state.gd")
const Layout = preload("res://scripts/campaign/act_one_layout.gd")
const SAVE_PATH := "user://campaign_v1/slot_01.json"
const PROFILE_ID := "five_night_3d_v1"
const DEFAULT_CLASSES: Array[String] = ["swordsman", "ranger", "guard"]
const BINDINGS := {"p_swordsman": {"identity_id": "rinne", "form_id": "rinne"}, "p_ranger": {"identity_id": "mint", "form_id": "mint"}, "p_guard": {"identity_id": "guard", "form_id": "guard"}, "p_mage": {"identity_id": "homura", "form_id": "sword"}, "p_healer": {"identity_id": "healer", "form_id": "healer"}, "p_controller": {"identity_id": "controller", "form_id": "controller"}}
const ENDING_PATH := "res://scenes/campaign/ending.tscn"
const CASE_PATH := "res://data/cases/night_patrol.json"
const CASE_ROOT := "t1"

static func scene_path(id: int) -> String:
	if id >= 6 and id <= 11: return Saga.SCENE_PATH
	return "res://scenes/campaign/night_%d.tscn" % id if id >= 1 and id <= 5 else ""

static func _interaction(id: String, label: String, x: float, kind: String, dialogue: String = "", clue: String = "", requires: Array = []) -> Dictionary:
	return {"id": id, "label": label, "position": [x, 0.0, 0.0], "kind": kind, "dialogue": dialogue, "clue_id": clue, "requires": requires.duplicate()}

# 旧局部登记不可放宽，用于旧档迁移校验及原建筑分块构建。
static func legacy_night(id: int) -> Dictionary:
	if id < 1 or id > 5: return {}
	var titles := ["第一夜 · 参道", "第二夜 · 回廊守灯", "第三夜 · 抬棺队列", "第四夜 · 棺中镜", "第五夜 · 本殿"]
	var stages := ["test_approach", "corridor_act", "night3_procession", "night4_mirror", "honden_act"]
	var clues := ["basin_reflection", "bell_self_ring", "coffin_procession", "mirror_in_coffin", "hollow_coffin_glow"]
	var intros := ["a1", "c1", "p1", "m1", "hd1"]
	var interactions: Array[Dictionary] = []
	var required: Array[String] = ["dialogue:" + intros[id - 1], "battle:cleared"]
	match id:
		1:
			interactions = [_interaction("family", "祖母与顾家的旧缘", -2.7, "dialogue", "r1", "", ["dialogue:a1"]), _interaction("basin", "察看水钵倒影", -0.4, "dialogue", "h1", "", ["dialogue:a1"]), _interaction("battle", "确认水钵异象", 1.0, "battle", "", clues[0], ["dialogue:h1"])]
			required.append_array(["dialogue:r1", "dialogue:h1"])
		2:
			interactions = [_interaction("battle", "调查无风钟鸣", -2.5, "battle", "", clues[1], ["dialogue:c1"]), _interaction("ritual:identify", "辨认来者 · 送行残文", -0.6, "ritual", "", "coffin_sendoff", ["dialogue:c1"]), _interaction("ritual:place", "安放旧物", 1.0, "ritual", "", "coffin_sendoff", ["ritual:identify"]), _interaction("ritual:guide", "执灯引路", 2.5, "ritual", "", "coffin_sendoff", ["ritual:place"])]
			required.append_array(["ritual:identify", "ritual:place", "ritual:guide"])
		3:
			interactions = [_interaction("procession", "察看抬棺队列", -0.5, "dialogue", "p3", "", ["dialogue:p1"]), _interaction("battle", "调查夜行纸棺", 1.5, "battle", "", clues[2], ["dialogue:p1", "dialogue:p3"])]
			required.append("dialogue:p3")
		4:
			interactions = [_interaction("mirror", "铜镜、纸棺与小夜", -0.6, "dialogue", "m1"), _interaction("battle", "调查棺中铜镜", 1.7, "battle", "", clues[3], ["dialogue:m1"])]
		5:
			interactions = [_interaction("battle", "确认空棺中的光", -0.5, "battle", "", clues[4], ["dialogue:hd1"]), _interaction("gatekeeper_return", "棺守让开与拜托", 1.8, "dialogue", "hd5", "", ["battle:cleared"])]
			required.append("dialogue:hd5")
	interactions.append(_interaction("exit", "进入下一夜" if id < 5 else "五夜查明 · 结案", 4.5, "exit", "", "", required))
	var definition := {"night": id, "id": "night_%d" % id, "title": titles[id - 1], "scene_path": scene_path(id), "dialogue_stage": stages[id - 1], "encounter_id": "campaign_night_%d" % id, "clue_id": clues[id - 1], "intro": intros[id - 1], "anchors": {"spawn": [-4.7, 0.0, 1.0], "battle_return": [-1.2, 0.0, 1.0], "exit": [4.5, 0.0, 0.0]}, "bounds": {"x": [-5.7, 5.7], "z": [-2.8, 2.8]}, "required_events": required, "interactions": interactions, "dialogue_stops": {"hd1": "hd4"} if id == 5 else {}}

	if id == 1:
		definition.bounds = {"x": [-9.05, 9.6], "z": [-1.85, 2.12], "y": [-0.5, 3.4]}
		definition.anchors = {"spawn": [-4.3, 0.04, 1.6], "battle_return": [-1.2, 0.04, 0.55], "exit": [8.65, 2.9, 0.35]}
		definition.interactions[0].position = [-4.3, 0.04, 0.7]
		definition.interactions[1].position = [0.12, 0.714, 1.94]
		definition.interactions[2].position = [0.12, 0.714, 1.94]
		definition.interactions[-1].position = definition.anchors.exit.duplicate()
	definition["clue_path"] = "res://data/clues/" + definition.dialogue_stage + ".json"
	for interaction in definition.interactions:
		interaction["clue_path"] = definition.clue_path if not interaction.clue_id.is_empty() else ""
	return definition

static func night(id: int) -> Dictionary:
	if id >= 6: return Saga.definition(id)
	var definition := legacy_night(id)
	if definition.is_empty(): return {}
	definition["map_layout"] = Layout.ID
	definition.bounds = Layout.bounds()
	for anchor in definition.anchors:
		definition.anchors[anchor] = Layout.to_world(definition.anchors[anchor], id)
	for interaction in definition.interactions:
		interaction.position = Layout.to_world(interaction.position, id)
	return definition

static func initial_world(id: int) -> Dictionary:
	if id >= 6: return Saga.initial_world(id - 4) if id <= 11 else {}
	var definition := night(id)
	if definition.is_empty(): return {}
	return {"world_version": 3, "map_layout": Layout.ID, "space": "3d", "night": id, "scene_id": definition.id, "scene_path": definition.scene_path, "position": definition.anchors.spawn.duplicate(), "facing": 1, "return_anchor": "spawn", "event_flags": {}, "resolved": {}, "dlg_fired": {}, "player_x": definition.anchors.spawn[0], "spirit": 2, "party_index": 0, "exit_prompted": false}

static func events(id: int) -> Dictionary:
	var definition := night(id)
	if definition.is_empty(): return {}
	var result := {"dialogue:" + definition.intro: []}
	for interaction in definition.interactions:
		if interaction.kind == "dialogue": result["dialogue:" + interaction.dialogue] = interaction.requires.duplicate()
		elif interaction.kind == "ritual": result[interaction.id] = interaction.requires.duplicate()
	return result

static func battle_requirements(id: int) -> Array:
	for interaction in night(id).get("interactions", []):
		if interaction.kind == "battle": return interaction.requires.duplicate()
	return []

static func complete(world: Dictionary) -> bool:
	for event in night(int(world.get("night", 0))).get("required_events", []):
		if not world.get("event_flags", {}).has(event): return false
	return not night(int(world.get("night", 0))).is_empty()

static func same_story(left: Dictionary, right: Dictionary) -> bool:
	for field in ["world_version", "map_layout", "space", "night", "scene_id", "scene_path", "event_flags", "resolved", "dlg_fired", "story_scene", "story_choice", "story_encounter"]:
		if left.get(field) != right.get(field): return false
	return true

static func validate_world(world: Dictionary) -> Array[String]:
	if world.get("map_layout") is String and world.map_layout == Saga.LAYOUT_ID: return Saga.validate_world(world)
	return _validate_world(world, false)

static func _validate_world(world: Dictionary, legacy: bool) -> Array[String]:
	if not State._plain(world): return ["正式3D世界只允许有限JSON值"]
	var errors: Array[String] = []
	if legacy:
		if world.has("map_layout"): errors.append("旧局部世界不可携带布局标记")
	elif not world.get("map_layout") is String or world.map_layout != Layout.ID:
		errors.append("未知或缺少第一幕地图布局")
	if not world.get("world_version") is int or world.world_version != 3 or not world.get("space") is String or world.space != "3d": errors.append("正式世界版本/空间非法")
	if not world.get("night") is int: return ["夜晚必须为整数"]
	var definition := legacy_night(world.night) if legacy else night(world.night)
	if definition.is_empty(): return ["未登记夜晚"]
	if not world.get("scene_id") is String or not world.get("scene_path") is String or world.scene_id != definition.id or world.scene_path != definition.scene_path: errors.append("夜晚与场景不符")
	var position = world.get("position")
	if not position is Array or position.size() != 3:
		errors.append("位置必须为三个有限数值")
	else:
		for value in position:
			if not (value is int or value is float) or not is_finite(float(value)): errors.append("位置必须为三个有限数值")
		if errors.is_empty() and (position[0] < definition.bounds.x[0] or position[0] > definition.bounds.x[1] or position[2] < definition.bounds.z[0] or position[2] > definition.bounds.z[1] or position[1] < definition.bounds.get("y", [-0.5, 2.0])[0] or position[1] > definition.bounds.get("y", [-0.5, 2.0])[1]): errors.append("玩家位置越出安全舞台")
	if not world.get("facing") is int or not world.facing in [-1, 1]: errors.append("朝向非法")
	if not definition.anchors.has(world.get("return_anchor")): errors.append("未登记安全锚点")
	var allowed := events(world.night)
	allowed["battle:cleared"] = battle_requirements(world.night)
	if not _flags(world.get("event_flags"), allowed.keys()): errors.append("正式剧情标记非法")
	var roots: Array = []
	for event in events(world.night):
		if event.begins_with("dialogue:"): roots.append(event.trim_prefix("dialogue:"))
	if not _flags(world.get("dlg_fired"), roots): errors.append("正式对白完成标记非法")
	var clues: Array = [definition.clue_id]
	if world.night == 2: clues.append("coffin_sendoff")
	if not _flags(world.get("resolved"), clues): errors.append("正式调查完成标记非法")
	if not errors.is_empty(): return errors
	for event in world.event_flags:
		for required in allowed[event]:
			if not world.event_flags.has(required): errors.append("事件缺少前置：" + event)
	for root in roots:
		if world.dlg_fired.has(root) != world.event_flags.has("dialogue:" + root): errors.append("对白和事件完成不一致")
	if world.resolved.has(definition.clue_id) != world.event_flags.has("battle:cleared"): errors.append("调查线索与本夜胜利不一致")
	if world.night == 2 and world.resolved.has("coffin_sendoff") != world.event_flags.has("ritual:guide"): errors.append("送行线索与引路步骤不一致")
	return errors

static func _flags(value, allowed: Array) -> bool:
	if not value is Dictionary: return false
	for key in value:
		if not key is String or not allowed.has(key) or not value[key] is bool or value[key] != true: return false
	return true

static func normalize(world: Dictionary) -> Dictionary:
	var result := world.duplicate(true)
	State._int_fields(result, ["world_version", "night", "facing", "spirit", "party_index"])
	# 无标志的v3只在完整旧世界合法时迁移，未知布局永不猜测或重标。
	# 正式存档world/history及pending快照均经此入口；normalize重复调用不会偏移两次。
	if not result.has("map_layout") and _validate_world(result, true).is_empty():
		result.position = Layout.to_world(result.position, result.night)
		result["player_x"] = result.position[0]
		result["map_layout"] = Layout.ID
	return result

static func battle_patch(world: Dictionary) -> Dictionary:
	if world.get("map_layout") is String and world.map_layout == Saga.LAYOUT_ID: return Saga.battle_patch(world)
	var definition := night(int(world.get("night", 0)))
	return {"patch_version": 3, "encounter_id": definition.get("encounter_id", ""), "event_flags": {"battle:cleared": true}, "resolved": {definition.get("clue_id", ""): true}}

static func validate_patch(patch: Dictionary, world: Dictionary) -> Array[String]:
	if world.get("map_layout") is String and world.map_layout == Saga.LAYOUT_ID: return Saga.validate_patch(patch, world)
	if not validate_world(world).is_empty(): return ["战果补丁缺少合法正式世界"]
	if patch != battle_patch(world): return ["正式战果补丁必须匹配登记的本夜遭遇"]
	if world.event_flags.has("battle:cleared"): return ["本夜战斗已完成"]
	for event in battle_requirements(world.night):
		if not world.event_flags.has(event): return ["本夜战斗缺少前置事件"]
	return []

# Text is read from the approved clue export; no duplicate story source is authored.
static func clue(id: int, clue_id: String) -> Dictionary:
	var definition := night(id)
	if definition.is_empty() or clue_id.is_empty(): return {}
	var source = JSON.parse_string(FileAccess.get_file_as_string(definition.clue_path))
	if not source is Dictionary or not source.get("clues") is Array: return {}
	for entry in source.clues:
		if entry is Dictionary and entry.get("id") == clue_id: return entry.duplicate(true)
	return {}
