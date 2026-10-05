# 景深为本次会话的呈现设置；战斗/返回舞台沿用，不污染正式剧情存档。
extends SceneTree
const Session=preload("res://scripts/campaign/chapter_session.gd")
const Chapters=preload("res://scripts/campaign/chapter_catalog.gd")
const Battle=preload("res://scripts/rpg/ui/battle_view.gd")
var failures:Array[String]=[]
func _initialize()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	_run.call_deferred()
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL:",message)
func _run()->void:
	var session:=Session.new()
	if not session.start_new(true).ok or not (await session.prepare_assets()).ok:quit(1);return
	var original:Dictionary=session.campaign.safe_snapshot().duplicate(true)
	var stage:Node3D=load(Chapters.scene_path(1)).instantiate();root.add_child(stage)
	for frame in 8:await physics_frame
	stage.set_hd2d_experiment(false)
	check(session.get_meta("hd2d_depth_enabled",true)==false,"暂停景深选项记入本次呈现会话")
	stage.free()
	stage=load(Chapters.scene_path(1)).instantiate();root.add_child(stage)
	for frame in 8:await physics_frame
	check(not stage.hd2d_experiment and not stage._hd2d_profile.effect.visible,"重建探索舞台保留关闭设置")
	check(session.campaign.safe_snapshot()==original,"呈现设置不写故事/战斗存档")
	stage.free()
	for event in ["dialogue:a1","dialogue:r1","dialogue:h1"]:
		if not session.commit_event(session.campaign.safe_snapshot().world,event).ok:quit(1);return
	if not session.begin_encounter(session.campaign.safe_snapshot().world,"basin_reflection").ok:quit(1);return
	var battle:=Battle.new();battle.router=session.router;root.add_child(battle)
	for frame in 3:await process_frame
	check(not battle._world_backdrop.get_node("BattleDepth").enabled,"战斗沿用探索的关闭景深设置")
	battle.free();session.close()
	print("DEPTH_PREFERENCE:4 assertions, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
