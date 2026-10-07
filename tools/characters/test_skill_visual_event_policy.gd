# 真实结算事件驱动的无纹理意图门禁；不读取UI文案，不代算规则。
extends SceneTree
const F = preload("res://tools/rpg/fixtures.gd")
const H = preload("res://tools/rpg/test_engine.gd")
const BattleEngine = preload("res://scripts/rpg/battle_engine.gd")
const Status = preload("res://scripts/rpg/status_rules.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
var checks := 0
var failures := 0
var Policy
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	check(FileAccess.file_exists("res://scripts/rpg/ui/skill_visual_event_policy.gd"), "独立纯事件策略存在")
	if failures: _finish(); return
	Policy = load("res://scripts/rpg/ui/skill_visual_event_policy.gd")
	_test_heal()
	_test_cleanse()
	_test_shield()
	_test_controller()
	_test_identity_and_cancel()
	_test_status_refresh_and_expiry()
	_test_damage_lifecycle()
	_test_seal_interrupt()
	_test_invalid_and_bounded()
	_test_closed_and_cross_action()
	_test_reflection_context()
	_finish()
func _finish() -> void:
	print("SKILL_VISUAL_EVENT_POLICY: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func _actor(class_id: String, id: String = "source") -> Dictionary:
	var actor := F.actor(class_id, id)
	actor["identity_id"] = class_id
	return actor
func _enemy(id: String = "enemy") -> Dictionary:
	var enemy := F.enemy("hound", id)
	enemy.stats.hp = 3000
	enemy.hp = 3000
	return enemy
func _layers(skill: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/effects/imagegen_spells/%s/manifest.json" % skill)).event_layers
func _cast(skill: String, others: Array, source: Dictionary = {}) -> Dictionary:
	if source.is_empty(): source = _actor("healer" if skill in ["heal", "group_heal", "cleanse", "holy_shield"] else "controller")
	var engine = H._selection(BattleEngine, source, others)
	var targets: Array = [] if skill in ["group_heal", "slow"] else [others[0].actor_id]
	var command := H._command(engine, "skill", skill, targets)
	return _submit(engine, command, skill)
func _submit(engine, command: Dictionary, skill: String) -> Dictionary:
	var result: Dictionary = engine.submit(command)
	var context := command.duplicate(true)
	context.source_id = command.actor_id
	context.effect_target_ids = []
	for event in result.events:
		if event.type == "command_accepted": context.effect_target_ids = event.payload.resolved_target_ids.duplicate()
	return {"engine": engine, "result": result, "context": context, "skill": skill}
func _feed(policy, cast: Dictionary, battle: String = "battle") -> Array:
	check(cast.result.accepted, "真实指令获接受：" + cast.skill)
	check(policy.begin_action(cast.context, battle, _layers(cast.skill)), "注册已接受动作：" + cast.skill)
	var intents: Array = []
	for event in cast.result.events: intents.append_array(policy.consume(event, cast.context, battle))
	return intents
func _phase(intents: Array, phase: String, op: String = "") -> Array:
	return intents.filter(func(intent): return intent.phase == phase and (op.is_empty() or intent.op == op))
func _events(cast: Dictionary, kind: String) -> Array:
	return cast.result.events.filter(func(event): return event.type == kind)
func _test_heal() -> void:
	var ally := _actor("guard", "ally"); ally.hp = 50
	var cast := _cast("heal", [ally, _enemy()])
	var policy = Policy.new()
	var intents := _feed(policy, cast)
	check(_phase(intents, "heal_impact", "spawn").size() == 1, "实际正治疗创建单体落点")
	check(_phase(intents, "guard_life_shield", "upsert").size() == 1, "护生只响应真实护盾")
	var removed: Array = policy.finish_action(cast.context, "battle")
	check(_phase(removed, "heal_impact", "remove").size() == 1 and _phase(removed, "guard_life_shield", "remove").is_empty(), "E只移除治疗瞬态，护生继续")
	check(policy.consume(_events(cast, "healed")[0], cast.context, "battle").is_empty(), "结束后迟到治疗不复活")
	var healthy := _actor("guard", "healthy")
	var down := _actor("guard", "down"); down.hp = 0
	cast = _cast("group_heal", [ally, healthy, down, _enemy()])
	policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "heal_impact").size() == 1 and _phase(intents, "heal_impact")[0].target_id == "ally", "群疗仅实际受益存活目标，满血/倒地没有落点")
	check(_events(cast, "healed").any(func(e): return e.payload.actual == 0), "群疗夹具确含真实零收益事件")
	cast = _cast("heal", [healthy, _enemy()])
	policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "heal_impact").is_empty() and _phase(intents, "guard_life_shield").size() == 1, "满血护生可以只加盾，不伪造治疗")
