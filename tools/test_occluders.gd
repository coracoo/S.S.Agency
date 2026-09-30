extends SceneTree
## 遮挡体可见性无头自检：不同玩家 x 下逐遮挡体打印 visible + 脚点高度
func _initialize() -> void:
	var scene = load("res://scenes/v3/stage.tscn").instantiate()
	root.add_child.call_deferred(scene)
	await process_frame
	await process_frame
	await process_frame
	for px in [1200.0, 1300.0, 1350.0, 1380.0, 1410.0, 1450.0]:
		scene._player_x = px
		scene._update_player_transform(0.016)
		scene._update_occluders()
		var vis: Array = []
		for occ in scene._occluders:
			vis.append((occ["sprite"] as Sprite2D).visible)
		print("OCCCHK px=", px, " feet=", scene._ground_y(px),
				" base/xrange=", scene._occluders.map(func(o): return [o["base_y"], o["xmin"], o["xmax"]]), " vis=", vis)
	quit()
