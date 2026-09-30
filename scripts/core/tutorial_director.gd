# 教学导演(GDD §八):分步教学提示触发器
# 提示文案外置 data/tutorial.json;触发方式:turn(回合计数)/event(EventBus 事件)/spirit(灵气阈值)
# 每条提示只触发一次;无 class_name,经动态 load / preload 实例化
extends RefCounted

var _tips: Array = []
var _shown: Dictionary = {}

func _init() -> void:
	var data = JsonLoader.load_file("res://data/tutorial.json")
	if data is Dictionary:
		_tips = data.get("tips", [])

func was_shown(tip_id: String) -> bool:
	return _shown.has(tip_id)

func shown_count() -> int:
	return _shown.size()

# 回合触发:返回本回合应显示的提示(数组,通常 0-1 条)
func check_turn(turn: int) -> Array:
	return _match(func(trig: Dictionary) -> bool:
		return str(trig.get("type", "")) == "turn" and int(trig.get("turn", 0)) == turn
	)

# 事件触发:EventBus 事件名匹配,可选 object 字段限定物体
func check_event(event_name: String, data: Dictionary = {}) -> Array:
	return _match(func(trig: Dictionary) -> bool:
		if str(trig.get("type", "")) != "event" or str(trig.get("event", "")) != event_name:
			return false
		var want_obj = str(trig.get("object", ""))
		if want_obj != "" and str(data.get("object_id", "")) != want_obj:
			return false
		return true
	)

# 灵气阈值触发
func check_spirit(density: int) -> Array:
	return _match(func(trig: Dictionary) -> bool:
		return str(trig.get("type", "")) == "spirit" and density >= int(trig.get("min", 99))
	)

func _match(pred: Callable) -> Array:
	var out = []
	for tip in _tips:
		var tid = str(tip.get("id", ""))
		if tid == "" or _shown.has(tid):
			continue
		var trig: Dictionary = tip.get("trigger", {})
		if pred.call(trig):
			_shown[tid] = true
			out.append(tip)
	return out
