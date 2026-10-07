# 新875ms候选需要真实图集与独立逐帧掌点，不能沿用旧49帧轨迹。
extends SceneTree
const Backdrop=preload("res://scripts/rpg/ui/battle_world_backdrop.gd")
const Actor=preload("res://scripts/rpg/ui/hd_actor_view.gd")
const Definition=preload("res://scripts/characters/pixel_character_definition.gd")
const Attachments=preload("res://scripts/characters/action_attachment_points.gd")
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:_run.call_deferred()
func _run()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1" or OS.get_environment("MAGE_CANDIDATE_MANIFEST").is_empty():quit(2);return
	var definition:=Definition.load_definition(OS.get_environment("MAGE_CANDIDATE_MANIFEST"),"battle")
	check(definition.get("ok",false),"候选真实定义可装配")
	if not definition.get("ok",false):quit(1);return
	var backdrop:=Backdrop.new();root.add_child(backdrop);backdrop.configure({"night":1,"position":[-4.5,.03,.45]},false)
	var actor:=Actor.new();root.add_child(actor);actor.configure(definition,323,1);actor.position=Vector2(1000,680)
	backdrop.bind_visuals({"mage":{"sprite":actor}});actor.play_action(&"attack")
	for index in 21:
		actor.animator.sprite.set_frame_and_progress(index,0);backdrop.sync_visuals(.06)
		var point:Dictionary=backdrop.actor_action_attachment("mage")
		check(point.get("ok",false) and point.get("profile")=="homura_mage_quick_attack_hand_v1" and point.get("frame_key")=="attack_cycles_%03d"%(index+30),"实际Sprite3D每帧使用新动作掌点")
		check(backdrop.actor_entries.mage.trail.active_count()==0,"清洁施法动作没有身体幽影")
	actor.animator.sprite.set_frame_and_progress(6,0);backdrop.sync_visuals(0)
	var release:Dictionary=backdrop.actor_action_attachment("mage")
	if release.get("ok",false):
		check(release.logical_point.distance_to(Vector2(1163.137,538.767))<.01,"native36独立量测的掌前坐标")
		var foot:Vector2=backdrop.camera.unproject_position(backdrop.actor_entries.mage.body.global_position)
		actor.set_facing(-1);backdrop.sync_visuals(0)
		var mirror:Dictionary=backdrop.actor_action_attachment("mage")
		check(absf(release.position.x+mirror.position.x-2*foot.x)<.02 and absf(release.position.y-mirror.position.y)<.02,"新动作掌点随实际billboard翻向，脚锚固定")
		check(absf(release.launch_seconds-5.0/24.0)<.0001 and absf(release.cast_scale-.55)<.0001,"新版profile把推掌cue与聚能尺寸传到真实投影")
	var retimed:=definition.duplicate(true);retimed.manifest.anims.attack.durations_ms[0]+=10;retimed.manifest.anims.attack.durations_ms[1]-=10
	check(not Attachments.resolve(retimed,"attack",6).ok,"总时长相同但逐帧重定时必须重新校准释放点")
	var remarkered:=definition.duplicate(true);remarkered.manifest.anims.attack.impact_ms+=40
	check(not Attachments.resolve(remarkered,"attack",6).ok,"改变M的版本不沿用已验释放点")
	actor.free();backdrop.free()
	print("MAGE_CANDIDATE_ATTACHMENT: %d assertions, %d failures"%[checks,failures])
	quit(1 if failures else 0)
