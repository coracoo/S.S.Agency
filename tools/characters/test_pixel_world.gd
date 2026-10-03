extends SceneTree
var failed := 0
func check(value: bool, message: String) -> void:
	print(('PASS: ' if value else 'FAIL: ') + message)
	if not value: failed += 1
func _initialize() -> void: call_deferred('run')
func run() -> void:
	if not FileAccess.file_exists('res://scenes/preview/friendly_pixel_playground.tscn'):
		check(false, '可操作角色参道场景尚未实现')
		quit(1)
		return
	var scene = load('res://scenes/preview/friendly_pixel_playground.tscn').instantiate()
	root.add_child(scene)
	await process_frame
	var hidden_actor = load('res://scripts/characters/pixel_character_world.gd').new()
	hidden_actor.visible = false
	scene.add_child(hidden_actor)
	check(hidden_actor.composite.render_target_update_mode == SubViewport.UPDATE_DISABLED, '初始隐藏的角色不刷新viewport')
	hidden_actor.queue_free()
	var actor = scene.actor
	check(actor != null and actor is CharacterBody3D, '真正3D碰撞角色')
	check(actor.select_form('legacy_rinne'), '显式原帧基线可用')
	actor.set_input_enabled(false)
	for i in 25: await physics_frame
	check(actor.is_on_floor(), '胶囊接地')
	var original: Vector3 = actor.position
	actor.motion_axis = 1.0
	for i in 30: await physics_frame
	check(actor.position.x > original.x + 0.5, '真实物理行走')
	actor.motion_axis = 0
	for i in 4: await physics_frame
	check(actor.animator.sprite.animation == 'idle', '停止后回待机')
	actor.animator.request_action('attack')
	original = actor.position
	actor.motion_axis = 1
	for i in 8: await physics_frame
	check(absf(actor.position.x - original.x) < 0.001, '攻击锁实际位移')
	for i in 35: await physics_frame
	check(actor.position.x > original.x, '攻击结束恢复真实移动')
	actor.motion_axis = 0
	actor.position = Vector3(4.5, 3.0, 0)
	actor.velocity = Vector3.ZERO
	for i in 45: await physics_frame
	check(actor.shadow.global_basis.y.normalized().dot(actor._shadow_ray.get_collision_normal()) > 0.999, '地面阴影匹配坡面法线')
	check(actor.position.y > 1.75 and actor.position.y < 2.05, '实际GLB中段台阶高度正确，不埋脚')
	actor.motion_axis = 1
	actor.position = Vector3(9.8, 3.1, 0)
	for i in 60: await physics_frame
	check(actor.position.x < 10.02 and actor.animator.sprite.animation == 'idle', '终点碰撞后不原地踏步')
	for i in 6: actor.select_form('legacy_rinne')
	check(actor.find_children('*', 'SubViewport', true, false).size() == 1, '反复换形态仅一个视口')
	actor.visible = false
	await process_frame
	check(actor.composite.render_target_update_mode == SubViewport.UPDATE_DISABLED, '不可见暂停视口')
	actor.visible = true
	await process_frame
	check(actor.composite.render_target_update_mode == SubViewport.UPDATE_ALWAYS, '重新显示持续刷新')
	check(not actor.select_form('unknown'), '未知形态不伪装成功')
	check(actor.has_method('select_manifest'),'支持按交付清单显式选择已接受revision')
	if actor.has_method('select_manifest'):
		check(actor.select_manifest('rinne','res://assets/chars/pixel/rinne/frame_material_refined/manifest.json'),'已接受凛音revision可按逻辑身份选择')
		check(actor.form_id=='rinne' and actor.animator.sprite.sprite_frames.get_frame_count('walk')==8,'保留逻辑身份但使用已接受8相位')

	check(FileAccess.file_exists('res://scenes/preview/friendly_roster_gallery.tscn'),'七形态展示入口存在')
	if FileAccess.file_exists('res://scenes/preview/friendly_roster_gallery.tscn'):
		var gallery=load('res://scenes/preview/friendly_roster_gallery.tscn').instantiate()
		root.add_child(gallery)
		await process_frame
		var gallery_roster:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(gallery.roster_path))
		var expected_dir:=''
		for form in gallery_roster.forms:
			if form.id=='rinne':expected_dir=JSON.parse_string(FileAccess.get_file_as_string(form.manifest)).dir
		check(gallery.actor.animator.definition.manifest.dir==expected_dir and not expected_dir.is_empty(),'七形态展示使用清单指定的凛音revision')
		var feet=gallery.stage.hero.unproject_position(gallery.actor.global_position)
		var head=gallery.stage.hero.unproject_position(gallery.actor.global_position+Vector3(0,1.6,0))
		check(feet.distance_to(head)>200,'资产展示中全身投影足够清楚')
		var weapon_top=gallery.stage.hero.unproject_position(gallery.actor.global_position+Vector3(0,148.0/60.0,0))
		check(weapon_top.y>=0,'完整脚锚画布中的高举武器不被展示镜头裁断')
		gallery.queue_free()
	scene.queue_free()
	await process_frame
	print('WORLD_RESULT: ', failed)
	quit(1 if failed else 0)
