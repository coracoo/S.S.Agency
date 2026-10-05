# 身高关系从真实人物像素参考点与节点变换测量，不能只比JSON数字。
extends SceneTree
const Bundle = preload("res://scripts/characters/party_asset_bundle.gd")
const Player = preload("res://scripts/exploration_3d/player_controller.gd")
const View = preload("res://scripts/rpg/ui/battle_view.gd")
const Session = preload("res://scripts/campaign/chapter_session.gd")
const REFERENCES := {"rinne": {"crown": Vector2(665, 64), "sole": Vector2(600, 1082), "ground": 1083.0}, "mint": {"crown": Vector2(616, 50), "sole": Vector2(650, 1062), "ground": 1063.0}, "guard": {"crown": Vector2(565, 97), "sole": Vector2(744, 1122), "ground": 1123.0}, "homura_mage": {"crown": Vector2(500, 48), "sole": Vector2(606, 1055), "ground": 1056.0}, "homura_sword": {"crown": Vector2(821, 90), "sole": Vector2(645, 1066), "ground": 1067.0}}
var failures: Array[String] = []
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(1); return
	_run.call_deferred()
func _run() -> void:
	check(FileAccess.file_exists("res://data/characters/stature.json"), "独立可配置六身份物理身高资料")
	var session := Session.new()
	check(session.start_new(true).ok and (await session.prepare_assets()).ok, "身高测试真实默认三人正式会话")
	for event in ["dialogue:a1", "dialogue:r1", "dialogue:h1"]: session.commit_event(session.campaign.safe_snapshot().world, event)
	check(session.begin_encounter(session.campaign.safe_snapshot().world, "basin_reflection").ok, "真实正式战斗用于像素测量")
	var view := View.new(); view.router = session.router; root.add_child(view)
	var measured: Dictionary = {}
	var feet: Dictionary = {}
	var world_measured: Dictionary = {}
	var actors_3d: Dictionary = {}
	var world := Node3D.new(); root.add_child(world)
	for index in 3:
		var identity: String = ["rinne", "mint", "guard"][index]
		var actor_id: String = ["p_swordsman", "p_ranger", "p_guard"][index]
		var definition: Dictionary = session.bundle.get_definition(identity)
		var ref: Dictionary = REFERENCES[identity]
		var image: Image = definition.frames.get_frame_texture("idle", 0).get_image()
		check(image.get_pixelv(Vector2i(ref.crown)).a >= 0.5 and image.get_pixelv(Vector2i(ref.sole)).a >= 0.5, "头顶与鞋底参考点落在真实原PNG主体：" + identity)
		var hd: Node2D = view._hd_views[actor_id]
		var crown_y: float = hd.animator.to_global(ref.crown).y
		var foot_y: float = hd.animator.to_global(Vector2(ref.sole.x, ref.ground)).y
		measured[identity] = foot_y - crown_y
		feet[identity] = foot_y
		var fixed_scale: Vector2 = hd.animator.scale
		for animation in ["idle", "walk", "attack"]:
			hd.animator.sprite.animation = animation
			for frame in definition.frames.get_frame_count(animation):
				hd.animator.sprite.frame = frame
				check(hd.animator.scale == fixed_scale, "战斗帧不重新fit比例：%s/%s/%d" % [identity, animation, frame])
		hd.animator.sprite.animation = "idle"; hd.animator.sprite.frame = 0
		var player := Player.new(); player.shared_definition = definition; player.input_enabled = false; world.add_child(player)
		player.process_mode = Node.PROCESS_MODE_DISABLED
		player.position = Vector3((index - 1) * 1.55, 0, 0)
		actors_3d[identity] = player
		var image_top: float = (float(definition.manifest.canvas.h) / 2.0 - ref.crown.y + player.billboard.offset.y) * player.billboard.pixel_size
		var image_ground: float = (float(definition.manifest.canvas.h) / 2.0 - ref.ground + player.billboard.offset.y) * player.billboard.pixel_size
		world_measured[identity] = image_top - image_ground
		check(absf(image_ground) < 0.00001, "探索鞋底同在角色根节点地面：" + identity)
		var fixed_pixel_size: float = player.billboard.pixel_size
		for animation in ["idle", "walk", "attack"]:
			player.animator.sprite.animation = animation
			for frame in definition.frames.get_frame_count(animation):
				player.animator.sprite.frame = frame
				check(is_equal_approx(player.billboard.pixel_size, fixed_pixel_size), "探索帧不改变米/像素：%s/%s/%d" % [identity, animation, frame])
		player.animator.sprite.animation = "idle"; player.animator.sprite.frame = 0
		print("HEIGHT_MEASURED:", identity, ":battle_px=", measured[identity], ":feet_y=", feet[identity], ":world_m=", world_measured[identity])
	check(measured.mint < measured.rinne and measured.guard > measured.rinne, "真实战斗本体像素：薄荷矮于凛音，岑照高于凛音")
	check(absf(feet.mint - feet.rinne) < 0.001 and absf(feet.guard - feet.rinne) < 0.001, "三人鞋底统一地面基线，而非槽位各自fit")
	check(absf(world_measured.rinne - 1.68) < 0.001 and absf(world_measured.mint - 1.58) < 0.001 and absf(world_measured.guard - 1.86) < 0.001, "真实原像素节点量得168/158/186cm本体身高")
	check(world_measured.mint < world_measured.rinne and world_measured.guard > world_measured.rinne, "真实探索本体米数同样矮/中/高")
	var ppm: float = measured.rinne / world_measured.rinne
	check(absf(measured.mint / world_measured.mint - ppm) < 0.001 and absf(measured.guard / world_measured.guard - ppm) < 0.001, "探索米数与战斗像素共享同一物理基准")
	if ResourceLoader.exists("res://scripts/characters/character_stature.gd"):
		var Stature = load("res://scripts/characters/character_stature.gd")
		var Def = load("res://scripts/characters/pixel_character_definition.gd")
		var mage: Dictionary = Def.load_definition(Bundle.MANIFESTS.homura_mage)
		var sword: Dictionary = Def.load_definition(Bundle.MANIFESTS.homura_sword)
		var a: float = (REFERENCES.homura_mage.ground - REFERENCES.homura_mage.crown.y) * Stature.world_pixel_size(mage)
		var b: float = (REFERENCES.homura_sword.ground - REFERENCES.homura_sword.crown.y) * Stature.world_pixel_size(sword)
		check(absf(a - b) < 0.00001, "焰华不同画布/头发/武器下，两形态本体同身高")
		var Hd = load("res://scripts/rpg/ui/hd_actor_view.gd")
		var dual_heights: Array[float] = []
		for entry in [{"key": "homura_mage", "definition": mage}, {"key": "homura_sword", "definition": sword}]:
			var hd = Hd.new(); root.add_child(hd)
			check(hd.configure(entry.definition, Stature.battle_body_height("homura"), -1), "焰华实际高清节点可按同身高配置：" + entry.key)
			var ref: Dictionary = REFERENCES[entry.key]
			dual_heights.append(hd.animator.to_global(Vector2(ref.sole.x, ref.ground)).y - hd.animator.to_global(ref.crown).y)
			check(absf(hd.animator.to_global(Vector2(ref.sole.x, ref.ground)).y) < 0.001, "焰华各形态真实鞋底同地面")
			hd.free()
		check(absf(dual_heights[0] - dual_heights[1]) < 0.001 and absf(dual_heights[0] - 323.0) < 0.001, "焰华实际两高清节点本体同为170cm/323px")
	else: check(false, "探索与战斗共享身高helper")
	if not OS.get_environment("CAMPAIGN_PRESENTATION_OUTPUT").is_empty():
		view._cancel_presentation(); view._render(); await _save("battle_three_character_statures.png")
		view.hide(); _setup_world(world)
		for identity in actors_3d:
			var actor_label := Label3D.new(); actor_label.text = {"rinne": "凛音 168cm", "mint": "薄荷 158cm", "guard": "岑照 186cm"}[identity]; actor_label.font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf"); actor_label.font_size = 42; actor_label.pixel_size = 0.003; actor_label.no_depth_test = true
			world.add_child(actor_label); actor_label.position = actors_3d[identity].position + Vector3(0, -0.18, 0.08)
		await _save("exploration_three_character_statures.png")
	view.free(); world.free(); session.close()
	for failure in failures: printerr("ASSERT FAIL: ", failure)
	print("CHARACTER STATURE: ", assertions, " assertions, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
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
