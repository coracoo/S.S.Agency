# 身高关系从真实人物像素参考点与节点变换测量，不能只比JSON数字。
extends SceneTree
const Bundle = preload("res://scripts/characters/party_asset_bundle.gd")
const Player = preload("res://scripts/exploration_3d/player_controller.gd")
const View = preload("res://scripts/rpg/ui/battle_view.gd")
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Support = preload("res://tools/campaign/presentation_test_support.gd")
const Stature = preload("res://scripts/characters/character_stature.gd")
const Definition = preload("res://scripts/characters/pixel_character_definition.gd")
const Portraits = preload("res://scripts/characters/identity_portraits.gd")
const REFERENCES := {"rinne": {"crown": Vector2(665, 64), "sole": Vector2(600, 1082), "ground": 1083.0}, "mint": {"crown": Vector2(616, 50), "sole": Vector2(650, 1062), "ground": 1063.0}, "guard": {"crown": Vector2(565, 97), "sole": Vector2(744, 1122), "ground": 1123.0}, "homura_mage": {"crown": Vector2(500, 48), "sole": Vector2(606, 1055), "ground": 1056.0}, "homura_sword": {"crown": Vector2(821, 90), "sole": Vector2(645, 1066), "ground": 1067.0}}
var failures: Array[String] = []
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(1); return
	_run.call_deferred()
