extends SceneTree
var failed:=0
func check(value:bool,message:String)->void:
	print(('PASS: ' if value else 'FAIL: ')+message)
	if not value:failed+=1
func _initialize()->void:call_deferred('run')
func run()->void:
	var loader=load('res://scripts/characters/pixel_character_definition.gd')
	var args=OS.get_cmdline_user_args()
	var form_id='guard' if args.is_empty() else args[0]
	var path='res://assets/chars/pixel/'+form_id+'/high_detail_complete/manifest.json'
	var expected_height=104.0/60.0 if form_id=='guard' else 1.6
	var started=Time.get_ticks_usec()
	var first:Dictionary=loader.load_definition(path)
	print('DETAIL_LOAD_FIRST_MS:',(Time.get_ticks_usec()-started)/1000.0)
	check(first.ok,'高细节动作源可读')
	if not first.ok:quit(1);return
	started=Time.get_ticks_usec()
	var second:Dictionary=loader.load_definition(path)
	print('DETAIL_LOAD_SHARED_MS:',(Time.get_ticks_usec()-started)/1000.0)
	check(first.frames.get_frame_texture('walk',0).get_rid()==second.frames.get_frame_texture('walk',0).get_rid(),'高细节重复实例实际共享纹理')
	check(first.frames.get_frame_count('walk')==8,'真实八相位帧数')
	var duration:=0.0
	var unique:={}
	for i in 8:
		duration+=first.frames.get_frame_duration('walk',i)/first.frames.get_animation_speed('walk')
		unique[first.frames.get_frame_texture('walk',i).get_rid().get_id()]=true
	check(unique.size()==8,'八相位并非复制相同PNG')
	check(absf(duration-0.50302)<0.000001,'保持0.50302秒步行周期')
	var scene=load('res://scenes/preview/friendly_roster_gallery.tscn').instantiate()
	root.add_child(scene)
	check(scene.actor.select_manifest(form_id,path),'真实物理角色显式载入高细节revision')
	check(scene.actor.enable_scene_integration(scene.stage),'批准融合profile可用于当前形态')
	scene.actor.set_input_enabled(false)
	for i in 20:await physics_frame
	var origin:Vector3=scene.actor.position
	check(scene.actor.composite.size==Vector2i(first.manifest.canvas.w,first.manifest.canvas.h) and scene.actor.composite.size.y>=1024,'完整原生画布无中间缩图')
	check(first.manifest.canvas.anchor[0]*2==first.manifest.canvas.w,'镜像围绕同一水平脚根')
	check(absf(scene.actor.billboard.pixel_size*1024-expected_height)<0.000001,'世界身高保持角色原值')
	if first.manifest.has('scene_integration'):
		check(scene.actor.scene_integration.contact_mode=='annotated','当前形态加载自己的SHA脚点标注')
	scene.actor.motion_axis=1
	var seen:={}
	for i in 65:
		await physics_frame
		seen[scene.actor.animator.sprite.frame]=true
	check(seen.size()==8,'实际播放经过全部八相位')
	check(scene.actor.position.x>origin.x+2.5,'真实右行位移与2.6m/s一致')
	scene.actor.motion_axis=-1
	for i in 65:await physics_frame
	check(absf(scene.actor.position.x-origin.x)<0.15 and scene.actor.animator.sprite.flip_h,'反向镜像返回原位置')
	scene.actor.motion_axis=0
	for i in 3:await physics_frame
	check(scene.actor.animator.sprite.animation=='idle','停步回真实idle')
	for state in {'idle':4,'walk':8,'attack':6,'hit':1,'defend':1,'down':1,'recover':1}:
		check(first.manifest.anims.has(state) and first.manifest.anims[state].frames.size()=={'idle':4,'walk':8,'attack':6,'hit':1,'defend':1,'down':1,'recover':1}[state],'完整动作源帧合同:'+state)
	check(scene.actor.animator.request_action('attack'),'真实六姿态攻击可触发')
	check(not scene.actor.animator.request_action('attack'),'攻击不可重入')
	await create_timer(0.6).timeout
	check(not scene.actor.animator.is_action_locked() and scene.actor.animator.sprite.animation=='idle','攻击460ms收招回待机')
	scene.actor.animator.request_action('down')
	await create_timer(1.2).timeout
	check(scene.actor.animator.is_downed(),'单失能姿态保持直到恢复')
	scene.actor.animator.request_action('recover')
	await create_timer(0.6).timeout
	check(not scene.actor.animator.is_downed() and not scene.actor.animator.is_action_locked(),'恢复真实姿态结束解锁')
	scene.queue_free();await process_frame
	print('DETAIL_MOTION_RESULT: ',failed)
	quit(1 if failed else 0)
