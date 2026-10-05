# 探索战外菜单：真实两战合法指令、实际场景按钮与隔离写失败回归。
extends RefCounted
const F = preload("res://tools/rpg/fixtures.gd")
const Campaign = preload("res://scripts/rpg/campaign.gd")
const Router = preload("res://scripts/rpg/encounter_router.gd")
const Store = preload("res://scripts/rpg/save_store.gd")
const Policies = preload("res://tools/rpg/strategy_policies.gd")
const Enemy = preload("res://scripts/rpg/enemy_policy.gd")
const TestCampaign = preload("res://tools/rpg/test_campaign.gd")
const Launcher = preload("res://scripts/rpg/ui/launcher_view.gd")

static func _world(path: String) -> Dictionary:
	return {"scene_path": path, "player_x": 735.5, "facing": -1, "resolved": {}, "dlg_fired": {"200": true, "900": true, "1400": true}, "exit_prompted": false, "spirit": 3, "party_index": 1}

static func _fight(router, world: Dictionary, clue: String, failures: Array[String]) -> Dictionary:
	var start: Dictionary = router.begin(world.scene_path, "res://scenes/v3/battle.tscn", world, clue)
	F.expect(start.ok, "探索两战使用正式Router进战", failures)
	if not start.ok: return {}
	var engine = router.create_engine()
	var strategy := Policies.new(router._catalog)
	var enemy := Enemy.new()
	for index in range(400):
		engine.advance(false)
		var state: Dictionary = engine.snapshot()
		if not state.outcome.is_empty(): break
		var command: Dictionary = strategy.choose("direct_damage", state, engine) if state.actors[state.active_actor_id].side == "player" else enemy.choose_command(state, router._catalog)
		var accepted: bool = engine.submit(command).accepted
		F.expect(accepted, "探索两战每条命令均经真实引擎接受", failures)
		if not accepted: return {}
	F.expect(engine.snapshot().outcome == "victory", "探索链真实引擎胜利，无资源/终局注入", failures)
	var finished: Dictionary = router.finish(router.result_from_engine())
	F.expect(finished.ok, "探索链胜利原子提交", failures)
	return finished

static func _button(node: Node) -> Button:
	return node.find_child("RpgPreparation", true, false) as Button

static func _settle(tree: SceneTree) -> void:
	await tree.process_frame
	await tree.process_frame

