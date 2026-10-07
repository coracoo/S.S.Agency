# 真实 Sprite3D 快照：只验证已选源帧，不生成/重绘人物像素。
extends SceneTree

const HELPER_PATH := "res://scripts/characters/snapshot_ghost_trail.gd"
var assertions := 0
var failures := 0
var proof := {"kind":"headless_behavioral_inspection", "rendered_proof":false, "engine":Engine.get_version_info().string, "cases":[]}
var helper_script: Script

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		print("FAIL: " + message)

func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	check(ResourceLoader.exists(HELPER_PATH), "存在独立的真实源帧残影组件")
	if ResourceLoader.exists(HELPER_PATH):
		helper_script = load(HELPER_PATH)
		await _test_frozen_pose()
		await _test_asymmetric_anchor()
		_test_limits_and_fade()
		await _test_lifetimes()
		await _test_scene_exit()
		await _test_automatic_timeout()
		_test_invalid_capture()
	var output := OS.get_environment("SNAPSHOT_GHOST_PROOF")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		check(file != null, "可写入独立无头检查凭据")
		proof["assertions"] = assertions
		proof["failures"] = failures
		if file != null: file.store_string(JSON.stringify(proof, "\t") + "\n")
	print("SNAPSHOT_GHOST_TRAIL: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)

func _source() -> AtlasTexture:
	var page := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	page.fill(Color.MAGENTA)
	for y in 5:
		for x in 4:
			page.set_pixel(x + 2, y + 3, Color(float(x) / 4, float(y) / 5, .35, float((x + y) % 4) / 3))
	var texture := AtlasTexture.new()
	texture.atlas = ImageTexture.create_from_image(page)
	texture.region = Rect2(2, 3, 4, 5)
	texture.margin = Rect2(6, 4, 16, 7)
	texture.filter_clip = true
	return texture

func _trail(actor_id: String = "rinne") -> Node3D:
	var trail: Node3D = helper_script.new()
	root.add_child(trail)
	trail.bind_actor(actor_id)
	trail.set_process(false)
	return trail

func _test_frozen_pose() -> void:
	var source := _source()
	var trail := _trail()
	var live := Node3D.new()
	root.add_child(live)
	live.transform = Transform3D(Basis(Vector3.UP, .4).scaled(Vector3(1.2, 1.1, 1)), Vector3(4, .7, -2))
	var at := live.global_transform
	var ghost: Sprite3D = trail.capture(source, Vector2(7, 10), at, .017, true, Color(.4, .7, 1, .75))
	check(ghost != null, "绑定演员后可以快照当前源帧")
	if ghost == null: trail.free(); live.free(); return
	var snapshot := ghost.texture as AtlasTexture
	var pixels := snapshot.get_image().get_data()
	check(snapshot != source and snapshot.atlas == source.atlas, "复制轻量帧视图、共享底图而不拷贝像素")
	check(snapshot.margin == Rect2() and snapshot.region == source.region and snapshot.filter_clip, "完整保留裁片及采样边界，去掉逻辑空白")
	check(pixels == source.atlas.get_image().get_region(Rect2i(source.region)).get_data(), "原姿态所有 RGBA 字节保持一致")
	check(ghost.global_transform.is_equal_approx(at.scaled_local(Vector3.ONE * 1.05)), "只围绕固定世界脚根放大 1.05 倍")
	check(ghost.flip_h and is_equal_approx(ghost.pixel_size, .017), "保存当前朝向和像素密度")
	check(ghost.modulate.is_equal_approx(Color(.4, .7, 1, .135)), "保存源 RGB 染色并叠加低透明度")
	check(not ghost.no_depth_test and ghost.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "残影保留深度测试且不额外投影")
	var frozen_offset := ghost.offset
	source.region = Rect2(11, 1, 7, 3)
	source.margin = Rect2(2, 1, 13, 9)
	source.atlas = _source().atlas
	live.position += Vector3(6, 0, -3)
	trail.position += Vector3(8, 2, 1)
	await process_frame
	check(snapshot.region == Rect2(2, 3, 4, 5) and snapshot.get_image().get_data() == pixels, "后续帧/region/图集变更不改变已拍姿态")
	check(ghost.offset == frozen_offset and ghost.global_transform.is_equal_approx(at.scaled_local(Vector3.ONE * 1.05)), "演员及父节点继续移动时残影仍留在拍摄脚根")
	proof.cases.append({"case":"frozen_pose", "source_region_after":str(source.region), "ghost_region":str(snapshot.region), "captured_root":str(at.origin), "ghost_root":str(ghost.global_position), "offset":str(ghost.offset), "alpha":ghost.modulate.a})
	trail.free()
	live.free()

func _test_asymmetric_anchor() -> void:
	var source := _source()
	for flipped in [false, true]:
		for anchor in [Vector2(7, 10), Vector2(13, 10)]:
			var trail := _trail()
			var world_root := Transform3D(Basis.IDENTITY, Vector3(3, 0, 5))
			var ghost: Sprite3D = trail.capture(source, anchor, world_root, .02, flipped)
			ghost.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			await process_frame
			await process_frame
			var left: float = (20 - 6 - 4 if flipped else 6) - anchor.x
			var expected := AABB(Vector3(left, anchor.y - 4 - 5, 0) * .02, Vector3(4, 5, 0) * .02)
			check(ghost.get_aabb().is_equal_approx(expected), "实际 Sprite3D 裁片包围盒以非对称逻辑脚锚正确镜像")
			for y in 5:
				for x in 4:
					var logical := Vector2(6 + x + .5, 4 + y + .5)
					var expected_local := Vector3((20 - logical.x if flipped else logical.x) - anchor.x, anchor.y - logical.y, 0) * .02
					var actual_local := Vector3((4 - x - .5 if flipped else x + .5) - 2 + ghost.offset.x, 2.5 - y - .5 + ghost.offset.y, 0) * .02
					check(actual_local.is_equal_approx(expected_local), "每个裁片像素均保持原画布和翻转锚点映射")
			check(ghost.global_transform.origin == world_root.origin, "放大不会移动地面脚根")
			trail.free()

func _test_limits_and_fade() -> void:
	var source := _source()
	for maximum in [-3, 3, 4, 999]:
		var trail := _trail()
		trail.max_ghosts = maximum
		var first: Sprite3D = trail.capture(source, Vector2(7, 10), Transform3D.IDENTITY, .02)
		for index in 8: trail.capture(source, Vector2(7, 10), Transform3D(Basis.IDENTITY, Vector3(index, 0, 0)), .02)
		check(trail.active_count() == clampi(maximum, 3, 4), "每演员最多 3–4 个存活快照")
		check(first.texture == null and not first.visible, "超过上限立即清空最老残影纹理和显示")
		trail.free()
	for requested in [-10.0, 10.0]:
		var trail := _trail()
		trail.ghost_alpha = requested
		trail.ghost_scale = requested
		trail.lifetime = requested
		var ghost: Sprite3D = trail.capture(source, Vector2(7, 10), Transform3D.IDENTITY, .02)
		var life: float = clampf(requested, .12, .20)
		var alpha: float = clampf(requested, .12, .24)
		check(is_equal_approx(ghost.modulate.a, alpha), "初始透明度硬限制在 .12–.24")
		check(ghost.scale.is_equal_approx(Vector3.ONE * clampf(requested, 1.03, 1.08)), "放大倍率硬限制在 1.03–1.08")
		trail._process(life * .5)
		check(is_equal_approx(ghost.modulate.a, alpha * .5), "生命周期一半时透明度平滑减半")
		check(ghost.global_position == Vector3.ZERO, "淡出过程不产生脚根漂移")
		trail._process(life * .51)
		check(trail.active_count() == 0 and ghost.texture == null and not ghost.visible, ".12–.20 秒内结束且立即释放纹理")
		trail.free()

func _test_lifetimes() -> void:
	for mode in ["timeout", "cancel", "rebind", "same_actor_rebind"]:
		var trail := _trail()
		var source := _source()
		var weak_page: WeakRef = weakref(source.atlas)
		var weak_source: WeakRef = weakref(source)
		var ghost: Sprite3D = trail.capture(source, Vector2(7, 10), Transform3D.IDENTITY, .02)
		var weak_view: WeakRef = weakref(ghost.texture)
		source = null
		check(weak_source.get_ref() == null, "快照不保留原动画帧资源：" + mode)
		check(weak_page.get_ref() != null, "快照存活期间保留需要的共享页：" + mode)
		if mode == "timeout": trail._process(.25)
		elif mode == "cancel": trail.cancel()
		else: trail.bind_actor("rinne" if mode == "same_actor_rebind" else "guard")
		check(trail.active_count() == 0 and not trail.is_processing(), "结束/取消/重新绑定清空队列并停止处理：" + mode)
		check(weak_view.get_ref() == null and weak_page.get_ref() == null, "无全局缓存遗留的纹理引用：" + mode)
		await process_frame
		check(not is_instance_valid(ghost), "清理完实际残影节点：" + mode)
		trail.free()
	var first := _trail("rinne")
	var second := _trail("guard")
	var source := _source()
	var a: Sprite3D = first.capture(source, Vector2(7, 10), Transform3D.IDENTITY, .02)
	var b: Sprite3D = second.capture(source, Vector2(7, 10), Transform3D.IDENTITY, .02)
	check(a.texture != b.texture, "不同演员不共享可变帧视图或残影缓存")
	first.cancel()
	check(second.active_count() == 1 and b.texture != null, "取消一个演员不清理另一演员")
	first.free(); second.free()

func _test_scene_exit() -> void:
	var trail := _trail()
	var source := _source()
	var page: WeakRef = weakref(source.atlas)
	var ghost: Sprite3D = trail.capture(source, Vector2(7, 10), Transform3D.IDENTITY, .02)
	source = null
	root.remove_child(trail)
	check(trail.active_count() == 0 and page.get_ref() == null, "退出场景当下释放所有页引用")
	await process_frame
	check(not is_instance_valid(ghost), "退出树也会释放残影节点")
	root.add_child(trail)
	check(trail.capture(_source(), Vector2(7, 10), Transform3D.IDENTITY, .02) == null, "离开场景后必须重新绑定演员")
	trail.free()

func _test_automatic_timeout() -> void:
	var trail := _trail()
	trail.capture(_source(), Vector2(7, 10), Transform3D.IDENTITY, .02)
	check(trail.is_processing(), "捕捉后自动启用处理，无需调用方手动计时")
	for tick in 15: await process_frame
	check(trail.active_count() == 0 and not trail.is_processing(), "真实引擎 tick 自动淡出并停止空闲处理")
	trail.free()

func _test_invalid_capture() -> void:
	var trail: Node3D = helper_script.new()
	root.add_child(trail)
	check(trail.capture(_source(), Vector2.ZERO, Transform3D.IDENTITY, .02) == null, "未绑定演员不产生残影")
	trail.bind_actor("rinne")
	check(trail.capture(null, Vector2.ZERO, Transform3D.IDENTITY, .02) == null, "缺失源纹理不产生残影")
	check(trail.capture(_source(), Vector2.ZERO, Transform3D.IDENTITY, 0) == null, "无效像素密度不产生残影")
	var viewport_texture := ViewportTexture.new()
	var animated_texture := AnimatedTexture.new()
	check(trail.capture(viewport_texture, Vector2.ZERO, Transform3D.IDENTITY, .02) == null, "拒绝会继续更新的视口纹理")
	check(trail.capture(animated_texture, Vector2.ZERO, Transform3D.IDENTITY, .02) == null, "拒绝会继续更新的动画纹理")
	var static_texture: Texture2D = _source().atlas
	var ghost: Sprite3D = trail.capture(static_texture, Vector2(8, 15), Transform3D.IDENTITY, .02)
	check(ghost.texture == static_texture and ghost.offset == Vector2(8, 7), "普通静态纹理也保持当前图像与逻辑脚锚")
	trail.free()
