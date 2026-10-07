extends SceneTree
var player: CanvasLayer
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	# 60Hz物理的最大步数会把低FPS的process delta钳到0.133s。
	Engine.physics_ticks_per_second = 3
	_run.call_deferred()
func _run() -> void:
	var fixture := OS.get_environment("CUTSCENE_TEST_FIXTURE")
	for path in [fixture, fixture.get_base_dir().path_join("long.ogv")]:
		player = load("res://scripts/campaign/cutscene_player.gd").new()
		root.add_child(player)
		var results: Array[String] = []
		player.finished.connect(func(result):
			results.append(result)
			print("CUTSCENE_LOW_FPS_RESULT:", result, " LAST_POSITION:", player._last_position, " PROCESS_DELTA:", player.get_process_delta_time(), " VIDEO_FRAME_SECONDS:", player._frame_seconds))
		if not player.play_file(path): quit(1); return
		for step in 40:
			if not results.is_empty(): break
			await create_timer(0.25, true).timeout
		if results != ["completed"]:
			printerr("ASSERT FAIL: 低帧率自然播放没有完成：", path)
			quit(1)
			return
		player.free()
	quit()
