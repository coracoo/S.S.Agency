# 角色融合回归：检查正式舞台接入已有受光与逐脚落地，而非改变原图/身高。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("ASSERT FAIL:",message)
func _run() -> void:
	check(str(ProjectSettings.get_setting("rendering/renderer/rendering_method",""))=="gl_compatibility","直接打开项目必须沿用Compatibility")
	check(str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile",""))=="gl_compatibility","移动回退也不能悄悄切换渲染器")
	var session := Session.new()
	check(session.start_new(true).ok,"创建隔离正式新游戏")
	check((await session.prepare_assets()).ok,"加载既有人物原图")
	var stage: Node3D = load(Catalog.scene_path(1)).instantiate();root.add_child(stage)
	for frame in 8: await physics_frame
	var player: Node3D = stage.player
	check(player.scene_integration != null,"正式主角必须接入已认可的场景融合")
	if player.scene_integration != null:
		check(player.scene_integration.enabled,"逐脚接地与受光实际启用")
		check(player.scene_integration.current_contact_specs().size()==2 and player.scene_integration.contact_mode=="annotated","最新凛音原PNG hash匹配两脚标注")
		check(player.billboard.material_override is ShaderMaterial,"地图主角使用已有受光shader")
		check(player.scene_integration._stage == null,"不能把旧参道环境配置覆盖连续世界")
	for actor in stage.get_node("ActOneNPCs").get_children():
		var sprite := actor.get_node_or_null("Body") as AnimatedSprite3D
		if sprite == null: continue
		check(sprite.material_override is ShaderMaterial,"驻场角色同步受光："+str(actor.name))
		if sprite.material_override is ShaderMaterial:
			var material := sprite.material_override as ShaderMaterial
			check(material.get_shader_parameter("art_texture")==sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame),"驻场受光纹理使用当前帧："+str(actor.name))
	stage.free();session.close()
	print("CAMPAIGN_ACTOR_LIGHTING:",checks," assertions, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
