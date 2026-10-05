# 艺术接入前后碰撞不变量、胶囊通路与真实stage截图。不得直接指向玩家user目录。
extends SceneTree
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
const Geometry = preload("res://scripts/campaign/chapter_geometry.gd")
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Store = preload("res://scripts/rpg/save_store.gd")
const BASELINE := "res://tools/campaign/fixtures/environment_collision_baseline.json"
var failures: Array[String] = []
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		printerr("ASSERT FAIL: ", message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _run() -> void:
	for id in range(2, 6):
		check(ResourceLoader.exists("res://scripts/campaign/environments/night_%d_art.gd" % id), "第%d夜艺术依赖显式可加载" % id)
	var recorded: Dictionary = {}
	var record_path := OS.get_environment("CAMPAIGN_ENVIRONMENT_RECORD")
	var baseline: Dictionary = {} if not record_path.is_empty() else JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
	for id in range(1, 6):
		var config: Dictionary = Catalog.night(id)
		var world: Node3D = Geometry.build(id, config)
		root.add_child(world)
		await physics_frame
		var shapes: Array[String] = []
		_collisions(world, shapes)
		shapes.sort()
		recorded[str(id)] = {"shapes": shapes, "anchors": config.anchors, "interactions": config.interactions, "bounds": config.bounds}
		print("ENVIRONMENT_COLLISIONS:", id, ":", shapes.size(), ":", JSON.stringify(shapes).sha256_text())
		if record_path.is_empty():
			if id == 1:
				var unchanged_environment: Environment = world.find_children("*", "WorldEnvironment", true, false)[0].environment
				check(is_equal_approx(unchanged_environment.ambient_light_energy, 0.62), "第%d夜原环境照明不变" % id)
			check(baseline.has(str(id)) and baseline[str(id)].shapes == shapes, "第%d夜原碰撞形状/世界变换/层与掩码未变化" % id)
			check(JSON.stringify(baseline[str(id)].anchors) == JSON.stringify(config.anchors), "第%d夜安全锚点不变" % id)
			check(JSON.stringify(baseline[str(id)].bounds) == JSON.stringify(config.bounds), "第%d夜场景边界不变" % id)
			check(JSON.stringify(baseline[str(id)].interactions) == JSON.stringify(config.interactions), "第%d夜交互登记不变" % id)
			if id > 1 and str(id) in OS.get_environment("CAMPAIGN_ENVIRONMENT_NIGHTS").split(","):
				var art: Node = world.get_node_or_null("EnvironmentArt")
				check(art != null, "第%d夜接入独立真实环境艺术" % id)
				var legacy: Node3D = world.get_node_or_null("LegacyCollision")
				check(legacy != null and not legacy.visible, "第%d夜旧占位可见层已隐藏" % id)
				if legacy != null:
					for light in legacy.find_children("*", "Light3D", true, false):
						check(not light.is_visible_in_tree(), "第%d夜旧占位灯已隐藏" % id)
				if art != null:
					check(art.find_children("*", "MeshInstance3D", true, false).size() >= 30, "第%d夜具有真实网格建筑/道具" % id)
					check(art.find_children("*", "PhysicsBody3D", true, false).is_empty(), "第%d夜艺术不增加新物理阻挡" % id)
					_test_ring_visibility(art, config, id)
					if id == 2: _test_night2_lighting(world)
					elif id >= 3: _test_later_night_lighting(world, id)
				await _test_paths(world, config, id)
		world.free()
	if not record_path.is_empty():
		var file := FileAccess.open(record_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(recorded, "\t")); file.close()
		print("BASELINE_RECORDED:", record_path)
	else:
		if DisplayServer.get_name() != "headless" and not OS.get_environment("CAMPAIGN_ENVIRONMENT_OUTPUT").is_empty():
			await _capture_stages()
	print("ENVIRONMENT ART: ", assertions, " assertions, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
func _collisions(node: Node, result: Array[String]) -> void:
	if node is CollisionShape3D:
		var shape: Shape3D = node.shape
		var value := "%s|%s|%s|%s|%s" % [shape.get_class(), _transform_key(node.global_transform), str(shape.size) if shape is BoxShape3D else str(shape.get_debug_mesh().get_aabb()), node.get_parent().collision_layer, node.get_parent().collision_mask]
		result.append(value)
	for child in node.get_children(): _collisions(child, result)
func _transform_key(value: Transform3D) -> String:
	var components: Array[String] = []
	for vector in [value.basis.x, value.basis.y, value.basis.z, value.origin]:
		for number in [vector.x, vector.y, vector.z]: components.append("%.5f" % number)
	return ",".join(components)
func _test_paths(world: Node3D, config: Dictionary, id: int) -> void:
	var space := world.get_world_3d().direct_space_state
	# 与真实角色相同的0.22m半径、1.4m高胶囊；脚底上抬3cm离开地板接触层。
	var capsule := CapsuleShape3D.new(); capsule.radius = 0.22; capsule.height = 1.4
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = capsule
	var positions: Array[Vector3] = []
	for value in config.anchors.values(): positions.append(Geometry.vector(value))
	for target in config.interactions: positions.append(Geometry.vector(target.position))
	for position in positions:
		query.transform.origin = position + Vector3(0, 0.73, 0)
		check(space.intersect_shape(query, 8).is_empty(), "第%d夜真实胶囊锚点/交互无重叠%s" % [id, position])
		var ray := PhysicsRayQueryParameters3D.create(position + Vector3.UP, position - Vector3.UP)
		var hit := space.intersect_ray(ray)
		check(not hit.is_empty() and hit.normal.y > 0.9, "第%d夜锚点/交互有可站立地面%s" % [id, position])
	# 连续扫掠代替只测离散点；中央折线路径依次连通所有交互与返场位置。
	var route: Array[Vector3] = [Geometry.vector(config.anchors.spawn), Vector3(-4.7, 0, 0)]
	for target in config.interactions: route.append(Geometry.vector(target.position))
	route.append(Geometry.vector(config.anchors.battle_return))
	for index in range(route.size() - 1):
		query.transform.origin = route[index] + Vector3(0, 0.73, 0)
		query.motion = route[index + 1] - route[index]
		var cast := space.cast_motion(query)
		check(cast[0] >= 0.999, "第%d夜中央连续胶囊通路%d畅通" % [id, index])
	query.motion = Vector3.ZERO
	for direction in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 1, 0), Vector3(0, 1, 0) + direction * 10)
		check(not space.intersect_ray(ray).is_empty(), "第%d夜边界仍阻挡%s" % [id, direction])
