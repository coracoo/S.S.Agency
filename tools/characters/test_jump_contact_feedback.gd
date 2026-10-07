# 跳跃接地反馈：纯小图夹具验证真实控制器/标记/坡面，不冒充源视频逐帧验收。
extends SceneTree
const Player = preload("res://scripts/exploration_3d/player_controller.gd")
var assertions := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	print(("PASS: " if value else "FAIL: ") + message)
	if not value: failures += 1
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	var exists := ResourceLoader.exists("res://scripts/characters/jump_contact_feedback.gd")
	check(exists,"具有独立且不修改源纹理的跳跃反馈组件")
	if exists: _helper_checks()
	await _controller_checks()
	if exists: await _root_contact_ray_checks()
	print("JUMP_CONTACT_FEEDBACK: %d assertions, %d failures" % [assertions,failures])
	quit(1 if failures else 0)
func _helper_checks() -> void:
	var feedback = load("res://scripts/characters/jump_contact_feedback.gd").new()
	root.add_child(feedback); feedback.set_process(false)
	check(feedback.sample(.3)==Vector2.ONE and not feedback.pulse.visible,"没有真实跳跃时接地保持原样")
	check(feedback.start({"takeoff":180,"apex":360,"landing":620}),"使用来源动作声明的三处标记")
	check(feedback.sample(.179)==Vector2.ONE and feedback.sample(.18)==Vector2.ONE,"起跳前与离地瞬间不提前缩影")
	var peak: Vector2 = feedback.sample(.36)
	check(peak.x>=.7 and peak.x<.9 and peak.y>=.35 and peak.y<.7,"顶点只温和缩小/淡化接地影")
	var rising: Vector2 = feedback.sample(.27)
	var falling: Vector2 = feedback.sample(.49)
	check(rising.x>peak.x and rising.x<1 and rising.is_equal_approx(falling),"两段不等长源时序仍平滑地升降")
	check(feedback.sample(.62)==Vector2.ONE and feedback.sample(.9)==Vector2.ONE,"着地而非收招结束时恢复接地影")
	var normal := Vector3(0,.8,.6)
	var point := Vector3(2,3,4)
	check(feedback.land(point,normal),"一次跳跃可以发出一次着地脉冲")
	check(feedback.pulse.visible and feedback.pulse.global_position.is_equal_approx(point) and feedback.pulse.global_basis.y.normalized().is_equal_approx(normal),"脉冲贴合实际地面/坡面")
	check(float(feedback.pulse.material_override.get_shader_parameter("opacity"))>=.32,"着地脉冲初段有足够的有限透明度供石面识别")
	var width: float = feedback.pulse.global_basis.x.length()
	feedback._process(.08)
	check(feedback.pulse.visible and feedback.pulse.global_basis.x.length()>width,"独立脉冲短暂扩散")
	var transform: Transform3D = feedback.pulse.global_transform
	check(not feedback.land(point,normal) and feedback.pulse.global_transform==transform,"重复或迟到着地通知不重启脉冲")
	feedback._process(.2)
	check(not feedback.pulse.visible,"脉冲在220毫秒内自行消散")
	feedback.start({"takeoff":20,"apex":80,"landing":170})
	check(feedback.sample(.08).is_equal_approx(peak) and feedback.sample(.17)==Vector2.ONE,"各形态独立标记而非硬编码凛音时间")
	feedback.cancel()
	check(not feedback.land(point,normal) and feedback.sample(.08)==Vector2.ONE and not feedback.pulse.visible,"取消后迟到通知不能制造幽灵脉冲")
	for events in [{},{"takeoff":100,"apex":90,"landing":200},{"takeoff":0,"apex":100,"landing":INF}]:
		check(not feedback.start(events) and feedback.sample(.1)==Vector2.ONE and not feedback.land(point,normal),"缺失/无序/非有限标记安全不生效")
	seed(901); var expected := randf(); seed(901)
	feedback.start({"takeoff":20,"apex":80,"landing":170}); feedback.sample(.08); feedback.land(point,normal); feedback._process(.04); feedback.cancel()
	check(randf()==expected,"程序化接地反馈不消耗游戏随机数")
	feedback.free()
func _definition() -> Dictionary:
	var frames := SpriteFrames.new(); frames.remove_animation("default")
	var image := Image.create(8,16,false,Image.FORMAT_RGBA8); image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var anims := {}
	for action in ["idle","walk","run","jump","interact","pickup","down"]:
		frames.add_animation(action); frames.set_animation_speed(action,1); frames.set_animation_loop(action,action in ["idle","walk","run"])
		for index in 9: frames.add_frame(action,texture,.1)
		anims[action] = {"frames":[],"events":{}}
	anims.jump = {"events":{"takeoff":180,"apex":360,"landing":620},"vertical_motion_baked":true}
	return {"ok":true,"frames":frames,"manifest":{"canvas":{"w":8,"h":16,"anchor":[4,16],"height_m":1.6,"content_height_px":16},"move_speed_mps":2.6,"run_speed_mps":4.2,"mirror_allowed":true,"anims":anims}}
