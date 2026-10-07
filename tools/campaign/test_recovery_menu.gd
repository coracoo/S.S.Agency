# 正式回收册UI门禁；使用明确事务胜利夹具，不将本测试称为自然战斗通关。
# 所有写档只发生于建立剧情夹具；阅读、选条目、切页、返回与截图必须零写档。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Campaign = preload("res://scripts/rpg/campaign.gd")
const Store = preload("res://scripts/rpg/save_store.gd")
const PartyPanel = preload("res://scripts/campaign/party_panel.gd")
const Fixture = preload("res://tools/campaign/saga_transaction_fixture.gd")
const Recovery = preload("res://scripts/campaign/recovery_catalog.gd")

class CountStore extends Store:
	var write_attempts := 0
	func _write_temporary(path: String, contents: String) -> Error:
		write_attempts += 1
		return super._write_temporary(path,contents)

var assertions := 0
var failures: Array[String] = []
var capture_root := ""
var store: RefCounted

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		printerr("FAIL: ",message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var isolated := OS.get_environment("RPG_TEST_ROOT").replace("\\","/").simplify_path().trim_suffix("/")
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or isolated.is_empty() or not OS.get_user_data_dir().replace("\\","/").simplify_path().begins_with(isolated+"/"):
		printerr("FAIL: 回收册门禁需要已核验的隔离user目录")
		quit(2)
		return
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1920,1080)
	capture_root = OS.get_environment("ACT_ONE_OUTPUT")
	if not capture_root.is_empty():
		check(DisplayServer.get_name() != "headless","截图模式必须有真实图形后端")
		if DisplayServer.get_name() == "headless": _finish();return
		root.position = Vector2i(-32000,-32000)
		DirAccess.make_dir_recursive_absolute(capture_root)
	store = CountStore.new()
	var session := Session.new(Campaign.new(null,store,Session.Chapters.SAVE_PATH))
	check(session.start_new(true).ok,"建立真实正式新档")
	await _test_empty_and_navigation(session)
	check(Fixture.enter_saga(session),"明确事务夹具依次提交首章五夜后进入第二章")
	check(Fixture.through(session,"C2-03"),"明确事务夹具完成C2-03，留下已胜利但后续联系尚未开放的首收")
	await _test_locked_records(session)
	check(Fixture.through(session,"C2-07"),"完成原调查事件以开放既有回收条目的茶棚联系")
	await _test_opened_links(session)
	session.close()
	await process_frame
	_finish()

func _baseline(session: RefCounted) -> Dictionary:
	return {"snapshot":session.campaign.safe_snapshot(),"bytes":FileAccess.get_file_as_bytes(Session.Chapters.SAVE_PATH),"writes":store.write_attempts}

func _read_only(session: RefCounted, before: Dictionary, label: String) -> void:
	check(session.campaign.safe_snapshot() == before.snapshot,label+"不改任何正式模型字段")
	check(FileAccess.get_file_as_bytes(Session.Chapters.SAVE_PATH) == before.bytes,label+"保持正式档原字节")
	check(store.write_attempts == before.writes,label+"连临时写档尝试也没有")

func _panel(session: RefCounted, page: String = "menu") -> CanvasLayer:
	var panel := PartyPanel.new()
	root.add_child(panel)
	panel.open(session,page)
	return panel

func _test_empty_and_navigation(session: RefCounted) -> void:
	var before := _baseline(session)
	var panel := _panel(session)
	await process_frame
	check(panel._tabs.size() == 4 and panel._tabs.keys() == ["party","inventory","equipment","loadout"],"顶排仍只有原四个整备标签")
	check(panel._hud.menu_inventory.position == Vector2(982,282) and panel._hud.menu_inventory.size.x == 280 and panel._hud.menu_recoveries.position == Vector2(1278,282) and panel._hud.menu_recoveries.size.x == 280,"菜单首行只在原576宽度内分成行囊与回收册")
	check(panel._hud.rest.position == Vector2(982,570) and panel._hud.menu_loadout.position == Vector2(982,498),"其它菜单行保持原位置")
	panel._hud.menu_recoveries.grab_focus()
	await _key(KEY_ENTER)
	check(panel.current_page == "recoveries" and not panel._roster_panel.visible,"真实确认键打开独立回收页并隐藏队员栏")
	check(panel._recovery.entries.is_empty() and panel._recovery._empty.visible and panel._recovery._empty.text.contains("真实胜利"),"空册明确仅已确认真实胜利才会收录")
	check(panel._recovery._buttons.is_empty() and panel._recovery._detail.text.is_empty(),"空册没有可领取占位条目或虚构回收内容")
	await _key(KEY_ESCAPE)
	check(panel.current_page == "menu","真实Esc从回收册返回原菜单")
	panel._hud.menu_inventory.grab_focus()
	await _key(KEY_ENTER)
	check(panel.current_page == "inventory" and panel._roster_panel.visible,"拆分后的行囊入口仍正常显示原使用目标栏")
	panel._hud.back.grab_focus()
	await _key(KEY_ENTER)
	check(panel.current_page == "menu","原行囊返回按钮仍回到菜单")
	_read_only(session,before,"空册与原页往返")
	if not capture_root.is_empty(): await _capture(session,"menu","",Vector2i(1920,1080),"recovery-menu-entry")
	panel.free()
	await process_frame

