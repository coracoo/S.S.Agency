# 只由核验过真实 user:// 的 Python 入口启动；模型由原仓库逐字复制。
extends SceneTree
const F = preload("res://tools/rpg/fixtures.gd")
const H = preload("res://tools/rpg/test_engine.gd")
const BattleEngine = preload("res://scripts/rpg/battle_engine.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Status = preload("res://scripts/rpg/status_rules.gd")
const Forms = preload("res://scripts/rpg/dual_form.gd")
var Policy
var checks := 0
var failures := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", text)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	check(FileAccess.file_exists("res://scripts/rpg/ui/physical_skill_visual_event_policy.gd"), "独立策略文件存在")
	if failures: _finish(); return
	Policy = load("res://scripts/rpg/ui/physical_skill_visual_event_policy.gd")
	_test_precision_and_forms()
	_test_conditions_and_sweep()
	_test_guard()
	_test_mint()
	_test_cover()
	_test_lifecycle()
	_test_identity_and_bounds()
	_test_contract_export()
	_test_out_of_order_life()
	_test_ineligible_dedup()
	_finish()
func _finish() -> void:
	print("PHYSICAL_SKILL_VISUAL_POLICY: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func _actor(form: String, id: String = "source") -> Dictionary:
	var classes := {"rinne": "swordsman", "mint": "ranger", "guard": "guard", "homura_sword": "mage"}
	var actor := F.actor(classes[form], "p_mage" if form == "homura_sword" else id)
	actor["identity_id"] = "homura" if form == "homura_sword" else form
	if form == "homura_sword":
		var catalog := Catalog.new(); catalog.load_all()
		Forms.initialize(actor, catalog)
		actor.unlocked_forms = ["sword", "mage"]
	return actor
func _enemy(id: String = "enemy") -> Dictionary:
	var actor := F.enemy("hound", id)
	actor.stats.hp = 3000; actor.hp = 3000
	return actor
func _submit(engine, command: Dictionary) -> Dictionary:
	var before: Dictionary = engine.snapshot()
	var catalog := Catalog.new(); catalog.load_all()
	var derived: Dictionary = catalog.skill_for(before.actors[command.actor_id], command.ability_id) if command.kind == "skill" and before.actors[command.actor_id].side == "player" else {}
	var result: Dictionary = engine.submit(command)
	var original_before := before.duplicate(true); var original_derived := derived.duplicate(true); var original_result := result.duplicate(true)
	var context: Dictionary = Policy.context_from_result(before, derived, result)
	check(before == original_before and derived == original_derived and result == original_result, "证据桥不改变快照/派生技能/结算事务")
	return {"engine": engine, "before": before, "derived": derived, "result": result, "context": context}
func _cast(form: String, skill: String, others: Array, source: Dictionary = {}) -> Dictionary:
	if source.is_empty(): source = _actor(form)
	var engine = H._selection(BattleEngine, source, others)
	var targets: Array = [] if skill in ["sweep", "battle_spirit", "iron_wall", "smoke_screen"] else [others[0].actor_id]
	return _submit(engine, H._command(engine, "skill", skill, targets))
func _groups(context: Dictionary) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/effects/imagegen_spells/%s/manifest.json" % context.variant_key)).phase_groups
func _feed(policy, cast: Dictionary) -> Array:
	check(cast.result.accepted, "真实指令接受")
	check(not cast.context.is_empty(), "已接受事务建立只读上下文")
	check(policy.begin_action(cast.context, "battle", _groups(cast.context)), "注册正确形态动作")
	var before: Dictionary = cast.engine.snapshot()
	var result := _consume(policy, cast.result.events, cast.context)
	check(before == cast.engine.snapshot(), "消费呈现事件不改变数值/RNG/模型状态")
	return result
func _consume(policy, events: Array, context: Dictionary = {}) -> Array:
	var intents: Array = []
	for event in events: intents.append_array(policy.consume(event, context, "battle"))
	return intents
func _phase(intents: Array, phase: String, op: String = "") -> Array:
	return intents.filter(func(i): return i.phase == phase and (op.is_empty() or i.op == op))
func _event(cast: Dictionary, kind: String) -> Dictionary: return H._event(cast.result.events, kind)
func _status_events(cast: Dictionary, id: String) -> Array:
	return cast.result.events.filter(func(e): return e.type == "status_applied" and e.payload.status.id == id)
func _test_precision_and_forms() -> void:
	var enemy := _enemy(); Status.apply(enemy, F.status("armor_break", .25, 3, "other"))
	var cast := _cast("rinne", "heavy_slash", [enemy]); var policy = Policy.new(); var intents := _feed(policy, cast)
	check(_phase(intents, "contact_damage", "spawn").size() == 1, "真实重斩只有一次接触")
	check(_phase(intents, "conditional_precision", "spawn").size() == 1, "同一首伤害和权威施法前派生支持破隙")
	check(intents.all(func(i): return i.form == "rinne" and i.variant_key == "rinne-heavy_slash"), "每个意图包括准确形态与资源键")
	var without_proof: Dictionary = cast.context.duplicate(true); without_proof.erase("precast_evidence")
	policy = Policy.new(); policy.begin_action(without_proof, "battle", _groups(cast.context)); intents = _consume(policy, cast.result.events, without_proof)
	check(_phase(intents, "conditional_precision").is_empty() and _phase(intents, "contact_damage").size() == 1, "缺权威证明仅拒绝条件层")
	var changed: Dictionary = cast.before.duplicate(true); changed.revision += 1
	check(Policy.context_from_result(changed, cast.derived, cast.result).is_empty(), "旧 revision 不形成条件证明")
	var wrong: Dictionary = cast.derived.duplicate(true); wrong.effects.append(wrong.effects[0].duplicate(true))
	var ambiguous: Dictionary = Policy.context_from_result(cast.before, wrong, cast.result)
	policy = Policy.new(); policy.begin_action(ambiguous, "battle", _groups(cast.context)); intents = _consume(policy, cast.result.events, ambiguous)
	check(_phase(intents, "conditional_precision").is_empty(), "多个候选伤害 effect 无序号证据时不猜")
	cast = _cast("rinne", "heavy_slash", [_enemy()]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "conditional_precision").is_empty(), "无施法前破甲没有精准层")
	var junior := _actor("rinne"); junior.level = 2
	cast = _cast("rinne", "heavy_slash", [enemy], junior); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "conditional_precision").is_empty(), "低等级未派生破隙不能仅因目标有破甲播放")
	cast = _cast("homura_sword", "heavy_slash", [enemy]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "conditional_precision").is_empty() and intents.all(func(i): return i.variant_key == "homura_sword-heavy_slash"), "共享技能 ID 不共享凛音素材或条件")
