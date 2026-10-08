# 强引同时作用于普通与条件系数；真实预览、命中及旧模式边界回归。
extends SceneTree
const Catalog=preload("res://scripts/rpg/catalog.gd")
const Factory=preload("res://scripts/rpg/actor_factory.gd")
const Loadouts=preload("res://scripts/rpg/loadout_rules.gd")
const Forms=preload("res://scripts/rpg/dual_form.gd")
const Battle=preload("res://scripts/rpg/battle_engine.gd")
const Damage=preload("res://scripts/rpg/damage_rules.gd")
const F=preload("res://tools/rpg/fixtures.gd")
const Replay=preload("res://scripts/rpg/replay.gd")
const Threats=preload("res://scripts/rpg/strategy_encounters.gd")
var assertions:=0
var failures:Array[String]=[]
var catalog:RefCounted
func check(value:bool,message:String)->void:
	assertions+=1
	if not value:failures.append(message);printerr("FAIL:",message)
func _initialize()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	catalog=Catalog.new();check(catalog.load_all().is_empty(),"真实目录加载")
	for row in [["swordsman","rinne","heavy_slash","armor_break"],["mage","homura","firebolt","burn"],["controller","controller","magic_break","weaken"]]:_case(row)
	var legacy:=F.actor("mage","p_mage");legacy["identity_id"]="homura";Forms.initialize(legacy,catalog);legacy.unlocked_forms=Forms.UNLOCKED_FORMS.duplicate();Forms.apply(legacy,"mage",catalog)
	check(is_equal_approx(catalog.skill_for(legacy,"firebolt").effects[0].conditional_coefficient,1.7),"旧等级模式仍保持原有条件系数")
	print("LOADOUT_CONDITIONAL_MODIFIERS:",assertions," assertions, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
func _actor(row:Array,strong:bool)->Dictionary:
	var build:=Loadouts.default_build(row[0])
	if strong:build.passive=["force_channel"]
	var actor:=Factory.new(catalog).create_loadout(row[0],"p_"+row[0],{"identity_id":row[1],"form_id":"mage" if row[0]=="mage" else row[1]}, {},build)
	if row[0]=="mage":Forms.initialize(actor,catalog);actor.unlocked_forms=Forms.UNLOCKED_FORMS.duplicate();Forms.apply(actor,"mage",catalog)
	return actor
func _case(row:Array)->void:
	var base_actor:=_actor(row,false);var source:=_actor(row,true)
	var base:Dictionary=catalog.skill_for(base_actor,row[2]);var modified:Dictionary=catalog.skill_for(source,row[2])
	var original:Dictionary=source.duplicate(true)
	check(is_equal_approx(modified.effects[0].coefficient,base.effects[0].coefficient+0.15),row[1]+"普通系数增加")
	check(is_equal_approx(modified.effects[0].conditional_coefficient,base.effects[0].conditional_coefficient+0.15),row[1]+"触发条件后仍获得同一强引加成")
	check(modified.mp_cost==base.mp_cost+1 and source==original,row[1]+"代价与只读派生正确")
	for condition in [false,true]:
		var target:=F.enemy("shield_soldier","enemy")
		if condition:target.statuses=[F.status(row[3],0.2 if row[3]!="burn" else 12.0,2,source.actor_id)]
		var engine:=Battle.new(catalog)
		var started:Dictionary=engine.start({"actors":{source.actor_id:source,"enemy":target},"inventory":{"mana_potion":1}},7)
		check(started.started,"合法装配实际进战："+row[1]+" "+str(started.get("reasons",[])))
		if not started.started:continue
		var initial:Dictionary=engine.snapshot()
		engine.advance();var state:Dictionary=engine.snapshot()
		check(state.active_actor_id==source.actor_id,"测试通过真实速度取得首轮，不篡改装配属性")
		var command:Dictionary={"command_id":"conditional_"+str(condition),"expected_revision":state.revision,"actor_id":source.actor_id,"kind":"skill","ability_id":row[2],"target_ids":["enemy"]}
		var preview:Dictionary=engine.preview(command)
		check(preview.legal,"普通/状态条件预览合法")
		if not preview.legal:continue
		var expected_effect:Dictionary=base.effects[0].duplicate(true)
		expected_effect.coefficient=(base.effects[0].conditional_coefficient if condition else base.effects[0].coefficient)+0.15
		var expected:Dictionary=Damage.direct(state.actors[source.actor_id],state.actors.enemy,expected_effect,{},false)
		check(preview.damage_ranges[0].normal==expected.damage,"真实预览兑现系数与当前属性："+row[1]+" condition="+str(condition))
		check(engine.snapshot()==state,"预览不消费资源或改变状态")
		var result:Dictionary=engine.submit(command)
		check(result.accepted,"真实指令接受")
		var hits:Array=result.events.filter(func(event):return event.type=="damage")
		var preview_hits:Array=preview.effects.filter(func(event):return event.type=="damage")
		check(not hits.is_empty() and not preview_hits.is_empty() and hits[0].payload.damage in [preview_hits[0].payload.normal,preview_hits[0].payload.critical_damage],"实际命中与预览伤害区间一致")
		var after:Dictionary=engine.snapshot();var commands:Array[Dictionary]=[];var events:Array[Dictionary]=[]
		for accepted in after.command_log.slice(initial.command_log.size()):commands.append(accepted)
		for event in after.event_log:
			if event.sequence>initial.event_sequence:events.append(event)
		var recorded:=Replay.record(initial,commands,events,catalog)
		check(Replay.verify(recorded,catalog).matches,"修正后的真实条件技能逐事件重放一致")
		# 旧版只哈希数据；算法已变，即使同一数据也不能标作同一战斗规则。
		recorded.mechanics_fingerprint=JSON.stringify({"catalog":catalog._definitions,"loadouts":Loadouts._data(),"threats":Threats._data()},"",true,true).sha256_text()
		var old:Dictionary=Replay.verify(recorded,catalog)
		check(not old.matches and int(old.first_difference.get("event_index",0))==-1,"旧派生算法指纹明确拒绝，不能冒充同版本回放")
