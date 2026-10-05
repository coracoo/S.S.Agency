# 战斗皮肤实际渲染夹具：真实会话与原人物PNG；终局/四敌/长状态只在隔离模型中构造。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const View = preload("res://scripts/rpg/ui/battle_view.gd")
const F = preload("res://tools/rpg/fixtures.gd")
const Status = preload("res://scripts/rpg/status_rules.gd")
const Policy = preload("res://scripts/rpg/enemy_policy.gd")
var output := ""
var battle: Control
var captures: Array[String] = []
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or OS.get_environment("ACT_ONE_OUTPUT").is_empty() or (DisplayServer.get_name() == "headless" and OS.get_environment("COMBAT_FIXTURE_CHECK") != "1"): quit(2); return
	output = OS.get_environment("ACT_ONE_OUTPUT")
	_run.call_deferred()
func _run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var session := Session.new()
	if not session.start_new(true).ok or not (await session.prepare_assets()).ok: quit(1); return
	for event in ["dialogue:a1", "dialogue:r1", "dialogue:h1"]:
		if not session.commit_event(session.campaign.safe_snapshot().world, event).ok: quit(1); return
	if not session.begin_encounter(session.campaign.safe_snapshot().world, "basin_reflection").ok: quit(1); return
	battle = View.new(); battle.router = session.router
	root.add_child(battle)
	for frame in 20: await process_frame
	battle._cancel_presentation()
	var state: Dictionary = battle.engine.snapshot()
	for id in state.actors:
		if state.actors[id].side == "player":
			state.actors[id].level = 5
			state.actors[id].hp = maxi(1, state.actors[id].hp - 20)
			state.actors[id].mp = maxi(0, state.actors[id].mp - 3)
	battle.engine.restore(state)
	if not battle.engine.last_errors.is_empty(): printerr(battle.engine.last_errors); quit(1); return
	battle._render()
	if OS.get_environment("COMBAT_MANUAL") == "1":
		root.size = Vector2i(1280, 720)
		print("COMBAT_MANUAL_READY: isolated real chapter battle")
		return
	await _shots("combat_commands")
	battle.select_command("attack_physical")
	var options: Dictionary = battle.command_options("attack_physical")
	if not options.get("targets", []).is_empty(): battle.select_target(options.targets[0])
	if not battle.current_preview().legal: printerr("单体预览夹具不合法"); quit(1); return
	await _shots("combat_target_preview")
	battle.cancel_command()
	var found_multi := false
	# 初始薄荷是游侠，没有群体技；用真实防御与AI推进到有合法群体技能的角色。
	for turn in 12:
		var current: Dictionary = battle.engine.snapshot()
		var active: Dictionary = current.actors[current.active_actor_id]
		for id in active.skill_ids:
			var skill: Dictionary = battle._catalog.get_definition("skills", id)
			if not str(skill.get("target_rule", "")).begins_with("all_"): continue
			battle.select_command("skill", id)
			var preview: Dictionary = battle.current_preview()
			if preview.legal and preview.effective_target_ids.size() > 1:
				found_multi = true
				break
		if found_multi: break
		battle.cancel_command()
		var command := {"command_id": "capture_defend_%d" % current.revision, "expected_revision": int(current.revision), "actor_id": current.active_actor_id, "kind": "defend", "ability_id": "", "target_ids": []}
		var response: Dictionary = battle.engine.submit(command)
		if not response.accepted: printerr(response.reasons); quit(1); return
		battle.engine.advance()
		battle._render()
	if not found_multi: printerr("当前角色没有合法群体预览夹具"); quit(1); return
	await _shots("combat_multi_target")
	battle.cancel_command()
	battle._basic_pressed("item")
	await _shots("combat_items")
	battle._close_items()
	battle._log_lines.clear()
	for index in 80: battle._log_lines.append("第 %d 轮：焰华 → 纸妖  伤害 28 · 目标护盾消耗 12" % (index + 1))
	battle._render(); battle._toggle_log()
	await _shots("combat_log")
	battle._toggle_log()
	battle._return_title()
	await _shots("combat_exit_confirmation")
	battle._cancel_return_title()
	var normal: Dictionary = battle.engine.snapshot()
	for outcome in ["victory", "defeat"]:
		var ending := normal.duplicate(true)
		ending.outcome = outcome; ending.phase = "outcome"; ending.active_actor_id = ""; ending.slot_token = {}; ending.queue_index = mini(ending.queue_index + 1, ending.queue.size())
		battle.engine.restore(ending)
		if not battle.engine.last_errors.is_empty(): printerr(battle.engine.last_errors); quit(1); return
		battle.result_saved = true; battle._result.show(); battle._render(); battle._show_result()
		await _shots("combat_" + outcome)
	battle.result_saved = false; battle.last_error = "测试夹具：写入被中断，请重试"
	battle._show_result()
	await _shots("combat_save_retry")
	battle._result.hide(); battle.engine.restore(normal)
	var crowded := normal.duplicate(true)
	crowded.actors["e_03_fire_spirit"] = F.enemy("fire_spirit", "e_03_fire_spirit")
	crowded.actors["e_04_elite_shield_soldier"] = F.enemy("elite_shield_soldier", "e_04_elite_shield_soldier")
	var policy := Policy.new()
	for id in ["e_03_fire_spirit", "e_04_elite_shield_soldier"]:
		crowded.actors[id].intent = policy.plan(crowded, id, battle._catalog)
	for id in crowded.actors:
		for status in [F.status("weaken", 0.1, 3, id), F.status("slow", 0.3, 2, id), F.status("mark", 1, 2, id)]:
			Status.apply(crowded.actors[id], status)
	battle.engine.restore(crowded)
	if not battle.engine.last_errors.is_empty(): printerr(battle.engine.last_errors); quit(1); return
	battle.last_error = ""; battle._build_actors(); battle._render()
	await _shots("combat_four_enemies_status")
	if OS.get_environment("COMBAT_FIXTURE_CHECK") == "1":
		battle.free(); session.close(); print("COMBAT_FIXTURES: 10 states verified; no screenshots"); quit(0); return
	var report_name := "combat_capture_report.json" if OS.get_environment("COMBAT_CAPTURE_ONLY").is_empty() else "combat_capture_" + OS.get_environment("COMBAT_CAPTURE_ONLY") + "_report.json"
	var file := FileAccess.open(output.path_join(report_name), FileAccess.WRITE)
	file.store_string(JSON.stringify({"captures": captures, "fixture": "真实会话与实际角色PNG；多敌/状态/终局为隔离可视夹具，不等同全章手动通关"}, "\t")); file.close()
	battle.free(); session.close()
	print("COMBAT_CAPTURE:", captures.size(), " screenshots plus paired text masks")
	quit(0)
