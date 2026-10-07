# 已独立量测的铃口/卷轴端盖，在实际Sprite3D中投影；不猜未测恢复帧。
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
	for form in ["healer","controller"]:
		var definition:=Definition.load_definition("res://assets/chars/pixel/%s/video_actions/manifest.json"%form,"battle")
		check(definition.get("ok",false),form+"正式源可加载")
		if not definition.get("ok",false):continue
		var backdrop:=Backdrop.new();root.add_child(backdrop);backdrop.configure({"night":1,"position":[-4.5,.03,.45]},false)
		var actor:=Actor.new();root.add_child(actor);actor.configure(definition,308,1);actor.position=Vector2(1160,680);backdrop.bind_visuals({"caster":{"sprite":actor}});actor.play_action(&"attack")
		var measured:=12 if form=="healer" else 15
		for index in measured:
			actor.animator.sprite.set_frame_and_progress(index,0);backdrop.sync_visuals(.06)
			var point:Dictionary=backdrop.actor_action_attachment("caster")
			check(point.get("ok",false) and point.get("frame_key")==definition.manifest.anims.attack.frames[index],form+"每个已测姿势使用对应实际焦点")
			check(backdrop.actor_entries.caster.trail.active_count()==0,form+"普通施法不生成身体幽影")
		actor.animator.sprite.set_frame_and_progress(7 if form=="healer" else 8,0);backdrop.sync_visuals(0)
		var focus:Dictionary=backdrop.actor_action_attachment("caster")
		if focus.get("ok",false):
			check(focus.logical_point==Vector2(1138,582) if form=="healer" else focus.logical_point==Vector2(1164,586),form+"物件动作cue为独立量测点")
			var body:Sprite3D=backdrop.actor_entries.caster.body;var foot:Vector2=backdrop.camera.unproject_position(body.global_position)
			actor.animator.position+=Vector2(1000,1000)
			check(backdrop.actor_action_attachment("caster").position==focus.position,form+"隐藏代理移动不影响法器实际锚")
			actor.set_facing(-1);backdrop.sync_visuals(0);var mirror:Dictionary=backdrop.actor_action_attachment("caster")
			check(absf(focus.position.x+mirror.position.x-2*foot.x)<.02 and absf(focus.position.y-mirror.position.y)<.02,form+"法器焦点随真实billboard镜像")
		actor.animator.sprite.set_frame_and_progress(measured,0);backdrop.sync_visuals(0)
		check(not backdrop.actor_action_attachment("caster").get("ok",false),form+"未测恢复帧明确拒绝，不补点或钳到末值")
		actor.free();backdrop.free()
	print("CASTER_TOOL_ATTACHMENTS: %d assertions, %d failures"%[checks,failures]);quit(1 if failures else 0)
