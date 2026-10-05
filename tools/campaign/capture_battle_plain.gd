# 无章节会话的纯战斗界面截图；验证非HD回退皮肤用。
extends SceneTree
const F = preload("res://tools/rpg/fixtures.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Battle = preload("res://scripts/rpg/battle_engine.gd")
const Policy = preload("res://scripts/rpg/enemy_policy.gd")
const View = preload("res://scripts/rpg/ui/battle_view.gd")
var output := ""
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or OS.get_environment("ACT_ONE_OUTPUT").is_empty(): quit(2); return
	output = OS.get_environment("ACT_ONE_OUTPUT")
	_run.call_deferred()
func _run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var catalog := Catalog.new()
	catalog.load_all()
	var actors := {"p_guard": F.actor("guard", "p_guard"), "p_swordsman": F.actor("swordsman", "p_swordsman"), "p_healer": F.actor("healer", "p_healer"), "e_1": F.enemy("hound", "e_1"), "e_2": F.enemy("hound", "e_2")}
	actors.p_swordsman.hp = actors.p_swordsman.stats.hp - 35
	actors.p_swordsman.mp = maxi(0, actors.p_swordsman.mp - 8)
	var engine := Battle.new(catalog)
	engine.set_policy(Policy.new())
	engine.start({"actors": actors, "inventory": {"healing_potion": 3, "mana_potion": 1, "revival_potion": 1, "cleansing_powder": 1, "energy_tea": 2, "guard_charm": 1, "moxa_roll": 2}}, 1701)
	var view = View.new()
	root.add_child(view)
	view.bind(engine, null)
	await process_frame
	for size in [Vector2i(1920, 1080)]:
		root.size = size
		await process_frame
		# 技能选中+目标预览状态
		view.select_command("skill", "heavy_slash")
		var options: Dictionary = view.command_options("skill", "heavy_slash")
		if not options.get("targets", []).is_empty(): view.select_target(options.targets[0])
		await process_frame
		await process_frame
		await process_frame
		root.get_texture().get_image().save_png(output.path_join("battle_preview.png"))
		view.cancel_command()
		view._toggle_log()
		await process_frame
		await process_frame
		await process_frame
		root.get_texture().get_image().save_png(output.path_join("battle_log.png"))
		view._toggle_log()
		view._items.visible = true
		await process_frame
		await process_frame
		await process_frame
		root.get_texture().get_image().save_png(output.path_join("battle_items.png"))
		print("BATTLE_CAPTURE: 3 screenshots")
	quit(0)