func _shots(name: String) -> void:
	var only := OS.get_environment("COMBAT_CAPTURE_ONLY")
	if not only.is_empty() and only != name: return
	if OS.get_environment("COMBAT_FIXTURE_CHECK") == "1":
		print("COMBAT_FIXTURE_OK:", name); return
	for size in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(1180, 812)]:
		root.size = size
		for frame in 6: await process_frame
		paused = true
		await RenderingServer.frame_post_draw
		var filename := "%s_%dx%d.png" % [name, size.x, size.y]
		if root.get_texture().get_image().save_png(output.path_join(filename)) != OK: quit(1); return
		captures.append(filename)
		await _text_mask(filename)
		paused = false
func _text_mask(filename: String) -> void:
	var backups: Array[Dictionary] = []
	var bounds: Array[Dictionary] = []
	var pixel_scale := Vector2(root.size) / root.get_visible_rect().size
	var text_root: Node = battle._canvas
	if is_instance_valid(battle._exit_confirmation): text_root = battle._exit_confirmation
	elif battle._result.visible: text_root = battle._result
	elif battle._items.visible: text_root = battle._items
	elif battle._log_panel.visible: text_root = battle._log_panel
	var pending: Array[Node] = [text_root]
	while not pending.is_empty():
		var node: Node = pending.pop_back(); pending.append_array(node.get_children())
		if not node is Control or not node.is_visible_in_tree(): continue
		if node is Button:
			var rect: Rect2 = node.get_global_rect()
			rect.position *= pixel_scale
			rect.size *= pixel_scale
			bounds.append({"text": node.text, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
			var colors: Dictionary = {}
			for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_outline_color", "font_shadow_color"]:
				colors[key] = node.get_theme_color(key); node.add_theme_color_override(key, Color.TRANSPARENT)
			backups.append({"node": node, "colors": colors})
		elif node is Label or node is RichTextLabel:
			backups.append({"node": node, "modulate": node.self_modulate}); node.self_modulate = Color(1, 1, 1, 0)
	for frame in 2: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(filename.trim_suffix(".png") + "_notext.png"))
	var file := FileAccess.open(output.path_join(filename.trim_suffix(".png") + "_text_bounds.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"image": filename, "scale": battle._canvas.scale.y * pixel_scale.y, "viewport_scale": [pixel_scale.x, pixel_scale.y], "buttons": bounds}, "\t")); file.close()
	for saved in backups:
		if saved.has("colors"):
			for key in saved.colors: saved.node.add_theme_color_override(key, saved.colors[key])
		else: saved.node.self_modulate = saved.modulate
	await process_frame