func _test_conditions_and_sweep() -> void:
	var source := _actor("rinne"); Status.apply(source, F.status("battle_spirit", .25, 2, "source"))
	var cast := _cast("rinne", "armor_break", [_enemy()], source)
	var policy = Policy.new(); var intents := _feed(policy, cast)
	check(_phase(intents, "armor_break_status", "upsert").size() == 1 and _phase(intents, "conditional_weaken", "upsert").size() == 1, "崩刃两个状态分别来自真实成功事件")
	check(_phase(policy.finish_action(cast.context, "battle"), "conditional_weaken", "remove").is_empty(), "结束接触不结束真实虚弱")
	cast = _cast("rinne", "armor_break", [_enemy()]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "conditional_weaken").is_empty(), "无战意不画崩刃")
	cast = _cast("homura_sword", "armor_break", [_enemy()]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "armor_break_status", "upsert").size() == 1 and _phase(intents, "conditional_burn", "upsert").size() == 1, "剑形护甲和火种分别有独立寿命")
	var first := _enemy("first"); Status.apply(first, F.status("armor_break", .25, 3, "other"))
	var second := _enemy("second"); var down := _enemy("down"); down.hp = 0
	cast = _cast("rinne", "sweep", [first, second, down]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "contact_damage", "spawn").size() == 2, "全体只对两个实际存活伤害各播一次")
	check(_phase(intents, "conditional_slow", "upsert").size() == 1 and _phase(intents, "armor_break_consumed", "spawn").size() == 1, "断阵分别读取真实缓速与消耗")
	check(_phase(intents, "conditional_slow")[0].target_id == "first", "不把条件复制到别的全体目标")
	check(_consume(policy, cast.result.events, cast.context).is_empty(), "同批事件重送不会加倍")
	var stronger := _enemy(); Status.apply(stronger, F.status("armor_break", .25, 3, "other")); Status.apply(stronger, F.status("slow", .7, 2, "other"))
	cast = _cast("rinne", "sweep", [stronger]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "conditional_slow").is_empty() and _phase(intents, "armor_break_consumed", "spawn").size() == 1, "缓速被强状态拒绝时仍可真实消耗破甲")
	first = _enemy("first"); Status.apply(first, F.status("burn", 2, 3, "other", {"base": 2.0}))
	cast = _cast("homura_sword", "sweep", [first, _enemy("second")]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "conditional_armor_break", "upsert").size() == 1 and _phase(intents, "contact_damage", "spawn").size() == 2, "燎阵按真实目标区分条件附甲")
	cast = _cast("rinne", "battle_spirit", [_enemy()]); policy = Policy.new(); intents = _feed(policy, cast)
	var spirit := _phase(intents, "battle_spirit_status", "upsert")
	check(spirit.size() == 1 and spirit[0].activation_frames == [5,6,7,8,13,14] and spirit[0].loop_frames == [15,16], "凛音战意先激活后原组循环")
	check(_phase(intents, "contact_damage").is_empty(), "纯战意不生伤害")
	cast = _cast("homura_sword", "battle_spirit", [_enemy()]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "battle_spirit_status", "upsert").size() == 1 and _phase(intents, "conditional_shield", "upsert").size() == 1, "剑形战意和条件盾各自成功")