static func run(failures: Array[String], catalog) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var store := TestCampaign.FailingStore.new()
	store.delegate = Store.new(catalog)
	var campaign := Campaign.new(catalog, store, "user://rpg_v1/exploration_ui.json")
	var classes: Array[String] = ["guard", "swordsman", "healer"]
	F.expect(campaign.new_run(classes).ok, "探索UI隔离新局", failures)
	var router := Router.new(campaign, catalog)
	Router.activate(router)
	var first := _fight(router, _world("res://scenes/v3/stage.tscn"), "basin_reflection", failures)
	if first.is_empty(): return
	var launcher := Launcher.new()
	tree.root.add_child(launcher)
	await _settle(tree)
	F.expect(campaign.snapshot().phase == "exploration", "首战后是真实探索态", failures)
	F.expect(not launcher._hud.items.disabled, "首战后真实战外道具按钮应开放", failures)
	F.expect(launcher._hud.rest.disabled, "首战后休息继续锁定", failures)
	launcher.open_roster()
	F.expect(launcher._hud.party_apply.disabled and launcher._equipment_buttons.armor.disabled and launcher._hud.branch_apply.disabled, "首战后编队装备分支不随道具解锁", failures)
	launcher._roster_panel.hide()
	if not launcher._hud.items.disabled:
		launcher._hud.items.pressed.emit()
		F.expect(launcher._hud.item_panel.visible, "真实按钮打开战外道具", failures)
		launcher._hud.outside_healing_potion.pressed.emit()
		var before := campaign.snapshot()
		store.fail = true
		launcher._cards[0].button.pressed.emit()
		F.expect(campaign.snapshot() == before and not launcher.last_error.is_empty(), "战外药写失败无库存/资源/world变化", failures)
		store.fail = false
		launcher._cards[0].button.pressed.emit()
		var after := campaign.snapshot()
		F.expect(after.roster.p_guard.hp == mini(before.roster.p_guard.hp + 80, before.roster.p_guard.stats.hp) and after.inventory.healing_potion == before.inventory.healing_potion - 1, "重试同一真实道具目标准确恢复80HP并消费1", failures)
		F.expect(after.world == before.world, "用药不改变探索世界", failures)
		launcher._hud.items.pressed.emit()
		launcher._hud.outside_mana_potion.pressed.emit()
		before = campaign.snapshot()
		launcher._cards[1].button.pressed.emit()
		after = campaign.snapshot()
		F.expect(after.roster.p_swordsman.mp == mini(before.roster.p_swordsman.mp + 20, before.roster.p_swordsman.stats.mp) and after.inventory.mana_potion == before.inventory.mana_potion - 1, "真实道具按钮准确恢复20MP并消费1", failures)
	launcher.free()
	var second := _fight(router, _world("res://scenes/v3/stage_corridor.tscn"), "bell_self_ring", failures)
	if second.is_empty(): return
	F.expect(campaign.snapshot().phase == "rest", "第二战到达明确休息点", failures)
	F.expect(tree.change_scene_to_file(second.next_scene) == OK, "胜利回到真实回廊", failures)
	await _settle(tree)
	var stage = tree.current_scene
	var menu := _button(stage)
	F.expect(menu != null and not menu.disabled and menu.text.contains("休息"), "回廊有明确可操作RPG休息准备入口", failures)
	if menu != null:
		var world: Dictionary = stage.export_rpg_world()
		var before := campaign.snapshot()
		stage._dlg_playing = true
		menu.pressed.emit()
		F.expect(tree.current_scene == stage and campaign.snapshot() == before, "对话期间不能由菜单绕过故事", failures)
		stage._dlg_playing = false
		store.fail = true
		menu.pressed.emit()
		F.expect(tree.current_scene == stage and campaign.snapshot() == before and stage.export_rpg_world() == world, "进入菜单写失败留原场景且世界/资源不变", failures)
		for child in stage.get_children():
			if child is AcceptDialog: child.queue_free()
		store.fail = false
		menu.pressed.emit()
		await _settle(tree)
		launcher = tree.current_scene
		F.expect(launcher is Launcher, "准备入口到真实launcher", failures)
		if launcher is Launcher:
			F.expect(campaign.snapshot().world == world and campaign.snapshot().roster == before.roster and campaign.snapshot().inventory == before.inventory, "打开准备保存完整世界但不自动恢复/补药", failures)
			F.expect(not launcher._hud.rest.disabled and not launcher._hud.explore.disabled and launcher._hud.next.disabled, "休息/返回探索可达且直接下一战禁止跳剧情", failures)
			F.expect(not launcher.start_encounter("slice_boss").ok and campaign.snapshot().pending_battle.is_empty(), "探索准备页API也拒绝绕过仪式直接Boss", failures)
			launcher.open_roster()
			F.expect(not launcher._hud.party_apply.disabled and not launcher._equipment_buttons.armor.disabled, "休息点编队换装真实控件开放", failures)
			launcher._roster_panel.hide()
			before = campaign.snapshot()
			store.fail = true
			launcher._hud.rest.pressed.emit()
			F.expect(campaign.snapshot() == before and not launcher.last_error.is_empty(), "休息写失败原资源/world不变可重试", failures)
			store.fail = false
			launcher._hud.rest.pressed.emit()
			var rested := campaign.snapshot()
			for actor in rested.roster.values(): F.expect(actor.hp == actor.stats.hp and actor.mp == actor.stats.mp, "显式休息恢复全部六人HPMP", failures)
			F.expect(rested.inventory == before.inventory and rested.world == world, "休息不补药且世界不变", failures)
			launcher._hud.explore.pressed.emit()
			await _settle(tree)
			stage = tree.current_scene
			F.expect(stage.export_rpg_world() == world, "准备返回保留场景位置朝向线索对话仪式前置", failures)
			# 原仪式路线仍由真实舞台触发与原取消回调返回。
			stage._rpg_pending_clue = "coffin_sendoff"
			stage._go_battle("res://scenes/v3/ritual.tscn")
			await _settle(tree)
			F.expect(router.ritual_active("res://scenes/v3/ritual.tscn"), "原仪式仍可正式进入", failures)
			var locked := Launcher.new()
			tree.root.add_child(locked)
			await _settle(tree)
			F.expect(locked._hud.items.disabled and locked._hud.rest.disabled, "仪式时道具与休息仍锁定", failures)
			var ritual_before := campaign.snapshot()
			locked._toggle_items()
			locked._choose_item("healing_potion")
			F.expect(not locked._hud.item_panel.visible and locked._pending_item.is_empty() and not locked.use_item("healing_potion", "p_guard").ok and campaign.snapshot() == ritual_before, "陈旧UI事件不能绕过仪式锁", failures)
			locked.free()
			tree.current_scene._return_to_exploration()
			await tree.create_timer(1.5).timeout
			stage = tree.current_scene
			world = stage.export_rpg_world()
			F.expect(world.resolved.get("bell_self_ring", false) and world.resolved.get("coffin_sendoff", false), "仪式返场保留两线索", failures)
			F.expect(_button(stage) != null, "仪式回廊仍有准备入口", failures)
			# 原标题清session，真实Continue恢复后入口不能消失。
			tree.change_scene_to_file("res://scenes/v3/title.tscn")
			await _settle(tree)
			F.expect(not Router.enabled(), "原标题清除RPG会话", failures)
			F.expect(_button(tree.current_scene) == null, "旧标题背景不出现RPG准备菜单", failures)
			tree.change_scene_to_file("res://scenes/rpg/launcher.tscn")
			await _settle(tree)
			# 此夹具使用专用安全槽，Continue仍走正式load_safe_run。
			tree.current_scene.open({"router": Router.new(Campaign.new(catalog, Store.new(catalog), "user://rpg_v1/exploration_ui.json"), catalog)})
			F.expect(tree.current_scene.continue_game().ok, "原标题后正式Continue成功", failures)
			await _settle(tree)
			stage = tree.current_scene
			F.expect(stage.export_rpg_world() == world and _button(stage) != null, "Continue保留原世界且准备入口可达", failures)
			F.expect(stage._all_clues_resolved(), "回廊原有出口前置不变", failures)
			if OS.get_environment("RPG_TEST_LEGACY_CONTRACTS") == "1":
				# 保存原复现断言；正式全篇顺序由campaign场景/状态与真实引擎E2E覆盖。
				tree.change_scene_to_file(stage._cfg.next)
				await _settle(tree)
				tree.current_scene._rpg_pending_clue = "hollow_coffin_glow"
				tree.current_scene._go_battle("res://scenes/v3/battle_honden.tscn")
				await _settle(tree)
				F.expect(tree.current_scene.scene_file_path == "res://scenes/rpg/battle.tscn" and Router.session.campaign.safe_snapshot().pending_battle.encounter_id == "slice_boss", "历史契约：保留原仪式/本殿顺序进入Boss", failures)
			else:
				F.expect(stage._cfg.next == "res://scenes/v3/stage_night3.tscn" and Router.session.campaign.safe_snapshot().pending_battle.is_empty(), "兼容回廊不再跳过第三、四夜直接Boss；正式五战由campaign E2E验收", failures)
	if tree.current_scene != null:
		tree.current_scene.free()
		tree.current_scene = null
	Router.clear_session()
	# 同一真实旧舞台没有新增RPG入口。
	var legacy = load("res://scenes/v3/stage_corridor.tscn").instantiate()
	tree.root.add_child(legacy)
	await _settle(tree)
	F.expect(_button(legacy) == null, "旧模式回廊不出现RPG准备菜单", failures)
	legacy.free()

