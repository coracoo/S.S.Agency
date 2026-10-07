# Transaction fixture, deliberately not evidence of human or real-combat completion.
extends RefCounted
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
static func victory(model: RefCounted, started: Dictionary) -> Dictionary:
	var roster: Array[Dictionary]=[]
	for id in model.safe_snapshot().party: roster.append(started.setup.actors[id].duplicate(true))
	return {"battle_id":started.battle_id,"outcome":"victory","roster":roster,"inventory":started.setup.inventory.duplicate(true),"xp":started.xp,"story_patch":started.story_patch.duplicate(true),"replay":{}}
static func complete_first(model: RefCounted) -> bool:
	for id in range(1,6):
		for event in Chapters.events(id):
			if event=="dialogue:hd5": continue
			if not model.commit_chapter_event(model.safe_snapshot().world,event).ok: return false
		var world: Dictionary=model.safe_snapshot().world
		var started: Dictionary=model.begin_battle(str(Chapters.night(id).encounter_id),world,Chapters.battle_patch(world))
		if not started.ok or not model.apply_result(victory(model,started)).ok: return false
		if id==5 and not model.commit_chapter_event(model.safe_snapshot().world,"dialogue:hd5").ok: return false
		if not model.advance_chapter(model.safe_snapshot().world).ok: return false
	return model.choose_resolution(model.safe_snapshot().world,"sendoff").ok and model.finish_ending(model.safe_snapshot().world).ok