func _test_guard() -> void:
	var cast := _cast("guard", "shield_bash", [_enemy()]); var policy = Policy.new(); var intents := _feed(policy, cast)
	check(_phase(intents, "damage_recovery", "spawn").size() == 1 and _phase(intents, "weaken_status", "upsert").size() == 1, "盾击伤害与震慑分别有真实事件")
	check(_phase(intents, "charge_interrupt").is_empty(), "无蓄力不能伪造打断")
	var source := _actor("guard"); source.stats.spd = 999
	var voice := F.enemy("saga_borrowed_voice", "voice")
	var catalog := Catalog.new(); catalog.load_all()
	var engine := BattleEngine.new(catalog); engine.set_policy(load("res://scripts/rpg/enemy_policy.gd").new())
	check(engine.start({"actors": {"source": source, "voice": voice}, "inventory": {}}, 17).started, "真实借声客战场")
	engine.advance()
	cast = _submit(engine, H._command(engine, "skill", "shield_bash", ["voice"])); policy = Policy.new(); intents = _feed(policy, cast)
	check(not _event(cast, "charge_interrupted").is_empty() and _phase(intents, "charge_interrupt", "spawn").size() == 1, "真实首领打断才能表现碎蓄力")
	# 正常首领不可打断蓄力来自真实模型状态，再由 Engine 产生免疫事件。
	var boss := F.enemy("gatekeeper", "boss")
	boss.boss = {"charge_valid": true, "charge_interruptible": false}
	var boss_engine = H._selection(BattleEngine, _actor("guard"), [boss])
	check(boss_engine.snapshot().actors.boss.boss.charge_valid and not boss_engine.snapshot().actors.boss.boss.charge_interruptible, "不可打断蓄力快照合法")
	cast = _submit(boss_engine, H._command(boss_engine, "skill", "shield_bash", ["boss"])); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "charge_interrupt").is_empty() and _phase(intents, "weaken_status", "upsert").size() == 1, "免疫打断不假装免疫独立虚弱")
	source = _actor("guard"); Status.apply(source, F.status("weaken", .2, 3, "enemy")); Status.apply(source, F.status("mark", .2, 3, "enemy"))
	cast = _cast("guard", "iron_wall", [_enemy()], source); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "cleanse", "spawn").size() == 1 and _phase(intents, "shield_sustain", "upsert").size() == 1, "多个真实净化同目标只一层，盾独立")
	check(_phase(intents, "shield_sustain")[0].activation_frames == [5,6,7,8], "铁壁按原施加组接持续组")
	cast = _cast("guard", "iron_wall", [_enemy()]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "cleanse").is_empty(), "无负面的铁壁不画净化")
	source = _actor("guard"); Status.apply_shield(source, F.shield(999, 4, "other")); Status.apply(source, F.status("weaken", .2, 3, "enemy"))
	cast = _cast("guard", "iron_wall", [_enemy()], source); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "shield_sustain").is_empty() and _phase(intents, "cleanse", "spawn").size() == 1, "弱盾拒绝不妨碍真实净化")
	cast = _cast("guard", "taunt", [_enemy()]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "taunt_status", "upsert").size() == 1 and _phase(intents, "conditional_weaken").is_empty(), "无盾挑衅只成功敌意状态")
	check(_phase(intents, "taunt_status")[0].facing_actor_id == "source" and _event(cast, "damage").is_empty(), "挑衅明确指向守卫且不生伤害")
	source = _actor("guard"); Status.apply_shield(source, F.shield(90, 3, "other"))
	cast = _cast("guard", "taunt", [_enemy()], source); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "conditional_weaken", "upsert").size() == 1, "真实施法前有盾时镇锋成功")

