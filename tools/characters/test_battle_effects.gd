# 独立特效只读取已提交事件；上限、去重、清空与RNG隔离。
extends SceneTree
var failed := 0
func check(ok:bool,label:String) -> void:
	print(("PASS: " if ok else "FAIL: ")+label)
	if not ok: failed+=1
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1":quit(1);return
	var path := "res://scripts/rpg/ui/battle_effects.gd"
	check(FileAccess.file_exists(path),"独立战斗特效组件存在")
	if not FileAccess.file_exists(path): print("BATTLE_EFFECTS_RESULT: ",failed);quit(1);return
	var Fx = load(path)
	var fx = Fx.new()
	root.add_child(fx)
	var event := {"sequence":7,"type":"damage","actor_id":"a","target_id":"b","payload":{"damage":18,"critical":false}}
	var original := event.duplicate(true)
	for form in ["rinne","mint","guard","homura_sword","homura_mage","healer","controller"]:
		var profile:Dictionary=Fx.profile(event,form)
		check(not profile.is_empty() and profile.duration>0 and profile.duration<=1.5,form+"有有界独立打击配置")
	fx.present_event(event,"rinne",Vector2(100,100),Vector2(300,100),"battle_one")
	fx.present_event(event,"rinne",Vector2(100,100),Vector2(300,100),"battle_one")
	check(fx.active_count()==1,"重复同事件不重复堆粒子")
	check(event==original,"特效不修改事件或模型")
	for i in range(80):
		var next:=event.duplicate(true);next.sequence=i+100
		fx.present_event(next,"homura_mage",Vector2.ZERO,Vector2(100,100),"battle_one")
	check(fx.active_count()<=24,"重复施法也遵守特效数量上限")
	fx._process(2.0)
	check(fx.active_count()==0,"特效自然清理不泄漏")
	fx.present_event(event,"healer",Vector2.ZERO,Vector2.ONE,"battle_two")
	check(fx.active_count()==1,"新战斗同sequence允许独立效果")
	fx.clear()
	check(fx.active_count()==0,"取消/换场即时清除全部特效")
	fx.free()
	print("BATTLE_EFFECTS_RESULT: ",failed)
	quit(1 if failed else 0)
