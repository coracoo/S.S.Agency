# 技能上下文、命中去重和生命周期：只验证呈现，不触碰真实战斗/存档。
extends SceneTree
const Effects = preload("res://scripts/rpg/ui/battle_effects.gd")
var failed := 0
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failed += 1
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(1); return
	var Capture = load("res://tools/characters/capture_spell_effects.gd")
	check(Capture != null, "图形proof脚本可在实际4.7.2解析")
	var captured_skills: Dictionary = {}
	for job in Capture.JOBS: captured_skills[job[1]] = true
	check(captured_skills.size() == 12, "图形proof覆盖全部12法术而非仅12组场景")
	var fx: Variant = Effects.new()
	root.add_child(fx)
	fx.set_process(false)
	check(fx.has_method("present_action"), "新增施法入口消费真实command上下文")
	check(fx.has_method("ability_profile"), "技能独立配置可查询")
	if not fx.has_method("present_action") or not fx.has_method("ability_profile"):
		fx.free(); print("SPELL_EFFECTS_RESULT: ", failed); quit(1); return
	var skills: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rpg/skills.json"))
	var kinds: Dictionary = {}
	for skill in skills.definitions:
		var profile: Dictionary = fx.ability_profile(str(skill.id))
		check(not profile.is_empty(), str(skill.id) + "有明确呈现映射")
		if profile.is_empty(): continue
		check(profile.target_rule == skill.target_rule, str(skill.id) + "目标规则来自真实技能")
		if skill.id in ["firebolt", "flame_wave", "ice_arrow", "burn_brand", "heal", "group_heal", "cleanse", "holy_shield", "weaken", "slow", "seal", "magic_break"]: kinds[profile.atlas] = true
	check(kinds.size() == 12, "12法术具有12种独立帧形态")
	var targets := {"b": Vector2(300, 180), "c": Vector2(400, 260)}
	var context := {"ability_id": "ice_arrow", "kind": "skill", "command_id": "one", "impact_delay": 0.4}
	var original := context.duplicate(true)
	check(fx.present_action(context, "homura_mage", Vector2(90, 200), targets, "battle"), "冰矢开始施法与飞行")
	check(not fx.present_action(context, "homura_mage", Vector2.ZERO, targets, "battle"), "同一command不可重复施法")
	var event := {"sequence": 7, "type": "damage", "actor_id": "a", "target_id": "b", "payload": {"damage": 18}}
	var event_copy := event.duplicate(true)
	var flight_texture_id: int = fx._textures.ice_arrow.get_instance_id()
	check(fx.present_event(event, "homura_mage", Vector2(90, 200), targets.b, "battle", context), "冰矢在真实damage命中边界生成冲击")
	check(fx._textures.ice_arrow.get_instance_id() == flight_texture_id, "多目标首次命中复用在途已加载纹理")
	check(not fx.present_event(event, "homura_mage", Vector2.ZERO, targets.b, "battle", context), "重复命中事件不重复应用")
	var slow := {"sequence": 8, "type": "status_applied", "actor_id": "a", "target_id": "b", "payload": {"status": {"id": "slow"}}}
	check(not fx.present_event(slow, "homura_mage", Vector2.ZERO, targets.b, "battle", context), "冰矢附带迟滞不再重播整段冲击")
	var other := event.duplicate(true); other.sequence = 9; other.target_id = "c"
	check(fx.present_event(other, "homura_mage", Vector2.ZERO, targets.c, "battle", context), "多目标命中各自播放且独立去重")
	fx.clear()
	fx.present_action(context,"homura_mage",Vector2.ZERO,{"b":targets.b},"single_flight")
	flight_texture_id = fx._textures.ice_arrow.get_instance_id()
	fx.present_event(event,"homura_mage",Vector2.ZERO,targets.b,"single_flight",context)
	check(fx._textures.ice_arrow.get_instance_id() == flight_texture_id,"单目标飞行转命中不重解码/上传同图集")
	check(context == original and event == event_copy, "输入事件与命令未改写")
	fx._process(3.0)
	check(fx.active_count() == 0, "施法飞行冲击与恢复全部有界清理")
	fx.clear()
	context.ability_id = "heal"; context.command_id = "heal_one"
	var healing := {"sequence": 10, "type": "healed", "actor_id": "a", "target_id": "b", "payload": {"actual": 20}}
	check(fx.present_event(healing, "healer", Vector2.ZERO, targets.b, "battle", context), "愈合有花瓣铃波命中")
	var shield := {"sequence": 11, "type": "shield_applied", "actor_id": "a", "target_id": "b", "payload": {"shield": {"amount": 12}}}
	check(fx.present_event(shield, "healer", Vector2.ZERO, targets.b, "battle", context), "护生专精护盾只作为独立附加层")
	check(not fx.present_event(shield, "healer", Vector2.ZERO, targets.b, "battle", context), "护生附加层亦按事件去重")
	fx.clear()
	context.ability_id = "cleanse"; context.command_id = "cleanse_one"
	for index in range(3):
		var removed := {"sequence": 20 + index, "type": "status_removed", "actor_id": "a", "target_id": "b", "payload": {"reason": "cleanse", "status": {"id": str(index)}}}
		check(fx.present_event(removed, "healer", Vector2.ZERO, targets.b, "battle", context) == (index == 0), "净化移除多状态只播一次 %d" % index)
	for index in range(80):
		context.command_id = "burst_%d" % index; context.ability_id = "firebolt"
		event.sequence = 100 + index
		fx.present_action(context, "homura_mage", Vector2.ZERO, targets, "battle")
		fx.present_event(event, "homura_mage", Vector2.ZERO, targets.b, "battle", context)
	check(fx.active_count() <= Effects.MAX_BURSTS, "重叠动作/多目标受统一burst上限约束")
	check(fx.texture_memory_bytes() <= 48 * 1024 * 1024, "活动图集预算不超过48MiB")
	fx.clear()
	check(fx.active_count() == 0 and fx.texture_memory_bytes() == 0, "换场取消释放粒子/图集/上下文")
	check(fx.present_event(event, "homura_mage", Vector2.ZERO, targets.b, "new_battle", context), "新战斗可重用sequence/command")
	fx._process(3.0)
	check(fx.texture_memory_bytes() == 0, "无活动效果后释放懒加载纹理")
	fx.clear()
	fx.present_action({"command_id":"slow_cast","ability_id":"slow","impact_delay":0.5},"controller",Vector2.ZERO,targets,"battle")
	fx._process(0.49)
	check(fx.active_count() == 1,"无飞行法术的起手持续到真实命中短窗，不提前空等0.30秒")
	fx.clear()
	check(fx.has_method("cancel_action"), "可取消指定行动并拒绝迟到事件")
	if fx.has_method("cancel_action"):
		context.command_id = "cancelled_one"
		fx.present_action(context, "homura_mage", Vector2.ZERO, targets, "battle")
		fx.cancel_action(context, "battle")
		event.sequence = 999
		check(not fx.present_event(event, "homura_mage", Vector2.ZERO, targets.b, "battle", context), "取消后迟到命中不重建纹理")
		check(fx.active_count() == 0 and fx.texture_memory_bytes() == 0, "指定行动取消立即回收")
	_test_real_events(fx)
	fx.clear()
	for row in load("res://scripts/rpg/ui/skill_effect_profiles.gd").ROWS:
		var overlapping := {"sequence":2000 + fx.active_count(), "type":row[3][0], "actor_id":"a", "target_id":row[0], "payload":{"reason":"cleanse"}}
		fx.present_event(overlapping,"mage",Vector2.ZERO,Vector2.ONE,"budget",{"command_id":row[0],"ability_id":row[0]})
		check(fx.texture_memory_bytes() <= 48*1024*1024, row[0]+"不同技能同时重叠仍遵守纹理预算")
	check(fx.texture_memory_bytes() == 10*Effects.ATLAS_BYTES,"压力场景实际达到十图集上限并逐出旧图集")
	fx.clear()
	var tick := {"sequence":3100,"type":"periodic_damage","actor_id":"a","target_id":"b","payload":{"damage":5}}
	check(fx.present_event(tick,"homura_mage",Vector2.ZERO,Vector2.ONE,"ticks",{"command_id":"turn_one","ability_id":"ice_arrow"}),"回合燃烧不误用残留冰矢上下文")
	tick.sequence += 1
	check(fx.present_event(tick,"homura_mage",Vector2.ZERO,Vector2.ONE,"ticks",{"command_id":"turn_one","ability_id":"ice_arrow"}),"两个真实燃烧tick不被同command目标去重吞掉")
	fx.free()
	print("SPELL_EFFECTS_RESULT: ", failed)
	quit(1 if failed else 0)

