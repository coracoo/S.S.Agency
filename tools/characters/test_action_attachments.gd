# 动作附件使用原画布坐标，经实际Sprite3D脚根/翻向/像素大小投影；不改变身体锚。
extends SceneTree
const Backdrop=preload("res://scripts/rpg/ui/battle_world_backdrop.gd")
const Actor=preload("res://scripts/rpg/ui/hd_actor_view.gd")
const Definition=preload("res://scripts/characters/pixel_character_definition.gd")
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:_run.call_deferred()
func _run()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	var backdrop:=Backdrop.new();root.add_child(backdrop);backdrop.configure({"night":1,"position":[-4.5,.03,.45]},false)
	check(backdrop.has_method("actor_action_attachment"),"真实billboard提供按动作来源绑定的附件点")
	if backdrop.has_method("actor_action_attachment"):
		var definition:=Definition.load_definition("res://assets/chars/pixel/homura_mage/video_actions/manifest.json","battle")
		var actor:=Actor.new();root.add_child(actor);actor.configure(definition,323,1);actor.position=Vector2(1000,680)
		backdrop.bind_visuals({"mage":{"sprite":actor}})
		actor.play_action(&"attack");actor.animator.sprite.set_frame_and_progress(2,0)
		var body:Sprite3D=backdrop.actor_entries.mage.body
		var fixed_offset:=body.offset;var fixed_size:=body.pixel_size
		var first:Dictionary=backdrop.actor_action_attachment("mage")
		var quick:bool=definition.manifest.anims.attack.frames.size()==21
		check(first.ok and first.frame_key==("attack_cycles_032" if quick else "attack_013") and first.profile==("homura_mage_quick_attack_hand_v1" if quick else "homura_mage_recovered_attack_hand_v1"),"正式源按自己校准的真实渲染帧键读取："+str(first))
		if not first.ok:
			print("ATTACHMENT_SOURCE:",definition.manifest.canvas," ",definition.manifest.anims.attack)
			actor.free();backdrop.free();quit(1);return
		check(first.position.y<backdrop.actor_effect_center("mage").y-40,"掌部点区别于腰腹命中中心")
		actor.animator.position+=Vector2(777,777)
		check(backdrop.actor_action_attachment("mage").position==first.position,"隐藏2D代理偏移不改变实际3D附件")
		actor.position+=Vector2(120,-20);actor.presentation_position_changed.emit()
		var moved:Dictionary=backdrop.actor_action_attachment("mage")
		check(moved.position.distance_to(first.position+Vector2(120,-20))<.02,"实际脚根位移同帧带动手锚")
		var foot:Vector2=backdrop.camera.unproject_position(body.global_position)
		actor.set_facing(-1);backdrop.sync_visuals(0)
		var mirrored:Dictionary=backdrop.actor_action_attachment("mage")
		check(absf((moved.position.x-foot.x)+(mirrored.position.x-foot.x))<.02 and absf(moved.position.y-mirrored.position.y)<.02,"镜像沿固定脚锚对称，保持实际高度")
		check(body.pixel_size==fixed_size,"手锚不逐帧缩放身体")
		actor.animator.sprite.set_frame_and_progress(12,0)
		var raised:Dictionary=backdrop.actor_action_attachment("mage")
		check(raised.position.y<mirrored.position.y,"抬掌动作逐帧跟踪，非固定屏幕Y偏移")
		var changed:=definition.duplicate(true);changed.manifest.anims.attack.frames=changed.manifest.anims.attack.frames.slice(0,20)
		actor.configure(changed,323,1);actor.play_action(&"attack");backdrop.sync_visuals(0)
		check(not backdrop.actor_action_attachment("mage").ok,"新875ms/不同选帧动作不能盲套旧手部轨迹")
		actor.free()
	backdrop.free()
	print("ACTION_ATTACHMENTS: %d assertions, %d failures"%[checks,failures])
	quit(1 if failures else 0)
