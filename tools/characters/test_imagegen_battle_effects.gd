# 法术表现只消费真实事件；时钟、去重、盾耗尽和缺图清单不依赖规则预测。
extends SceneTree
var checks := 0
var failures := 0
func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",message)
func _initialize() -> void: _run.call_deferred()
func _event(kind: String,sequence: int,payload: Dictionary={},target: String="target") -> Dictionary:
	return {"type":kind,"sequence":sequence,"actor_id":"source","target_id":target,"payload":payload}
func _context(id: String="one",ability: String="firebolt") -> Dictionary:
	return {"command_id":id,"kind":"skill","ability_id":ability,"source_id":"source","impact_delay":.24,"action_duration":.6}
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	var Script = load("res://scripts/rpg/ui/imagegen_battle_effects.gd")
	check(Script!=null,"独立imagegen事件渲染器存在")
	if Script!=null:
		var fx = Script.new(); root.add_child(fx); fx.set_process(false)
		var context := _context()
		var targets := {"target":Vector2(420,320),"second":Vector2(620,340)}
		check(not fx.present_action(context,"homura_mage",Vector2(100,300),targets,"battle"),"默认生产关闭")
		fx.preview_pending_art=true
		check(fx.has_method("sample_burst"),"cast手点跟踪与发射冻结拥有可检查的同一渲染采样入口")
		check(fx.present_action(context,"homura_mage",Vector2(100,300),targets,"battle"),"明确预览开启实际12帧施法")
		check(not fx.present_action(context,"homura_mage",Vector2.ZERO,targets,"battle"),"重复命令不起第二套火弹")
		if fx.has_method("sample_burst"):
			fx.update_positions(targets,{"source":Vector2(140,200)})
			var cast:Dictionary=fx.sample_burst(fx._bursts[0])
			check(cast.position==Vector2(140,200),"起手跟踪最新真实手点")
			fx._process(.16)
			var flight:Dictionary=fx._bursts.filter(func(value):return value.phase=="travel")[0]
			var first:Dictionary=fx.sample_burst(flight)
			fx.update_positions(targets,{"source":Vector2(900,800)})
			var second:Dictionary=fx.sample_burst(flight)
			check(first.position==second.position and flight.source==Vector2(140,200),"飞弹发射后起点冻结，不被后续手势拖走")
			fx._process(.08)
		else: fx._process(.24)
		check(fx.hit_count()==0,"到预计impact只结束飞行，不伪造实际命中")
		var hit := _event("damage",1,{"damage":22})
		var original := hit.duplicate(true)
		check(fx.present_event(hit,"homura_mage",Vector2.ZERO,targets.target,"battle",context),"实际damage才创建命中层")
		check(hit==original,"不修改模型原始事件")
		check(not fx.present_event(hit,"homura_mage",Vector2.ZERO,targets.target,"battle",context),"相同damage去重")
		check(fx.present_event(_event("damage",2,{"damage":11},"second"),"homura_mage",Vector2.ZERO,targets.second,"battle",context),"真实多目标各命中一次")
		check(fx.hit_count()==2,"两目标主效果各一份")
		fx.present_event(_event("actor_defeated",98),"homura_mage",Vector2.ZERO,targets.target,"battle",context)
		check(fx.hit_count()==2,"同M的KO清状态但不抹掉已经发生的一次命中层")
		fx._process(.36)
		check(fx.active_count()==0 and fx.texture_memory_bytes()==0,"E清掉所有瞬态及页面强引用")
		context=_context("burn","burn_brand")
		fx.present_action(context,"homura_mage",Vector2.ZERO,targets,"battle")
		check(fx.present_event(_event("status_applied",3,{"status":{"id":"burn","stacks":2}}),"homura_mage",Vector2.ZERO,targets.target,"battle",context),"真实burn事件才挂低频余烬")
		fx._process(2.0)
		check(fx.status_count()==1,"动作结束保留规则仍有效的燃烧层")
		var casts: int=fx.action_count()
		fx.present_event(_event("periodic_damage",4,{"damage":4}),"homura_mage",Vector2.ZERO,targets.target,"battle",{})
		check(fx.action_count()==casts and fx.status_count()==1,"周期燃烧仅现有状态轻脉冲，不重新施法")
		fx.present_event(_event("status_removed",5,{"status":{"id":"burn"},"reason":"consumed"}),"homura_mage",Vector2.ZERO,targets.target,"battle",{})
		check(fx.status_count()==0 and fx.texture_memory_bytes()==0,"实际消耗燃烧后清状态和图页")
		fx.present_event(_event("shield_applied",6,{"shield":{"amount":10}}),"guard",Vector2.ZERO,targets.target,"battle",{})
		check(fx.state_count()==1 and fx.missing_art().has("shield"),"盾事件跟踪有效层，缺少已验图时明确缺口")
		fx.present_event(_event("saga_reflected",7,{"absorption":{"shield_after":{},"hp_loss":1}}),"guard",Vector2.ZERO,targets.target,"battle",{})
		check(fx.state_count()==0,"反射吸收后空盾也立刻去层")
		var statuses := ["weaken","armor_break","battle_spirit","magic_break","awake","slow"]
		for index in statuses.size():
			fx.present_event(_event("status_applied",32+index,{"status":{"id":statuses[index]}}),"controller",Vector2.ZERO,targets.target,"battle",{})
		check(fx.state_count()==6,"14技法用实际状态事件补层，不猜条件分支")
		fx.present_event(_event("actor_defeated",90),"controller",Vector2.ZERO,targets.target,"battle",{})
		check(fx.state_count()==0,"死亡清除所有该角色状态引用")
		context=_context("cancel")
		fx.present_action(context,"homura_mage",Vector2.ZERO,targets,"battle")
		fx.cancel_action(context,"battle")
		check(not fx.present_event(_event("damage",91),"homura_mage",Vector2.ZERO,targets.target,"battle",context),"取消后晚到命中不生成效果")
		fx.clear()
		check(fx.active_count()==0 and fx.texture_memory_bytes()==0,"退出清空所有效果页")
		var wave_targets:Dictionary={"a":Vector2(150,460),"b":Vector2(374,460),"c":Vector2(598,460)}
		var wave:=_context("group-wave","flame_wave")
		check(fx.present_action(wave,"homura_mage",Vector2(1100,420),wave_targets,"wave-battle"),"群体炎浪沿真实三目标发起")
		var travels:Array=fx._bursts.filter(func(burst):return burst.phase=="travel")
		check(travels.size()==1,"炎浪只有一个群体波前，不复制成三枚火团")
		fx._process(.18)
		if travels.size()==1:
			var sample:Dictionary=fx.sample_burst(travels[0])
			check(sample.stretch.x>1 and sample.stretch.y==1,"波前按目标范围横向展开，保持垂直可见高度")
		fx._process(.06)
		for i in 3:fx.present_event(_event("damage",200+i,{"damage":5},["a","b","c"][i]),"homura_mage",Vector2.ZERO,wave_targets[["a","b","c"][i]],"wave-battle",wave)
		check(fx.hit_count()==3,"群体波前不合并或重复实际三次目标命中")
		fx.clear()
		var quick:=_context("quick-cast","firebolt")
		quick.impact_delay=7.0/24.0;quick.action_duration=.875
		quick.launch_seconds=5.0/24.0;quick.cast_scale=.55
		check(fx.present_action(quick,"homura_mage",Vector2(1100,420),targets,"quick-battle"),"新动作独立释放点可启动")
		var quick_cast:Dictionary=fx._bursts.filter(func(burst):return burst.phase=="cast")[0]
		var quick_travel:Dictionary=fx._bursts.filter(func(burst):return burst.phase=="travel")[0]
		check(absf(quick_cast.end-5.0/24.0)<.0001 and absf(quick_travel.start-5.0/24.0)<.0001,"等待新动作推掌再发射，真实M不变")
		fx._process(.18)
		check(fx.sample_burst(quick_travel).is_empty(),"收掌时火弹尚未离身")
		var quick_sample:Dictionary=fx.sample_burst(quick_cast)
		check(not quick_sample.is_empty() and absf(quick_sample.scale-float(quick_sample.frame.scale)*.55)<.0001,"只缩小聚能球保留脸部，飞弹和命中图尺寸不变")
		fx.clear();fx.free()
	print("IMAGEGEN_BATTLE_EFFECTS: %d assertions, %d failures" % [checks,failures])
	quit(1 if failures else 0)