func _test_locked_records(session: RefCounted) -> void:
	var before := _baseline(session)
	var panel := _panel(session)
	panel._hud.menu_recoveries.grab_focus()
	await _key(KEY_ENTER)
	var book: Control = panel._recovery
	var expected: Array = Recovery.earned(before.snapshot,panel._catalog)
	check(book.entries == expected and book.entries.size() == 8,"真实已胜检查点展示六种首章记录及两种第二章记录")
	check(book.entries.filter(func(entry): return entry.enemy_id == "hound").size() == 1,"重复出场的影犬在册中仍仅一条首收")
	var paper_id := "recovery_saga_paper_soldier"
	check(book._buttons.has(paper_id),"已提交C2-03的纸兵首收可在列表选择")
	if not book._buttons.has(paper_id): panel.free();return
	book._buttons[paper_id].grab_focus()
	await _key(KEY_ENTER)
	check(book.selected_id == paper_id,"真实确认键选择首收条目")
	var paper: Dictionary = book._selected()
	var detail: String = book._detail.text
	check(detail.contains(paper.name) and detail.contains("循令纸兵") and detail.contains("首收地点：第2章") and detail.contains("首次遭遇"),"回收详情展示材料名、真实敌种与首收地点")
	check(detail.contains("战后留记") and detail.contains("循令纸兵退治后留存") and detail.contains("留存数量：1"),"用可读战后留记说明一次永久收录")
	check(not paper.battle_id.is_empty() and not paper.encounter_id.is_empty() and not paper.verified_scope.is_empty(),"内部首胜来源和审计范围仍完整保留在记录数据")
	_no_technical_ids(book,before.snapshot)
	var raw := _raw_entry(paper_id)
	check(not detail.contains(raw.links[0].label) and not detail.contains(raw.links[0].text) and not detail.contains(raw.links[0].scene_id),"尚未调查的联系不显示原标题、正文或场次ID")
	check(detail.contains("后续调查尚未完成"),"锁定联系只给出一般状态说明")
	# 只篡改UI自己的条目副本，验证未解锁内容即使误传到表现层也不会进文字/tooltip。
	for entry in book.entries:
		if entry.id != paper_id: continue
		entry.links[0].label = "LOCKED_TITLE_SENTINEL"
		entry.links[0].text = "LOCKED_TEXT_SENTINEL"
		entry.links[0].scene_id = "LOCKED_SCENE_SENTINEL"
	book.select_record(paper_id)
	var displayed := _all_text(book)
	check(not displayed.contains("LOCKED_TITLE_SENTINEL") and not displayed.contains("LOCKED_TEXT_SENTINEL") and not displayed.contains("LOCKED_SCENE_SENTINEL"),"UI自身同样保护未解锁内容，不依赖上游先删文本")
	check(book._detail.scroll_active and book._detail.get_v_scroll_bar().max_value > book._detail.get_v_scroll_bar().page,"实际长详情有可滚动溢出")
	var scroll_before: float = book._detail.get_v_scroll_bar().value
	var wheel := InputEventMouseButton.new()
	wheel.position = book._detail.get_global_rect().get_center()
	wheel.global_position = wheel.position
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	root.push_input(wheel,true)
	await process_frame
	await process_frame
	check(book._detail.get_v_scroll_bar().value > scroll_before,"真实鼠标滚轮可以阅读详情下方内容")
	for resolution in [Vector2i(1920,1080),Vector2i(1280,720),Vector2i(1024,768)]:
		root.size = resolution
		await process_frame
		await process_frame
		for control in [book,book._detail,book._count,panel._hud.back,panel._hud.close]:
			check(root.get_visible_rect().encloses(control.get_global_rect()),"回收页关键控件在画布内：%s/%s" % [str(resolution),control.name])
		check(not panel._roster_panel.visible and not book._detail.get_global_rect().intersects(book.find_child("RecordListScroll",true,false).get_global_rect()),"多分辨率详情与列表不重叠且不挤入队员栏："+str(resolution))
		if not capture_root.is_empty(): await _capture(session,"recoveries",paper_id,resolution,"recovery-locked")
	root.size = Vector2i(1920,1080)
	await process_frame
	panel._tabs.inventory.grab_focus()
	await _key(KEY_ENTER)
	check(panel.current_page == "inventory" and panel._roster_panel.visible,"回收册可通过原顶排标签返回行囊")
	panel.show_page("recoveries")
	check(panel._recovery.selected_id == paper_id,"离开后再开回收册保留有效阅读条目")
	await _key(KEY_ESCAPE)
	check(panel.current_page == "menu","长详情阅读后Esc正常返回菜单")
	_read_only(session,before,"已胜利回收册的选择、缩放、滚动与往返")
	panel.free()
	await process_frame

