# 直接调用纯模型，断言源自规格，不经过 UI 或随机采样。
extends RefCounted

const Fixtures = preload("res://tools/rpg/fixtures.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Factory = preload("res://scripts/rpg/actor_factory.gd")
const State = preload("res://scripts/rpg/battle_state.gd")

static func run() -> Array[String]:
	Fixtures.assertion_count = 0
	var failures: Array[String] = []
	for script in ["damage_rules", "status_rules"]:
		Fixtures.expect(FileAccess.file_exists("res://scripts/rpg/%s.gd" % script), "未实现规则：" + script, failures)
	if not failures.is_empty():
		return failures
	var Damage = load("res://scripts/rpg/damage_rules.gd")
	var Status = load("res://scripts/rpg/status_rules.gd")
	_test_damage(Damage, failures)
	_test_absorb(Damage, failures)
	_test_strength(Status, failures)
	_test_shield(Status, Damage, failures)
	_test_slot_clocks(Status, Damage, failures)
	_test_round_clocks(Status, failures)
	_test_stun_and_cleanse(Status, failures)
	_test_snapshot_compatibility(Status, Damage, failures)
	_test_clock_guards(Status, Damage, failures)
	print("RPG rules 断言：", Fixtures.assertion_count)
	return failures

static func _test_damage(Damage, failures: Array[String]) -> void:
	var sword := Fixtures.actor("swordsman", "sword")
	var mage := Fixtures.actor("mage", "mage")
	var healer := Fixtures.actor("healer", "healer")
	var target := Fixtures.actor("swordsman", "target")
	target.stats.def = 25
	var catalog = Catalog.new()
	catalog.load_all()
	var heavy: Dictionary = catalog.get_definition("skills", "heavy_slash").effects[0]
	var fire: Dictionary = catalog.get_definition("skills", "firebolt").effects[0]
	Fixtures.expect(Damage.direct(sword, target, heavy, {}, false).get("damage", -1) == 72, "五级重斩 DEF25 = 72", failures)
	Fixtures.expect(Damage.heal_amount(20.0, 1.2, float(healer.stats.matk)) == 86, "五级愈合 = 86", failures)
	Fixtures.expect(Damage.direct(mage, target, fire, {}, false).get("damage", -1) == 73, "五级火弹 MDEF25 = 73", failures)
	var burn_effect: Dictionary = catalog.get_definition("skills", "burn_brand").effects[1]
	var burn_snapshot: Dictionary = Damage.burn_snapshot(mage, burn_effect)
	Fixtures.expect(is_equal_approx(float(burn_snapshot.get("base", -1.0)), 13.0), "灼印保存每跳基础量13", failures)
	var burn := Fixtures.status("burn", 13.0, 3, "mage")
	burn.snapshot = burn_snapshot
	Fixtures.expect(Damage.periodic(burn, target).get("damage", -1) == 13, "灼烧不读 DEF/MDEF", failures)
	var direct_effect := {"damage_type": "physical", "coefficient": 1.0, "element": "neutral", "can_crit": true}
	sword.stats.atk = 100
	target.stats.def = 0
	target.statuses = [Fixtures.status("defend", 0.4, 1, "target")]
	var result: Dictionary = Damage.direct(sword, target, direct_effect, {"cover_reduction": 0.3}, false)
	Fixtures.expect(result.get("damage", -1) == 42, "100 × 防御0.6 × 掩护0.7 = 42", failures)
	Fixtures.expect(is_equal_approx(float(result.get("factors", {}).get("unrounded", -1.0)), 42.0), "日志保存未取整乘区结果", failures)
	target.statuses = []
	sword.stats.atk = 1
	target.stats.def = 999
	Fixtures.expect(Damage.direct(sword, target, direct_effect, {}, false).get("damage", -1) == 1, "非零直接伤害至少1", failures)
	direct_effect.coefficient = 0.0
	Fixtures.expect(Damage.direct(sword, target, direct_effect, {}, true).get("damage", -1) == 0, "零系数不是保底伤害", failures)
	direct_effect.coefficient = 1.0
	sword.stats.atk = 7
	target.stats.def = 33
	target.weaknesses = ["fire"]
	direct_effect.element = "fire"
	var fractional: Dictionary = Damage.direct(sword, target, direct_effect, {"output_bonuses": [0.11]}, true)
	Fixtures.expect(fractional.get("damage", -1) == 11, "只在最终取整，保留中间小数", failures)
	Fixtures.expect(is_equal_approx(float(fractional.get("factors", {}).get("unrounded", -1.0)), 7.0 * 100.0 / 133.0 * 1.25 * 1.11 * 1.5), "完整精度乘区可重放", failures)
	sword.stats.atk = 100
	target.stats.def = 100
	target.weaknesses = []
	direct_effect.element = "neutral"
	target.statuses = [Fixtures.status("armor_break", 0.25, 2, "source")]
	Fixtures.expect(Damage.direct(sword, target, direct_effect, {}, false).get("damage", -1) == 57, "减防先作用于防御值", failures)
	target.statuses = [Fixtures.status("magic_break", 0.25, 2, "source")]
	target.stats.mdef = 100
	var magic_effect := {"damage_type": "magic", "coefficient": 1.0, "element": "neutral", "can_crit": true}
	mage.stats.matk = 100
	Fixtures.expect(Damage.direct(mage, target, magic_effect, {}, false).get("damage", -1) == 57, "物理魔法共用减防管线", failures)
	target.stats.def = 0
	target.statuses = [Fixtures.status("stagger", 0.2, 1, "source"), Fixtures.status("defend", 0.4, 1, "target")]
	sword.statuses = [Fixtures.status("battle_spirit", 0.4, 2, "sword"), Fixtures.status("weaken", 0.2, 2, "enemy")]
	var capped: Dictionary = Damage.direct(sword, target, direct_effect, {"output_bonuses": [0.3, 0.2], "vulnerability_bonuses": [0.2], "damage_reductions": [0.1, 0.3], "cover_reduction": 0.3}, true)
	Fixtures.expect(capped.get("damage", -1) == 95, "输出+50%／易伤+25%封顶，减伤同类只取最强", failures)
	Fixtures.expect(is_equal_approx(float(capped.get("factors", {}).get("output_factor", -1.0)), 1.5), "输出乘区封顶日志", failures)
	Fixtures.expect(is_equal_approx(float(capped.get("factors", {}).get("vulnerability_factor", -1.0)), 1.25), "易伤乘区封顶日志", failures)
	Fixtures.expect(is_equal_approx(float(capped.get("factors", {}).get("reduction_factor", -1.0)), 0.6), "防御和同类减伤不连乘", failures)
	Fixtures.expect(Damage.heal_amount(20.0, 1.2, 55.0) == 86, "治疗接口不接收虚弱／战意乘区", failures)
	target.statuses = []
	sword.statuses = []
	target.resistances = ["fire"]
	direct_effect.element = "fire"
	Fixtures.expect(Damage.direct(sword, target, direct_effect, {}, false).get("damage", -1) == 75, "当前火抗0.75", failures)
	direct_effect.element = "neutral"
	target.resistances = ["neutral"]
	target.weaknesses = ["neutral"]
	Fixtures.expect(Damage.direct(sword, target, direct_effect, {}, false).get("damage", -1) == 100, "中性固定1", failures)
	direct_effect.can_crit = false
	Fixtures.expect(Damage.direct(sword, target, direct_effect, {}, true).get("damage", -1) == 100, "禁止暴击的效果不会因输入true暴击", failures)
	# 灼烧只保存适用持续输出与虚弱，不保存战意、目标防御、目标抗性。
	mage.statuses = [Fixtures.status("battle_spirit", 0.4, 2, "mage"), Fixtures.status("weaken", 0.2, 2, "enemy")]
	mage.stats.matk = 65
	burn_snapshot = Damage.burn_snapshot(mage, burn_effect, {"output_bonuses": [0.25]})
	Fixtures.expect(is_equal_approx(float(burn_snapshot.get("base", -1.0)), 13.0), "灼烧保存13 × 1.25 × 0.8，战意不参与", failures)
	burn.magnitude = float(burn_snapshot.get("base", 0.0))
	burn.snapshot = burn_snapshot
	mage.hp = 0
	mage.stats.matk = 1
	mage.statuses = []
	target.weaknesses = []
	target.resistances = ["fire"]
	target.stats.mdef = 999
	target.statuses = [Fixtures.status("defend", 0.4, 1, "target"), Fixtures.status("stagger", 0.2, 1, "source")]
	var tick: Dictionary = Damage.periodic(burn, target)
	Fixtures.expect(tick.get("damage", -1) == 6, "跳伤只读当前火抗与减伤，不读来源死亡／防御／易伤／暴击", failures)
	Fixtures.expect(is_equal_approx(float(tick.get("factors", {}).get("base", -1.0)), 13.0), "灼烧日志保留施加源快照", failures)
	Fixtures.expect(Damage.heal_amount(0.0, 0.0, 55.0) == 0, "零治疗不强制变1", failures)

static func _test_absorb(Damage, failures: Array[String]) -> void:
	var target := Fixtures.actor("swordsman", "target")
	target.shield = Fixtures.shield(30, 2, "guard")
	var zero_before := target.duplicate(true)
	var zero: Dictionary = Damage.absorb(target, 0)
	Fixtures.expect(target == zero_before and zero.get("absorbed", -1) == 0 and zero.get("hp_loss", -1) == 0, "零伤害完全不消耗护盾", failures)
	var first: Dictionary = Damage.absorb(target, 42)
	Fixtures.expect(first.get("absorbed", -1) == 30 and first.get("hp_loss", -1) == 12 and not first.get("defeated", true), "减伤后30盾只损12HP", failures)
	Fixtures.expect(target.hp == 228 and target.shield.is_empty(), "盾吸收后耗尽清空", failures)
	target.statuses = [Fixtures.status("weaken", 0.2, 2, "enemy"), Fixtures.status("cover", 0.3, 1, "target")]
	target.intent = {"ability_id": "bite"}
	target.boss = {"phase": 2, "charge_valid": true, "charge_interruptible": true}
	var lethal: Dictionary = Damage.absorb(target, 999)
	Fixtures.expect(lethal.get("hp_loss", -1) == 228 and lethal.get("defeated", false) and target.hp == 0, "致死不令HP为负且记录实际HP损失", failures)
	Fixtures.expect(target.statuses.is_empty() and target.shield.is_empty() and target.intent.is_empty() and not target.boss.get("charge_valid", false) and target.boss.phase == 2, "倒地清本地状态／盾／待释放而保留Boss阶段", failures)
	Fixtures.expect(Damage.absorb(target, 100).get("hp_loss", -1) == 0, "倒地后不重复扣HP", failures)
	var guarded := Fixtures.actor("guard", "guard")
	guarded.shield = Fixtures.shield(100, 2, "guard")
	Damage.absorb(guarded, 20)
	Fixtures.expect(guarded.hp == 320 and guarded.shield.get("amount", -1) == 80 and guarded.shield.get("remaining", -1) == 2, "部分吸收只扣剩余量不扣时长", failures)

static func _test_strength(Status, failures: Array[String]) -> void:
	var actor := Fixtures.actor("guard", "guard")
	var incoming := Fixtures.status("weaken", 0.4, 2, "strong")
	var original := incoming.duplicate(true)
	var add: Dictionary = Status.apply(actor, incoming)
	Fixtures.expect(add.get("applied", false) and add.get("change", "") == "added", "新增状态报告实际生效", failures)
	Fixtures.expect(incoming == original, "施加不改写传入状态", failures)
	var before := actor.duplicate(true)
	var weaker: Dictionary = Status.apply(actor, Fixtures.status("weaken", 0.2, 99, "weak"))
	Fixtures.expect(not weaker.get("applied", true) and actor == before, "弱状态完全忽略且不延长／改变generation", failures)
	var equal: Dictionary = Status.apply(actor, Fixtures.status("weaken", 0.4, 4, "equal"))
	var current := Fixtures.find_status(actor, "weaken")
	Fixtures.expect(equal.get("applied", false) and current.get("remaining", -1) == 4 and current.get("generation", -1) > before.statuses[0].generation, "同强取较长并刷新generation", failures)
	Status.apply(actor, Fixtures.status("weaken", 0.4, 1, "short"))
	Fixtures.expect(Fixtures.find_status(actor, "weaken").get("remaining", -1) == 4, "同强短时长不缩短", failures)
	Status.apply(actor, Fixtures.status("weaken", 0.5, 1, "stronger"))
	current = Fixtures.find_status(actor, "weaken")
	Fixtures.expect(current.get("magnitude", -1.0) == 0.5 and current.get("remaining", -1) == 1 and current.get("source_id", "") == "stronger", "强状态替换幅度与自己的时长", failures)
	actor.statuses = []
	Status.apply(actor, Fixtures.status("burn", 13.0, 3, "mage"))
	before = actor.duplicate(true)
	Status.apply(actor, Fixtures.status("burn", 6.0, 20, "enemy"))
	Fixtures.expect(actor == before, "灼烧按保存每跳基础量比较强度", failures)

static func _test_shield(Status, Damage, failures: Array[String]) -> void:
	var actor := Fixtures.actor("guard", "guard")
	var original := Fixtures.shield(70, 2, "guard")
	var saved := original.duplicate(true)
	Status.apply_shield(actor, original)
	Fixtures.expect(original == saved and actor.shield.get("amount", -1) == 70, "护盾独立总量，施加不改输入", failures)
	Damage.absorb(actor, 10)
	var before := actor.duplicate(true)
	var weaker: Dictionary = Status.apply_shield(actor, Fixtures.shield(59, 8, "ally"))
	Fixtures.expect(not weaker.get("applied", true) and actor == before, "较弱新盾不续当前剩余强盾", failures)
	Status.apply_shield(actor, Fixtures.shield(60, 3, "ally"))
	Fixtures.expect(actor.shield.get("amount", -1) == 60 and actor.shield.get("remaining", -1) == 3 and actor.shield.get("generation", -1) > before.shield.generation, "同量按当前剩余量刷新时长", failures)
	Status.apply_shield(actor, Fixtures.shield(80, 1, "ally"))
	Fixtures.expect(actor.shield.get("amount", -1) == 80 and actor.shield.get("remaining", -1) == 1, "更强盾替换为新时长", failures)
	before = actor.duplicate(true)
	Status.apply_shield(actor, Fixtures.shield(0, 2, "ally"))
	Fixtures.expect(actor == before, "零量护盾无有效效果", failures)

static func _test_slot_clocks(Status, Damage, failures: Array[String]) -> void:
	var actor := Fixtures.actor("swordsman", "sword")
	var token: Dictionary = Status.begin_slot(actor)
	Status.apply(actor, Fixtures.status("battle_spirit", 0.4, 2, "sword"))
	Status.end_slot(actor, token)
	Fixtures.expect(actor.slot_count == 1 and Fixtures.find_status(actor, "battle_spirit").get("remaining", -1) == 2, "自身新增战意本槽不扣，剩未来2槽", failures)
	var target := Fixtures.actor("guard", "target")
	var effect := {"damage_type": "physical", "element": "neutral", "coefficient": 1.0, "can_crit": false}
	target.stats.def = 0
	for index in range(2):
		token = Status.begin_slot(actor)
		Fixtures.expect(Damage.direct(actor, target, effect, {}, false).get("damage", -1) == 84, "战意覆盖后续槽%d" % (index + 1), failures)
		Status.end_slot(actor, token)
	Fixtures.expect(Fixtures.find_status(actor, "battle_spirit").is_empty(), "战意在第二个未来槽末移除", failures)
	Status.apply(actor, Fixtures.status("weaken", 0.2, 2, "enemy"))
	for index in range(2):
		token = Status.begin_slot(actor)
		Fixtures.expect(Damage.direct(actor, target, effect, {}, false).get("damage", -1) == 48, "虚弱覆盖目标未来槽%d（无论命令）" % (index + 1), failures)
		Status.end_slot(actor, token)
	Fixtures.expect(Fixtures.find_status(actor, "weaken").is_empty() and actor.slot_count == 5, "虚弱准确消耗两槽", failures)
	Status.apply(actor, Fixtures.status("battle_spirit", 0.4, 2, "sword"))
	token = Status.begin_slot(actor)
	Status.apply(actor, Fixtures.status("battle_spirit", 0.4, 2, "sword"))
	Status.end_slot(actor, token)
	Fixtures.expect(Fixtures.find_status(actor, "battle_spirit").get("remaining", -1) == 2, "同槽刷新generation不当场扣时长", failures)
	token = Status.begin_slot(actor)
	var removed_generation: int = Fixtures.find_status(actor, "battle_spirit").get("generation", -1)
	actor.statuses = []
	Status.apply(actor, Fixtures.status("battle_spirit", 0.4, 2, "sword"))
	Status.end_slot(actor, token)
	Fixtures.expect(Fixtures.find_status(actor, "battle_spirit").get("remaining", -1) == 2 and Fixtures.find_status(actor, "battle_spirit").get("generation", -1) > removed_generation, "同槽移除再施加不会generation碰撞", failures)
	var clone := actor.duplicate(true)
	var a_token: Dictionary = Status.begin_slot(actor)
	var b_token: Dictionary = Status.begin_slot(clone)
	Status.apply(actor, Fixtures.status("weaken", 0.2, 2, "enemy"))
	Status.apply(clone, Fixtures.status("weaken", 0.2, 2, "enemy"))
	Fixtures.expect(actor == clone and a_token == b_token, "快照恢复后计数／generation／token确定一致", failures)
	Status.end_slot(actor, a_token)
	Status.end_slot(clone, b_token)
	Fixtures.expect(actor == clone, "恢复后的结束结算一致", failures)
	# 槽开始先失效防御，再进行灼烧，盾仍可吸收。
	var burned := Fixtures.actor("guard", "burned")
	Status.apply(burned, Fixtures.status("defend", 0.4, 1, "burned"))
	Status.apply(burned, Fixtures.status("cover", 0.3, 1, "burned", {"target_id": "friend"}))
	Status.apply(burned, Fixtures.status("burn", 20.0, 2, "mage"))
	Status.apply_shield(burned, Fixtures.shield(5, 2, "healer"))
	token = Status.begin_slot(burned)
	Fixtures.expect(burned.hp == 305 and burned.shield.is_empty(), "防御先到期，灼烧20先扣5盾再损15HP", failures)
	Fixtures.expect(Fixtures.find_status(burned, "defend").is_empty() and Fixtures.find_status(burned, "cover").is_empty(), "防御／掩护在其拥有者下槽开始移除", failures)
	var events: Array = token.get("events", [])
	Fixtures.expect(events.size() >= 3 and events[0].get("type", "") == "status_removed" and events[events.size() - 1].get("type", "") == "periodic_damage", "到期事件先于灼烧事件", failures)
	Status.end_slot(burned, token)
	Fixtures.expect(Fixtures.find_status(burned, "burn").get("remaining", -1) == 1, "灼烧槽末才扣次数", failures)
	burned.hp = 0
	var frozen := burned.duplicate(true)
	token = Status.begin_slot(burned)
	Status.end_slot(burned, token)
	Fixtures.expect(burned == frozen and token.get("defeated", false), "倒地期间不推进槽／状态／盾", failures)
	var shielded := Fixtures.actor("guard", "shielded")
	token = Status.begin_slot(shielded)
	Status.apply_shield(shielded, Fixtures.shield(70, 2, "shielded"))
	Status.end_slot(shielded, token)
	Fixtures.expect(shielded.shield.get("remaining", -1) == 2, "自身新盾本槽不减时长", failures)
	for index in range(2):
		token = Status.begin_slot(shielded)
		Status.end_slot(shielded, token)
	Fixtures.expect(shielded.shield.is_empty(), "盾准确覆盖未来两槽", failures)

static func _test_round_clocks(Status, failures: Array[String]) -> void:
	var actor := Fixtures.actor("ranger", "b")
	var other := Fixtures.actor("guard", "a")
	var actors := {"b": actor, "a": other}
	Status.begin_round(actors)
	Status.apply(actor, Fixtures.status("slow", 0.3, 1, "mage"))
	Status.end_round(actors)
	Fixtures.expect(Fixtures.find_status(actor, "slow").get("remaining", -1) == 1, "轮内施加缓速不消耗本轮快照", failures)
	var events: Array = Status.begin_round(actors)
	Fixtures.expect(events.size() == 2 and events[0].get("actor_id", "") == "a" and events[1].get("actor_id", "") == "b", "轮序快照事件按永久ID排序", failures)
	Fixtures.expect(_speed_event(events, "b").get("effective_spd", -1.0) == 35.0, "冰矢影响下一次快照SPD50×0.7", failures)
	Fixtures.expect(not Fixtures.find_status(actor, "slow").is_empty(), "最后一次快照后仍留状态至该轮末", failures)
	var slot: Dictionary = Status.begin_slot(actor)
	Status.end_slot(actor, slot)
	Fixtures.expect(not Fixtures.find_status(actor, "slow").is_empty(), "缓速不按目标槽移除", failures)
	Status.end_round(actors)
	Fixtures.expect(Fixtures.find_status(actor, "slow").is_empty(), "冰矢最后受影响轮结束移除", failures)
	Status.apply(actor, Fixtures.status("slow", 0.3, 2, "controller"))
	for index in range(2):
		events = Status.begin_round(actors)
		Fixtures.expect(_speed_event(events, "b").get("effective_spd", -1.0) == 35.0, "迟滞影响未来快照%d" % (index + 1), failures)
		Status.end_round(actors)
		Fixtures.expect(Fixtures.find_status(actor, "slow").is_empty() == (index == 1), "迟滞仅在第二次受影响轮末移除", failures)
	Status.apply(actor, Fixtures.status("slow", 0.3, 1, "mage"))
	Status.begin_round(actors)
	Status.apply(actor, Fixtures.status("slow", 0.3, 2, "controller"))
	Status.end_round(actors)
	Fixtures.expect(Fixtures.find_status(actor, "slow").get("remaining", -1) == 2, "末次快照轮内同幅刷新不被旧到期记录移除", failures)
	Status.begin_round(actors)
	var snapshot_before := actors.duplicate(true)
	Status.apply(actor, Fixtures.status("slow", 0.2, 99, "weak"))
	Fixtures.expect(actors == snapshot_before, "较弱缓速不续强缓速也不改变快照记录", failures)
	Status.cleanse(actor)
	Fixtures.expect(Fixtures.find_status(actor, "slow").is_empty(), "缓速净化只移除状态，不负责重排现有队列", failures)

static func _test_stun_and_cleanse(Status, failures: Array[String]) -> void:
	var actor := Fixtures.actor("controller", "actor")
	var stun_effect := {"type": "apply_status", "status_id": "stun"}
	var interrupt := {"type": "interrupt"}
	Fixtures.expect(Status.immunity(actor, stun_effect).is_empty(), "普通存活目标可眩晕", failures)
	Status.apply(actor, Fixtures.status("stun", 1.0, 1, "enemy"))
	var token: Dictionary = Status.begin_slot(actor)
	Fixtures.expect(token.get("stunned", false) and actor.slot_count == 1 and actor.opportunity_count == 0, "眩晕跳过槽但推进槽计数，不制造命令机会", failures)
	Status.end_slot(actor, token)
	Fixtures.expect(Fixtures.find_status(actor, "stun").is_empty() and Fixtures.find_status(actor, "awake").get("remaining", -1) == 2, "消耗眩晕槽后生成2槽清醒且本槽不扣", failures)
	for index in range(2):
		Fixtures.expect(not Status.immunity(actor, stun_effect).is_empty(), "清醒覆盖未来槽%d" % (index + 1), failures)
		var before := actor.duplicate(true)
		Fixtures.expect(not Status.apply(actor, Fixtures.status("stun", 1.0, 1, "enemy")).get("applied", true) and actor == before, "清醒拒绝新眩晕不改状态", failures)
		token = Status.begin_slot(actor)
		Status.end_slot(actor, token)
	Fixtures.expect(Status.immunity(actor, stun_effect).is_empty(), "2槽清醒后可再次眩晕", failures)
	Status.apply(actor, Fixtures.status("stun", 1.0, 1, "enemy"))
	Status.cleanse(actor)
	token = Status.begin_slot(actor)
	Status.end_slot(actor, token)
	Fixtures.expect(Fixtures.find_status(actor, "awake").is_empty(), "提前净化眩晕不额外授予清醒", failures)
	Status.apply(actor, Fixtures.status("awake", 1.0, 2, "actor"))
	actor.boss = {"charge_valid": true, "charge_interruptible": true}
	Fixtures.expect(Status.immunity(actor, interrupt).is_empty(), "清醒不阻止打断", failures)
	Fixtures.expect(Status.immunity(actor, {"type": "apply_status", "status_id": "weaken"}).is_empty(), "清醒不阻止软控制", failures)
	actor.statuses = []
	actor.boss.charge_interruptible = false
	Fixtures.expect(not Status.immunity(actor, stun_effect).is_empty() and not Status.immunity(actor, interrupt).is_empty(), "不可打断蓄力同时拒绝眩晕和打断", failures)
	Fixtures.expect(Status.immunity(actor, {"type": "apply_status", "status_id": "slow"}).is_empty(), "不可打断蓄力不阻止缓速", failures)
	actor.boss.charge_valid = false
	Fixtures.expect(Status.immunity(actor, stun_effect).is_empty(), "蓄力无效后不保留硬控免疫", failures)
	actor.boss = {}
	Fixtures.expect(not Status.immunity(actor, interrupt).is_empty(), "没有蓄力无法产生有效打断", failures)
	# 净化准确八种；蓄力／阶段在boss字典里，其他正面不动。
	actor.statuses = []
	var negative_ids := ["burn", "weaken", "armor_break", "magic_break", "slow", "mark", "taunt", "stun"]
	for id in negative_ids:
		actor.statuses.append(Fixtures.status(id, 1.0, 2, "enemy"))
	for id in ["awake", "battle_spirit", "defend", "cover", "stagger"]:
		actor.statuses.append(Fixtures.status(id, 1.0, 2, "actor"))
	actor.boss = {"phase": 2, "charge_valid": true, "charge_interruptible": false}
	var boss_before: Dictionary = actor.boss.duplicate(true)
	var removed: Array = Status.cleanse(actor)
	Fixtures.expect(removed.size() == 8 and actor.statuses.size() == 5, "净化移除且只移除规格8种可驱散负面", failures)
	for id in negative_ids:
		Fixtures.expect(Fixtures.find_status(actor, id).is_empty(), "净化移除" + id, failures)
	for id in ["awake", "battle_spirit", "defend", "cover", "stagger"]:
		Fixtures.expect(not Fixtures.find_status(actor, id).is_empty(), "净化保留" + id, failures)
	Fixtures.expect(actor.boss == boss_before, "净化不改蓄力／阶段", failures)
	Fixtures.expect(Status.cleanse(actor).is_empty(), "无负面净化没有虚假变更", failures)

static func _test_snapshot_compatibility(Status, Damage, failures: Array[String]) -> void:
	var actor := Fixtures.actor("mage", "mage")
	Status.apply(actor, Fixtures.status("burn", 13.0, 3, "source", Damage.burn_snapshot(actor, {"magnitude": 0.2})))
	Status.apply(actor, Fixtures.status("slow", 0.3, 2, "source"))
	Status.apply_shield(actor, Fixtures.shield(30, 2, "source"))
	Status.begin_round({"mage": actor})
	var errors: Array[String] = State.validate(Fixtures.state(actor))
	Fixtures.expect(errors.is_empty(), "真实规则状态／generation／轮次快照符合现有验证器：" + str(errors), failures)
	var restored = JSON.parse_string(JSON.stringify(Fixtures.state(actor)))
	# 保存层会规范化整数；这里检查所有新增值只含JSON值，不含Node／资源。
	Fixtures.expect(restored is Dictionary and restored.actors.mage.get("status_generation", -1) == actor.get("status_generation", -1), "generation计数保留在JSON快照可恢复", failures)

static func _speed_event(events: Array, id: String) -> Dictionary:
	for event in events:
		if event.get("actor_id", "") == id:
			return event.get("payload", {})
	return {}

static func _test_clock_guards(Status, Damage, failures: Array[String]) -> void:
	var actor := Fixtures.actor("swordsman", "actor")
	Status.apply(actor, Fixtures.status("weaken", 0.2, 2, "enemy"))
	Status.apply_shield(actor, Fixtures.shield(30, 2, "ally"))
	var token: Dictionary = Status.begin_slot(actor)
	var stored := Fixtures.state(actor)
	stored["slot_token"] = token
	stored.phase = "action_selection"
	stored.queue = [actor.actor_id]
	stored.active_actor_id = actor.actor_id
	Fixtures.expect(State.validate(stored).is_empty(), "选择等待期的完整槽token可以存于BattleState且只含JSON值", failures)
	var restored: Dictionary = JSON.parse_string(JSON.stringify(stored))
	var restored_actor: Dictionary = restored.actors.actor
	var original_events: Array = Status.end_slot(actor, token)
	var restored_events: Array = Status.end_slot(restored_actor, restored.slot_token)
	# JSON.parse 把整数字段读成 float；存档层负责恢复 schema 类型，这里比较相同 JSON 数值／事件。
	Fixtures.expect(JSON.parse_string(JSON.stringify(actor)) == JSON.parse_string(JSON.stringify(restored_actor)) and JSON.parse_string(JSON.stringify(original_events)) == JSON.parse_string(JSON.stringify(restored_events)), "JSON恢复保留槽开始generation，能够确定性完成同一槽", failures)
	var before := actor.duplicate(true)
	Fixtures.expect(Status.end_slot(actor, token).is_empty() and actor == before, "重复结束同一个token不重复扣状态／盾", failures)
	var foreign := Fixtures.actor("guard", "foreign")
	before = foreign.duplicate(true)
	Fixtures.expect(Status.end_slot(foreign, token).is_empty() and foreign == before, "错误拥有者token不能扣其他角色时长", failures)
	actor.statuses = [Fixtures.status("awake", 1.0, 0, "actor")]
	Fixtures.expect(Status.immunity(actor, {"type": "apply_status", "status_id": "stun"}).is_empty(), "零剩余清醒实例不产生硬控免疫", failures)
	actor.statuses = []
	actor.hp = 0
	before = actor.duplicate(true)
	Fixtures.expect(not Status.apply(actor, Fixtures.status("stun", 1.0, 1, "enemy")).get("applied", true) and actor == before, "致死命中之后不给倒地目标附加状态", failures)
	Fixtures.expect(not Status.apply_shield(actor, Fixtures.shield(30, 2, "ally")).get("applied", true) and actor == before, "倒地目标不能获盾", failures)
	var burned := Fixtures.actor("guard", "burned")
	burned.hp = 5
	Status.apply(burned, Fixtures.status("burn", 20.0, 3, "mage"))
	Status.apply(burned, Fixtures.status("stun", 1.0, 1, "enemy"))
	token = Status.begin_slot(burned)
	Fixtures.expect(burned.hp == 0 and burned.slot_count == 1 and token.get("defeated", false) and not token.get("stunned", true), "灼烧先致死时不进入眩晕检查／命令选择", failures)
	Status.end_slot(burned, token)
	Fixtures.expect(burned.statuses.is_empty(), "灼烧致死不会补清醒或留负面状态", failures)
	before = burned.duplicate(true)
	var dead_events: Array = Status.begin_round({"burned": burned})
	Status.end_round({"burned": burned})
	Fixtures.expect(dead_events.is_empty() and burned == before, "轮序快照不包含倒地角色且不推进其时钟", failures)
	var source := Fixtures.actor("swordsman", "source")
	var target := Fixtures.actor("guard", "target")
	var source_before := source.duplicate(true)
	var target_before := target.duplicate(true)
	Damage.direct(source, target, {"damage_type": "physical", "element": "neutral", "coefficient": 1.0}, {}, true)
	Fixtures.expect(source == source_before and target == target_before, "伤害计算只读输入，不影响预览或RNG", failures)
	Damage.absorb(target, -1)
	Fixtures.expect(target == target_before, "负伤害输入不治疗或损盾", failures)
	var invalid := Fixtures.status("burn", 13.0, 3, "source")
	invalid.clock = "round_snapshot"
	before = target.duplicate(true)
	Fixtures.expect(not Status.apply(target, invalid).get("applied", true) and target == before, "非法时钟元数据拒绝且不改generation", failures)
	invalid = Fixtures.status("burn", 13.0, 3, "source")
	invalid.magnitude = NAN
	Fixtures.expect(not Status.apply(target, invalid).get("applied", true) and target == before, "非有限状态强度拒绝且不改generation", failures)
