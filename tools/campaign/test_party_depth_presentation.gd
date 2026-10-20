# 角色纵深缓存回归：真实Session/三近战BattleView；备用形态仅投影只读快照，不提交未解锁的换形。
# 由root在隔离user://下串行启动；本文件不创建或修改正式源码。
extends SceneTree
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Chapters = preload("res://scripts/campaign/chapter_catalog.gd")
const Forms = preload("res://scripts/rpg/dual_form.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Battle = preload("res://scripts/rpg/battle_engine.gd")
const EnemyPolicy = preload("res://scripts/rpg/enemy_policy.gd")
const Presentation = preload("res://tools/campaign/presentation_test_support.gd")
const PARTY: Array[String] = ["p_swordsman","p_mage","p_guard"]
var output := ""
var label := "before"
var session: RefCounted
var battle: Control
var failures: Array[String] = []
var setup_errors: Array[String] = []
var diagnostics: Dictionary = {}

func _initialize() -> void:
	output = OS.get_environment("RPG_TEST_ROOT").path_join("party-depth-cache")
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()-1):
		if args[index] == "--label": label = args[index+1]
	var isolated := OS.get_environment("RPG_TEST_ROOT").replace("\\","/").simplify_path().trim_suffix("/")
	var user_dir := OS.get_user_data_dir().replace("\\","/").simplify_path()
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or isolated.is_empty() or not user_dir.to_lower().begins_with(isolated.to_lower()+"/") or not _in_task(output):
		printerr("DEPTH_CACHE_BLOCKED: isolated user directory/output not verified")
		quit(2)
		return
	if FileAccess.file_exists(Chapters.SAVE_PATH):
		printerr("DEPTH_CACHE_BLOCKED: fresh isolated save slot required")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		printerr("DEPTH_CACHE_BLOCKED: scoped output unavailable")
		quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1920,1080)
	root.content_scale_size = Vector2i(1920,1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if DisplayServer.get_name() != "headless": root.position = Vector2i(-32000,-32000)
	session = Session.new()
	var classes: Array[String] = ["swordsman","mage","guard"]
	var created: Dictionary = session.start_new(false,classes)
	if not created.get("ok",false):
		await _abort("production start_new: "+str(created))
		return
	var selected: Dictionary = session.campaign.set_party(PARTY)
	if not selected.get("ok",false):
		await _abort("production set_party: "+str(selected))
		return
	var world: Dictionary = session.campaign.safe_snapshot().world.duplicate(true)
	for event_id in ["dialogue:a1","dialogue:r1","dialogue:h1"]:
		var committed: Dictionary = session.commit_event(world,event_id)
		if not committed.get("ok",false):
			await _abort("production commit_event: "+str(committed))
			return
		world = session.campaign.safe_snapshot().world.duplicate(true)
	var started: Dictionary = session.begin_encounter(world,"basin_reflection")
	if not started.get("ok",false):
		await _abort("production begin_encounter: "+str(started))
		return
	var prepared: Dictionary = await session.prepare_assets("battle",true)
	if not prepared.get("ok",false):
		await _abort("production battle assets: "+str(prepared))
		return
	battle = load("res://scenes/rpg/battle.tscn").instantiate()
	root.add_child(battle)
	current_scene = battle
	var ready: Dictionary = await Presentation.wait_for_battle(self,battle,PARTY)
	if not ready.get("ok",false) or not await _wait_stable():
		await _abort("production battle ready: "+str(ready))
		return
	if not battle.has_method("_resolve_party_depth_plan"):
		await _abort("production layout helper is absent")
		return
	var initial_state: Dictionary = battle.engine.snapshot().duplicate(true)
	var engine_id: int = battle.engine.get_instance_id()
	if initial_state.actors.p_mage.get("form_id") != "sword":
		await _abort("official first-chapter Homura must start in sword form")
		return
	var actual_feet := _actual_feet()
	var initial_plan: Dictionary = battle.get("_party_depth_plan").duplicate(true)
	if not initial_plan.get("ok",false):
		await _abort("production initial plan failed: "+str(initial_plan))
		return
	var copied_state := initial_state.duplicate(true)
	var catalog := Catalog.new()
	var catalog_errors: Array[String] = catalog.load_all()
	if not catalog_errors.is_empty():
		await _abort("catalog unavailable: "+str(catalog_errors))
		return
	# 仅调用生产派生函数投影备用form，不改unlocked_forms，不提交，不保存，不声称合法F/Y实战。
	Forms.apply(copied_state.actors.p_mage,"mage",catalog)
	var alternate_plan: Dictionary = battle.call("_resolve_party_depth_plan",PARTY,copied_state)
	if not alternate_plan.get("ok",false):
		await _abort("alternate snapshot helper failed: "+str(alternate_plan))
		return
	var before_json := {}
	var alternate_json := {}
	for actor_id in PARTY:
		var original: Vector2 = actual_feet[actor_id]
		var proposed: Vector2 = alternate_plan.feet[actor_id]
		before_json[actor_id] = [original.x,original.y]
		alternate_json[actor_id] = [proposed.x,proposed.y]
		_expect(original.distance_to(proposed) <= .5,"same-battle helper keeps initial production source foot: "+actor_id)
	_expect(alternate_plan.get("roles",{}).get("p_mage") == initial_plan.get("roles",{}).get("p_mage"),"same-battle helper keeps initial Homura role")
	_expect(battle.engine.get_instance_id() == engine_id and battle.engine.snapshot() == initial_state,"helper projection leaves authoritative engine, HP/MP, queue, RNG and locked forms unchanged")
	# 真实重建入口也复验实际source脚点；这里权威state始终是原sword，不冒称法形游戏操作。
	battle.call("_build_actors")
	var rebuilt := _actual_feet()
	for actor_id in PARTY:
		_expect((rebuilt[actor_id] as Vector2).distance_to(actual_feet[actor_id]) <= .5,"production rebuild keeps original source foot: "+actor_id)
	# 新权威engine重新绑定时必须丢弃旧缓存；标记仅放在展示计划，不改模型。
	battle.get("_party_depth_plan").test_cache_nonce = "same_engine_only"
	# Router.create_engine会复用原实例；新实例从同一正式登记setup/seed启动，不改setup字段。
	var fresh_engine: RefCounted = Battle.new()
	fresh_engine.set_policy(EnemyPolicy.new())
	var fresh_started: Dictionary = fresh_engine.start(started.setup,started.seed)
	_expect(fresh_started.get("started",false),"fresh engine validates the unchanged production encounter setup")
	_expect(fresh_engine.get_instance_id() != engine_id,"new battle uses a distinct authoritative engine")
	battle.bind(fresh_engine,session.campaign)
	await _wait_stable()
	_expect(not battle.get("_party_depth_plan").has("test_cache_nonce"),"new engine binding clears previous formation cache")
	diagnostics = {"engine_id":engine_id,"party":PARTY,"initial_form":"sword","projected_copy_form":"mage","actual_source_feet":before_json,"alternate_helper_feet":alternate_json,"initial_roles":initial_plan.get("roles",{}),"alternate_roles":alternate_plan.get("roles",{}),"mode":"actual production helper / factory-state snapshot projection; no gameplay switch submitted","production_rebuild_called":true,"authoritative_state_unchanged":battle.engine.snapshot() == initial_state}
	await _finish()

func _actual_feet() -> Dictionary:
	var result := {}
	for actor_id in PARTY: result[actor_id] = battle.get("_actors")[actor_id].sprite.position
	return result

func _wait_stable() -> bool:
	var deadline := Time.get_ticks_msec()+45000
	while is_instance_valid(battle) and Time.get_ticks_msec() < deadline:
		await process_frame
		var player = battle.get("_hd_player")
		if not battle.processing and (not is_instance_valid(player) or not player.is_busy()): return true
	return false

func _in_task(path: String) -> bool:
	return (path.replace("\\","/").simplify_path().trim_suffix("/")+"/").to_lower().begins_with((OS.get_environment("RPG_TEST_ROOT").replace("\\","/").simplify_path().trim_suffix("/")+"/").to_lower())

func _expect(value: bool,message: String) -> void:
	if not value:
		failures.append(message)
		printerr("DEPTH_CACHE_ASSERT_FAIL: ",message)

func _abort(message: String) -> void:
	setup_errors.append(message)
	printerr("DEPTH_CACHE_SETUP_ERROR: ",message)
	await _finish()

func _finish() -> void:
	var report := {"status":"setup-error" if not setup_errors.is_empty() else ("fail" if not failures.is_empty() else "pass"),"label":label,"mode":"production helper cache regression","diagnostics":diagnostics,"contract_failures":failures,"setup_errors":setup_errors,"user_dir":OS.get_user_data_dir(),"gameplay_switch_submitted":false}
	var file := FileAccess.open(output.path_join("cache-regression-report.json"),FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	else: setup_errors.append("scoped cache report unavailable")
	if is_instance_valid(battle):
		battle.set_process(false)
		if battle.has_method("_cancel_presentation"): battle.call("_cancel_presentation")
		var player = battle.get("_hd_player")
		if is_instance_valid(player) and player.has_method("bind_actors"): player.bind_actors({})
		var backdrop = battle.get("_world_backdrop")
		if is_instance_valid(backdrop) and backdrop.has_method("clear_visuals"): backdrop.clear_visuals()
		current_scene = null
		battle.queue_free()
		for frame in 2: await process_frame
	if session != null: session.close()
	print("DEPTH_CACHE_RESULT: ",report.status," / ",failures.size()," contract failures / ",setup_errors.size()," setup errors")
	quit(2 if not setup_errors.is_empty() else (1 if not failures.is_empty() else 0))