func _test_mint() -> void:
	var cast := _cast("mint", "mark", [_enemy()]); var policy = Policy.new(); var intents := _feed(policy, cast)
	var mark := _phase(intents, "mark_sustain", "upsert")
	check(mark.size() == 1 and mark[0].activation_frames == [9,10,11,12] and mark[0].loop_frames == [13,14,15,16], "标记激活组和持续组衔接")
	check(_phase(intents, "travel", "spawn").size() == 1 and _event(cast, "damage").is_empty(), "一颗标记弹无虚构伤害")
	var enemy := _enemy(); Status.apply(enemy, F.status("mark", .25, 3, "source"))
	cast = _cast("mint", "hunt", [enemy]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "damage_recovery", "spawn").size() == 1 and _phase(intents, "mark_consumed", "spawn").size() == 1 and _phase(intents, "mp_refund", "spawn").size() == 1, "猎杀伤害、真实消耗和回馈各自读事件")
	check(_phase(intents, "mp_refund")[0].target_id == "source", "回 MP 在施法者本人")
	cast = _cast("mint", "hunt", [_enemy()]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "mark_consumed").is_empty() and _phase(intents, "mp_refund").is_empty(), "无标记的猎杀不假消耗或回 MP")
	enemy = _enemy(); enemy.hp = 1; Status.apply(enemy, F.status("mark", .25, 3, "source"))
	cast = _cast("mint", "hunt", [enemy, _enemy("spare")]); policy = Policy.new(); intents = _feed(policy, cast)
	check(not _event(cast, "actor_defeated").is_empty(), "真实猎杀击倒")
	check(_phase(intents, "mark_consumed").is_empty() and _phase(intents, "mp_refund", "spawn").size() == 1, "KO 清理不是 skill_consumed，回馈仍可真实发生")
	cast = _cast("mint", "ambush", [_enemy()]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "damage_recovery", "spawn").size() == 1 and _phase(intents, "mark_apply_sustain", "upsert").size() == 1, "奇袭一次伤害后追踪标记独立")
	cast = _cast("mint", "smoke_screen", [_enemy()]); policy = Policy.new(); intents = _feed(policy, cast)
	check(_phase(intents, "shield_sustain", "upsert").size() == 1 and _phase(intents, "battle_spirit", "upsert").size() == 1, "烟幕盾和伏弓战意分别存续")
	check(_event(cast, "damage").is_empty(), "烟幕无额外伤害")

func _enemy_attack(cast: Dictionary, target: String) -> Dictionary:
	var errors: Array[String] = []
	H._next_actor(cast.engine, "enemy", errors)
	check(errors.is_empty(), "推进真实敌方命令")
	return _submit(cast.engine, H._command(cast.engine, "attack_physical", "", [target]))
