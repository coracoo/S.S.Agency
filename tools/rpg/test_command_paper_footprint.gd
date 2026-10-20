extends SceneTree
const Menu = preload("res://scripts/rpg/ui/actor_command_menu.gd")
var failures := 0
func check(value: bool,label: String) -> void:
	if not value: failures += 1; printerr("PAPER_FOOTPRINT_FAIL: ",label)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _run() -> void:
	var menu = Menu.new();root.add_child(menu)
	if not menu.has_method("occupied_rects"):
		check(false,"透明菜单必须提供实际纸面占区，不能把透明页眉空段当纸板")
		menu.queue_free();quit(1);return
	var skills: Array = []
	for index in 4: skills.append({"id":"skill"+str(index),"name":"长原因技能","mp_cost":9,"legal":false,"reasons":["MP不足，技能仍在冷却中；目标不可选"],"summary":"单体伤害","target_label":"敌方单体"})
	menu.present({"page":"skills","actor_name":"薄荷","skills":skills,"basics":["attack_physical","defend","item"]})
	var required: Vector2 = menu.required_size_for_page("skills",true)
	var origin := Vector2(24,984-required.y)
	menu.set_placement(Rect2(origin,required),true)
	for frame in 3: await process_frame
	var protected: Array[Rect2] = [Rect2(97,726,306,54),Rect2(457,726,306,54),Rect2(1364,365,242,355),Rect2(1639,361,139,301)]
	check(menu.get("_header_paper").position.x > 1000,"停靠技能页眉在右侧净空")
	check(menu.occupied_rects().size()==6,"四叶加短页眉和返回，透明间隙不占区")
	check(Rect2(origin,required).intersects(protected[0]),"用例确实覆盖根容器透明段与意图区相交")
	for local in menu.occupied_rects():
		var actual := Rect2(origin+local.position,local.size)
		for obstacle in protected:check(actual.intersection(obstacle).get_area()<=.01,"实际纸面和焦点边与保护区无交叠")
	menu.queue_free();await process_frame
	print("PAPER_FOOTPRINT_CONTRACT: ",failures," failures")
	quit(0 if failures==0 else 1)
