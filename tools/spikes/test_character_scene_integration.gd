extends SceneTree
var failed := 0
func check(ok: bool, label: String) -> void:
	print(('PASS: ' if ok else 'FAIL: ')+label)
	if not ok: failed += 1
func _initialize() -> void: call_deferred('run')
func run() -> void:
	var script_path = 'res://scripts/characters/character_scene_integration.gd'
	check(FileAccess.file_exists(script_path),'存在可复用且默认关闭的融合helper')
	if not FileAccess.file_exists(script_path): quit(1); return
	var actor = load('res://scripts/characters/pixel_character_world.gd').new()
	root.add_child(actor)
	actor.set_physics_process(false)
	check(actor.select_manifest('guard','res://assets/chars/pixel/guard/high_detail_complete/manifest.json'),'最终22帧高清素材可载入')
	actor.animator.set_process(false)
	var helper = load(script_path).new()
	actor.add_child(helper)
	check(helper.attach_to(actor),'helper绑定已知profile')
	check(not helper.enabled and actor.billboard.material_override == null,'绑定不会自动改变基线')
	var texture = actor.billboard.texture
	helper.set_enabled(true)
	check(actor.billboard.material_override != null and actor.billboard.texture == texture,'显式启用且同纹理不复制')
	var canvas: Dictionary = actor.animator.definition.manifest.canvas
	check(helper.canvas_point_to_world(Vector2(canvas.anchor[0],canvas.anchor[1])).distance_to(actor.global_position)<0.0001,'画布脚锚准确映射世界根节点')
	var p = Vector2(canvas.anchor[0]+100,canvas.anchor[1])
	actor.animator.sprite.flip_h=false
	var right = helper.canvas_point_to_world(p).x - actor.global_position.x
	actor.animator.sprite.flip_h=true
	var left = helper.canvas_point_to_world(p).x - actor.global_position.x
	check(absf(right+left)<0.0001 and right>0,'镜像脚点随flip准确翻转')
	actor.animator.sprite.flip_h=false
	for spec in [['idle',0,2],['idle',4,2],['walk',0,2],['walk',1,1],['walk',4,2],['walk',5,1],['attack',2,2],['down',0,2]]:
		actor.animator.sprite.animation=spec[0]
		actor.animator.sprite.set_frame_and_progress(spec[1],0)
		actor.animator.sprite.pause()
		var contacts = helper.current_contact_specs()
		check(contacts.size()==spec[2],'%s:%d承重标注数量正确，无摆脚强影'%[spec[0],spec[1]])
		check(helper.contact_mode=='annotated','真实帧SHA匹配后才使用逐脚标注')
	actor.animator.sprite.animation='attack';actor.animator.sprite.set_frame_and_progress(2,0)
	var attack = helper.current_contact_specs()
	check(absf(attack[0].point[0]-attack[1].point[0])*actor.billboard.pixel_size>0.8,'攻击展开双脚有真实大跨度而非固定中心双影')
	var expected_sha = helper._metadata.frames.attack3.sha256
	helper._metadata.frames.attack3.sha256 = 'invalid'
	helper.current_contact_specs()
	check(helper.contact_mode=='root_fallback','源SHA不匹配不使用陈旧脚点')
	helper._metadata.frames.attack3.sha256=expected_sha
	var floor = StaticBody3D.new()
	var collision = CollisionShape3D.new()
	var box = BoxShape3D.new();box.size=Vector3(12,0.1,12)
	collision.shape=box;floor.add_child(collision);floor.position.y=-0.05;root.add_child(floor)
	var camera = Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4.7
	root.add_child(camera);camera.position=Vector3(0,2.2,8);camera.look_at(Vector3(0,0.85,0));camera.make_current()
	actor.position=Vector3(0,0.05,0)
	await physics_frame;await physics_frame
	helper.update_contacts()
	check(helper.grounded_count==2,'攻击双脚经真实物理ray命中地面')
	var first: Vector3=helper._shadows[0].global_position
	actor.position.x+=1.0
	helper.update_contacts()
	check(absf(helper._shadows[0].global_position.x-first.x-1.0)<0.01,'角色根节点移动同步带动逐脚影')
	actor.position.y=2.0;helper.update_contacts()
	check(helper.grounded_count==0,'离地或无地面不虚构接触影')
	actor.position=Vector3(0,0.05,0);floor.rotation.z=deg_to_rad(15)
	await physics_frame;await physics_frame
	helper.update_contacts()
	check(helper.grounded_count>0 and absf(helper._shadows[0].global_basis.y.normalized().x)>0.1,'阴影法线跟随实际射线命中的斜坡')
	var stage=load('res://scenes/preview/act01_approach_3d.tscn').instantiate();root.add_child(stage)
	var environment=stage.get_node('WorldEnvironment').environment
	helper.apply_to_stage(stage)
	check(stage.get_node('WorldEnvironment').environment!=environment,'环境使用实例副本')
	helper.restore_stage()
	check(stage.get_node('WorldEnvironment').environment==environment,'恢复stage原环境引用')
	stage.queue_free();camera.queue_free();floor.queue_free()
	check(actor.select_manifest('rinne','res://assets/chars/pixel/rinne/frame_material_refined/manifest.json'),'切换未标注角色')
	var fallback = helper.current_contact_specs()
	check(helper.contact_mode=='root_fallback' and fallback.size()==1,'未知帧只给明确标识的保守根部柔影')
	helper.set_enabled(false)
	check(actor.billboard.material_override==null,'关闭恢复原角色材质')
	actor.queue_free();await process_frame
	print('CHARACTER_SCENE_INTEGRATION_RESULT: ',failed)
	quit(1 if failed else 0)