func _test_cover() -> void:
	var ally := _actor("mint", "ally"); ally.stats.spd = 1
	var cast := _cast("guard", "cover", [ally, _enemy()]); var policy = Policy.new(); var intents := _feed(policy, cast)
	check(_phase(intents, "cover_link", "upsert").size() == 1 and _phase(intents, "cover_status", "upsert").size() == 1, "掩护自身状态产生独立连线与状态层")
	check(_phase(intents, "cover_link")[0].target_id == "source" and _phase(intents, "cover_link")[0].endpoints == ["source", "ally"], "守卫是状态拥有者，队友端点来自 snapshot")
	check(_phase(intents, "cover_redirected").is_empty(), "施放掩护时不预播转伤")
	policy.finish_action(cast.context, "battle")
	var attack := _enemy_attack(cast, "ally")
	check(attack.result.accepted and not attack.context.is_empty(), "敌击也有权威事务上下文")
	var window_context: Dictionary = Policy.context_from_enemy_events(attack.before.actors, attack.result.events)
	check(not window_context.is_empty() and not window_context.has("precast_evidence"), "自动敌击窗口不用伪造玩家施法前证明")
	check(Policy.context_from_enemy_events(attack.before.actors, cast.result.events).is_empty(), "敌击窗口桥拒绝玩家指令")
	check(Policy.context_from_enemy_events(attack.before.actors, attack.result.events + attack.result.events).is_empty(), "多个接受命令/重复序号不是一个敌击窗口")
	attack.context = window_context
	var removal := _event(attack, "status_removed"); var redirect := _event(attack, "cover_redirected")
	check(removal.payload.reason == "cover_consumed" and redirect.sequence == removal.sequence + 1, "真实转伤严格先移除再重定向")
	intents = _consume(policy, attack.result.events, attack.context)
	check(_phase(intents, "cover_link", "remove").size() == 1 and _phase(intents, "cover_status", "remove").size() == 1, "被消耗掩护的两层全部清除")
	var reaction := _phase(intents, "cover_redirected", "spawn")
	check(reaction.size() == 1 and reaction[0].source_id == "source" and reaction[0].trigger_actor_id == "enemy" and reaction[0].target_id == "source", "后续敌方动作保持原守卫来源并在实际承伤端反应")
	check(_phase(policy.finish_action(attack.context, "battle"), "cover_redirected", "remove").size() == 1, "未登记敌技能也可在本动作 E 清反应")
	check(policy.consume(redirect, attack.context, "battle").is_empty(), "转伤事件不会重复")
	check(policy.retained_variant_keys().is_empty(), "敌击 E 后释放最后掩护反应图集")
	policy = Policy.new(); _feed(policy, cast); policy.finish_action(cast.context, "battle")
	policy.consume(removal, attack.context, "battle")
	check(policy.retained_variant_keys() == ["cover"], "消耗移除与转伤之间只暂留真实掩护图集")
	var other: Dictionary = attack.context.duplicate(true); other.command_id = "unrelated"
	check(policy.consume(redirect, other, "battle").is_empty(), "未来其他命令不能冒领 cover 墓碑")
	policy = Policy.new(); _feed(policy, cast); policy.finish_action(cast.context, "battle")
	var expired: Dictionary = removal.duplicate(true); expired.payload.reason = "owner_slot_start"
	policy.consume(expired, attack.context, "battle")
	check(policy.consume(redirect, attack.context, "battle").is_empty(), "自然到期不为转伤构造证明")
	check(policy.retained_variant_keys().is_empty(), "无真实消耗的状态到期释放其唯一资源")
	policy = Policy.new(); _feed(policy, cast); policy.finish_action(cast.context, "battle")
	policy.consume(removal, attack.context, "battle")
	var late: Dictionary = redirect.duplicate(true); late.sequence += 1
	check(policy.consume(late, attack.context, "battle").is_empty(), "不邻接的迟到转伤不能消费证明")

