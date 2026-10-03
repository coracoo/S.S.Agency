# 参道世界的纯数据契约；不加载场景或迁移旧二维坐标。
class_name ApproachWorldSnapshot
extends RefCounted
const State = preload("res://scripts/rpg/battle_state.gd")
const SCENE_PATH := "res://scenes/exploration_3d/approach.tscn"
const FLAGS := ["approach_entered", "basin_observed", "basin_inspected", "basin_cleared", "approach_complete"]
const ANCHORS := ["spawn", "basin_safe", "upper_exit"]
static func initial(config: Dictionary) -> Dictionary:
	var position: Array = config.get("anchors", {}).get("spawn", [-4.3, 0.0, 1.6]).duplicate()
	return {"world_version": 2, "space": "3d", "scene_id": "approach_3d", "scene_path": SCENE_PATH, "position": position, "player_x": position[0], "facing": 1, "camera": {"mode": "follow", "target": [position[0], position[1] + 1.1, position[2]], "size": 8.0}, "return_anchor": "spawn", "event_flags": {}, "resolved": {}, "dlg_fired": {}, "spirit": 2, "party_index": 0, "exit_prompted": false}
static func normalize(world: Dictionary) -> Dictionary:
	var value := world.duplicate(true)
	State._int_fields(value, ["world_version", "facing", "spirit", "party_index"])
	return value
static func validate(world: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not State._plain(world): return ["3D 世界只允许有限 JSON 值"]
	if not world.get("world_version") is int or world.get("world_version") != 2: errors.append("未知 world_version，原档保持不变")
	if world.get("space") != "3d" or world.get("scene_id") != "approach_3d" or world.get("scene_path") != SCENE_PATH: errors.append("3D 世界场景归属非法")
	if not _vector(world.get("position")): errors.append("位置必须是三个有限数值")
	elif not _number(world.get("player_x")) or world.player_x != world.position[0]: errors.append("player_x 必须等于 position.x")
	if not world.get("facing") is int or not world.get("facing") in [-1, 1]: errors.append("朝向必须为 -1 或 1")
	if not ANCHORS.has(world.get("return_anchor")): errors.append("未知安全锚点")
	if not world.get("spirit") is int or world.get("spirit") != 2 or not world.get("party_index") is int or world.get("party_index") != 0: errors.append("试玩兼容计数非法")
	if not world.get("exit_prompted") is bool: errors.append("出口提示必须为布尔值")
	var camera = world.get("camera")
	if not camera is Dictionary:
		errors.append("缺少镜头快照")
	elif camera.get("mode") != "follow" or not _vector(camera.get("target")) or not _number(camera.get("size")) or camera.get("size", 0) <= 0:
		errors.append("镜头模式、目标或尺寸非法")
	if not _flags(world.get("event_flags"), FLAGS): errors.append("剧情标记不在白名单或不为 true")
	if not _flags(world.get("dlg_fired"), ["a1", "h1"]): errors.append("对白标记非法")
	if not _flags(world.get("resolved"), ["basin_reflection"]): errors.append("调查线索标记非法")
	if not errors.is_empty(): return errors
	var flags: Dictionary = world.event_flags
	for index in range(1, FLAGS.size()):
		if flags.has(FLAGS[index]) and not flags.has(FLAGS[index - 1]): errors.append("剧情标记缺少前置：" + FLAGS[index])
	if flags.has("approach_entered") != world.dlg_fired.has("a1") or flags.has("basin_observed") != world.dlg_fired.has("h1"): errors.append("对白完成标记不一致")
	if flags.has("basin_cleared") != world.resolved.has("basin_reflection"): errors.append("胜利与线索状态不一致")
	return errors
static func validate_patch(patch: Dictionary, world: Dictionary) -> Array[String]:
	if not validate(world).is_empty(): return ["剧情补丁缺少合法 3D 世界"]
	if not State._plain(patch) or patch.size() != 4: return ["参道补丁字段不符"]
	if not patch.get("patch_version") is int or patch.get("patch_version") != 2 or patch.get("encounter_id") != "approach_basin": return ["参道补丁版本或遭遇不符"]
	if patch.get("event_flags") != {"basin_cleared": true} or patch.get("resolved") != {"basin_reflection": true}: return ["参道补丁仅允许本场胜利标记"]
	if not world.event_flags.has("basin_inspected") or world.event_flags.has("basin_cleared"): return ["参道补丁前置不符"]
	return []
static func same_story(left: Dictionary, right: Dictionary) -> bool:
	for field in ["world_version", "space", "scene_id", "scene_path", "event_flags", "resolved", "dlg_fired", "spirit", "party_index"]:
		if left.get(field) != right.get(field): return false
	return true
static func _number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))
static func _vector(value) -> bool:
	return value is Array and value.size() == 3 and _number(value[0]) and _number(value[1]) and _number(value[2])
static func _flags(value, allowed: Array) -> bool:
	if not value is Dictionary: return false
	for key in value:
		if not allowed.has(key) or not value[key] is bool or value[key] != true: return false
	return true