func _test_opened_links(session: RefCounted) -> void:
	var before := _baseline(session)
	var panel := _panel(session,"recoveries")
	var book: Control = panel._recovery
	var lamp_id := "recovery_saga_lamp_shadow"
	check(book._buttons.has(lamp_id),"重复获胜后仍有首次灯影回收记录")
	if not book._buttons.has(lamp_id): panel.free();return
	book._buttons[lamp_id].grab_focus()
	await _key(KEY_ENTER)
	var lamp: Dictionary = book._selected()
	check(lamp.encounter_id == "saga_c2_03" and book.entries.filter(func(entry): return entry.id == lamp_id).size() == 1,"后续同类敌胜利不会覆盖实际首收来源或新增副本")
	var raw := _raw_entry(lamp_id)
	var detail: String = book._detail.text
	check(detail.contains(raw.links[0].label) and detail.contains(raw.links[0].text),"已完成C2-07后展示真实开放的茶棚调查联系")
	check(not detail.contains(raw.links[1].label) and not detail.contains(raw.links[1].text),"同条目的尚未完成C2-09联系继续隐藏")
	_no_technical_ids(book,before.snapshot)
	check(book.find_children("*","Button",true,false).size() == book.entries.size(),"册页只有选择记录按钮，没有发奖、使用或交易按钮")
	if not capture_root.is_empty(): await _capture(session,"recoveries",lamp_id,Vector2i(1920,1080),"recovery-opened")
	_read_only(session,before,"调查联系开放后的阅读")
	panel.free()
	await process_frame

func _raw_entry(id: String) -> Dictionary:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/enemy_recoveries.json"))
	for entry in document.definitions:
		if entry.id == id: return entry
	return {}

func _all_text(node: Node) -> String:
	var value := ""
	if node is Label or node is RichTextLabel or node is Button: value += str(node.text)
	if node is Control: value += node.tooltip_text
	for child in node.get_children(): value += _all_text(child)
	return value

func _no_technical_ids(book: Control, saved: Dictionary) -> void:
	var displayed := _all_text(book)
	check(not displayed.contains(str(saved.run_id)),"玩家正文不显示内部run_id")
	for entry in book.entries:
		check(not displayed.contains(str(entry.battle_id)) and not displayed.contains(str(entry.encounter_id)),"玩家正文不显示内部battle_id或encounter_id："+str(entry.enemy_id))

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event,true)
	await process_frame
	event.pressed = false
	root.push_input(event,true)
	await process_frame
	await process_frame

func _capture(session: RefCounted, page: String, selected: String, resolution: Vector2i, label: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = resolution
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var copy := PartyPanel.new()
	viewport.add_child(copy)
	copy.open(session,page)
	if page == "recoveries" and not selected.is_empty():
		copy._recovery.select_record(selected)
	for frame in 4: await process_frame
	if page == "recoveries":
		copy._recovery.focus_first()
		await process_frame
		await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(capture_root.path_join("%s-%dx%d.png" % [label,resolution.x,resolution.y])) == OK,"独立Subviewport保存回收页实际排版："+label)
	viewport.free()

func _finish() -> void:
	print("RECOVERY_MENU: %d assertions, %d failures" % [assertions,failures.size()])
	quit(0 if failures.is_empty() else 1)