func _test_cleanse() -> void:
	var ally := _actor("guard", "ally"); ally.hp = 50
	Status.apply(ally, F.status("weaken", .2, 2, "enemy"))
	Status.apply(ally, F.status("magic_break", .25, 2, "enemy"))
	var cast := _cast("cleanse", [ally, _enemy()])
	var policy = Policy.new(); var intents := _feed(policy, cast)
	check(_events(cast, "status_removed").size() == 2, "净化夹具实际移除两个负面")
	check(_events(cast, "status_removed")[0].actor_id == "ally", "真实净化事件源为被净化者，不能误判成外来命令")
	check(_phase(intents, "cleanse_removal", "spawn").size() == 1, "多负面净化同动作目标只播放一次")
	check(_phase(intents, "rejuvenation_heal", "spawn").size() == 1, "真实先移除后正治疗触发回春")
	policy = Policy.new(); check(policy.begin_action(cast.context, "battle", _layers("cleanse")), "注册乱序净化")
	check(policy.consume(_events(cast, "healed")[0], cast.context, "battle").is_empty(), "移除尚未到达时不能提前播回春")
	policy.consume(_events(cast, "status_removed")[0], cast.context, "battle")
	check(policy.consume(_events(cast, "healed")[0], cast.context, "battle").is_empty(), "早到事件不缓冲成后续伪触发")
	var wrong: Dictionary = _events(cast, "status_removed")[0].duplicate(true); wrong.payload.reason = "target_slot_end"
	policy = Policy.new(); policy.begin_action(cast.context, "battle", _layers("cleanse"))
	check(policy.consume(wrong, cast.context, "battle").is_empty(), "自然到期不显示净化")
	check(policy.consume(_events(cast, "healed")[0], cast.context, "battle").is_empty(), "自然到期不能作为回春前提")
	var clean := _actor("guard", "ally"); clean.hp = 50
	cast = _cast("cleanse", [clean, _enemy()])
	policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "cleanse_removal").is_empty() and _phase(intents, "rejuvenation_heal").is_empty(), "无负面的净化无移除和回春视觉")
func _test_shield() -> void:
	var ally := _actor("guard", "ally")
	Status.apply(ally, F.status("stun", 1, 1, "enemy"))
	var cast := _cast("holy_shield", [ally, _enemy()])
	var policy = Policy.new(); var intents := _feed(policy, cast)
	check(_phase(intents, "holy_shield_edge", "upsert").size() == 1 and _phase(intents, "awake_clarity", "upsert").size() == 1, "护盾与清醒是两项独立实效")
	check(not F.find_status(cast.engine.snapshot().actors.ally, "stun").is_empty() and _events(cast, "status_removed").is_empty(), "定神不净化已经存在的眩晕")
	var finish: Array = policy.finish_action(cast.context, "battle")
	check(_phase(finish, "holy_shield_edge", "update").size() == 1 and _phase(finish, "holy_shield_edge")[0].activation_frames.is_empty(), "E结束护盾激活，持续循环保留")
	var advance: Array = _target_slot(cast.engine, "ally")
	var lifecycle: Array = []
	for event in advance: lifecycle.append_array(policy.consume(event, {}, "battle"))
	check(_phase(lifecycle, "awake_clarity", "remove").size() == 1, "目标真实槽末清醒到期")
	check(_phase(lifecycle, "holy_shield_edge", "update").size() == 1, "无动作context的盾时钟更新原层")
	check(not _phase(lifecycle, "holy_shield_edge").is_empty() and _phase(lifecycle, "holy_shield_edge")[0].source_id == "source", "时钟actor是目标时仍保留施法来源")
	# stronger shield拒绝护盾本身，但定神仍独立生效。
	ally = _actor("guard", "ally"); Status.apply_shield(ally, F.shield(999, 3, "other"))
	cast = _cast("holy_shield", [ally, _enemy()]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "holy_shield_edge").is_empty() and _phase(intents, "awake_clarity").size() == 1, "护盾被忽略不吞掉独立清醒")
