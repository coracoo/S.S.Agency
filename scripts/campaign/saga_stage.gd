# 后六章实地探索；沿用首章的人物、对话、菜单与输入锁，所有故事与资源修改交给正式事务。
extends "res://scripts/campaign/chapter_stage.gd"
const Saga = preload("res://scripts/campaign/saga_catalog.gd")
const Region = preload("res://scripts/campaign/saga_world.gd")
const ResidentArt = preload("res://scripts/campaign/saga_npc_art.gd")
const SPEAKER_IDS := {"凛音":"rinne","薄荷":"mint","岑照":"guard","焰华":"homura","苏合":"healer","清明":"controller","小夜":"sayo","镜中薄荷":"mint","镜中焰华":"homura","焰华的镜影":"homura","凛音的镜影":"rinne"}
const CHAPTER_NUMBERS := ["二","三","四","五","六","七"]
var chapter_id := 2
var _chapter: Dictionary = {}
var _active_entry: Dictionary = {}
var _selected_option: Dictionary = {}
var _targets: Array[Dictionary] = []
var _notice_remaining := 0.0
var _service_bought := false

func _ready() -> void:
	_register_input()
	_build_hud()
	session = Session.current
	if session == null or not session.campaign.safe_snapshot().has("saga"):
		_show_error("后续旅程尚未建立，请从第一章结案后下山。", _return_title)
		return
	chapter_id = int(session.campaign.safe_snapshot().saga.chapter)
	night_id = chapter_id + 4
	_chapter = Saga.chapter(chapter_id)
	config = Saga.definition(night_id)
	_geometry = Region.build(chapter_id)
	add_child(_geometry)
	player = Player.new()
	player.name = "Player"
	player.input_enabled = false
	if session.bundle != null: player.shared_definition = session.bundle.get_definition("rinne")
	add_child(player)
	if player.animator.definition.is_empty():
		_show_error("凛音高清素材装配失败，请从标题重新加载。", _return_title)
		return
	camera_rig = WorldCamera.new()
	camera_rig.name = "SagaCameraRig"
	add_child(camera_rig)
	camera_rig.configure_world(config.bounds)
	player.set_camera_basis(camera_rig.camera.global_basis)
	player.enable_scene_integration()
	await get_tree().physics_frame
	if _closed or not is_inside_tree(): return
	# 六地区共用同一路径；旧战果缓存不能覆盖随后已经提交的跨章或对白进度。
	Router.take_world(Saga.SCENE_PATH)
	var world: Dictionary = session.campaign.safe_snapshot().world
	var restored: Dictionary = restore_world(world)
	if not restored.ok:
		_show_error(restored.error, _return_title)
		return
	ready_for_play = true
	set_hd2d_experiment(bool(session.get_meta("hd2d_depth_enabled", hd2d_experiment)))
	_refresh_targets()
	_resume_explore()
	_tutorial_remaining = 7.0
	_refresh_hud()
	# 战后/关闭游戏恢复只读取已保存活动场次；普通新场次必须走到调查点。
	_resume_story_checkpoint.call_deferred()

func _process(delta: float) -> void:
	if _closed: return
	if not Input.is_action_pressed("approach_interact") and not Input.is_action_pressed("ui_accept") and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): _confirm_armed = true
	for button in _modal_buttons:
		if is_instance_valid(button): button.disabled = not _confirm_armed or _transition_busy
	if not _modal_buttons.is_empty() and _confirm_armed and not _transition_busy and get_viewport().gui_get_focus_owner() == null:
		_modal_buttons[0].grab_focus()
	if ready_for_play and player != null:
		if controls_enabled:
			camera_rig.follow(player,delta)
			_tutorial_remaining = maxf(0.0,_tutorial_remaining-delta)
		if is_instance_valid(_hd2d_profile): _hd2d_profile.follow(player.position)
	if _notice_remaining > 0:
		_notice_remaining = maxf(0.0,_notice_remaining-delta)
		if _notice_remaining == 0: _hud.notice.text = ""
	_refresh_hud()

func _unhandled_input(event: InputEvent) -> void:
	if _closed or not ready_for_play or (event is InputEventKey and event.echo): return
	if event.is_action_pressed("approach_pause"):
		get_viewport().set_input_as_handled()
		if _mode == "explore": _open_pause()
		elif _mode in ["pause","map","journal","travel","interaction_select"]: _resume_explore()
		return
	if event.is_action_pressed("approach_map"):
		get_viewport().set_input_as_handled()
		if _mode == "explore": _open_map()
		elif _mode == "map": _resume_explore()
		return
	if event.is_action_pressed("approach_interact") and controls_enabled and _confirm_armed:
		get_viewport().set_input_as_handled()
		var nearby := nearby_interactions()
		if nearby.size() == 1: request_interaction(str(nearby[0].id))
		elif nearby.size() > 1: _open_interaction_select(nearby)

