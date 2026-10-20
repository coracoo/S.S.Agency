extends SceneTree
const Menu = preload("res://scripts/rpg/ui/actor_command_menu.gd")
var failures: Array[String] = []
var checks := 0
func expect(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("PAPER_STYLE_FAIL: ",message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _run() -> void:
	var menu = Menu.new()
	root.add_child(menu)
	menu.present({"page":"target","actor_name":"凛音","basics":["attack_physical","defend","item"],"selected_label":"物理普攻","cost_text":"MP 0","target_text":"纸妖","confirm_legal":true})
	menu.set_placement(Rect2(24,116,740,132),false)
	await process_frame
	for item in [[menu.confirm_button,"leaf"],[menu.back_button,"leaf"],[menu.get("_header_paper"),"leaf"],[menu.get("_target_paper"),"summary"]]:
		var control: Control = item[0]
		var style: StyleBox = control.get_theme_stylebox("normal" if control is Button else "panel")
		expect(style is StyleBoxTexture,"实际菜单纸面使用已核验原PNG纹理："+item[1])
		if style is StyleBoxTexture:
			expect(style.texture.get_size() == (Vector2(512,192) if item[1]=="leaf" else Vector2(768,96)),"纹理logical size正确")
			for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: expect(is_equal_approx(style.get_texture_margin(side),12),"真实纹理12px切片")
	var focus: StyleBox = menu.confirm_button.get_theme_stylebox("focus")
	expect(focus is StyleBoxFlat and focus.border_width_left==3 and focus.expand_margin_left==2,"保留原生3px焦点外扩2")
	var has_toggle := false
	for property in menu.get_property_list():
		if property.name == "use_washi_paper": has_toggle = true
	expect(has_toggle,"保留原StyleBox可回退")
	if has_toggle:
		var fallback = Menu.new(); fallback.use_washi_paper = false
		root.add_child(fallback)
		fallback.present({"page":"target","basics":["defend","item"],"selected_label":"物理普攻","confirm_legal":true})
		fallback.set_placement(Rect2(24,116,740,132),false)
		await process_frame
		expect(fallback.confirm_button.get_theme_stylebox("normal") is StyleBoxFlat,"关闭纹理后原StyleBox仍可用")
		expect(fallback.confirm_button.get_rect() == menu.confirm_button.get_rect(),"回退不改变确认点击框")
		fallback.queue_free()
	menu.queue_free()
	await process_frame
	print("PAPER_STYLE_CONTRACT: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
