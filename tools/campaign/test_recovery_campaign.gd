# 首战使用真实指令；战场回收必须来自已保存胜利，不能相信战斗方自报物品。
extends SceneTree
const Session=preload("res://scripts/campaign/chapter_session.gd")
const Recovery=preload("res://scripts/campaign/recovery_catalog.gd")
const Strategy=preload("res://tools/campaign/saga_battle_strategy.gd")
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
	var session:=Session.new();check(session.start_new(true).ok,"新建正式局")
	var model:RefCounted=session.campaign
	check(Recovery.earned(model.safe_snapshot(),model._catalog).is_empty(),"未战胜时没有永久回收")
	for event in ["dialogue:a1","dialogue:r1","dialogue:h1"]:check(session.commit_event(model.safe_snapshot().world,event).ok,"首战前置："+event)
	var started:Dictionary=session.begin_encounter(model.safe_snapshot().world,"basin_reflection")
	check(started.ok,"正式首战建立")
	if not started.ok:session.close();_finish();return
	var preview:=Recovery.preview_new(model.safe_snapshot(),started.encounter_id,model._catalog)
	check(not preview.is_empty() and preview.all(func(row):return row.preview),"战前只预览首收，不当成已获")
	check(Recovery.earned(model.safe_snapshot(),model._catalog).is_empty(),"进战不提前收录")
	var engine:RefCounted=session.router.create_engine()
	var commands:=0
	while engine!=null and engine.snapshot().outcome.is_empty() and commands<150:
		engine.advance();var state:Dictionary=engine.snapshot()
		if state.outcome.is_empty() and state.phase=="action_selection":
			var command:Dictionary=Strategy.choose(state,engine,model._catalog)
			if command.is_empty() or not engine.submit(command).accepted:break
			commands+=1
	var result:Dictionary=session.router.result_from_engine()
	check(result.get("outcome")=="victory","真实指令获得首胜")
	if result.get("outcome")!="victory":session.close();_finish();return
	result["new_recoveries"]=[{"id":"forged_control_pin","name":"伪造实销"}]
	var before:Dictionary=model.safe_snapshot();var bytes:=FileAccess.get_file_as_bytes(Session.Chapters.SAVE_PATH)
	var original_store:RefCounted=model._store;model._store=FaultStore.new(model._catalog)
	var failed:Dictionary=session.router.finish(result)
	check(not failed.ok and not failed.has("new_recoveries"),"保存失败不发布首收回执")
	check(model.safe_snapshot()==before and FileAccess.get_file_as_bytes(Session.Chapters.SAVE_PATH)==bytes and Recovery.earned(before,model._catalog).is_empty(),"保存失败仍未收录且原档保留")
	model._store=original_store
	var accepted:Dictionary=session.router.finish(result)
	check(accepted.ok,"真实战果保存")
	var rows:=Recovery.earned(model.safe_snapshot(),model._catalog)
	check(accepted.get("new_recoveries")==rows and not rows.is_empty(),"首收回执只由已提交战果的回收册派生")
	check(rows.map(func(row):return row.id)==preview.map(func(row):return row.id),"实际首收与胜前预测敌种一致")
	check(rows.all(func(row):return not row.preview and row.battle_id==result.battle_id and not row.tradable and not row.consumable and not row.mainline_key),"永久回收有真实来源且不可售卖/消耗/冒充主线钥匙")
	check(not rows.any(func(row):return row.id=="forged_control_pin"),"忽略战斗方伪造的掉落声明")
	var repeated:Dictionary=session.router.finish(result)
	check(repeated.ok and repeated.get("new_recoveries",[]).is_empty() and Recovery.earned(model.safe_snapshot(),model._catalog)==rows,"重复胜利交付不重播首收或新增记录")
	var resumed:=Session.new();check(resumed.resume().ok,"真实新会话续档")
	check(Recovery.earned(resumed.campaign.safe_snapshot(),resumed.campaign._catalog)==rows,"继续游戏从原胜利完整复原回收册")
	resumed.close();session.close();print("RECOVERY_REAL_COMMANDS:",commands);_finish()
func _finish()->void:
	print("RECOVERY_CAMPAIGN:",assertions," assertions, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
