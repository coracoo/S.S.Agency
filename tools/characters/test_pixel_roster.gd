extends SceneTree
var failed := 0
func check(value: bool, message: String) -> void:
	print(('PASS: ' if value else 'FAIL: ') + message)
	if not value: failed += 1
func _initialize() -> void: call_deferred('run')
func run() -> void:
	var loader = load('res://scripts/characters/pixel_character_definition.gd')
	var roster: Dictionary = JSON.parse_string(FileAccess.get_file_as_string('res://assets/chars/pixel/roster.json'))
	var world = load('res://scripts/characters/pixel_character_world.gd').new()
	root.add_child(world)
	world.set_physics_process(false)
	var identities := {}
	for form in roster.forms:
		var result: Dictionary = loader.load_definition(form.manifest)
		check(result.ok, form.id + '真实帧清单载入')
		if not result.ok: continue
		identities[result.manifest.identity_id] = true
		for state in {'idle':4,'walk':8,'attack':6,'hit':1,'defend':1,'down':1,'recover':1}:
			check(result.manifest.anims.has(state) and result.manifest.anims[state].frames.size()=={'idle':4,'walk':8,'attack':6,'hit':1,'defend':1,'down':1,'recover':1}[state],form.id+'最终源帧合同:'+state)
		check(world.select_manifest(form.id,form.manifest), form.id + '可切换到世界节点')
		var canvas:Dictionary=result.manifest.canvas
		check(world.composite.size == Vector2i(canvas.w,canvas.h), form.id + '合成画布保留清单原生尺寸')
		check(world.billboard.offset == Vector2(float(canvas.w)/2-float(canvas.anchor[0]),float(canvas.anchor[1])-float(canvas.h)/2), form.id + '脚锚世界原点一致')
		check(absf(world.billboard.pixel_size*float(canvas.content_height_px)-float(canvas.height_m)) < 0.0001, form.id + '源像素密度不改变世界身高')
		world.animator.set_motion(2.6,1)
		var seen := {}
		var elapsed := 0.0
		while elapsed < 0.56:
			await process_frame
			elapsed += world.get_process_delta_time()
			seen[world.animator.sprite.frame]=true
		check(seen.size()==8,form.id+'完整8相位实际播放')
		world.animator.set_motion(0,1)
		world.animator.request_action('attack')
		check(not world.animator.request_action('attack'), form.id + '动作不可重入')
		await create_timer(0.65).timeout
		check(not world.animator.is_action_locked(), form.id + '动作结束恢复')
		world.animator.request_action('down')
		await create_timer(0.1).timeout
		check(world.animator.is_downed(), form.id + '失能姿态保持')
		world.animator.request_action('recover')
		await create_timer(0.5).timeout
		check(not world.animator.is_downed() and not world.animator.is_action_locked(), form.id + '恢复完成')
	check(identities.size() == 6, '七形态属于六身份，焰华不复制角色')
	world.queue_free()
	await process_frame
	print('ROSTER_RESULT: ', failed)
	quit(1 if failed else 0)