func _test_lifecycle() -> void:
	var cast := _cast("mint", "smoke_screen", [_enemy()]); var policy = Policy.new(); _feed(policy, cast); policy.finish_action(cast.context, "battle")
	var attack := _enemy_attack(cast, "source")
	var damage := _event(attack, "damage"); var intents := _consume(policy, attack.result.events, attack.context)
	check(_phase(intents, "shield_sustain", "update").size() == 1 and _phase(intents, "shield_sustain", "update")[0].value == damage.payload.absorption.shield_after, "跨动作承伤更新原盾真实剩余量")
	var snapshot: Dictionary = cast.engine.snapshot(); snapshot.actors.enemy.stats.atk = 99999; cast.engine.restore(snapshot)
	attack = _enemy_attack(cast, "source"); intents = _consume(policy, attack.result.events.filter(func(e): return e.type != "actor_defeated"), attack.context)
	check(_phase(intents, "shield_sustain", "remove").size() == 1 and _phase(intents, "battle_spirit", "remove").size() == 1, "absorption 耗尽/倒地可独立清盾与状态")
	cast = _cast("homura_sword", "battle_spirit", [_enemy()]); policy = Policy.new(); _feed(policy, cast); policy.finish_action(cast.context, "battle")
	var errors: Array[String] = []
	var start_index: int = cast.engine.snapshot().event_log.size()
	H._next_actor(cast.engine, "p_mage", errors)
	_consume(policy, cast.engine.snapshot().event_log.slice(start_index))
	var switch_command: Dictionary = H._command(cast.engine, "switch_form"); switch_command["form_id"] = "mage"
	var switched: Dictionary = cast.engine.submit(switch_command)
	check(switched.accepted, "真实焰华切法形")
	intents = _consume(policy, switched.events)
	check(intents.is_empty() and policy.get("_layers").values().any(func(i): return i.variant_key == "homura_sword-battle_spirit"), "切形不清除原剑形状态或改用别的图集")
	# 时钟按真实事件维护；动作已退役也仍可更新，且旧移除不能删刷新代次。
	cast = _cast("mint", "mark", [_enemy()]); policy = Policy.new(); _feed(policy, cast); policy.finish_action(cast.context, "battle")
	start_index = cast.engine.snapshot().event_log.size(); H._next_actor(cast.engine, "source", errors)
	intents = _consume(policy, cast.engine.snapshot().event_log.slice(start_index))
	check(_phase(intents, "mark_sustain", "update").size() == 1, "真实目标槽时钟跨施法动作更新标记")
	var refreshed := _submit(cast.engine, H._command(cast.engine, "skill", "mark", ["enemy"]))
	intents = _feed(policy, refreshed)
	check(_phase(intents, "mark_sustain", "upsert").size() == 1, "真实同名刷新换新 generation")
	var old: Dictionary = _status_events(cast, "mark")[0]
	var forged_removal := {"sequence": refreshed.context.last_sequence + 1, "type": "status_removed", "actor_id": "enemy", "target_id": "enemy", "payload": {"status": old.payload.status, "reason": "target_slot_end"}}
	check(policy.consume(forged_removal, {}, "battle").is_empty(), "旧 generation 的移除不能清新层")
	check(policy.consume(old, cast.context, "battle").is_empty(), "迟到旧施加不能复活旧图")
	var newer: Dictionary = _status_events(refreshed, "mark")[0]
	var early = Policy.new(); early.begin_action(cast.context, "battle", _groups(cast.context))
	var tick := {"sequence": newer.sequence + 1, "type": "status_tick", "actor_id": "enemy", "target_id": "enemy", "payload": {"status": newer.payload.status}}
	early.consume(tick, {}, "battle")
	check(early.consume(old, cast.context, "battle").is_empty(), "先到时钟不新造图，却挡住旧施加")

