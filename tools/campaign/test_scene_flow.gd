# 正式五夜场景契约；运行前由test_environment.gd核验隔离user目录。
extends SceneTree
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
const Campaign = preload("res://scripts/rpg/campaign.gd")
const Session = preload("res://scripts/campaign/chapter_session.gd")
const SaveBase = preload("res://scripts/rpg/save_store.gd")
const Router = preload("res://scripts/rpg/encounter_router.gd")
const Dialogue = preload("res://scripts/ui/dialogue_overlay.gd")
class FaultStore extends SaveBase:
	var fail_write := false
	func _replace_file(temporary: String, destination: String) -> Error:
		return ERR_FILE_CANT_WRITE if fail_write else super._replace_file(temporary, destination)
var failures: Array[String] = []
var checks := 0
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1":
		printerr("FAIL: 必须先验证隔离user目录")
		quit(2)
		return
	call_deferred("_run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)
func _run() -> void:
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/campaign/title.tscn", "唯一入口必须是正式主线标题")
	for id in range(1, 6):
		var path := "res://scenes/campaign/night_%d.tscn" % id
		check(ResourceLoader.exists(path), "第%d夜缺少3D场景" % id)
		if not ResourceLoader.exists(path): continue
		var packed: PackedScene = load(path)
		check(packed != null, "第%d夜场景可加载" % id)
		if packed == null: continue
		var stage: Node = packed.instantiate()
		check(stage is Node3D, "第%d夜必须真实Node3D" % id)
		check(stage.get("night_id") == id, "第%d夜绑定正确登记" % id)
		stage.free()
	check(ResourceLoader.exists("res://scripts/campaign/chapter_stage.gd"), "缺少正式章节控制器")
	check(ResourceLoader.exists("res://scripts/campaign/chapter_geometry.gd"), "缺少正式三维地形")
	check(ResourceLoader.exists("res://scenes/campaign/ending.tscn"), "缺少结尾画面")
	if ResourceLoader.exists("res://scripts/campaign/chapter_stage.gd"):
		var Stage = load("res://scripts/campaign/chapter_stage.gd")
		var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogues.json"))
		var roots := {1: ["a1", "r1", "h1"], 2: ["c1"], 3: ["p1", "p3"], 4: ["m1"], 5: ["hd1", "hd5"]}
		var original_keys := ["test_approach", "corridor_act", "night3_procession", "night4_mirror", "honden_act"]
		var total := 0
		for id in range(1, 6):
			var nodes: Dictionary = Stage.dialogue_nodes(id)
			var original: Dictionary = source.stages[original_keys[id - 1]].nodes
			var visited: Dictionary = {}
			for root_id in roots[id]: _walk(nodes, root_id, visited)
			check(visited.size() == original.size(), "第%d夜所有原剧情节点具有实际触发路径" % id)
			for key in original:
				check(nodes.has(key) and nodes[key].text == original[key].text, "不得改正文：" + key)
				total += 1
		check(total == 38, "保留38个探索节点")
		var final_nodes: Dictionary = Stage.dialogue_nodes(5)
		check(final_nodes.hd4.next == "", "hd1链战前止于hd4")
		check(source.stages.honden_act.nodes.hd4.next == "hd5", "不得改源JSON的hd4")
		_test_input_guards(Stage)
		var subject = Stage.new()
		check(subject.has_method("clue_record"), "场景须读取每夜原线索正文")
		if subject.has_method("clue_record"):
			for id in range(1, 6):
				var definition: Dictionary = Chapters.night(id)
				var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/clues/%s.json" % definition.dialogue_stage))
				var record: Dictionary = subject.clue_record(id, definition.clue_id)
				check(record.hint == original.clues[0].hint and record.resolve_text == original.clues[0].resolve_text, "第%d夜线索正文原样接入" % id)
			check(subject.clue_record(2, "coffin_sendoff").hint.contains("先辨认、再安放、最后引路"), "守灯三步接原残文")
		subject.free()
	_test_dialogue_overlay()
	await _test_scene_runtime()
	if failures.is_empty(): print("CAMPAIGN_SCENE_OK: %d checks" % checks)
	else: printerr("CAMPAIGN_SCENE_FAIL: %d/%d" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
func _walk(nodes: Dictionary, id: String, visited: Dictionary) -> void:
	if id.is_empty() or visited.has(id) or not nodes.has(id): return
	visited[id] = true
	var node: Dictionary = nodes[id]
	_walk(nodes, str(node.get("next", "")), visited)
	for choice in node.get("choices", []): _walk(nodes, str(choice.get("next", "")), visited)
func _test_input_guards(Stage: Script) -> void:
	var stage = Stage.new()
	stage.ready_for_play = true
	stage.set_controls_enabled(true)
	check(stage.begin_operation("dialogue"), "可开始一次对话操作")
	check(not stage.controls_enabled, "对话锁行动")
	check(not stage.begin_operation("battle"), "双击不能重入战斗")
	var token: int = stage.operation_token()
	stage.shutdown()
	check(not stage.callback_valid(token), "离场后旧回调失效")
	check(not stage.begin_operation("dialogue"), "离场后不能重入")
	stage.free()

func _test_dialogue_overlay() -> void:
	load("res://scripts/campaign/chapter_stage.gd")._register_input()
	var dialogue := Dialogue.new()
	root.add_child(dialogue)
	dialogue._update_portrait("right", "res://assets/chars/portraits/hakuyo_half.png", "hakuyo")
	check(dialogue._portraits.right.tex != null, "旧说话者肖像可见")
	dialogue._update_portrait("right", "", "guanshou")
	check(dialogue._portraits.right.tex == null and dialogue._portraits.right.ctrl.tex == null, "空肖像清除薄荷，棺守不串图")
	dialogue._active = true
	dialogue._waiting_choice = true
	dialogue.choice_guard = func(_next): return {"ok": false, "error": "模拟选择保存失败"}
	dialogue._pick_choice("e_send")
	check(dialogue._waiting_choice and dialogue._choice_next.is_empty(), "选择写失败停留原选项")
	dialogue.choice_guard = func(_next): return {"ok": true}
	dialogue._pick_choice("e_send")
	check(not dialogue._waiting_choice and dialogue._choice_next == "e_send", "选择保存后才进入分支")
	dialogue._pick_choice("e_seal")
	check(dialogue._choice_next == "e_send", "同帧双击分支只取一次")
	dialogue.abort()
	dialogue.free()
	var held := Dialogue.new()
	root.add_child(held)
	held.advance_action = &"approach_interact"
	held.require_release = true
	Input.action_press("approach_interact")
	held.play({"node": {"text": "保持键不会翻页", "next": ""}}, "node")
	check(not held._advance_armed, "对白打开时按住E必须先释放")
	Input.action_release("approach_interact")
	held.abort()
	held.free()
	var case: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Chapters.CASE_PATH))
	var reached: Dictionary = {}
	_walk(case.nodes, "t1", reached)
	check(reached.size() == 14, "原14个结案节点与两支线均可达")