func _capture_stages() -> void:
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("CAMPAIGN_ENVIRONMENT_FIXTURES")))
	var output := OS.get_environment("CAMPAIGN_ENVIRONMENT_OUTPUT")
	var report := {"renderer": RenderingServer.get_video_adapter_name(), "vendor": RenderingServer.get_video_adapter_vendor(), "api": RenderingServer.get_video_adapter_api_version(), "method": "gl_compatibility", "resolution": [1920, 1080], "fixture_note": "真实E2E安全快照恢复正式stage；关闭开场对白仅用于环境视觉夹具，不宣称本轮人工全篇通关。", "nights": {}}
	root.size = Vector2i(1920, 1080)
	for requested in OS.get_environment("CAMPAIGN_ENVIRONMENT_NIGHTS").split(","):
		var id := int(requested)
		var store := Store.new()
		var fixture: Dictionary = fixtures[requested]
		var saved: Dictionary = store.normalize(fixture.snapshot)
		check(store.write_safe(saved, Catalog.SAVE_PATH) == OK, "第%d夜真实E2E快照合法写入隔离user" % id)
		var session := Session.new()
		check(session.resume().ok, "第%d夜由正式Session恢复" % id)
		check((await session.prepare_assets()).ok, "第%d夜正式角色素材装配" % id)
		var stage: Node3D = load(Catalog.scene_path(id)).instantiate()
		var use_hd2d := id == 2 and OS.get_environment("CAMPAIGN_ENVIRONMENT_HD2D") == "1"
		stage.hd2d_experiment = use_hd2d and OS.get_environment("CAMPAIGN_HD2D_HUD_CLICK") != "1"
		root.add_child(stage)
		for frame in 8: await physics_frame
		check(stage.ready_for_play and stage.player != null and stage.camera_rig != null, "第%d夜真实stage/角色/HUD就绪" % id)
		if not stage.ready_for_play:
			stage.free(); session.close(); continue
		# 仅关闭视觉夹具对白，不提交剧情或战果；正式会话仍保留原始检查点。
		stage._generation += 1
		if is_instance_valid(stage._dialogue):
			stage._dialogue.abort(); stage._dialogue.queue_free()
		stage._dialogue = null
		stage._resume_explore()
		if id == 2 and OS.get_environment("CAMPAIGN_ENVIRONMENT_LIGHTING_AB") == "1":
			report.nights[requested] = {"source": fixture.source, "lighting_ab": await _probe_night2_lights(stage, output)}
			stage.free(); session.close(); await process_frame
			continue
		if use_hd2d and OS.get_environment("CAMPAIGN_HD2D_HUD_CLICK") == "1":
			await _manual_hd2d_hud_clicks(stage, output)
		if use_hd2d:
			check(stage._hd2d_profile != null and stage._hd2d_profile.enabled, "正式二夜stage已开启HD2D profile")
		var shots: Array[Dictionary] = []
		var viewpoints: Array = [{"view": "center", "position": Vector3(0, 0.04, 0.8)}, {"view": "left", "position": Vector3(-4.5, 0.04, 0.8)}, {"view": "right", "position": Vector3(4.5, 0.04, 0.8)}]
		if id == 1:
			# 首夜有实际斜坡，选已登记地面安全点；不把角色塞到坡面以下。
			viewpoints = [{"view": "center", "position": Vector3(-1.2, 0.04, 0.55)}, {"view": "left", "position": Geometry.vector(stage.config.anchors.spawn)}, {"view": "right", "position": Geometry.vector(stage.config.anchors.exit)}]
		for entry in viewpoints:
			stage.player.position = entry.position
			stage.player.velocity = Vector3.ZERO
			stage.camera_rig.follow(stage.player, 10.0)
			for frame in 8: await process_frame
			# 固定同一idle帧/朝向/发丝相位，避免美术比较混入角色动画差异。
			stage.player.process_mode = Node.PROCESS_MODE_DISABLED
			stage.player.facing = 1
			stage.player.animator.set_motion(0, 1)
			stage.player.animator.sprite.animation = "idle"
			stage.player.animator.sprite.frame = 0
			stage.player.animator.sprite.pause()
			stage.player.animator._idle_clock = 0.0
			stage.player.animator._update_layers()
			stage.camera_rig.follow(stage.player, 10.0)
			await RenderingServer.frame_post_draw
			check(stage.player.animator.sprite.animation == "idle" and stage.player.animator.sprite.frame == 0, "视觉轮次角色固定idle0")
			var filename := "night_%d_%s.png" % [id, entry.view]
			check(root.get_texture().get_image().save_png(output.path_join(filename)) == OK, "真实stage截图：" + filename)
			shots.append({"file": filename, "fixed_idle": {"animation": "idle", "frame": 0, "facing": stage.player.facing, "hair_clock": stage.player.animator._idle_clock, "pixel_size": stage.player.billboard.pixel_size}, "player": str(stage.player.position), "camera": stage.camera_rig.snapshot(), "meshes": stage.get_node("ChapterGeometry").find_children("*", "MeshInstance3D", true, false).filter(func(mesh): return mesh.is_visible_in_tree()).size()})
			print("ENVIRONMENT_SCREENSHOT:", output.path_join(filename))
			if OS.get_environment("CAMPAIGN_ENVIRONMENT_COMPARISON") == "1":
				stage._ui_layer.hide()
				await process_frame; await RenderingServer.frame_post_draw
				var clear_filename := ("night_%d_%s_no_hud_hd2d_camera.png" if use_hd2d else "night_%d_%s_no_hud_default_camera.png") % [id, entry.view]
				check(root.get_texture().get_image().save_png(output.path_join(clear_filename)) == OK, "同默认镜头无HUD环境对照：" + clear_filename)
				stage._ui_layer.show()
			stage.player.process_mode = Node.PROCESS_MODE_INHERIT
		if id in [4, 5] and OS.get_environment("CAMPAIGN_ENVIRONMENT_OVERVIEW") == "1":
			stage.set_controls_enabled(false)
			stage._ui_layer.hide()
			stage.camera_rig.camera.size = 11.5
			stage.camera_rig.target = Vector3(0, 2.1, -2.0)
			stage.camera_rig._apply()
			await process_frame; await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(output.path_join("night_%d_overview_not_default.png" % id)) == OK, "第%d夜艺术全景检查图（非默认游玩镜头）" % id)
			stage._ui_layer.show()
			stage.camera_rig.camera.size = 8.0
			stage.set_controls_enabled(true)
		stage.player.position = Vector3(-3.0, 0.04, 0.8)
		stage.camera_rig.follow(stage.player, 10.0)
		stage.player.set_move_input(Vector2.RIGHT)
		var samples: Array[float] = []
		var start := Time.get_ticks_usec()
		for frame in 45:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			samples.append((now - start) / 1000.0); start = now
		stage.player.set_move_input(Vector2.ZERO)
		check(stage.player.position.x > -2.9, "第%d夜真实控制器向右行走" % id)
		samples.sort()
		var mean := 0.0
		for value in samples: mean += value
		mean /= samples.size()
		report.nights[requested] = {"source": fixture.source, "screenshots": shots, "frame_wall_ms": {"samples": samples.size(), "mean": mean, "median": samples[samples.size() / 2], "p95": samples[int(samples.size() * 0.95)], "note": "包含CPU与软件渲染/同步的实测帧间隔，不等同目标GPU耗时"}}
		print("ENVIRONMENT_FRAME_SAMPLE:", id, ":", JSON.stringify(report.nights[requested].frame_wall_ms))
		if OS.get_environment("CAMPAIGN_ENVIRONMENT_WALK") == "1":
			report.nights[requested]["walk_capture"] = await _record_walk(stage, id, output)
		if use_hd2d:
			var world_before: Dictionary = stage.export_world()
			var disk_before := FileAccess.get_file_as_string(Catalog.SAVE_PATH)
			check(stage.set_hd2d_experiment(false), "正式stage关闭HD2D")
			check(is_equal_approx(stage.camera_rig.camera.size, 8.0) and stage.get_node("ChapterGeometry/EnvironmentArt/Night2Art/SourceCorridor").visible, "正式stage恢复原R03相机与资产")
			check(stage.export_world() == world_before and FileAccess.get_file_as_string(Catalog.SAVE_PATH) == disk_before, "切换呈现不改章节世界或存档")
		stage.free(); session.close()
		await process_frame
	var file := FileAccess.open(output.path_join("render-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()

func _record_walk(stage: Node3D, id: int, output: String) -> Dictionary:
	var directory := output.path_join("night_%d_walk" % id)
	DirAccess.make_dir_recursive_absolute(directory)
	stage.player.position = Vector3(-1.5, 0.04, 0.8)
	stage.player.velocity = Vector3.ZERO
	stage.camera_rig.follow(stage.player, 10.0)
	var began := Time.get_ticks_usec()
	var frames: Array[Dictionary] = []
	while Time.get_ticks_usec() - began < 3000000:
		stage.player.set_move_input(Vector2.RIGHT if Time.get_ticks_usec() - began < 1500000 else Vector2.LEFT)
		await RenderingServer.frame_post_draw
		var filename := directory.path_join("frame_%04d.jpg" % frames.size())
		var seconds := float(Time.get_ticks_usec() - began) / 1000000.0
		check(root.get_texture().get_image().save_jpg(filename, 0.95) == OK, "第%d夜真实移动录像帧" % id)
		frames.append({"file": filename, "seconds": seconds})
	stage.player.set_move_input(Vector2.ZERO)
	return {"frames": frames, "seconds": float(Time.get_ticks_usec() - began) / 1000000.0, "note": "真实stage左右移动的逐帧视口采集，可按记录时间编码，未改图像内容"}

func _test_ring_visibility(art: Node3D, config: Dictionary, id: int) -> void:
	# 原交互环最高点是0.035+(0.32-0.27)/2=0.06m；艺术地面不能埋没其金色上缘。
	for target in config.interactions:
		var covered := false
		var center := Geometry.vector(target.position)
		for node in art.find_children("*", "MeshInstance3D", true, false):
			var aabb: AABB = node.global_transform * node.get_aabb()
			if aabb.position.y > 0.1 or aabb.end.y > 0.15: continue
			for index in 24:
				var angle := TAU * index / 24.0
				if aabb.has_point(center + Vector3(cos(angle) * 0.295, 0.058, sin(angle) * 0.295)):
					covered = true
		check(not covered, "第%d夜地面不埋没交互金环上缘：%s" % [id, target.id])

func _test_night2_lighting(world: Node3D) -> void:
	var lighting: Node3D = world.get_node_or_null("Night2Lighting")
	check(lighting != null, "第二夜独立暖灯光层已建立")
	var environment: Environment = world.find_children("*", "WorldEnvironment", true, false)[0].environment
	check(environment.ambient_light_energy >= 0.10 and environment.ambient_light_energy <= 0.30, "第二夜冷暗填光保留可读性但不再均匀灰亮")
	if lighting == null: return
	var lamps := lighting.find_children("*", "OmniLight3D", true, false)
	check(lamps.size() >= 4 and lamps.size() <= 6, "回廊实际灯位有有界数量局部暖光池")
	for lamp in lamps:
		check(lamp.light_color.r > lamp.light_color.b and lamp.light_energy > 0.5 and lamp.omni_range <= 4.8, "局部灯投暖光、有效且有界范围")
		check(not lamp.shadow_enabled, "局部灯不叠加大量动态阴影")
	var keys := world.find_children("*", "DirectionalLight3D", true, false)
	check(keys.size() == 1 and not keys[0].shadow_enabled, "保留方向受光但移除已实测的动态阴影acne")
	var contacts := lighting.find_children("Contact_*", "MeshInstance3D", true, false)
	check(contacts.size() == 6, "五柱脚与旧箱用小面积静态柔接触暗部保留落地感")
	for contact in contacts:
		check(contact.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and contact.material_override is ShaderMaterial, "接触暗部不重新引入动态阴影或碰撞")

func _probe_night2_lights(stage: Node3D, output: String) -> Dictionary:
	# 三组只读图形夹具同树/同中心镜头/同idle；不会保存任何生产配置。
	stage.player.position = Vector3(0, 0.04, 0.8)
	stage.player.velocity = Vector3.ZERO
	stage.player.set_move_input(Vector2.ZERO)
	for frame in 8: await physics_frame
	stage.set_controls_enabled(false)
	stage.player.process_mode = Node.PROCESS_MODE_DISABLED
	stage.player.animator.set_motion(0, 1)
	stage.player.animator.sprite.animation = "idle"
	stage.player.animator.sprite.frame = 0
	stage.player.animator.sprite.pause()
	stage.player.animator._idle_clock = 0.0
	stage.player.animator._update_layers()
	stage.camera_rig.follow(stage.player, 10.0)
	stage._ui_layer.hide()
	var key: DirectionalLight3D = stage.get_node("ChapterGeometry/CoolNightKey")
	var lamps := stage.get_node("ChapterGeometry/Night2Lighting").find_children("*", "OmniLight3D", true, false)
	var original_shadow: bool = key.shadow_enabled
	var near_wall_lamps: Array = lamps.filter(func(lamp): return str(lamp.name).begins_with("WarmWallLantern_"))
	near_wall_lamps.sort_custom(func(left, right): return absf(left.position.x) < absf(right.position.x))
	near_wall_lamps = near_wall_lamps.slice(0, mini(3, near_wall_lamps.size()))
	var result := {"camera": stage.camera_rig.snapshot(), "fixed_idle": {"animation": "idle", "frame": 0, "hair_clock": 0.0, "pixel_size": stage.player.billboard.pixel_size}, "variants": {}}
	for variant in ["original", "no_directional_shadow", "three_local_wall_lights"]:
		key.shadow_enabled = original_shadow and variant != "no_directional_shadow"
		var active: Array[Dictionary] = []
		for lamp in lamps:
			lamp.visible = variant != "three_local_wall_lights" or near_wall_lamps.has(lamp)
			if lamp.visible:
				active.append({"name": str(lamp.name), "position": str(lamp.position), "energy": lamp.light_energy, "range": lamp.omni_range})
		for frame in 8: await RenderingServer.frame_post_draw
		var samples: Array[float] = []
		var began := Time.get_ticks_usec()
		for frame in 45:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			samples.append((now - began) / 1000.0); began = now
		var filename := "night_2_probe_%s.png" % variant
		check(root.get_texture().get_image().save_png(output.path_join(filename)) == OK, "真实同镜头A/B：" + variant)
		samples.sort()
		var mean := 0.0
		for value in samples: mean += value
		mean /= samples.size()
		result.variants[variant] = {"screenshot": filename, "directional_shadow": key.shadow_enabled, "warm_lights": active, "frame_wall_ms": {"samples": 45, "mean": mean, "median": samples[22], "p95": samples[42]}}
		print("NIGHT2_LIGHTING_PROBE:", variant, ":", JSON.stringify(result.variants[variant]))
	return result

func _test_later_night_lighting(world: Node3D, id: int) -> void:
	var lighting := world.get_node_or_null("Night%dLighting" % id)
	check(lighting != null, "第%d夜独立局部灯层" % id)
	var env: Environment = world.find_children("*", "WorldEnvironment", true, false)[0].environment
	check(env.ambient_light_energy >= 0.15 and env.ambient_light_energy <= 0.30, "第%d夜冷暗环境保留材质层次" % id)
	if lighting == null: return
	var lamps := lighting.find_children("*", "OmniLight3D", true, false)
	check(lamps.size() == id, "第%d夜限定%d个局部灯" % [id, id])
	for lamp in lamps:
		check(lamp.light_energy > 0.0 and lamp.omni_range <= 3.5 and not lamp.shadow_enabled, "第%d夜局部照明有界且无动态阴影" % id)
	var keys := world.find_children("*", "DirectionalLight3D", true, false)
	check(keys.size() == 1 and not keys[0].shadow_enabled, "第%d夜保留单一无阴影冷夜方向光" % id)

func _manual_hd2d_hud_clicks(stage: Node3D, output: String) -> void:
	stage.player.position = Vector3(0, 0.04, 0.8)
	stage.player.velocity = Vector3.ZERO
	stage.camera_rig.follow(stage.player, 10.0)
	var disk_before := FileAccess.get_file_as_string(Catalog.SAVE_PATH)
	for expected in [true, false]:
		var began := Time.get_ticks_msec()
		print("HD2D_HUD_WAIT_CLICK:", "ON" if expected else "OFF")
		while stage.hd2d_experiment != expected and Time.get_ticks_msec() - began < 120000:
			await process_frame
		check(stage.hd2d_experiment == expected, "真实GUI点击HD2D按钮：" + str(expected))
		await process_frame; await RenderingServer.frame_post_draw
		var filename := "hud_manual_on.png" if expected else "hud_manual_off.png"
		check(root.get_texture().get_image().save_png(output.path_join(filename)) == OK, "实际点击状态截图")
	check(FileAccess.get_file_as_string(Catalog.SAVE_PATH) == disk_before, "手动点击HD2D未改存档字节")
	stage.set_hd2d_experiment(true)
	# 操作提示截图已留证；后续行走视频只留固定HUD提示，避免大字遮环境。
	stage._notice("")
