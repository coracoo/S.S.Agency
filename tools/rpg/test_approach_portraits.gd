# 新试玩的所有人物显示面统一取已批准高清帧；旧对白默认行为不被重映射。
extends RefCounted
const F = preload("res://tools/rpg/fixtures.gd")
const Session = preload("res://scripts/exploration_3d/approach_session.gd")
const Overlay = preload("res://scripts/ui/dialogue_overlay.gd")
const Profile = preload("res://scripts/exploration_3d/trial_profile.gd")
static func run() -> Array[String]:
	var failures: Array[String] = []
	var source := "res://scripts/characters/identity_portraits.gd"
	F.expect(FileAccess.file_exists(source), "缺少高清人物立绘统一来源", failures)
	if not failures.is_empty(): return failures
	var Portraits = load(source)
	_test_bad_manifest(Portraits, failures)
	F.expect(Portraits.identity_for_speaker("hakuyo") == "mint" and Portraits.identity_for_speaker("rinne") == "rinne", "旧speaker按试玩身份显式映射", failures)
	var bundle := preload("res://scripts/characters/party_asset_bundle.gd").new()
	F.expect((await bundle.prepare(Profile.BINDINGS)).ok, "立绘采用三人共享bundle", failures)
	for id in ["rinne", "mint", "guard"]:
		var definition: Dictionary = bundle.get_definition(id)
		var approved: Dictionary = Portraits.load_idle_definition(id)
		F.expect(approved.ok and approved.manifest.dir == "res://assets/chars/pixel/%s/high_detail_complete/frames/" % id, "UI仍严格使用同身份批准静态立绘：" + id, failures)
		for kind in ["portrait", "avatar"]:
			var art: Dictionary = Portraits.from_definition(definition, id, kind)
			F.expect(art.ok and art.texture is AtlasTexture and art.texture.atlas.get_rid() == approved.frames.get_frame_texture("idle", 0).get_rid(), "立绘/头像共享批准静态原图，独立于视频身体图集：" + id + "/" + kind, failures)
			F.expect(Rect2(Vector2.ZERO, art.texture.atlas.get_size()).encloses(art.texture.region) and art.source_path.contains("high_detail_complete/frames/"), "裁切只取新帧内部，不回落旧图", failures)
	F.expect(not Portraits.from_definition({}, "rinne", "portrait").ok, "缺新图时明确失败，不伪装旧图成功", failures)
	var tree: SceneTree = Engine.get_main_loop()
	var overlay = Overlay.new()
	tree.root.add_child(overlay)
	F.expect(overlay.portrait_provider == Callable(), "旧Overlay默认仍走原portrait字段", failures)
	overlay.portrait_provider = func(speaker: String): return Portraits.from_definition(bundle.get_definition(Portraits.identity_for_speaker(speaker)), Portraits.identity_for_speaker(speaker), "portrait")
	var nodes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogues.json")).stages.test_approach.nodes
	overlay._nodes = nodes
	overlay._present_node("a1")
	F.expect(overlay._portraits.left.path == "identity:rinne:portrait" and overlay._portraits.left.tex.atlas.get_rid() == Portraits.load_idle_definition("rinne").frames.get_frame_texture("idle", 0).get_rid(), "真实对白凛音使用批准静态原图上身", failures)
	overlay._present_node("a2")
	F.expect(overlay._portraits.right.path == "identity:mint:portrait" and overlay._portraits.right.ctrl.flip_h, "真实对白薄荷用新HD并朝向对话中央", failures)
	overlay.portrait_provider = func(_speaker: String): return {"ok": false, "error": "missing approved art"}
	overlay._present_node("a1")
	F.expect(overlay._portraits.left.tex == null and not overlay.portrait_error.is_empty(), "坏新图不会隐式加载旧半身", failures)
	overlay.abort()
	overlay.queue_free()
	await tree.process_frame
	var title = preload("res://scenes/v3/title.tscn").instantiate()
	tree.root.add_child(title)
	F.expect(title._bg_stage._player.get_meta("identity_id", "") == "rinne" and title._bg_stage._anim_manifest.get("id") == "rinne_high_detail_complete", "真实标题活背景也使用已选新凛音", failures)
	title.queue_free()
	await tree.process_frame
	bundle.clear()
	return failures

static func _test_bad_manifest(Portraits, failures: Array[String]) -> void:
	F.expect(Portraits.has_method("from_idle_manifest"), "标题清单有可测试的严格类型边界", failures)
	if not Portraits.has_method("from_idle_manifest"): return
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/chars/pixel/rinne/high_detail_complete/manifest.json"))
	for field in ["w", "h", "content_height_px", "height_m", "anchor"]:
		var bad := good.duplicate(true)
		bad.canvas.erase(field)
		F.expect(not Portraits.from_idle_manifest(bad, "rinne").ok, "缺少标题画布字段安全拒绝：" + field, failures)
	for canvas in [{"w": NAN}, {"w": 0}, {"h": "1152"}, {"anchor": [INF, 1]}, {"anchor": [1]}, {"w": 9000}]:
		var bad := good.duplicate(true)
		bad.canvas.merge(canvas, true)
		F.expect(not Portraits.from_idle_manifest(bad, "rinne").ok, "标题画布坏数值安全拒绝", failures)
	for malformed in ["bad", [], null]:
		var bad := good.duplicate(true)
		bad.anims = malformed
		F.expect(not Portraits.from_idle_manifest(bad, "rinne").ok, "坏anims类型安全拒绝", failures)
	for field in ["frames", "durations_ms"]:
		for value in [[null], [NAN], ["../outside"], [true]]:
			var bad := good.duplicate(true)
			bad.anims.idle.frames = ["idle1"]
			bad.anims.idle.durations_ms = [100]
			bad.anims.idle[field] = value
			F.expect(not Portraits.from_idle_manifest(bad, "rinne").ok, "坏待机元素不崩溃：" + field, failures)
	F.expect(not Portraits.from_definition({"ok": true, "frames": SpriteFrames.new(), "manifest": "bad"}, "rinne", "portrait").ok, "坏立绘定义不会类型崩溃", failures)
