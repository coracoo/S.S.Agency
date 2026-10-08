# 仅供事务测试：用明确标记的胜利夹具走正式模型，不作为真实战斗通关证据。
extends RefCounted
const Chapters=preload("res://scripts/campaign/chapter_catalog.gd")
const Saga=preload("res://scripts/campaign/saga_catalog.gd")
const Mechanisms=preload("res://scripts/campaign/mechanism_rules.gd")
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
static func through(session:RefCounted,target:String,stop_before:bool=false,decisions:Dictionary={})->bool:
	var model:RefCounted=session.campaign
	for step in 90:
		var saved:Dictionary=model.safe_snapshot()
		if stop_before and (saved.saga.active_scene==target or (saved.saga.active_scene.is_empty() and saved.saga.scene==target)):return true
		if not stop_before and saved.saga.completed.has(target):return true
		var id:String=saved.saga.active_scene if not saved.saga.active_scene.is_empty() else saved.saga.scene
		var optional:Dictionary={"C2-05":"C2-S01","C3-06":"C3-S01","C4-02":"C4-S01","C5-02":"C5-S01"}
		if saved.saga.active_scene.is_empty() and optional.has(id) and not saved.saga.completed.has(optional[id]):id=optional[id]
		if id.is_empty() or not model.begin_saga_scene(saved.world,id).ok:return false
		saved=model.safe_snapshot()
		var options:Array=Saga.eligible_choices(Saga.scene(id),saved.saga)
		if not options.is_empty():
			var selected:String=decisions.get(id,{"C3-06":"b"}.get(id,str(options[0].id)))
			if not model.choose_saga_option(saved.world,id,selected).ok:return false
		saved=model.safe_snapshot()
		if not saved.world.story_encounter.is_empty() and not saved.saga.battles.has(id):
			if not complete_mechanisms(model,id,true):return false
			saved=model.safe_snapshot()
			if not finish_battle(session,session.begin_encounter(saved.world,id)):return false
		if not complete_mechanisms(model,id):return false
		if not model.complete_saga_scene(model.safe_snapshot().world,id).ok:return false
	return false

# 测试夹具逐站调用正式事务，不跳过门禁。它验证模型，不声称角色已经真实走过这些坐标。
static func complete_mechanisms(model:RefCounted,scene_id:String,before_battle:bool=false)->bool:
	if model.safe_snapshot().get("progression_version",0)<3:return true
	for attempt in 60:
		var saved:Dictionary=model.safe_snapshot()
		var errors:Array=Mechanisms.battle_errors(saved,scene_id) if before_battle else Mechanisms.completion_errors(saved,scene_id)
		if errors.is_empty():return true
		var progressed:=false
		for target in Mechanisms.targets(saved):
			var current:Dictionary=Mechanisms.view_state(saved,target.mechanism_id)
			var operators:Array=saved.roster.keys()
			operators.sort_custom(func(a,b):return str(a)!=current.first_actor and str(b)==current.first_actor)
			for operator in operators:
				var world:Dictionary=saved.world.duplicate(true);world.position=target.position.duplicate()
				var preview:Dictionary=Mechanisms.preview(saved,world,target.mechanism_id,target.action_id,operator)
				if not preview.ok:continue
				var after:Dictionary=Mechanisms.view_state(preview.candidate,target.mechanism_id)
				if after.step<=current.step and after.complete==current.complete:continue
				var result:Dictionary=model.commit_mechanism(world,target.mechanism_id,target.action_id,operator)
				if not result.ok:printerr("FIXTURE_MECHANISM:",result.error);return false
				progressed=true;break
			if progressed:break
		if not progressed:printerr("FIXTURE_MECHANISM_STALLED:",scene_id," ",errors);return false
	return false
