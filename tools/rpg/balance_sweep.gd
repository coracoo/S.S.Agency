# L5标准装备的真实连战；seed仅传入引擎，不改变正式Campaign随机开局规则。
class_name RpgBalanceSweep
extends RefCounted
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Campaign = preload("res://scripts/rpg/campaign.gd")
const Battle = preload("res://scripts/rpg/battle_engine.gd")
const Enemy = preload("res://scripts/rpg/enemy_policy.gd")
const Replay = preload("res://scripts/rpg/replay.gd")
const Policies = preload("res://tools/rpg/strategy_policies.gd")
const ROUND_LIMIT := 100
var last_audit: Dictionary = {}
var _catalog: RefCounted
var output_dir: String

func _init() -> void:
	_catalog = Catalog.new()
	_catalog.load_all()
	output_dir = OS.get_environment("RPG_SWEEP_OUTPUT")
	if output_dir.is_empty(): output_dir = "user://rpg_tests/acceptance"

static func combinations() -> Array:
	var result: Array = []
	for a in range(Catalog.CLASS_IDS.size()):
		for b in range(a + 1, Catalog.CLASS_IDS.size()):
			for c in range(b + 1, Catalog.CLASS_IDS.size()): result.append([Catalog.CLASS_IDS[a], Catalog.CLASS_IDS[b], Catalog.CLASS_IDS[c]])
	return result

