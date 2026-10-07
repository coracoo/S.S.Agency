# 实际七章场景、商人输入与模型交易接口验证；只允许统一runner核验后的隔离user目录。
# 使用真实旧七章检查点迁移；场景点位移动为交互测试夹具，不冒充人工走图或视觉验收。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Campaign = preload("res://scripts/rpg/campaign.gd")
const Store = preload("res://scripts/rpg/save_store.gd")
const Merchant = preload("res://scripts/campaign/merchant_catalog.gd")
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")

class FaultStore extends Store:
	var fail_write := false
	func _replace_file(temporary: String, destination: String) -> Error:
		return ERR_FILE_CANT_WRITE if fail_write else super._replace_file(temporary,destination)

var assertions := 0
var failures: Array[String] = []
var capture_root := ""

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
		printerr("FAIL: 商人场景测试需要已核验的隔离user目录")
		quit(2)
		return
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1920,1080)
	capture_root = OS.get_environment("ACT_ONE_OUTPUT")
	if not capture_root.is_empty():
		check(DisplayServer.get_name() != "headless","截图模式必须使用实际图形后端")
		if DisplayServer.get_name() == "headless": _finish();return
		root.position = Vector2i(-32000,-32000)
		DirAccess.make_dir_recursive_absolute(capture_root)
	var path: String = Chapters.SAVE_PATH
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes("res://tools/campaign/fixtures/loadout-schema2-chapter7.json"))
	file.close()
	var store := FaultStore.new()
	var session := Session.new(Campaign.new(null,store,path))
	var resumed: Dictionary = session.resume()
	check(resumed.ok,"真实旧七章安全档经正式入口迁移并恢复")
	if not resumed.ok:
		printerr(resumed.get("error",""))
		session.close()
		_finish()
		return
	check(Merchant.presence(session.campaign.safe_snapshot()),"终章战前安全检查点允许商人出现")
	var stage: Node3D = load("res://scenes/campaign/saga.tscn").instantiate()
	root.add_child(stage)
	for frame in 6000:
		await process_frame
		if stage.ready_for_play or not stage.last_error.is_empty(): break
	check(stage.ready_for_play,"正式七章场景与人物资源实际加载完成："+str(stage.last_error))
	if not stage.ready_for_play:
		stage.free()
		session.close()
		_finish()
		return
	stage.player.set_physics_process(false)
	check(stage._targets.any(func(target): return target.id == "@merchant"),"安全窗口登记独立近距商人交互")
	check(is_instance_valid(stage._merchant_actor) and stage._merchant_actor.is_visible_in_tree(),"地图中有真正可见的独立商人节点")
	if is_instance_valid(stage._merchant_actor):
		check(stage._merchant_actor.find_children("*","MeshInstance3D",true,false).size() >= 20,"商人由斗笠、披风、货箱、背篓和灯的独立网格构成")
		check(stage._merchant_actor.find_child("MerchantLanternLight",true,false) is OmniLight3D,"商人摊点具有独立暖灯")
		check(stage._merchant_actor.get_meta("art_status","") == "independent_procedural_static_no_dedicated_animation","程序化静态人物不伪称已有逐帧美术")
	var anchor: Vector3 = Merchant.anchor(session.campaign.safe_snapshot())
	check(stage._merchant_actor.position == anchor,"人物和交互共用目录安全锚点")
	stage.player.position = anchor+Vector3(0,0,3)
	stage._confirm_armed = true
	check(not stage.request_interaction("@merchant"),"在交易半径之外不能远程打开商人")
	stage.player.position = anchor+Vector3(0,0,1.2)
	if not capture_root.is_empty(): await _capture_world(stage,anchor)
	stage._confirm_armed = true
	var before: Dictionary = session.campaign.safe_snapshot()
	var disk := FileAccess.get_file_as_bytes(path)
	await _key(KEY_E,true)
	check(stage._mode == "merchant" and is_instance_valid(stage._merchant_panel),"附近真实E键输入打开商人面板")
	check(not stage.controls_enabled and not stage._confirm_armed,"开窗锁住角色移动与地图重复确认")
	if not is_instance_valid(stage._merchant_panel):
		stage.free();session.close();_finish();return
	var panel: Control = stage._merchant_panel
	check(not panel._input_armed and panel._buy.disabled,"按住开窗键期间不能顺带购买")
	panel._buy_selected()
	check(session.campaign.safe_snapshot() == before and FileAccess.get_file_as_bytes(path) == disk,"打开窗口与未松键确认均不改资源、世界或存档")
	await _key(KEY_E,false)
	check(panel._input_armed and get_root().gui_get_focus_owner() != null,"松键后建立键盘焦点并允许选择商品")
	check(not panel.offers.is_empty(),"面板实际展示模型货架")
	var chosen: Dictionary = {}
	for offer in panel.offers:
		if offer.unlocked and offer.stock > 0 and offer.price <= before.saga.coins:
			chosen = offer
			break
	check(not chosen.is_empty(),"真实检查点至少有一项可购商品")
	if chosen.is_empty(): stage.free();session.close();_finish();return
	panel._select(str(chosen.id))
	check(panel._detail.text.contains(str(chosen.name)) and panel._detail.text.contains("现有") and panel._detail.text.contains("本周目剩余"),"明示商品名称、持有数量与全局剩余库存")
	await _check_layout(panel)
	store.fail_write = true
	panel._buy_selected()
	check(not panel.last_error.is_empty() and not panel.last_error.contains("交易已保存"),"正式写档失败显示错误而非成功提示")
	check(session.campaign.safe_snapshot() == before and FileAccess.get_file_as_bytes(path) == disk,"正式原子写档失败不扣银钱、不发物品且磁盘不变")
	store.fail_write = false
	await process_frame
	panel._buy.grab_focus()
	await _key(KEY_ENTER,true)
	await _key(KEY_ENTER,false)
	var after: Dictionary = session.campaign.safe_snapshot()
	check(after.saga.coins == before.saga.coins-int(chosen.price),"真实键盘购买通过正式模型扣除展示价格")
	var inventory_key := "gear" if chosen.kind == "gear" else "cards"
	check(int(after[inventory_key].get(chosen.item_id,0)) == int(before[inventory_key].get(chosen.item_id,0))+1,"购买物品实际进入正式持有表")
	var updated: Dictionary = panel._selected()
	check(int(updated.stock) == int(chosen.stock)-1 and panel._balance.text.contains(str(after.saga.coins)),"购买后货架和余额从保存结果刷新")
	for actor_id in after.roster:
		check(after.roster[actor_id].hp == before.roster[actor_id].hp and after.roster[actor_id].mp == before.roster[actor_id].mp,"商人交易不自动恢复HP/MP："+actor_id)
	await _key(KEY_ESCAPE,true)
	check(stage._mode == "explore" and stage.controls_enabled and not stage._confirm_armed,"Esc退出并保持松键前确认锁")
	await _key(KEY_ESCAPE,false)
	await _key(KEY_E,true)
	await _key(KEY_E,false)
	check(stage._mode == "merchant" and session.campaign.safe_snapshot() == after,"重开窗口不补货、不回血、不生成第二笔交易")
	panel = stage._merchant_panel
	panel._select(str(chosen.id))
	check(panel._selected().stock == updated.stock,"重开仍展示同一份全局库存")
	stage._merchant_closed()
	# 到原补给位置真实购买药物，建立可重放的低余额；不伪改银钱骗过商人账本。
	var shop: Array = stage.config.anchors.shop
	stage.player.position = Vector3(shop[0],shop[1],shop[2])+Vector3(0,0,1.2)
	for purchase in 12:
		var remaining: int = session.campaign.safe_snapshot().saga.coins
		if remaining < 18: break
		var quantity: int = mini(9,remaining/18)
		var supplied: Dictionary = session.campaign.buy_saga_item(stage.export_world(),"healing_potion",quantity)
		check(supplied.ok,"原补给店真实消费建立低余额交易夹具")
		if not supplied.ok: break
	after = session.campaign.safe_snapshot()
	check(after.saga.coins < 18,"低余额来自实际消耗品购买历史")
	stage.apply_committed_world(after.world)
	stage.player.position = anchor+Vector3(0,0,1.2)
	stage._confirm_armed = true
	check(stage.request_interaction("@merchant"),"低余额仍可实地查看商人货架")
	await process_frame
	var poor_panel: Control = stage._merchant_panel
	var unsold := ""
	for offer in poor_panel.offers:
		if offer.unlocked and offer.stock > 0: unsold = str(offer.id);break
	check(not unsold.is_empty(),"低余额检查点仍有真实待售商品")
	poor_panel._select(unsold)
	check(poor_panel._buy.disabled and poor_panel._status.text.contains("银钱不足"),"余额不足显示具体原因并禁止确认")
	poor_panel._buy_selected()
	check(session.campaign.safe_snapshot() == after,"不足余额UI不污染真实交易档")
	var insufficient: Dictionary = session.campaign.buy_merchant_item(stage.export_world(),unsold,1)
	check(not insufficient.ok and session.campaign.safe_snapshot() == after,"正式模型同样拒绝真实低余额购买")
	stage._merchant_closed()
	var closed_world: Dictionary = session.campaign.safe_snapshot()
	var hidden: Dictionary = closed_world.duplicate(true)
	hidden.saga.battles.append("C7-05")
	check(not Merchant.presence(hidden),"C7-05获胜后目录明确要求商人全球离场")
	# 只读呈现替身验证离场清理，不将构造的战果写入真实Campaign。
	var proxy := VisibilityModel.new(closed_world,session.campaign._catalog)
	var original_model: RefCounted = session.campaign
	session.campaign = proxy
	proxy.saved = hidden
	stage._refresh_targets()
	check(not is_instance_valid(stage._merchant_actor) and not stage._targets.any(func(target): return target.kind == "merchant"),"模型停止出场时删除地图实体和交互目标")
	session.campaign = original_model
	check(original_model.safe_snapshot() == after,"离场呈现夹具不伪造真实终战胜利")
	stage.free()
	session.close()
	await process_frame
	_finish()

