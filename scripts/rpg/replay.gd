# 日志无墙上时钟；相同目录版本、初始状态、显式输入逐事件重演。
class_name RpgReplay
extends RefCounted

const BattleEngine = preload("res://scripts/rpg/battle_engine.gd")
const Commands = preload("res://scripts/rpg/command_rules.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")

static func record(initial: Dictionary, commands: Array[Dictionary], events: Array[Dictionary], catalog: RefCounted = null) -> Dictionary:
	var effective := catalog
	if effective == null:
		effective = Catalog.new()
		effective.load_all()
	return {"schema_version": 1, "rules_version": initial.get("rules_version", ""), "mechanics_fingerprint": effective.mechanics_fingerprint(), "seed": initial.get("seed", 0), "initial": initial.duplicate(true), "commands": commands.duplicate(true), "events": events.duplicate(true)}

static func verify(recording: Dictionary, catalog: RefCounted, policy: RefCounted = null) -> Dictionary:
	if recording.get("schema_version") != 1 or recording.get("rules_version") != catalog.rules_version or not recording.get("initial") is Dictionary or not recording.get("commands") is Array or not recording.get("events") is Array:
		return _failure(-1, "重放结构或规则版本非法", null, null)
	if recording.has("mechanics_fingerprint") and recording.mechanics_fingerprint != catalog.mechanics_fingerprint():
		return _failure(-1, "重放技能数据指纹与当前目录不符", recording.mechanics_fingerprint, catalog.mechanics_fingerprint())
	if recording.get("seed") != recording.initial.get("seed"):
		return _failure(-1, "seed与初始快照不符", recording.initial.get("seed"), recording.get("seed"))
	var engine := BattleEngine.new(catalog)
	engine.set_policy(policy)
	engine.restore(recording.initial)
	if not engine.last_errors.is_empty(): return _failure(-1, "初始快照非法", [], engine.last_errors)
	var actual: Array[Dictionary] = []
	var expected: Array = recording.events
	for index in range(recording.commands.size()):
		if not recording.commands[index] is Dictionary: return _failure(actual.size(), "指令结构非法", null, recording.commands[index])
		actual.append_array(engine.advance(false))
		var prefix := _compare_prefix(expected, actual, recording.schema_version is float)
		if not prefix.is_empty(): return prefix
		var command: Dictionary = recording.commands[index].duplicate(true)
		var revision = command.get("expected_revision")
		if revision is float and is_finite(revision) and revision == floor(revision): command.expected_revision = int(revision)
		var result := engine.submit(command)
		if not result.accepted: return _failure(actual.size(), "指令被拒绝", command, result.reasons)
		actual.append_array(result.events)
		prefix = _compare_prefix(expected, actual, recording.schema_version is float)
		if not prefix.is_empty(): return prefix
	if actual.size() < expected.size(): actual.append_array(engine.advance(false))
	for index in range(maxi(actual.size(), expected.size())):
		var wanted = expected[index] if index < expected.size() else null
		var found = actual[index] if index < actual.size() else null
		if not _same_json_value(wanted, found, recording.schema_version is float): return _failure(index, "结算事件不同", wanted, found)
	return {"matches": true, "first_difference": {}, "event_count": actual.size(), "fingerprint_verified": recording.has("mechanics_fingerprint"), "legacy_unfingerprinted": not recording.has("mechanics_fingerprint")}

# Dictionary键序不属于规则输入；数值的JSON表示统一，但数组顺序保持。
static func canonical(value) -> String:
	return JSON.stringify(_ordered(value), "", true, true)

static func _ordered(value):
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort()
		for key in keys: result[key] = _ordered(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_ordered(item))
		return result
	if value is float and is_finite(value) and value == floor(value): return int(value)
	return value

static func _failure(index: int, reason: String, expected, actual) -> Dictionary:
	return {"matches": false, "first_difference": {"event_index": index, "reason": reason, "expected": expected, "actual": actual}}

# Godot4.6.3的单次十进制解析并非总在2ULP内（实测采样可差4ULP）。
# 只接受精确原值或同版本full_precision JSON运输一次的精确结果；没有ULP范围容差。
# 不修改记录、不近似伤害/随机，整数、字符串、数组顺序与字段集合仍逐项严格比较。
static func _same_json_value(expected, actual, transported: bool = false) -> bool:
	if expected is Dictionary and actual is Dictionary:
		if expected.size() != actual.size(): return false
		for key in expected:
			if not actual.has(key) or not _same_json_value(expected[key], actual[key], transported): return false
		return true
	if expected is Array and actual is Array:
		if expected.size() != actual.size(): return false
		for index in range(expected.size()):
			if not _same_json_value(expected[index], actual[index], transported): return false
		return true
	if (expected is int or expected is float) and (actual is int or actual is float):
		if expected == actual: return true
		# 整数语义不得用浮点误差容忍吞掉小数篡改。
		if expected is int or actual is int: return false
		if not transported or not is_finite(expected) or not is_finite(actual) or signf(expected) != signf(actual): return false
		return expected == JSON.parse_string(JSON.stringify(actual, "", true, true))
	return typeof(expected) == typeof(actual) and expected == actual

static func _compare_prefix(expected: Array, actual: Array, transported: bool) -> Dictionary:
	for index in range(actual.size()):
		var wanted = expected[index] if index < expected.size() else null
		if not _same_json_value(wanted, actual[index], transported): return _failure(index, "结算事件不同", wanted, actual[index])
	return {}
