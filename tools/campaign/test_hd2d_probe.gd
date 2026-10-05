# 仅测试夹具：正式二夜安全快照、隔离存档、固定角色和独立实验镜头。
extends SceneTree
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Store = preload("res://scripts/rpg/save_store.gd")
const SHADER_PATH := "res://scripts/campaign/presentation/hd2d_depth_blur.gdshader"
var failures: Array[String] = []
var output: String
func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		printerr("ASSERT FAIL: ", message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _run() -> void:
	output = OS.get_environment("HD2D_OUTPUT")
	check(FileAccess.file_exists(SHADER_PATH), "景深shader资源必须存在")
	if failures.size() > 0: quit(1); return
	var shader := load(SHADER_PATH) as Shader
	check(shader != null, "shader可加载")
	if OS.get_environment("HD2D_CONTRACT_ONLY") == "1":
		print("HD2D_CONTRACT:", "pass" if failures.is_empty() else "fail")
		quit(0 if failures.is_empty() else 1); return
	root.size = Vector2i(1920, 1080)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("HD2D_FIXTURE")))
	var store := Store.new()
	check(store.write_safe(store.normalize(fixture.snapshot), Catalog.SAVE_PATH) == OK, "隔离快照写入")
	var session := Session.new()
	check(session.resume().ok, "正式Session恢复")
	check((await session.prepare_assets()).ok, "正式角色素材装配")
	var stage: Node3D = load(Catalog.scene_path(2)).instantiate()
	root.add_child(stage)
	for frame in 8: await physics_frame
	check(stage.ready_for_play, "真实二夜stage可玩")
	if not stage.ready_for_play: quit(1); return
	# 可选夹具分支；只替换美术节点，正式R03注册/碰撞/灯光均不写盘。
	if OS.get_environment("HD2D_VARIANT") == "1":
		var old := stage.get_node("ChapterGeometry/EnvironmentArt/Night2Art/SourceCorridor")
		var parent := old.get_parent()
		parent.remove_child(old)
		old.free()
		var variant: Node3D = load("res://assets/3d/night02_corridor_hd2d/night02_corridor_hd2d.glb").instantiate()
		variant.name = "SourceCorridorHD2DTestOnly"
		parent.add_child(variant)
	stage._generation += 1
	if is_instance_valid(stage._dialogue):
		stage._dialogue.abort(); stage._dialogue.queue_free()
	stage._dialogue = null
	stage._resume_explore()
	stage.set_controls_enabled(false)
	stage.player.position = Vector3(0, 0.04, 0.8)
	stage.player.velocity = Vector3.ZERO
	stage.player.facing = 1
	stage.player.animator.set_motion(0, 1)
	stage.player.animator.sprite.animation = "idle"
	stage.player.animator.sprite.frame = 0
	stage.player.animator.sprite.pause()
	stage.player.animator._idle_clock = 0.0
	stage.player.animator._update_layers()
	stage.player.process_mode = Node.PROCESS_MODE_DISABLED
	var camera := Camera3D.new()
	camera.name = "HD2DProbeCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 9.2
	camera.near = 0.1
	camera.far = 120.0
	stage.add_child(camera)
	var target: Vector3 = stage.player.global_position + Vector3.UP * 1.1
	camera.position = target + Vector3(0, 6.2, 11.0)
	camera.look_at(target)
	camera.make_current()
	var material := ShaderMaterial.new()
	material.shader = shader
	# 最早透明通道先做后期，随后原生透明灯晕正常绘制；不重画角色。
	material.render_priority = -128
	var quad := MeshInstance3D.new()
	quad.name = "HD2DProbeQuad"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2, 2)
	quad.mesh = mesh
	quad.material_override = material
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(quad)
	quad.position.z = -1.0
	var report := {"source": fixture.source, "hd2d_variant": OS.get_environment("HD2D_VARIANT") == "1", "resolution": [1920, 1080], "renderer": RenderingServer.get_video_adapter_name(), "method": RenderingServer.get_current_rendering_method(), "camera": {"size": camera.size, "offset": [0, 6.2, 11], "target": str(target)}, "note": "真实二夜stage；独立实验镜头。前四图保留完整场景且无额外几何；probe_boards诊断图隐藏HUD和遮挡环境美术，保留角色/交互环并加界外棋盘探针。identity为无写入空操作；焦内discard保留原像素，非低精度屏幕复制。只验证后期能力，不代表最终HD2D美术。", "shots": [], "regions": {}}
	for mode in ["off", "identity", "depth", "blur"]:
		quad.visible = mode != "off"
		material.set_shader_parameter("effect_mode", 2 if mode == "depth" else 1 if mode == "blur" else 0)
		await _settle()
		await _capture("night2_" + mode + ".png")
		report.shots.append("night2_" + mode + ".png")
	# 两个不带碰撞的界外棋盘，明确标为探针；验证近/远深度皆可触发。
	var boards := Node3D.new()
	boards.name = "TEST_ONLY_DepthBoards"
	stage.add_child(boards)
	_board(boards, Vector3(-5.8, 2.6, 5.5), Color("dd9955"), "near")
	_board(boards, Vector3(5.0, 0.7, -7.5), Color("55aacc"), "far")
	stage._ui_layer.hide()
	stage.get_node("ChapterGeometry/EnvironmentArt").hide()
	for mode in ["off", "depth", "blur"]:
		quad.visible = mode != "off"
		material.set_shader_parameter("effect_mode", 2 if mode == "depth" else 1)
		await _settle()
		await _capture("probe_boards_" + mode + ".png")
	for entry in [["character", Vector3(-0.8, 0.0, 0.8), Vector3(0.8, 2.9, 0.8)], ["near", Vector3(-6.7, 1.7, 5.5), Vector3(-4.9, 3.5, 5.5)], ["far", Vector3(4.1, -0.2, -7.5), Vector3(5.9, 1.6, -7.5)]]:
		var a := camera.unproject_position(entry[1])
		var b := camera.unproject_position(entry[2])
		report.regions[entry[0]] = [minf(a.x,b.x), minf(a.y,b.y), maxf(a.x,b.x), maxf(a.y,b.y)]
	boards.hide()
	stage._ui_layer.show()
	stage.get_node("ChapterGeometry/EnvironmentArt").show()
	report["frame_wall_ms"] = {}
	for mode in ["off", "blur"]:
		quad.visible = mode != "off"
		material.set_shader_parameter("effect_mode", 1)
		await _settle()
		var samples: Array[float] = []
		var previous := Time.get_ticks_usec()
		for frame in 24:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			samples.append((now - previous) / 1000.0)
			previous = now
		samples.sort()
		var mean := 0.0
		for sample in samples: mean += sample
		report.frame_wall_ms[mode] = {"count": samples.size(), "mean": mean/samples.size(), "median": samples[12], "p95": samples[22], "note": "软件渲染整帧墙钟，非目标GPU耗时"}
	var file := FileAccess.open(output.path_join("probe-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	stage.free(); session.close()
	print("HD2D_PROBE:", "pass" if failures.is_empty() else "fail")
	quit(0 if failures.is_empty() else 1)
func _settle() -> void:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
func _capture(filename: String) -> void:
	check(root.get_texture().get_image().save_png(output.path_join(filename)) == OK, "截图写入" + filename)
	print("HD2D_SCREENSHOT:", output.path_join(filename))
func _board(parent: Node3D, center: Vector3, color: Color, label: String) -> void:
	for x in 12:
		for y in 12:
			var tile := MeshInstance3D.new()
			tile.name = label + "_" + str(x) + "_" + str(y)
			var mesh := QuadMesh.new()
			mesh.size = Vector2(0.15, 0.15)
			tile.mesh = mesh
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = color if (x+y)%2 == 0 else Color("171820")
			tile.material_override = material
			parent.add_child(tile)
			tile.position = center + Vector3((x-5.5)*0.15, (y-5.5)*0.15, 0)
