# 可视检查专用：真实窗口截图与缩放，不自动选择指令、不修改战斗资源。
extends SceneTree
const Router = preload("res://scripts/rpg/encounter_router.gd")
var capture_dir := ""
var capture_index := 0
var small := false

class CaptureObserver extends Node:
	var harness: SceneTree
	var elapsed := 0.0
	var previous := ""
	func _process(delta: float) -> void:
		elapsed += delta
		if elapsed < 1.0: return
		elapsed = 0
		var scene := harness.current_scene
		if scene == null: return
		var signature: String = scene.scene_file_path + str(harness.root.size)
		if scene.get("engine") != null: signature += str(scene.engine.snapshot().revision) + str(scene.pending_command)
		elif scene.get("campaign") != null: signature += str(scene.campaign.snapshot())
		if signature != previous:
			previous = signature
			harness._capture()
	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_F12: harness._capture()
			if event.keycode == KEY_F11:
				harness.small = not harness.small
				harness.root.size = Vector2i(960, 720) if harness.small else Vector2i(1280, 720)

func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or DisplayServer.get_name() == "headless":
		printerr("FAIL: 截图必须在已验证隔离目录与真实窗口中运行")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()):
		if args[index] == "--capture-dir" and index + 1 < args.size(): capture_dir = args[index + 1]
	if capture_dir.is_empty() or not capture_dir.begins_with("/workspace/scratch/"):
		printerr("FAIL: 需要明确的scratch截图输出目录")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	for filename in DirAccess.get_files_at(capture_dir):
		if filename.begins_with("capture_") and filename.ends_with(".png"): capture_index = maxi(capture_index, filename.trim_prefix("capture_").trim_suffix(".png").to_int())
	call_deferred("_start")

func _start() -> void:
	var observer := CaptureObserver.new()
	observer.harness = self
	root.add_child(observer)
	root.size = Vector2i(1280, 720)
	root.position = Vector2i(40, 140)
	change_scene_to_file("res://scenes/rpg/launcher.tscn")

func _capture() -> void:
	await RenderingServer.frame_post_draw
	capture_index += 1
	var base := capture_dir.path_join("capture_%03d" % capture_index)
	var error := root.get_texture().get_image().save_png(base + ".png")
	var scene := current_scene
	var record := {"rpg_enabled": Router.enabled(), "scene": scene.scene_file_path, "viewport": [root.size.x, root.size.y], "save_root": OS.get_environment("RPG_TEST_ROOT")}
	if scene.get("engine") != null:
		record["battle"] = scene.engine.snapshot()
		record["selection"] = scene.pending_command.duplicate(true)
		record["preview"] = scene.current_preview()
	if scene.get("campaign") != null: record["campaign"] = scene.campaign.snapshot()
	if scene.has_method("open_roster"):
		record["roster_ui"] = {"selected_class_ids": scene.selected_class_ids.duplicate(), "draft_party": scene._draft_party.duplicate(), "detail_class": scene._detail_class, "preview_branch": scene._preview_branch, "visible": scene._roster_panel.visible, "branch_text": scene._hud.branch_preview.text, "party_apply_disabled": scene._hud.party_apply.disabled, "branch_apply_disabled": scene._hud.branch_apply.disabled}
	var file := FileAccess.open(base + ".json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(record, "\t", true, true))
	print("RPG_CAPTURE: ", base, " error=", error)
