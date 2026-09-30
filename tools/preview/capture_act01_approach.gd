# 需要可用图形显示；headless 使用 dummy 驱动，不能生成真实渲染截图。
# Godot --path . --script res://tools/preview/capture_act01_approach.gd
extends SceneTree

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("需要图形显示，请去掉 --headless 后运行。")
		quit(1)
		return
	# 独立 1920×1080 视口不受窗口管理器尺寸限制影响。
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var preview := load("res://scenes/preview/act01_approach_3d.tscn").instantiate() as Node3D
	viewport.add_child(preview)
	await create_timer(1.0).timeout
	await _save(viewport, "hero.png")
	preview.toggle_hud()
	await _save(viewport, "hero_clean.png")
	preview.show_view(true)
	await _save(viewport, "inspection.png")
	preview.reset_preview()
	preview.toggle_hud()
	preview.toggle_character()
	await _save(viewport, "character_scale.png")
	preview.queue_free()
	viewport.queue_free()
	await process_frame
	quit(0)

func _save(viewport: SubViewport, filename: String) -> void:
	for frame in range(3):
		await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var path := "res://docs/reference/act01_approach_3d/" + filename
	var error := image.save_png(path)
	if error != OK:
		printerr("截图保存失败：%s / %s" % [path, error])
		quit(1)
		return
	print("ACT01_CAPTURE: %s %s" % [path, image.get_size()])
