# 六地区真实Godot图形采集。剧情进度使用正式事务夹具；截图不冒充人工七章通关。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
const Saga = preload("res://scripts/campaign/saga_catalog.gd")
const Region = preload("res://scripts/campaign/saga_world.gd")
const BOSS_CAPTURE_SCENES := ["C2-12","C3-10","C4-09","C5-09","C5-12","C6-11","C7-05","C7-06","C7-10"]
var _output := ""
var _records: Array = []
var _failures: Array[String] = []
func _initialize() -> void:
	_output=OS.get_environment("ACT_ONE_OUTPUT")
	if OS.get_environment("RPG_TEST_ISOLATED")!="1" or _output.is_empty(): quit(2); return
	_run.call_deferred()
func _run() -> void:
	create_timer(480).timeout.connect(func(): _fail("图形采集超时，请检查错误日志"))
	root.size=Vector2i(1920,1080)
	if OS.get_environment("SAGA_CAPTURE_MODE") == "npc_art":
		await _capture_resident_art(); quit(0 if _failures.is_empty() else 1); return
	var session:=Session.new()
	if not session.start_new(true).ok or not _finish_first(session): _fail("第一章夹具失败"); return
	if not (await session.prepare_assets()).ok: _fail("人物素材装配失败"); return
	if OS.get_environment("SAGA_CAPTURE_MODE") != "boss_art":
		var ending: Node=load("res://scenes/campaign/ending.tscn").instantiate(); root.add_child(ending)
		await _capture("chapter1_downmountain",{"note":"真实已结案第一章，含第二章继续入口"})
		ending.free()
	if not session.campaign.continue_saga().ok: _fail("下山事务失败"); return
	if OS.get_environment("SAGA_CAPTURE_MODE") == "title_continue":
		session.close()
		var title: Node=load("res://scenes/campaign/title.tscn").instantiate(); root.add_child(title); current_scene=title
		await _capture("title_saved_saga",{"note":"真实标题场景；隔离正式存档已由第一章事务完成并下山"})
		title._continue()
		for frame in 180: await process_frame
		if current_scene == null or not current_scene.get("ready_for_play"):
			_fail("真实标题继续游戏未进入可玩舞台"); return
		await _capture("title_continue_saga",{"note":"真实标题继续按钮回调读取隔离正式存档，恢复第二章探索"})
		_write_capture_manifest(); Session.current.close(); quit(0 if _failures.is_empty() else 1); return
	if OS.get_environment("SAGA_CAPTURE_MODE") == "manual2":
		var live: Node = load(Saga.SCENE_PATH).instantiate(); root.add_child(live); current_scene=live
		print("SAGA_MANUAL_READY: 第二章新开场，正式事务夹具，仅隔离存档")
		return
	var captured: Dictionary={}
	var choices := {"C2-S01":"a","C3-S01":"a","C4-S01":"a","C5-S01":"a","C3-06":"b","C5-08":"a","C6-04":"a","C6-05":"a","C6-S01":"a","C6-S03":"a","C6-S04":"a","C6-14":"a","C7-01":"a","C7-09":"a"}
	var optional := {"C2-05":"C2-S01","C3-06":"C3-S01","C4-02":"C4-S01","C5-02":"C5-S01"}
	var steps:=0
	while session.campaign.safe_snapshot().story_phase!="complete" and steps<220:
		steps+=1
		var state: Dictionary=session.campaign.safe_snapshot()
		var saga: Dictionary=state.saga
		if not captured.has(saga.chapter) and OS.get_environment("SAGA_CAPTURE_MODE") != "boss_art":
			captured[saga.chapter]=true
			if not await _capture_region(session,int(saga.chapter)): return
			if OS.get_environment("SAGA_CAPTURE_MODE") == "polish" and int(saga.chapter)==4:
				_write_capture_manifest(); print("SAGA_POLISH_CAPTURE_DONE"); session.close(); quit(0 if _failures.is_empty() else 1); return
			state=session.campaign.safe_snapshot(); saga=state.saga
		var id: String=saga.active_scene if not saga.active_scene.is_empty() else saga.scene
		if saga.active_scene.is_empty() and optional.has(id) and not saga.completed.has(optional[id]): id=optional[id]
		if saga.active_scene.is_empty() and saga.scene=="C6-13":
			if not saga.flags.clinic_awake: id="C6-S01" if not saga.completed.has("C6-S01") else "C6-S02"
			elif not saga.flags.evacuation_route_ready: id="C6-S03"
			elif not saga.flags.alley_rescued: id="C6-S04"
		if id.is_empty(): _fail("意外空游标"); return
		if id=="C7-09" and OS.get_environment("SAGA_CAPTURE_MODE") != "boss_art" and not await _capture_final_choice(session): return
		state=session.campaign.safe_snapshot()
		if not session.campaign.begin_saga_scene(state.world,id).ok: _fail("无法开始："+id); return
		state=session.campaign.safe_snapshot()
		var options: Array=Saga.eligible_choices(Saga.scene(id),state.saga)
		if not options.is_empty():
			var choice: String=choices.get(id,str(options[0].id))
			if not session.campaign.choose_saga_option(state.world,id,choice).ok: _fail("无法选择："+id); return
		state=session.campaign.safe_snapshot()
		if not state.world.story_encounter.is_empty() and not state.saga.battles.has(id):
			var started: Dictionary=session.begin_encounter(state.world,id)
			if not started.ok: _fail("无法进入战斗："+id); return
			if id in (BOSS_CAPTURE_SCENES if OS.get_environment("SAGA_CAPTURE_MODE") == "boss_art" else ["C2-03","C7-10"]):
				var battle: Node=load("res://scenes/rpg/battle.tscn").instantiate(); root.add_child(battle)
				for frame in 90: await process_frame
				var enemy_ids: Array=[]
				for actor in started.setup.actors.values():
					if actor.side == "enemy": enemy_ids.append(actor.class_id)
				await _capture("battle_"+id,{"note":"真实RPG战斗场景，进度由事务夹具准备；非人工通关","scene":id,"enemy_ids":enemy_ids})
				battle.free()
			if not session.router.finish(_victory(session,started)).ok: _fail("战果事务失败："+id); return
		if not session.campaign.complete_saga_scene(session.campaign.safe_snapshot().world,id).ok: _fail("完成事务失败："+id); return
		if OS.get_environment("SAGA_CAPTURE_MODE") == "boss_art" and id == "C7-10":
			if _records.size() != BOSS_CAPTURE_SCENES.size(): _failures.append("未采齐全部目标战斗")
			_write_capture_manifest(); print("SAGA_BOSS_ART_CAPTURE_DONE:",_records.size()); session.close(); quit(0 if _failures.is_empty() else 1); return
	var final: Node=load(Saga.ENDING_PATH).instantiate(); root.add_child(final)
	await _capture("saga_dawn_ending",{"note":"全部终章后日谈已完成后的最终结案页"})
	final.free()
	_write_capture_manifest()
	session.close()
	print("SAGA_GRAPHICAL_CAPTURES:",_records.size()," FAILURES:",_failures.size())
	quit(0 if _failures.is_empty() else 1)
