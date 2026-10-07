# 真实规则事件驱动的全部28变体离屏合成；不冒充完整战斗UI或实时帧率验收。
extends SceneTree
const F = preload("res://tools/rpg/fixtures.gd")
const H = preload("res://tools/rpg/test_engine.gd")
const Battle = preload("res://scripts/rpg/battle_engine.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Forms = preload("res://scripts/rpg/dual_form.gd")
const Status = preload("res://scripts/rpg/status_rules.gd")
const Policy = preload("res://scripts/rpg/ui/physical_skill_visual_event_policy.gd")
const Effects = preload("res://scripts/rpg/ui/imagegen_battle_effects.gd")
const JOBS := {
	"rinne":["heavy_slash","armor_break","sweep","battle_spirit"],
	"homura_sword":["heavy_slash","armor_break","sweep","battle_spirit"],
	"guard":["cover","shield_bash","iron_wall","taunt"],
	"mint":["mark","hunt","ambush","smoke_screen"],
	"homura_mage":["firebolt","flame_wave","ice_arrow","burn_brand"],
	"healer":["heal","group_heal","cleanse","holy_shield"],
	"controller":["weaken","slow","seal","magic_break"]}
var failures: Array[String] = []
func _initialize() -> void:
	root.position = Vector2i(-32000,-32000)
	root.hide()
	_run.call_deferred()
func _cast(form: String, skill: String) -> Dictionary:
	var catalog := Catalog.new();catalog.load_all()
	var class_id: String = {"rinne":"swordsman","homura_sword":"mage","guard":"guard","mint":"ranger","homura_mage":"mage","healer":"healer","controller":"controller"}[form]
	var source := F.actor(class_id,"p_mage" if form.begins_with("homura") else "source")
	source["identity_id"] = "homura" if form.begins_with("homura") else form
	if form.begins_with("homura"):
		Forms.initialize(source,catalog)
		if form == "homura_mage":
			source.unlocked_forms = ["sword","mage"]
			Forms.apply(source,"mage",catalog)
	var enemy := F.enemy("hound","enemy");enemy.hp=3000;enemy.stats.hp=3000
	var other := F.enemy("hound","other");other.hp=3000;other.stats.hp=3000
	var ally := F.actor("guard","ally");ally.hp=30
	Status.apply(ally,F.status("burn",.1,3,"enemy"))
	if skill in ["heavy_slash","sweep"]:Status.apply(enemy,F.status("armor_break",.25,3,"prior"))
	if skill == "hunt":Status.apply(enemy,F.status("mark",.2,3,source.actor_id))
	var engine = H._selection(Battle,source,[enemy,other,ally])
	var all_targets := ["sweep","battle_spirit","iron_wall","smoke_screen","flame_wave","group_heal","slow"]
	var targets: Array = [] if skill in all_targets else ["ally" if skill in ["cover","heal","cleanse","holy_shield"] else "enemy"]
	var before: Dictionary = engine.snapshot()
	var result: Dictionary = engine.submit(H._command(engine,"skill",skill,targets))
	if not result.accepted:return {"ok":false,"reason":str(result.reasons)}
	var context := Policy.context_from_result(before,catalog.skill_for(before.actors[source.actor_id],skill),result)
	context["form"]=form;context["impact_delay"]=.4;context["action_duration"]=1.2;context["launch_seconds"]=.18
	return {"ok":true,"events":result.events,"context":context,"state":engine.snapshot()}
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1":quit(2);return
	var output := OS.get_environment("ACT_ONE_OUTPUT")
	if output.is_empty():quit(2);return
	var viewport := SubViewport.new();viewport.size=Vector2i(1200,720);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new();background.size=Vector2(1200,720);background.color=Color("18222d");viewport.add_child(background)
	var title := Label.new();title.position=Vector2(24,20);title.add_theme_font_size_override("font_size",24);viewport.add_child(title)
	var fx := Effects.new();viewport.add_child(fx);fx.preview_pending_art=true;fx.set_process(false)
	var positions := {"source":Vector2(900,330),"p_mage":Vector2(900,330),"enemy":Vector2(280,330),"other":Vector2(470,330),"ally":Vector2(930,550)}
	var grounds := {"source":Vector2(900,430),"p_mage":Vector2(900,430),"enemy":Vector2(280,430),"other":Vector2(470,430),"ally":Vector2(930,650)}
	for id in ["source","enemy","other","ally"]:
		var marker := Label.new();marker.position=positions[id]+Vector2(-25,60);marker.text=id;viewport.add_child(marker)
	var report := {"purpose":"真实规则事件到28变体离屏PNG；非完整战斗UI或实时FPS","jobs":[],"failures":failures}
	for form in JOBS:
		for skill in JOBS[form]:
			var job := "%s-%s" % [form,skill]
			var cast := _cast(form,skill)
			if not cast.ok:failures.append(job+": "+cast.reason);continue
			fx.clear();fx.update_positions(positions,positions);fx.update_ground_positions(grounds)
			var targets := {}
			for id in cast.context.effect_target_ids:targets[id]=positions[id]
			if not fx.present_action(cast.context,form,positions[cast.context.source_id],targets,job):failures.append(job+": renderer "+str(fx.missing_art()));continue
			var accepted := H._event(cast.events,"command_accepted")
			fx.present_event(accepted,form,positions[cast.context.source_id],positions[cast.context.source_id],job,cast.context)
			var elapsed := 0.0
			var fed := false
			var snapshots := []
			for moment in [.05,.25,.45,.75,1.05,1.40]:
				if moment >= .4 and not fed:
					fx._process(.4-elapsed);elapsed=.4;fed=true
					for event in cast.events:
						if event.type != "command_accepted":fx.present_event(event,form,positions[cast.context.source_id],positions.get(str(event.target_id),Vector2.ZERO),job,cast.context)
				fx._process(moment-elapsed);elapsed=moment
				title.text=job+" / "+str(moment)+"s"
				fx.queue_redraw();await process_frame
				RenderingServer.force_draw(false)
				var image := viewport.get_texture().get_image()
				if image == null or image.is_empty():failures.append(job+": empty render");break
				var name := "%s-%03d.png" % [job,roundi(moment*100)]
				image.save_png(output.path_join(name))
				snapshots.append({"time":moment,"file":name,"drawn":fx.draw_snapshot(),"layers":fx.layer_snapshot()})
			report.jobs.append({"variant":job,"snapshots":snapshots,"missing":fx.missing_art(),"peak_bound_bytes":Effects.MAX_TEXTURE_BYTES})
			print("SKILL_RENDER_CAPTURE:",job,":",snapshots.size())
	report["failures"]=failures
	FileAccess.open(output.path_join("capture-report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SKILL_RENDER_CAPTURE_TOTAL:",report.jobs.size()," FAILURES:",failures.size())
	quit(0 if failures.is_empty() and report.jobs.size()==28 else 1)
