# 小资源走真实章节、战斗、读档与返场，避免测试预先加载全部正式图集。
extends "res://tools/characters/test_texture_contexts.gd"
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Stage = preload("res://scripts/campaign/chapter_stage.gd")
const View = preload("res://scripts/rpg/ui/battle_view.gd")
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(1); return
	create_timer(30.0).timeout.connect(func(): printerr("FAIL: 阶段场景测试未正常结束"); quit(1))
	var supported := false
	for method in Session.new().get_method_list():
		if method.name == "prepare_assets": supported = method.args.size() >= 1
	check(supported,"正式会话支持阶段预热参数")
	if not supported: _finish(); return
	var paths := {}
	for identity in Bundle.FORMS:
		for form in Bundle.FORMS[identity]:
			var key: String = Bundle.asset_key(identity,form)
			var manifest := _fixture(identity,form)
			manifest["portrait_source_manifest"] = "res://assets/chars/pixel/%s/high_detail_complete/manifest.json" % key
			paths[key] = _write(manifest,key)
	var session := Session.new()
	check(session.start_new(true).ok,"在核验隔离目录建立正式新档")
	session.bundle = Bundle.new(paths)
	var party: Array[String] = ["p_healer","p_mage","p_controller"]
	check(session.campaign.set_party(party).ok,"正式编队可不包含凛音")
	for event in ["dialogue:a1","dialogue:r1","dialogue:h1"]:
		check(session.commit_event(session.campaign.safe_snapshot().world,event).ok,"正式战前调查："+event)
	check((await session.call("prepare_assets","battle")).ok,"模拟上一战斗阶段已预热")
	var old: WeakRef = weakref(session.bundle.get_definition("healer").frames.get_frame_texture("attack",0).atlas)
	var stage := Stage.new()
	root.add_child(stage)
	check(old.get_ref() == null, "新世界场景预热开始前即释放旧战斗缓存，避免整组重叠峰值")
	for tick in 100:
		await process_frame
		if stage.ready_for_play or not stage.last_error.is_empty(): break
	check(stage.ready_for_play,"战斗上下文返场前先恢复世界动作")
	check(stage.player != null and stage.player.form_id == "healer","无凛音编队直接以已选苏合建立世界人物")
	check(not session.bundle._definitions.has("rinne") and session.bundle._definitions.size() == 4,"世界只持有所选三身份及焰华双形态")
	check(old.get_ref() == null,"返场释放战斗专用纹理")
	var before: Dictionary = session.campaign.safe_snapshot()
	stage.shutdown(); stage.free()
	check(session.begin_encounter(before.world,"basin_reflection").ok,"正式事务保存战前快照")
	var safe: Dictionary = session.campaign.safe_snapshot()
	var view := View.new(); view.router = session.router
	root.add_child(view)
	check(view._asset_loading and view.engine == null,"战斗预热期间尚未创建推进引擎，不能提前行动")
	view.select_command("attack_physical"); view.confirm_command()
	check(session.campaign.safe_snapshot() == safe,"预热期间重复点击不改安全档")
	for tick in 100:
		await process_frame
		if not view._asset_loading: break
	check(not view._hd_failed and view._hd_views.size() == 3 and view.engine != null,"完整战斗动作预热之后才构建三位演员")
	check(not session.bundle.get_definition("healer").frames.has_animation("walk") and session.bundle.get_definition("homura","mage").frames.has_animation("attack"),"战斗保留双形态且释放世界动作")
	view._cancel_presentation()
	var engine_before: Dictionary = view.engine.snapshot()
	await view._retry_hd_assets()
	check(view.engine.snapshot() == engine_before,"资源重试不重建/推进已运行引擎，不重复伤害或消耗")
	view.select_command("attack_physical")
	var target := ""
	for id in view.engine.snapshot().actors:
		if view.engine.snapshot().actors[id].side == "enemy": target = id; break
	view.select_target(target)
	var target_before: int = view.engine.snapshot().actors[target].hp
	view.confirm_command()
	var committed: Dictionary = view.engine.snapshot()
	check(committed.actors[target].hp < target_before and committed.phase == "action_end", "真实攻击已提交一次且正在等待表现后推进")
	await view._retry_hd_assets()
	for tick in 60:
		await process_frame
		if not view.processing: break
	check(view.engine.snapshot().actors[target].hp == committed.actors[target].hp, "表现中重试不再次应用已经提交的攻击伤害")
	check(view.engine.snapshot().phase != "action_end" and not view.processing, "表现中重试后正常恢复下一合法行动槽，不悬停空active_actor")
	view.free()
	var resumed := Session.new()
	check(resumed.resume().ok,"战前关闭后仍可从实际磁盘恢复")
	resumed.bundle = Bundle.new(paths)
	check((await resumed.prepare_assets()).ok and resumed.bundle.get_definition("healer").get("context") == "battle","继续游戏按战前安全档自动选择battle预热")
	var started: Dictionary = resumed.router._setup
	var roster: Array[Dictionary] = []
	for id in resumed.campaign.safe_snapshot().party: roster.append(started.setup.actors[id].duplicate(true))
	var result := {"battle_id":started.battle_id, "outcome":"victory", "roster":roster, "inventory":started.setup.inventory.duplicate(true), "xp":started.xp, "story_patch":started.story_patch.duplicate(true), "replay":{}}
	check(resumed.router.finish(result).ok, "正式胜利事务提交安全奖励")
	var returned := Stage.new(); root.add_child(returned)
	for tick in 100:
		await process_frame
		if returned.ready_for_play or not returned.last_error.is_empty(): break
	check(returned.ready_for_play and resumed.bundle.get_definition("healer").context == "world", "已保存胜利后真实返场重新预热世界组")
	check(resumed.campaign.safe_snapshot().pending_battle.is_empty(), "资源返场不复写战前状态或丢失已保存胜利")
	returned.free(); resumed.close()
	await _session_request_checks(paths)
	await _cancelled_scene_load(paths)
	await _failed_scene_load(paths)
	_finish()