func _test_controller() -> void:
	var cast := _cast("weaken", [_enemy()])
	var policy = Policy.new(); var intents := _feed(policy, cast)
	check(_phase(intents, "weaken_apply", "spawn").size() == 1 and _phase(intents, "weaken_status", "upsert").size() == 1, "虚弱施加与持续明确分层")
	var status_layer: Dictionary = _phase(intents, "weaken_status")[0]
	policy.finish_action(cast.context, "battle")
	var enemy := _enemy("marked"); Status.apply(enemy, F.status("weaken", .2, 2, "source"))
	cast = _cast("slow", [enemy, _enemy("plain")]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "slow_apply_sustain").size() == 2, "群缓速逐真实状态目标创建持续")
	check(_phase(intents, "conditional_magic_break").size() == 1 and _phase(intents, "conditional_magic_break")[0].target_id == "marked", "蚀咒只来自单独实际破魔状态")
	check(_phase(intents, "slow_apply_sustain")[0].activation_frames.map(func(v): return int(v)) == [9, 10] and _phase(intents, "slow_apply_sustain")[0].loop_frames.map(func(v): return int(v)) == [11, 12], "缓速激活与循环遵循批准帧")
	cast = _cast("magic_break", [_enemy()]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "damage_recovery", "spawn").size() == 1 and _phase(intents, "magic_break_status", "upsert").size() == 1, "破魔伤害与状态独立")
	enemy = _enemy(); enemy.hp = 1
	cast = _cast("magic_break", [enemy, _enemy("survivor")]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "damage_recovery", "spawn").size() == 1 and _phase(intents, "magic_break_status").is_empty(), "击杀只播放真实伤害，死亡跳过状态")
	enemy = _enemy(); Status.apply(enemy, F.status("magic_break", .25, 2, "source")); Status.apply(enemy, F.status("awake", 1, 2, "enemy"))
	cast = _cast("seal", [enemy]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "stun_apply_sustain").is_empty() and _phase(intents, "charge_interrupt").is_empty() and _phase(intents, "mp_refund", "spawn").size() == 1, "封缄眩晕免疫/无蓄力仍可独立真实回MP")
	check(_phase(intents, "mp_refund")[0].target_id == "source", "回馈位于施法者")
	cast = _cast("seal", [_enemy()]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "stun_apply_sustain", "upsert").size() == 1 and _phase(intents, "charge_interrupt").is_empty() and _phase(intents, "mp_refund").is_empty(), "普通封缄只有眩晕，不制造打断或回MP")
	check(status_layer.ability_id == "weaken" and status_layer.source_id == "source", "持续图层保存能力与源身份")
func _test_identity_and_cancel() -> void:
	var cast := _cast("weaken", [_enemy()])
	var event: Dictionary = _events(cast, "status_applied")[0]
	var policy = Policy.new(); policy.begin_action(cast.context, "battle", _layers("weaken"))
	check(policy.consume(event, cast.context, "other_battle").is_empty(), "不同战场事件不可串入")
	var wrong: Dictionary = cast.context.duplicate(true); wrong.command_id = "other_command"
	check(policy.consume(event, wrong, "battle").is_empty(), "未接纳指令不可创建图层")
	wrong = cast.context.duplicate(true); wrong.source_id = "other"
	check(policy.consume(event, wrong, "battle").is_empty(), "相同指令不能更换施法者")
	var copied := event.duplicate(true); copied.actor_id = "other"
	check(policy.consume(copied, cast.context, "battle").is_empty(), "伪造事件来源不能污染同一序号")
	var intents: Array = policy.consume(event, cast.context, "battle")
	check(intents.size() == 2, "拒绝不匹配身份后原事件仍可消费")
	check(policy.consume(event, cast.context, "battle").is_empty(), "同序号事件去重")
	var removed: Array = policy.cancel_action(cast.context, "battle")
	check(_phase(removed, "weaken_apply", "remove").size() == 1 and _phase(removed, "weaken_status", "remove").is_empty(), "取消仅停止视觉动作，不反转已提交虚弱")
	copied = event.duplicate(true); copied.sequence += 100
	check(policy.consume(copied, cast.context, "battle").is_empty(), "取消后的新序号迟到事件不再生成")
	check(not policy.begin_action(cast.context, "battle", _layers("weaken")), "同一取消指令不可重开")
	var cleared: Array = policy.clear()
	check(_phase(cleared, "weaken_status", "remove").size() == 1, "离场clear移除持续层")
	check(policy.consume(event, {}, "battle").is_empty() and policy.clear().is_empty(), "clear幂等且迟到事件无残留")