func _frames(count: int) -> void:
	for index in range(count): await physics_frame
func _silence_dialogue(stage: Node) -> void:
	stage._generation += 1
	if is_instance_valid(stage._dialogue):
		stage._dialogue.abort()
		stage._dialogue.queue_free()
	stage._dialogue = null
	stage._resume_explore()
func _victory(session: RefCounted, started: Dictionary) -> Dictionary:
	var roster: Array[Dictionary] = []
	for id in session.campaign.safe_snapshot().party: roster.append(started.setup.actors[id].duplicate(true))
	return {"battle_id": started.battle_id, "outcome": "victory", "roster": roster, "inventory": started.setup.inventory.duplicate(true), "xp": started.xp, "story_patch": started.story_patch.duplicate(true), "replay": {}}
func _test_scene_runtime() -> void:
	var store := FaultStore.new()
	var session := Session.new(Campaign.new(null, store, Chapters.SAVE_PATH))
	var started: Dictionary = session.start_new(true)
	check(started.ok, "真实正式会话建立")
	if not started.ok: return
	var assets: Dictionary = await session.prepare_assets()
	check(assets.ok, "真实已批准人物资源加载")
	if not assets.ok: return
	for id in range(1, 6):
		# 夹具直接置于本夜入口，测试入口对白；真实跨夜留原位另由连续世界测试覆盖。
		if id > 1:
			var arrival: Dictionary = session.campaign.safe_snapshot().world
			arrival.position = Chapters.night(id).anchors.spawn.duplicate()
			check(session.save_world(arrival).ok, "第%d夜入口夹具合法保存" % id)
		var stage: Node3D = load(Chapters.scene_path(id)).instantiate()
		root.add_child(stage)
		await _frames(4)
		check(stage.ready_for_play, "第%d夜真实场景树已就绪" % id)
		if not stage.ready_for_play:
			stage.free()
			return
		check(not stage.controls_enabled and stage._mode == "dialogue", "第%d夜入口剧情锁移动" % id)
		_silence_dialogue(stage)
		await _test_hd2d_hud(stage, id)
		var before: Vector3 = stage.player.position
		stage.player.set_move_input(Vector2.RIGHT)
		await _frames(6)
		check(stage.player.position.x > before.x + 0.01, "第%d夜可在真实3D空间移动" % id)
		check(stage.begin_operation("dialogue"), "第%d夜操作锁可进入" % id)
		var locked: Vector3 = stage.player.position
		await _frames(4)
		check(Vector2(stage.player.position.x - locked.x, stage.player.position.z - locked.z).length() < 0.005, "第%d夜菜单/对话锁停止实际平面位移" % id)
		stage.player.keyboard_input = true
		Input.action_press("approach_right")
		stage._resume_explore()
		await _frames(4)
		check(absf(stage.player.position.x - locked.x) < 0.005, "第%d夜菜单关闭后按住移动键不穿透" % id)
		Input.action_release("approach_right")
		await _frames(2)
		Input.action_press("approach_right")
		await _frames(6)
		check(stage.player.position.x > locked.x + 0.01, "第%d夜释放并重按后恢复移动" % id)
		Input.action_release("approach_right")
		await _frames(2)
		await _test_opposite_movement_keys(stage, id, "approach_left", "approach_right")
		await _test_opposite_movement_keys(stage, id, "approach_forward", "approach_back")
		for target in stage.config.interactions:
			check(stage.interaction_dispatch(target.id) == target.kind, "实际调查分派：第%d夜/%s" % [id, target.id])
		check(not stage.request_interaction("unregistered"), "未登记调查不得推进")
		var safe: Dictionary = session.campaign.safe_snapshot().world
		safe["test_extension"] = {"keep": true}
		check(stage.restore_world(safe).ok and stage.export_world().test_extension.keep, "第%d夜快照未知合法字段保留" % id)
		stage._world.erase("test_extension")
		var airborne: Dictionary = stage.export_world()
		airborne.position = [stage.config.anchors.spawn[0], 1.6, stage.config.anchors.spawn[2]]
		var recovered: Dictionary = stage.restore_world(airborne)
		check(recovered.ok and recovered.used_fallback and stage.player.position.distance_to(GeometryVector(stage.config.anchors.spawn)) < 0.1, "第%d夜悬空位置恢复真实安全锚点" % id)
		var invalid: Dictionary = stage.export_world()
		invalid.position = [999, 0, 0]
		check(not stage.restore_world(invalid).ok, "第%d夜越界存档明确拒绝" % id)
		check(stage.begin_operation("confirmation"), "第%d夜调查确认锁可进入" % id)
		var presses: Array[int] = [0]
		stage._show_modal("确认测试", "测试连击", [{"text": "确认", "call": func(): presses[0] += 1}])
		var modal_token: int = stage.operation_token()
		stage._confirm_armed = false
		stage._modal_action(func(): presses[0] += 1, modal_token)
		check(presses[0] == 0, "第%d夜确认未释放E/鼠标前不执行" % id)
		stage._confirm_armed = true
		stage._modal_action(func(): presses[0] += 1, modal_token)
		stage._modal_action(func(): presses[0] += 1, modal_token)
		check(presses[0] == 1, "第%d夜同帧双击确认只执行一次" % id)
		stage._resume_explore()
		var intro := str(stage.config.intro)
		store.fail_write = true
		stage._commit_dialogue(intro, Callable())
		check(stage._mode == "error" and not stage.controls_enabled and not stage._world.event_flags.has("dialogue:" + intro), "第%d夜对白保存失败不推进/不放行" % id)
		store.fail_write = false
		stage._commit_dialogue(intro, Callable())
		check(stage.controls_enabled and stage._world.event_flags.has("dialogue:" + intro), "第%d夜重试保存成功后恢复探索" % id)
		for event_id in Chapters.events(id):
			if event_id == "dialogue:hd5": continue
			if stage._world.event_flags.has(event_id): continue
			if event_id.begins_with("ritual:"):
				stage._confirm_armed = true
				var disk_before := FileAccess.get_file_as_string(Chapters.SAVE_PATH)
				check(stage.request_interaction(event_id), "守灯步骤实际弹出确认：" + event_id)
				stage._resume_explore()
				check(FileAccess.get_file_as_string(Chapters.SAVE_PATH) == disk_before, "取消仪式不写完成：" + event_id)
				store.fail_write = true
				stage._commit_ritual(event_id)
				check(not stage._world.event_flags.has(event_id), "仪式失败不推进：" + event_id)
				store.fail_write = false
				stage._commit_ritual(event_id)
				check(stage._world.event_flags.has(event_id), "守灯步骤已成功逐步保存：" + event_id)
			else:
				var committed: Dictionary = session.commit_event(stage.export_world(), event_id)
				check(committed.ok, "真实对白事件提交：" + event_id)
				stage.apply_committed_world(committed.world)
		var battle_position: Vector3 = stage.player.position
		var encounter: Dictionary = session.begin_encounter(stage.export_world(), Chapters.night(id).clue_id)
		check(encounter.ok, "第%d夜实际统一RPG入口" % id)
		if not encounter.ok:
			stage.free()
			return
		var returned: Dictionary = session.router.finish(_victory(session, encounter))
		check(returned.ok and returned.next_scene == Chapters.scene_path(id), "第%d夜战果返场到正确3D夜晚" % id)
		check(stage.restore_world(returned.world).ok and stage.player.position.distance_to(battle_position) < 0.1, "第%d夜战后恢复战前真实位置" % id)
		stage.apply_committed_world(returned.world)
		if id == 1:
			check(returned.get("unlocked_forms", []) == ["mage"], "真实首夜Router胜利结果产生法师解锁通知")
			var before_notice: Dictionary = session.campaign.safe_snapshot()
			var disk_before_notice := FileAccess.get_file_as_string(Chapters.SAVE_PATH)
			var returned_stage: Node3D = load(Chapters.scene_path(1)).instantiate()
			root.add_child(returned_stage)
			await _frames(4)
			check(returned_stage._hud.notice.text == "焰华的法师形态已解锁，可在整备或她行动时自由切换。" and returned_stage._hud.notice.is_visible_in_tree(), "真实战后返场HUD可见最短解锁提示")
			check(returned_stage.controls_enabled and returned_stage._mode == "explore" and returned_stage._modal == null, "解锁提示不引入模态或改变探索锁")
			check(Router.take_unlocked_forms().is_empty(), "Stage已一次性消费Router解锁通知")
			returned_stage.free()
			var second_stage: Node3D = load(Chapters.scene_path(1)).instantiate()
			root.add_child(second_stage)
			await _frames(4)
			check(second_stage._hud.notice.text.is_empty(), "重复重建且无通知不显示解锁提示")
			check(session.campaign.safe_snapshot() == before_notice and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == disk_before_notice, "解锁展示不改存档或二次发奖")
			second_stage.free()
		if id == 5:
			stage._commit_dialogue("hd5", Callable())
			check(stage._world.event_flags.has("dialogue:hd5"), "hd5战后实际提交")
		var token: int = stage.operation_token()
		if id == 5:
			stage._advance_night()
			check(session.campaign.safe_snapshot().story_phase == "ending" and stage._mode == "ending" and stage._dialogue._playing_id == "t1", "第五夜场景先保存ending检查点才播放结案")
		else:
			var advanced: Dictionary = session.advance_night(stage.export_world())
			check(advanced.ok, "第%d夜出口正式提交" % id)
		stage.shutdown()
		check(not stage.callback_valid(token), "第%d夜离场废弃旧回调" % id)
		stage.free()
		await _frames(2)
	var selected: Dictionary = session.choose_resolution(session.campaign.safe_snapshot().world, "seal_monitoring")
	check(selected.ok and session.campaign.safe_snapshot().case_status == "monitoring", "镇守实际保存续监状态")
	session.close()
	var resumed := Session.new()
	check(resumed.resume().ok and resumed.campaign.safe_snapshot().resolution == "seal_monitoring", "退出后选择已保存可恢复")
	resumed.close()
	var title: Node3D = load("res://scenes/campaign/title.tscn").instantiate()
	root.add_child(title)
	title._set_busy(true)
	title._request_new()
	title._continue()
	check(title._session == null, "标题加载中双击开始/继续不能建重复会话")
	var generation_before: int = title._generation
	title._cancel_loading()
	check(not title._busy and title._generation > generation_before and title._session == null, "取消加载使旧回调失效并恢复标题")
	title._set_busy(false)
	var before_replace := FileAccess.get_file_as_string(Chapters.SAVE_PATH)
	title._request_new()
	var replacement: Control = title._replace_panel
	title._request_new()
	check(is_instance_valid(replacement) and title._replace_panel == replacement, "标题已有存档只打开一个替换确认")
	title._cancel_replace()
	check(FileAccess.get_file_as_string(Chapters.SAVE_PATH) == before_replace, "取消新游戏替换不改原正式存档")
	title.free()
