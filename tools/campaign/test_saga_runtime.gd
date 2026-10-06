# 六地区呈现以真实会话验收；状态夹具不冒充人工完整通关。
extends SceneTree
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Saga = preload("res://scripts/campaign/saga_catalog.gd")
var failures: Array[String] = []
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); printerr("ASSERT FAIL: ", message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _run() -> void:
	check(ResourceLoader.exists(Saga.SCENE_PATH), "后六章必须有真实可加载探索场景")
	check(ResourceLoader.exists(Saga.ENDING_PATH), "终章必须有独立结案场景")
	check(ResourceLoader.exists("res://scripts/campaign/saga_npc_art.gd"),"后章居民必须有独立原图登记加载器")
	if not ResourceLoader.exists(Saga.SCENE_PATH) or not ResourceLoader.exists(Saga.ENDING_PATH):
		_finish(); return
	var residents = load("res://scripts/campaign/saga_npc_art.gd")
	for speaker in residents.data().get("characters",{}):
		check(residents.definition(speaker).ok,"新增居民图格与锚点验证："+str(speaker))
	var identity_nodes: Dictionary = load("res://scripts/campaign/saga_stage.gd").saga_dialogue_nodes([{ "speaker":"凛音的镜影", "text":"影像" }])
	check(identity_nodes.line_0.name == "凛音的镜影" and identity_nodes.line_0.speaker == "rinne","镜影沿用当前原图但保留明确影像署名")
	check(residents.portrait("老梁").ok and residents.portrait("阿诚").ok,"老梁阿诚复用原交付半身图")
	check(str(residents.portrait("老梁").source_path).ends_with("liang_half.png"),"旧居民半身立绘来源元数据指向实际半身原图")
	check(not residents.portrait("未登记居民").ok,"未登记居民明确报告缺图而非挪用同行形象")
	var sheet:=ImageTexture.create_from_image(Image.create(100,100,false,Image.FORMAT_RGBA8))
	var valid_record: Dictionary={"speaker":"裁切验收","world_region":[0,0,40,100],"portrait_region":[40,0,60,80],"body_anchor":[20,98],"crown_y":2,"height_cm":170}
	check(residents.from_record(valid_record,sheet).ok,"居民整身与半身独立裁取原图区域")
	valid_record.portrait_region=[70,0,60,80]
	check(not residents.from_record(valid_record,sheet).ok,"拒绝超出原图的跨格人物裁取")
	var session := Session.new()
	check(session.start_new(true).ok, "建立真实正式会话")
	check(_finish_first(session), "测试夹具经第一章事务进入结案")
	check(session.campaign.continue_saga().ok, "继续第二章事务成功")
	check((await session.prepare_assets()).ok, "正式角色原图装配")
	var stage: Node3D = load(Saga.SCENE_PATH).instantiate()
	root.add_child(stage)
	for frame in 5: await physics_frame
	check(stage.ready_for_play and stage.chapter_id == 2, "第二章世界可自由探索")
	check(stage.resumes_battle_aftermath({"battles":["C6-S04"],"completed":[],"battle_encounters":{"C6-S04":"saga_c6_s04"},"events":[]},"C6-S04"),"未完战后场次应恢复战后正文")
	check(not stage.resumes_battle_aftermath({"battles":["C6-S04"],"completed":["C6-S04"],"battle_encounters":{"C6-S04":"saga_c6_s04"},"events":[{"id":"C6-S04","choice":"a"}]},"C6-S04"),"已完成可再访场次应重新按当前条件展示开场和选项")
	check(stage.resumes_battle_aftermath({"battles":["C6-04"],"completed":["C6-04"],"battle_encounters":{"C6-04":"saga_c6_04"},"events":[{"id":"C6-04","choice":"b"}]},"C6-04"),"先前暂缓已访问场次的新胜利仍恢复战后正文")
	var unrescued_speakers: Array[String] = stage.visible_speakers(Saga.scene("C2-S03"),{"flags":{"night_market_rescued":false},"completed":[],"choices":{}})
	check(unrescued_speakers.has("阿杏") and not unrescued_speakers.has("阿柳"),"地图人物也按当前救援条件筛选，不提前显示待救者")
	check(stage.confirmed_choice({"story_scene":"C7-09","story_choice":"d"}).id == "d","重访终章方案中断后从当前世界恢复已确认选项")
	var deferred: Dictionary = Saga.initial("seal_monitoring")
	deferred.completed = ["C2-01","C2-02","C2-03","C2-04","C2-S01"]
	deferred.choices["C2-S01"] = "b"
	check(stage.journal_pending(Saga.chapter(2),deferred).any(func(entry): return entry.id == "C2-S01"),"手帖继续列出已暂缓、仍可补救的后巷救援")
	deferred.flags.night_market_rescued = true
	check(not stage.journal_pending(Saga.chapter(2),deferred).any(func(entry): return entry.id == "C2-S01"),"真正救援完成后不再假列未结事项")
	check(stage.first_chapter_record({"resolution":"seal_monitoring","saga":{"flags":{"responsibility_resolved":true}}}).contains("后续已完成送行"),"手帖保留历史镇守选择并正确呈现后来送行已完成")
	check(stage.first_chapter_record({"resolution":"seal_monitoring","saga":{"flags":{"responsibility_resolved":false}}}).contains("责任未了"),"尚未履责时不会假写已交接")
	check(stage.player is CharacterBody3D and stage.camera_rig.camera is Camera3D, "保留真实人物碰撞与3D相机")
	check(stage._geometry.get_child_count() > 2, "场景加载真实地区几何")
	var before: Dictionary = stage.export_world()
	stage._open_map()
	check(stage._mode == "map" and not stage.controls_enabled, "打开地图锁住移动")
	check(stage._modal.get_node_or_null("SagaRegionMap") != null, "地图包含可行走范围及位置")
	stage._resume_explore()
	check(stage.export_world() == before and not stage._confirm_armed, "关闭地图不改世界且须松键")
	stage._confirm_armed = true
	check(not stage.request_interaction("C2-03"), "不能远程触发未开放场次")
	check(stage.request_interaction("C2-01"), "抵达街口可以调查批准开场")
	check(session.campaign.safe_snapshot().saga.active_scene == "C2-01", "对白开始前已保存活动场次")
	check(stage.export_world().story_scene == "C2-01", "呈现快照保留当前场次")
	check(not stage.controls_enabled and not stage.request_interaction("C2-01"), "对白期间重复输入不能再开事件")
	_finish_lines(stage)
	check(session.campaign.safe_snapshot().saga.completed.has("C2-01") and stage._mode == "explore", "开场完整结束后才提交并恢复探索")
	_move_to(stage,"inn")
	check(stage.request_interaction("C2-02"), "走到客栈后触发第二场")
	_finish_lines(stage)
	_move_to(stage,"alley")
	check(stage.request_interaction("C2-03"), "走到巷口后触发护送遭遇")
	_finish_lines(stage)
	check(stage._mode == "battle_cue" and not session.campaign.safe_snapshot().saga.flags.street_guests_safe, "战斗cue独立显示，战前不冒写护送成功")
	check(stage.has_method("_postpone_battle"),"战前可保留选择并返回实地歇脚")
	if stage.has_method("_postpone_battle"):
		stage._postpone_battle()
		check(stage._mode == "explore" and session.campaign.safe_snapshot().saga.active_scene == "C2-03","暂缓应战不清除已保存场次")
		check(stage._targets.any(func(target): return target.id == "@rest"),"活动战斗场次期间仍能走到休整点")
		_move_to(stage,"rest")
		check(stage.request_interaction("@rest") and stage._mode == "explore","实地歇脚可恢复资源并回探索")
		check(session.campaign.safe_snapshot().saga.active_scene == "C2-03","休息不吞掉未完战斗")
		check(stage._targets.any(func(target): return target.id == "@supply"),"活动场次期间仍可找到实地补给点")
		_move_to(stage,"shop")
		check(stage.request_interaction("@supply") and stage._mode == "field_shop","实地补给不另开故事场次")
		stage._buy_field_item("healing_potion")
		check(session.campaign.safe_snapshot().saga.active_scene == "C2-03" and stage.export_world().story_scene == "C2-03","补给购买保留当前遭遇检查点")
		stage._resume_explore()
		_move_to(stage,"alley")
		check(stage.request_interaction("C2-03"),"歇脚后回原处继续已保存遭遇")
		_finish_lines(stage)
	var begun: Dictionary = session.begin_encounter(stage.export_world(),"C2-03")
	check(begun.ok,"真实RPG入口保存后章战斗检查点")
	var roster: Array[Dictionary] = []
	for id in session.campaign.safe_snapshot().party: roster.append(begun.setup.actors[id].duplicate(true))
	var won: Dictionary = session.router.finish({"battle_id":begun.battle_id,"outcome":"victory","roster":roster,"inventory":begun.setup.inventory.duplicate(true),"xp":begun.xp,"story_patch":begun.story_patch.duplicate(true),"replay":{}})
	check(won.ok,"战果夹具经真实事务提交")
	stage.shutdown(); stage.free()
	stage = load(Saga.SCENE_PATH).instantiate(); root.add_child(stage)
	for frame in 5: await physics_frame
	check(stage._mode == "dialogue" and stage._dialogue._text_label.text == Saga.scene("C2-03").after_lines[0].text, "战斗返场从战后原文开始，不重播战前对话")
	check(not session.campaign.safe_snapshot().saga.flags.street_guests_safe, "看完战后救援前不提前提交剧情效果")
	_finish_lines(stage)
	check(session.campaign.safe_snapshot().saga.flags.street_guests_safe and stage._mode == "explore", "战后全文播完后提交救援并恢复标记")
	_move_to(stage,"shop")
	check(stage.request_interaction("C2-04"),"抵达灯铺继续主线")
	_finish_lines(stage)
	stage._confirm_armed = true
	check(stage.request_interaction("C2-R02"),"灯铺服务在剧情开放后实地可用")
	_finish_lines(stage)
	check(stage._mode == "shop","商店对白结束后显示真实商品")
	var money: int = session.campaign.safe_snapshot().saga.coins
	var count: int = session.campaign.safe_snapshot().inventory.get("healing_potion",0)
	stage._buy_item("healing_potion")
	check(session.campaign.safe_snapshot().saga.coins == money - 18 and session.campaign.safe_snapshot().inventory.get("healing_potion",0) == count + 1,"交易在成功对白前原子保存银钱与库存")
	check(stage._dialogue._text_label.text == Saga.scene("C2-R02").event_lines.shop_success[0].text,"购买成功才播放成交原文")
	_finish_lines(stage)
	while session.campaign.safe_snapshot().saga.coins >= 18:
		stage._buy_item("healing_potion"); _finish_lines(stage)
	var insufficient_before: Dictionary = session.campaign.safe_snapshot()
	stage._buy_item("healing_potion")
	check(session.campaign.safe_snapshot() == insufficient_before,"钱不足的交易不修改库存或资金")
	check(stage._dialogue._text_label.text == Saga.scene("C2-R02").event_lines.shop_insufficient[0].text,"钱不足才播放对应原文")
	_finish_lines(stage); stage._leave_shop()
	check(stage._mode == "explore" and session.campaign.safe_snapshot().saga.completed.has("C2-R02"),"离开商店后保存此次访问")
	var physical_points: Dictionary = {}
	for target in stage._targets: physical_points[str(target.position)] = true
	check(stage._story_markers.get_child_count() == physical_points.size(),"同一物理锚点的主线、闲谈与休整共用一个可读标记")
	var fresh_world: Dictionary = session.campaign.safe_snapshot().world
	session.router._return_world = before.duplicate(true)
	stage.shutdown(); stage.free()
	stage = load(Saga.SCENE_PATH).instantiate(); root.add_child(stage)
	for frame in 5: await physics_frame
	check(stage.export_world().event_flags == fresh_world.event_flags,"共用后章场景路径不允许旧战斗返回缓存覆盖新检查点")
	# 单测商城分支路由；仅用批准数据搭呈现，跨章完成事务若误触会被模型拒绝。
	for shop_id in ["C6-R01","C7-R01"]:
		stage.begin_operation("choice"); stage._active_entry = Saga.scene(shop_id); stage._selected_option = Saga.choice(shop_id,"a")
		stage._after_option()
		check(stage._mode == "shop","购物选择必须打开真实商品列表："+shop_id)
		stage._active_entry = {}; stage._selected_option = {}; stage._resume_explore()
	# 纯呈现夹具只读取终章方案，取消不得对当前真实第二章档写任何内容。
	var safe_before: Dictionary = session.campaign.safe_snapshot()
	stage.begin_operation("choice"); stage._active_entry = Saga.scene("C7-09")
	stage._preview_option("d"); _finish_lines(stage)
	check(stage._mode == "confirmation" and session.campaign.safe_snapshot() == safe_before,"预览终章后果并非确认，不锁定任何选择")
	stage._cancel_option(); _finish_lines(stage)
	check(stage._mode == "choice" and stage._selected_option.is_empty() and session.campaign.safe_snapshot() == safe_before,"取消后二次说明并返回完整方案，不应用效果")
	stage._active_entry = {}; stage._resume_explore()
	# 长后果确认不可被按钮单行裁掉；菜单中的免费休息必须由实地休整点提供。
	stage._generation += 1
	if is_instance_valid(stage._dialogue): stage._dialogue.abort(); stage._dialogue.queue_free()
	stage._dialogue = null
	stage._show_modal("确认", "后果", [{"text":"我知道同伴反对，也知道城中人会失去选择，仍由我保留并重新接通。", "call":Callable()}])
	check(stage._modal_buttons[0].get_node_or_null("ActionText") != null, "长确认选项使用完整换行正文")
	stage._resume_explore()
	stage._open_party("menu")
	check(not stage._party_panel._hud.rest.visible, "探索菜单不能绕过实地休整锚点")
	stage._release_party_panel()
	stage.shutdown(); stage.free()
	await _confirmed_plan_restart(session)
	session.close()
	_finish()
func _finish_first(session: RefCounted) -> bool:
	for night in range(1,6):
		for event in Chapters.events(night):
			if event != "dialogue:hd5" and not session.commit_event(session.campaign.safe_snapshot().world,event).ok: return false
		var start: Dictionary = session.begin_encounter(session.campaign.safe_snapshot().world,Chapters.night(night).clue_id)
		if not start.ok: return false
		var roster: Array[Dictionary] = []
		for id in session.campaign.safe_snapshot().party: roster.append(start.setup.actors[id].duplicate(true))
		if not session.router.finish({"battle_id":start.battle_id,"outcome":"victory","roster":roster,"inventory":start.setup.inventory.duplicate(true),"xp":start.xp,"story_patch":start.story_patch.duplicate(true),"replay":{}}).ok: return false
		if night == 5 and not session.commit_event(session.campaign.safe_snapshot().world,"dialogue:hd5").ok: return false
		if not session.advance_night(session.campaign.safe_snapshot().world).ok: return false
	return session.choose_resolution(session.campaign.safe_snapshot().world,"sendoff").ok and session.finish_ending(session.campaign.safe_snapshot().world).ok
func _finish() -> void:
	print("SAGA_RUNTIME_ASSERTIONS:",assertions," FAILURES:",failures.size())
	quit(0 if failures.is_empty() else 1)

func _finish_lines(stage: Node) -> void:
	var steps := 0
	while is_instance_valid(stage._dialogue) and steps < 8:
		steps += 1
		stage._dialogue._present_node("")

func _move_to(stage: Node, location: String) -> void:
	var world: Dictionary = stage.export_world()
	world.position = stage.config.anchors[location].duplicate()
	check(stage.restore_world(world).ok,"调查点可恢复真实位置：" + location)
	stage._confirm_armed = true

# 正式事务走到终战，先确认一次方案，再退出未胜战斗重选；历史completed不能抹掉新确认。
func _confirmed_plan_restart(session: RefCounted) -> void:
	var reached := _reach_final_choice(session)
	check(reached,"完整正式事务夹具可到终章选择")
	if not reached: return
	var model: RefCounted=session.campaign
	var world: Dictionary=model.safe_snapshot().world.duplicate(true)
	world.position=Saga.anchors(7)[Saga.scene("C7-09").location].duplicate()
	check(session.save_world(world).ok,"终章方案实地位置可保存")
	check(model.begin_saga_scene(model.safe_snapshot().world,"C7-09").ok and model.choose_saga_option(model.safe_snapshot().world,"C7-09","a").ok and model.complete_saga_scene(model.safe_snapshot().world,"C7-09").ok,"首次终章方案通过真实确认提交")
	check(model.begin_saga_scene(model.safe_snapshot().world,"C7-10").ok,"进入已选方案末战场次")
	var battle: Dictionary=session.begin_encounter(model.safe_snapshot().world,"C7-10")
	var defeated_roster: Array[Dictionary]=[]
	for actor in model.safe_snapshot().party:
		var fallen: Dictionary=battle.setup.actors[actor].duplicate(true); fallen.hp=0; defeated_roster.append(fallen)
	var defeat: Dictionary=session.router.finish({"battle_id":battle.battle_id,"outcome":"defeat","roster":defeated_roster,"inventory":battle.setup.inventory.duplicate(true),"xp":0,"story_patch":{},"replay":{}})
	check(battle.ok and defeat.ok and model.leave_saga_battle().ok,"败北后返回整备保留战前资源并进入重试对白")
	check(model.begin_saga_scene(model.safe_snapshot().world,"C7-R04").ok and model.choose_saga_option(model.safe_snapshot().world,"C7-R04","b3").ok and model.complete_saga_scene(model.safe_snapshot().world,"C7-R04").ok,"明确返回方案前置")
	check(model.begin_saga_scene(model.safe_snapshot().world,"C7-09").ok and model.choose_saga_option(model.safe_snapshot().world,"C7-09","d").ok,"历史已完成选择仍可正式确认新分支")
	check(model.safe_snapshot().saga.completed.has("C7-09") and model.safe_snapshot().world.story_choice=="d","重选确认与历史已完成记录同时存在")
	session.close()
	var resumed:=Session.new()
	check(resumed.resume().ok and (await resumed.prepare_assets()).ok,"已确认重选方案可退出会话再续档")
	var stage: Node3D=load(Saga.SCENE_PATH).instantiate(); root.add_child(stage)
	for frame in 5: await physics_frame
	check(stage.ready_for_play and stage._selected_option.get("id","")=="d","真实舞台续档恢复新确认，不重新弹出被模型锁定的选择")
	check(is_instance_valid(stage._dialogue) and stage._dialogue._text_label.text==Saga.choice("C7-09","d").confirmation.lines[0].text,"恢复从已确认答复播放，不再重问是否同意")
	stage.shutdown(); stage.free(); resumed.close()

func _reach_final_choice(session: RefCounted) -> bool:
	var choices: Dictionary={"C2-S01":"a","C3-S01":"a","C4-S01":"a","C5-S01":"a","C3-06":"b","C5-08":"a","C6-04":"a","C6-05":"a","C6-S01":"a","C6-S03":"a","C6-S04":"a","C6-14":"a","C7-01":"a"}
	var optional: Dictionary={"C2-05":"C2-S01","C3-06":"C3-S01","C4-02":"C4-S01","C5-02":"C5-S01"}
	for step in 180:
		var state: Dictionary=session.campaign.safe_snapshot(); var saga: Dictionary=state.saga
		if saga.scene=="C7-09" and saga.active_scene.is_empty(): return true
		var id: String=saga.active_scene if not saga.active_scene.is_empty() else saga.scene
		if saga.active_scene.is_empty() and optional.has(id) and not saga.completed.has(optional[id]): id=optional[id]
		if saga.active_scene.is_empty() and saga.scene=="C6-13":
			if not saga.flags.clinic_awake: id="C6-S01" if not saga.completed.has("C6-S01") else "C6-S02"
			elif not saga.flags.evacuation_route_ready: id="C6-S03"
			elif not saga.flags.alley_rescued: id="C6-S04"
		var result: Dictionary=session.campaign.begin_saga_scene(state.world,id)
		if not result.ok: printerr("RESTART_FIXTURE_BEGIN:",id,result); return false
		state=session.campaign.safe_snapshot()
		var options: Array=Saga.eligible_choices(Saga.scene(id),state.saga)
		if not options.is_empty():
			result=session.campaign.choose_saga_option(state.world,id,str(choices.get(id,options[0].id)))
			if not result.ok: printerr("RESTART_FIXTURE_CHOICE:",id,result); return false
		state=session.campaign.safe_snapshot()
		if not state.world.story_encounter.is_empty() and not state.saga.battles.has(id):
			var started: Dictionary=session.begin_encounter(state.world,id)
			if not started.ok: printerr("RESTART_FIXTURE_BATTLE:",id,started); return false
			var roster: Array[Dictionary]=[]
			for actor in session.campaign.safe_snapshot().party: roster.append(started.setup.actors[actor].duplicate(true))
			result=session.router.finish({"battle_id":started.battle_id,"outcome":"victory","roster":roster,"inventory":started.setup.inventory.duplicate(true),"xp":started.xp,"story_patch":started.story_patch.duplicate(true),"replay":{}})
			if not result.ok: printerr("RESTART_FIXTURE_RESULT:",id,result); return false
		result=session.campaign.complete_saga_scene(session.campaign.safe_snapshot().world,id)
		if not result.ok: printerr("RESTART_FIXTURE_COMPLETE:",id,result); return false
	return false