# 独立目检当前待机首帧的本体头顶/鞋底坐标；排除高马尾、发饰和武器。
# 原图参考与视频参考分开固定，不能按被测canvas反推坐标而让错误缩放自洽。
const VIDEO_REFERENCES := {
	"rinne": {"frame": "idle_015", "crown": Vector2(1020, 994), "sole": Vector2(990, 1441), "ground": 1442.0},
	"mint": {"frame": "idle_037", "crown": Vector2(1022, 482), "sole": Vector2(1035, 928), "ground": 930.0},
	"guard": {"frame": "idle_034", "crown": Vector2(1010, 482), "sole": Vector2(1085, 928), "ground": 930.0},
	"homura_mage": {"frame": "idle_natural_001", "crown": Vector2(1027, 482), "sole": Vector2(1086, 929), "ground": 930.0},
	"homura_sword": {"frame": "idle_024", "crown": Vector2(1020, 482), "sole": Vector2(950, 929), "ground": 930.0}
}
func _run() -> void:
	check(FileAccess.file_exists("res://data/characters/stature.json"), "独立可配置六身份物理身高资料")
	var session := Session.new()
	check(session.start_new(true).ok and (await session.prepare_assets("world")).ok, "身高测试真实默认三人正式会话")
	# BattleView会释放会话中的world定义；测试显式持有探索演员实际所需的版本。
	var world_definitions: Dictionary = {}
	for identity in ["rinne", "mint", "guard"]:
		world_definitions[identity] = session.bundle.get_definition(identity)
	for event in ["dialogue:a1", "dialogue:r1", "dialogue:h1"]: session.commit_event(session.campaign.safe_snapshot().world, event)
	check(session.begin_encounter(session.campaign.safe_snapshot().world, "basin_reflection").ok, "真实正式战斗用于像素测量")
	var view := View.new(); view.router = session.router; root.add_child(view)
	var ready: Dictionary = await Support.wait_for_battle(self, view, session.campaign.safe_snapshot().party)
	check(ready.ok, "身高测试等待真实战斗演员：" + ready.error)
	if not ready.ok:
		view.free(); session.close(); _finish(); return
	view._cancel_presentation(); view._render()
	var measured: Dictionary = {}
	var feet: Dictionary = {}
	var world_measured: Dictionary = {}
	var actors_3d: Dictionary = {}
	var world := Node3D.new(); root.add_child(world)
	for index in 3:
		var identity: String = ["rinne", "mint", "guard"][index]
		var actor_id: String = ["p_swordsman", "p_ranger", "p_guard"][index]
		var hd: Node2D = view._hd_views[actor_id]
		var battle_definition: Dictionary = hd._definition
		var world_definition: Dictionary = world_definitions[identity]
		check(world_definition.context == "world" and battle_definition.context == "battle", "探索/战斗持有各自真实上下文：" + identity)
		_test_reference_png(identity)
		var ref: Dictionary = _runtime_reference(battle_definition, identity)
		_runtime_reference(world_definition, identity)
		var crown_y: float = hd.animator.to_global(ref.crown).y
		var foot_y: float = hd.animator.to_global(Vector2(ref.sole.x, ref.ground)).y
		measured[identity] = foot_y - crown_y
		feet[identity] = foot_y
		_check_battle_scale(hd, battle_definition, identity)
		var body: Sprite3D = view._world_backdrop.actor_entries[actor_id].body
		var body_height := _sprite_pixel_y(body, ref.crown.y) - _sprite_pixel_y(body, ref.ground)
		check(absf(body_height - Stature.height_cm(identity) / 100.0) < 0.00001 and absf(_sprite_pixel_y(body, ref.ground)) < 0.00001, "真实3D战斗薄片保留本体米数及鞋底锚：" + identity)
		var player := Player.new(); player.shared_definition = world_definition; player.input_enabled = false; world.add_child(player)
		player.process_mode = Node.PROCESS_MODE_DISABLED
		player.position = Vector3((index - 1) * 1.55, 0, 0)
		actors_3d[identity] = player
		var image_top := _world_pixel_y(player, ref.crown.y)
		var image_ground := _world_pixel_y(player, ref.ground)
		world_measured[identity] = image_top - image_ground
		check(absf(image_ground) < 0.00001, "探索真实紧凑图集鞋底锚在角色根节点：" + identity)
		_check_world_scale(player, world_definition, identity)
		print("HEIGHT_MEASURED:", identity, ":battle_px=", measured[identity], ":feet_y=", feet[identity], ":world_m=", world_measured[identity])
	check(measured.mint < measured.rinne and measured.guard > measured.rinne, "真实战斗本体像素：薄荷矮于凛音，岑照高于凛音")
	check(absf(feet.mint - feet.rinne) < 0.001 and absf(feet.guard - feet.rinne) < 0.001, "三人鞋底统一地面基线，而非槽位各自fit")
	# 同时检查二维演员根节点和正式3D绘制薄片，避免只测隐藏的参考节点。
	for index in 3:
		var identity: String = ["rinne", "mint", "guard"][index]
		var hd: Node2D = view._hd_views[["p_swordsman", "p_ranger", "p_guard"][index]]
		check(absf(feet[identity] - hd.global_position.y) < 0.001, "战斗鞋底落在实际投影脚点：" + identity)
	check(absf(world_measured.rinne - 1.68) < 0.001 and absf(world_measured.mint - 1.58) < 0.001 and absf(world_measured.guard - 1.86) < 0.001, "实际alpha校准节点量得168/158/186cm本体身高")
	check(world_measured.mint < world_measured.rinne and world_measured.guard > world_measured.rinne, "真实探索本体米数同样矮/中/高")
	var ppm: float = measured.rinne / world_measured.rinne
	check(absf(measured.mint / world_measured.mint - ppm) < 0.001 and absf(measured.guard / world_measured.guard - ppm) < 0.001, "探索米数与战斗像素共享同一物理基准")
	var dual_heights: Array[float] = []
	var dual_world_heights: Array[float] = []
	var Hd = load("res://scripts/rpg/ui/hd_actor_view.gd")
	for key in ["homura_mage", "homura_sword"]:
		_test_reference_png(key)
		var definition: Dictionary = Definition.load_definition(Bundle.MANIFESTS[key], "battle")
		check(definition.get("ok", false), "焰华当前视频战斗定义可加载：" + key)
		if not definition.get("ok", false): continue
		var ref: Dictionary = _runtime_reference(definition, key)
		var hd = Hd.new(); root.add_child(hd)
		check(hd.configure(definition, Stature.battle_body_height("homura"), -1), "焰华真实视频高清节点配置：" + key)
		dual_heights.append(hd.animator.to_global(Vector2(ref.sole.x, ref.ground)).y - hd.animator.to_global(ref.crown).y)
		check(absf(hd.animator.to_global(Vector2(ref.sole.x, ref.ground)).y) < 0.001, "焰华各形态真实鞋底同地面")
		_check_battle_scale(hd, definition, key)
		hd.free()
		var world_definition: Dictionary = Definition.load_definition(Bundle.MANIFESTS[key], "world")
		check(world_definition.get("ok", false), "焰华当前视频探索定义可加载：" + key)
		if not world_definition.get("ok", false): continue
		_runtime_reference(world_definition, key)
		var player := Player.new(); player.shared_definition = world_definition; player.input_enabled = false; world.add_child(player)
		player.process_mode = Node.PROCESS_MODE_DISABLED
		dual_world_heights.append(_world_pixel_y(player, ref.crown.y) - _world_pixel_y(player, ref.ground))
		check(absf(_world_pixel_y(player, ref.ground)) < 0.00001, "焰华探索视频鞋底锚同地面：" + key)
		_check_world_scale(player, world_definition, key)
		player.free()
	check(dual_heights.size() == 2 and absf(dual_heights[0] - dual_heights[1]) < 0.001 and absf(dual_heights[0] - 323.0) < 0.001, "焰华实际两高清节点本体同为170cm/323px")
	check(dual_world_heights.size() == 2 and absf(dual_world_heights[0] - dual_world_heights[1]) < 0.00001 and absf(dual_world_heights[0] - 1.7) < 0.00001, "焰华实际探索双形态同为170cm")
	if not OS.get_environment("CAMPAIGN_PRESENTATION_OUTPUT").is_empty():
		view._cancel_presentation(); view._render(); await _save("battle_three_character_statures.png")
		view.hide(); _setup_world(world)
		for identity in actors_3d:
			var actor_label := Label3D.new(); actor_label.text = {"rinne": "凛音 168cm", "mint": "薄荷 158cm", "guard": "岑照 186cm"}[identity]; actor_label.font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf"); actor_label.font_size = 42; actor_label.pixel_size = 0.003; actor_label.no_depth_test = true
			world.add_child(actor_label); actor_label.position = actors_3d[identity].position + Vector3(0, -0.18, 0.08)
		await _save("exploration_three_character_statures.png")
	view.free(); world.free(); session.close()
	_finish()

