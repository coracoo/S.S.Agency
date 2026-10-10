# 终章连续实战：同一真实检查点、一次石阶休息、有限购物；只由正式API改变持久状态。
extends SceneTree
const Campaign = preload("res://scripts/rpg/campaign.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Store = preload("res://scripts/rpg/save_store.gd")
const Router = preload("res://scripts/rpg/encounter_router.gd")
const Saga = preload("res://scripts/campaign/saga_catalog.gd")
const Strategy = preload("res://tools/campaign/final_gauntlet_strategy.gd")
const Replay = preload("res://scripts/rpg/replay.gd")
const EnemyPolicy = preload("res://scripts/rpg/enemy_policy.gd")
const Boss = preload("res://scripts/rpg/saga_boss_rules.gd")
const SAVE := "user://campaign_v1/slot_01.json"
var catalog: RefCounted
var output := ""
var source_path := ""
var baseline: PackedByteArray
var failures: Array[String] = []
var assertions := 0
var summaries: Array = []
var preparation_log: Array = []
var rest_count := 0

func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	output = OS.get_environment("GAUNTLET_OUTPUT")
	source_path = OS.get_environment("GAUNTLET_CHECKPOINT")
	if output.is_empty() or source_path.is_empty(): printerr("FAIL: 缺少隔离运行器的证据参数"); quit(2); return
	catalog = Catalog.new()
	_expect(catalog.load_all().is_empty(), "正式规则目录载入")
	_run.call_deferred()

func _run() -> void:
	_expect(FileAccess.file_exists(source_path), "真实七章检查点存在")
	if not failures.is_empty(): _finish(); return
	_copy_to_isolated(FileAccess.get_file_as_bytes(source_path))
	var migrated := Campaign.new(catalog, Store.new(catalog), SAVE)
	if not _ok(migrated.load_run(), "原检查点经正式load_run严格校验/迁移"): _finish(); return
	var original: Dictionary = migrated.safe_snapshot()
	_expect(original.saga.chapter == 7 and original.saga.scene == "C7-01" and original.pending_battle.is_empty(), "从终战之前开始")
	baseline = FileAccess.get_file_as_bytes(SAVE)
	_write("migrated-checkpoint.json", original)
	_write("source.json", {"path":source_path,"sha256":FileAccess.get_sha256(source_path),"mechanics_fingerprint":catalog.mechanics_fingerprint(),"strategy_sha256":FileAccess.get_sha256("res://tools/campaign/final_gauntlet_strategy.gd"),"scope":"仅真实终章连续三阶段，不是自然七章通关"})
	var cases: Array = [
		{"id":"protection_zero","front":"p_guard","purchases":[]},
		{"id":"protection_293","front":"p_guard","purchases":[["mana_potion",8],["healing_potion",4],["revival_potion",1]]},
		{"id":"cross_burst_293","front":"p_swordsman","purchases":[["mana_potion",8],["healing_potion",4],["revival_potion",1]]},
		{"id":"control_293","front":"p_controller","purchases":[["mana_potion",8],["healing_potion",4],["revival_potion",1]]}
	]
	var selected := OS.get_environment("GAUNTLET_CASES")
	for config in cases:
		if not selected.is_empty() and not str(config.id) in selected.split(","): continue
		_run_case(config)
	_finish()

func _run_case(config: Dictionary) -> void:
	_copy_to_isolated(baseline)
	var model := Campaign.new(catalog, Store.new(catalog), SAVE)
	if not _ok(model.load_run(), config.id+"读取统一迁移基线"): return
	var original: Dictionary = model.safe_snapshot()
	preparation_log = []; rest_count = 0
	if not _prepare(model, config): return
	var prepared: Dictionary = model.safe_snapshot()
	_expect(prepared.gear == original.gear and prepared.cards == original.cards, config.id+"只使用检查点实有装备与收藏")
	var budget: int = original.saga.coins-prepared.saga.coins
	_expect(budget <= 300 and budget >= 0 and rest_count == 1, config.id+"购物预算与一次休息")
	_write(config.id+"/preparation.json", {"operations":preparation_log,"spent":budget,"rest_count":rest_count,"snapshot":prepared})
	var case_summary := {"id":config.id,"party":prepared.party,"spent":budget,"purchases":config.purchases,"rest_count":rest_count,"stages":[],"interstage_items":[],"complete":false,"stopped_at":""}
	for step in 16:
		var saved: Dictionary = model.safe_snapshot()
		var scene_id: String = saved.saga.active_scene if not saved.saga.active_scene.is_empty() else saved.saga.scene
		if scene_id.is_empty() or scene_id == "C7-14": break
		if not _at_scene(model, scene_id): break
		if not _ok(model.begin_saga_scene(model.safe_snapshot().world,scene_id), config.id+"开始原场次"+scene_id): break
		var choices: Array = Saga.eligible_choices(Saga.scene(scene_id),model.safe_snapshot().saga)
		if not choices.is_empty():
			if not _ok(model.choose_saga_option(model.safe_snapshot().world,scene_id,"a"),config.id+"确认批准选择"+scene_id+"/a"): break
		saved = model.safe_snapshot()
		if not saved.world.story_encounter.is_empty() and not saved.saga.battles.has(scene_id):
			_expect(scene_id in ["C7-05","C7-06","C7-10"],"仅跑同一分段撤阵三阶段")
			var result := _battle(model,config.id,scene_id)
			case_summary.stages.append(result)
			if result.get("outcome") != "victory": case_summary.stopped_at=scene_id; break
		if not _ok(model.complete_saga_scene(model.safe_snapshot().world,scene_id),config.id+"完成原场次"+scene_id): break
		if scene_id in ["C7-05","C7-06"]:
			case_summary.interstage_items.append_array(_finite_recovery(model,scene_id))
		if scene_id == "C7-10": case_summary.complete=true; break
	case_summary["final_snapshot"]=model.safe_snapshot()
	case_summary["rest_count"]=rest_count
	_expect(rest_count==1,config.id+"终战后没有免费休息")
	summaries.append(case_summary)
	_write(config.id+"/summary.json",case_summary)
	print("FINAL_GAUNTLET_CASE:",JSON.stringify({"id":config.id,"spent":budget,"complete":case_summary.complete,"stopped_at":case_summary.stopped_at,"stages":case_summary.stages}))

func _prepare(model: RefCounted, config: Dictionary) -> bool:
	# 先合法卸卡、卸武器，再转移唯一持有物；不用改候选角色字典绕过库存限制。
	for id in ["p_guard","p_controller","p_swordsman"]:
		if not _operation(model.set_loadout(id,_build([])),"卸卡",{"actor":id}): return false
		if not _operation(model.equip(id,"weapon",""),"卸武器",{"actor":id}): return false
	if not _operation(model.set_loadout("p_mage",_mage_build([])),"清空焰华两形态",{}): return false
	var front_weapon: String = "training_focus_blade" if config.front=="p_controller" else "training_guard_blade"
	for row in [["p_mage","weapon","spirit_bell"],["p_mage","armor","monk_kesa"],["p_mage","accessory","bead_bracelet"],["p_healer","weapon","training_sigil"],["p_healer","armor","ranger_garb"],[config.front,"weapon",front_weapon]]:
		if not _operation(model.equip(row[0],row[1],row[2]),"装备",{"actor":row[0],"slot":row[1],"item":row[2]}): return false
	if not _operation(model.set_loadout("p_mage",_mage_build(["burn_brand","firebolt","seal","weaken"])),"焰华构筑",{}): return false
	if not _operation(model.set_form("p_mage","mage"),"焰华术形态",{}): return false
	if not _operation(model.set_loadout("p_healer",_build(["heal","group_heal","cleanse","magic_break"])),"治疗兼破魔",{}): return false
	var active: Array = ["shield_bash","heavy_slash","armor_break","battle_spirit"] if config.front=="p_swordsman" else ["shield_bash","cover","iron_wall","armor_break"]
	if config.front=="p_controller": active=["weaken","magic_break","seal","group_heal"]
	if not _operation(model.set_loadout(config.front,_build(active)),"前排跨职构筑",{"actor":config.front,"active":active}): return false
	var party: Array[String] = [config.front,"p_mage","p_healer"]
	if not _operation(model.set_party(party),"编队",{"party":party}): return false
	var world: Dictionary = model.safe_snapshot().world
	var stairs: Array = Saga.definition(11).anchors.stairs
	world.position=stairs.duplicate(); world.player_x=stairs[0]
	if not _operation(model.save_exploration(world),"抵达终战前石阶",{}): return false
	for purchase in config.purchases:
		if not _operation(model.buy_saga_item(model.safe_snapshot().world,purchase[0],purchase[1]),"实际购买",{"item":purchase[0],"count":purchase[1]}): return false
	if not _operation(model.rest(),"石阶唯一一次休息",{}): return false
	rest_count+=1
	return true

func _build(active: Array) -> Dictionary:
	return {"version":1,"active":{"default":active.duplicate()},"passive":["steady_breath","light_step"]}
func _mage_build(active: Array) -> Dictionary:
	return {"version":1,"active":{"sword":[],"mage":active.duplicate()},"passive":["steady_breath","light_step"]}

func _at_scene(model: RefCounted, id: String) -> bool:
	var world: Dictionary = model.safe_snapshot().world
	var entry: Dictionary = Saga.scene(id)
	var point: Array = Saga.definition(world.night).anchors[entry.location]
	world.position=point.duplicate(); world.player_x=point[0]
	return _ok(model.save_exploration(world),"保存批准场次实地检查点"+id)

func _finite_recovery(model: RefCounted, stage_id: String) -> Array:
	var operations: Array = []
	# 只消耗已经带入的有限药物，不补库存、不采购、不使用rest。
	for id in model.safe_snapshot().party:
		for item in ["revival_potion","healing_potion","mana_potion"]:
			for attempt in 12:
				var saved: Dictionary = model.safe_snapshot()
				var actor: Dictionary = saved.roster[id]
				if int(saved.inventory.get(item,0))<=0: break
				var useful: bool = actor.hp==0 if item=="revival_potion" else (actor.hp>0 and actor.stats.hp-actor.hp>=80 if item=="healing_potion" else actor.hp>0 and actor.mp<35 and actor.stats.mp-actor.mp>=20)
				if not useful: break
				var before: Dictionary = {"hp":actor.hp,"mp":actor.mp}
				if not _ok(model.use_item_outside(item,id),"连续阶段之间实际用药"): return operations
				actor=model.safe_snapshot().roster[id]
				operations.append({"after_stage":stage_id,"actor":id,"item":item,"before":before,"after":{"hp":actor.hp,"mp":actor.mp}})
	return operations

func _battle(model: RefCounted, case_id: String, scene_id: String) -> Dictionary:
	var router := Router.new(model,catalog)
	var world: Dictionary = model.safe_snapshot().world
	if not _ok(router.begin(world.scene_path,"res://scenes/rpg/battle.tscn",world,scene_id),"正式路由开战"+scene_id): return {}
	var before: Dictionary = model.safe_snapshot()
	var engine: RefCounted = router.create_engine()
	_expect(engine!=null,"真实战斗引擎创建")
	if engine==null: return {}
	var decisions: Array = []
	while engine.snapshot().outcome.is_empty() and decisions.size()<220:
		engine.advance()
		var state: Dictionary = engine.snapshot()
		if not state.outcome.is_empty(): break
		if state.phase!="action_selection": _expect(false,"引擎没有进入合法选择阶段"); break
		var ranked: Array = Strategy.ranked(state,engine,catalog,scene_id)
		# 第三阶段遵照公开目标依赖，不拿被保护内层的持续状态绕过出口顺序。
		ranked=ranked.filter(func(row):
			for id in row.command.target_ids:
				var target: Dictionary = state.actors[id]
				if target.side=="enemy" and Boss.blocked(state,target): return false
			return true)
		if ranked.is_empty(): _expect(false,"缺少真实合法指令"); break
		var command: Dictionary = ranked[0].command
		decisions.append({"round":state.round,"command":command,"actors":state.actors.duplicate(true),"top_options":ranked.slice(0,5)})
		if not _ok(engine.submit(command),"真实指令","accepted"): break
	var final: Dictionary = engine.snapshot()
	var result: Dictionary = router.result_from_engine()
	var replay_result: Dictionary = {}
	if not result.is_empty():
		replay_result=Replay.verify(result.replay,catalog,EnemyPolicy.new())
		_expect(replay_result.matches,"连续阶段逐事件重放"+scene_id+":"+str(replay_result.get("first_difference",{})))
		if not _ok(router.finish(result),"真实胜负提交"+scene_id): return {}
	else: _expect(false,"命令上限前必须得到真实胜负")
	var defeated: Array = []; var resources: Dictionary = {}; var enemy_resources: Dictionary = {}
	for id in before.party:
		var actor: Dictionary = final.actors[id]
		resources[id]={"hp":actor.hp,"mp":actor.mp,"max_hp":actor.stats.hp,"max_mp":actor.stats.mp}
		if actor.hp<=0: defeated.append(id)
	for id in final.actors:
		if final.actors[id].side=="enemy": enemy_resources[id]={"hp":final.actors[id].hp,"mp":final.actors[id].mp,"max_hp":final.actors[id].stats.hp}
	var counts: Dictionary = {}; var selected_counts: Dictionary = {}
	for event in final.event_log: counts[event.type]=int(counts.get(event.type,0))+1
	for decision in decisions:
		var key: String = decision.command.ability_id if not decision.command.ability_id.is_empty() else decision.command.kind
		selected_counts[key]=int(selected_counts.get(key,0))+1
	var summary := {"scene":scene_id,"outcome":final.outcome,"rounds":final.round,"commands":decisions.size(),"seed":before.pending_battle.seed,"battle_id":before.pending_battle.battle_id,"replay_matches":replay_result.get("matches",false),"party_resources_before":{},"party_resources_after":resources,"enemy_resources_after":enemy_resources,"inventory_before":before.inventory,"inventory_after":final.inventory,"defeated":defeated,"commands_by_ability":selected_counts,"events_by_type":counts}
	for id in before.party: summary.party_resources_before[id]={"hp":before.roster[id].hp,"mp":before.roster[id].mp}
	_write(case_id+"/"+scene_id+"-decisions.json",decisions)
	_write(case_id+"/"+scene_id+"-result.json",result)
	_write(case_id+"/"+scene_id+"-final.json",final)
	_write(case_id+"/"+scene_id+"-replay-verification.json",replay_result)
	_write(case_id+"/"+scene_id+"-persistent-after.json",model.safe_snapshot())
	if final.outcome=="victory":
		var reloaded := Campaign.new(catalog,Store.new(catalog),SAVE)
		_expect(reloaded.load_run().ok and reloaded.safe_snapshot()==model.safe_snapshot(),"真实胜利可重读"+scene_id)
	return summary

func _operation(result: Dictionary, label: String, detail: Dictionary) -> bool:
	preparation_log.append({"action":label,"detail":detail,"result":result.duplicate(true)})
	return _ok(result,label)
func _ok(result: Dictionary, label: String, key: String="ok") -> bool:
	_expect(result.get(key,false),label+":"+str(result.get("error",result.get("reasons",""))))
	return result.get(key,false)
func _expect(condition: bool, label: String) -> void:
	assertions+=1
	if not condition: failures.append(label); printerr("FAIL: ",label)
func _copy_to_isolated(bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute("user://campaign_v1")
	var file := FileAccess.open(SAVE,FileAccess.WRITE)
	file.store_buffer(bytes); file.close()
func _write(name: String, value: Variant) -> void:
	var path := output.path_join(name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(value,"  ",true,true)); file.close()
func _finish() -> void:
	if OS.get_environment("GAUNTLET_REQUIRE_COMPLETION")=="1":
		_expect(not summaries.is_empty(),"严格验收必须实际运行至少一个构筑")
		for row in summaries:_expect(row.get("complete",false),"连续三阶段必须实际完成："+str(row.get("id",""))+" stopped="+str(row.get("stopped_at","")))
	_write("summary.json",{"assertions":assertions,"failures":failures,"cases":summaries,"scope":"同检查点的终章三阶段连续资源对照；失败属于证据，不视作测试失败；未证明自然七章平衡"})
	print("FINAL_GAUNTLET: %d assertions, %d failures"%[assertions,failures.size()])
	quit(0 if failures.is_empty() else 1)
