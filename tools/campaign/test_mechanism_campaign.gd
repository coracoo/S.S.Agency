# 实地机关模型事务；剧情到达由明确的事务夹具提供，移动坐标不充作人工GUI通关。
extends SceneTree
const Session=preload("res://scripts/campaign/chapter_session.gd")
const Store=preload("res://scripts/rpg/save_store.gd")
const Fixture=preload("res://tools/campaign/saga_transaction_fixture.gd")
class FaultStore extends "res://scripts/rpg/save_store.gd":
	func _replace_file(_temporary:String,_destination:String)->Error:return ERR_FILE_CANT_WRITE
var assertions:=0
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	assertions+=1
	if not value:failures.append(message);printerr("FAIL:",message)
func _initialize()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	_run.call_deferred()
func _run()->void:
	var session:=Session.new();check(session.start_new(true).ok,"正式新档建立")
	var model:RefCounted=session.campaign
	check(model.has_method("commit_mechanism"),"地图机关存在唯一正式事务入口")
	check(model.safe_snapshot().get("progression_version")==3 and model.safe_snapshot().get("mechanisms") is Dictionary,"新版本完整保存局部机关状态")
	if not model.has_method("commit_mechanism"):session.close();_finish();return
	var rules=load("res://scripts/campaign/mechanism_rules.gd")
	check(Fixture.enter_saga(session) and Fixture.through(session,"C2-09"),"经正式事务抵达水口试验前")
	model=session.campaign
	check(model.begin_saga_scene(model.safe_snapshot().world,"C2-10").ok,"正式开启水口复验场次")
	var before:Dictionary=model.safe_snapshot()
	check(not model.complete_saga_scene(before.world,"C2-10").ok and model.safe_snapshot()==before,"未复验不能先提交成功剧情")
	var gate:Array=rules.gates(before,"C2-10","opening")
	check(not gate.is_empty() and gate[0].before_source_index==7,"第7来源块前保留地图操作门禁")
	var target:Dictionary=_progress_target(rules,before,model._catalog,"water_echo")
	check(not target.is_empty(),"水口有实际可操作站")
	if target.is_empty():session.close();_finish();return
	var world:Dictionary=before.world.duplicate(true);world.position=target.position.duplicate()
	var far:Dictionary=world.duplicate(true);far.position=[-21.0,0.0,0.0]
	check(not model.call("commit_mechanism",far,"water_echo",target.action_id,before.party[0]).ok and model.safe_snapshot()==before,"远离物件不能隔空试验")
	check(not model.call("commit_mechanism",world,"water_echo","not_registered",before.party[0]).ok and model.safe_snapshot()==before,"未知机关操作拒绝")
	check(not model.call("commit_mechanism",world,"water_echo",target.action_id,"unknown_actor").ok,"不允许虚构操作者")
	var original_store:RefCounted=model._store;var original_bytes:=FileAccess.get_file_as_bytes(Session.Chapters.SAVE_PATH)
	model._store=FaultStore.new(model._catalog)
	check(not model.call("commit_mechanism",world,"water_echo",target.action_id,before.party[0]).ok,"写盘失败不发布地图变化")
	check(model.safe_snapshot()==before and FileAccess.get_file_as_bytes(Session.Chapters.SAVE_PATH)==original_bytes,"失败保留状态与原档")
	model._store=original_store
	var steps:=0
	while not rules.view_state(model.safe_snapshot(),"water_echo").complete and steps<20:
		var saved:Dictionary=model.safe_snapshot();target=_progress_target(rules,saved,model._catalog,"water_echo")
		if target.is_empty():check(false,"每一步都有合法实地动作");break
		world=saved.world.duplicate(true);world.position=target.position.duplicate()
		var response:Dictionary=model.call("commit_mechanism",world,"water_echo",target.action_id,saved.party[0])
		check(response.ok,"提交水口实地动作："+target.action_id+" "+str(response.get("error","")))
		if not response.ok:break
		var after:Dictionary=model.safe_snapshot()
		check(after.saga==before.saga and after.roster==before.roster and after.inventory==before.inventory and after.gear==before.gear and after.cards==before.cards and after.merchant==before.merchant,"机关步骤不发奖/不消耗/不提前写剧情")
		var resumed:=Session.new();check(resumed.resume().ok,"每步保存后真实新会话续档")
		check(resumed.campaign.safe_snapshot()==after,"中断后机关与地图位置完整恢复")
		session=resumed;model=session.campaign;steps+=1
	check(rules.view_state(model.safe_snapshot(),"water_echo").complete and steps>=4,"分步观察与复验均发生，不能单键完成")
	check(not model.safe_snapshot().saga.flags.get("water_echo_verified",false),"物理试验完成仍不提前改批准剧情flag")
	check(model.complete_saga_scene(model.safe_snapshot().world,"C2-10").ok,"复验后正式完整场次可提交")
	check(model.safe_snapshot().saga.flags.get("water_echo_verified",false),"批准剧情事实只由场次完成产生")
	var valid:Dictionary=model.safe_snapshot()
	var invalid:Dictionary=valid.duplicate(true);invalid.erase("mechanisms")
	check(not Store.new()._decode(JSON.stringify(invalid)).ok,"新版本缺机关状态拒绝，不静默清空")
	invalid=valid.duplicate(true);invalid.mechanisms.version=99
	check(not Store.new().validate(invalid).is_empty(),"未知机关版本保留原档")
	for malformed in [null,[],2,"bad"]:
		invalid=valid.duplicate(true);invalid.mechanisms.legacy=malformed
		check(not Store.new()._decode(JSON.stringify(invalid)).ok,"损坏继承前缀类型安全拒绝："+str(malformed))
	session.close();print("MECHANISM_ACTUAL_STEPS:",steps);_finish()
func _progress_target(rules:GDScript,saved:Dictionary,_catalog:RefCounted,id:String)->Dictionary:
	var current:Dictionary=rules.view_state(saved,id)
	for target in rules.targets(saved):
		if target.mechanism_id!=id:continue
		var world:Dictionary=saved.world.duplicate(true);world.position=target.position.duplicate()
		var trial:Dictionary=rules.preview(saved,world,id,target.action_id,saved.party[0])
		if not trial.get("ok",false):continue
		var after:Dictionary=rules.view_state(trial.candidate,id)
		if after.step>current.step or after.complete!=current.complete:return target
	return {}
func _finish()->void:
	print("MECHANISM_CAMPAIGN:",assertions," assertions, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
