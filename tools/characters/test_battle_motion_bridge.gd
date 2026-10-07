# 真正3D身体的同帧移动、投影脚域与清洁源快照；无头量测不代替美术实拍。
extends SceneTree
const Backdrop = preload("res://scripts/rpg/ui/battle_world_backdrop.gd")
const Actor = preload("res://scripts/rpg/ui/hd_actor_view.gd")
const Framing = preload("res://scripts/rpg/ui/battle_party_framing.gd")
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",message)
func _definition() -> Dictionary:
	var page := Image.create(64,64,false,Image.FORMAT_RGBA8); page.fill(Color.WHITE)
	var original := AtlasTexture.new(); original.atlas = ImageTexture.create_from_image(page)
	original.region = Rect2(0,0,50,60); original.margin = Rect2(70,60,250,388)
	var frames := SpriteFrames.new(); frames.remove_animation(&"default")
	var manifest := {"identity_id":"rinne","form_id":"rinne","mirror_allowed":true,"move_speed_mps":2.6,"canvas":{"w":300,"h":448,"anchor":[150,420],"content_height_px":400,"height_m":1.68},"packed_frames":{"body":{"offset":[70,60],"region":[0,0,50,60]}},"anims":{}}
	for action in ["idle","attack","battle_dash","down"]:
		frames.add_animation(action); frames.set_animation_speed(action,1000); frames.set_animation_loop(action,action == "idle")
		frames.add_frame(action,original,200); frames.add_frame(action,original.duplicate(),200)
		manifest.anims[action] = {"frames":["body","body"],"impact_ms":200}
	manifest.anims.battle_dash.clean_body = true
	manifest.anims.battle_dash.qa_approved = true
	return {"ok":true,"frames":frames,"manifest":manifest,"layer_frames":[]}
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	for facing in [-1,1]:
		var backdrop := Backdrop.new(); root.add_child(backdrop)
		backdrop.configure({"night":1,"position":[-4.5,.03,.45]},false)
		var source := Actor.new(); root.add_child(source)
		var definition := _definition()
		source.configure(definition,319.2,facing)
		source.position = Vector2(1450 if facing < 0 else 470,680)
		source.set_meta("content_height",319.2)
		backdrop.bind_visuals({"s":{"sprite":source}})
		var record: Dictionary = backdrop.actor_entries.s
		source.animator.sprite.animation = &"attack"
		source.animator.sprite.set_frame_and_progress(1,0)
		var actual_frame := source.animator.sprite.sprite_frames.get_frame_texture(&"attack",1)
		check(record.body.get_meta("logical_frame_texture_id") == actual_frame.get_instance_id(),"动画帧信号当次调用同步真实billboard，不滞后一tick")
		check(record.body.material_override.get_shader_parameter("art_texture") == record.body.texture,"同帧动画切换后实际材质与body一致")
		check(record.trail.active_count()==0,"动画帧回调只做零delta同步，不凭回调数量生成残影")
		var initial: Vector3 = record.body.position
		source.position += Vector2(140*facing,-15)
		source.presentation_position_changed.emit()
		check(record.body.position != initial,"移动信号当次调用已经更新真实Sprite3D")
		check(backdrop.camera.unproject_position(record.body.position).distance_to(source.position)<.01,"实际3D脚点投影与当前移动脚点一致")
		check(record.shadow.position.is_equal_approx(record.body.position+Vector3(0,.014,0)),"接触阴影同帧跟随实际3D脚点")
		check(record.body.material_override.get_shader_parameter("art_texture") == record.body.texture,"实际材质仍持有当前紧凑帧")
		check(backdrop.has_method("melee_foot_bounds"),"舞台提供真实投影安全脚域")
		if backdrop.has_method("melee_foot_bounds"):
			var bounds: Rect2 = backdrop.melee_foot_bounds("s")
			check(bounds.has_point(source.position),"当前home包含在可用脚域")
			for foot in [bounds.position,bounds.end,Vector2(bounds.position.x,bounds.end.y),Vector2(bounds.end.x,bounds.position.y)]:
				for flipped in [false,true]:
					var body_bounds := Framing.projected_bounds(backdrop.camera,backdrop._ground_point(foot),definition,flipped)
					check(body_bounds.position.x >= 15.9 and body_bounds.end.x <= 1904.1 and body_bounds.position.y >= 153.9 and body_bounds.end.y <= 744.1,"双朝向完整动作边界不越画布或底HUD")
		check(record.has("trail"),"每个实际3D演员拥有独立快照帮助节点")
		if record.has("trail"):
			record.trail.set_process(false)
			source.animator.sprite.animation = &"battle_dash"; source.animator.sprite.pause()
			backdrop.sync_visuals(.06)
			check(record.trail.active_count()==1,"清洁dash采样一帧残影")
			var ghost: Sprite3D = record.trail.get_child(0)
			check(ghost.global_position.is_equal_approx(record.body.global_position),"残影冻结实际3D世界脚根，不是2D代理")
			check(ghost.texture is AtlasTexture and ghost.texture.atlas == record.body.texture.atlas,"残影复用原页像素的独立紧凑视图")
			var frozen := ghost.global_position
			var frozen_alpha := ghost.modulate.a
			backdrop.sync_visuals(0); backdrop.sync_visuals(0)
			check(record.trail.active_count()==1 and ghost.modulate.a == frozen_alpha and is_equal_approx(frozen_alpha,.18),"零delta同步不重复采样或推进淡出")
			source.position += Vector2(30*facing,0); source.presentation_position_changed.emit()
			check(ghost.global_position==frozen,"真人移动不会拖走已拍快照")
			record.trail.cancel()
			source.animator.sprite.animation = &"attack"; source.animator.sprite.pause()
			backdrop.sync_visuals(.06)
			check(record.trail.active_count()==0,"无清洁标签的旧attack默认禁止叠影")
			source._definition.manifest.anims.attack.independent_ghost_ready=true
			backdrop.sync_visuals(.06)
			check(record.trail.active_count()==0,"独立设计标记不能代替清洁源资格")
			source._definition.manifest.anims.attack.clean_body=true
			backdrop.sync_visuals(.06)
			check(record.trail.active_count()==1,"凛音清洁源与独立幽影设计双标记才可拍影")
			for identity in ["homura","healer","controller"]:
				source._definition.manifest.identity_id=identity;source._definition.manifest.form_id="mage" if identity=="homura" else identity
				backdrop.sync_visuals(.06)
				check(record.trail.active_count()==0,"施法角色不因clean或误设独立标记产生身体残影："+identity)
			source._definition.manifest.identity_id="rinne";source._definition.manifest.form_id="rinne"
			backdrop.cancel_trails()
			check(record.trail.active_count()==0,"整段取消立即释放残影")
		var prior_bounds: Rect2 = source._melee_allowed_feet
		var replacement := _definition(); replacement.manifest.canvas.anchor[1] = 400
		source.configure(replacement,319.2,facing); backdrop.sync_visuals(0)
		check(source._melee_allowed_feet != prior_bounds and source._melee_allowed_feet == backdrop.melee_foot_bounds("s"),"重配新定义后重新计算一次完整安全脚域")
		backdrop.clear_visuals()
		source.position += Vector2(10,0); source.presentation_position_changed.emit()
		check(backdrop.actor_entries.is_empty() and source.animator.visible,"解绑断开旧运动回调并恢复来源显示")
		source.free(); backdrop.free()
	print("BATTLE_MOTION_BRIDGE: %d assertions, %d failures" % [checks,failures])
	quit(1 if failures else 0)
