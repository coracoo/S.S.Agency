# 多目标KO信号与姿态分开：逻辑倒地立即成立，当前hit完整后才切个人down。
extends SceneTree
const Actor=preload("res://scripts/rpg/ui/hd_actor_view.gd")
const Fixture=preload("res://tools/characters/test_expanded_actions.gd")
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:_run.call_deferred()
func _run()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	var fixtures:=Fixture.new();var definition:=fixtures.definition();fixtures.free()
	var actor:=Actor.new();root.add_child(actor);actor.configure(definition,300,1)
	check(actor.has_method("set_downed_after_hit"),"演员提供逻辑KO与hit尾段分离接口")
	if actor.has_method("set_downed_after_hit"):
		actor.play_action(&"hit");actor.set_downed_after_hit()
		check(actor.is_downed() and actor.animator.sprite.animation==&"hit" and actor.is_action_busy(),"KO立即成立但保留当前hit")
		actor.animator._complete_action()
		check(actor.is_downed() and actor.animator.sprite.animation==&"down" and actor.animator.sprite.frame==0,"hit自然结束才开始down首帧")
		for mode in ["cancel","revive","rebind"]:
			actor.configure(definition,300,1);actor.play_action(&"hit");actor.set_downed_after_hit()
			if mode=="cancel":actor.cancel_action()
			elif mode=="revive":actor.set_downed(false)
			else:actor.configure(definition,300,1)
			actor.animator._complete_action()
			check(actor.is_downed()==(mode=="cancel"),mode+"后迟到结束信号不改变新的KO状态")
			check(actor.animator.sprite.animation==(&"down" if mode=="cancel" else &"idle"),mode+"后没有迟到down覆盖新姿态")
	actor.free()
	print("DEFERRED_DEFEAT_POSE: %d assertions, %d failures"%[checks,failures])
	quit(1 if failures else 0)
