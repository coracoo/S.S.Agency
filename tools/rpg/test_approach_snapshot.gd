extends RefCounted
const F = preload("res://tools/rpg/fixtures.gd")
const A = preload("res://tools/rpg/approach_fixtures.gd")
const Store = preload("res://scripts/rpg/save_store.gd")
const Campaign = preload("res://scripts/rpg/campaign.gd")
static func run() -> Array[String]:
	var failures: Array[String] = []
	var path := "res://scripts/exploration_3d/world_snapshot.gd"
	F.expect(FileAccess.file_exists(path), "缺少 3D 世界接口", failures)
	if not failures.is_empty(): return failures
	var W = load(path)
	var world := A.world()
	F.expect(W.validate(world).is_empty(), "3D 世界合法", failures)
	F.expect(W.validate(W.initial({})).is_empty(), "初始世界合法", failures)
	var store := Store.new()
	var transported: Dictionary = store.normalize(JSON.parse_string(JSON.stringify({"world": world})))
	F.expect(transported.world.position == world.position and transported.world.world_version is int, "xyz 往返及整数规范化", failures)
	for field in ["world_version", "space", "scene_id", "scene_path", "position", "player_x", "facing", "camera", "event_flags", "return_anchor", "resolved", "dlg_fired", "spirit", "party_index", "exit_prompted"]:
		var bad := world.duplicate(true)
		bad.erase(field)
		F.expect(not W.validate(bad).is_empty(), "缺失字段拒绝：" + field, failures)
	var changes := [{"world_version": 3}, {"world_version": 2.1}, {"space": "2d"}, {"scene_id": "other"}, {"scene_path": "res://scenes/v3/stage.tscn"}, {"position": [NAN, 0, 0]}, {"position": [0, INF, 0]}, {"position": [1, 2]}, {"position": ["1", 2, 3]}, {"player_x": 99}, {"facing": 0}, {"return_anchor": "unknown"}, {"event_flags": {"cheat": true}}, {"event_flags": {"approach_entered": false}}, {"event_flags": {"basin_cleared": true}}, {"dlg_fired": {"unknown": true}}, {"resolved": {"basin_reflection": true}}, {"camera": {"mode": "free", "target": [0, 0, 0], "size": 8}}, {"camera": {"mode": "follow", "target": [0, 0, 0], "size": -1}}, {"camera": {"mode": "follow", "target": [0, INF, 0], "size": 8}}, {"spirit": 3}, {"party_index": 1}]
	for change in changes:
		var bad := world.duplicate(true)
		bad.merge(change, true)
		F.expect(not W.validate(W.normalize(bad)).is_empty(), "拒绝非法世界：" + str(change), failures)
	var old := {"scene_path": "res://scenes/v3/stage.tscn", "player_x": 900, "facing": 1, "spirit": 2, "party_index": 0, "exit_prompted": false, "resolved": {}, "dlg_fired": {}}
	F.expect(Store.validate_world(old).is_empty() and not store.normalize({"world": old}).world.has("world_version"), "旧世界不迁移", failures)
	world.event_flags = {"approach_entered": true, "basin_observed": true, "basin_inspected": true}
	world.dlg_fired = {"a1": true, "h1": true}
	var patch := {"patch_version": 2, "encounter_id": "approach_basin", "event_flags": {"basin_cleared": true}, "resolved": {"basin_reflection": true}}
	F.expect(W.validate_patch(patch, world).is_empty(), "登记战果补丁合法", failures)
	for change in [{"patch_version": 3}, {"encounter_id": "slice_1"}, {"event_flags": {"approach_complete": true}}, {"resolved": {"other": true}}, {"next_scene": "res://scenes/v3/stage.tscn"}]:
		var bad := patch.duplicate(true)
		bad.merge(change, true)
		F.expect(not W.validate_patch(bad, world).is_empty(), "拒绝未登记补丁", failures)
	F.expect(not Store.validate_story_patch({"resolved": {"basin_reflection": true}}, world).is_empty(), "3D 世界不能用旧补丁绕过", failures)
	var save_path := "user://rpg_v1/tests/approach_snapshot.json"
	var campaign := Campaign.new(null, store, save_path)
	var classes: Array[String] = ["swordsman", "ranger", "guard"]
	F.expect(campaign.new_run(classes).ok, "建立安全夹具", failures)
	var safe := campaign.safe_snapshot()
	safe.world = world
	F.expect(store.write_safe(safe, save_path) == OK, "保存 3D 世界", failures)
	var before := FileAccess.get_file_as_string(save_path)
	for fault in [A.RenameFailStore.new(), A.CorruptWriteStore.new()]:
		F.expect(fault.write_safe(safe, save_path) != OK and FileAccess.get_file_as_string(save_path) == before, "写失败保留原字节", failures)
	F.expect(store.load_safe(save_path).snapshot.world == world, "完整快照往返", failures)
	var pending: Dictionary = store.normalize({"pending_battle": {"story_patch": {"patch_version": 2.0}}})
	F.expect(pending.pending_battle.story_patch.patch_version is int, "补丁整值规范化", failures)
	pending = store.normalize({"pending_battle": {"story_patch": {"patch_version": 2.1}}})
	F.expect(pending.pending_battle.story_patch.patch_version == 2.1, "补丁小数不能截断伪装版本", failures)
	var future_path := "user://rpg_v1/tests/approach_future.json"
	var future := safe.duplicate(true)
	future.world.world_version = 99
	var future_bytes := JSON.stringify(future)
	var file := FileAccess.open(future_path, FileAccess.WRITE)
	file.store_string(future_bytes)
	file.close()
	F.expect(not store.load_safe(future_path).ok and store.write_safe(safe, future_path) != OK and FileAccess.get_file_as_string(future_path) == future_bytes, "未来世界版本保留原字节", failures)
	return failures