func _capture_region(session: RefCounted,chapter: int) -> bool:
	var stage: Node3D=load(Saga.SCENE_PATH).instantiate(); root.add_child(stage)
	for frame in 12: await physics_frame
	if not stage.ready_for_play: stage.free(); _fail("地区未就绪："+str(chapter)); return false
	await _capture("chapter%d_explore" % chapter,{"chapter":chapter,"note":"正常跟随镜头、实际探索HUD、人物及地区"})
	if chapter == 4:
		var look_world: Dictionary = stage.export_world()
		look_world.position = Region.anchors(4).corridor.duplicate()
		if not stage.restore_world(look_world).ok: _fail("镜廊机位恢复失败"); return false
		await _capture("chapter4_gallery",{"chapter":4,"note":"批准镜廊调查锚点的正常跟随镜头，位置为截图夹具"})
		look_world.position = Region.anchors(4).archive.duplicate()
		if not stage.restore_world(look_world).ok: _fail("修阵室机位恢复失败"); return false
		await _capture("chapter4_archive",{"chapter":4,"note":"批准修阵室调查锚点的正常跟随镜头，位置为截图夹具"})
	stage._open_map()
	await _capture("chapter%d_map" % chapter,{"chapter":chapter,"note":"真实可行走区域与交互点地图"})
	stage._resume_explore()
	if chapter==2:
		stage._open_pause()
		await _capture("saga_pause",{"note":"真实暂停菜单"})
		stage._open_journal()
		await _capture("saga_journal",{"note":"真实手帖目标与开放支线"})
		stage._resume_explore(); stage._open_party("menu")
		await _capture("saga_party_menu",{"note":"原人物状态与菜单美术，无远程休息按钮"})
		stage._party_panel.show_page("inventory")
		await _capture("saga_inventory",{"note":"真实道具库存与使用目标"})
		stage._party_panel.show_page("equipment")
		await _capture("saga_equipment",{"note":"真实装备与属性预览"})
		stage._release_party_panel(); stage._resume_explore(); stage._confirm_armed=true
		stage.request_interaction("C2-01")
		for frame in 40: await process_frame
		if is_instance_valid(stage._dialogue):
			for key in stage._dialogue._nodes:
				if stage._dialogue._nodes[key].speaker in ["rinne","mint","guard","homura","healer","controller"]:
					stage._dialogue._present_node(key); break
			stage._dialogue._typing=false; stage._dialogue._text_label.visible_characters=-1
		await _capture("saga_dialogue",{"note":"批准开场原文与六身份原图半身立绘"})
		stage._generation+=1
		if is_instance_valid(stage._dialogue): stage._dialogue.abort(); stage._dialogue.queue_free()
		stage._dialogue=null
	stage.set_process(false); stage.set_controls_enabled(false); stage._ui_layer.hide(); stage.set_hd2d_experiment(false)
	var camera: Camera3D=stage.camera_rig.camera
	var b: Dictionary=Region.bounds(chapter); var target:=Vector3((b.x[0]+b.x[1])*.5,0,(b.z[0]+b.z[1])*.5)
	camera.size=34; camera.global_position=target+Vector3(0,36,40); camera.look_at(target)
	await _capture("chapter%d_overview" % chapter,{"chapter":chapter,"note":"真实几何拉远总览，镜头改变且景深关闭，不是正常游玩视角"})
	stage.shutdown(); stage.free()
	return true
