extends RefCounted
const F = preload("res://tools/rpg/fixtures.gd")
const A = preload("res://tools/rpg/approach_fixtures.gd")
static func run() -> Array[String]:
	var failures: Array[String] = []
	for file in ["player_controller", "camera_rig", "approach_stage"]:
		F.expect(FileAccess.file_exists("res://scripts/exploration_3d/%s.gd" % file), "缺少参道空间接口：" + file, failures)
	if not failures.is_empty(): return failures
	var tree: SceneTree = Engine.get_main_loop()
	var Stage = load("res://scripts/exploration_3d/approach_stage.gd")
	var stage = Stage.new()
	tree.root.add_child(stage)
	await _frames(tree, 5)
	var actor = stage.player
	actor.set_camera_basis(Basis.IDENTITY)
	actor.position = Vector3(-4, 0.08, 0)
	actor.set_move_input(Vector2.RIGHT)
	await _frames(tree, 25)
	F.expect(actor.position.x > -3.5, "真实四向右移", failures)
	var straight_speed: float = Vector2(actor.velocity.x, actor.velocity.z).length()
	actor.set_move_input(Vector2(1, 1))
	await _frames(tree, 2)
	var diagonal_speed: float = Vector2(actor.velocity.x, actor.velocity.z).length()
	F.expect(absf(diagonal_speed - straight_speed) < 0.02, "斜向移动不加速", failures)
	actor.set_move_input(Vector2.LEFT)
	await _frames(tree, 15)
	F.expect(actor.facing == -1, "横向切换朝向", failures)
	var previous_facing: int = actor.facing
	var before: Vector3 = actor.position
	actor.set_move_input(Vector2(0, 1))
	await _frames(tree, 25)
	F.expect(actor.position.z - before.z > 0.5 and actor.facing == previous_facing, "纵深移动且保持左右朝向", failures)
	before = actor.position
	actor.set_move_input(Vector2(0, -1))
	await _frames(tree, 30)
	F.expect(before.z - actor.position.z > 0.5, "真实向后移动", failures)
	stage.set_controls_enabled(false)
	before = actor.position
	actor.set_move_input(Vector2.RIGHT)
	await _frames(tree, 8)
	F.expect(absf(actor.position.x - before.x) < 0.001, "关闭控制清空移动", failures)
	actor.keyboard_input = true
	Input.action_press("approach_right")
	stage.set_controls_enabled(true)
	before = actor.position
	await _frames(tree, 6)
	F.expect(absf(actor.position.x - before.x) < 0.001, "跨对白持续按住移动键须先松开", failures)
	Input.action_release("approach_right")
	await _frames(tree, 2)
	Input.action_press("approach_right")
	await _frames(tree, 8)
	F.expect(actor.position.x > before.x + 0.1, "松开再按移动恢复", failures)
	Input.action_release("approach_right")
	actor.position = Vector3(-0.5, 0.1, 0)
	actor.velocity = Vector3.ZERO
	actor.set_move_input(Vector2.RIGHT)
	await _frames(tree, 230)
	F.expect(actor.position.x > 8 and actor.position.y > 2.7 and actor.is_on_floor(), "整段坡面衔接上平台", failures)
	actor.set_move_input(Vector2.RIGHT)
	await _frames(tree, 90)
	F.expect(actor.position.x <= 9.45, "右边界不得超出可见平台 x=9.695", failures)
	actor.set_move_input(Vector2(0, 1))
	await _frames(tree, 80)
	F.expect(actor.position.z <= 0.84, "上平台前边界不得超出可见石板 z=1.025", failures)
	actor.position.z = 0.0
	actor.set_move_input(Vector2.LEFT)
	await _frames(tree, 240)
	F.expect(actor.position.x < 0 and actor.position.y < 0.15 and actor.is_on_floor(), "下坡连续回平地", failures)
	actor.position = Vector3(-4, 0.1, 0)
	actor.velocity = Vector3.ZERO
	actor.set_move_input(Vector2(0, 1))
	await _frames(tree, 150)
	F.expect(actor.position.z < 2.2 and actor.is_on_floor(), "前边界不坠落", failures)
	F.expect(actor.animator.sprite.animation == &"idle", "抵墙实际不动回待机", failures)
	actor.set_move_input(Vector2(0, -1))
	await _frames(tree, 150)
	F.expect(actor.position.z > -1.2 and actor.is_on_floor(), "后边界不坠落", failures)
	actor.position = Vector3(-8, 0.08, 0.5)
	actor.set_move_input(Vector2.LEFT)
	await _frames(tree, 90)
	F.expect(actor.position.x >= -8.85, "左边界不得越过可见石路 x=-9.19", failures)
	actor.position = Vector3(0.1, 0.1, 0.1)
	actor.velocity = Vector3.ZERO
	actor.set_move_input(Vector2(0, 1))
	await _frames(tree, 70)
	F.expect(actor.position.z < 1.05, "水钵器物真实阻挡", failures)
	actor.set_move_input(Vector2.ZERO)
	await _frames(tree, 3)
	var world: Dictionary = stage.export_world()
	world.event_flags = {"approach_entered": true}
	world.dlg_fired = {"a1": true}
	var restored: Dictionary = stage.restore_world(world)
	F.expect(restored.ok and not restored.used_fallback and stage.export_world().position == world.position and stage.camera_rig.snapshot() == world.camera, "合法位置镜头精确恢复", failures)
	var bad := world.duplicate(true)
	bad.scene_id = "other"
	F.expect(not stage.restore_world(bad).ok, "拒绝其他场景快照", failures)
	bad = world.duplicate(true)
	bad.position = [NAN, 0, 0]
	F.expect(not stage.restore_world(bad).ok, "非法数值不可回退伪装合法", failures)
	bad = world.duplicate(true)
	bad.position = [100, 100, 100]
	bad.player_x = 100
	var fallback: Dictionary = stage.restore_world(bad)
	F.expect(fallback.ok and fallback.used_fallback and stage.export_world().event_flags == world.event_flags, "合法但不可达位置回锚点保留剧情", failures)
	F.expect(str(actor.animator.definition.manifest.dir).contains("high_detail_complete"), "实际读取高清帧清单", failures)
	stage.queue_free()
	await tree.process_frame
	return failures
static func _frames(tree: SceneTree, count: int) -> void:
	for index in range(count):
		await tree.physics_frame
		await tree.process_frame
