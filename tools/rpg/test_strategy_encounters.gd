# 固定威胁与明确奖励的只读测试，不启动战斗也不写玩家存档。
extends SceneTree

const Catalog = preload("res://scripts/rpg/catalog.gd")
const BossPolicy = preload("res://scripts/rpg/boss_policy.gd")
var rules: GDScript
var catalog: RefCounted
var assertions := 0
var failures: Array[String] = []

func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1":
		printerr("FAIL: 请经隔离Python入口运行固定遭遇测试")
		quit(1)
		return
	_expect(FileAccess.file_exists("res://scripts/rpg/strategy_encounters.gd"), "正式遭遇需要可运行的无等级威胁规则")
	if failures.is_empty():
		rules = load("res://scripts/rpg/strategy_encounters.gd")
		catalog = Catalog.new()
		var errors: Array[String] = catalog.load_all()
		_expect(errors.is_empty(), "使用真实目录，数据引用合法：" + str(errors))
		if errors.is_empty():
			_test_all_profiles()
			_test_fixed_values()
			_test_rejected_actors()
			_test_mutation_safety()
			_test_gatekeeper_phase_speed()
	print("RPG_STRATEGY_ENCOUNTERS: %d assertions, %d failures" % [assertions, failures.size()])
	for failure in failures: printerr("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)

func _formal_ids() -> Array[String]:
	var result: Array[String] = []
	for id in catalog.get_ids("encounters"):
		if id.begins_with("campaign_night_") or id.begins_with("saga_"): result.append(id)
	return result

func _test_all_profiles() -> void:
	var formal := _formal_ids()
	_expect(formal.size() == 31, "正式遭遇覆盖首章五夜与后六章26场")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rpg/strategy_encounters.json"))
	_expect(document.schema_version == 1 and document.definitions.size() == 31, "固定威胁配置没有漏场或混入试玩场")
	for id in formal:
		var definition: Dictionary = rules.definition(id)
		_expect(not definition.is_empty(), "正式场次都有固定威胁：" + id)
		if definition.is_empty(): continue
		var source: Dictionary = catalog.get_definition("encounters", id)
		_expect(definition.enemy_ids == source.enemy_ids, "保留敌人次序与重复数量：" + id)
		var rewards: Dictionary = rules.rewards(id)
		_expect(rewards.size() == 4 and rewards.has_all(["coins", "gear", "items", "cards"]), "奖励严格为四类：" + id)
		_expect(rewards.coins is int and rewards.coins >= 0, "明确银钱为非负整数：" + id)
		_expect(rewards.gear == source.get("loot", {}).get("gear", {}), "仅复制既有正式装备掉落：" + id)
		_expect(rewards.items.is_empty() and rewards.cards.is_empty(), "不凭空赠送道具或卡：" + id)
		for gear_id in rewards.gear:
			_expect(not catalog.get_definition("equipment", gear_id).is_empty() and rewards.gear[gear_id] is int and rewards.gear[gear_id] > 0, "战利品实际目录可用：" + gear_id)
		for index in definition.enemy_ids.size():
			var enemy_id: String = definition.enemy_ids[index]
			var actor_id := "e_%02d_%s" % [index + 1, enemy_id]
			var actor: Dictionary = rules.enemy_actor(id, enemy_id, actor_id, catalog)
			_expect(not actor.is_empty(), "固定敌人创建成功：" + id + "/" + enemy_id)
			if actor.is_empty(): continue
			_expect(actor.actor_id == actor_id and actor.class_id == enemy_id and actor.side == "enemy", "敌方身份与永久ID保留")
			_expect(not actor.has("level") and not actor.has("xp") and actor.threat_version == 1 and actor.threat_profile == id, "敌人只记录明确威胁来源")
			_expect(actor.stats == definition.enemy_stats[enemy_id] and actor.hp == actor.stats.hp and actor.mp == actor.stats.mp, "初始资源来自固定属性")
			var reasons: Array[String] = rules.validate_actor(actor, catalog)
			_expect(reasons.is_empty(), "新建威胁敌人通过校验：" + str(reasons))
			for skill_id in actor.skill_ids: _expect(not catalog.get_definition("abilities", skill_id).is_empty(), "敌技能指向真实目录：" + skill_id)
			for field in ["equipment", "branch", "shield", "cooldown_until", "intent", "boss"]:
				_expect(actor[field] is Dictionary and actor[field].is_empty(), "新建战斗字典为空：" + field)
			_expect(actor.statuses.is_empty() and actor.slot_count == 0 and actor.opportunity_count == 0 and actor.revived_round == -1, "新建敌人的状态及行动时钟初始化")
			actor.hp = 0
			actor.mp = 0
			actor.statuses = [{"id": "slow", "source_id": "p_controller", "magnitude": 0.2, "clock": "round_snapshot", "remaining": 1, "generation": 1, "applied_slot": 0}]
			actor.slot_count = 2
			actor.opportunity_count = 2
			actor.boss = {"phase": 1}
			_expect(rules.validate_actor(actor, catalog).is_empty(), "固定来源校验允许当前资源、状态、时钟和Boss阶段变化")

func _test_fixed_values() -> void:
	var hound: Dictionary = rules.enemy_actor("campaign_night_1", "hound", "e_hound", catalog)
	_expect(hound.stats == {"hp": 180, "mp": 0, "atk": 45, "matk": 10, "def": 20, "mdef": 15, "spd": 40}, "首章猎犬维持已有固定威胁基线")
	var paper: Dictionary = rules.enemy_actor("saga_c3_03", "saga_paper_soldier", "e_paper", catalog)
	_expect(paper.stats == {"hp": 160, "mp": 33, "atk": 34, "matk": 20, "def": 26, "mdef": 26, "spd": 25}, "第三章纸兵固定值与原批准数值一致，包括半值取整")
	_expect(rules.rewards("campaign_night_2") == {"coins": 0, "gear": {"exorcism_sword": 1}, "items": {}, "cards": {}}, "首章不新增银钱，保留退邪剑")
	_expect(rules.rewards("saga_c2_03").coins == 59, "后章普通场明确给59银钱")
	_expect(rules.rewards("saga_c2_12").coins == 105, "后章Boss明确给105银钱")
	_expect(rules.rewards("saga_c7_13").coins == 115, "终局明确给115银钱")
	for id in ["missing", "slice_1", "elite_test", ""]:
		_expect(rules.definition(id).is_empty() and rules.rewards(id).is_empty(), "未知与历史遭遇不会进入正式策略配置：" + id)
		_expect(rules.enemy_actor(id, "hound", "e_hound", catalog).is_empty(), "未登记遭遇不能创建正式敌人：" + id)
	_expect(rules.enemy_actor("campaign_night_1", "gatekeeper", "e_wrong", catalog).is_empty(), "拒绝将场外敌种注入遭遇")
	_expect(rules.enemy_actor("campaign_night_1", "hound", "", catalog).is_empty(), "拒绝缺少永久ID的敌人")
	_expect(rules.enemy_actor("campaign_night_1", "hound", "e_hound", null).is_empty(), "没有目录不能臆造敌技能")

func _test_rejected_actors() -> void:
	var base: Dictionary = rules.enemy_actor("campaign_night_1", "hound", "e_hound", catalog)
	for patch in [{"threat_version": 2}, {"threat_version": 1.0}, {"threat_profile": "missing"}, {"threat_profile": "slice_1"}, {"threat_profile": 1}, {"class_id": "gatekeeper"}, {"side": "player"}, {"actor_id": ""}, {"level": 5}, {"xp": 40}, {"equipment": {"weapon": "standard_weapon"}}, {"branch": {"id": "power"}}]:
		var actor := base.duplicate(true)
		actor.merge(patch, true)
		var before := actor.duplicate(true)
		_expect(not rules.validate_actor(actor, catalog).is_empty(), "拒绝伪造威胁字段：" + str(patch))
		_expect(actor == before, "校验不修复或改写输入")
	var forged := base.duplicate(true)
	forged.stats.atk += 1
	_expect(not rules.validate_actor(forged, catalog).is_empty(), "拒绝篡改固定敌方属性")
	forged = base.duplicate(true)
	forged.stats.atk = 45.0
	_expect(not rules.validate_actor(forged, catalog).is_empty(), "敌方属性必须为整数")
	forged = base.duplicate(true)
	forged.skill_ids = ["shield_stance"]
	_expect(not rules.validate_actor(forged, catalog).is_empty(), "拒绝替换成其他敌种技能")
	forged = base.duplicate(true)
	forged.weaknesses = []
	_expect(not rules.validate_actor(forged, catalog).is_empty(), "拒绝伪造敌人基础弱点")
	forged = base.duplicate(true)
	forged.hp = forged.stats.hp + 1
	_expect(not rules.validate_actor(forged, catalog).is_empty(), "当前资源可变但不能超过固定上限")
	_expect(not rules.validate_actor({}, catalog).is_empty(), "空角色拒绝且不崩溃")

func _test_mutation_safety() -> void:
	var definition: Dictionary = rules.definition("campaign_night_1")
	definition.enemy_stats.hound.hp = 999
	definition.enemy_ids.clear()
	_expect(rules.definition("campaign_night_1").enemy_stats.hound.hp == 180 and rules.definition("campaign_night_1").enemy_ids.size() == 2, "查询定义返回深复制")
	var rewards: Dictionary = rules.rewards("campaign_night_2")
	rewards.gear.exorcism_sword = 9
	rewards.coins = 999
	_expect(rules.rewards("campaign_night_2").gear.exorcism_sword == 1 and rules.rewards("campaign_night_2").coins == 0, "奖励查询返回深复制")
	var actor: Dictionary = rules.enemy_actor("campaign_night_1", "hound", "e_first", catalog)
	actor.stats.hp = 3
	actor.skill_ids.clear()
	_expect(rules.enemy_actor("campaign_night_1", "hound", "e_second", catalog).stats.hp == 180 and not rules.enemy_actor("campaign_night_1", "hound", "e_second", catalog).skill_ids.is_empty(), "敌人实例互不共享属性或技能数组")

func _test_gatekeeper_phase_speed() -> void:
	var actor: Dictionary = rules.enemy_actor("campaign_night_5", "gatekeeper", "e_gatekeeper", catalog)
	var starting_speed: int = actor.stats.spd
	var bonus: int = catalog.get_definition("enemies", "gatekeeper").boss.phase_spd_bonus
	BossPolicy.initialize(actor)
	actor.hp = floori(actor.stats.hp * 0.4)
	var state := {"actors": {"e_gatekeeper": actor}, "round": 3}
	var events: Array[Dictionary] = BossPolicy.observe_phase(state, "e_gatekeeper")
	_expect(events.size() == 1 and actor.boss.phase == 1 and actor.boss.pending_phase == 2, "真实阶段观察只登记下一轮转换")
	_expect(actor.stats.spd == starting_speed and rules.validate_actor(actor, catalog).is_empty(), "阶段待生效时仍要求原固定速度")
	_expect(BossPolicy.on_round_start(state, "e_gatekeeper").is_empty() and actor.stats.spd == starting_speed, "同轮不能提前取得阶段加速")
	state.round = 4
	events = BossPolicy.on_round_start(state, "e_gatekeeper")
	_expect(events.size() == 1 and actor.boss.phase == 2 and actor.boss.pending_phase == 0 and actor.boss.pending_phase_round == -1, "真实轮首完成守关者第二阶段转换")
	_expect(actor.stats.spd == starting_speed + bonus, "真实Boss规则与目录登记的速度加成一致")
	var before := actor.duplicate(true)
	_expect(rules.validate_actor(actor, catalog).is_empty(), "固定威胁允许真实第二阶段精确速度增量")
	_expect(actor == before, "阶段属性校验仍然只读")
	state.round = 5
	_expect(BossPolicy.on_round_start(state, "e_gatekeeper").is_empty() and actor.stats.spd == starting_speed + bonus, "第二阶段只增加一次速度")
	_expect(rules.validate_actor(actor, catalog).is_empty(), "阶段后续轮仍接受已提交的精确速度")
	for wrong_speed in [starting_speed, starting_speed + bonus - 1, starting_speed + bonus + 1, starting_speed + bonus * 2]:
		var forged := actor.duplicate(true)
		forged.stats.spd = wrong_speed
		_expect(not rules.validate_actor(forged, catalog).is_empty(), "第二阶段拒绝缺失、偏差或重复速度加成")
	for stat in ["hp", "mp", "atk", "matk", "def", "mdef"]:
		var forged := actor.duplicate(true)
		forged.stats[stat] += 1
		_expect(not rules.validate_actor(forged, catalog).is_empty(), "阶段转换不放宽其他固定属性：" + stat)
	for patch in [{"phase": 1}, {"phase": 2.0}, {"pending_phase": 2}, {"pending_phase_round": 3}]:
		var forged := actor.duplicate(true)
		forged.boss.merge(patch, true)
		_expect(not rules.validate_actor(forged, catalog).is_empty(), "未明确完成第二阶段不能套用速度例外：" + str(patch))
	var forged := actor.duplicate(true)
	forged.boss = {"phase": 2}
	_expect(not rules.validate_actor(forged, catalog).is_empty(), "单独伪造phase标签不取得阶段速度例外")
	for pair in [["campaign_night_1", "hound"], ["saga_c2_12", "saga_borrowed_voice"]]:
		var other: Dictionary = rules.enemy_actor(pair[0], pair[1], "e_other", catalog)
		other.boss = actor.boss.duplicate(true)
		other.stats.spd += bonus
		_expect(not rules.validate_actor(other, catalog).is_empty(), "其他敌种即使伪造守关者phase2也不获得速度例外：" + pair[1])
