# 关卡导演(GDD §八):三阶段流程(侦查/惊醒/决战)+ 棺材主逃脱判定
# 配置外置 maps.json levelFlow;无 class_name,经动态 load / preload 实例化(引用 EventBus)
extends RefCounted

const ESCAPE_LOSE_TEXT := "棺材主逃脱了…"
const WIPE_LOSE_TEXT := "全员阵亡…"

var _state: GameState
var _stages: Array = []
var _escape_cfg: Dictionary = {}
var _current_stage: String = ""

func _init(state: GameState) -> void:
	_state = state
	_stages = state.level_flow.get("stages", [])
	_escape_cfg = state.level_flow.get("escape", {})

# 回合数 → 阶段配置(stages 按 fromTurn 升序,取 fromTurn <= turn 的最后一个)
func stage_for_turn(turn: int) -> Dictionary:
	var result: Dictionary = {}
	for s in _stages:
		if int(s.get("fromTurn", 1)) <= turn:
			result = s
	return result

func stage_id_for_turn(turn: int) -> String:
	return str(stage_for_turn(turn).get("id", ""))

func stage_name(sid: String) -> String:
	for s in _stages:
		if str(s.get("id", "")) == sid:
			return str(s.get("name", sid))
	return sid

# 玩家回合开始结算:推进阶段机并返回本回合效果
# 返回 {stage, changed, from, spirit_gain}
func on_player_turn_start(turn: int) -> Dictionary:
	var stage = stage_for_turn(turn)
	var sid = str(stage.get("id", ""))
	var changed = sid != _current_stage and _current_stage != ""
	var from = _current_stage
	_current_stage = sid
	_state.level_stage = sid
	return {
		"stage": sid,
		"changed": changed,
		"from": from,
		"spirit_gain": int(stage.get("spiritPerTurn", 0)),
	}

# 地图上的门格(objects 层 door),即 Boss 逃脱目标
func door_cells() -> Array:
	var cells = []
	for y in range(_state.map.rows):
		for x in range(_state.map.cols):
			if _state.map.get_object(x, y) == "door":
				cells.append(Vector2i(x, y))
	return cells

func nearest_door(pos: Vector2i) -> Vector2i:
	var best = Vector2i(-1, -1)
	var best_d = 1 << 30
	for c in door_cells():
		var d = absi(c.x - pos.x) + absi(c.y - pos.y)
		if d < best_d:
			best_d = d
			best = c
	return best

# 逃脱是否激活:到 startTurn 且灵气低于封印阈值(未受封印威胁)
func escape_active(turn: int, spirit_density: int) -> bool:
	if _escape_cfg.is_empty():
		return false
	if turn < int(_escape_cfg.get("startTurn", 99)):
		return false
	return spirit_density < int(_escape_cfg.get("requireSpiritBelow", 6))

# 距逃脱开始剩余回合数(<=0 表示已开始)
func escape_countdown(turn: int) -> int:
	if _escape_cfg.is_empty():
		return 1 << 30
	return int(_escape_cfg.get("startTurn", 0)) - turn

func escape_warn_turns() -> int:
	return int(_escape_cfg.get("warnTurns", 2))

# 棺材主(Boss)是否已到门口(与门格相邻或站上)→ 逃脱成功
# 注:door 物体带 blocking 标签,单位无法站上门格本身,故按"到门边"判定
func check_boss_escaped() -> Unit:
	var doors = door_cells()
	for e in _state.enemies:
		if not e.is_alive:
			continue
		if not (bool(e.ai_profile.get("bossPhases", false)) or e.tags.has("boss")):
			continue
		for c in doors:
			if absi(e.position.x - c.x) + absi(e.position.y - c.y) <= 1:
				return e
	return null

# Boss 到门格:置失败原因 + 广播 boss:escaped(含失败文案),返回是否触发
func report_boss_escaped() -> bool:
	var boss = check_boss_escaped()
	if boss == null:
		return false
	_state.lose_reason = "escaped"
	EventBus.emit("boss:escaped", {
		"unit_id": boss.id,
		"pos": boss.position,
		"reason_text": ESCAPE_LOSE_TEXT,
	})
	return true