func run(class_ids: Array[String], policy_id: String, seed: int, mode: String) -> Dictionary:
	var key := "%s_%s_%d_%s" % ["-".join(class_ids), policy_id, seed, mode]
	var result := {"party": class_ids.duplicate(), "strategy": policy_id, "seed": seed, "mode": mode, "outcome": "incomplete", "rounds_by_battle": {}, "knockdowns": {}, "hp_remaining": {}, "mp_remaining": {}, "items_used": {}, "decisions": [], "terminal_reason": "", "replay_path": output_dir.path_join(key + ".json")}
	# 输出固定13字段；完整审计与引擎日志另置同一路径，不塞入结果摘要。
	last_audit = {"errors": [], "battles": [], "rest": [], "final_campaign": {}}
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or not mode in ["chain", "boss_only"] or not Policies.IDS.has(policy_id):
		result.terminal_reason = "未隔离或参数非法"
		last_audit.errors.append(result.terminal_reason)
		return result
	DirAccess.make_dir_recursive_absolute(output_dir)
	var campaign := Campaign.new(_catalog, null, "user://rpg_v1/tests/sweep_" + key + ".json")
	if not campaign.new_run(class_ids, 5).ok:
		last_audit.errors.append(campaign.last_error)
		return result
	var initial_inventory: Dictionary = campaign.snapshot().inventory.duplicate(true)
	for id in campaign.snapshot().party: result.knockdowns[id] = 0
	var encounter_ids: Array = ["slice_1", "slice_2", "slice_boss"] if mode == "chain" else ["slice_boss"]
	for encounter_id in encounter_ids:
		if encounter_id == "slice_boss" and mode == "chain":
			var before_rest: Dictionary = campaign.snapshot()
			_check(campaign.rest().ok, "明确休息点失败")
			var after_rest: Dictionary = campaign.snapshot()
			_check(before_rest.inventory == after_rest.inventory, "休息偷偷补库存")
			for actor in after_rest.roster.values(): _check(actor.hp == actor.stats.hp and actor.mp == actor.stats.mp, "休息未按公开规则回复")
			last_audit.rest.append({"before": before_rest, "after": after_rest})
		var round_limit := _round_limit_for(encounter_id)
		var safe: Dictionary = campaign.safe_snapshot()
		var world := {"scene_path": "res://scenes/v3/stage.tscn", "player_x": 735.5, "facing": -1, "resolved": safe.world.get("resolved", {}), "dlg_fired": {}, "exit_prompted": false, "spirit": 2, "party_index": 0}
		var patch := {"resolved": {"basin_reflection" if encounter_id == "slice_1" else "bell_self_ring": true}, "next_scene": "res://scenes/v3/stage.tscn"}
		var start: Dictionary = campaign.begin_battle(encounter_id, world, patch)
		_check(start.ok, "进战失败：" + str(start.get("error", "")))
		if not start.ok: break
		_check(start.setup.inventory == safe.inventory, "进战库存改变")
		for id in safe.party:
			_check(start.setup.actors[id].hp == safe.roster[id].hp and start.setup.actors[id].mp == safe.roster[id].mp, "连战资源未继承：" + id)
		var engine := Battle.new(_catalog)
		engine.set_policy(Enemy.new())
		_check(engine.start(start.setup, seed).started, "引擎启动失败")
		var initial: Dictionary = engine.snapshot()
		var policy := Policies.new(_catalog)
		var decisions: Array = []
		while true:
			engine.advance(false)
			var state: Dictionary = engine.snapshot()
			if not state.outcome.is_empty() or state.round > round_limit: break
			var command: Dictionary
			var is_player: bool = state.actors[state.active_actor_id].side == "player"
			if is_player: command = _player_command(policy, policy_id, state, engine)
			else: command = Enemy.new().choose_command(state, _catalog)
			if command.is_empty():
				last_audit.errors.append("策略无合法命令")
				break
			var submitted: Dictionary = engine.submit(command)
			_check(submitted.accepted, "指令拒绝：" + str(submitted.reasons))
			if not submitted.accepted: break
			if is_player:
				var decision := policy.last_decision.duplicate(true)
				decision["encounter_id"] = encounter_id
				decision["resources_before"] = _resources(state)
				decision["resources_after"] = _resources(engine.snapshot())
				decisions.append(decision)
		var final: Dictionary = engine.snapshot()
		result.rounds_by_battle[encounter_id] = int(final.round)
		result.decisions.append_array(decisions)
		for event in final.event_log:
			if event.type == "actor_defeated" and result.knockdowns.has(event.target_id): result.knockdowns[event.target_id] += 1
		var commands: Array[Dictionary] = []
		commands.assign(final.command_log)
		var events: Array[Dictionary] = []
		for event in final.event_log:
			if event.sequence > initial.event_sequence: events.append(event)
		var recording := Replay.record(initial, commands, events)
		var verified := Replay.verify(recording, _catalog, Enemy.new())
		_check(verified.matches, "逐事件重放不一致：" + str(verified.get("first_difference", {})))
		last_audit.battles.append({"encounter_id": encounter_id, "seed": seed, "setup": start.setup, "replay": recording, "verification": verified, "final": final})
		for id in safe.party:
			result.hp_remaining[id] = final.actors[id].hp
			result.mp_remaining[id] = final.actors[id].mp
		for id in initial_inventory: result.items_used[id] = int(initial_inventory[id]) - int(final.inventory[id])
		# advance可能在超限轮的首槽灼烧直接产生终局；先判上限，不能交付该战果。
		if final.round > round_limit or final.outcome.is_empty():
			result.outcome = "incomplete"
			result.terminal_reason = "%d轮安全上限，未完成" % round_limit if final.round > round_limit else "策略/引擎错误，未完成"
			break
		result.outcome = final.outcome
		result.terminal_reason = encounter_id + "：" + final.outcome
		var roster: Array[Dictionary] = []
		for id in safe.party: roster.append(final.actors[id].duplicate(true))
		var battle_result := {"battle_id": start.battle_id, "outcome": final.outcome, "roster": roster, "inventory": final.inventory, "xp": start.xp if final.outcome == "victory" else 0, "story_patch": patch if final.outcome == "victory" else {}, "replay": recording}
		var before_apply: Dictionary = campaign.safe_snapshot()
		_check(campaign.apply_result(battle_result).ok, "战果交付失败")
		var after_apply: Dictionary = campaign.safe_snapshot()
		var repeated: Dictionary = campaign.apply_result(battle_result)
		_check(repeated.ok and campaign.safe_snapshot() == after_apply and repeated.story_patch.is_empty(), "重复战果更改场景/谜题/经验")
		_check(engine.advance().is_empty() and engine.snapshot() == final, "终局advance不是幂等")
		if not commands.is_empty(): _check(not engine.submit(commands[-1]).accepted and engine.snapshot() == final, "终局重复命令改变模型")
		if final.outcome == "defeat":
			_check(after_apply == before_apply, "败北写回资源或经验")
			var retry: Dictionary = campaign.retry_battle()
			_check(retry.setup == start.setup and retry.seed == start.seed and retry.battle_id == start.battle_id, "败北重试补资源或换种子")
			break
		_check(repeated.already_applied, "胜利重复未识别")
		for actor in roster: _check(after_apply.roster[actor.actor_id].hp == actor.hp and after_apply.roster[actor.actor_id].mp == actor.mp, "战果资源未持久化")
		_check(after_apply.inventory == final.inventory, "战果库存未持久化")
		var restored := Campaign.new(_catalog, null, "user://rpg_v1/tests/sweep_" + key + ".json")
		_check(restored.load_run().ok and restored.apply_result(battle_result).already_applied and restored.safe_snapshot() == after_apply, "跨实例重复交付不幂等")
	last_audit.final_campaign = campaign.safe_snapshot()
	if result.outcome == "victory" and result.rounds_by_battle.size() != encounter_ids.size(): result.outcome = "incomplete"
	if result.outcome == "victory": _check(campaign.snapshot().xp == (200 if mode == "chain" else 120) and campaign.snapshot().level == 5, "胜利XP或等级错误")
	var file := FileAccess.open(result.replay_path, FileAccess.WRITE)
	if file == null: _check(false, "无法写完整重放证据")
	else: file.store_string(JSON.stringify({"result": result, "audit": last_audit}, "", true, true))
	return result

