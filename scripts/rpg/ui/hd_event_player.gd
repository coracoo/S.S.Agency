# 顺序消费已提交事件；没有引擎引用，不做伤害、资源或随机数计算。
class_name HdEventPlayer
extends Node
signal drained
signal visual_warning(message: String)
signal _frame_tick(delta: float)
var _views: Dictionary = {}
var _batches: Array[Dictionary] = []
var _played_commands: Dictionary = {}
var _generation := 0
var _busy := false

func bind_actors(views: Dictionary) -> void:
	cancel()
	_views = views.duplicate()

func enqueue(events: Array, snapshot: Dictionary) -> void:
	_batches.append({"events": events.duplicate(true), "snapshot": snapshot.duplicate(true)})
	if _busy: return
	_busy = true
	_drain.call_deferred(_generation)

func is_busy() -> bool:
	return _busy

func cancel() -> void:
	_generation += 1
	_batches.clear()
	_played_commands.clear()
	_busy = false
	# 先唤醒当前代次的等待栈，让嵌套协程在节点释放前同步返回。
	_frame_tick.emit(0.0)
	for view in _views.values():
		if is_instance_valid(view): view.cancel_action()

func _process(delta: float) -> void:
	_frame_tick.emit(delta)

func _exit_tree() -> void:
	cancel()

func _drain(generation: int) -> void:
	while generation == _generation and not _batches.is_empty():
		var batch: Dictionary = _batches.pop_front()
		for event in batch.events:
			if generation != _generation or not is_inside_tree(): return
			await _play_event(event, generation)
		if generation != _generation or not is_inside_tree(): return
		# 每批最终姿态只服从该批快照，动画绝不反向改模型。
		for actor_id in batch.snapshot.get("actors", {}):
			var view = _view(actor_id)
			if view != null: view.set_downed(int(batch.snapshot.actors[actor_id].get("hp", 0)) <= 0)
	if generation != _generation: return
	_busy = false
	drained.emit()

func _play_event(event: Dictionary, generation: int) -> void:
	var payload: Dictionary = event.get("payload", {})
	var view = _view(str(event.get("target_id", "")))
	var action: StringName = &""
	match event.get("type", ""):
		"command_accepted":
			var command: Dictionary = payload.get("command", {})
			var id := str(command.get("command_id", ""))
			if id.is_empty() or _played_commands.has(id): return
			_played_commands[id] = true
			view = _view(str(event.get("actor_id", "")))
			action = &"defend" if command.get("kind") == "defend" else &"attack"
		"damage", "periodic_damage":
			if view != null:
				var absorption: Dictionary = payload.get("absorption", {})
				var loss := int(absorption.get("hp_loss", payload.get("damage", 0)))
				var absorbed := int(absorption.get("absorbed", 0))
				var text := "HP -%d · 盾 -%d" % [loss, absorbed] if absorbed > 0 else "-%d" % loss
				view.show_feedback(text, Color(1.0, 0.48, 0.36))
			action = &"hit"
		"actor_defeated":
			if view != null: view.set_downed(true)
			# down有意保持，不能等待action_finished。
			return
		"revived":
			if view != null: view.show_feedback("HP +%d" % int(payload.get("hp", 0)), Color(0.56, 1.0, 0.69))
			action = &"recover"
		"healed", "mp_restored":
			if view != null:
				view.show_feedback("%s +%d" % ["HP" if event.type == "healed" else "MP", int(payload.get("actual", 0))], Color(0.56, 1.0, 0.69))
			return
		_:
			return
	if view == null: return
	if not view.play_action(action):
		visual_warning.emit("角色动作未接受：%s" % action)
		return
	var elapsed := 0.0
	var limit: float = view.action_timeout()
	while is_instance_valid(view) and view.is_inside_tree() and view.is_action_busy():
		if generation != _generation or not is_inside_tree(): return
		var delta: float = await _frame_tick
		if generation != _generation: return
		elapsed += delta
		if elapsed >= limit:
			if is_instance_valid(view): view.cancel_action()
			visual_warning.emit("角色动作等待超时，已安全结束表现")
			return

func _view(actor_id: String) -> Variant:
	var view = _views.get(actor_id)
	return view if is_instance_valid(view) and view.is_inside_tree() else null
