# 参道夹具只用于隔离 runner。
extends RefCounted
const Store = preload("res://scripts/rpg/save_store.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
class RenameFailStore extends Store:
	func _replace_file(_temporary: String, _destination: String) -> Error:
		return ERR_FILE_CANT_WRITE
class CorruptWriteStore extends Store:
	func _write_temporary(path: String, _contents: String) -> Error:
		return super._write_temporary(path, "{broken")
class FailingStore extends Store:
	var fail := false
	func write_safe(value: Dictionary, path: String = Store.DEFAULT_PATH) -> Error:
		return ERR_FILE_CANT_WRITE if fail else super.write_safe(value, path)
static func world() -> Dictionary:
	return {"world_version": 2, "space": "3d", "scene_id": "approach_3d", "scene_path": "res://scenes/exploration_3d/approach.tscn", "position": [-4.3, 0.0, 1.6], "player_x": -4.3, "facing": 1, "camera": {"mode": "follow", "target": [-4.3, 1.1, 1.6], "size": 8.0}, "return_anchor": "spawn", "event_flags": {}, "resolved": {}, "dlg_fired": {}, "spirit": 2, "party_index": 0, "exit_prompted": false}
static func catalog() -> RefCounted:
	var result := Catalog.new()
	result.load_all()
	return result
