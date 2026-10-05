# 六身份七形态与最终敌图的真实加载验收；必须先验证隔离user目录。
extends SceneTree
const Bundle = preload("res://scripts/characters/party_asset_bundle.gd")
const Portraits = preload("res://scripts/characters/identity_portraits.gd")
var failures: Array[String] = []
var assertions := 0
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1":
		printerr("FAIL: 请先执行隔离预检")
		quit(1)
		return
	_run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
func _run() -> void:
	check(Bundle.MANIFESTS.size() == 7, "七份正式高清形态清单登记")
	var bundle := Bundle.new()
	var first := {"p_swordsman": {"identity_id": "rinne", "form_id": "rinne"}, "p_ranger": {"identity_id": "mint", "form_id": "mint"}, "p_guard": {"identity_id": "guard", "form_id": "guard"}}
	var result: Dictionary = await bundle.prepare(first)
	check(result.ok, "默认三人可加载")
	check(bundle._definitions.size() == 3, "只强持有所选三人的形态")
	var second := {"p_mage": {"identity_id": "homura", "form_id": "mage"}, "p_healer": {"identity_id": "healer", "form_id": "healer"}, "p_controller": {"identity_id": "controller", "form_id": "controller"}}
	result = await bundle.prepare(second)
	check(result.ok, "焰华/医者/司符者三人可选加载")
	if result.ok:
		check(bundle._definitions.size() == 4, "所选含焰华只多持有其第二形态，不加载未选身份")
		for actor_id in second:
			var binding: Dictionary = second[actor_id]
			var definition: Dictionary = bundle.call("get_definition", binding.identity_id, binding.form_id)
			check(definition.get("manifest", {}).get("identity_id") == binding.identity_id, "六身份没有复用凛音或薄荷：" + actor_id)
			check(Portraits.from_definition(definition, binding.identity_id, "avatar").ok, "高清真实头像：" + actor_id)
		second.p_mage.form_id = "sword"
		result = await bundle.prepare(second)
		check(result.ok and bundle._bindings.size() == 3, "焰华剑形态仍是同一p_mage")
		var sword: Dictionary = bundle.call("get_definition", "homura", "sword")
		check(sword.get("manifest", {}).get("form_id") == "sword", "按实际清单载入剑形态")
		check(Portraits.from_definition(sword, "homura", "avatar").ok, "剑形态头像来自剑形态")
		check(bundle.call("get_definition", "homura", "mage").get("manifest", {}).get("form_id") == "mage", "焰华另一形态预载，战内即时切换无需重新解码")
	for invalid in [{"identity_id": "homura", "form_id": ""}, {"identity_id": "healer", "form_id": ""}, {"identity_id": "homura_mage", "form_id": ""}]:
		check(not (await bundle.prepare({"p_mage": invalid})).ok, "严格拒绝空形态与伪第七身份：" + str(invalid))
	bundle.clear()
	check(bundle._definitions.is_empty(), "关闭释放资源")
	var cancellation := {"done": false, "result": {}}
	_prepare_cancel(bundle, first, cancellation)
	bundle.clear()
	await process_frame
	check(cancellation.done and cancellation.result.get("cancelled", false) and bundle._definitions.is_empty(), "异步取消后旧加载不得发布")
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rpg/presentation.json"))
	for id in ["hound", "shield_soldier", "cultist", "fire_spirit", "elite_shield_soldier", "gatekeeper"]:
		var path: String = config.enemy_art.get(id, "")
		check(path == "res://assets/chars/enemies/current/%s.png" % id and FileAccess.file_exists(path), "六张最终敌图按ID独立接入：" + id)
		check(config.asset_facings.get(path) == "right", "最终敌图原生右向：" + id)
		check(config.get("enemy_geometry", {}).has(id), "静态敌图脚点与内容高登记：" + id)
	check(config.get("night_backgrounds", {}).get("1", "") == "res://assets/bg/approach_battle.png", "首夜显式新参道背景")
	check(FileAccess.file_exists("res://scripts/campaign/party_panel.gd"), "正式六选三整备panel接口")
	var view_source := FileAccess.get_file_as_string("res://scripts/rpg/ui/battle_view.gd")
	check(view_source.contains("chapter_session.gd"), "正式ChapterSession驱动高清战斗")
	await _test_session_panel()
	if not OS.get_environment("CAMPAIGN_PRESENTATION_OUTPUT").is_empty(): await _capture_lineups()
	for failure in failures: printerr("ASSERT FAIL: ", failure)
	print("CAMPAIGN PRESENTATION: ", assertions, " assertions, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
func _prepare_cancel(bundle: RefCounted, bindings: Dictionary, output: Dictionary) -> void:
	output.result = await bundle.prepare(bindings)
	output.done = true

func _test_session_panel() -> void:
	var Session = load("res://scripts/campaign/chapter_session.gd")
	var Panel = load("res://scripts/campaign/party_panel.gd")
	var View = load("res://scripts/rpg/ui/battle_view.gd")
	if Session == null or Panel == null or View == null:
		check(false, "正式会话/整备/战斗真实脚本可加载")
		return
	var session: RefCounted = Session.new()
	var started: Dictionary = session.start_new(true)
	check(started.ok, "正式整备测试从隔离正式新档开始")
	if not started.ok: return
	check(session.campaign.safe_snapshot().roster.size() == 6, "正式六身份完整名单，没有第七actor")
	check((await session.prepare_assets()).ok, "正式session加载当前三人")
	var panel = Panel.new()
	root.add_child(panel)
	panel.open(session)
	check(panel._rows.size() == 6 and panel._items.size() == 4 and panel._equipment.size() == 3 and panel._branches.size() == 3 and panel._skills.size() == 4, "整备保留六人/道具/装备/技能分支入口")
	var safe: Dictionary = session.campaign.safe_snapshot()
	panel.draft_party.assign(["p_mage", "p_mage", "p_healer"])
	check(not (await panel.apply_party()).ok and session.campaign.safe_snapshot() == safe, "整备拒绝重复身份且不写档")
	panel.draft_party.assign(["p_mage", "p_healer"])
	check(not (await panel.apply_party()).ok and session.campaign.safe_snapshot() == safe, "整备拒绝少于三人且不写档")
	panel.draft_party.assign(["p_mage", "p_healer", "p_controller"])
	check((await panel.apply_party()).ok and session.campaign.safe_snapshot().party == panel.draft_party and session.bundle._definitions.size() == 4, "真实六选三含焰华时保存并预载双形态")
	panel.select_actor("p_mage")
	var mage: Dictionary = session.campaign.safe_snapshot().roster.p_mage.duplicate(true)
	check(not (await panel.toggle_form()).ok, "首夜整备法师尚未解锁，不能提前切换")
	var sword: Dictionary = session.campaign.safe_snapshot().roster.p_mage.duplicate(true)
	check(sword.form_id == "sword" and sword.actor_id == mage.actor_id and sword.class_id == mage.class_id and sword.hp == mage.hp and sword.mp == mage.mp and sword.skill_ids == mage.skill_ids and sword.equipment == mage.equipment and session.campaign.safe_snapshot().roster.size() == 6, "未解锁切换不改变同一身份、HP/MP、技能与装备")
	check(session.bundle.get_definition("homura", "sword").get("manifest", {}).get("form_id") == "sword", "正式session切换实际剑形态")
	panel.busy = true
	var busy_before: Dictionary = session.campaign.safe_snapshot()
	var busy_result: Dictionary = panel.toggle_equipment("armor")
	check(not busy_result.ok and session.campaign.safe_snapshot() == busy_before, "异步人物加载锁住装备变更")
	panel.busy = false
	panel.preview_branch("power")
	var before_branch: Dictionary = session.campaign.safe_snapshot()
	check(not panel.apply_branch().ok and session.campaign.safe_snapshot() == before_branch, "L5分支不可通过整备提前解锁")
	check(panel.toggle_equipment("armor").ok and panel.toggle_equipment("armor").ok, "原有装备三槽能力仍由模型保存")
	var before_item: Dictionary = session.campaign.safe_snapshot()
	check(panel.use_item("healing_potion").ok and session.campaign.safe_snapshot().inventory.healing_potion == before_item.inventory.healing_potion - 1, "原有战外道具实际保存库存与恢复")
	var resumed: RefCounted = Session.new()
	check(resumed.resume().ok and resumed.campaign.safe_snapshot().party == ["p_mage", "p_healer", "p_controller"] and resumed.campaign.safe_snapshot().roster.p_mage.form_id == "sword", "重进正式档保留非默认编队和焰华形态")
	if not OS.get_environment("CAMPAIGN_PRESENTATION_OUTPUT").is_empty(): await _save_frame("party_panel_six_choices.png")
	panel.free()
	check((await resumed.prepare_assets()).ok, "重进高清资源来自已保存形态")
	for event in ["dialogue:a1", "dialogue:r1", "dialogue:h1"]:
		check(resumed.commit_event(resumed.campaign.safe_snapshot().world, event).ok, "真实战前准备事件：" + event)
	var battle: Dictionary = resumed.begin_encounter(resumed.campaign.safe_snapshot().world, "basin_reflection")
	check(battle.ok, "正式第一夜战斗接入")
	if battle.ok:
		var view = View.new()
		view.router = resumed.router
		root.add_child(view)
		await process_frame
		check(view._hd_enabled() and view._is_chapter() and view._hd_views.size() == 3 and not view._hd_failed, "正式ChapterSession驱动非默认三人高清战斗")
		check(view._canvas.get_meta("background_path", "") == "res://assets/bg/approach_battle.png", "真实正式首夜战斗显示新参道背景")
		for actor_id in resumed.campaign.safe_snapshot().party:
			check(view._actors[actor_id].avatar.get_meta("source_path", "").contains("high_detail_complete/frames/"), "战斗头像来自真实高清帧：" + actor_id)
		for actor_id in view.engine.snapshot().actors:
			var actor: Dictionary = view.engine.snapshot().actors[actor_id]
			var sprite: Node2D = view._actors[actor_id].sprite
			check(sprite.get_meta("facing_right") == (actor.side == "enemy"), "友右朝左/敌左朝右：" + actor_id)
			if actor.side == "enemy":
				var image_sprite: Sprite2D = sprite.visual.get_child(0)
				check(image_sprite.texture.get_width() == 1024 and image_sprite.has_meta("source_anchor"), "最终静态敌图已加载且使用真实脚锚：" + actor_id)
				var source_image := Image.new()
				var source_path: String = view._config.enemy_art[actor.class_id]
				source_image.load_png_from_buffer(FileAccess.get_file_as_bytes(source_path))
				check(image_sprite.texture.get_image().get_data() == source_image.get_data() and image_sprite.get_meta("source_path", "") == source_path, "真实战斗Texture逐像素等于对应敌ID原图、未fallback：" + actor_id)
		if not OS.get_environment("CAMPAIGN_PRESENTATION_OUTPUT").is_empty():
			await _save_frame("battle_nondefault_sword.png")
		view.free()
	var missing_session_view = View.new()
	missing_session_view.campaign = resumed.campaign
	check(missing_session_view._hd_enabled() and missing_session_view._is_chapter(), "正式安全档失去活跃资源会话时不得静默降级旧立绘")
	missing_session_view.free()
	resumed.close()

func _save_frame(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("CAMPAIGN_PRESENTATION_OUTPUT").path_join(filename)
	check(root.get_viewport().get_texture().get_image().save_png(path) == OK, "图形证据保存：" + filename)

func _capture_lineups() -> void:
	var Kit = load("res://scripts/rpg/ui/ui_kit.gd")
	var Hd = load("res://scripts/rpg/ui/hd_actor_view.gd")
	var Stature = load("res://scripts/characters/character_stature.gd")
	var backdrop := Control.new()
	backdrop.size = Vector2(1920, 1080)
	root.add_child(backdrop)
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rpg/presentation.json"))
	Kit.backdrop(backdrop, Kit.config_for_night(config, 1))
	Kit.panel(backdrop, Rect2(35, 40, 1850, 140))
	Kit.label(backdrop, "六身份 · 七形态高清原始帧（仅表现，不增加角色）", Rect2(65, 70, 1790, 65), 38)
	var forms := ["rinne", "mint", "guard", "homura_mage", "homura_sword", "healer", "controller"]
	for index in forms.size():
		var form: String = forms[index]
		var identity := "homura" if form.begins_with("homura_") else form
		var definition: Dictionary = Portraits.load_idle_definition(identity, form.trim_prefix("homura_"))
		var actor = Hd.new()
		check(actor.configure(definition, Stature.battle_body_height(identity), -1), "七形态实际配置：" + form)
		backdrop.add_child(actor)
		actor.position = Vector2(150 + index * 258, 820)
		Kit.label(backdrop, "%s · %dcm" % [form, roundi(Stature.height_cm(identity))], Rect2(30 + index * 258, 858, 240, 50), 22)
	await _save_frame("lineup_seven_forms.png")
	backdrop.free()
	var enemies := Control.new()
	enemies.size = Vector2(1920, 1080)
	root.add_child(enemies)
	Kit.backdrop(enemies, Kit.config_for_night(config, 4))
	Kit.panel(enemies, Rect2(35, 25, 1850, 75))
	Kit.label(enemies, "六张最终右向敌图 · 原始透明PNG · 静态表现", Rect2(65, 38, 1790, 50), 34)
	var ids := ["hound", "shield_soldier", "cultist", "fire_spirit", "elite_shield_soldier", "gatekeeper"]
	for index in ids.size():
		var id: String = ids[index]
		var foot := Vector2(345 + index % 3 * 610, 520 + index / 3 * 500)
		var actor: Node2D = Kit.actor_sprite(enemies, config.enemy_art[id], 380, false, config.enemy_geometry[id])
		actor.position = foot
		Kit.label(enemies, config.enemy_labels[id], Rect2(foot.x - 260, foot.y + 9, 520, 50), 27)
	await _save_frame("lineup_six_enemies.png")
	enemies.free()
	await _capture_battle_team(["swordsman", "ranger", "guard"], "", "battle_default_three.png")
	await _capture_battle_team(["mage", "healer", "controller"], "mage", "battle_nondefault_mage.png")

func _capture_battle_team(classes: Array[String], form: String, filename: String) -> void:
	var Session = load("res://scripts/campaign/chapter_session.gd")
	var View = load("res://scripts/rpg/ui/battle_view.gd")
	var session: RefCounted = Session.new()
	check(session.start_new(true, classes).ok, "图形编队正式新档：" + filename)
	if form == "mage":
		for event in ["dialogue:a1", "dialogue:r1", "dialogue:h1"]: check(session.commit_event(session.campaign.safe_snapshot().world, event).ok, "术形态图形解锁登记事件")
		var first: Dictionary = session.begin_encounter(session.campaign.safe_snapshot().world, "basin_reflection")
		var roster: Array[Dictionary] = []
		for id in session.campaign.safe_snapshot().party: roster.append(first.setup.actors[id].duplicate(true))
		check(session.router.finish({"battle_id": first.battle_id, "outcome": "victory", "roster": roster, "inventory": first.setup.inventory.duplicate(true), "xp": first.xp, "story_patch": first.story_patch.duplicate(true), "replay": {}}).ok, "术形态图形首夜胜利解锁")
		check(session.advance_night(session.campaign.safe_snapshot().world).ok, "术形态图形进入第二夜")
		check(session.campaign.set_form("p_mage", form).ok, "图形已解锁焰华法师")
	check((await session.prepare_assets()).ok, "图形战斗所选三人真实资源加载")
	for event in (["dialogue:c1"] if form == "mage" else ["dialogue:a1", "dialogue:r1", "dialogue:h1"]): check(session.commit_event(session.campaign.safe_snapshot().world, event).ok, "图形战前事件")
	check(session.begin_encounter(session.campaign.safe_snapshot().world, "bell_self_ring" if form == "mage" else "basin_reflection").ok, "图形正式已登记遭遇")
	var view = View.new()
	view.router = session.router
	root.add_child(view)
	check(view._hd_views.size() == 3 and not view._hd_failed, "图形三人高清战斗：" + filename)
	await _save_frame(filename)
	view.free()
	session.close()