func _test_identity_and_bounds() -> void:
	var cast := _cast("rinne", "armor_break", [_enemy()]); var policy = Policy.new()
	check(policy.begin_action(cast.context, "battle", _groups(cast.context)), "注册身份回归夹具")
	var wrong: Dictionary = cast.context.duplicate(true); wrong.form = "homura_sword"; wrong.variant_key = "homura_sword-armor_break"
	check(policy.consume(_event(cast, "damage"), wrong, "battle").is_empty(), "错误形态 context 不抢同一事件")
	check(_phase(policy.consume(_event(cast, "damage"), cast.context, "battle"), "contact_damage", "spawn").size() == 1, "拒绝错误 context 后正确事件仍可用")
	policy.cancel_action(cast.context, "battle")
	check(policy.consume(_status_events(cast, "armor_break")[0], cast.context, "battle").is_empty(), "取消后迟到的新状态层不能建立")
	check(not policy.begin_action(cast.context, "battle", _groups(cast.context)), "同一命令不重开")
	policy.clear()
	check(not policy.begin_action(cast.context, "battle", _groups(cast.context)), "clear 后旧战场不能重开")
	check(policy.begin_action(cast.context, "next_battle", _groups(cast.context)), "新战場代次可继续")
	check(policy.consume(_event(cast, "damage"), cast.context, "battle").is_empty(), "新战场拒旧战场事件")
	policy = Policy.new(); _feed(policy, cast)
	var cancelled: Array = policy.cancel_action(cast.context, "battle")
	check(_phase(cancelled, "armor_break_status", "remove").is_empty(), "取消呈现不撤销已真实提交的状态")
	policy = Policy.new(); policy.begin_action(cast.context, "battle", _groups(cast.context))
	for sequence in range(1, 2200): policy.consume({"sequence": sequence, "type": "round_snapshot", "actor_id": "enemy", "target_id": "enemy", "payload": {}}, {}, "battle")
	check(policy.consume(_event(cast, "damage"), cast.context, "battle").is_empty(), "有界窗口淘汰旧序号后不重播")
	check(policy.get("_seen").size() <= Policy.MAX_HISTORY and policy.get("_cover_consumed").size() <= Policy.MAX_HISTORY, "事件和跨动作证据缓存有界")

func _test_contract_export() -> void:
	var output: Dictionary = {"schema": 1, "contract_id": "physical_skill_visual_v1", "integration_status": "manifest_bound_renderer_pending", "variants": {}}
	for form in Policy.SKILLS:
		for skill in Policy.SKILLS[form]:
			var variant := "%s-%s" % [form, skill] if form in ["rinne", "homura_sword"] else str(skill)
			var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/effects/imagegen_spells/%s/manifest.json" % variant))
			var contract: Dictionary = Policy.bindings(form, skill, manifest.phase_groups)
			check(not contract.is_empty(), "有限绑定完整覆盖 " + variant)
			var bad: Dictionary = manifest.phase_groups.duplicate(true)
			bad[bad.keys()[0]].activation_frames = [999]
			check(Policy.bindings(form, skill, bad).is_empty(), "非法帧不允许静默放宽 " + variant)
			bad = manifest.phase_groups.duplicate(true); bad[bad.keys()[0]].binding = "automatic"
			check(Policy.bindings(form, skill, bad).is_empty(), "未知绑定模式拒绝 " + variant)
			var declared: Dictionary = manifest.phase_groups.duplicate(true)
			for group in declared.values(): group.binding = "physical_skill_visual_v1"
			check(Policy.bindings(form, skill, declared) == contract, "显式绑定只改合同状态不改原帧 " + variant)
			var reactions: Dictionary = Policy.reaction_bindings(form, skill, manifest.phase_groups)
			output.variants[variant] = {"form": form, "ability_id": skill, "variant_key": variant, "event_layers": contract, "reaction_layers": reactions, "proposed_phase_groups": declared}
	var location := OS.get_environment("PHYSICAL_POLICY_OUTPUT")
	check(not location.is_empty(), "规范导出仅写隔离入口指定证据路径")
	if not location.is_empty():
		var file := FileAccess.open(location.path_join("physical-skill-event-bindings.json"), FileAccess.WRITE)
		check(file != null, "有限绑定规范可写")
		if file != null: file.store_string(JSON.stringify(output, "  ", true) + "\n")

