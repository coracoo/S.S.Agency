# 仅供事务测试：用明确标记的胜利夹具走正式模型，不作为真实战斗通关证据。
extends RefCounted
const Chapters=preload("res://scripts/campaign/chapter_catalog.gd")
const Saga=preload("res://scripts/campaign/saga_catalog.gd")
static func finish_battle(session:RefCounted,started:Dictionary)->bool:
	if not started.get("ok",false):return false
	var roster:Array[Dictionary]=[]
	for id in session.campaign.safe_snapshot().party:roster.append(started.setup.actors[id].duplicate(true))
	return session.router.finish({"battle_id":started.battle_id,"outcome":"victory","roster":roster,"inventory":started.setup.inventory.duplicate(true),"rewards":started.rewards.duplicate(true),"story_patch":started.story_patch.duplicate(true),"replay":{}}).ok
static func enter_saga(session:RefCounted)->bool:
	if not session.start_new(true).ok:return false
	for night in range(1,6):
		for event in Chapters.events(night):
			if event=="dialogue:hd5":continue
			if not session.commit_event(session.campaign.safe_snapshot().world,event).ok:return false
		if not finish_battle(session,session.begin_encounter(session.campaign.safe_snapshot().world,Chapters.night(night).clue_id)):return false
		if night==5 and not session.commit_event(session.campaign.safe_snapshot().world,"dialogue:hd5").ok:return false
		if not session.advance_night(session.campaign.safe_snapshot().world).ok:return false
	return session.choose_resolution(session.campaign.safe_snapshot().world,"sendoff").ok and session.finish_ending(session.campaign.safe_snapshot().world).ok and session.campaign.continue_saga().ok
static func through(session:RefCounted,target:String)->bool:
	var model:RefCounted=session.campaign
	for step in 90:
		var saved:Dictionary=model.safe_snapshot()
		if saved.saga.completed.has(target):return true
		var id:String=saved.saga.active_scene if not saved.saga.active_scene.is_empty() else saved.saga.scene
		var optional:Dictionary={"C2-05":"C2-S01","C3-06":"C3-S01","C4-02":"C4-S01","C5-02":"C5-S01"}
		if saved.saga.active_scene.is_empty() and optional.has(id) and not saved.saga.completed.has(optional[id]):id=optional[id]
		if id.is_empty() or not model.begin_saga_scene(saved.world,id).ok:return false
		saved=model.safe_snapshot()
		var options:Array=Saga.eligible_choices(Saga.scene(id),saved.saga)
		if not options.is_empty():
			var selected:String={"C3-06":"b"}.get(id,str(options[0].id))
			if not model.choose_saga_option(saved.world,id,selected).ok:return false
		saved=model.safe_snapshot()
		if not saved.world.story_encounter.is_empty() and not saved.saga.battles.has(id):
			if not finish_battle(session,session.begin_encounter(saved.world,id)):return false
		if not model.complete_saga_scene(model.safe_snapshot().world,id).ok:return false
	return false