func _capture_final_choice(session: RefCounted) -> bool:
	var entry:=Saga.scene("C7-09")
	var world: Dictionary=session.campaign.safe_snapshot().world.duplicate(true)
	world.position=Region.anchors(7)[entry.location].duplicate()
	if not session.save_world(world).ok: _fail("最终选择位置保存失败"); return false
	var stage: Node3D=load(Saga.SCENE_PATH).instantiate(); root.add_child(stage)
	for frame in 10: await physics_frame
	if not stage.ready_for_play: _fail("最终方案舞台未就绪"); return false
	stage._confirm_armed=true
	if not stage.request_interaction("C7-09"): _fail("最终方案未能实地触发："+str(stage.player.position)); return false
	if is_instance_valid(stage._dialogue): stage._dialogue._present_node("")
	if stage._mode!="choice": _fail("最终方案没有进入选择状态："+stage._mode); return false
	await _capture("saga_final_options",{"note":"真实四结局条件选单；可用准备经前章事务完成"})
	stage._preview_option("d")
	if is_instance_valid(stage._dialogue): stage._dialogue._present_node("")
	if stage._mode!="confirmation": _fail("终章二次确认没有打开："+stage._mode); return false
	await _capture("saga_final_confirmation",{"note":"未提交的永夜方案二次确认，完整后果文字可见"})
	stage._cancel_option()
	if is_instance_valid(stage._dialogue): stage._dialogue._present_node("")
	if stage._mode!="choice" or session.campaign.safe_snapshot().saga.choices.has("C7-09"): _fail("取消选择后状态不正确"); return false
	await _capture("saga_confirmation_cancelled",{"note":"取消确认后回到方案选单，未保存永夜选择"})
	stage.shutdown(); stage.free()
	return true
func _capture(name: String,metadata: Dictionary) -> void:
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	var path:=_output.path_join(name+".png")
	if root.get_texture().get_image().save_png(path)!=OK: _failures.append("截图写入失败："+name)
	metadata["file"]=path; _records.append(metadata)
	print("SAGA_CAPTURE:",path)