func _target_slot(engine, target: String) -> Array:
	var events: Array = []
	for attempt in 20:
		var advanced: Array = engine.advance(false)
		events.append_array(advanced)
		if advanced.any(func(e): return e.type == "slot_ended" and e.target_id == target): return events
		if not engine.snapshot().outcome.is_empty(): return events
		var result: Dictionary = engine.submit(H._command(engine, "defend"))
		check(result.accepted, "推进真实防御槽")
		events.append_array(result.events)
		if result.events.any(func(e): return e.type == "slot_ended" and e.target_id == target): return events
	check(false, "有限步到达目标真实槽")
	return events

func _test_status_refresh_and_expiry() -> void:
	var second := _actor("controller", "second"); second.stats.spd = 998
	var cast := _cast("weaken", [_enemy(), second])
	var policy = Policy.new(); var initial := _feed(policy, cast)
	var layer: Dictionary = _phase(initial, "weaken_status")[0]
	var old: Dictionary = _events(cast, "status_applied")[0]
	policy.finish_action(cast.context, "battle")
	for event in cast.engine.advance(false): policy.consume(event, {}, "battle")
	check(cast.engine.snapshot().active_actor_id == "second", "真实次位控制师得到行动")
	var refreshed := _submit(cast.engine, H._command(cast.engine, "skill", "weaken", ["enemy"]), "weaken")
	var intents := _feed(policy, refreshed)
	var refreshes := _phase(intents, "weaken_status", "upsert")
	check(refreshes.size() == 1 and refreshes[0].layer_key == layer.layer_key and refreshes[0].source_id == "second", "同名刷新替换图层来源，不叠两个持续层")
	policy.finish_action(refreshed.context, "battle")
	var ticks: Array = []
	var tick_events: Array = _target_slot(cast.engine, "enemy")
	for event in tick_events: ticks.append_array(policy.consume(event, {}, "battle"))
	var updates := _phase(ticks, "weaken_status", "update")
	check(updates.size() == 1 and updates[0].source_id == "second" and updates[0].ability_id == "weaken", "真实tick保留最新施法者与原图层")
	check(not updates.is_empty() and updates[0].value.remaining == 1, "tick仅同步真实剩余一槽")
	var outdated := {"sequence": cast.engine.snapshot().event_sequence + 1, "type": "status_removed", "actor_id": "enemy", "target_id": "enemy", "payload": {"status": old.payload.status, "reason": "target_slot_end"}}
	check(policy.consume(outdated, {}, "battle").is_empty(), "旧generation移除不能删除较新的刷新层")
	# 使用真实引擎后续事件自然到期；复制的乱序挑战使用不同序号，避免占用后续真实事件。
	var expired: Array = []
	var expiry_events: Array = _target_slot(cast.engine, "enemy")
	for event in expiry_events: expired.append_array(policy.consume(event, {}, "battle"))
	check(_phase(expired, "weaken_status", "remove").size() == 1, "刷新后的虚弱真实到期一次")
	check(policy.consume(old, cast.context, "battle").is_empty(), "旧施加不能在到期后复活")
	var newer_removal: Dictionary = expiry_events.filter(func(e): return e.type == "status_removed" and e.payload.status.id == "weaken")[0]
	var newer_tick: Dictionary = tick_events.filter(func(e): return e.type == "status_tick" and e.payload.status.id == "weaken")[0]
	for newer in [newer_removal, newer_tick]:
		var reordered = Policy.new(); _feed(reordered, cast)
		reordered.begin_action(refreshed.context, "battle", _layers("weaken"))
		var cleanup: Array = reordered.consume(newer, {}, "battle")
		check(_phase(cleanup, "weaken_status", "remove").size() == 1, "更新generation的生命周期先到时撤掉旧来源：" + newer.type)
		check(reordered.consume(_events(refreshed, "status_applied")[0], refreshed.context, "battle").is_empty(), "刷新晚于自身tick/到期到达时不重放激活或复活：" + newer.type)
	var unregistered_refresh = Policy.new(); _feed(unregistered_refresh, cast); unregistered_refresh.finish_action(cast.context, "battle")
	var dropped_origin: Array = unregistered_refresh.consume(_events(refreshed, "status_applied")[0], refreshed.context, "battle")
	check(_phase(dropped_origin, "weaken_status", "remove").size() == 1, "新刷新动作未注册也不能留下旧施法来源的持续图")
	check(dropped_origin.all(func(i): return i.op == "remove"), "未注册刷新仅撤旧图，不猜新技能视觉")
	var initially_absent = Policy.new(); initially_absent.begin_action(cast.context, "battle", _layers("weaken"))
	check(initially_absent.consume(newer_tick, {}, "battle").is_empty(), "无可见层的tick不推测技能来源")
	check(initially_absent.consume(old, cast.context, "battle").is_empty(), "无层tick仍挡住未见过的更早施加")
	var slow := _cast("slow", [_enemy()]); policy = Policy.new(); _feed(policy, slow); policy.finish_action(slow.context, "battle")
	var slow_events: Array = []
	for repeat in 3:
		for event in _target_slot(slow.engine, "enemy"): slow_events.append_array(policy.consume(event, {}, "battle"))
	for event in slow.engine.advance(false): slow_events.append_array(policy.consume(event, {}, "battle"))
	check(_phase(slow_events, "slow_apply_sustain", "remove").size() == 1, "缓速等真实最后快照轮末移除，不拿remaining自行提前结束")