func _saga() -> Dictionary:
	return session.campaign.safe_snapshot().get("saga",{}) if session != null else {}

func _refresh_targets() -> void:
	_targets.clear()
	var saga := _saga()
	var active := str(saga.get("active_scene",""))
	for entry in _chapter.get("scenes",[]):
		var id := str(entry.id)
		if not active.is_empty() and id != active: continue
		if id != active and not Saga.available(saga,id): continue
		var location := str(entry.location)
		if not config.anchors.has(location): continue
		_targets.append({"id":id,"label":str(entry.title),"kind":"scene","location":location,"position":config.anchors[location],"radius":2.15,"main":str(entry.kind) in ["main","ending"] or id == active})
	_targets.append({"id":"@rest","label":"歇脚 · 全员恢复","kind":"rest","location":"rest","position":config.anchors.rest,"radius":2.1})
	if not active.is_empty():
		_targets.append({"id":"@supply","label":"补给 · 日用药物","kind":"field_shop","location":"shop","position":config.anchors.shop,"radius":2.1})
	if active.is_empty():
		_targets.append({"id":"@travel","label":"沿路前行 / 返回旧地","kind":"travel","location":"exit","position":config.anchors.exit,"radius":2.3})
	config["interactions"] = _targets.duplicate(true)
	_refresh_story_markers()
	_refresh_npcs()

func nearby_interactions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if player == null: return result
	for target in _targets:
		if player.position.distance_to(Geometry.vector(target.position)) <= float(target.radius): result.append(target)
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if bool(a.get("main",false)) != bool(b.get("main",false)): return bool(a.get("main",false))
		return player.position.distance_to(Geometry.vector(a.position)) < player.position.distance_to(Geometry.vector(b.position)))
	return result

func nearest_interaction() -> Dictionary:
	var values := nearby_interactions()
	return values[0] if not values.is_empty() else {}

func request_interaction(id: String) -> bool:
	if _mode != "explore" or _closed or not ready_for_play or not _confirm_armed: return false
	var target: Dictionary = {}
	for candidate in nearby_interactions():
		if str(candidate.id) == id: target = candidate; break
	if target.is_empty(): return false
	if not begin_operation("interaction"): return false
	match str(target.kind):
		"rest": _rest_at_anchor()
		"travel": _show_travel()
		"field_shop": _show_field_shop()
		_: _begin_story(id)
	return true

func _open_interaction_select(nearby: Array[Dictionary]) -> void:
	if not begin_operation("interaction_select"): return
	var actions: Array = []
	for target in nearby: actions.append({"text":("主线 · " if target.get("main",false) else "") + str(target.label),"call":_selected_target.bind(str(target.id))})
	actions.append({"text":"继续行走","call":_resume_explore})
	_show_modal("这里可以调查", "请选择眼前的人物或地点。", actions)

func _selected_target(id: String) -> void:
	_resume_explore()
	_confirm_armed = true
	request_interaction(id)

func _begin_story(id: String) -> void:
	var result: Dictionary = session.campaign.begin_saga_scene(export_world(),id)
	if not result.get("ok",false):
		_show_error(str(result.get("error","调查检查点保存失败")),_begin_story.bind(id)); return
	apply_committed_world(session.campaign.safe_snapshot().world)
	_active_entry = Saga.scene(id)
	_selected_option = {}
	_service_bought = false
	# 模型在新一轮访问时清除历史选项；当前世界里的确认即使场次曾被暂缓完成也不能丢掉。
	_selected_option = confirmed_choice(_world)
	if resumes_battle_aftermath(_saga(),id): _play_aftermath(); return
	if not _selected_option.is_empty():
		var resumed_lines: Array = _selected_option.get("confirmation",{}).get("lines",[]) if _selected_option.has("confirmation") else _selected_option.get("lines",[])
		_play_lines(resumed_lines,_after_option); return
	var opening: Array = _active_entry.get("lines",[])
	if _saga().completed.has(id) and not _active_entry.get("event_lines",{}).get("revisit",[]).is_empty(): opening = _active_entry.event_lines.revisit
	_play_lines(opening,_after_opening)

static func confirmed_choice(world: Dictionary) -> Dictionary:
	return Saga.choice(str(world.get("story_scene","")),str(world.get("story_choice","")))