func _controller_checks() -> void:
	var player_script: Script = Player
	var has_api := player_script.get_script_method_list().any(func(method: Dictionary): return method.name == "get_jump_shadow_factors")
	check(has_api,"控制器把同一接地阶段提供给两条阴影路径")
	if not has_api: return
	var player := Player.new()
	var floor_body := StaticBody3D.new(); var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size=Vector3(10,.2,10)
	shape.shape=box; shape.position.y=-.1; floor_body.add_child(shape); root.add_child(floor_body)
	player.shared_definition=_definition(); root.add_child(player); player.position=Vector3(0,.01,0); player.set_move_input(Vector2.ZERO)
	for frame in 4: await physics_frame
	player.set_physics_process(false); player.set_process(false); player.animator.set_process(false); player._jump_feedback.set_process(false)
	player.animator.sprite.pause()
	var point := player.global_position
	var texture: Texture2D = player.animator.sprite.sprite_frames.get_frame_texture("jump",0)
	var pixels := texture.get_image().get_data()
	check(player.request_jump(),"实际接地胶囊允许启动跳跃")
	player.animator.sprite.pause()
	check(not player._jump_feedback.pulse.visible,"开始/起跳时没有提前着地反馈")
	player.animator._process(.18)
	player._physics_process(0)
	var width := player.shadow.global_basis.x.length()
	var opacity: float = player.shadow.material_override.albedo_color.a
	player.animator._process(.18); player._physics_process(0)
	check(player.shadow.visible and player.shadow.global_basis.x.length()<width and player.shadow.material_override.albedo_color.a<opacity,"根仍接地时普通阴影也按顶点缩小/淡化")
	check(player.global_position.distance_to(point)<.01 and player.billboard.position.y==0 and texture.get_image().get_data()==pixels,"不改变胶囊、烘焙视频位置或原像素")
	check(player.enable_scene_integration(),"启用原有场景接地路径")
	player.scene_integration.set_process(false); player.scene_integration.update_contacts()
	var contact: MeshInstance3D = player.scene_integration._shadows[0]
	var peak_width := contact.global_basis.x.length()
	var peak_opacity: float = contact.material_override.get_shader_parameter("opacity")
	check(contact.visible and peak_width<.65 and peak_opacity<.42*.55,"融合阴影使用相同顶点阶段")
	player.animator._process(.259)
	check(not player._jump_feedback.pulse.visible,"着地标记前1ms仍没有脉冲")
	player.animator._process(.002); player.scene_integration.update_contacts()
	check(player._jump_feedback.pulse.visible and player.animator.sprite.animation==&"jump" and player.animator.is_action_locked(),"真实landing标记在收招前发出脉冲")
	print("CONTACT_RESTORED: width=",contact.global_basis.x.length()," opacity=",contact.material_override.get_shader_parameter("opacity")," peak_opacity=",peak_opacity," root_y=",player.position.y)
	check(is_equal_approx(contact.global_basis.x.length(),.65) and is_equal_approx(contact.material_override.get_shader_parameter("opacity"),peak_opacity*2.0),"着地标记恢复融合接地影（保留实际胶囊离地微量衰减）")
	player._jump_feedback._process(.07); var pulse_transform: Transform3D = player._jump_feedback.pulse.global_transform
	player.animator.action_marker.emit(&"landing")
	check(player._jump_feedback.pulse.global_transform==pulse_transform,"重复真实信号不重启脉冲")
	player.animator._on_animation_finished(); player._process(0)
	check(player._jump_feedback.pulse.visible,"收招结束不截断独立落地脉冲")
	player.disable_scene_integration(); player._physics_process(0)
	check(player.shadow.visible and is_equal_approx(player.shadow.global_basis.x.length(),1.0) and is_equal_approx(player.shadow.material_override.albedo_color.a,.25),"关闭融合后普通阴影完整恢复")
	player.set_control_enabled(false)
	check(not player._jump_feedback.pulse.visible and player.get_jump_shadow_factors()==Vector2.ONE,"关控制立即取消尚在播放的反馈")
	player.animator.action_marker.emit(&"landing")
	check(not player._jump_feedback.pulse.visible,"关控制后的迟到标记不生成脉冲")
	player.set_control_enabled(true); player.set_move_input(Vector2.ZERO); player._physics_process(0)
	check(player.request_jump(),"重新解锁后可以再次跳跃")
	player.animator.sprite.pause(); player.animator._process(.36)
	player.set_control_enabled(false); player.animator.action_marker.emit(&"landing")
	check(not player._jump_feedback.pulse.visible and player.get_jump_shadow_factors()==Vector2.ONE,"落地前关控制不会产生幻影脉冲")
	player.set_control_enabled(true); player.set_move_input(Vector2.ZERO); player._physics_process(0)
	check(player.request_jump(),"取消后的新跳跃独立布防")
	player.animator.sprite.pause(); player.animator._process(.36)
	player.apply_definition("another",_definition())
	player.animator.action_marker.emit(&"landing"); player._process(0)
	check(player._hop_duration==0 and not player._jump_feedback.pulse.visible and player.get_jump_shadow_factors()==Vector2.ONE,"换形态清理跳跃与旧标记")
	player._physics_process(0); check(player.request_jump(),"换形态后的下一次跳跃重新布防")
	player.animator.sprite.pause(); player.animator._process(.36); player.animator.reset(); player._process(0)
	player.animator.action_marker.emit(&"landing")
	check(not player._jump_feedback.pulse.visible and player.get_jump_shadow_factors()==Vector2.ONE,"外部动画重置不会继承旧跳跃反馈")
	player.free(); floor_body.free()