func _test_damage_lifecycle() -> void:
	var ally := _actor("guard", "ally")
	var foe := _enemy(); foe.stats.atk = 20
	var cast := _cast("holy_shield", [ally, foe])
	var policy = Policy.new(); _feed(policy, cast); policy.finish_action(cast.context, "battle")
	for event in cast.engine.advance(false): policy.consume(event, {}, "battle")
	check(cast.engine.snapshot().active_actor_id == "enemy", "攻击者真实获得行动")
	var hit: Dictionary = cast.engine.submit(H._command(cast.engine, "attack_physical", "", ["ally"]))
	check(hit.accepted, "真实攻击护盾目标")
	var intents: Array = []
	for event in hit.events: intents.append_array(policy.consume(event, {}, "battle"))
	var damage: Dictionary = H._event(hit.events, "damage")
	var updates := _phase(intents, "holy_shield_edge", "update")
	check(updates.size() == 1 and updates[0].value == damage.payload.absorption.shield_after and updates[0].source_id == "source", "吸收伤害同步真实剩余盾量并保留原来源")
	var before: Dictionary = cast.engine.snapshot()
	before.actors.enemy.stats.atk = 9999
	cast.engine.restore(before)
	var ignored_failures: Array[String] = []
	var start_index: int = cast.engine.snapshot().event_log.size()
	H._next_actor(cast.engine, "enemy", ignored_failures)
	check(ignored_failures.is_empty(), "真实推进强攻击行动")
	for event in cast.engine.snapshot().event_log.slice(start_index): policy.consume(event, {}, "battle")
	var lethal: Dictionary = cast.engine.submit(H._command(cast.engine, "attack_physical", "", ["ally"]))
	intents = []
	for event in lethal.events:
		if event.type != "actor_defeated": intents.append_array(policy.consume(event, {}, "battle"))
	check(lethal.accepted and H._event(lethal.events, "damage").payload.absorption.defeated, "真实致死夹具")
	check(_phase(intents, "holy_shield_edge", "remove").size() == 1, "真实耗尽盾不依赖shield_removed")
	start_index = cast.engine.snapshot().event_log.size()
	H._next_actor(cast.engine, "source", ignored_failures)
	for event in cast.engine.snapshot().event_log.slice(start_index): policy.consume(event, {}, "battle")
	var revival: Dictionary = cast.engine.submit(H._command(cast.engine, "item", "revival_potion", ["ally"]))
	check(revival.accepted and not H._event(revival.events, "revived").is_empty(), "真实道具复活")
	for event in revival.events: policy.consume(event, {}, "battle")
	var delayed = Policy.new(); delayed.begin_action(cast.context, "battle", _layers("holy_shield"))
	delayed.consume(H._event(lethal.events, "damage"), {}, "battle")
	for event in revival.events: delayed.consume(event, {}, "battle")
	check(delayed.consume(_events(cast, "status_applied")[0], cast.context, "battle").is_empty(), "复活后未见过的死前清醒施加也不可迟到复活")
	check(policy.consume(H._event(lethal.events, "actor_defeated"), {}, "battle").is_empty(), "复活后迟到的旧KO不覆盖存活代次")
	start_index = cast.engine.snapshot().event_log.size()
	H._next_actor(cast.engine, "source", ignored_failures)
	for event in cast.engine.snapshot().event_log.slice(start_index): policy.consume(event, {}, "battle")
	var healed := _submit(cast.engine, H._command(cast.engine, "skill", "heal", ["ally"]), "heal")
	intents = _feed(policy, healed)
	check(_phase(intents, "heal_impact", "spawn").size() == 1, "旧KO迟到仍允许复活后的实际治疗")
	policy.finish_action(healed.context, "battle")
	policy.clear()
	# 周期伤害使用同一absorption结构，但不生成另一技能的命中。
	var status_cast := _cast("weaken", [_enemy()]); policy = Policy.new(); _feed(policy, status_cast); policy.finish_action(status_cast.context, "battle")
	var snapshot: Dictionary = status_cast.engine.snapshot()
	Status.apply(snapshot.actors.enemy, F.status("burn", 9999, 2, "source", {"base": 9999.0}))
	status_cast.engine.restore(snapshot)
	var periodic: Array = status_cast.engine.advance(false)
	intents = []
	for event in periodic: intents.append_array(policy.consume(event, {}, "battle"))
	check(periodic.any(func(e): return e.type == "periodic_damage"), "真实槽首灼烧事件")
	check(_phase(intents, "weaken_status", "remove").size() == 1 and intents.all(func(i): return i.op == "remove"), "周期致死只清理持续，不伪造任何新命中")