func _test_real_events(fx: Variant) -> void:
	var F = load("res://tools/rpg/fixtures.gd")
	var H = load("res://tools/rpg/test_engine.gd")
	var Engine = load("res://scripts/rpg/battle_engine.gd")
	var Status = load("res://scripts/rpg/status_rules.gd")
	var Catalog = load("res://scripts/rpg/catalog.gd")
	var catalog = Catalog.new(); catalog.load_all()
	for class_id in ["guard", "swordsman", "ranger", "mage", "healer", "controller"]:
		for ability in catalog.get_definition("classes", class_id).skill_ids:
			var source: Dictionary = F.actor(class_id, "source")
			var ally: Dictionary = F.actor("guard", "ally"); ally.hp = 40
			var enemy: Dictionary = F.enemy("hound", "enemy")
			enemy.stats.hp = 3000; enemy.hp = 3000
			var enemy_two: Dictionary = enemy.duplicate(true); enemy_two.actor_id = "enemy_two"
			if ability == "cleanse":
				Status.apply(ally, F.status("slow", 0.3, 2, "enemy"))
				Status.apply(ally, F.status("weaken", 0.2, 2, "enemy"))
			var engine = H._selection(Engine, source, [ally, enemy, enemy_two])
			var rule: String = catalog.get_definition("skills", ability).target_rule
			var selected: Array = [] if rule in ["all_allies", "all_enemies", "self"] else ["ally" if rule in ["single_ally", "other_ally"] else "enemy"]
			var command: Dictionary = H._command(engine, "skill", ability, selected, "real_" + ability)
			var result: Dictionary = engine.submit(command)
			check(result.accepted, ability + "真实模型接受技能命令")
			if not result.accepted: continue
			var saved: Dictionary = engine.snapshot()
			var original_events: Array = result.events.duplicate(true)
			fx.clear()
			var main_targets: Dictionary = {}
			for event in result.events:
				if fx.present_event(event, class_id, Vector2(80,180), Vector2(350,180), "real", command):
					main_targets[event.target_id] = true
			check(main_targets.size() == (2 if rule == "all_enemies" or rule == "all_allies" else 1), ability + "真实事件产生正确数量的独立目标效果")
			for event in result.events: fx.present_event(event, class_id, Vector2.ZERO, Vector2.ONE, "real", command)
			check(engine.snapshot() == saved and result.events == original_events, ability + "重复呈现不更改模型/事件/RNG/重放")
			check(fx.texture_memory_bytes() > 0, ability + "实际载入图集而非空配置")
			fx._process(3.0)