class VisibilityModel extends RefCounted:
	var saved: Dictionary
	var _catalog: RefCounted
	func _init(snapshot: Dictionary, definitions: RefCounted) -> void:
		saved = snapshot.duplicate(true)
		_catalog = definitions
	func safe_snapshot() -> Dictionary: return saved.duplicate(true)

func _check_layout(panel: Control) -> void:
	for resolution in [Vector2i(1920,1080),Vector2i(1280,720),Vector2i(1024,768)]:
		root.size = resolution
		await process_frame
		await process_frame
		var visible := root.get_visible_rect()
		for control in [panel._balance,panel._detail,panel._quantity,panel._buy,panel._close,panel._status]:
			check(visible.encloses(control.get_global_rect()) and control.size.x > 0 and control.size.y > 0,"三分辨率关键控件实际布局在画布内：%s/%s" % [str(resolution),control.name])
		check(panel._buy.size.y >= 48 and panel._close.size.y >= 48,"购买和退出保持可用命中高度："+str(resolution))
		check(panel.get_node("SafeMargins/ShopFrame").get_global_rect().position.x >= 24,"商店边缘保留安全间距："+str(resolution))
		if not capture_root.is_empty(): await _capture_panel(panel,resolution)
	root.size = Vector2i(1920,1080)
	await process_frame

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame
	await process_frame

func _capture_world(stage: Node3D, anchor: Vector3) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,960)
	viewport.world_3d = stage.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.9
	viewport.add_child(camera)
	camera.position = anchor+Vector3(2.8,2.5,4.8)
	camera.look_at(anchor+Vector3(0,.9,0))
	camera.current = true
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(capture_root.path_join("merchant-world.png")) == OK,"独立Subviewport保存真实地区商人画面")
	viewport.free()

func _capture_panel(panel: Control, resolution: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = resolution
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var copy: Control = load("res://scripts/campaign/merchant_panel.gd").new()
	viewport.add_child(copy)
	copy.open(panel.campaign,panel.world)
	for frame in 4: await process_frame
	copy._select(panel.selected_id)
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(capture_root.path_join("merchant-%dx%d.png" % [resolution.x,resolution.y])) == OK,"独立Subviewport保存商店实际排版："+str(resolution))
	viewport.free()

func _finish() -> void:
	print("MERCHANT_STAGE: %d assertions, %d failures" % [assertions,failures.size()])
	quit(0 if failures.is_empty() else 1)
