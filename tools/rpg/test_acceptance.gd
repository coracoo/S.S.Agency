# 最终验收只运行真实模型；失败终局也是必须保留的证据。
extends RefCounted

const F = preload("res://tools/rpg/fixtures.gd")

static func run() -> Array[String]:
	F.assertion_count = 0
	var failures: Array[String] = []
	for name in ["balance_sweep", "strategy_policies"]:
		F.expect(FileAccess.file_exists("res://tools/rpg/%s.gd" % name), "验收工具尚未实现：" + name, failures)
	if not failures.is_empty(): return failures
	var Sweep = load("res://tools/rpg/balance_sweep.gd")
	var sweeper = Sweep.new()
	F.expect(sweeper.combinations().size() == 20, "六选三恰20种", failures)
	var party: Array[String] = ["guard", "swordsman", "healer"]
	for mode in ["chain", "boss_only"]:
		var output: Dictionary = sweeper.run(party, "direct_damage", 11, mode)
		F.expect(output.outcome in ["victory", "defeat", "incomplete"], "合法终局必须保留", failures)
		F.expect(sweeper.last_audit.errors.is_empty(), "真实连战重放/继承/幂等：" + str(sweeper.last_audit.errors), failures)
		F.expect(sweeper.last_audit.battles.size() > 0, "不能用空结果冒充连战", failures)
		F.expect(output.keys().size() == 13 and output.has("terminal_reason") and output.has("replay_path"), "输出13项固定协议", failures)
		F.expect(FileAccess.file_exists(output.replay_path), "完整重放日志落盘", failures)
		var transported = JSON.parse_string(FileAccess.get_file_as_string(output.replay_path))
		for battle in transported.audit.battles:
			var verified: Dictionary = preload("res://scripts/rpg/replay.gd").verify(battle.replay, sweeper._catalog, preload("res://scripts/rpg/enemy_policy.gd").new())
			F.expect(verified.matches, "落盘JSON逐事件重放：" + str(verified.get("first_difference", {})), failures)
		if output.outcome == "victory":
			F.expect(sweeper.last_audit.final_campaign.level == 5 and sweeper.last_audit.final_campaign.xp == (200 if mode == "chain" else 120), "胜利链路精确XP且仍L5", failures)
		var repeated: Dictionary = sweeper.run(party, "direct_damage", 11, mode)
		F.expect(output == repeated, "同组合/策略/种子结果逐字段一致", failures)
	_test_policy_contract(failures)
	var limited := LimitedSweep.new()
	limited.output_dir = sweeper.output_dir.path_join("timeout_fixture")
	var timeout: Dictionary = limited.run(party, "direct_damage", 11, "chain")
	F.expect(timeout.outcome == "incomplete" and timeout.terminal_reason.contains("安全上限") and timeout.rounds_by_battle.slice_boss == 2, "前两战胜利后的Boss超时仍为未完成，保留实际超限轮数", failures)
	F.expect(limited.last_audit.errors.is_empty() and limited.last_audit.final_campaign.xp == 80, "超时保留前80XP与可重放日志，不伪发Boss奖励", failures)
	_test_round_limit_terminal(sweeper.output_dir, failures)
	var passive := PassiveSweep.new()
	passive.output_dir = sweeper.output_dir.path_join("defeat_fixture")
	var defeat: Dictionary = passive.run(party, "direct_damage", 47, "chain")
	F.expect(defeat.outcome == "defeat" and defeat.rounds_by_battle.size() == 1 and passive.last_audit.final_campaign.xp == 0, "纯防御夹具真实败北保留，无下一场或奖励", failures)
	F.expect(passive.last_audit.errors.is_empty() and FileAccess.file_exists(defeat.replay_path), "败北逐事件重放/重试继承/日志保留", failures)
	F.expect(sweeper._round_limit_for("slice_boss") == 100, "正式批测上限保持100轮", failures)
	var matrix_mode := OS.get_environment("RPG_SWEEP_MODE")
	if not matrix_mode.is_empty():
		for mode in ["chain", "boss_only"]:
			if matrix_mode == "both" or matrix_mode == mode:
				var matrix: Dictionary = sweeper.run_matrix(mode)
				F.expect(matrix.count == 180 and matrix.errors.is_empty(), "矩阵180条及全部审计通过：" + str(matrix.errors), failures)
	print("RPG acceptance 断言：", F.assertion_count)
	return failures