func _test_seal_interrupt() -> void:
	var source := _actor("controller")
	var voice := F.enemy("saga_borrowed_voice", "voice")
	Status.apply(voice, F.status("magic_break", .25, 2, "source"))
	var catalog := Catalog.new(); catalog.load_all()
	var engine := BattleEngine.new(catalog)
	engine.set_policy(load("res://scripts/rpg/enemy_policy.gd").new())
	source.stats.spd = 999
	check(engine.start({"actors": {"source": source, "voice": voice}, "inventory": {}}, 17).started, "真实借声客启动")
	engine.advance()
	var cast := _submit(engine, H._command(engine, "skill", "seal", ["voice"]), "seal")
	var policy = Policy.new(); var intents := _feed(policy, cast)
	check(_events(cast, "charge_interrupted").size() == 1 and _phase(intents, "charge_interrupt", "spawn").size() == 1, "实际号令打断才出现破符")
	check(_phase(intents, "stun_apply_sustain").size() == 1 and _phase(intents, "mp_refund").size() == 1, "眩晕/打断/回馈各自成功互不替代")
	var refund: Dictionary = _events(cast, "mp_restored")[0].duplicate(true); refund.sequence += 100
	check(policy.consume(refund, cast.context, "battle").is_empty(), "不同序号也不能同动作重复返还视觉")

func _test_invalid_and_bounded() -> void:
	var cast := _cast("weaken", [_enemy()])
	var event: Dictionary = _events(cast, "status_applied")[0]
	var policy = Policy.new(); policy.begin_action(cast.context, "battle", _layers("weaken"))
	var forged := event.duplicate(true); forged.payload.status.source_id = "different_source"
	check(policy.consume(forged, cast.context, "battle").is_empty(), "状态来源与事件/命令不符时不能播放施加")
	forged = event.duplicate(true); forged.sequence = 0
	check(policy.consume(forged, cast.context, "battle").is_empty(), "预览未发布零序号不能成为真实成功")
	var unknown := event.duplicate(true); unknown.type = "effect_ignored"; unknown.payload = {"reason": "weaken", "text": "造成眩晕并回复MP"}
	check(policy.consume(unknown, cast.context, "battle").is_empty(), "失败和文字永不推断效果")
	policy = Policy.new(); policy.begin_action(cast.context, "battle", _layers("weaken"))
	var cancel := {"sequence": 1, "type": "saga_cancelled", "actor_id": "source", "target_id": "source", "payload": {"text": "本次行动失效"}}
	check(policy.consume(cancel, cast.context, "battle").is_empty() and policy.consume(event, cast.context, "battle").is_empty(), "结算前saga取消阻止整招新图层")
	policy = Policy.new(); policy.begin_action(cast.context, "battle", _layers("weaken"))
	for sequence in range(1, 2200):
		policy.consume({"sequence": sequence, "type": "round_snapshot", "actor_id": "enemy", "target_id": "enemy", "payload": {}}, {}, "battle")
	check(policy.consume(event, cast.context, "battle").is_empty(), "有界序号窗口淘汰后的旧事件不能重新播放")
	check(policy.get("_seen").size() <= policy.MAX_HISTORY and policy.get("_latest").size() <= policy.MAX_HISTORY, "事件与生命周期历史有硬内存上限")