static func visible_speakers(entry: Dictionary, saga: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for line in Saga.visible_lines(entry.get("lines",[]),saga):
		var speaker:=str(line.get("speaker",""))
		if not speaker.is_empty() and speaker!="旁白" and not names.has(speaker): names.append(speaker)
	return names

static func resumes_battle_aftermath(saga: Dictionary, id: String) -> bool:
	return Saga.awaiting_aftermath(saga,id)

func _resume_story_checkpoint() -> void:
	if _closed or not ready_for_play or _mode != "explore": return
	var id := str(_saga().get("active_scene",""))
	if id.is_empty(): return
	# 支线接续会记录下一场，但只有真实已开始的story_scene或战后才恢复演出。
	var entry := Saga.scene(id)
	if entry.is_empty(): return
	if player.position.distance_to(Geometry.vector(config.anchors.get(entry.location,config.anchors.spawn))) > 2.4: return
	if begin_operation("dialogue"): _begin_story(id)

func _after_opening() -> void:
	var options := eligible_choices(_active_entry,_saga())
	if not options.is_empty(): _show_story_choices(); return
	if str(_active_entry.get("service","")) == "shop": _show_shop(); return
	_after_option()

static func eligible_choices(entry: Dictionary, saga: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for option in entry.get("choices",[]):
		if Saga.matches(option.get("requires",{}),Saga.context(saga)): result.append(option.duplicate(true))
	return result

func _show_story_choices() -> void:
	_mode = "choice"
	var actions: Array = []
	for option in eligible_choices(_active_entry,_saga()): actions.append({"text":str(option.text),"call":_preview_option.bind(str(option.id))})
	if str(_active_entry.get("service","")) == "rest": actions.append({"text":"先歇脚 · 全员恢复","call":_rest_during_scene})
	_show_modal(str(_active_entry.title),"选择处理方式。只有确认并完成此段后，结果才会写入手帖。",actions)

func _preview_option(id: String) -> void:
	var option := Saga.choice(str(_active_entry.id),id)
	if option.is_empty() or not Saga.matches(option.get("requires",{}),Saga.context(_saga())): return
	_selected_option = option
	if option.has("confirmation"):
		# 预览后果不等于同意；取消不触碰模型choices，更不提前应用effects。
		_play_lines(option.get("lines",[]),_show_option_confirmation)
	else: _commit_option(false)

func _show_option_confirmation() -> void:
	_mode = "confirmation"
	var confirmation: Dictionary = _selected_option.confirmation
	_show_modal("请再确认这项决定",str(_selected_option.text),[{"text":str(confirmation.text),"call":_commit_option.bind(true)},{"text":str(confirmation.get("cancel_text","返回选项")),"call":_cancel_option}])

func _cancel_option() -> void:
	var lines: Array = _selected_option.get("confirmation",{}).get("cancel_lines",[])
	_selected_option = {}
	_play_lines(lines,_show_story_choices)

func _commit_option(confirmed: bool) -> void:
	var result: Dictionary = session.campaign.choose_saga_option(export_world(),str(_active_entry.id),str(_selected_option.id))
	if not result.get("ok",false):
		_show_error(str(result.get("error","选择尚未保存")),_commit_option.bind(confirmed)); return
	apply_committed_world(session.campaign.safe_snapshot().world)
	var lines: Array = _selected_option.get("confirmation",{}).get("lines",[]) if confirmed else _selected_option.get("lines",[])
	_play_lines(lines,_after_option)

func _after_option() -> void:
	match str(_selected_option.get("service","")):
		"shop": _show_shop(); return
		"cancel": _play_lines(_active_entry.get("event_lines",{}).get("shop_cancel",[]),_complete_story); return
	var encounter := str(_world.get("story_encounter", ""))
	if not _world.has("story_encounter"): encounter = Saga.encounter(str(_active_entry.id),str(_selected_option.get("id","")))
	if not encounter.is_empty() and not _saga().battles.has(str(_active_entry.id)):
		_show_battle_cue(); return
	_play_aftermath()

func _show_battle_cue() -> void:
	_mode = "battle_cue"
	var cues: Array[String] = []
	for line in _active_entry.get("battle_lines",[]):
		if not Saga.matches(line.get("when",{}),Saga.context(_saga())): continue
		if not str(line.get("choice_id","")).is_empty() and str(line.choice_id) != str(_selected_option.get("id","")): continue
		var cue := str(line.get("cue",""))
		if not cue.is_empty() and not cues.has(cue): cues.append(cue)
		if not str(line.get("text","")).is_empty(): cues.append("%s：%s" % [str(line.get("speaker","")),str(line.text)])
	var body := "\n\n".join(cues)
	if body.is_empty(): body = "同伴已经站稳位置。按当前三人编队应战，胜利后回到此处继续。"
	_show_modal("应对异象 · " + str(_active_entry.title),body,[{"text":"进入战斗","call":_begin_saga_battle},{"text":"先检查队伍","call":_prepare_for_battle},{"text":"暂缓应战 · 实地歇脚与补给","call":_postpone_battle}])

func _postpone_battle() -> void:
	# 只收起呈现，活动场次、已确认选择、战前资源都仍由正式档保留。
	_active_entry = {}
	_selected_option = {}
	_refresh_targets()
	_resume_explore()
	_notice("当前方案已保留。可沿地图走到休整点或商铺，准备好后再回来。")

func _show_field_shop() -> void:
	_mode = "field_shop"
	var actions: Array = []
	for item in Saga.SHOP:
		var label: String = session.campaign._catalog.get_definition("items",str(item)).get("name",str(item))
		actions.append({"text":"%s ×1 · %d文" % [label,int(Saga.SHOP[item])],"call":_buy_field_item.bind(str(item))})
	actions.append({"text":"继续准备","call":_resume_explore})
	_show_modal("行囊补给","现有 %d 文。购买日用药物会立即保存；当前调查与已确认方案保持原样。" % int(_saga().coins),actions)

func _buy_field_item(item_id: String) -> void:
	var result: Dictionary = session.campaign.buy_saga_item(export_world(),item_id,1)
	if not result.get("ok",false):
		_show_modal("补给尚未完成",str(result.get("error","交易未能保存")),[{"text":"返回货架","call":_show_field_shop},{"text":"继续行走","call":_resume_explore}]); return
	apply_committed_world(session.campaign.safe_snapshot().world)
	_show_field_shop()

func _prepare_for_battle() -> void:
	_mode = "explore"
	_open_party("party")

func _begin_saga_battle() -> void:
	_transition_busy = true
	var result: Dictionary = session.begin_encounter(export_world(),str(_active_entry.id))
	if not result.get("ok",false):
		_transition_busy = false
		_show_error(str(result.get("error","战前检查点未保存")),_begin_saga_battle); return
	_go_scene(str(result.get("battle_scene","res://scenes/rpg/battle.tscn")))

func _play_aftermath() -> void:
	var lines: Array = _selected_option.get("after_lines",[])
	if lines.is_empty(): lines = _active_entry.get("after_lines",[])
	var combined: Array = lines.duplicate(true)
	combined.append_array(_active_entry.get("followup_lines",[]))
	_play_lines(combined,_complete_story)

func _complete_story() -> void:
	_transition_busy = true
	var result: Dictionary = session.campaign.complete_saga_scene(export_world(),str(_active_entry.id))
	if not result.get("ok",false):
		_transition_busy = false
		_show_error(str(result.get("error","场次结果尚未保存")),_complete_story); return
	var safe: Dictionary = session.campaign.safe_snapshot()
	apply_committed_world(safe.world)
	if str(safe.get("story_phase","")) == "complete": _go_scene(Saga.ENDING_PATH); return
	if int(safe.saga.chapter) != chapter_id: _go_scene(Saga.SCENE_PATH); return
	_active_entry = {}
	_selected_option = {}
	_refresh_targets()
	_resume_explore()
	_notice("记录已保存。" + ("请沿灯路前往下一处。" if not str(safe.saga.get("active_scene","")).is_empty() else ""))

func _play_lines(lines: Array, afterward: Callable) -> void:
	_close_modal()
	_mode = "dialogue"
	set_controls_enabled(false)
	var nodes := saga_dialogue_nodes(Saga.visible_lines(lines,_saga()))
	if nodes.is_empty():
		if afterward.is_valid(): afterward.call()
		return
	_dialogue = Dialogue.new(_theme)
	_dialogue.advance_action = &"approach_interact"
	_dialogue.require_release = true
	_dialogue.portrait_provider = _dialogue_portrait
	_dialogue.portrait_failed.connect(_portrait_failed)
	add_child(_dialogue)
	_dialogue.finished.connect(_lines_finished.bind(operation_token(),afterward),CONNECT_ONE_SHOT)
	_dialogue.play(nodes,"line_0")

static func saga_dialogue_nodes(lines: Array) -> Dictionary:
	var nodes: Dictionary = {}
	for index in lines.size():
		var line: Dictionary = lines[index]
		var speaker := str(line.get("speaker","旁白"))
		nodes["line_%d" % index] = {"name":speaker,"speaker":str(SPEAKER_IDS.get(speaker,speaker)),"text":str(line.get("text","")),"side":"right" if speaker in ["薄荷","清明","苏合"] else "left","next":"line_%d" % (index+1) if index+1 < lines.size() else ""}
	return nodes

func _lines_finished(token: int, afterward: Callable) -> void:
	if not callback_valid(token) or not is_inside_tree(): return
	if is_instance_valid(_dialogue):
		remove_child(_dialogue)
		_dialogue.queue_free()
	_dialogue = null
	_confirm_armed = false
	if afterward.is_valid(): afterward.call()

func _show_shop() -> void:
	_mode = "shop"
	var actions: Array = []
	for item in Saga.SHOP:
		actions.append({"text":"%s ×1 · %d文" % [str(session.campaign._catalog.get_definition("items",str(item)).get("name",str(item))),int(Saga.SHOP[item])],"call":_buy_item.bind(str(item))})
	actions.append({"text":"收好行囊，继续调查" if _service_bought else "暂不购买","call":_leave_shop})
	_show_modal(str(_active_entry.title),"现有 %d 文。查案必需工具由委托提供，不会因银钱不足扣留。" % int(_saga().coins),actions)

func _buy_item(item_id: String) -> void:
	var result: Dictionary = session.campaign.buy_saga_item(export_world(),item_id,1)
	if not result.get("ok",false) and int(_saga().coins) >= int(Saga.SHOP.get(item_id,0)):
		_show_error(str(result.get("error","交易未能保存")),_buy_item.bind(item_id)); return
	var event := "shop_success" if result.get("ok",false) else "shop_insufficient"
	if result.get("ok",false):
		_service_bought = true
		apply_committed_world(session.campaign.safe_snapshot().world)
	else: _notice(str(result.get("error","交易未完成")))
	_play_lines(_active_entry.get("event_lines",{}).get(event,[]),_show_shop)

func _leave_shop() -> void:
	if _service_bought: _complete_story()
	else: _play_lines(_active_entry.get("event_lines",{}).get("shop_cancel",[]),_complete_story)

func _rest_during_scene() -> void:
	var result: Dictionary = session.campaign.rest()
	if result.get("ok",false):
		apply_committed_world(session.campaign.safe_snapshot().world)
		_notice("全员已恢复，状态已保存。")
	else: _notice(str(result.get("error","暂时无法休息")))
	_show_story_choices()

func _rest_at_anchor() -> void:
	var saved: Dictionary = session.save_world(export_world())
	if not saved.get("ok",false): _show_error(str(saved.error),_rest_at_anchor); return
	var result: Dictionary = session.campaign.rest()
	if not result.get("ok",false): _show_error(str(result.error),_rest_at_anchor); return
	apply_committed_world(session.campaign.safe_snapshot().world)
	_resume_explore()
	_notice("在安全处歇脚。全员 HP、MP 与状态已恢复并保存。")

func _show_travel() -> void:
	_mode = "travel"
	var saga := _saga()
	var actions: Array = []
	for destination in range(2,mini(7,int(saga.max_chapter)+1)+1):
		if destination == chapter_id: continue
		if destination > int(saga.max_chapter) and not Saga.chapter_complete(saga,int(saga.max_chapter)): continue
		actions.append({"text":"前往第%s章 · %s" % [CHAPTER_NUMBERS[destination-2],str(Saga.chapter(destination).title)],"call":_travel_to.bind(destination)})
	actions.append({"text":"留在本地","call":_resume_explore})
	_show_modal("沿灯路前行", "旧地仍能返回。未做的救援、未寄的信、未结的责任，会原样留在手帖里。",actions)

func _travel_to(destination: int) -> void:
	_transition_busy = true
	var result: Dictionary = session.campaign.travel_saga(export_world(),destination)
	if not result.get("ok",false):
		_transition_busy = false
		_show_error(str(result.get("error","前路尚未开放")),_travel_to.bind(destination)); return
	apply_committed_world(session.campaign.safe_snapshot().world)
	_go_scene(Saga.SCENE_PATH)

func _open_pause() -> void:
	if not begin_operation("pause"): return
	_show_modal("行旅手帖",_chapter_title() + "\n当前位置与正式资源变更会分别保存。",[{"text":"队伍 / 道具 / 装备","call":_open_party.bind("menu")},{"text":"查看主线与未结事项","call":_open_journal},{"text":"保存并返回标题","call":_ask_title},{"text":"继续探索","call":_resume_explore}])

func _open_journal() -> void:
	if _mode == "explore" and not begin_operation("journal"): return
	_mode = "journal"
	var saga := _saga()
	var lines: Array[String] = ["当前目标：" + _objective_text(),"", "本地未结事项："]
	var count := 0
	for entry in journal_pending(_chapter,saga):
		lines.append("• %s · %s" % [str(entry.title),_location_name(str(entry.location))]); count += 1
	if count == 0: lines.append("当前没有已开放的未结支线。")
	lines.append("\n最近记录：")
	var completed: Array = saga.completed
	for index in range(maxi(0,completed.size()-12),completed.size()):
		var entry := Saga.scene(str(completed[index]))
		lines.append("✓ " + str(entry.get("title",completed[index])))
	lines.append("\n首章记录：" + first_chapter_record(session.campaign.safe_snapshot()))
	_show_modal("行旅手帖 · 主线与责任","\n".join(lines),[{"text":"返回行走","call":_resume_explore}])

static func journal_pending(chapter: Dictionary, saga: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in chapter.get("scenes",[]):
		if str(entry.get("kind","")) != "side" or not Saga.available(saga,str(entry.id)): continue
		if saga.get("completed",[]).has(entry.id) and (not bool(entry.get("repeatable",false)) or Saga.eligible_choices(entry,saga).is_empty()): continue
		result.append(entry.duplicate(true))
	return result

static func first_chapter_record(state: Dictionary) -> String:
	if str(state.get("resolution","")) == "sendoff": return "首章已为小夜送行，案件已结。"
	if state.get("saga",{}).get("flags",{}).get("responsibility_resolved",false): return "首章曾选择镇守；后续已完成送行，续监责任已了结。"
	return "首章选择镇守；神社仍需续监，责任未了。"

func _party_closed() -> void:
	if _closed: return
	_title_party_draft = null
	_release_party_panel()
	apply_committed_world(session.campaign.safe_snapshot().world)
	if not _active_entry.is_empty() and not _saga().battles.has(str(_active_entry.id)):
		_show_battle_cue(); return
	_refresh_targets()
	_resume_explore()

func _refresh_npcs() -> void:
	if is_instance_valid(_npc_layer):
		remove_child(_npc_layer); _npc_layer.queue_free()
	_npc_layer = NPCs.new()
	_npc_layer.name = "SagaInterlocutors"
	add_child(_npc_layer)
	var occupied: Dictionary = {}
	for target in _targets:
		if str(target.kind) != "scene" or occupied.has(Geometry.vector(target.position)): continue
		var entry := Saga.scene(str(target.id))
		var resident := ""
		for speaker in visible_speakers(entry,_saga()):
			if ResidentArt.supports(speaker): resident=speaker; break
		if not resident.is_empty():
			var resident_node: Node3D=ResidentArt.world_actor(resident)
			if resident_node!=null:
				resident_node.name="Resident_"+str(target.location)
				resident_node.position=Geometry.vector(target.position)+Vector3(.72,0,-.35)
				_npc_layer.add_child(resident_node)
				occupied[Geometry.vector(target.position)]=true
				continue
		var identity := ""
		var person := ""
		for speaker in visible_speakers(entry,_saga()):
			if SPEAKER_IDS.has(speaker) and speaker not in ["凛音","小夜"]:
				identity = SPEAKER_IDS[speaker]; person = speaker; break
		if identity.is_empty(): continue
		var actor: Node3D = _npc_layer._create_actor({"identity_id":identity,"label":person})
		actor.name = "Companion_" + str(target.location)
		actor.position = Geometry.vector(target.position) + Vector3(.72,0,-.35)
		_npc_layer.add_child(actor)
		occupied[Geometry.vector(target.position)] = true

func _refresh_story_markers() -> void:
	if is_instance_valid(_story_markers):
		remove_child(_story_markers); _story_markers.queue_free()
	_story_markers = Node3D.new(); _story_markers.name = "SagaInvestigationMarkers"; add_child(_story_markers)
	var placed: Dictionary = {}
	for target in _targets:
		if placed.has(Geometry.vector(target.position)): continue
		placed[Geometry.vector(target.position)] = true
		var marker := Node3D.new(); marker.name = "Anchor_" + str(target.location); marker.position = Geometry.vector(target.position)
		_story_markers.add_child(marker)
		var mesh := MeshInstance3D.new(); var torus := TorusMesh.new(); torus.inner_radius=.34; torus.outer_radius=.41; mesh.mesh=torus; mesh.position.y=.035
		var material := StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color("eac985") if target.get("main",false) else Color("87bdb1")
		mesh.material_override=material; marker.add_child(mesh)
		var label := Label3D.new(); label.font=load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf"); label.text="◆ " + str(target.label)
		label.font_size=32; label.pixel_size=.005; label.position.y=2.45; label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate=material.albedo_color; label.outline_size=7; label.outline_modulate=Color("182431"); label.no_depth_test=false
		marker.add_child(label)

func _dialogue_portrait(speaker: String) -> Dictionary:
	var aliases := {"沈烛舟旧录音":"沈烛舟","陆芸之魂":"陆芸","镜中卖饼人":"卖饼人"}
	if aliases.has(speaker) and ResidentArt.supports(aliases[speaker]): return ResidentArt.portrait(aliases[speaker])
	if ResidentArt.supports(speaker): return ResidentArt.portrait(speaker)
	return super._dialogue_portrait(speaker)

func _chapter_title() -> String:
	return "第%s章 · %s" % [CHAPTER_NUMBERS[clampi(chapter_id-2,0,5)],str(_chapter.get("title","行旅"))]

func _location_name(id: String) -> String:
	return str(Region.labels(chapter_id).get(id,{"rest":"休整处","shop":"商铺"}.get(id,id)))

func _objective_target() -> Dictionary:
	var saga := _saga()
	var id := str(saga.get("active_scene",""))
	if id.is_empty(): id = str(saga.get("scene",""))
	return Saga.scene(id)

func _objective_text() -> String:
	var target := _objective_target()
	if target.is_empty(): return "前往出口，沿灯路去下一处" if chapter_id < 7 else "核对手帖中的未结事项"
	var position := Geometry.vector(config.anchors.get(target.location,config.anchors.spawn))
	var distance: float = player.position.distance_to(position) if player != null else 0.0
	return "%s · %s · %d米" % [str(target.title),_location_name(str(target.location)),roundi(distance)]

func _refresh_hud() -> void:
	if _hud.is_empty(): return
	_ui_layer.visible = _mode == "explore"
	_hud.title.text = _chapter_title()
	_hud.title.size.x = 350
	_hud.region.text = "行旅银钱 %d 文" % int(_saga().get("coins",0))
	_hud.region.position.x = 430
	_hud.region.size.x = 220
	_hud.objective.text = _objective_text() if ready_for_play else "正在展开地区…"
	_hud.objective.tooltip_text = _hud.objective.text
	_hud.map.disabled = not ready_for_play or not controls_enabled
	_hud.pause.disabled = not ready_for_play or not controls_enabled
	var target := nearest_interaction()
	_hud.prompt.text = "E · " + str(target.label) if not target.is_empty() else ("WASD 行走 · E 调查 · M 地图 · Esc 手帖" if _tutorial_remaining > 0 else "")
	if nearby_interactions().size()>1: _hud.prompt.text = "E · 调查此处（多项）"
	_hud.prompt_panel.visible = not _hud.prompt.text.is_empty()

func _notice(message: String) -> void:
	super._notice(message)
	_notice_remaining = 6.0

func _open_map() -> void:
	if not begin_operation("map"): return
	_close_modal()
	var size := get_viewport().get_visible_rect().size
	_modal = Control.new(); _modal.size=size; _modal.set_meta("layout_size",size); _modal.mouse_filter=Control.MOUSE_FILTER_STOP; _modal_layer.add_child(_modal)
	var shade := ColorRect.new(); shade.color=Color(.015,.018,.035,.82); shade.size=size; _modal.add_child(shade)
	var width:=minf(1540,size.x-72); var height:=minf(880,size.y-72); var left:=(size.x-width)/2; var top:=(size.y-height)/2
	Art.panel(_modal,Rect2(left,top,width,height))
	Kit.label(_modal,_chapter_title()+" · 地区图",Rect2(left+42,top+30,width-370,58),34)
	Kit.label(_modal,"实线为可行走地面　白点：你　金点：主线　青点：调查 / 整备\n地图只作路引。所有调查、救援与离章都需实际抵达。",Rect2(left+42,top+106,width-84,78),23)
	var map := RegionMap.new(); map.name="SagaRegionMap"; map.position=Vector2(left+42,top+212); map.size=Vector2(width-84,height-258)
	map.chapter=chapter_id; map.actor=player.position; map.targets=_targets.duplicate(true); _modal.add_child(map)
	var button := Art.button(_modal,"返回行走 [M]",Rect2(left+width-280,top+28,238,76),_modal_action.bind(_resume_explore,operation_token()))
	button.disabled=true; _modal_buttons.append(button)

class RegionMap extends Control:
	var chapter := 2
	var actor := Vector3.ZERO
	var targets: Array = []
	var _area := Rect2()
	var _scale := 1.0
	var _offset := Vector2.ZERO
	func _point(value: Vector3) -> Vector2:
		return _offset+(Vector2(value.x,value.z)-_area.position)*_scale
	func _draw() -> void:
		var bounds: Dictionary = Region.bounds(chapter)
		_area=Rect2(bounds.x[0],bounds.z[0],bounds.x[1]-bounds.x[0],bounds.z[1]-bounds.z[0])
		_scale=minf((size.x-100)/_area.size.x,(size.y-74)/_area.size.y)
		_offset=(size-_area.size*_scale)/2
		for rect: Rect2 in Region._rects(chapter):
			var drawn:=Rect2(_offset+(rect.position-_area.position)*_scale,rect.size*_scale)
			draw_rect(drawn,Color("3f5354")); draw_rect(drawn,Color("7b8e87"),false,1.5)
		for route in Region.routes(chapter):
			for index in range(1,route.size()): draw_line(_point(Vector3(route[index-1][0],0,route[index-1][2])),_point(Vector3(route[index][0],0,route[index][2])),Color("baae88"),2,true)
		var font: Font=load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
		var anchors: Dictionary=Region.anchors(chapter)
		for key in Region.labels(chapter):
			var a: Array=anchors[key]; var at:=_point(Vector3(a[0],0,a[2]))
			draw_circle(at,4,Color("95a89e")); draw_string(font,at+Vector2(8,-10),str(Region.labels(chapter)[key]),HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color("e6dcc4"))
		for index in range(targets.size()-1,-1,-1):
			var target: Dictionary=targets[index]
			var a: Array=target.position; var at:=_point(Vector3(a[0],0,a[2])); var color:=Color("edcb83") if target.get("main",false) else Color("85d3c2")
			draw_circle(at,7,color); draw_arc(at,11,0,TAU,24,color,1.5,true)
		var here:=_point(actor); draw_circle(here,8,Color.WHITE); draw_arc(here,14,0,TAU,24,Color.WHITE,2,true)
		draw_string(font,here+Vector2(-18,34),"你",HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color.WHITE)

# 長选项、结局二次确认与多项菜单统一在可滚动容器里完整排版，避免单行裁切后果。
func _show_modal(title: String, body: String, actions: Array) -> void:
	_close_modal()
	_confirm_armed = false
	var canvas_size := get_viewport().get_visible_rect().size
	_modal=Control.new(); _modal.size=canvas_size; _modal.set_meta("layout_size",canvas_size); _modal.mouse_filter=Control.MOUSE_FILTER_STOP; _modal_layer.add_child(_modal)
	var shade:=ColorRect.new(); shade.color=Color(.015,.018,.035,.78); shade.size=canvas_size; _modal.add_child(shade)
	var width:=minf(1120,canvas_size.x-64); var content:=width-96
	var body_height:=_text_height(body,content-20,25)
	var heights: Array[float]=[]
	var total:=body_height+28
	for action in actions:
		var height:=maxf(76,_text_height(str(action.text),content-84,24)+34)
		heights.append(height); total+=height+14
	var height:=minf(canvas_size.y-72,total+142)
	var left:=(canvas_size.x-width)/2; var top:=(canvas_size.y-height)/2
	Art.panel(_modal,Rect2(left,top,width,height))
	Kit.label(_modal,title,Rect2(left+48,top+27,content,58),34)
	var scroll:=ScrollContainer.new(); scroll.name="SagaModalScroll"; scroll.position=Vector2(left+48,top+103); scroll.size=Vector2(content,height-133)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO; scroll.follow_focus=true; _modal.add_child(scroll)
	var column:=VBoxContainer.new(); column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",14); scroll.add_child(column)
	var description:=Kit.label(column,body,Rect2(0,0,content-20,body_height),25)
	description.name="ModalBody"; description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; description.custom_minimum_size=Vector2(content-20,body_height); description.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var token:=operation_token()
	for index in actions.size():
		var action: Dictionary=actions[index]
		var button:=Art.button(column,"",Rect2(0,0,content-20,heights[index]),_modal_action.bind(action.call,token),index==0)
		button.custom_minimum_size.y=heights[index]; button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; button.focus_mode=Control.FOCUS_ALL; button.disabled=true
		button.tooltip_text=str(action.text)
		var label:=Kit.label(button,str(action.text),Rect2(32,17,content-84,heights[index]-34),24)
		label.name="ActionText"; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); label.offset_left=32; label.offset_right=-32; label.offset_top=15; label.offset_bottom=-15
		_modal_buttons.append(button)

func _text_height(text: String, width: float, font_size: int) -> float:
	var paragraph:=TextParagraph.new(); paragraph.width=width
	paragraph.break_flags=TextServer.BREAK_MANDATORY|TextServer.BREAK_WORD_BOUND|TextServer.BREAK_ADAPTIVE
	paragraph.add_string(text,load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf"),font_size)
	return maxf(36,ceilf(paragraph.get_size().y)+8)

func _open_party(page: String = "party") -> void:
	super._open_party(page)
	if is_instance_valid(_party_panel):
		# 实地休整点才可休息；原面板仅复用队伍、道具、装备，不开放远程免费恢复。
		_party_panel._hud.rest.hide()