static func _test_round_limit_terminal(output_dir: String, failures: Array[String]) -> void:
	var boundary := BurnBoundarySweep.new()
	boundary.output_dir = output_dir.path_join("burn_boundary_fixture")
	var party: Array[String] = ["swordsman", "mage", "healer"]
	var output: Dictionary = boundary.run(party, "direct_damage", 11, "chain")
	F.expect(output.outcome == "incomplete" and output.terminal_reason.contains("安全上限"), "超限首槽灼烧胜利必须优先判未完成", failures)
	F.expect(output.rounds_by_battle == {"slice_1": 5}, "摘要保留实际第5轮，不能截成第4轮胜利", failures)
	F.expect(boundary.last_audit.battles.size() == 1 and boundary.last_audit.rest.is_empty(), "超限终局停止链路，不进入第二战或休息", failures)
	var safe: Dictionary = boundary.last_audit.final_campaign
	F.expect(safe.xp == 0 and safe.applied_battle_ids.is_empty(), "超限终局不交付战果或发XP", failures)
	var first: Dictionary = boundary.last_audit.battles[0]
	F.expect(first.final.round == 5 and first.final.outcome == "victory", "原始引擎第5轮胜利保留供诊断", failures)
	F.expect(first.final.event_log[-1].type == "outcome" and first.final.event_log[-1].payload == {"outcome": "victory", "round": 5}, "不篡改原始胜利事件", failures)
	var lethal_burn := false
	for event in first.final.event_log:
		if event.type == "periodic_damage" and event.payload.absorption.defeated:
			lethal_burn = event.payload.status.id == "burn" and event.payload.damage == 16 and event.payload.absorption.hp_before == 15
	F.expect(lethal_burn, "真实灼烧16点击倒余15HP猎犬，非注入终局", failures)
	F.expect(boundary.last_audit.errors.is_empty() and first.verification.matches, "超限原始事件仍可完整重放", failures)
	for id in safe.party:
		F.expect(safe.roster[id].hp == first.setup.actors[id].hp and safe.roster[id].mp == first.setup.actors[id].mp, "超限不写回战内资源：" + id, failures)
	F.expect(safe.inventory == first.setup.inventory, "超限不写回战内库存", failures)
	var transported = JSON.parse_string(FileAccess.get_file_as_string(output.replay_path))
	F.expect(transported.result.outcome == "incomplete" and transported.audit.battles.size() == 1 and transported.audit.battles[0].final.round == 5 and transported.audit.battles[0].final.outcome == "victory", "落盘同时保留未完成分类与原始超限胜利", failures)
	var verified: Dictionary = preload("res://scripts/rpg/replay.gd").verify(transported.audit.battles[0].replay, boundary._catalog, preload("res://scripts/rpg/enemy_policy.gd").new())
	F.expect(verified.matches, "灼烧边界落盘逐事件重放一致", failures)
	var within := FirstLimitedSweep.new()
	within.output_dir = output_dir.path_join("within_limit_fixture")
	var normal_party: Array[String] = ["guard", "swordsman", "healer"]
	var normal: Dictionary = within.run(normal_party, "direct_damage", 11, "chain")
	F.expect(normal.rounds_by_battle.slice_1 == 4 and within.last_audit.battles[0].final.round == 4 and within.last_audit.battles[0].final.outcome == "victory", "恰第4轮正常胜利仍在限轮内", failures)
	F.expect(normal.outcome == "victory" and within.last_audit.battles.size() == 3 and within.last_audit.final_campaign.xp == 200 and within.last_audit.final_campaign.applied_battle_ids.size() == 3 and within.last_audit.errors.is_empty(), "限轮内胜利正常交付并完成三战200XP", failures)