func _test_closed_and_cross_action() -> void:
	var cast := _cast("weaken", [_enemy()])
	var policy = Policy.new(); _feed(policy, cast); policy.finish_action(cast.context, "battle")
	var ticks: Array = []
	for event in _target_slot(cast.engine, "enemy"): ticks.append_array(policy.consume(event, cast.context, "battle"))
	check(_phase(ticks, "weaken_status", "update").size() == 1, "已关闭动作context不阻断真实持续状态维护")
	policy.clear()
	check(not policy.begin_action(cast.context, "battle", _layers("weaken")), "clear后旧战场的迟到begin也不能重建")
	check(policy.begin_action(cast.context, "new_battle", _layers("weaken")), "新战场代次可使用相同command_id")
	check(policy.consume(_events(cast, "status_applied")[0], cast.context, "battle").is_empty(), "新战场拒绝旧战场事件")
	var ally := _actor("guard", "ally"); ally.hp = 50
	Status.apply(ally, F.status("weaken", .2, 2, "enemy"))
	cast = _cast("cleanse", [ally, _enemy()]); policy = Policy.new()
	policy.begin_action(cast.context, "battle", _layers("cleanse"))
	var removal: Dictionary = _events(cast, "status_removed")[0]
	policy.consume(removal, cast.context, "battle")
	var other: Dictionary = cast.context.duplicate(true); other.command_id = "other_cleanse"
	policy.begin_action(other, "battle", _layers("cleanse"))
	check(policy.consume(_events(cast, "healed")[0], other, "battle").is_empty(), "另一指令的净化不能借用已发生的移除")
	var mismatched: Dictionary = _events(cast, "healed")[0].duplicate(true); mismatched.sequence += 10; mismatched.target_id = "enemy"
	check(policy.consume(mismatched, cast.context, "battle").is_empty(), "另一目标不能借用净化前提")
	var source_only: Dictionary = cast.context.duplicate(true); source_only.command_id = "unaccepted"
	check(policy.finish_action(source_only, "battle").is_empty(), "错误command结束不影响其他动作")

func _test_reflection_context() -> void:
	var controller := _actor("controller", "controller"); controller.stats.spd = 998
	var mirror := F.enemy("saga_joined_mirror", "mirror")
	load("res://scripts/rpg/saga_boss_rules.gd").initialize(mirror)
	mirror.saga.phase = 2
	var shield := _cast("holy_shield", [controller, mirror])
	var policy = Policy.new(); _feed(policy, shield); policy.finish_action(shield.context, "battle")
	for event in shield.engine.advance(false): policy.consume(event, {}, "battle")
	check(shield.engine.snapshot().active_actor_id == "controller", "真实控制师在镜面前行动")
	var attack := _submit(shield.engine, H._command(shield.engine, "skill", "magic_break", ["mirror"]), "magic_break")
	var intents := _feed(policy, attack)
	var reflections := _events(attack, "saga_reflected")
	check(reflections.size() == 1 and reflections[0].actor_id == "mirror", "真实魔法镜面产生敌人作为来源的反射")
	var changed := _phase(intents, "holy_shield_edge")
	check(changed.any(func(i): return i.target_id == "controller" and i.value == reflections[0].payload.absorption.shield_after), "反射携带原施法context仍维护施法者护盾")
	if not changed.is_empty(): check(changed[0].value == reflections[0].payload.absorption.shield_after, "反射盾量来自真实吸收而非重算")
	var missing_action = Policy.new(); _feed(missing_action, shield); missing_action.finish_action(shield.context, "battle")
	var fallback_updates: Array = []
	for event in attack.result.events: fallback_updates.append_array(missing_action.consume(event, attack.context, "battle"))
	check(_phase(fallback_updates, "holy_shield_edge", "update").any(func(i): return i.value == reflections[0].payload.absorption.shield_after), "新动作因渲染未注册时仍维护真实反射护盾")
	check(_phase(fallback_updates, "damage_recovery").is_empty(), "未注册动作只维护旧状态，不生成命中")