func _cancelled_scene_load(paths: Dictionary) -> void:
	var session := Session.new()
	check(session.start_new(true).ok,"取消夹具重开正式安全档")
	session.bundle = Bundle.new(paths)
	check((await session.call("prepare_assets","world")).ok,"取消夹具先有世界资源")
	for event in ["dialogue:a1","dialogue:r1","dialogue:h1"]: session.commit_event(session.campaign.safe_snapshot().world,event)
	check(session.begin_encounter(session.campaign.safe_snapshot().world,"basin_reflection").ok,"取消夹具写入真实战前状态")
	var safe: Dictionary = session.campaign.safe_snapshot()
	var view := View.new(); view.router = session.router
	root.add_child(view)
	check(view._asset_loading,"移除场景时预热确实仍进行中")
	view.free()
	await process_frame
	check(not session.bundle.is_preparing() and session.bundle._definitions.is_empty(),"退出中断预热后不保留旧阶段，且不得发布已移除场景资源")
	check(session.campaign.safe_snapshot() == safe and session.router.engine == null,"取消预热不推进模型也不丢战前档")
	session.close()

func _failed_scene_load(paths: Dictionary) -> void:
	var session := Session.new()
	check(session.start_new(true).ok, "失败加载夹具建立安全新档")
	session.bundle = Bundle.new(paths)
	check((await session.call("prepare_assets", "world")).ok, "失败加载夹具已备世界动作")
	var original := FileAccess.get_file_as_string(paths.rinne)
	var broken: Dictionary = JSON.parse_string(original)
	broken.packed_frames.attack.atlas = "user://missing_attack.png"
	_write(broken, "rinne")
	for event in ["dialogue:a1", "dialogue:r1", "dialogue:h1"]: session.commit_event(session.campaign.safe_snapshot().world, event)
	check(session.begin_encounter(session.campaign.safe_snapshot().world, "basin_reflection").ok, "失败加载夹具建立真实战前检查点")
	var safe: Dictionary = session.campaign.safe_snapshot()
	var view := View.new(); view.router = session.router
	root.add_child(view)
	for tick in 100:
		await process_frame
		if not view._asset_loading: break
	check(view._hd_failed and is_instance_valid(view._asset_error_panel) and view.engine == null, "图集失败显示既有重试面板且不启动战斗")
	check(session.campaign.safe_snapshot() == safe and session.bundle._definitions.is_empty(), "失败保留安全档但无旧阶段缓存，不发布部分战斗资源")
	_write(JSON.parse_string(original), "rinne")
	await view._retry_hd_assets()
	check(not view._hd_failed and view.engine != null and view._hd_views.size() == 3, "修复真实资源后可重试进入同一遭遇")
	view.free(); session.close()

func _prepare_session(session: RefCounted, context: String, output: Dictionary) -> void:
	output.result = await session.prepare_assets(context)
	output.done = true
func _session_request_checks(paths: Dictionary) -> void:
	var session := Session.new()
	check(session.start_new(true).ok, "代际夹具创建真实安全档")
	session.bundle = Bundle.new(paths)
	var old := {"done":false, "result":{}}
	_prepare_session(session, "world", old)
	var request := session.asset_generation
	session.cancel_asset_preparation(request)
	var recent := {"done":false, "result":{}}
	_prepare_session(session, "battle", recent)
	session.cancel_asset_preparation(request)
	for tick in 20:
		await process_frame
		if recent.done and old.done: break
	check(old.done and old.result.get("cancelled",false) and recent.done and recent.result.ok, "过期场景取消不能取消后启动的阶段请求")
	check(session.bundle.get_definition("rinne").context == "battle", "新阶段不会被旧session协程清空")
	var changed := {"done":false, "result":{}}
	_prepare_session(session,"world",changed)
	var party: Array[String] = ["p_healer","p_mage","p_controller"]
	check(session.campaign.set_party(party).ok, "异步途中以真实事务变更所选队伍")
	for tick in 20:
		await process_frame
		if changed.done: break
	check(changed.done and changed.result.get("cancelled",false) and session.bundle._definitions.is_empty(), "队伍已变更时旧选择资源不能发布")
	check((await session.prepare_assets()).ok and session.bundle._definitions.size() == 4 and session.bundle.get_definition("rinne").is_empty(), "重试只持有新编队与焰华双形态")
	session.close()
