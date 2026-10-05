# 云端人工按键验收夹具：真实新游戏/输入/对白，F12只保存实拍，不改游戏状态。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
var stage: Node3D
var session: RefCounted
var output := ""
var _shot_armed := true
var _shot_count := 0
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or OS.get_environment("ACT_ONE_OUTPUT").is_empty(): quit(2); return
	output = OS.get_environment("ACT_ONE_OUTPUT")
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1280,720)
	session = Session.new()
	if not session.start_new(true).ok or not (await session.prepare_assets()).ok: quit(1); return
	stage = load(Catalog.scene_path(1)).instantiate()
	root.add_child(stage)
	process_frame.connect(_frame)
func _frame() -> void:
	if not Input.is_key_pressed(KEY_F12): _shot_armed = true
	if not _shot_armed or not Input.is_key_pressed(KEY_F12) or not is_instance_valid(stage) or not stage.ready_for_play: return
	_shot_armed = false
	_shot_count += 1
	_capture.call_deferred()
func _capture() -> void:
	await RenderingServer.frame_post_draw
	var filename := output.path_join("manual_%02d.png" % _shot_count)
	root.get_texture().get_image().save_png(filename)
	var file := FileAccess.open(output.path_join("manual_%02d.json" % _shot_count),FileAccess.WRITE)
	file.store_string(JSON.stringify({"mode":stage._mode,"controls_enabled":stage.controls_enabled,"world":stage.export_world(),"camera":stage.camera_rig.snapshot(),"hd2d":stage.hd2d_experiment},"\t"));file.close()
	print("MANUAL_SCREENSHOT:",filename)
