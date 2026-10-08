# 实地机关纯规则测试；只能由已核验user目录的Python入口运行。
extends SceneTree
var assertions := 0
var failures: Array[String] = []
var rules: GDScript
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_expect(FileAccess.file_exists("res://scripts/campaign/mechanism_rules.gd"), "六机关必须具有可运行的纯规则")
	if failures.is_empty():
		rules = load("res://scripts/campaign/mechanism_rules.gd")
		_expect(rules.definitions().size() == 6, "登记六个实地机关")
		_expect(rules.initial().history.is_empty(), "初始不伪造机关操作")
		_test_sequences()
		_test_boundaries()
		_test_legacy_and_history()
		_test_gates()
		_test_catalog_references()
		_test_real_legacy()
	print("CAMPAIGN_MECHANISM_RULES: %d assertions, %d failures" % [assertions, failures.size()])
	for failure in failures: printerr("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)

func _saved(scene: String, choice: String = "", ferry_done: bool = false) -> Dictionary:
	var chapter := int(scene.substr(1, 1))
	var prior: String = {"C2-10":"C2-09","C3-16":"C3-14","C6-08":"C6-07","C6-09":"C6-08","C6-S03":"C6-12","C6-S04":"C6-12"}[scene]
	var events: Array = [{"id":prior,"choice":""}]
	if ferry_done: events.push_front({"id":"C3-16","choice":""})
	var world := {"night":chapter + 4,"scene_id":"night_%d" % (chapter + 4),"scene_path":"res://scenes/campaign/saga.tscn","position":[0.0,0.0,0.0],"player_x":0.0,"facing":1,"party_index":0,"story_scene":scene,"story_choice":choice,"event_flags":{},"resolved":{}}
	var saved := {"run_id":"mechanism_test","world":world,"world_history":{world.scene_id:world.duplicate(true)},"inventory":{},"gear":{},"cards":{},"roster":{},"party":["p_guard","p_mage","p_healer"],"pending_battle":{},"applied_battle_ids":["mechanism_test:1","mechanism_test:2","mechanism_test:3","mechanism_test:4","mechanism_test:5"],"saga":{"chapter":chapter,"scene":scene,"active_scene":scene,"choices":{scene:choice},"events":events,"battles":[],"battle_encounters":{},"completed":[prior],"flags":{"ferry_repaired":ferry_done},"coins":0}}
	for id in ["guard","mage","healer","ranger","swordsman","controller"]: saved.roster["p_"+id] = {"actor_id":"p_"+id,"side":"player"}
	saved["mechanisms"] = rules.migrate(saved)
	return saved

func _position(mechanism: String, action_id: String, scene: String) -> Array:
	for action in rules.definition(mechanism).actions:
		if action.id == action_id: return action.positions[scene].duplicate()
	return []

func _act(saved: Dictionary, mechanism: String, action_id: String, actor: String = "p_guard") -> Dictionary:
	var world: Dictionary = saved.world.duplicate(true)
	world.position = _position(mechanism, action_id, saved.saga.active_scene)
	world.player_x = world.position[0]
	var before := saved.duplicate(true)
	var result: Dictionary = rules.preview(saved, world, mechanism, action_id, actor)
	_expect(result.ok, "%s/%s合法操作：%s" % [mechanism,action_id,result.get("error","")])
	_expect(saved == before, "预览不修改输入")
	if not result.ok: return saved
	var candidate: Dictionary = result.candidate
	for key in saved:
		if key not in ["mechanisms","world","world_history"]: _expect(candidate[key] == saved[key], "机关不修改资源/剧情字段：" + key)
	_expect(rules.validate(candidate).is_empty(), "每步断点都能严格续读：" + str(rules.validate(candidate)))
	return candidate

func _win_alley(saved: Dictionary) -> Dictionary:
	var result := saved.duplicate(true)
	result.saga.battles.append("C6-S04")
	result.saga.battle_encounters["C6-S04"] = "saga_c6_s04"
	result.applied_battle_ids.append("mechanism_test:6")
	return result

func _test_sequences() -> void:
	for pair in [["water_echo","C2-10",""],["ferry","C3-16",""],["junction","C6-08",""],["ward_test","C6-09",""],["driftwood","C6-S03","a"],["alley","C6-S04","a"]]:
		var saved := _saved(pair[1],pair[2],pair[0] == "driftwood")
		_expect(rules.validate(saved).is_empty(), "机关开始状态合法：" + pair[0])
		var prior_size: int = saved.mechanisms.history.size()
		for action_id in rules.definition(pair[0]).steps:
			if pair[0] == "alley" and action_id == "remove_far": saved = _win_alley(saved)
			saved = _act(saved,pair[0],action_id,"p_healer" if action_id == "second_operator" else "p_guard")
		_expect(rules.view_state(saved,pair[0]).complete, "完整实地步骤到达终态：" + pair[0])
		_expect(saved.mechanisms.history.size() == prior_size + rules.definition(pair[0]).steps.size(), "每次实际操作只记录一步")
		_expect(rules.completion_errors(saved,pair[1]).is_empty(), "机关完成后才允许场次结算：" + pair[0])
		_expect(saved.saga.coins == 0 and saved.inventory.is_empty() and saved.cards.is_empty(), "零钱/零药/零收藏仍可完成实地机关")
		var visual: Dictionary = rules.view_state(saved,pair[0]).visual
		saved.saga.active_scene = ""
		_expect(rules.view_state(saved,pair[0]).visual == visual, "完成物件脱离当前场次仍显示终态")

func _test_boundaries() -> void:
	var saved := _saved("C6-08")
	var far: Dictionary = saved.world.duplicate(true)
	far.position = [100.0,0.0,100.0]
	_expect(not rules.preview(saved,far,"junction","support_rod","p_guard").ok, "距离太远不得遥控机关")
	var at: Dictionary = saved.world.duplicate(true); at.position = _position("junction","take_pin","C6-08")
	_expect(not rules.preview(saved,at,"junction","take_pin","p_guard").ok, "未托杆隔离不能取销")
	at.position = _position("junction","support_rod","C6-08")
	_expect(not rules.preview(saved,at,"junction","support_rod","unknown").ok, "操作者必须是现有身份")
	at.event_flags["forged"] = true
	_expect(not rules.preview(saved,at,"junction","support_rod","p_guard").ok, "操作位置不能夹带剧情flag")
	for id in ["support_rod","isolate","take_pin"]: saved = _act(saved,"junction",id)
	_expect(not rules.preview(saved,saved.world,"junction","support_rod","p_guard").ok, "已取销不可倒退")
	saved = _saved("C2-10")
	for id in ["observe","block"]: saved = _act(saved,"water_echo",id)
	_expect(rules.view_state(saved,"water_echo").visual.bell_stopped, "放下隔板立即停钟，听声只记录确认")
	saved = _act(saved,"water_echo","unblock")
	_expect(rules.view_state(saved,"water_echo").step == 1 and not rules.view_state(saved,"water_echo").complete, "未听完可撤隔断，仍需重新核对")
	for id in ["block","listen","unblock","listen"]: saved = _act(saved,"water_echo",id)
	saved = _act(saved,"water_echo","retry")
	_expect(rules.view_state(saved,"water_echo").step == 0 and rules.view_state(saved,"water_echo").complete, "可无收益再试且不抹去已完成验证")
	saved = _saved("C6-09")
	for id in ["position_outer","position_inner","pull_pin","check_exit"]: saved = _act(saved,"ward_test",id)
	at = saved.world.duplicate(true); at.position = _position("ward_test","second_operator","C6-09"); at.player_x = at.position[0]
	_expect(not rules.preview(saved,at,"ward_test","second_operator","p_guard").ok, "首验者不能冒充第二操作者")
	for id in ["p_mage","p_healer","p_ranger","p_swordsman","p_controller"]:
		_expect(rules.preview(saved,at,"ward_test","second_operator",id).ok, "换手不设职业门槛：" + id)
	saved = _saved("C6-S04","a")
	for id in ["prepare_cloth","cover_near"]: saved = _act(saved,"alley",id)
	at = saved.world.duplicate(true); at.position = _position("alley","remove_far","C6-S04"); at.player_x = at.position[0]
	_expect(rules.battle_errors(saved,"C6-S04").is_empty(), "备布遮近镜后可开原短战")
	_expect(not rules.preview(saved,at,"alley","remove_far","p_guard").ok, "战前或败北不能拆远镜")
	saved.pending_battle = {"encounter_id":"saga_c6_s04","battle_id":"mechanism_test:6"}
	_expect(not rules.preview(saved,at,"alley","remove_far","p_guard").ok, "待战快照不能当已胜利")
	for scene in ["C6-S03","C6-S04"]:
		var deferred := _saved(scene,"b")
		_expect(rules.completion_errors(deferred,scene).is_empty() and rules.gates(deferred,scene,"choice").is_empty(), "暂缓B不强加成功机关门槛")
		_expect(rules.targets(deferred).is_empty(), "暂缓期间不开放成功操作")

func _test_legacy_and_history() -> void:
	var repaired_dock:=_saved("C6-S03","a",true)
	_expect(not rules.targets(repaired_dock).any(func(target):return target.mechanism_id=="ferry"),"已修渡的后章现场不再堆叠无效修渡标记")
	_expect(rules.targets(repaired_dock).any(func(target):return target.mechanism_id=="driftwood"),"已修渡仍保留真实清路操作点")
	var empty := {"mechanisms":rules.initial()}
	_expect(rules.validate(empty).is_empty(), "首章无saga零状态合法")
	var saved := _saved("C6-S03","b")
	saved.saga.events.append({"id":"C6-S03","choice":"b"})
	saved.mechanisms = rules.migrate(saved)
	_expect(not saved.mechanisms.states.driftwood.complete and not saved.mechanisms.states.ferry.complete and saved.mechanisms.history.is_empty(), "旧档暂缓B不伪造修路或操作历史")
	saved.saga.events.append({"id":"C6-S03","choice":"a"})
	saved.mechanisms = rules.migrate(saved)
	_expect(saved.mechanisms.states.driftwood.complete and saved.mechanisms.states.ferry.complete and saved.mechanisms.history.is_empty(), "合法旧成功只投影共享终态，不虚构走路历史")
	_expect(rules.validate(saved).is_empty(), "旧档终态投影可独立校验")
	saved = _saved("C6-S04","a")
	for id in ["prepare_cloth","cover_near"]: saved = _act(saved,"alley",id)
	saved = _win_alley(saved)
	saved = _act(saved,"alley","remove_far")
	var forged := saved.duplicate(true)
	forged.mechanisms.history[-1].battles = 0; forged.mechanisms.history[-1].battle_id = ""
	_expect(not rules.validate(forged).is_empty(), "未来胜利不能回填战前拆远镜记录")
	for field in ["step","events","battles"]:
		forged = saved.duplicate(true); forged.mechanisms.history[-1][field] = 1.5
		_expect(not rules.validate(forged).is_empty(), "历史计数拒绝小数：" + field)
	forged = saved.duplicate(true); forged.mechanisms.states.alley.complete = true
	_expect(not rules.validate(forged).is_empty(), "终态必须能由实际动作重演得出")
	forged = saved.duplicate(true); forged.mechanisms.history[-1].position = [0.0,0.0,0.0]
	_expect(not rules.validate(forged).is_empty(), "回放历史也检查真实操作点距离")
	forged = saved.duplicate(true); forged.mechanisms.extra = true
	_expect(not rules.validate(forged).is_empty(), "未知机关字段拒绝")
	var normalized: Dictionary = rules.normalize(JSON.parse_string(JSON.stringify(saved.mechanisms)))
	saved.mechanisms = normalized
	_expect(rules.validate(saved).is_empty(), "JSON运输后规范化整数与位置，可续读而不修复非法值")
	saved = _saved("C6-08")
	saved.saga.events.append({"id":"C6-08","choice":""})
	saved.saga.active_scene = ""
	_expect(not rules.validate(saved).is_empty(), "新版本不能只添加未来完成事件跳过机关")
	saved = _saved("C6-S04","a")
	saved.saga.events.append({"id":"C6-S04","choice":"a"})
	saved = _win_alley(saved)
	saved.mechanisms = rules.migrate(saved)
	saved.mechanisms.legacy.battles = 0
	saved.mechanisms.states.alley = {"step":0,"complete":false,"first_actor":""}
	_expect(not rules.validate(saved).is_empty(), "历史完成A与其胜利必须同在迁移前缀，不能借未来胜利补记")

func _test_gates() -> void:
	var expected := {"C2-10":[7],"C3-16":[1,5],"C6-08":[12,14,17],"C6-09":[8,13]}
	for scene in expected:
		var gates: Array = rules.gates(_saved(scene),scene,"opening")
		var indices: Array = []
		for gate in gates: indices.append(gate.before_source_index)
		_expect(indices == expected[scene], "按批准来源索引暂停，不按lines数组猜：" + scene)
	var drift := _saved("C6-S03","a")
	_expect(rules.gates(drift,"C6-S03","choice").map(func(g):return g.before_source_index) == [10,17], "未修渡口先补共享结构与试航")
	drift = _saved("C6-S03","a",true)
	_expect(rules.gates(drift,"C6-S03","choice").map(func(g):return g.before_source_index) == [17], "已修渡口不重复要求补修")
	var alley := _saved("C6-S04","a")
	_expect(rules.gates(alley,"C6-S04","choice")[0].before_source_index == 8, "后巷choice行7之后保留通道尾门禁")
	_expect(rules.gates(alley,"C6-S04","aftermath").map(func(g):return g.before_source_index) == [11,15], "缺失于after_lines的11/15动作块仍是演出门禁")

func _test_catalog_references() -> void:
	var story: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/saga.json"))
	var scenes := {}
	for chapter in story.chapters:
		for scene in chapter.scenes: scenes[scene.id] = scene
	var region = load("res://scripts/campaign/saga_world.gd")
	for definition in rules.definitions():
		for gate in definition.gates:
			_expect(gate.before_source_index is int and scenes.has(gate.scene_id) and scenes[gate.scene_id].source_blocks.any(func(block):return block.source_index == gate.before_source_index), "每个停点对应真实批准来源块")
		for context in definition.contexts:
			var cells: Dictionary = region._grid(context.chapter)
			for action in definition.actions:
				var point: Array = action.positions[context.scene_id]
				_expect(cells.has(Vector2i(floori(point[0]),floori(point[2]))), "每个操作点位于现有地区可行走地面："+definition.id+"/"+action.id)
				_expect(action.visual_duration >= 1.4 if action.id in ["sail_out","sail_back"] else action.visual_duration > 0, "动作表现有独立可见时长，船去回不瞬移")

func _test_real_legacy() -> void:
	var path := OS.get_environment("MECHANISM_CHECKPOINT")
	if path.is_empty(): return
	var before_hash := FileAccess.get_sha256(path)
	var store = load("res://scripts/rpg/save_store.gd").new()
	var decoded: Dictionary = store._decode(FileAccess.get_file_as_string(path))
	_expect(decoded.ok, "真实旧检查点先经当前Store严格校验："+str(decoded.get("error","")))
	if not decoded.ok: return
	var saved: Dictionary = decoded.snapshot
	saved["mechanisms"] = rules.migrate(saved)
	_expect(saved.mechanisms.history.is_empty(), "真实旧档投影没有编造操作历史")
	_expect(rules.validate(saved).is_empty(), "真实事件前缀可投影机关终态")
	var start := Time.get_ticks_usec()
	for unused in range(20): rules.validate(saved)
	print("MECHANISM_LEGACY_VALIDATE_US: ", (Time.get_ticks_usec()-start)/20, " events=",saved.saga.events.size())
	_expect(FileAccess.get_sha256(path) == before_hash, "只读投影保持原检查点字节")
