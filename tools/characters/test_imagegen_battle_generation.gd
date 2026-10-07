# 渲染器本身封闭旧战场，不能只依赖BattleView外层的代次保护。
extends SceneTree
const Effects=preload("res://scripts/rpg/ui/imagegen_battle_effects.gd")
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func context(skill:String,id:String)->Dictionary:return {"command_id":id,"kind":"skill","ability_id":skill,"source_id":"source","target_ids":["target"],"effect_target_ids":["target"],"impact_delay":.3,"action_duration":1.2}
func _initialize()->void:_run.call_deferred()
func _run()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	for skill in ["firebolt","heal"]:
		var fx:=Effects.new();root.add_child(fx);fx.set_process(false);fx.preview_pending_art=true
		var ctx:=context(skill,"first")
		var targets:={"target":Vector2(300,300)}
		check(fx.present_action(ctx,"healer",Vector2(900,300),targets,"old"),skill+" 首次接纳")
		fx.clear()
		check(not fx.present_action(ctx,"healer",Vector2(900,300),targets,"old"),skill+" clear后的旧battle动作拒绝")
		check(fx.active_count()==0 and fx.texture_memory_bytes()==0,skill+" 旧动作不能残留cast/刚加载纹理")
		fx.present_event({"sequence":50,"type":"damage","actor_id":"source","target_id":"target","payload":{"damage":22}},"healer",Vector2.ZERO,targets.target,"old",ctx)
		fx.present_event({"sequence":51,"type":"status_applied","actor_id":"source","target_id":"target","payload":{"status":{"id":"burn","source_id":"source","generation":1,"remaining":2}}},"healer",Vector2.ZERO,targets.target,"old",context("burn_brand","old-burn"))
		fx.present_event({"sequence":52,"type":"status_tick","actor_id":"target","target_id":"target","payload":{"status":{"id":"burn","source_id":"source","generation":1,"remaining":1}}},"",Vector2.ZERO,targets.target,"old",{})
		check(fx.active_count()==0 and fx.state_count()==0 and fx.texture_memory_bytes()==0,skill+" 迟到damage/apply/tick均不能重建旧场")
		check(fx.present_action(ctx,"healer",Vector2(900,300),targets,"new"),skill+" 新battle允许相同command ID")
		fx.finish_action(ctx,"new")
		check(fx.present_action(context(skill,"second"),"healer",Vector2(900,300),targets,"new"),skill+" 同场正常后续动作仍可用")
		check(not fx.present_action(context(skill,"foreign"),"healer",Vector2(900,300),targets,"foreign"),skill+" 未clear不跨场混合")
		fx.clear();fx.free()
	var fx:=Effects.new();root.add_child(fx);fx.preview_pending_art=true;fx.set_process(false)
	var invalid:=context("heal","bad");invalid["actor_id"]="wrong-source"
	check(not fx.present_action(invalid,"healer",Vector2.ZERO,{"target":Vector2.ONE},"valid"),"policy拒绝来源不符时renderer必须拒绝")
	check(fx.active_count()==0 and fx.texture_memory_bytes()==0 and fx._started.is_empty(),"policy拒绝无动作/纹理/去重占位")
	check(fx.present_action(context("heal","bad"),"healer",Vector2.ZERO,{"target":Vector2.ONE},"valid"),"修正context可用原command重试")
	fx.free()
	print("IMAGEGEN_BATTLE_GENERATION: %d assertions, %d failures"%[checks,failures]);quit(1 if failures else 0)