# 存活/倒地资源边界用明确隔离夹具；不冒充上述真实引擎通关。
static func test_item_boundaries(failures: Array[String], catalog) -> void:
	var tree: SceneTree = Engine.get_main_loop()
	var path := "user://rpg_v1/item_ui_boundaries.json"
	var campaign := Campaign.new(catalog, Store.new(catalog), path)
	var classes: Array[String] = ["guard", "swordsman", "healer"]
	campaign.new_run(classes)
	var fixture := campaign.snapshot()
	fixture.phase = "exploration"
	fixture.roster.p_guard.hp = 100
	fixture.roster.p_swordsman.hp = 0
	fixture.roster.p_swordsman.mp = 13
	fixture.roster.p_healer.mp = 10
	F.expect(Store.new(catalog).write_safe(fixture, path) == OK and campaign.load_run().ok, "战外道具UI资源夹具合法落盘", failures)
	var router := Router.new(campaign, catalog)
	Router.activate(router)
	var launcher := Launcher.new()
	tree.root.add_child(launcher)
	await _settle(tree)
	for case in [["healing_potion", 1], ["revival_potion", 0], ["cleansing_powder", 0]]:
		var before := campaign.snapshot()
		launcher._hud.items.pressed.emit()
		launcher._hud["outside_" + case[0]].pressed.emit()
		launcher._cards[case[1]].button.pressed.emit()
		F.expect(campaign.snapshot() == before and not launcher.last_error.is_empty(), "错误存活状态或无效净化不耗资源：" + case[0], failures)
	launcher._hud.items.pressed.emit()
	launcher._hud.outside_revival_potion.pressed.emit()
	launcher._cards[1].button.pressed.emit()
	F.expect(campaign.snapshot().roster.p_swordsman.hp == 72 and campaign.snapshot().roster.p_swordsman.mp == 13 and campaign.snapshot().inventory.revival_potion == 0, "真实UI复苏30%HP保留MP只耗1瓶", failures)
	var before := campaign.snapshot()
	launcher._hud.items.pressed.emit()
	launcher._hud.outside_revival_potion.pressed.emit()
	launcher._cards[1].button.pressed.emit()
	F.expect(campaign.snapshot() == before, "库存0点击不产生额外修改", failures)
	# 选药以后进战，旧按钮事件与重新载入的待战档都不得用药。
	launcher._choose_item("healing_potion")
	var started: Dictionary = campaign.begin_battle("slice_1", {})
	F.expect(started.ok, "道具锁定夹具正式进战", failures)
	launcher._render()
	for mode in ["battle", "pending", "defeat"]:
		if mode == "pending": campaign.load_run()
		if mode == "defeat":
			campaign.retry_battle()
			var defeat: Dictionary = TestCampaign._victory(campaign, started)
			defeat.outcome = "defeat"
			defeat.xp = 0
			for actor in defeat.roster: actor.hp = 0
			F.expect(campaign.apply_result(defeat).ok, "明确败北资源夹具", failures)
		launcher._render()
		before = campaign.snapshot()
		launcher._toggle_items()
		launcher._choose_item("healing_potion")
		F.expect(launcher._hud.items.disabled and launcher._hud.rest.disabled and not launcher._hud.item_panel.visible and launcher._pending_item.is_empty(), "战斗/待战/败北UI均拒绝旧道具操作：" + mode, failures)
		F.expect(not launcher.use_item("healing_potion", "p_guard").ok and not router.open_preparation(_world("res://scenes/v3/stage.tscn")).ok and not router.resume_exploration().ok and campaign.snapshot() == before, "锁定态模型与路由同源拒绝且无修改：" + mode, failures)
	launcher.free()
	Router.clear_session()
