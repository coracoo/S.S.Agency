# UI契约验证真实模型；预览、取消和重复确认绝不另算规则。
extends RefCounted
const F = preload("res://tools/rpg/fixtures.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Battle = preload("res://scripts/rpg/battle_engine.gd")
const Campaign = preload("res://scripts/rpg/campaign.gd")
const Router = preload("res://scripts/rpg/encounter_router.gd")
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
const Store = preload("res://scripts/rpg/save_store.gd")
const Policy = preload("res://scripts/rpg/enemy_policy.gd")

static func run() -> Array[String]:
	F.assertion_count = 0
	var failures: Array[String] = []
	for name in ["battle_presenter", "battle_view", "launcher_view"]:
		F.expect(FileAccess.file_exists("res://scripts/rpg/ui/%s.gd" % name), "缺少真实UI：" + name, failures)
	for name in ["battle", "launcher"]:
		F.expect(FileAccess.file_exists("res://scenes/rpg/%s.tscn" % name), "缺少可玩场景：" + name, failures)
	if not failures.is_empty(): return failures
	var Presenter = load("res://scripts/rpg/ui/battle_presenter.gd")
	var View = load("res://scripts/rpg/ui/battle_view.gd")
	var catalog := Catalog.new()
	catalog.load_all()
	F.expect(Presenter.ability_name("mana_potion", catalog) == "魔力药", "道具选定预览使用中文名称", failures)
	var actors := {"p_guard": F.actor("guard", "p_guard"), "p_swordsman": F.actor("swordsman", "p_swordsman"), "p_healer": F.actor("healer", "p_healer"), "e_1": F.enemy("hound", "e_1")}
	var engine := Battle.new(catalog)
	engine.set_policy(Policy.new())
	engine.start({"actors": actors, "inventory": {"healing_potion": 3, "mana_potion": 1, "revival_potion": 1, "cleansing_powder": 1}}, 1701)
	var view = View.new()
	view.bind(engine, null)
	var before: Dictionary = engine.snapshot()
	var projected: Dictionary = Presenter.present(before, catalog)
	F.expect(projected.commands.skills.size() == 4, "当前职业始终四个固定技能位", failures)
	F.expect(projected.commands.basic.has("attack_physical") and projected.commands.basic.has("defend") and projected.commands.basic.has("item"), "普攻防御道具恒有入口", failures)
	view.select_command("skill", "heavy_slash")
	view.select_target("e_1")
	F.expect(view.current_preview().legal, "技能与目标只预览", failures)
	F.expect(engine.snapshot() == before, "点击目标不改HP/MP/RNG", failures)
	view.cancel_command()
	F.expect(view.pending_command.is_empty() and engine.snapshot() == before, "取消免费且清选择", failures)
	view.select_command("skill", "heavy_slash")
	view.select_target("e_1")
	var command_id: String = view.pending_command.command_id
	view.confirm_command()
	view.confirm_command()
	var after: Dictionary = engine.snapshot()
	F.expect(after.accepted_commands.has(command_id) and after.command_log.size() == before.command_log.size() + 1, "双击确认同一ID只执行一次", failures)
	F.expect(after.actors.p_swordsman.mp == before.actors.p_swordsman.mp - 8, "只收一次实际MP", failures)
	F.expect(view.processing, "提交期间输入锁定", failures)
	view.free()
	# 低MP、CD、群体受影响成员均来自引擎预览。
	engine = Battle.new(catalog)
	engine.set_policy(Policy.new())
	actors.p_swordsman.mp = 0
	engine.start({"actors": actors, "inventory": {"healing_potion": 0}}, 1701)
	engine.advance(false)
	view = View.new()
	view.bind(engine, null)
	view.select_command("skill", "heavy_slash")
	view.select_target("e_1")
	F.expect(not view.current_preview().legal and view.current_preview().reasons.has("MP不足"), "MP不足原因完整可读", failures)
	view.cancel_command()
	view.select_command("skill", "sweep")
	F.expect(view.current_preview().effective_target_ids == ["e_1"], "全体技能显示模型全部目标", failures)
	view.free()
	await _test_automatic_target_clicks(View, catalog, failures)
	await _test_single_target_auto_select(View, catalog, failures)
	_test_intent_details(Presenter, catalog, failures)
	_test_model_projection(Presenter, View, catalog, failures)
	await _test_intent_label_bounds(View, catalog, failures)
	await _test_four_enemy_layout(View, catalog, failures)
	await _test_boss_head_visibility(View, catalog, failures)
	await _test_disabled_skill_reasons(View, catalog, failures)
	_test_fallen_targets(View, catalog, failures)
	_test_launcher_save_boundary(failures)
	_test_independent_mode_return(failures)
	await _test_battle_scene_ready(View, catalog, failures)
	_test_save_result_retry(View, failures)
	var Launcher = load("res://scripts/rpg/ui/launcher_view.gd")
	var launcher = Launcher.new()
	var tree: SceneTree = Engine.get_main_loop()
	tree.root.add_child(launcher)
	await tree.process_frame
	F.expect(not launcher._hud.inventory.text.is_empty(), "真实准备场景ready完成库存与按钮投影", failures)
	F.expect(not launcher._hud.roster_notice.disabled and launcher.available_class_ids.size() == 6, "六职业编队分支入口开放", failures)
	launcher.free()
	await load("res://tools/rpg/test_exploration_ui.gd").run(failures, catalog)
	await load("res://tools/rpg/test_exploration_ui.gd").test_item_boundaries(failures, catalog)
	print("RPG ui 断言：", F.assertion_count)
	return failures

static func _test_model_projection(Presenter, View, catalog, failures: Array[String]) -> void:
	for class_id in ["guard", "swordsman", "healer"]:
		var actor: Dictionary = F.actor(class_id, "p_active")
		actor.stats.spd = 100
		var engine := Battle.new(catalog)
		engine.start({"actors": {"p_active": actor, "e_1": F.enemy("hound", "e_1")}, "inventory": {"healing_potion": 3}}, 1701)
		var view = View.new()
		view.bind(engine, null)
		var model: Dictionary = Presenter.present(engine.snapshot(), catalog)
		F.expect(model.commands.skills.size() == 4, class_id + "四技能永不抽换", failures)
		F.expect(model.actors[1].hp == actor.hp or model.actors[0].hp == actor.hp, "HP数字直接投影", failures)
		view.select_command("attack_physical")
		view.select_target("e_1")
		var before: Dictionary = engine.snapshot()
		var original: Dictionary = view.pending_command.duplicate(true)
		var external := original.duplicate(true)
		external.command_id = "other_confirm"
		F.expect(engine.submit(external).accepted, "构造真实陈旧预览", failures)
		var advanced: Dictionary = engine.snapshot()
		view.confirm_command()
		F.expect(engine.snapshot() == advanced and not view.processing and not view.last_error.is_empty(), "陈旧确认免费拒绝并有可读错误", failures)
		view.free()
	# 冷却、全体目标、逐目标免疫均走唯一预览事件。
	var guard: Dictionary = F.actor("guard", "p_active")
	guard.stats.spd = 100
	guard.cooldown_until["shield_bash"] = 2
	var engine := Battle.new(catalog)
	engine.start({"actors": {"p_active": guard, "e_1": F.enemy("hound", "e_1")}, "inventory": {"healing_potion": 1}}, 1701)
	var view = View.new()
	view.bind(engine, null)
	view.select_command("skill", "shield_bash")
	view.select_target("e_1")
	F.expect(view.current_preview().reasons.has("技能冷却中"), "冷却原因直接来自模型", failures)
	view.cancel_command()
	view.select_command("item", "healing_potion")
	view.select_target("p_active")
	F.expect(view.current_preview().item_cost == 1, "道具预览显示真实单位库存费用", failures)
	var before: Dictionary = engine.snapshot()
	view.cancel_command()
	F.expect(engine.snapshot() == before, "取消道具不扣库存", failures)
	view.free()

static func _test_launcher_save_boundary(failures: Array[String]) -> void:
	var Launcher = load("res://scripts/rpg/ui/launcher_view.gd")
	var campaign := Campaign.new(null, Store.new(), "user://rpg_v1/ui_boundary.json")
	var router := Router.new(campaign)
	var launcher = Launcher.new()
	launcher.open({"router": router})
	F.expect(not launcher.continue_game().ok and not launcher.last_error.is_empty() and campaign.snapshot().is_empty(), "无安全档继续只显示失败，不能自动开新局", failures)
	F.expect(launcher.new_game().ok and campaign.snapshot().phase == "preparation", "只有明确New才写新局", failures)
	var old_safe: Dictionary = campaign.safe_snapshot()
	var stale_campaign := Campaign.new(null, Store.new(), "user://rpg_v1/ui_boundary.json")
	stale_campaign.load_run()
	var stale_view = Launcher.new()
	stale_view.open({"router": Router.new(stale_campaign)})
	F.expect(launcher.new_game().ok, "明确第二次新局提交", failures)
	F.expect(not stale_view.rest_party().ok and not stale_view.last_error.is_empty() and stale_campaign.safe_snapshot() == old_safe, "陈旧准备操作错误可见且不覆盖安全档", failures)
	F.expect(stale_view.continue_game().ok and stale_campaign.safe_snapshot() == campaign.safe_snapshot(), "用户可显式重新载入最新安全档", failures)
	var started: Dictionary = launcher.start_encounter()
	F.expect(started.ok, "准备按campaign下一遭遇进入", failures)
	var resume = Launcher.new()
	resume.open({"router": Router.new(Campaign.new(null, Store.new(), "user://rpg_v1/ui_boundary.json"))})
	var loaded: Dictionary = resume.continue_game()
	F.expect(loaded.ok and loaded.pending_battle and loaded.next_scene == "res://scenes/rpg/battle.tscn", "继续调用load_safe_run恢复待战，绝不新开局", failures)
	F.expect(resume.router.create_engine().snapshot() == router.create_engine().snapshot(), "继续待战是同种子/库存/资源", failures)
	launcher.free()
	stale_view.free()
	resume.free()
	Router.clear_session()

static func _test_battle_scene_ready(View, catalog, failures: Array[String]) -> void:
	var actors := {"p_swordsman": F.actor("swordsman", "p_swordsman"), "p_guard": F.actor("guard", "p_guard"), "p_healer": F.actor("healer", "p_healer"), "e_1": F.enemy("hound", "e_1")}
	var engine := Battle.new(catalog)
	engine.set_policy(Policy.new())
	engine.start({"actors": actors, "inventory": {"healing_potion": 3, "mana_potion": 1, "revival_potion": 1, "cleansing_powder": 1}}, 1701)
	var view = View.new()
	view.bind(engine, null)
	var tree: SceneTree = Engine.get_main_loop()
	tree.root.add_child(view)
	await tree.process_frame
	F.expect(view._skill_buttons[0].text.split("\n").size() <= 2, "技能卡只用两行，不挤出和纸面板", failures)
	F.expect(view._skill_buttons.size() == 4 and view._skill_buttons[0].text.contains("150%物攻"), "真实战斗ready显示四槽与预览真实伤害摘要", failures)
	F.expect(view._skill_buttons[3].text.contains("2次行动"), "技能状态时长含行动单位", failures)
	if OS.get_environment("RPG_TEST_LEGACY_CONTRACTS") == "1":
		F.expect(view._actors.e_1.sprite.get_child(0).flip_h, "历史契约：左向敌图必须镜像面向右侧我方", failures)
	else:
		F.expect(not view._actors.e_1.sprite.get_child(0).flip_h and view._config.enemy_art.hound == "res://assets/chars/enemies/current/hound.png", "正式疾行敌图原生右向，在左侧不重复镜像", failures)
	F.expect(view._actors.p_swordsman.sprite.get_child(0).flip_h, "右向凛音镜像面向左侧敌方", failures)
	F.expect(view._actors.e_1.intent.text.contains("预计伤害"), "敌方意图显示模型数字", failures)
	F.expect(view._preview_panel.size.y < 300 and view._preview_panel.size.x >= 400, "预览面板紧凑且可读", failures)
	view._skill_buttons[0].pressed.emit()
	view.select_target("e_1")
	F.expect(not view._hud.confirm.disabled, "真实目标选择启用确认按钮", failures)
	var before: Dictionary = engine.snapshot()
	view._hud.cancel.pressed.emit()
	F.expect(view.pending_command.is_empty() and engine.snapshot() == before, "真实取消按钮免费", failures)
	view._skill_buttons[0].pressed.emit()
	view.select_target("e_1")
	view._hud.confirm.pressed.emit()
	F.expect(view._skill_buttons[0].text.contains("重斩"), "结算期间四技能仍保留原行动者卡位", failures)
	view._hud.confirm.pressed.emit()
	await tree.create_timer(0.6).timeout
	F.expect(not view.processing and engine.snapshot().active_actor_id == "p_healer" and engine.snapshot().actors.p_swordsman.mp == before.actors.p_swordsman.mp - 8, "真实双击确认/动画结束后只收费一次并交给下一角色", failures)
	view.free()

static func _test_save_result_retry(View, failures: Array[String]) -> void:
	var TestCampaign = load("res://tools/rpg/test_campaign.gd")
	var failing_store = TestCampaign.FailingStore.new()
	failing_store.delegate = Store.new()
	var campaign := Campaign.new(null, failing_store, "user://rpg_v1/ui_save_retry.json")
	var ids: Array[String] = ["guard", "swordsman", "healer"]
	F.expect(campaign.new_run(ids).ok, "UI战果测试隔离开局", failures)
	var router := Router.new(campaign)
	var begun: Dictionary = campaign.begin_battle("slice_1", {})
	router.adopt_battle(begun)
	var engine = router.create_engine()
	for index in range(180):
		engine.advance()
		var state: Dictionary = engine.snapshot()
		if not state.outcome.is_empty(): break
		var actor: Dictionary = state.actors[state.active_actor_id]
		var targets: Array = []
		for target in state.actors.values():
			if target.side == "enemy" and target.hp > 0: targets.append(target)
		targets.sort_custom(func(a, b): return a.hp < b.hp if a.hp != b.hp else a.actor_id < b.actor_id)
		var command := {"command_id": "ui_result_%d" % state.revision, "expected_revision": state.revision, "actor_id": actor.actor_id, "kind": "attack_magic" if actor.class_id == "healer" else "attack_physical", "ability_id": "", "target_ids": [targets[0].actor_id]}
		if actor.class_id == "swordsman":
			var heavy := command.duplicate(true)
			heavy.kind = "skill"
			heavy.ability_id = "heavy_slash"
			if engine.preview(heavy).legal: command = heavy
		if actor.class_id == "healer":
			for id in campaign.safe_snapshot().party:
				if state.actors[id].hp > 0 and state.actors[id].hp <= state.actors[id].stats.hp - 86:
					var heal := command.duplicate(true)
					heal.kind = "skill"
					heal.ability_id = "heal"
					heal.target_ids = [id]
					if engine.preview(heal).legal: command = heal
		F.expect(engine.submit(command).accepted, "真实战果前合法输入", failures)
	F.expect(engine.snapshot().outcome == "victory", "UI存档失败回归使用真实胜利", failures)
	var view = View.new()
	view.router = router
	view.engine = engine
	view.campaign = campaign
	var before: Dictionary = campaign.safe_snapshot()
	failing_store.fail = true
	F.expect(not view.save_result().ok and not view.result_saved and not view.last_error.is_empty() and campaign.safe_snapshot() == before, "保存失败留在可重试战果，不发布奖励", failures)
	failing_store.fail = false
	F.expect(view.save_result().ok and view.result_saved and campaign.snapshot().xp == 40, "同一真实战果重试持久化一次", failures)
	F.expect(view.save_result().ok and campaign.snapshot().xp == 40, "重复交付战果不重复奖励", failures)
	view.free()

static func _test_fallen_targets(View, catalog, failures: Array[String]) -> void:
	var source: Dictionary = F.actor("healer", "p_healer")
	source.stats.spd = 100
	var fallen: Dictionary = F.actor("swordsman", "p_swordsman")
	fallen.hp = 0
	var enemy: Dictionary = F.enemy("hound", "e_dead")
	enemy.hp = 0
	var engine := Battle.new(catalog)
	engine.start({"actors": {"p_healer": source, "p_swordsman": fallen, "e_dead": enemy, "e_alive": F.enemy("hound", "e_alive")}, "inventory": {"revival_potion": 1}}, 1701)
	var view = View.new()
	view.bind(engine, null)
	view.select_command("attack_magic")
	view.select_target("e_dead")
	var before: Dictionary = engine.snapshot()
	view.confirm_command()
	F.expect(not view.current_preview().legal and engine.snapshot() == before and not view.last_error.is_empty(), "倒地敌人非法确认不改变资源或RNG", failures)
	view.cancel_command()
	view.select_command("skill", "heal")
	view.select_target("p_swordsman")
	F.expect(not view.current_preview().legal, "治疗按钮不能复活倒地目标", failures)
	view.cancel_command()
	view.select_command("item", "revival_potion")
	view.select_target("p_swordsman")
	F.expect(view.current_preview().legal and view.current_preview().item_cost == 1, "复苏药能选中灰色倒地队员", failures)
	view.confirm_command()
	F.expect(engine.snapshot().actors.p_swordsman.hp == 72 and engine.snapshot().inventory.revival_potion == 0, "复苏确认只消耗真实一次库存且显示30%HP", failures)
	view.free()

static func _test_disabled_skill_reasons(View, catalog, failures: Array[String]) -> void:
	var actor: Dictionary = F.actor("swordsman", "p_swordsman")
	actor.stats.spd = 100
	actor.mp = 0
	var engine := Battle.new(catalog)
	engine.start({"actors": {"p_swordsman": actor, "e_1": F.enemy("hound", "e_1")}, "inventory": {"healing_potion": 1}}, 1701)
	var view = View.new()
	view.bind(engine, null)
	var tree: SceneTree = Engine.get_main_loop()
	tree.root.add_child(view)
	await tree.process_frame
	F.expect(view._skill_buttons[0].disabled, "不足MP技能仍常驻但禁止实际点击提交", failures)
	F.expect(view._skill_buttons[0].text.contains("MP不足"), "禁用技能卡常显共享预览原因", failures)
	view.free()

static func _test_boss_head_visibility(View, catalog, failures: Array[String]) -> void:
	var actors := {"p_swordsman": F.actor("swordsman", "p_swordsman"), "p_guard": F.actor("guard", "p_guard"), "p_healer": F.actor("healer", "p_healer"), "e_boss": F.enemy("gatekeeper", "e_boss")}
	actors.p_guard.shield = F.shield(64, 2, "p_healer")
	var engine := Battle.new(catalog)
	engine.set_policy(Policy.new())
	engine.start({"actors": actors, "inventory": {"healing_potion": 3}}, 1701)
	var view = View.new()
	view.bind(engine, null)
	var tree: SceneTree = Engine.get_main_loop()
	tree.root.add_child(view)
	await tree.process_frame
	F.expect(view._actors.p_guard.status.text.contains("2次行动"), "护盾持续必须明确标行动单位", failures)
	var w: Dictionary = view._actors.e_boss
	var body := Rect2(w.sprite.position - Vector2(120, 365), Vector2(240, 365))
	F.expect(not w.card.get_rect().intersects(body), "Boss资料面板不能遮住棺守面具", failures)
	var before: Dictionary = engine.snapshot()
	var original_x: float = w.sprite.position.x
	view._play_action("e_boss", ["p_guard"])
	F.expect(w.sprite.get_meta("facing_right") and w.sprite.get_meta("action_tween").is_running() and engine.snapshot() == before, "静图敌人动作面向真实右侧目标，纯表现不改模型", failures)
	F.expect(w.sprite.get_meta("foot_point").x == original_x, "动作保留固定脚点契约", failures)
	view.bind(engine, null)
	F.expect(view._actors.size() == 4 and is_instance_valid(view._actors.p_guard.hp) and view._actors.p_guard.hp.text.contains("320"), "重试式重绑定安全重建父子控件", failures)
	F.expect(view._actors.p_guard.status is RichTextLabel and view._actors.p_guard.status.scroll_active and view._actors.p_guard.card.get_rect().size.y > view._actors.p_guard.status.position.y + view._actors.p_guard.status.size.y, "多状态文本有界可滚动不越出队员卡", failures)
	view.free()

static func _test_independent_mode_return(failures: Array[String]) -> void:
	var Launcher = load("res://scripts/rpg/ui/launcher_view.gd")
	var regular := Campaign.new(null, Store.new(), "user://rpg_v1/ui_regular_mode.json")
	var regular_router := Router.new(regular)
	var launcher = Launcher.new()
	launcher.open({"router": regular_router})
	F.expect(launcher.new_game().ok, "独立模式隔离回归先创建常规局", failures)
	var original: Dictionary = regular.safe_snapshot()
	F.expect(launcher.new_game(true).ok and regular.safe_snapshot() == original, "独立Boss不动常规局", failures)
	var independent: Dictionary = launcher.campaign.safe_snapshot()
	F.expect(launcher.new_game(false).ok and launcher.router == regular_router, "明确新开连战回到常规槽", failures)
	var store := Store.new()
	F.expect(store.load_safe("user://rpg_v1/ui_regular_mode.json").snapshot.run_id != original.run_id, "常规新局写自己的槽", failures)
	F.expect(store.load_safe("user://rpg_v1/slot_boss_test.json").snapshot.run_id == independent.run_id, "回到连战不能覆盖独立测试槽", failures)
	launcher.free()
	Router.clear_session()

# 自动集合只能由共享预览决定；点人物不能把全体输入改成子集。
static func _test_automatic_target_clicks(View, catalog, failures: Array[String]) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	for row in [["swordsman", "sweep", 12, ["e_1", "e_2"]], ["healer", "group_heal", 22, ["p_guard", "p_healer", "p_swordsman"]]]:
		var actors := {"p_guard": F.actor("guard", "p_guard"), "p_swordsman": F.actor("swordsman", "p_swordsman"), "p_healer": F.actor("healer", "p_healer"), "e_1": F.enemy("hound", "e_1"), "e_2": F.enemy("shield_soldier", "e_2")}
		var source_id: String = "p_" + row[0]
		actors[source_id].stats.spd = 100
		for id in ["p_guard", "p_healer", "p_swordsman"]: actors[id].hp -= 40
		var engine := Battle.new(catalog)
		engine.start({"actors": actors, "inventory": {"healing_potion": 3}}, 1701)
		var view = View.new()
		view.bind(engine, null)
		tree.root.add_child(view)
		await tree.process_frame
		var before: Dictionary = engine.snapshot()
		view.select_command("skill", row[1])
		F.expect(view.current_preview().legal and view.current_preview().effective_target_ids == row[3], row[1] + "空输入由模型选完整集合", failures)
		for id in row[3]:
			view._actors[id].target.pressed.emit()
			F.expect(view.pending_command.target_ids.is_empty() and view.current_preview().legal and view.current_preview().effective_target_ids == row[3], row[1] + "点人物不覆写自动集合：" + id, failures)
		F.expect(view._hud.prompt.text.contains("全体目标已选，可直接确认") and not view._hud.confirm.disabled, row[1] + "准确提示与确认可用", failures)
		view._hud.cancel.pressed.emit()
		F.expect(engine.snapshot() == before and view.pending_command.is_empty(), row[1] + "取消不收费不改RNG", failures)
		view.select_command("skill", "heavy_slash" if row[0] == "swordsman" else "heal")
		var single_id: String = "e_2" if row[0] == "swordsman" else "p_guard"
		view.select_target(single_id)
		F.expect(view.pending_command.target_ids == [single_id] and view.current_preview().legal, row[1] + "切单体仍可选对象", failures)
		view.select_command("skill", row[1])
		view.select_target(row[3][0])
		var expected: Dictionary = view.current_preview()
		view._hud.confirm.pressed.emit()
		view._hud.confirm.pressed.emit()
		var after: Dictionary = engine.snapshot()
		F.expect(after.command_log.size() == 1 and after.actors[source_id].mp == before.actors[source_id].mp - row[2], row[1] + "重选双确认仅一次费用与指令", failures)
		var affected: Array[String] = []
		for event in expected.effects:
			if event.type in ["damage", "healed"] and not affected.has(event.target_id): affected.append(event.target_id)
		affected.sort()
		F.expect(affected == row[3], row[1] + "逐目标真实效果覆盖完整集合", failures)
		for id in row[3]:
			F.expect(after.actors[id].hp < before.actors[id].hp if row[0] == "swordsman" else after.actors[id].hp > before.actors[id].hp, row[1] + "确认改变每个目标真实HP：" + id, failures)
		await tree.create_timer(0.6).timeout
		view.free()

static func _test_single_target_auto_select(View, catalog, failures: Array[String]) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	# 单场只剩一个敌人：选技能即预填唯一目标，一步确认即可出手。
	var actors := {"p_guard": F.actor("guard", "p_guard"), "p_swordsman": F.actor("swordsman", "p_swordsman"), "e_1": F.enemy("hound", "e_1")}
	actors.p_swordsman.stats.spd = 100
	var engine := Battle.new(catalog)
	engine.start({"actors": actors, "inventory": {"healing_potion": 3}}, 1701)
	var view = View.new()
	view.bind(engine, null)
	tree.root.add_child(view)
	await tree.process_frame
	view.select_command("attack_physical")
	F.expect(view.pending_command.target_ids == ["e_1"], "单敌普攻自动选中唯一目标", failures)
	F.expect(view.current_preview().legal, "自动选中后预览直接合法", failures)
	F.expect(view._hud.prompt.text.contains("唯一目标已自动选中，可直接确认"), "单敌自动选中提示", failures)
	F.expect(not view._hud.confirm.disabled, "单敌自动选中后确认可用", failures)
	view._hud.confirm.pressed.emit()
	F.expect(engine.snapshot().command_log.size() == 1, "单敌免点选直接确认执行", failures)
	# 多目标时保持手动点选，不预填。
	var multi := {"p_guard": F.actor("guard", "p_guard"), "p_swordsman": F.actor("swordsman", "p_swordsman"), "e_1": F.enemy("hound", "e_1"), "e_2": F.enemy("cultist", "e_2")}
	multi.p_swordsman.stats.spd = 100
	var engine2 := Battle.new(catalog)
	engine2.start({"actors": multi, "inventory": {}}, 1701)
	var view2 = View.new()
	view2.bind(engine2, null)
	tree.root.add_child(view2)
	await tree.process_frame
	view2.select_command("attack_physical")
	F.expect(view2.pending_command.target_ids.is_empty(), "多敌不自动选中，保持手动点选", failures)
	view2.free()
	view.free()

static func _intent_text(Presenter, state: Dictionary, catalog, id: String) -> String:
	for actor in Presenter.present(state, catalog).actors:
		if actor.actor_id == id: return actor.intent.get("text", "")
	return ""

static func _test_intent_details(Presenter, catalog, failures: Array[String]) -> void:
	var actors := {"p_guard": F.actor("guard", "p_guard"), "p_swordsman": F.actor("swordsman", "p_swordsman"), "p_healer": F.actor("healer", "p_healer"), "e_cultist": F.enemy("cultist", "e_cultist")}
	var engine := Battle.new(catalog)
	engine.set_policy(Policy.new())
	engine.start({"actors": actors, "inventory": {}}, 1701)
	engine.advance()
	var before: Dictionary = engine.snapshot()
	var text := _intent_text(Presenter, before, catalog, "e_cultist")
	F.expect(text.contains("魔法") and text.contains("灵属性") and text.contains("虚弱") and text.contains("2次行动") and text.contains("预计伤害"), "虚咒意图公开类型元素状态时钟及数字", failures)
	F.expect(engine.snapshot() == before, "意图详细投影只读不改模型", failures)
	actors.erase("e_cultist")
	actors["e_boss"] = F.enemy("gatekeeper", "e_boss")
	engine = Battle.new(catalog)
	engine.set_policy(Policy.new())
	var begun: Dictionary = engine.start({"actors": actors, "inventory": {}}, 1701)
	F.expect(begun.started, "意图Boss初始化：" + str(begun.reasons), failures)
	if not begun.started: return
	var checked := {"waiting": false, "cancelled": false, "pulse_prepare": false, "pulse_wait": false, "pulse_release": false}
	for index in range(100):
		engine.advance()
		var state: Dictionary = engine.snapshot()
		if not state.outcome.is_empty(): break
		var boss: Dictionary = state.actors.e_boss
		text = _intent_text(Presenter, state, catalog, "e_boss")
		var effects: Array = boss.intent.preview.get("effects", [])
		var types: Array = effects.map(func(event): return event.type)
		if boss.boss.step == 3 and types.has("charge_wait") and not checked.waiting:
			F.expect(text.contains("继续蓄力") and text.contains("等待反应机会") and text.contains("可打断") and not text.contains("预计伤害"), "未获反应机会不伪造伤害并解释等待", failures)
			checked.waiting = true
		if boss.boss.step == 5 and not checked.pulse_prepare:
			F.expect(text.contains("不可打断，建议防御") and text.contains("魔法") and text.contains("灵属性") and text.contains("灼烧") and text.contains("2次行动"), "脉冲准备公开承诺释放类型状态及保护", failures)
			checked.pulse_prepare = true
		if boss.boss.step == 6 and types.has("charge_wait") and not checked.pulse_wait:
			F.expect(text.contains("不可打断，建议防御") and text.contains("等待反应机会") and text.contains("灼烧") and text.contains("2次行动") and not text.contains("预计伤害"), "脉冲继续蓄力保留明确保护和预计状态", failures)
			checked.pulse_wait = true
		if boss.boss.step == 6 and not boss.intent.preview.damage_ranges.is_empty() and not checked.pulse_release:
			F.expect(text.contains("不可打断，建议防御") and text.contains("魔法") and text.contains("灵属性") and text.contains("灼烧") and text.contains("2次行动") and text.contains("预计伤害"), "脉冲释放显示真实逐目标数值状态与保护", failures)
			checked.pulse_release = true
		var command := {"command_id": "intent_%d" % state.revision, "expected_revision": state.revision, "actor_id": state.active_actor_id, "kind": "defend", "ability_id": "", "target_ids": []}
		if boss.boss.step == 3 and boss.boss.charge_valid and state.active_actor_id == "p_guard":
			command.kind = "skill"
			command.ability_id = "shield_bash"
			command.target_ids = ["e_boss"]
		var response: Dictionary = engine.submit(command)
		F.expect(response.accepted, "意图测试使用实际合法指令", failures)
		if command.ability_id == "shield_bash":
			text = _intent_text(Presenter, engine.snapshot(), catalog, "e_boss")
			F.expect(text.contains("释放取消") and not text.contains("不可打断") and not text.contains("可打断") and not text.contains("预计伤害"), "已打断穿刺锁定目标不误报保护或伤害", failures)
			checked.cancelled = true
		if checked.values().all(func(value): return value): break
	F.expect(checked.values().all(func(value): return value), "意图回归真实遍历准备等待释放与取消", failures)

static func _test_intent_label_bounds(View, catalog, failures: Array[String]) -> void:
	var actors := {"p_guard": F.actor("guard", "p_guard"), "p_swordsman": F.actor("swordsman", "p_swordsman"), "p_healer": F.actor("healer", "p_healer"), "e_1": F.enemy("hound", "e_1"), "e_cultist": F.enemy("cultist", "e_cultist")}
	var engine := Battle.new(catalog)
	engine.set_policy(Policy.new())
	engine.start({"actors": actors, "inventory": {}}, 1701)
	var view = View.new()
	view.bind(engine, null)
	var tree: SceneTree = Engine.get_main_loop()
	tree.root.add_child(view)
	await tree.process_frame
	var intent: Label = view._actors.e_cultist.intent
	F.expect(intent.text.contains("虚弱") and intent.text.contains("2次行动") and intent.tooltip_text == intent.text, "真实意图控件显示完整文字并提供同文tooltip", failures)
	F.expect(intent.get_rect().end.y <= 744 and intent.get_line_count() * Kit.font.get_height(intent.get_theme_font_size("font_size")) <= intent.size.y, "四行虚咒意图在操作板上方完整可读：" + str(intent.get_rect()) + " 行数" + str(intent.get_line_count()) + " 行高" + str(Kit.font.get_height(intent.get_theme_font_size("font_size"))), failures)
	view.free()


# 四敌必须独立可读，不能沿用双敌宽面板互相覆盖。
static func _test_four_enemy_layout(View, catalog, failures: Array[String]) -> void:
	for near_side in ["right", "left"]:
		var actors := {"p_ranger": F.actor("ranger", "p_ranger"), "p_mage": F.actor("mage", "p_mage"), "p_controller": F.actor("controller", "p_controller")}
		var enemy_ids := ["hound", "cultist", "fire_spirit", "elite_shield_soldier"]
		for index in range(4):
			var id := "e_%02d_%s" % [index + 1, enemy_ids[index]]
			actors[id] = F.enemy(enemy_ids[index], id)
		var engine := Battle.new(catalog)
		engine.set_policy(Policy.new())
		engine.start({"actors": actors, "inventory": {}}, 11)
		var view = View.new()
		view._config.near_side = near_side
		view.bind(engine, null)
		var tree: SceneTree = Engine.get_main_loop()
		tree.root.add_child(view)
		await tree.process_frame
		var cards: Array[Rect2] = []
		var intents: Array[Rect2] = []
		for id in actors:
			if actors[id].side != "enemy": continue
			var widgets: Dictionary = view._actors[id]
			var card: Rect2 = widgets.card.get_rect()
			var intent: Label = widgets.intent
			for previous in cards: F.expect(not card.intersects(previous), near_side + "四敌卡不重叠：" + id, failures)
			for previous in intents: F.expect(not intent.get_rect().intersects(previous), near_side + "四敌意图不重叠：" + id, failures)
			cards.append(card)
			intents.append(intent.get_rect())
			F.expect(intent.get_rect().end.y <= 744 and intent.get_line_count() * Kit.font.get_height(intent.get_theme_font_size("font_size")) <= intent.size.y, near_side + "四敌完整意图不压操作板：" + id, failures)
			F.expect(Rect2(0, 154, 1920, 590).encloses(card), "四敌卡留在安全显示区", failures)
		F.expect(view._hud.prompt.get_rect().end.y <= 744, "四敌操作提示不压和纸装饰边框", failures)
		for rect in intents: F.expect(not view._hud.prompt.get_rect().intersects(rect), "四敌提示与意图区分离", failures)
		var queue: Label = view._hud.queue
		F.expect(queue.get_line_count() * Kit.font.get_height(queue.get_theme_font_size("font_size")) <= 90, "七人轮序不溢出顶部栏", failures)
		var defeated_state: Dictionary = engine.snapshot()
		defeated_state.actors.e_04_elite_shield_soldier.hp = 0
		engine.restore(defeated_state)
		view._render()
		await tree.process_frame
		var title: Label = view._actors.e_04_elite_shield_soldier.title
		F.expect(title.get_rect().end.x <= 204 and Kit.font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title.get_theme_font_size("font_size")).x <= 194, "四敌长名称加倒地不挤出独立卡片", failures)
		view.free()