func GeometryVector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

# 相反action仍各自pressed；合成轴零不能代表玩家已全部释放。
func _test_opposite_movement_keys(stage: Node, night: int, first: String, second: String) -> void:
	check(stage.begin_operation("pause"), "第%d夜相反键测试先锁菜单：%s" % [night, first])
	Input.action_press(first)
	Input.action_press(second)
	stage._resume_explore()
	await _frames(4)
	check(not stage.player._movement_armed and stage.player.move_input == Vector2.ZERO, "第%d夜相反键同按关闭菜单仍锁：%s" % [night, first])
	var before: Vector3 = stage.player.position
	Input.action_release(first)
	await _frames(5)
	check(not stage.player._movement_armed and stage.player.move_input == Vector2.ZERO and Vector2(stage.player.position.x - before.x, stage.player.position.z - before.z).length() < 0.005, "第%d夜只松相反键之一，未释放的另键不穿透：%s" % [night, second])
	Input.action_release(second)
	await _frames(2)
	check(stage.player._movement_armed, "第%d夜所有移动键全松才解除锁：%s" % [night, first])
	Input.action_press(second)
	await _frames(3)
	check(stage.player.move_input != Vector2.ZERO, "第%d夜全部释放后重新按方向恢复：%s" % [night, second])
	Input.action_release(second)
	await _frames(2)

