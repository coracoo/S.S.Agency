# 新八法术的实际图集层/释放合同；规则匹配本身由独立真实Engine策略回归覆盖。
extends SceneTree
const Effects=preload("res://scripts/rpg/ui/imagegen_battle_effects.gd")
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func context(ability:String,id:String)->Dictionary:return {"command_id":id,"kind":"skill","ability_id":ability,"source_id":"caster","effect_target_ids":["ally"],"target_ids":["ally"],"impact_delay":.3,"action_duration":1.2}
func event(kind:String,sequence:int,payload:Dictionary)->Dictionary:return {"type":kind,"sequence":sequence,"actor_id":"caster","target_id":"ally","payload":payload}
func _initialize()->void:_run.call_deferred()
func _run()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	var fx:=Effects.new();root.add_child(fx);fx.set_process(false);fx.preview_pending_art=true
	for skill in ["firebolt","flame_wave","ice_arrow","burn_brand","heal","group_heal","cleanse","holy_shield","weaken","slow","seal","magic_break"]:
		check(fx.present_action(context(skill,skill),"healer",Vector2(1000,400),{"ally":Vector2(450,350)},"budget"),"12套同时实际在用不因32MiB旧预算静默丢图："+skill)
	check(fx.texture_memory_bytes()==45*1024*1024,"实际登记12套RGBA合计45MiB，未重复解码页面")
	fx.clear();check(fx.texture_memory_bytes()==0,"全部释放后不保留45MiB页")
	check(fx.has_method("layer_snapshot") and fx.has_method("update_ground_positions"),"事件层提供实际采样与独立地面落点")
	if fx.has_method("layer_snapshot") and fx.has_method("update_ground_positions"):
		fx.update_positions({"caster":Vector2(1000,400),"ally":Vector2(450,350)},{"caster":Vector2(940,270)})
		fx.update_ground_positions({"caster":Vector2(1000,680),"ally":Vector2(450,650)})
		var shield:=context("holy_shield","shield")
		check(fx.present_action(shield,"healer",Vector2(940,270),{"ally":Vector2(450,350)},"layers"),"圣盾独立动作启动")
		fx._process(.3)
		var shield_value:={"amount":40,"remaining":3,"generation":1,"source_id":"caster"}
		fx.present_event(event("shield_applied",10,{"shield":shield_value}),"healer",Vector2.ZERO,Vector2(450,350),"layers",shield)
		var awake:={"id":"awake","remaining":3,"generation":2,"source_id":"caster"}
		fx.present_event(event("status_applied",11,{"status":awake}),"healer",Vector2.ZERO,Vector2(450,350),"layers",shield)
		var layers:Array=fx.layer_snapshot()
		check(layers.size()==2 and layers.any(func(layer):return layer.phase=="holy_shield_edge") and layers.any(func(layer):return layer.phase=="awake_clarity"),"盾与awake来自两套实际phase而非Mage通用status")
		fx.finish_action(shield,"layers");fx._process(1.7)
		check(fx.layer_snapshot().size()==2 and fx.texture_memory_bytes()>0,"来源E结束不消除已提交持续层")
		shield_value.amount=20;shield_value.remaining=2
		fx.present_event(event("shield_tick",12,{"shield":shield_value}),"",Vector2.ZERO,Vector2(450,350),"layers",{})
		layers=fx.layer_snapshot()
		check(layers.all(func(layer):return layer.ability_id=="holy_shield"),"无动作context的tick保持原技能/phase")
		check(not fx.missing_art().has("shield"),"已登记的盾tick不误报通用盾图缺失")
		fx.present_event(event("saga_reflected",13,{"absorption":{"shield_after":{}}}),"",Vector2.ZERO,Vector2(450,350),"layers",{})
		layers=fx.layer_snapshot();check(layers.size()==1 and layers[0].phase=="awake_clarity","反射耗尽只移除盾，awake独立保留")
		fx.present_event(event("status_removed",14,{"status":awake,"reason":"expired"}),"",Vector2.ZERO,Vector2(450,350),"layers",{})
		check(fx.layer_snapshot().is_empty() and fx.texture_memory_bytes()==0,"最后状态移除释放页面")
		var heal:=context("heal","heal")
		fx.present_action(heal,"healer",Vector2(940,270),{"ally":Vector2(450,350)},"layers");fx._process(.3)
		fx.present_event(event("healed",20,{"actual":25}),"healer",Vector2.ZERO,Vector2(450,350),"layers",heal)
		layers=fx.layer_snapshot()
		check(layers.size()==1 and layers[0].phase=="heal_impact" and layers[0].position==Vector2(450,650),"治疗真正事件在脚下采样，不借身体中心当落地点")
		fx.cancel_action(heal,"layers");check(fx.layer_snapshot().is_empty(),"动作取消移除瞬态")
		check(not fx.present_event(event("healed",21,{"actual":25}),"healer",Vector2.ZERO,Vector2(450,350),"layers",heal),"迟到治疗不重新长出层")
		var slow:=context("slow","slow")
		fx.present_action(slow,"controller",Vector2(940,270),{"ally":Vector2(450,350)},"layers");fx._process(.3)
		var value:={"id":"slow","remaining":2,"generation":3,"source_id":"caster"}
		fx.present_event(event("status_applied",30,{"status":value}),"controller",Vector2.ZERO,Vector2(450,350),"layers",slow)
		layers=fx.layer_snapshot();check(layers.size()==1 and layers[0].ability_id=="slow" and layers[0].phase=="slow_apply_sustain","控制者缓速保留自己的冰钟层，不改用冰矢图")
		fx.cancel_action(slow,"layers");check(fx.layer_snapshot().size()==1,"取消演出不撤销已提交持续效果")
		fx.present_event(event("status_removed",31,{"status":value,"reason":"expired"}),"controller",Vector2.ZERO,Vector2(450,350),"layers",slow)
		check(fx.layer_snapshot().is_empty(),"关闭动作的context仍可维护真实状态移除")
		fx.clear();check(fx.active_count()==0 and fx.texture_memory_bytes()==0,"离场clear释放全部层和页")
	fx.free();print("IMAGEGEN_EVENT_LAYERS: %d assertions, %d failures"%[checks,failures]);quit(1 if failures else 0)