func run_matrix(mode: String) -> Dictionary:
	var rows: Array = []
	var errors: Array = []
	var outcomes := {"victory": 0, "defeat": 0, "incomplete": 0}
	for party in combinations():
		var ids: Array[String] = []
		ids.assign(party)
		for policy_id in Policies.IDS:
			for seed in [11, 23, 47]:
				var row := run(ids, policy_id, seed, mode)
				rows.append(row)
				outcomes[row.outcome] += 1
				for error in last_audit.errors: errors.append({"party": party, "strategy": policy_id, "seed": seed, "error": error})
				print("SWEEP %s %d/180 %s %s seed=%d %s %s" % [mode, rows.size(), "/".join(party), policy_id, seed, row.outcome, str(row.rounds_by_battle)])
	var summary := {"mode": mode, "count": rows.size(), "outcomes": outcomes, "errors": errors, "rows": rows}
	var file := FileAccess.open(output_dir.path_join("summary_" + mode + ".json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(summary, "", true, true))
	else: errors.append("无法写矩阵摘要")
	print("SWEEP SUMMARY ", mode, " ", outcomes, " errors=", errors.size())
	return summary

func _check(condition: bool, message: String) -> void:
	if not condition: last_audit.errors.append(message)

static func _resources(state: Dictionary) -> Dictionary:
	var result := {"inventory": state.inventory.duplicate(true), "actors": {}}
	for id in state.actors:
		if state.actors[id].side == "player": result.actors[id] = {"hp": state.actors[id].hp, "mp": state.actors[id].mp}
	return result


# 可被验收夹具缩短以实测超限分支；正式矩阵固定100，绝不按胜利处理。
func _round_limit_for(_encounter_id: String) -> int:
	return ROUND_LIMIT


# 验收失败夹具可注入明确的被动动作；正常矩阵仍仅调用三种公开策略。
func _player_command(policy: RefCounted, policy_id: String, state: Dictionary, engine: RefCounted) -> Dictionary:
	return policy.choose(policy_id, state, engine)
