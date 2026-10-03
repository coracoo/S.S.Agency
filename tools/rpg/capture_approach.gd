# 仅人工图形验收；全部存档与记录均由受保护 runner 建立。
extends SceneTree
class Recorder extends Node:
	var output := OS.get_environment("RPG_APPROACH_OUTPUT")
	var intervals: Array = []
	var previous := 0
	var inputs: Array = []
	var transitions: Array = []
	var last_scene := 0
	var recorded_final := false
	var compact_window := false
	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		if previous > 0: intervals.append({"ms": Time.get_ticks_msec(), "duration_ms": (now - previous) / 1000.0})
		previous = now
		var current := get_tree().current_scene
		if is_instance_valid(current) and current.get_instance_id() != last_scene:
			last_scene = current.get_instance_id()
			transitions.append({"ms": Time.get_ticks_msec(), "scene": current.scene_file_path})
			print("MANUAL_SCENE:", current.scene_file_path, " ", Time.get_ticks_msec())
	func _input(event: InputEvent) -> void:
		if event is InputEventKey:
			inputs.append({"ms": Time.get_ticks_msec(), "key": event.physical_keycode, "pressed": event.pressed, "echo": event.echo})
			if event.pressed and not event.echo:
				if event.keycode == KEY_F11:
					compact_window = not compact_window
					get_tree().root.size = Vector2i(960, 720) if compact_window else Vector2i(1280, 720)
				elif event.keycode == KEY_F12: capture.call_deferred()
				elif event.keycode == KEY_F10:
					record("final")
					recorded_final = true
					get_tree().quit()
		elif event is InputEventMouseButton:
			inputs.append({"ms": Time.get_ticks_msec(), "mouse": event.button_index, "pressed": event.pressed, "position": [event.position.x, event.position.y]})
	func capture() -> void:
		await RenderingServer.frame_post_draw
		var tag := str(Time.get_ticks_msec())
		get_viewport().get_texture().get_image().save_png(output.path_join(tag + ".png"))
		record(tag)
		print("MANUAL_CAPTURE:", tag)
	func record(tag: String) -> void:
		var size := DisplayServer.window_get_size()
		var result := {"inputs": inputs, "frame_intervals_ms": intervals, "transitions": transitions, "window_size": [size.x, size.y], "root_size": [get_tree().root.size.x, get_tree().root.size.y], "viewport_size": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]}
		var current := get_tree().current_scene
		if is_instance_valid(current):
			result["scene"] = current.scene_file_path
			if current.has_method("export_world"): result["world"] = current.export_world()
			if current.has_method("confirm_command") and current.engine != null:
				result["battle"] = current.engine.snapshot()
				result["processing"] = current.processing
		var session = load("res://scripts/exploration_3d/approach_session.gd").current
		if session != null: result["safe"] = session.campaign.safe_snapshot()
		var path := "user://rpg_v1/approach_3d_01.json"
		if FileAccess.file_exists(path):
			var durable: Dictionary = load("res://scripts/rpg/save_store.gd").new().load_safe(path)
			result["durable"] = durable.get("snapshot", {})
		var file := FileAccess.open(output.path_join(tag + ".json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "  "))
		file.close()
	func _exit_tree() -> void:
		if not recorded_final: record("final")
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or OS.get_environment("RPG_APPROACH_OUTPUT").is_empty():
		printerr("FAIL: 未通过隔离预检")
		quit(1)
		return
	call_deferred("launch")
func launch() -> void:
	var scene = load("res://scenes/v3/title.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	root.add_child(Recorder.new())
	print("MANUAL_READY: 全部操作由键鼠完成。F11切换窗口大小，F12截图/状态，F10结束。")