func _root_contact_ray_checks() -> void:
	# 根接触注释不能走相机射线；前景挡板可能遮住脚底，却不改变角色脚下地面。
	var definition := _definition()
	var texture: Texture2D = definition.frames.get_frame_texture("idle",0)
	check(texture.get_image().save_png("user://jump_contact_frame.png")==OK,"隔离目录保存接触注释校验夹具")
	definition.manifest.dir = "user://"
	definition.manifest.character_id = "jump_contact_fixture"
	definition.manifest.scene_integration = {"contact_metadata":"user://jump_contact_metadata.json"}
	for action in definition.manifest.anims:
		definition.manifest.anims[action]["frames"] = ["jump_contact_frame","jump_contact_frame","jump_contact_frame","jump_contact_frame","jump_contact_frame","jump_contact_frame","jump_contact_frame","jump_contact_frame","jump_contact_frame"]
	var metadata := {"character_id":"jump_contact_fixture","canvas":[8,16],"frames":{"jump_contact_frame":{"sha256":FileAccess.get_sha256("user://jump_contact_frame.png"),"contacts":[{"point":[4,16],"width_px":4,"strength":.55,"kind":"root"}]}}}
	var file := FileAccess.open("user://jump_contact_metadata.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata)); file.close()
	var floor_body := StaticBody3D.new(); var floor_shape := CollisionShape3D.new(); var floor_box := BoxShape3D.new(); floor_box.size=Vector3(10,.2,10)
	floor_shape.shape=floor_box; floor_shape.position.y=-.1; floor_body.add_child(floor_shape); root.add_child(floor_body)
	var blocker := StaticBody3D.new(); var blocker_shape := CollisionShape3D.new(); var blocker_box := BoxShape3D.new(); blocker_box.size=Vector3(4,4,.2)
	blocker_shape.shape=blocker_box; blocker.position=Vector3(0,1.5,2); blocker.add_child(blocker_shape); root.add_child(blocker)
	var camera := Camera3D.new(); root.add_child(camera); camera.position=Vector3(0,3,5); camera.look_at(Vector3.ZERO); camera.current=true
	var player := Player.new(); player.shared_definition=definition; root.add_child(player); player.set_move_input(Vector2.ZERO)
	for tick in 4: await physics_frame
	player.set_physics_process(false); player.animator.sprite.pause()
	player.enable_scene_integration(); player.scene_integration.set_process(false); player.scene_integration.update_contacts()
	check(player.scene_integration.contact_mode=="annotated","fixture通过真实源hash并使用注释接触点")
	check(not player.scene_integration._ground_ray(player.global_position+Vector3.UP*.2,player.global_position-Vector3.UP*1.4).is_empty(),"前景挡板不影响真实根接地射线")
	check(player.scene_integration.grounded_count==1 and player.scene_integration._shadows[0].visible,"root类型注释复用根接地，不因前景射线碰墙而丢阴影")
	var root_shadow: MeshInstance3D = player.scene_integration._shadows[0]
	check(is_equal_approx(root_shadow.global_basis.x.length(),.65),"根接地影覆盖原有0.65米脚下范围，不藏在双靴内")
	check(root_shadow.material_override.get_shader_parameter("falloff")==1.4,"根接地影采用可读但仍柔和的径向衰减")
	player.scene_integration._metadata.frames.jump_contact_frame.contacts[0].kind="foot"
	player.scene_integration.update_contacts()
	check(player.scene_integration.grounded_count==0,"真实逐脚注释保留原相机投影与竖面拒绝行为")
	blocker.free(); await physics_frame
	player.scene_integration.update_contacts()
	check(player.scene_integration.grounded_count==1 and root_shadow.material_override.get_shader_parameter("falloff")==3.2,"没有挡板时真实逐脚注释保留原柔和材质")
	player.free(); camera.free(); floor_body.free()