static func _test_policy_contract(failures: Array[String]) -> void:
	var Engine = preload("res://scripts/rpg/battle_engine.gd")
	var Enemy = preload("res://scripts/rpg/enemy_policy.gd")
	var Policies = load("res://tools/rpg/strategy_policies.gd")
	var engine = Engine.new()
	engine.set_policy(Enemy.new())
	engine.start({"actors": {"p_guard": F.actor("guard", "p_guard"), "e_hound": F.enemy("hound", "e_hound")}, "inventory": F.state(F.actor("guard", "p_guard")).inventory}, 11)
	engine.advance()
	for policy_id in Policies.IDS:
		var policy = Policies.new()
		var before: Dictionary = engine.snapshot()
		var command: Dictionary = policy.choose(policy_id, before, engine)
		F.expect(engine.preview(command).legal, policy_id + "只选择合法命令", failures)
		F.expect(engine.snapshot() == before, policy_id + "选择/预览不改变状态/RNG", failures)
		var hidden_changed: Dictionary = before.duplicate(true)
		for key in ["seed", "rng_state", "event_log", "command_log", "accepted_commands"]: hidden_changed.erase(key)
		F.expect(policy.choose(policy_id, hidden_changed, engine) == command, policy_id + "不依赖隐藏随机/历史", failures)
		# 所有技能MP耗尽时，控制策略必须仍能回退合法普攻。
	var state: Dictionary = engine.snapshot()
	state.actors.p_guard.mp = 0
	engine.restore(state)
	var fallback: Dictionary = Policies.new().choose("control_burst", engine.snapshot(), engine)
	F.expect(fallback.kind == "attack_physical" and engine.preview(fallback).legal, "无可用控制回退合法普攻", failures)


class LimitedSweep extends "res://tools/rpg/balance_sweep.gd":
	func _round_limit_for(encounter_id: String) -> int:
		return 1 if encounter_id == "slice_boss" else 100


class FirstLimitedSweep extends "res://tools/rpg/balance_sweep.gd":
	func _round_limit_for(encounter_id: String) -> int:
		return 4 if encounter_id == "slice_1" else 100


# 仅选择合法动作，让R4余15HP的猎犬在R5首槽被16点灼烧击倒；不改模型/资源。
class BurnBoundarySweep extends FirstLimitedSweep:
	func _player_command(policy: RefCounted, policy_id: String, state: Dictionary, engine: RefCounted) -> Dictionary:
		var actor: Dictionary = state.actors[state.active_actor_id]
		var hound := ""
		var shield := ""
		for id in state.actors:
			if state.actors[id].class_id == "hound": hound = id
			if state.actors[id].class_id == "shield_soldier": shield = id
		if shield.is_empty(): return policy.choose(policy_id, state, engine)
		var kind := "defend"
		var ability := ""
		var target := ""
		if state.round == 1:
			target = shield
			if actor.class_id == "swordsman": kind = "skill"; ability = "heavy_slash"
			elif actor.class_id == "mage": kind = "skill"; ability = "firebolt"
			else: kind = "attack_magic"
		elif state.round == 2:
			if actor.class_id == "swordsman": kind = "skill"; ability = "heavy_slash"; target = shield
			elif actor.class_id == "mage": kind = "skill"; ability = "burn_brand"; target = hound
			elif state.actors[shield].hp > 0: kind = "attack_magic"; target = shield
		elif state.round == 3 and actor.class_id == "swordsman": kind = "skill"; ability = "heavy_slash"; target = hound
		elif state.round == 4 and actor.class_id == "mage": kind = "attack_magic"; target = hound
		var command := {"command_id": "burn_boundary_%d" % state.revision, "expected_revision": int(state.revision), "actor_id": state.active_actor_id, "kind": kind, "ability_id": ability, "target_ids": [] if target.is_empty() else [target]}
		policy.last_decision = {"round": state.round, "actor_id": state.active_actor_id, "command": command, "reason": "灼烧限轮夹具：真实合法动作，不是矩阵策略", "score": 0, "preview": engine.preview(command)}
		return command


# 故意不进攻、不用药的失败覆盖；不纳入三公开策略胜率矩阵。
class PassiveSweep extends "res://tools/rpg/balance_sweep.gd":
	func _player_command(policy: RefCounted, _policy_id: String, state: Dictionary, _engine: RefCounted) -> Dictionary:
		var command := {"command_id": "passive_%d" % state.revision, "expected_revision": int(state.revision), "actor_id": state.active_actor_id, "kind": "defend", "ability_id": "", "target_ids": []}
		policy.last_decision = {"round": state.round, "actor_id": state.active_actor_id, "command": command, "reason": "失败覆盖夹具：明确只防御，不是矩阵策略", "score": 0, "preview": {}}
		return command
