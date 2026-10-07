# 七形态技法验证真实指令、条件不成立分支与资源闭环，不以文案代替规则。
extends RefCounted
const F = preload("res://tools/rpg/fixtures.gd")
const H = preload("res://tools/rpg/test_engine.gd")
const R = preload("res://tools/rpg/test_refinements.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const BattleEngine = preload("res://scripts/rpg/battle_engine.gd")
const Status = preload("res://scripts/rpg/status_rules.gd")
const Replay = preload("res://scripts/rpg/replay.gd")
const Presenter = preload("res://scripts/rpg/ui/battle_presenter.gd")
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
const CASES := [
	[0, "armor_break", 4, 8, 1], [0, "sweep", 5, 14, 2],
	[1, "hunt", 4, 9, 0], [1, "smoke_screen", 5, 9, 2],
	[2, "iron_wall", 4, 12, 2], [2, "taunt", 5, 5, 1],
	[3, "sweep", 4, 14, 1], [3, "battle_spirit", 5, 8, 2],
	[4, "flame_wave", 4, 20, 1], [4, "ice_arrow", 5, 12, 1],
	[5, "cleanse", 4, 8, 0], [5, "holy_shield", 5, 12, 1],
	[6, "slow", 4, 12, 1], [6, "seal", 5, 12, 2]
]

static func run() -> Array[String]:
	var failures: Array[String] = []
	F.assertion_count = 0
	var catalog := Catalog.new()
	F.expect(catalog.load_all().is_empty(), "技法目录加载", failures)
	for row in CASES:
		var actor: Dictionary = R._actor(catalog, R.CASES[row[0]])
		var skill: Dictionary = catalog.skill_for(actor, row[1])
		F.expect([skill.mp_cost, skill.cooldown] == [row[3], row[4]], "技法费用/CD：" + row[1] + str(row[0]), failures)
		F.expect(skill.get("technique", {}).get("unlock_level", 0) == row[2], "技法开放等级：" + row[1], failures)
		actor.level = row[2] - 1
		F.expect(not catalog.skill_for(actor, row[1]).has("technique"), "提前等级不获得技法：" + row[1], failures)
		actor.level = 5
		var enemy := F.enemy("hound", "enemy")
		enemy.stats.hp = 3000
		enemy.hp = 3000
		var ally := F.actor("guard", "ally")
		ally.hp = 50
		Status.apply(ally, F.status("weaken", 0.2, 2, "enemy"))
		var engine = H._selection(BattleEngine, actor, [enemy, ally])
		var target: Array = ["ally"] if skill.target_rule == "single_ally" else (["enemy"] if skill.target_rule == "single_enemy" else [])
		var command := H._command(engine, "skill", row[1], target)
		var before: Dictionary = engine.snapshot()
		var preview: Dictionary = engine.preview(command)
		F.expect(preview.legal, "技法真实预览合法：" + row[1], failures)
		F.expect(preview.get("technique", {}) == skill.get("technique", {}), "预览携带相同技法说明", failures)
		engine.preview(command)
		F.expect(engine.snapshot() == before, "技法预览无副作用", failures)
		var low := before.duplicate(true)
		low.actors[actor.actor_id].mp = row[3] - 1
		engine.restore(low)
		F.expect(not engine.submit(command).accepted and engine.snapshot() == low, "回馈不能预支/MP不足零副作用", failures)
		engine.restore(before)
		var result: Dictionary = engine.submit(command)
		F.expect(result.accepted, "技法真实执行：" + row[1], failures)
		if not result.accepted: continue
		F.expect(engine.snapshot().actors[actor.actor_id].mp == actor.mp - row[3], "无条件收益时按技法实际收费", failures)
		F.expect(engine.snapshot().actors[actor.actor_id].cooldown_until[row[1]] == before.actors[actor.actor_id].slot_count + row[4] + 1, "技法CD按本人行动槽设置", failures)
		F.expect(not engine.submit(command).accepted, "重复技法指令不能重复领取收益", failures)
		var commands: Array[Dictionary] = [command]
		var events: Array[Dictionary] = []
		events.assign(result.events)
		F.expect(Replay.verify(Replay.record(before, commands, events), catalog).matches, "技法重放确定：" + row[1], failures)
		Kit.init()
		var card: String = Presenter.TARGET_SHORT[skill.target_rule] + " · " + Presenter.card_summary(skill, preview, catalog)
		F.expect(Kit.font.get_string_size(card, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x <= 268, "技法四卡不溢出：" + row[1] + " " + card, failures)
	_test_ranger_refund(catalog, failures)
	_test_multi_target_trade(catalog, failures)
	_test_cleanse(catalog, failures)
	_test_positive_effects(catalog, failures)
	_test_self_clocks(catalog, failures)
	_test_fingerprint(catalog, failures)
	_test_validation(failures)
	_test_refresh_and_caps(catalog, failures)
	_test_art_catalog(catalog, failures)
	_test_voice_primary_memory(catalog, failures)
	_test_router_catalog_fingerprint(failures)
	print("RPG 技法断言：", F.assertion_count)
	return failures

static func _test_ranger_refund(catalog: RefCounted, failures: Array[String]) -> void:
	var actor: Dictionary = R._actor(catalog, R.CASES[1])
	var enemy := F.enemy("hound", "enemy")
	enemy.hp = 1
	Status.apply(enemy, F.status("mark", 1, 3, actor.actor_id))
	var engine = H._selection(BattleEngine, actor, [enemy])
	var command := H._command(engine, "skill", "hunt", ["enemy"])
	var preview: Dictionary = engine.preview(command)
	var result: Dictionary = engine.submit(command)
	F.expect(result.accepted and engine.snapshot().actors[actor.actor_id].mp == actor.mp - 6, "猎杀对已标记目标击杀仍只返3MP，净耗6", failures)
	F.expect(H._event(preview.effects, "mp_restored").get("payload", {}).get("actual", 0) == 3, "满MP出手预览先扣费，准确显示返还3MP", failures)
	F.expect(result.events.filter(func(e): return e.type == "mp_restored").size() == 1, "标记击杀返还一次", failures)

static func _test_multi_target_trade(catalog: RefCounted, failures: Array[String]) -> void:
	var actor: Dictionary = R._actor(catalog, R.CASES[0])
	var first := F.enemy("hound", "a")
	var second := F.enemy("hound", "b")
	for enemy in [first, second]:
		enemy.stats.hp = 3000
		enemy.hp = 3000
	Status.apply(first, F.status("armor_break", 0.25, 2, actor.actor_id))
	var engine = H._selection(BattleEngine, actor, [first, second])
	F.expect(engine.submit(H._command(engine, "skill", "sweep")).accepted, "凛音断阵横扫全敌", failures)
	var after: Dictionary = engine.snapshot()
	F.expect(F.find_status(after.actors.a, "armor_break").is_empty() and F.find_status(after.actors.a, "slow").get("remaining") == 1, "已破甲目标转换为一次未来轮序缓速", failures)
	F.expect(F.find_status(after.actors.b, "slow").is_empty(), "未破甲目标不能免费缓速", failures)
	var snapshots := Status.begin_round(after.actors)
	F.expect(H._event(snapshots, "round_snapshot").payload.speed_reduction == 0.3, "断阵只在下一轮快照降低速度", failures)
	Status.end_round(after.actors)
	F.expect(F.find_status(after.actors.a, "slow").is_empty(), "一次快照缓速按时消退", failures)

static func _test_cleanse(catalog: RefCounted, failures: Array[String]) -> void:
	for afflicted in [false, true]:
		var actor: Dictionary = R._actor(catalog, R.CASES[5])
		var ally := F.actor("guard", "ally")
		ally.hp = 50
		if afflicted: Status.apply(ally, F.status("weaken", 0.2, 2, "enemy"))
		var engine = H._selection(BattleEngine, actor, [ally, F.enemy("hound", "enemy")])
		var result: Dictionary = engine.submit(H._command(engine, "skill", "cleanse", ["ally"]))
		F.expect(result.accepted, "净化仍可按原规则使用", failures)
		F.expect(engine.snapshot().actors.ally.hp == (72 if afflicted else 50), "只有施法前确有可净化负面才治疗22", failures)
		F.expect(engine.snapshot().actors.ally.statuses.is_empty(), "净化先移除负面，不破坏触发快照", failures)

static func _test_positive_effects(catalog: RefCounted, failures: Array[String]) -> void:
	# 可施法时的七种软负面全部净化；眩晕仍会在选择前剥夺行动。
	var guard: Dictionary = R._actor(catalog, R.CASES[2])
	for id in ["burn", "weaken", "armor_break", "magic_break", "slow", "mark", "taunt"]:
		Status.apply(guard, F.status(id, 1.0 if id in ["mark", "taunt", "burn"] else 0.2, 3, "enemy"))
	var enemy := F.enemy("hound", "enemy")
	enemy.stats.hp = 3000
	enemy.hp = 3000
	var engine = H._selection(BattleEngine, guard, [enemy])
	var result: Dictionary = engine.submit(H._command(engine, "skill", "iron_wall"))
	F.expect(result.accepted and engine.snapshot().actors.p_guard.statuses.is_empty(), "整阵铁壁真实移除七种可行动软负面", failures)
	F.expect(engine.snapshot().actors.p_guard.shield.amount == 70, "整阵保持原70护盾", failures)
	for shielded in [false, true]:
		guard = R._actor(catalog, R.CASES[2])
		if shielded: guard.shield = F.shield(40, 2, guard.actor_id)
		engine = H._selection(BattleEngine, guard, [enemy])
		engine.submit(H._command(engine, "skill", "taunt", ["enemy"]))
		F.expect(not F.find_status(engine.snapshot().actors.enemy, "weaken").is_empty() == shielded, "镇锋只在施法前有盾时压制输出", failures)
	for prepared in [false, true]:
		var rinne: Dictionary = R._actor(catalog, R.CASES[0])
		if prepared: Status.apply(rinne, F.status("battle_spirit", 0.4, 2, rinne.actor_id))
		engine = H._selection(BattleEngine, rinne, [enemy])
		engine.submit(H._command(engine, "skill", "armor_break", ["enemy"]))
		F.expect(not F.find_status(engine.snapshot().actors.enemy, "weaken").is_empty() == prepared, "崩刃须先准备战意", failures)
		F.expect(F.find_status(engine.snapshot().actors.enemy, "armor_break").get("remaining") == 2, "崩刃不改变原破甲时长", failures)
	# 各AOE条件逐目标判断，不能因其中一人满足就向全体扩散。
	for row in [[3, "sweep", "burn", "armor_break"], [4, "flame_wave", "burn", "burn"], [6, "slow", "weaken", "magic_break"]]:
		var actor: Dictionary = R._actor(catalog, R.CASES[row[0]])
		var marked := enemy.duplicate(true)
		marked.actor_id = "a"
		var clear := enemy.duplicate(true)
		clear.actor_id = "b"
		Status.apply(marked, F.status(row[2], 3.0 if row[2] == "burn" else 0.2, 1, actor.actor_id))
		engine = H._selection(BattleEngine, actor, [marked, clear])
		var preview: Dictionary = engine.preview(H._command(engine, "skill", row[1]))
		result = engine.submit(H._command(engine, "skill", row[1]))
		F.expect(result.accepted, "条件AOE真实结算：" + row[1], failures)
		var current: Dictionary = engine.snapshot()
		F.expect(not F.find_status(current.actors.a, row[3]).is_empty() and F.find_status(current.actors.b, row[3]).is_empty(), "AOE只奖励正确目标：" + row[1], failures)
		for event in preview.effects:
			if event.type == "status_applied": F.expect(result.events.any(func(value): return value.type == event.type and value.target_id == event.target_id and value.payload == event.payload), "条件AOE状态预览与实战完全一致", failures)
		if row[1] == "flame_wave":
			var burn := F.find_status(current.actors.a, "burn")
			F.expect(is_equal_approx(burn.magnitude, actor.stats.matk * 0.2) and burn.remaining == 3, "续燎将弱火种升级为当前术攻20%/3行动", failures)
	# 灼烧换虚弱严格发生在冰矢伤害之后；不因自己刚追加的缓速重复触发。
	var mage: Dictionary = R._actor(catalog, R.CASES[4])
	var burning := enemy.duplicate(true)
	Status.apply(burning, F.status("burn", 5.0, 3, mage.actor_id))
	engine = H._selection(BattleEngine, mage, [burning])
	result = engine.submit(H._command(engine, "skill", "ice_arrow", ["enemy"]))
	var after: Dictionary = engine.snapshot()
	F.expect(F.find_status(after.actors.enemy, "burn").is_empty() and F.find_status(after.actors.enemy, "weaken").get("remaining") == 2 and F.find_status(after.actors.enemy, "slow").get("remaining") == 1, "熄焰消耗灼烧，保留缓速并附2行动虚弱", failures)
	var types: Array = result.events.map(func(value): return value.type)
	F.expect(types.find("damage") < types.find("status_removed"), "熄焰先造成冰伤再消耗火种", failures)
	var controller: Dictionary = R._actor(catalog, R.CASES[6])
	var broken := enemy.duplicate(true)
	Status.apply(broken, F.status("magic_break", 0.25, 2, controller.actor_id))
	Status.apply(broken, F.status("awake", 1, 2, broken.actor_id))
	engine = H._selection(BattleEngine, controller, [broken])
	result = engine.submit(H._command(engine, "skill", "seal", ["enemy"]))
	F.expect(result.accepted and engine.snapshot().actors.p_controller.mp == controller.mp - 9, "解印对已破魔者净耗9MP，眩晕免疫不吞回馈", failures)
	F.expect(F.find_status(engine.snapshot().actors.enemy, "stun").is_empty(), "解印不绕过清醒眩晕免疫", failures)
	var immune := enemy.duplicate(true)
	Status.apply(immune, F.status("awake", 1, 2, immune.actor_id))
	engine = H._selection(BattleEngine, controller, [immune])
	var unchanged: Dictionary = engine.snapshot()
	F.expect(not engine.submit(H._command(engine, "skill", "seal", ["enemy"])).accepted and engine.snapshot() == unchanged, "封缄控制全免疫且无回馈条件时零消耗", failures)
	# 定神是预防新眩晕，不能当成净化已存在的眩晕。
	var healer: Dictionary = R._actor(catalog, R.CASES[5])
	var ally := F.actor("guard", "ally")
	Status.apply(ally, F.status("stun", 1, 1, "enemy"))
	engine = H._selection(BattleEngine, healer, [ally, enemy])
	engine.submit(H._command(engine, "skill", "holy_shield", ["ally"]))
	after = engine.snapshot()
	F.expect(not F.find_status(after.actors.ally, "stun").is_empty() and F.find_status(after.actors.ally, "awake").get("remaining") == 1, "定神仍保留已有眩晕", failures)
	F.expect(not Status.apply(after.actors.ally, F.status("stun", 1, 1, "enemy")).applied, "定神在有效期拒绝新的眩晕", failures)

static func _test_self_clocks(catalog: RefCounted, failures: Array[String]) -> void:
	for row in [[1, "smoke_screen", 0.25], [3, "battle_spirit", 0.4]]:
		var actor: Dictionary = R._actor(catalog, R.CASES[row[0]])
		var enemy := F.enemy("hound", "enemy")
		enemy.stats.hp = 3000
		enemy.hp = 3000
		var engine = H._selection(BattleEngine, actor, [enemy])
		engine.submit(H._command(engine, "skill", row[1]))
		F.expect(F.find_status(engine.snapshot().actors[actor.actor_id], "battle_spirit").get("remaining") == (1 if row[0] == 1 else 2), "新自增益不在施法槽立刻扣时长", failures)
		H._next_actor(engine, actor.actor_id, failures)
		if row[0] == 3:
			var before: Dictionary = engine.snapshot()
			var switch := H._command(engine, "switch_form")
			switch["form_id"] = "mage"
			F.expect(engine.submit(switch).accepted, "焰衣后下一行动可切法形", failures)
			var after: Dictionary = engine.snapshot()
			F.expect(after.actors[actor.actor_id].mp == before.actors[actor.actor_id].mp and after.actors[actor.actor_id].hp == before.actors[actor.actor_id].hp and after.actors[actor.actor_id].cooldown_until == before.actors[actor.actor_id].cooldown_until and after.actors[actor.actor_id].shield == before.actors[actor.actor_id].shield, "焰衣切形共享HP/MP/CD/盾", failures)
		var command := H._command(engine, "attack_magic" if row[0] == 3 else "attack_physical", "", ["enemy"])
		var preview: Dictionary = engine.preview(command)
		F.expect(is_equal_approx(H._event(preview.effects, "damage").payload.factors.output_bonus, row[2]), "自增益真实覆盖下一次出手", failures)
		engine.submit(command)
		if row[0] == 1: F.expect(F.find_status(engine.snapshot().actors[actor.actor_id], "battle_spirit").is_empty(), "伏弓战意在下一行动后到期", failures)
		else: F.expect(engine.snapshot().actors[actor.actor_id].shield.is_empty(), "焰衣护盾在下一行动后到期", failures)

static func _test_fingerprint(catalog: RefCounted, failures: Array[String]) -> void:
	var actor: Dictionary = R._actor(catalog, R.CASES[0])
	var engine = H._selection(BattleEngine, actor, [F.enemy("hound", "enemy")])
	var before: Dictionary = engine.snapshot()
	var command := H._command(engine, "skill", "armor_break", ["enemy"])
	var result: Dictionary = engine.submit(command)
	var commands: Array[Dictionary] = [command]
	var events: Array[Dictionary] = []
	events.assign(result.events)
	var recording := Replay.record(before, commands, events, catalog)
	F.expect(recording.get("mechanics_fingerprint", "").length() == 64, "新重放携带目录SHA256", failures)
	var moved := JSON.parse_string(JSON.stringify(recording, "", true, true)) as Dictionary
	F.expect(Replay.verify(moved, catalog).get("fingerprint_verified", false), "新重放JSON运输后指纹确定", failures)
	recording.mechanics_fingerprint = "different"
	F.expect(not Replay.verify(recording, catalog).matches, "不同技能指纹在重放前明确拒绝", failures)
	recording.erase("mechanics_fingerprint")
	var legacy := Replay.verify(recording, catalog)
	F.expect(legacy.matches and legacy.get("legacy_unfingerprinted", false), "旧无指纹重放仍按记录事件严格校验并标明旧格式", failures)
	recording.events[0].type = "tampered"
	F.expect(not Replay.verify(recording, catalog).matches, "旧无指纹不能跳过事件完整性校验", failures)

static func _test_validation(failures: Array[String]) -> void:
	for row in [
		["missing", func(d): d.definitions[0].erase("techniques")],
		["wrong_skill", func(d): d.definitions[0].techniques[0].skill_id = "firebolt"],
		["duplicate", func(d): d.definitions[0].techniques[1].skill_id = "armor_break"],
		["early", func(d): d.definitions[0].techniques[0].unlock_level = 2],
		["bad_cost", func(d): d.definitions[0].techniques[0].mp_cost_add = -1],
		["gate", func(d): d.definitions[0].techniques[0].extra_effects[0].requires = {"missing": true}],
		["reward", func(d): d.definitions[1].techniques[0].extra_effects[0].fixed = 99],
		["zero_reward", func(d): d.definitions[1].techniques[0].extra_effects[0].fixed = 0],
		["duplicate_reward", func(d): d.definitions[1].techniques[0].extra_effects.append(d.definitions[1].techniques[0].extra_effects[0].duplicate(true))],
		["recipient", func(d): d.definitions[1].techniques[0].extra_effects[0].recipient = "all_allies"]
	]:
		var root := F.write_catalog_copy("technique_" + row[0])
		var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rpg/character_refinements.json"))
		row[1].call(document)
		var file := FileAccess.open(root.path_join("character_refinements.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(document))
		file.close()
		var catalog := Catalog.new()
		F.expect(not catalog.load_all(root).is_empty() and catalog.get_ids("skills").is_empty(), "非法技法目录整体失败关闭：" + row[0], failures)

static func _test_refresh_and_caps(catalog: RefCounted, failures: Array[String]) -> void:
	for magnitude in [13.0, 20.0]:
		var actor: Dictionary = R._actor(catalog, R.CASES[4])
		var enemy := F.enemy("hound", "enemy")
		enemy.stats.hp = 3000
		enemy.hp = 3000
		Status.apply(enemy, F.status("burn", magnitude, 1, actor.actor_id, {"base": magnitude}))
		var engine = H._selection(BattleEngine, actor, [enemy])
		var previous := F.find_status(engine.snapshot().actors.enemy, "burn").duplicate(true)
		engine.submit(H._command(engine, "skill", "flame_wave"))
		var after: Dictionary = engine.snapshot()
		var current := F.find_status(after.actors.enemy, "burn")
		if magnitude == 20.0: F.expect(current == previous, "续燎不能覆盖或延长强于当前术攻20%的灼烧", failures)
		else:
			F.expect(current.remaining == 3 and current.generation != previous.generation, "续燎等强刷新至3次目标行动且更新代次", failures)
			var token := Status.begin_slot(after.actors.enemy)
			Status.end_slot(after.actors.enemy, token)
			F.expect(F.find_status(after.actors.enemy, "burn").remaining == 2, "续燎下一真实行动产生灼烧并正常扣一次", failures)
	# 目录夹具把猎杀变为全体，用相同实际引擎验证施法者回馈按命令而非按目标计数。
	var root := F.write_catalog_copy("source_refund_cap", "skills", func(document):
		for skill in document.definitions:
			if skill.id == "hunt":
				skill.target_rule = "all_enemies"
				skill.single_direct = false
				skill.effects[0].single_direct = false
	)
	var file := FileAccess.open(root.path_join("character_refinements.json"), FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string("res://data/rpg/character_refinements.json"))
	file.close()
	var custom := Catalog.new()
	F.expect(custom.load_all(root).is_empty(), "返还上限使用合法目录夹具", failures)
	var actor: Dictionary = R._actor(catalog, R.CASES[1])
	actor.stats.spd = 999
	var actors := {actor.actor_id: actor}
	for id in ["a", "b"]:
		var enemy := F.enemy("hound", id)
		Status.apply(enemy, F.status("mark", 1, 3, actor.actor_id))
		actors[id] = enemy
	var engine := BattleEngine.new(custom)
	F.expect(engine.start({"actors": actors, "inventory": {}}, 7).started, "多目标返还夹具实际启动", failures)
	engine.advance()
	var result := engine.submit(H._command(engine, "skill", "hunt"))
	F.expect(result.accepted and result.events.filter(func(event): return event.type == "mp_restored").size() == 1 and engine.snapshot().actors[actor.actor_id].mp == actor.mp - 6, "两个标记目标只返一次3MP，不能乘以目标数", failures)

static func _test_art_catalog(catalog: RefCounted, failures: Array[String]) -> void:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/characters/skill-art-briefs-2026-10-07.json"))
	F.expect(document.get("records", []).size() == 28, "逐形态美术委托完整覆盖28卡位", failures)
	for row in document.get("records", []):
		var actor := F.actor("mage" if row.identity_id == "homura" else row.class_id, "p_mage" if row.identity_id == "homura" else "p_" + row.class_id)
		actor["identity_id"] = row.identity_id
		if row.identity_id == "homura":
			R.Forms.initialize(actor, catalog)
			actor.unlocked_forms = ["sword", "mage"]
			R.Forms.apply(actor, "mage" if row.class_id == "mage" else "sword", catalog)
		var skill: Dictionary = catalog.skill_for(actor, row.skill_id)
		F.expect(Replay.canonical([skill.mp_cost, skill.cooldown]) == Replay.canonical([row.level5_cost, row.level5_cooldown]), "美术委托费用/CD与真实目录一致：" + row.form_id + "/" + row.skill_id, failures)
		F.expect(Replay.canonical(skill.effects) == Replay.canonical(row.level5_effects), "美术委托效果逐字段与实际技能一致：" + row.form_id + "/" + row.skill_id, failures)
		for field in ["cast", "release", "hit", "recovery", "travel", "target_shape", "status_feedback"]:
			F.expect(row.get(field) is String and not row[field].is_empty(), "美术委托具备阶段/范围语义：" + field, failures)

static func _test_voice_primary_memory(catalog: RefCounted, failures: Array[String]) -> void:
	var Saga = load("res://scripts/rpg/saga_boss_rules.gd")
	var Policy = load("res://scripts/rpg/enemy_policy.gd")
	for level in [4, 5]:
		for marked in [false, true]:
			var actor: Dictionary = R._actor(catalog, R.CASES[6])
			actor.level = level
			actor.stats.spd = 999
			var enemy := F.enemy("saga_borrowed_voice", "voice")
			if marked: Status.apply(enemy, F.status("magic_break", 0.25, 2, actor.actor_id))
			var engine := BattleEngine.new(catalog)
			engine.set_policy(Policy.new())
			F.expect(engine.start({"actors": {actor.actor_id: actor, "voice": enemy}, "inventory": {}}, 17).started, "借声封缄实战启动", failures)
			engine.advance()
			var result := engine.submit(H._command(engine, "skill", "seal", ["voice"]))
			F.expect(result.accepted, "L4/L5有无破魔都可实际封缄借声客", failures)
			var after := engine.snapshot()
			F.expect(after.actors.voice.saga.pending_memory == "control", "个人专精/技法不能改变封缄的主动作类别：L%d/%s" % [level, marked], failures)
			after.round += 1
			Saga.on_round_start(after, "voice")
			F.expect(Saga.plan(after, "voice", catalog).ability_id == "saga_voice_control", "下一轮仍回放控制而非自身治疗", failures)
			var refunded: Array = result.events.filter(func(event): return event.type == "mp_restored")
			F.expect(refunded.size() == (1 if level == 5 and marked else 0), "封缄真实返还条件与分类相互独立", failures)
	# 分类遵循基础24卡主动作；附带盾/治疗不改写回放类型，主治疗和主盾仍保留类别。
	for row in [[1, "hunt", "physical"], [5, "cleanse", "control"], [3, "battle_spirit", "control"], [5, "heal", "heal"], [5, "holy_shield", "guard"], [2, "iron_wall", "guard"]]:
		for level in [4, 5]:
			var actor: Dictionary = R._actor(catalog, R.CASES[row[0]])
			actor.level = level
			F.expect(Saga._memory(actor, {"kind": "skill", "ability_id": row[1]}, catalog) == row[2], "借声按基础主动作分类，忽略附效：" + row[1], failures)

static func _test_router_catalog_fingerprint(failures: Array[String]) -> void:
	var Campaign = load("res://scripts/rpg/campaign.gd")
	var Store = load("res://scripts/rpg/save_store.gd")
	var Router = load("res://scripts/rpg/encounter_router.gd")
	var Policy = load("res://scripts/rpg/enemy_policy.gd")
	var root := F.write_catalog_copy("router_catalog_fingerprint", "skills", func(document): document.definitions[0].mp_cost = 5)
	var custom := Catalog.new()
	F.expect(custom.load_all(root).is_empty(), "注入的不同合法技能目录可加载", failures)
	var campaign = Campaign.new(custom, Store.new(custom), "user://rpg_v1/tests/technique_custom_router.json")
	var party: Array[String] = ["guard", "swordsman", "healer"]
	F.expect(campaign.new_run(party, 5).ok, "使用注入目录创建隔离队伍", failures)
	var router = Router.new(campaign, custom)
	var world := {"scene_path": "res://scenes/v3/stage.tscn", "player_x": 735.5, "facing": -1, "resolved": {}, "dlg_fired": {"200": true}, "exit_prompted": false, "spirit": 2, "party_index": 1}
	var started: Dictionary = campaign.begin_battle("slice_1", world)
	F.expect(started.ok and router.adopt_battle(started).ok, "路由采用注入目录的真实战斗", failures)
	var engine: RefCounted = router.create_engine()
	F.expect(engine != null, "注入目录的实际引擎创建", failures)
	if engine == null: return
	engine.advance()
	F.expect(engine.submit(H._command(engine, "defend")).accepted, "真实战斗执行一条合法命令", failures)
	var recording: Dictionary = router.capture_replay(engine)
	F.expect(recording.get("mechanics_fingerprint") == custom.mechanics_fingerprint(), "路由捕获必须绑定创建引擎的同一目录", failures)
	F.expect(Replay.verify(recording, custom, Policy.new()).matches, "注入目录路由捕获的真实重放可验证", failures)
	var standard := Catalog.new()
	standard.load_all()
	F.expect(not Replay.verify(recording, standard, Policy.new()).matches, "注入目录重放不能误标为默认目录", failures)
