# 包外/源码均用全新Godot进程续读已验证的完整检查点，绝不写真实玩家目录。
extends SceneTree
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
const Saga = preload("res://scripts/campaign/saga_catalog.gd")
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Store = preload("res://scripts/rpg/save_store.gd")
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	var source := OS.get_environment("SAGA_RESUME_SNAPSHOT")
	var decoded = JSON.parse_string(FileAccess.get_file_as_string(source))
	if not decoded is Dictionary: printerr("FAIL: checkpoint JSON missing"); quit(1); return
	var store := Store.new()
	var snapshot := store.normalize(decoded)
	if store.write_safe(snapshot, Chapters.SAVE_PATH) != OK:
		printerr("FAIL: checkpoint invalid: ", store.last_error); quit(1); return
	var session := Session.new()
	var resumed: Dictionary = session.resume()
	if not resumed.ok or session.campaign.safe_snapshot() != snapshot:
		printerr("FAIL: process resume differs: ", resumed); quit(1); return
	var expected: String = "res://scenes/rpg/battle.tscn" if not snapshot.pending_battle.is_empty() else snapshot.return_scene
	if resumed.get("next_scene") != expected:
		printerr("FAIL: wrong process resume route"); quit(1); return
	if not snapshot.pending_battle.is_empty():
		var setup: Dictionary = session.campaign.retry_battle()
		if setup.seed != snapshot.pending_battle.seed or setup.battle_id != snapshot.pending_battle.battle_id:
			printerr("FAIL: process retry changed seed/ID"); quit(1); return
		for id in snapshot.party:
			if setup.setup.actors[id].hp != snapshot.roster[id].hp or setup.setup.actors[id].mp != snapshot.roster[id].mp:
				printerr("FAIL: process retry changed resources"); quit(1); return
	print("SAGA_PROCESS_RESUME: ", snapshot.get("saga", {}).get("chapter", 1), " active=", snapshot.get("saga", {}).get("active_scene", ""), " route=", expected)
	session.close()
	quit(0)
