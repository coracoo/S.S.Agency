# 只用真实正式事务准备C7-06；从已验证失败检查点局部重试，不伪造角色、资源或战果。
extends SceneTree
const Campaign = preload("res://scripts/rpg/campaign.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Store = preload("res://scripts/rpg/save_store.gd")
const Router = preload("res://scripts/rpg/encounter_router.gd")
const OldStrategy = preload("res://tools/campaign/saga_battle_strategy.gd")
const Replay = preload("res://scripts/rpg/replay.gd")
const EnemyPolicy = preload("res://scripts/rpg/enemy_policy.gd")
const SAVE := "user://campaign_v1/slot_01.json"
var strategy: GDScript
var catalog: RefCounted
var assertions := 0
var failures: Array[String] = []
var output := ""
var ready_bytes: PackedByteArray
var original_seed := 0
var original_gear: Dictionary
var summaries: Array = []
var evidence_root := ""

func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	evidence_root = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("ssa-campaign-evidence/goal-loadouts-20261008")
	output = OS.get_environment("TACTICS_OUTPUT")
	if output.is_empty(): output = evidence_root.path_join("tactics")
	_expect(output.is_absolute_path() and not output.replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://").replace("\\", "/")), "证据目录必须位于仓库外")
	_expect(FileAccess.file_exists("res://tools/campaign/loadout_battle_strategy.gd"), "需要可执行的公开状态战术策略")
	if not failures.is_empty(): _finish(); return
	strategy = load("res://tools/campaign/loadout_battle_strategy.gd")
	catalog = Catalog.new()
	_expect(catalog.load_all().is_empty(), "真实目录完整载入")
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var checkpoint := OS.get_environment("TACTICS_CHECKPOINT")
	if checkpoint.is_empty(): checkpoint = evidence_root.path_join("saga/sendoff-gentle-dawn/checkpoints/pending_C7-06.json")
	_expect(FileAccess.file_exists(checkpoint), "已有真实C7-06战前检查点")
	if not failures.is_empty(): _finish(); return
	_copy_to_isolated(FileAccess.get_file_as_bytes(checkpoint))
	var model := Campaign.new(catalog, Store.new(catalog), SAVE)
	if not _ok(model.load_run(), "原始检查点通过正式校验"): _finish(); return
	var safe: Dictionary = model.safe_snapshot()
	original_seed = safe.pending_battle.seed
	original_gear = safe.gear.duplicate(true)
	_expect(safe.pending_battle.encounter_id == "saga_c7_06", "只运行C7-06")
	var baseline := _battle(model, "baseline", true)
	_expect(baseline.get("outcome") == "defeat", "保留不配装原策略真实败北对照")
	if not _ok(model.leave_saga_battle(), "真实败北后通过公开事务返回整备"): _finish(); return
	ready_bytes = FileAccess.get_file_as_bytes(SAVE)
	_write("legal-preparation-checkpoint.json", model.safe_snapshot())
	for variant in ["guard_control", "sword_shield"]:
		_copy_to_isolated(ready_bytes)
		model = Campaign.new(catalog, Store.new(catalog), SAVE)
		if not _ok(model.load_run(), variant + "恢复合法整备检查点"): continue
		if not _prepare(model, variant): continue
		var prepared: Dictionary = model.safe_snapshot()
		_write(variant + "-preparation.json", prepared)
		_expect(prepared.gear == original_gear, variant + "装配没有新增或复制装备")
		if not _ok(model.choose_saga_option(prepared.world, "C7-R04", "a2"), "批准的第二阶段重试选项"): continue
		if not _ok(model.complete_saga_scene(model.safe_snapshot().world, "C7-R04"), "真实完成败后重试互动"): continue
		if not _ok(model.begin_saga_scene(model.safe_snapshot().world, "C7-06"), "沿批准路线重进C7-06"): continue
		var world: Dictionary = model.safe_snapshot().world
		var router := Router.new(model, catalog)
		if not _ok(router.begin(world.scene_path, "res://scenes/rpg/battle.tscn", world, "C7-06"), "通过正式路由重新开战"): continue
		_expect(model.safe_snapshot().pending_battle.seed == original_seed, variant + "沿原战斗ID重试，没有重掷种子")
		var result := _battle(model, variant, false, router)
		_expect(result.get("outcome") == "victory", variant + "合法不同构筑通过真实命令获胜")
		if result.get("outcome") == "victory":
			var after: Dictionary = model.safe_snapshot()
			_expect(after.saga.battles.has("C7-06"), variant + "真实胜利提交到剧情记录")
			var resumed := Campaign.new(catalog, Store.new(catalog), SAVE)
			_expect(resumed.load_run().ok and resumed.safe_snapshot() == after, variant + "战果与有限消耗可续档")
	_finish()

func _prepare(model: RefCounted, variant: String) -> bool:
	# 先卸下其他在册身份占用的法器/刀盾；原持有者也必须留有合法构筑。
	if not _ok(model.set_loadout("p_controller", _build([], false)), "卸除控制者主动卡"): return false
	if not _ok(model.equip("p_controller", "weapon", ""), "释放唯一符具"): return false
	if not _ok(model.set_loadout("p_mage", {"version": 1, "active": {"sword": [], "mage": []}, "passive": ["steady_breath", "light_step"]}), "两形态同时调整为法器配置"): return false
	for setting in [["weapon", "spirit_bell"], ["armor", "monk_kesa"], ["accessory", "bead_bracelet"]]:
		if not _ok(model.equip("p_mage", setting[0], setting[1]), "焰华穿戴已持有装备：" + setting[1]): return false
	if not _ok(model.set_loadout("p_mage", {"version": 1, "active": {"sword": [], "mage": ["burn_brand", "firebolt", "seal", "weaken"]}, "passive": ["steady_breath", "light_step"]}), "焰华准备灼烧/追击/打断/减伤"): return false
	if not _ok(model.equip("p_healer", "weapon", "training_sigil"), "治疗者接过唯一符具"): return false
	if not _ok(model.set_loadout("p_healer", _build(["heal", "group_heal", "cleanse", "magic_break"])), "治疗者兼顾回复与破魔"): return false
	var party: Array[String] = ["p_guard", "p_mage", "p_healer"]
	if variant == "sword_shield":
		if not _ok(model.set_loadout("p_guard", _build([], false)), "非出战守卫先卸卡"): return false
		if not _ok(model.equip("p_guard", "weapon", ""), "释放唯一刀盾"): return false
		if not _ok(model.equip("p_swordsman", "weapon", "training_guard_blade"), "凛音使用已持有刀盾"): return false
		if not _ok(model.set_loadout("p_swordsman", _build(["shield_bash", "heavy_slash", "armor_break", "battle_spirit"])), "凛音准备跨职业打断与剑术"): return false
		party[0] = "p_swordsman"
	else:
		if not _ok(model.set_loadout("p_guard", _build(["shield_bash", "cover", "iron_wall", "armor_break"])), "守卫准备打断/防护/破甲"): return false
	if not _ok(model.set_party(party), "提交三人队伍"): return false
	var coins_before: int = model.safe_snapshot().saga.coins
	for purchase in [["mana_potion", 4], ["healing_potion", 2], ["revival_potion", 1]]:
		if not _ok(model.buy_saga_item(model.safe_snapshot().world, purchase[0], purchase[1]), "实际花钱购买有限补给"): return false
	_expect(model.safe_snapshot().saga.coins == coins_before - 169, "4法力/2治疗/1复苏严格支付169银钱")
	if not _ok(model.use_item_outside("healing_potion", "p_mage"), "实际消耗一瓶购买的治疗药补足焰华换装后的生命缺口"): return false
	# 不额外rest；换装提高上限不会免费回满新增HP/MP。
	return true

func _build(active: Array, passives: bool = true) -> Dictionary:
	return {"version": 1, "active": {"default": active.duplicate()}, "passive": ["steady_breath", "light_step"] if passives else []}

func _battle(model: RefCounted, variant: String, legacy: bool, adopted: RefCounted = null) -> Dictionary:
	var router: RefCounted = adopted if adopted != null else Router.new(model, catalog)
	if adopted == null:
		var started: Dictionary = model.retry_battle()
		if not _ok(started, variant + "恢复真实战前快照"): return {}
		if not _ok(router.adopt_battle(started), variant + "路由接纳真实快照"): return {}
	var engine: RefCounted = router.create_engine()
	_expect(engine != null, variant + "真实模型启动")
	if engine == null: return {}
	var before: Dictionary = model.safe_snapshot()
	var decisions: Array = []
	while engine.snapshot().outcome.is_empty() and decisions.size() < 160:
		engine.advance()
		var state: Dictionary = engine.snapshot()
		if not state.outcome.is_empty(): break
		if state.phase != "action_selection": break
		var ranked: Array = [] if legacy else strategy.ranked(state, engine, catalog)
		var command: Dictionary = OldStrategy.choose(state, engine, catalog) if legacy else (ranked[0].command if not ranked.is_empty() else {})
		if command.is_empty(): break
		decisions.append({"round": state.round, "command": command, "actors": state.actors.duplicate(true), "top_options": ranked.slice(0, 5)})
		if not _ok(engine.submit(command), variant + "真实命令提交", "accepted"): break
	var final: Dictionary = engine.snapshot()
	var result: Dictionary = router.result_from_engine()
	if not result.is_empty():
		var verified := Replay.verify(result.replay, catalog, EnemyPolicy.new())
		_expect(verified.matches, variant + "完整命令逐事件重放一致：" + str(verified.get("first_difference", {})))
		_write(variant + "-replay-verification.json", verified)
	_write(variant + "-decisions.json", decisions)
	_write(variant + "-result.json", result)
	_write(variant + "-final.json", final)
	if not result.is_empty(): _ok(router.finish(result), variant + "通过正式结果校验并提交")
	var summary := {"variant": variant, "outcome": final.outcome, "round": final.round, "commands": decisions.size(), "seed": before.pending_battle.seed, "inventory_before": before.inventory, "inventory_after": final.inventory, "party": before.party, "coins_before_battle": before.saga.coins}
	var resources := {}
	for id in before.party: resources[id] = {"hp": final.actors[id].hp, "mp": final.actors[id].mp, "max_hp": final.actors[id].stats.hp, "max_mp": final.actors[id].stats.mp}
	summary["remaining_party_resources"] = resources
	summaries.append(summary)
	print("LOADOUT_TACTICS_CASE: ", JSON.stringify(summary))
	return result

func _copy_to_isolated(bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute("user://campaign_v1")
	var file := FileAccess.open(SAVE, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

func _write(name: String, data: Variant) -> void:
	var file := FileAccess.open(output.path_join(name), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(data, "  ", true, true)); file.close()

func _ok(result: Dictionary, label: String, key: String = "ok") -> bool:
	_expect(result.get(key, false), label + "：" + str(result.get("error", result.get("reasons", ""))))
	return result.get(key, false)

func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)

func _finish() -> void:
	if DirAccess.dir_exists_absolute(output): _write("summary.json", {"assertions": assertions, "failures": failures, "cases": summaries, "scope": "C7-06局部、真实装配/购买/重试；没有自然七章平衡结论"})
	print("RPG_LOADOUT_TACTICS: %d assertions, %d failures" % [assertions, failures.size()])
	for failure in failures: printerr("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