func _finish_first(session: RefCounted) -> bool:
	for night in range(1,6):
		for event in Chapters.events(night):
			if event!="dialogue:hd5" and not session.commit_event(session.campaign.safe_snapshot().world,event).ok: return false
		var start: Dictionary=session.begin_encounter(session.campaign.safe_snapshot().world,Chapters.night(night).clue_id)
		if not start.ok or not session.router.finish(_victory(session,start)).ok: return false
		if night==5 and not session.commit_event(session.campaign.safe_snapshot().world,"dialogue:hd5").ok: return false
		if not session.advance_night(session.campaign.safe_snapshot().world).ok: return false
	return session.choose_resolution(session.campaign.safe_snapshot().world,"sendoff").ok and session.finish_ending(session.campaign.safe_snapshot().world).ok
func _victory(session: RefCounted,started: Dictionary) -> Dictionary:
	var roster: Array[Dictionary]=[]
	for id in session.campaign.safe_snapshot().party: roster.append(started.setup.actors[id].duplicate(true))
	return {"battle_id":started.battle_id,"outcome":"victory","roster":roster,"inventory":started.setup.inventory.duplicate(true),"xp":started.xp,"story_patch":started.story_patch.duplicate(true),"replay":{}}
func _fail(message: String) -> void:
	printerr("SAGA_CAPTURE_FAILED:",message); quit(1)

func _capture_resident_art() -> void:
	var Art = load("res://scripts/campaign/saga_npc_art.gd")
	for speaker in Art.data().get("characters",{}):
		var actor: Node3D=Art.world_actor(speaker)
		if actor==null: _failures.append("居民无法加载："+speaker); continue
		var set:=Node3D.new(); root.add_child(set); set.add_child(Region.build(2)); set.add_child(actor)
		var camera:=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=4.6; camera.position=Vector3(0,3.0,7); set.add_child(camera); camera.look_at(Vector3(0,.9,0)); camera.make_current()
		var layer:=CanvasLayer.new(); set.add_child(layer)
		var portrait:=TextureRect.new(); portrait.position=Vector2(100,120); portrait.size=Vector2(480,720); portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; portrait.texture=Art.portrait(speaker).texture; layer.add_child(portrait)
		var label:=Label.new(); label.text=speaker+" · 新居民独立原图 / 实际3D静态人物与对话半身"; label.position=Vector2(90,950); label.add_theme_font_override("font",load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")); label.add_theme_font_size_override("font_size",28); layer.add_child(label)
		await _capture("npc_"+str(Art.data().characters[speaker].id),{"speaker":speaker,"note":"真实引擎渲染；左为独立半身图，中为有脚底锚点与身高标尺的3D世界静态人物","source":Art.data().characters[speaker].sheet})
		layer.hide()
		var Dialogue=load("res://scripts/ui/dialogue_overlay.gd")
		var dialogue: CanvasLayer=Dialogue.new(); dialogue.portrait_provider=Art.portrait; set.add_child(dialogue)
		var quote := ""
		for chapter in Saga.data().get("chapters",[]):
			for scene in chapter.get("scenes",[]):
				for block in scene.get("source_blocks",[]):
					if quote.is_empty() and str(block.get("text","")).begins_with(speaker+"："): quote=str(block.text).trim_prefix(speaker+"：")
		if quote.is_empty(): quote="人物原画显示验收（非新增剧情对白）。"
		dialogue.play({"portrait":{"name":speaker,"speaker":speaker,"text":quote,"next":""}},"portrait")
		dialogue._typing=false; dialogue._text_label.visible_characters=-1
		await _capture("npc_dialogue_"+str(Art.data().characters[speaker].id),{"speaker":speaker,"note":"真实正式对话层与原文台词的半身取景验收，未提交剧情事件","source":Art.data().characters[speaker].sheet})
		dialogue.abort()
		set.free()
	_write_capture_manifest()
	print("SAGA_NPC_CAPTURES:",_records.size()," FAILURES:",_failures.size())

func _write_capture_manifest() -> void:
	var file:=FileAccess.open(_output.path_join("capture-manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info(),"renderer":RenderingServer.get_video_adapter_name(),"method":"真实引擎图形采集；需要剧情进度时由正式状态事务夹具建立，不能当作人工七章全通","records":_records,"failures":_failures},"\t")); file.close()