func _finish() -> void:
	for failure in failures: printerr("ASSERT FAIL: ", failure)
	print("CHARACTER STATURE: ", assertions, " assertions, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func _test_reference_png(key: String) -> void:
	var identity := "homura" if key.begins_with("homura_") else key
	var definition: Dictionary = Portraits.load_idle_definition(identity, key.trim_prefix("homura_"))
	check(definition.get("ok", false), "保留独立原PNG身高校准：" + key)
	if not definition.get("ok", false): return
	var reference: Dictionary = REFERENCES[key]
	var image: Image = definition.frames.get_frame_texture("idle", 0).get_image()
	check(image.get_pixelv(Vector2i(reference.crown)).a >= 0.5 and image.get_pixelv(Vector2i(reference.sole)).a >= 0.5, "原PNG头顶与鞋底仍为真实主体像素：" + key)
	var original_height: float = (float(reference.ground) - reference.crown.y) * Stature.world_pixel_size(definition)
	check(absf(original_height - Stature.height_cm(identity) / 100.0) < 0.00001, "原PNG本体身高与视频目标一致：" + key)

func _runtime_reference(definition: Dictionary, key: String) -> Dictionary:
	var ref: Dictionary = VIDEO_REFERENCES[key]
	var manifest: Dictionary = definition.manifest
	check(manifest.anims.idle.frames[0] == ref.frame, "当前视频待机首帧与独立参考一致：" + key)
	var texture: Texture2D = definition.frames.get_frame_texture("idle", 0)
	check(texture is AtlasTexture, "真实视频帧来自已打包图集：" + key)
	if not texture is AtlasTexture: return ref
	# 明确读图集区域，不能把AtlasTexture.get_image的紧凑坐标当虚拟画布坐标。
	var image: Image = texture.atlas.get_image().get_region(Rect2i(texture.region))
	var offset := Vector2i(texture.margin.position)
	check(image.get_pixelv(Vector2i(ref.crown) - offset).a >= 0.5 and image.get_pixelv(Vector2i(ref.sole) - offset).a >= 0.5, "当前视频头顶/鞋底落在实际alpha主体：" + key)
	var bottom := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a >= 0.5: bottom = maxi(bottom, y + offset.y + 1)
	check(bottom >= 0 and absf(bottom - float(ref.ground)) <= 2.0, "实际不透明鞋底距地面锚最多两个源像素：%s/%d" % [key, bottom])
	var registration: Dictionary = manifest.get("runtime_registration", {})
	check(registration.get("target_body_height_px") == 448 and absf(float(ref.ground) - ref.crown.y - 448.0) < 0.001, "独立像素校准符合已登记448px固定本体：" + key)
	return ref

func _check_battle_scale(hd: Node2D, definition: Dictionary, key: String) -> void:
	var scale_before: Vector2 = hd.animator.scale
	for animation in definition.frames.get_animation_names():
		# 先回有效帧，避免animation_changed回调读到上段长动画的越界帧号。
		hd.animator.sprite.frame = 0
		hd.animator.sprite.animation = animation
		for frame in definition.frames.get_frame_count(animation):
			hd.animator.sprite.frame = frame
			check(hd.animator.scale == scale_before, "战斗所有已载帧不重新fit：%s/%s/%d" % [key, animation, frame])
	hd.animator.sprite.frame = 0; hd.animator.sprite.animation = "idle"

func _world_pixel_y(player: Node3D, logical_y: float) -> float:
	return _sprite_pixel_y(player.billboard, logical_y)

func _sprite_pixel_y(body: Sprite3D, logical_y: float) -> float:
	var rect: Rect2 = body.get_meta("logical_frame_rect")
	return (body.texture.get_height() * 0.5 - (logical_y - rect.position.y) + body.offset.y) * body.pixel_size

func _check_world_scale(player: Node3D, definition: Dictionary, key: String) -> void:
	var fixed_pixel_size: float = player.billboard.pixel_size
	var anchor_y: float = definition.manifest.canvas.anchor[1]
	for animation in definition.frames.get_animation_names():
		player.animator.sprite.frame = 0
		player.animator.sprite.animation = animation
		for frame in definition.frames.get_frame_count(animation):
			player.animator.sprite.frame = frame
			player._sync_direct_frame()
			check(is_equal_approx(player.billboard.pixel_size, fixed_pixel_size) and absf(_world_pixel_y(player, anchor_y)) < 0.00001, "探索每帧紧凑图集保持比例/脚锚：%s/%s/%d" % [key, animation, frame])
	player.animator.sprite.frame = 0; player.animator.sprite.animation = "idle"; player._sync_direct_frame()
func _setup_world(world: Node3D) -> void:
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 3.2
	camera.position = Vector3(0, 1.2, 7); world.add_child(camera); camera.look_at(Vector3(0, 0.85, 0)); camera.current = true
	var floor := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(16, 16); floor.mesh = plane
	var material := StandardMaterial3D.new(); material.albedo_color = Color(0.22, 0.23, 0.27); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; floor.material_override = material; world.add_child(floor)
	var grid := MeshInstance3D.new(); var box := BoxMesh.new(); box.size = Vector3(8, 0.012, 0.012); grid.mesh = box; grid.position = Vector3(0, 0, 0.02)
	var line_material := StandardMaterial3D.new(); line_material.albedo_color = Color(0.95, 0.8, 0.42); line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; grid.material_override = line_material; world.add_child(grid)
	var environment := WorldEnvironment.new(); var settings := Environment.new(); settings.background_mode = Environment.BG_COLOR; settings.background_color = Color(0.08, 0.09, 0.12); environment.environment = settings; world.add_child(environment)
func _save(name: String) -> void:
	await process_frame; await RenderingServer.frame_post_draw
	check(root.get_viewport().get_texture().get_image().save_png(OS.get_environment("CAMPAIGN_PRESENTATION_OUTPUT").path_join(name)) == OK, "真实身高画面：" + name)
