# 回程等完整原生攻击结束，再转身用同一已验多帧dash跑回；命中时钟不改。
extends SceneTree
const Actor = preload("res://scripts/rpg/ui/hd_actor_view.gd")
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value: failures+=1;printerr("FAIL: ",message)
func _initialize()->void: _run.call_deferred()
func definition()->Dictionary:
	var frames:=SpriteFrames.new();frames.remove_animation("default")
	var image:=Image.create(32,64,false,Image.FORMAT_RGBA8);image.fill(Color.WHITE)
	var texture:=ImageTexture.create_from_image(image)
	for action in ["idle","attack","battle_dash","down"]:
		frames.add_animation(action);frames.set_animation_speed(action,1000);frames.set_animation_loop(action,action=="idle")
		for i in (5 if action=="battle_dash" else 3): frames.add_frame(action,texture,40 if action=="battle_dash" else 200)
	return {"ok":true,"frames":frames,"layer_frames":[],"manifest":{"identity_id":"guard","form_id":"guard","mirror_allowed":true,"move_speed_mps":2.6,"canvas":{"w":32,"h":64,"anchor":[16,63],"content_height_px":60,"height_m":1.78},"anims":{"attack":{"impact_ms":200},"battle_dash":{"qa_approved":true,"clean_body":true}}}}
func _run()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	for facing in [-1,1]:
		var actor:=Actor.new();var target:=Node2D.new();root.add_child(actor);root.add_child(target)
		actor.configure(definition(),300,facing);actor.set_process(false);actor.animator.set_process(false)
		actor.position=Vector2(1300 if facing<0 else 620,680);target.position=Vector2(420 if facing<0 else 1500,680)
		var home:=actor.position
		check(actor.begin_melee_approach(target),"QA源可接近")
		actor._step_melee(.2)
		check(actor.play_action(&"attack"),"在敌前开始完整原生动作")
		var strike:=actor.position
		actor.begin_melee_recovery(.4)
		actor._step_melee(.3)
		check(actor.position==strike and actor.animator.sprite.animation==&"attack","剩余收招阶段保持敌前，不滑回")
		actor._step_melee(.2)
		check(actor.position==strike and actor.animator.sprite.animation==&"attack","时长已过但原生动作未结束时仍等待E")
		actor.animator._complete_action()
		actor._step_melee(.01)
		check(actor._melee.get("phase")=="return" and actor.animator.sprite.animation==&"battle_dash","E后用多帧dash返回")
		check(actor._facing==-facing,"回程面向home，不能仍朝敌方向滑退")
		check(is_equal_approx(actor.animator.sprite.speed_scale,.2/.22),"已验200ms真实帧重定标到220ms回程")
		actor._step_melee(.11)
		check(actor.position!=home and actor.position!=strike,"回程途中脚点连续且仍锁定表现")
		actor._step_melee(.11)
		check(actor.position==home and not actor.is_melee_moving() and actor._facing==facing,"到达后精确复位并恢复战斗朝向")
		check(actor.animator.sprite.animation==&"idle" and actor.animator.sprite.speed_scale==1,"归位不残留dash或变速")
		for cancel_kind in ["cancel","down"]:
			actor.begin_melee_approach(target);actor._step_melee(.2);actor.play_action(&"attack");actor.begin_melee_recovery(0);actor.animator._complete_action();actor._step_melee(.2);actor._step_melee(.11)
			check(actor.position!=home and actor.position!=strike,"取消夹具已在实际回程中点")
			if cancel_kind=="down":actor.set_downed(true)
			else:actor.cancel_action()
			check(actor.position==home and not actor.is_melee_moving(),"回程中"+cancel_kind+"立即停止并精确归位")
			actor._step_melee(1)
			check(actor.position==home,"迟到delta不会重新移动")
		actor.free();target.free()
	print("MELEE_RETURN_DASH: %d assertions, %d failures"%[checks,failures])
	quit(1 if failures else 0)