func _test_out_of_order_life() -> void:
	var ally := _actor("guard", "ally"); ally.stats.spd = 1
	var foe := _enemy(); foe.stats.atk = 99999
	var cast := _cast("mint", "smoke_screen", [ally, foe])
	var lethal := _enemy_attack(cast, "source")
	var death := _event(lethal, "actor_defeated")
	check(not death.is_empty(), "同一真实战场先击倒")
	var errors: Array[String] = []
	H._next_actor(cast.engine, "ally", errors)
	var revival := _submit(cast.engine, H._command(cast.engine, "item", "revival_potion", ["source"]))
	var revived := _event(revival, "revived")
	check(revival.result.accepted and not revived.is_empty(), "同一真实战场再复活")
	for attempt in 4:
		H._next_actor(cast.engine, "source", errors)
		if cast.engine.preview(H._command(cast.engine, "skill", "smoke_screen")).legal: break
		cast.engine.submit(H._command(cast.engine, "defend"))
	var fresh := _submit(cast.engine, H._command(cast.engine, "skill", "smoke_screen"))
	check(fresh.result.accepted and errors.is_empty(), "复活后真实重新施盾")
	var shield := _event(fresh, "shield_applied")
	check(int(death.sequence) < int(revived.sequence) and int(revived.sequence) < int(shield.sequence), "权威顺序是死亡、复活、新盾")
	var policy = Policy.new(); policy.begin_action(fresh.context, "battle", _groups(fresh.context))
	check(_phase(policy.consume(shield, fresh.context, "battle"), "shield_sustain", "upsert").size() == 1, "传输乱序先收到新盾")
	check(policy.consume(death, {}, "battle").is_empty(), "旧死亡不能删除更晚存活代次的护盾")
	policy.consume(revived, {}, "battle")
	check(policy.get("_layers").values().any(func(layer): return layer.status_id == "shield" and layer.value.generation == shield.payload.shield.generation), "迟到复活后新盾原代次仍存在")
	# 被保护端也由新掩护的权威状态证明存活，不能被其旧死亡拆除连线。
	ally = _actor("mint", "ally"); ally.stats.spd = 1
	foe = _enemy(); foe.stats.atk = 99999
	cast = _cast("guard", "iron_wall", [ally, foe])
	lethal = _enemy_attack(cast, "ally"); death = _event(lethal, "actor_defeated")
	H._next_actor(cast.engine, "source", errors)
	revival = _submit(cast.engine, H._command(cast.engine, "item", "revival_potion", ["ally"]))
	revived = _event(revival, "revived")
	H._next_actor(cast.engine, "source", errors)
	fresh = _submit(cast.engine, H._command(cast.engine, "skill", "cover", ["ally"]))
	check(fresh.result.accepted and not death.is_empty() and not revived.is_empty(), "真实复活后重新掩护队友")
	policy = Policy.new(); _feed(policy, fresh)
	check(policy.consume(death, {}, "battle").is_empty(), "队友旧死亡不能移除更新的掩护双端点")
	policy.consume(revived, {}, "battle")
	check(policy.get("_layers").values().filter(func(layer): return layer.status_id == "cover").size() == 2, "复活后两条掩护层都保留")

func _test_ineligible_dedup() -> void:
	var cast := _cast("mint", "mark", [_enemy()]); var policy = Policy.new()
	policy.begin_action(cast.context, "battle", _groups(cast.context))
	var applied: Dictionary = _status_events(cast, "mark")[0]
	policy.consume(applied, cast.context, "battle")
	var duplicate: Dictionary = applied.duplicate(true); duplicate.sequence = cast.context.last_sequence
	check(policy.consume(duplicate, cast.context, "battle").is_empty(), "同代状态重标序号也不能再播激活")
	var enemy := _enemy(); Status.apply(enemy, F.status("mark", .25, 3, "source"))
	cast = _cast("mint", "hunt", [enemy]); policy = Policy.new(); policy.begin_action(cast.context, "battle", _groups(cast.context))
	var refund := _event(cast, "mp_restored"); var zero: Dictionary = refund.duplicate(true); zero.payload.actual = 0
	check(policy.consume(zero, cast.context, "battle").is_empty(), "零回馈不触发")
	check(policy.consume(refund, cast.context, "battle").is_empty(), "已观察的不合格条件同序号不能之后伪触发")
	var rejected: Dictionary = cast.engine.submit(H._command(cast.engine, "skill", "hunt", ["missing"]))
	check(Policy.context_from_result(cast.engine.snapshot(), cast.derived, rejected).is_empty(), "真实非法命令无法建立上下文")
