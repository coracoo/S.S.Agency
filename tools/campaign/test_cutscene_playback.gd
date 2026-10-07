# 只通过隔离Python入口运行；自建色块视频不是正式美术。
extends SceneTree
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Clips = preload("res://scripts/campaign/cutscene_catalog.gd")
const Player = preload("res://scripts/campaign/cutscene_player.gd")
class StageHarness extends "res://scripts/campaign/chapter_stage.gd":
	var fixture_path := ""
	func _ready() -> void:
		_register_input()
		config = Catalog.night(1)
		_world = session.campaign.safe_snapshot().world.duplicate(true)
		ready_for_play = true
		_mode = "explore"
		set_controls_enabled(true)
	func _refresh_hud() -> void: pass
	func _refresh_world_objects(_animate: bool = false) -> void: pass
	func _dialogue_portrait(_speaker: String) -> Dictionary: return {"ok": true, "empty": true}
	func _cutscene_path(_file_name: String) -> String: return fixture_path
var failures: Array[String] = []
var assertions := 0
var fixture := ""
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); printerr("ASSERT FAIL: ", message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	fixture = OS.get_environment("CUTSCENE_TEST_FIXTURE")
	_run.call_deferred()
func _run() -> void:
	check(FileAccess.file_exists(fixture), "仓库外技术夹具已生成")
	print("CUTSCENE_ENGINE:", Engine.get_version_info().string)
	print("CUTSCENE_CLASSES:", ClassDB.get_inheriters_from_class("VideoStream"))
	print("CUTSCENE_EXTENSIONS:", ResourceLoader.get_recognized_extensions_for_type("VideoStream"))
	check(Clips.for_dialogue(1, "a1").is_empty() and Clips.for_dialogue(2, "h1").is_empty(), "标题开场与其他夜次不触发石钵片段")
	check(Clips.for_dialogue(1, "h1").continue_at == "h3", "片段仅替代现有h1/h2两句")
	await _player_checks()
	await _stage_checks()
	var before := FileAccess.get_file_as_string(Catalog.SAVE_PATH)
	var preview: Control = load("res://scenes/preview/night1_cutscene.tscn").instantiate()
	root.add_child(preview)
	await process_frame
	check(preview._label.text.contains("assets/cutscenes/night1_stone_bowl.ogv"), "F6预览缺片时显示精确路径")
	check(Session.current == null and FileAccess.get_file_as_string(Catalog.SAVE_PATH) == before, "F6预览不创建会话或修改正式档")
	preview.free()
	print("CUTSCENE_ASSERTIONS:", assertions, " FAILURES:", failures.size())
	quit(0 if failures.is_empty() else 1)
func _new_player() -> CanvasLayer:
	var player := Player.new()
	root.add_child(player)
	return player
func _player_checks() -> void:
	var audio := AudioStreamPlayer.new()
	audio.stream = AudioStreamGenerator.new()
	root.add_child(audio)
	audio.play()
	var prepaused := AudioStreamPlayer.new()
	prepaused.stream = AudioStreamGenerator.new()
	root.add_child(prepaused)
	prepaused.play()
	prepaused.stream_paused = true
	var player := _new_player()
	var results: Array[String] = []
	player.finished.connect(func(result): results.append(result))
	check(not player.play_file(fixture + ".missing.ogv"), "缺片立即返回原对白")
	check(not player.play_file(fixture.get_base_dir().path_join("bad.ogv")), "坏文件立即返回原对白")
	check(not player.play_file(fixture.get_base_dir().path_join("truncated.ogv")), "截断Ogg文件立即返回原对白")
	for broken in ["damaged.ogv", "missing_page.ogv", "missing_eos.ogv"]:
		var invalid := _new_player()
		check(not invalid.play_file(fixture.get_base_dir().path_join(broken)), "损坏的Ogg流拒绝播放：" + broken)
		invalid.free()
	check(not paused and not audio.stream_paused and prepaused.stream_paused and results.is_empty(), "启动失败不改变暂停音频也不重复回调")
	check(player.play_file(fixture), "真实Theora/Vorbis夹具开始解码")
	check(paused and audio.stream_paused and prepaused.stream_paused, "播放期间冻结场景与现有音频")
	check(not player.play_file(fixture), "连按不能重启当前片段")
	check(not player.video.loop, "播放器禁止循环")
	check(absf(player.video.size.x / player.video.size.y - 16.0 / 9.0) < 0.001, "不同视口保持原片比例")
	await create_timer(0.45, true).timeout
	check(player.video.stream_position > 0.1 and player.video.get_video_texture().get_width() == 160, "真实解码时间与画面尺寸有效")
	if not OS.get_environment("CUTSCENE_TEST_OUTPUT").is_empty():
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		check(image != null and not image.is_empty(), "原生窗口有实际可读画面")
		if image != null: image.save_png(OS.get_environment("CUTSCENE_TEST_OUTPUT").path_join("cutscene_fixture.png"))
	for step in 50:
		if not results.is_empty(): break
		await create_timer(0.05, true).timeout
	check(results == ["completed"], "自然结束仅报告一次completed")
	check(not paused and not audio.stream_paused and prepaused.stream_paused, "自然结束恢复原暂停和音频状态")
	player._video_finished()
	check(results.size() == 1, "重复finished信号不重复结算")
	player.free()
	player = _new_player(); results.clear()
	player.finished.connect(func(result): results.append(result))
	check(player.play_file(fixture), "Esc验证使用实际视频")
	await process_frame
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.physical_keycode = KEY_ESCAPE; escape.pressed = true
	Input.parse_input_event(escape)
	Input.flush_buffered_events()
	player._video_finished()
	Input.parse_input_event(escape.duplicate())
	Input.flush_buffered_events()
	check(results == ["skipped"], "Esc、结束同帧与连按只回调一次")
	check(not paused and not audio.stream_paused, "Esc后输入和音频可恢复")
	escape = escape.duplicate(); escape.pressed = false; Input.parse_input_event(escape); Input.flush_buffered_events()
	player.free()
	paused = true
	var audio_before := audio.stream_paused
	var prepaused_before := prepaused.stream_paused
	player = _new_player()
	check(player.play_file(fixture), "已有暂停状态也可播放")
	player.abort()
	check(paused and audio.stream_paused == audio_before and prepaused.stream_paused == prepaused_before, "取消恢复进入前的暂停与音频状态")
	player.free(); paused = false
	prepaused.stream_paused = true
	player = _new_player(); check(player.play_file(fixture), "场景退出前片段活动")
	player.free()
	check(not paused and not audio.stream_paused and prepaused.stream_paused, "直接离树恢复暂停与音频，不悬挂输入")
	player = _new_player(); results.clear()
	player.finished.connect(func(result): results.append(result))
	check(player.play_file(fixture), "中途故障验证开始播放")
	player.video.paused = true
	player._process(Player.STALL_SECONDS + 0.1)
	check(results == ["failed"] and not paused, "停止推进的流自动失败并释放输入")
	player.free(); audio.free(); prepaused.free()
func _stage_checks() -> void:
	for scenario in ["missing", "bad", "complete", "skip", "failed", "exit"]:
		var session := Session.new()
		check(session.start_new(true).ok, scenario + " 使用隔离正式档")
		check(session.commit_event(session.campaign.safe_snapshot().world, "dialogue:a1").ok, "先完成原开场到达条件")
		var stage := StageHarness.new()
		stage.session = session
		stage.fixture_path = fixture if scenario not in ["missing", "bad"] else ("" if scenario == "missing" else fixture.get_base_dir().path_join("bad.ogv"))
		root.add_child(stage)
		await process_frame
		check(stage._cutscene == null and stage.controls_enabled, "进入第一夜不提前播放石钵")
		var before: Dictionary = session.campaign.safe_snapshot()
		var saved_before := FileAccess.get_file_as_string(Catalog.SAVE_PATH)
		stage._confirm_armed = true
		check(stage.request_interaction("basin"), scenario + " 原basin调查接线")
		check(not stage.request_interaction("basin"), "连按调查不重入")
		check(session.campaign.safe_snapshot() == before and FileAccess.get_file_as_string(Catalog.SAVE_PATH) == saved_before, "片段启动不提前完成/奖励/写档")
		if scenario == "exit":
			stage.shutdown(); stage.free()
			await process_frame
			check(not paused and session.campaign.safe_snapshot() == before and FileAccess.get_file_as_string(Catalog.SAVE_PATH) == saved_before, "离场不提交剧情，恢复存档仍待调查")
			session.close()
			continue
		if scenario == "skip":
			await process_frame
			var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
			Input.parse_input_event(escape)
			Input.flush_buffered_events()
			escape = escape.duplicate(); escape.pressed = false; Input.parse_input_event(escape); Input.flush_buffered_events()
		elif scenario == "failed":
			stage._cutscene.video.paused = true
			stage._cutscene._process(Player.STALL_SECONDS + 0.1)
		elif scenario == "complete":
			for step in 50:
				if stage._mode != "cutscene": break
				await create_timer(0.05, true).timeout
		await process_frame
		await process_frame
		var expected := "h3" if scenario in ["complete", "skip"] else "h1"
		check(stage._dialogue != null and stage._dialogue._playing_id == expected, scenario + " 从" + expected + "接续且不重复前两句")
		check(not paused and not stage.controls_enabled and stage._mode == "dialogue", "片段后继续原对白输入锁")
		check(session.campaign.safe_snapshot() == before and FileAccess.get_file_as_string(Catalog.SAVE_PATH) == saved_before, "接续对白前尚未写入h1完成")
		var dialogue: CanvasLayer = stage._dialogue
		var visited: Array[String] = []
		while dialogue._active and visited.size() < 10:
			visited.append(dialogue._playing_id)
			var choices: Array = dialogue._nodes[dialogue._playing_id].get("choices", [])
			if not choices.is_empty(): dialogue._choice_next = str(choices[0].next)
			dialogue._complete_current()
		check(visited.has("h3") and visited.has("h4a") and visited.has("h5"), "接续保留原选择分支和末句")
		check(stage.controls_enabled and stage._mode == "explore" and session.campaign.safe_snapshot().world.event_flags.get("dialogue:h1", false), "原对白完成才提交h1并恢复探索")
		var after := FileAccess.get_file_as_string(Catalog.SAVE_PATH)
		stage._confirm_armed = true
		check(not stage.request_interaction("basin") and FileAccess.get_file_as_string(Catalog.SAVE_PATH) == after, "已完成的石钵不重复播放或写档")
		stage.free(); session.close()
		var resumed := Session.new()
		check(resumed.resume().ok and resumed.campaign.safe_snapshot().world.event_flags.get("dialogue:h1", false), "重新加载保留原事件完成状态")
		resumed.close()