func _test_hd2d_hud(stage: Node3D, id: int) -> void:
	# UI 精修后景深开关降权进暂停菜单（docs/campaign/ui-atmosphere.md），不再占右上 HUD。
	check(stage.hd2d_experiment, "第%d夜全图默认开启分层景深" % id)
	check(is_equal_approx(stage.camera_rig.camera.size, 9.2), "第%d夜全图景深人物尺寸基线 9.2" % id)
	check(stage._hud.get("hd2d") == null, "第%d夜景深开关不占探索 HUD 角落" % id)
	var world_before: Dictionary = stage.export_world()
	var disk_before := FileAccess.get_file_as_string(Chapters.SAVE_PATH)
	var geometry_id: int = stage._geometry.get_instance_id()
	# 暂停菜单里的景深开关：按一次关、再按开，人物尺寸不跳变。
	check(stage.begin_operation("pause"), "第%d夜进入暂停菜单" % id)
	stage._confirm_armed = true
	stage._show_pause_menu()
	await _frames(2)
	var button: Button = _modal_button(stage, "景深：开")
	check(button != null, "第%d夜暂停菜单提供景深开关" % id)
	if button == null:
		stage._resume_explore()
		return
	stage._confirm_armed = true
	button.pressed.emit()
	await _frames(2)
	check(not stage.hd2d_experiment, "实际按钮信号关闭景深")
	var off_button: Button = _modal_button(stage, "景深：关")
	check(off_button != null, "关闭后暂停菜单按钮同步为「景深：关」")
	if off_button == null:
		stage._resume_explore()
		return
	stage._confirm_armed = true
	off_button.pressed.emit()
	await _frames(2)
	check(stage.hd2d_experiment and is_equal_approx(stage.camera_rig.camera.size, 9.2), "再次点击恢复全图景深，人物尺寸不跳变")
	check(stage._geometry.get_instance_id() == geometry_id, "开关不将连续世界换回旧小房间")
	check(stage.export_world() == world_before and FileAccess.get_file_as_string(Chapters.SAVE_PATH) == disk_before, "景深开关不写世界状态或存档")
	stage._resume_explore()
	# 锁定模式守卫：只有暂停模式能切，战斗/仪式/对白与转场中都不能。
	for mode in ["battle", "ritual", "dialogue"]:
		stage._confirm_armed = true
		check(stage.begin_operation(mode), "进入锁定模式" + mode)
		stage._toggle_depth_from_pause()
		check(stage.hd2d_experiment, "锁定模式" + mode + "程序触发也不能切换")
		stage._resume_explore()
	stage._confirm_armed = true
	check(stage.begin_operation("pause"), "第%d夜再次进入暂停" % id)
	stage._transition_busy = true
	stage._toggle_depth_from_pause()
	check(stage.hd2d_experiment, "转场时不切换")
	stage._transition_busy = false
	stage._resume_explore()

func _modal_button(stage: Node3D, text: String) -> Button:
	for button: Button in stage._modal_buttons:
		if is_instance_valid(button) and button.text == text: return button
	return null
