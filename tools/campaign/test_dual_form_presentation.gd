# 双职业使用真实正式会话、权威引擎与UI；仅临时测试目录写档。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const View = preload("res://scripts/rpg/ui/battle_view.gd")
const PartyPanel = preload("res://scripts/campaign/party_panel.gd")
var failures: Array[String] = []
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(1); return
	_run.call_deferred()
func _finish() -> void:
	for failure in failures: printerr("ASSERT FAIL: ", failure)
	print("DUAL FORM PRESENTATION: ", assertions, " assertions, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
func _result(session: RefCounted, started: Dictionary, outcome: String, actors: Dictionary = {}) -> Dictionary:
	var roster: Array[Dictionary] = []
	for id in session.campaign.safe_snapshot().party:
		var actor: Dictionary = (actors if not actors.is_empty() else started.setup.actors)[id].duplicate(true)
		if outcome == "defeat": actor.hp = 0
		roster.append(actor)
	return {"battle_id": started.battle_id, "outcome": outcome, "roster": roster, "inventory": started.setup.inventory.duplicate(true), "xp": started.xp if outcome == "victory" else 0, "story_patch": started.story_patch.duplicate(true) if outcome == "victory" else {}, "replay": {}}
func _events(session: RefCounted, night: int) -> void:
	for event in Chapters.events(night):
		if event == "dialogue:hd5": continue
		check(session.commit_event(session.campaign.safe_snapshot().world, event).ok, "整合测试登记事件：" + event)
func _run() -> void:
	var session := Session.new()
	check(session.start_new(true, ["mage", "ranger", "guard"]).ok, "双职业正式三人新档")
	var actor: Dictionary = session.campaign.safe_snapshot().roster.p_mage
	check(actor.get("form_id") == "sword" and actor.get("active_class_id") == "swordsman" and actor.get("unlocked_forms") == ["sword"], "焰华开局剑士且术形态锁定")
	var probe_view := View.new()
	check(probe_view.has_method("switch_active_form"), "真实战斗自由切换按钮提交接口")
	probe_view.free()
	if actor.get("dual_form_version") != 1: session.close(); _finish(); return
	check((await session.prepare_assets()).ok and session.bundle._definitions.size() == 4 and session.bundle.get_definition("homura", "mage").get("ok", false), "所选焰华双高清形态预载，未选身份不常驻")
	var panel := PartyPanel.new()
	root.add_child(panel); panel.open(session); panel.select_actor("p_mage")
	check(panel._hud.form.disabled and panel._hud.form.text.contains("未解锁"), "首夜整备显示法师未解锁")
	var before: Dictionary = session.campaign.safe_snapshot()
	check(not (await panel.toggle_form()).ok and session.campaign.safe_snapshot() == before, "首夜panel不能绕过术形态锁")
	if not OS.get_environment("CAMPAIGN_PRESENTATION_OUTPUT").is_empty(): await _save_frame("party_homura_sword_locked.png")
	panel.free()
	_events(session, 1)
	var first: Dictionary = session.begin_encounter(session.campaign.safe_snapshot().world, "basin_reflection")
	check(first.ok, "首夜战前剑形态保存")
	check(session.router.finish(_result(session, first, "victory")).ok, "真实首夜胜利事务解锁法师")
	check(session.campaign.safe_snapshot().roster.p_mage.unlocked_forms == ["sword", "mage"] and session.campaign.safe_snapshot().roster.p_mage.form_id == "sword", "解锁新形态但不擅自切换")
	var resumed := Session.new()
	check(resumed.resume().ok and resumed.campaign.safe_snapshot().roster.p_mage.unlocked_forms == ["sword", "mage"], "解锁写档后重启保留")
	check(resumed.advance_night(resumed.campaign.safe_snapshot().world).ok, "进入第二夜测试战内自由切换")
	check((await resumed.prepare_assets()).ok, "续档所选双形态资源就绪")
	_events(resumed, 2)
	var second: Dictionary = resumed.begin_encounter(resumed.campaign.safe_snapshot().world, "bell_self_ring")
	check(second.ok, "第二夜战前仍为剑形态")
	var engine: RefCounted = resumed.router.create_engine()
	_seek_homura(engine)
	check(engine.snapshot().active_actor_id == "p_mage", "真实队列到焰华当前行动槽")
	if engine.snapshot().active_actor_id != "p_mage": resumed.close(); _finish(); return
	var view := View.new()
	view.router = resumed.router
	root.add_child(view)
	view._cancel_presentation()
	view._render()
	check(view._hud.has("form") and view._hud.form.visible and not view._hud.form.disabled, "解锁后当前焰华行动显示可用切换按钮")
	var catalog := Catalog.new(); catalog.load_all()
	var sword_skills: Array = catalog.get_definition("classes", "swordsman").skill_ids
	var mage_skills: Array = catalog.get_definition("classes", "mage").skill_ids
	check(engine.snapshot().actors.p_mage.skill_ids == sword_skills and not view._basic_buttons.attack_magic.visible, "剑士四技能与物理基础指令显示")
	# 把真实冷却值加入合法恢复快照，验证形态切换不重置该角色的共享冷却。
	var cooldown_state: Dictionary = engine.snapshot()
	cooldown_state.actors.p_mage.cooldown_until["firebolt"] = int(cooldown_state.actors.p_mage.slot_count) + 2
	engine.restore(cooldown_state)
	check(engine.last_errors.is_empty(), "共享CD夹具通过真实restore验证：" + str(engine.last_errors))
	var switch_before: Dictionary = engine.snapshot()
	if not OS.get_environment("CAMPAIGN_PRESENTATION_OUTPUT").is_empty(): await _save_frame("battle_homura_sword_turn.png")
	var changed: Dictionary = view.call("switch_active_form")
	check(changed.get("accepted", false), "UI通过唯一引擎submit成功切至法师")
	var switched: Dictionary = engine.snapshot()
	for field in ["phase", "active_actor_id", "slot_token", "queue", "queue_index", "rng_state", "inventory"]: check(switched[field] == switch_before[field], "自由切换保留行动槽/队列/RNG/库存：" + field)
	for field in ["hp", "mp", "stats", "equipment", "cooldown_until", "statuses", "slot_count", "opportunity_count"]: check(switched.actors.p_mage[field] == switch_before.actors.p_mage[field], "自由切换不改共享资源：" + field)
	check(switched.revision == switch_before.revision + 1 and switched.actors.p_mage.skill_ids == mage_skills and switched.actors.p_mage.active_class_id == "mage", "只更新revision、当前职业与法师四技能")
	check(view._hd_views.p_mage._definition.manifest.form_id == "mage" and view._basic_buttons.attack_magic.visible and view._skill_buttons[0].text.contains("火弹"), "同一高清节点瞬时换术形态、魔攻和四技能")
	check(not view._hd_player.is_busy() and not view.processing, "自由切换不触发攻击动画、不锁额外行动")
	if not OS.get_environment("CAMPAIGN_PRESENTATION_OUTPUT").is_empty(): await _save_frame("battle_homura_mage_turn.png")
	var cd_preview: Dictionary = engine.preview({"command_id": "probe_cooldown", "expected_revision": switched.revision, "actor_id": "p_mage", "kind": "skill", "ability_id": "firebolt", "target_ids": ["e_01_hound"]})
	check(not cd_preview.legal and cd_preview.reasons.has("技能冷却中"), "切回法师不能绕过其已有技能CD：" + str(cd_preview.reasons) + " / " + str(switched.actors.p_mage.cooldown_until))
	check(view.call("switch_active_form").get("accepted", false) and engine.snapshot().actors.p_mage.skill_ids == sword_skills, "同一行动槽自由切回剑士")
	check(view.call("switch_active_form").get("accepted", false), "再切术形态不新增行动槽")
	var defeat: Dictionary = resumed.router.finish(_result(resumed, second, "defeat", engine.snapshot().actors))
	check(defeat.ok and resumed.router.retry().ok and resumed.router.create_engine().snapshot().actors.p_mage.form_id == "sword", "败北重试恢复战前剑形态，不持久战内临时切换")
	view.free()
	engine = resumed.router.create_engine(); _seek_homura(engine)
	view = View.new(); view.router = resumed.router; root.add_child(view); view._cancel_presentation(); view._render()
	check(view.call("switch_active_form").get("accepted", false), "重试仍可在本人行动槽切术")
	var victory: Dictionary = resumed.router.finish(_result(resumed, second, "victory", engine.snapshot().actors))
	check(victory.ok and resumed.campaign.safe_snapshot().roster.p_mage.form_id == "mage" and resumed.campaign.safe_snapshot().roster.p_mage.skill_ids == mage_skills, "胜利提交持久最终职业与四技能")
	view.free(); resumed.close()
	var final_session := Session.new()
	check(final_session.resume().ok and final_session.campaign.safe_snapshot().roster.p_mage.form_id == "mage", "最终职业保存后重进保留")
	final_session.close()
	_finish()
func _seek_homura(engine: RefCounted) -> void:
	for index in 12:
		engine.advance()
		var state: Dictionary = engine.snapshot()
		if state.active_actor_id == "p_mage" or not state.outcome.is_empty(): return
		if state.phase == "action_selection":
			var command := {"command_id": "seek_%d_%d" % [index, state.revision], "expected_revision": state.revision, "actor_id": state.active_actor_id, "kind": "defend", "ability_id": "", "target_ids": []}
			check(engine.submit(command).accepted, "测试正常防御推进到焰华，不跳队列")

func _save_frame(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_viewport().get_texture().get_image().save_png(OS.get_environment("CAMPAIGN_PRESENTATION_OUTPUT").path_join(filename)) == OK, "双职业图形证据：" + filename)
