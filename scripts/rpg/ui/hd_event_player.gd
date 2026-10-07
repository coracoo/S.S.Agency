# 顺序消费已提交事件；没有引擎引用，不做伤害、资源或随机数计算。
class_name HdEventPlayer
extends Node
signal drained
signal cancelled
signal event_presented(event: Dictionary)
signal action_started(command_event: Dictionary, timing: Dictionary)
signal visual_warning(message: String)
signal _frame_tick(delta: float)
var _views: Dictionary = {}
var _batches: Array[Dictionary] = []
var _played_commands: Dictionary = {}
var _presented_sequences: Dictionary = {}
var _attack_recovery: Dictionary = {}
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
	_presented_sequences.clear()
	_attack_recovery.clear()
	_busy = false
	# 先唤醒当前代次的等待栈，让嵌套协程在节点释放前同步返回。
	_frame_tick.emit(0.0)
	for view in _views.values():
		if is_instance_valid(view): view.cancel_action()
	cancelled.emit()

func _process(delta: float) -> void:
	if not _attack_recovery.is_empty(): _attack_recovery.elapsed += delta
	_frame_tick.emit(delta)

func _exit_tree() -> void:
	cancel()

func _drain(generation: int) -> void:
	while generation == _generation and not _batches.is_empty():
		var batch: Dictionary = _batches.pop_front()
		var has_new_events: bool = batch.events.is_empty()
		for index in batch.events.size():
			var event: Dictionary = batch.events[index]
			if generation != _generation or not is_inside_tree(): return
			var sequence := int(event.get("sequence",0))
			if sequence > 0 and _presented_sequences.has(sequence): continue
			has_new_events = true
			if sequence > 0: _presented_sequences[sequence] = true
			await _play_event(event, generation, _melee_target(batch.events,index))
		# 全重复批次连同它的旧快照都忽略，避免重试旧致死包覆盖后来的复苏。
		if not has_new_events: continue
		# 伤害已在命中点显示，来源仍须完整收招后才同步快照或解锁下一批。
		await _finish_attack_recovery(generation)
		if generation != _generation or not is_inside_tree(): return
		# 每批最终姿态只服从该批快照，动画绝不反向改模型。
		for actor_id in batch.snapshot.get("actors", {}):
			var view = _view(actor_id)
			if view != null: view.set_downed(int(batch.snapshot.actors[actor_id].get("hp", 0)) <= 0)
	if generation != _generation: return
	_busy = false
	drained.emit()

func _play_event(event: Dictionary, generation: int, melee_target: Node2D = null) -> void:
	# 接纳后的成本事件立即呈现；第一项实际效果才等原生M，事件数组顺序不变。
	if event.get("type") not in ["command_accepted","resources_changed"]:
		if not await _await_source_impact(generation): return
	var payload: Dictionary = event.get("payload", {})
	var view = _view(str(event.get("target_id", "")))
	var action: StringName = &""
	var approach_elapsed := 0.0
	var view_epoch := -1
	match event.get("type", ""):
		"command_accepted":
			var command: Dictionary = payload.get("command", {})
			var id := str(command.get("command_id", ""))
			if id.is_empty() or _played_commands.has(id): return
			await _finish_attack_recovery(generation)
			if generation != _generation or not is_inside_tree(): return
			_played_commands[id] = true
			view = _view(str(event.get("actor_id", "")))
			view_epoch = _view_epoch(view)
			action = &"defend" if command.get("kind") == "defend" else (&"item" if command.get("kind") == "item" else &"attack")
			if view != null and melee_target != null and view.has_method("begin_melee_approach") and view.begin_melee_approach(melee_target):
				while is_instance_valid(view) and view.is_inside_tree() and view.is_melee_approaching():
					if generation != _generation or not is_inside_tree(): return
					var delta: float = await _frame_tick
					if generation != _generation: return
					if not is_instance_valid(view) or not view.is_inside_tree(): return
					approach_elapsed += delta
					if approach_elapsed >= 0.4:
						view.restore_melee_home()
						visual_warning.emit("近战接近超时，已恢复原站位")
						break
			if is_instance_valid(view) and view_epoch != _view_epoch(view): return
		"damage", "periodic_damage":
			if view != null:
				var absorption: Dictionary = payload.get("absorption", {})
				var loss := int(absorption.get("hp_loss", payload.get("damage", 0)))
				var absorbed := int(absorption.get("absorbed", 0))
				var text := "HP -%d · 盾 -%d" % [loss, absorbed] if absorbed > 0 else "-%d" % loss
				view.show_feedback(text, Color(1.0, 0.48, 0.36))
			event_presented.emit(event)
			action = &"hit"
		"actor_defeated":
			if view != null: view.set_downed(true)
			event_presented.emit(event)
			# down结束后仍保持末帧；只等待播放结束，不等待永不发出的action_finished。
			if view != null: await _wait_for_action(view, generation, view.action_timeout())
			return
		"revived":
			if view != null: view.show_feedback("HP +%d" % int(payload.get("hp", 0)), Color(0.56, 1.0, 0.69))
			event_presented.emit(event)
			action = &"recover"
		"healed", "mp_restored":
			if view != null:
				view.show_feedback("%s +%d" % ["HP" if event.type == "healed" else "MP", int(payload.get("actual", 0))], Color(0.56, 1.0, 0.69))
			event_presented.emit(event)
			return
		_:
			event_presented.emit(event)
			return
	# 呈现信号可能触发换场或取消；旧栈不能在回调返回后重新启动受击。
	if generation != _generation or not is_inside_tree() or not is_instance_valid(view): return
	if not view.play_action(action):
		if view.has_method("restore_melee_home"): view.restore_melee_home()
		visual_warning.emit("角色动作未接受：%s" % action)
		return
	var limit: float = view.action_timeout()
	var impact: float = view.action_impact_time() if action in [&"attack", &"item"] and view.has_method("action_impact_time") else 0.0
	view_epoch = _view_epoch(view)
	if event.get("type") == "command_accepted":
		action_started.emit(event.duplicate(true),{"approach_seconds":approach_elapsed,"native_impact_seconds":impact,"total_impact_delay":approach_elapsed+impact,"action_duration":maxf(0.0,limit-0.35)})
		if generation != _generation or not is_inside_tree() or not is_instance_valid(view): return
		if view_epoch != _view_epoch(view): return
	if impact > 0:
		_attack_recovery = {"view":view,"elapsed":0.0,"limit":limit,"epoch":view_epoch,"impact":impact,"impact_pending":true}
		return
	await _wait_for_action(view, generation, limit)
	if generation == _generation and is_instance_valid(view) and view_epoch == _view_epoch(view) and view.has_method("begin_melee_recovery"):
		view.begin_melee_recovery(0.0)
		await _wait_for_motion(view,generation)

func _await_source_impact(generation: int) -> bool:
	if generation != _generation or not is_inside_tree(): return false
	if _attack_recovery.is_empty() or not _attack_recovery.get("impact_pending",false): return true
	var view = _attack_recovery.view
	var epoch := int(_attack_recovery.epoch)
	while is_instance_valid(view) and view.is_inside_tree() and view.is_action_busy() and float(_attack_recovery.elapsed)<float(_attack_recovery.impact):
		if generation != _generation or epoch != _view_epoch(view): return false
		await _frame_tick
		if generation != _generation: return false
	if not is_instance_valid(view) or epoch != _view_epoch(view): return false
	_attack_recovery.impact_pending=false
	if view.has_method("begin_melee_recovery"):
		view.begin_melee_recovery(maxf(0.0,float(_attack_recovery.limit)-.35-float(_attack_recovery.elapsed)))
	return true

func _finish_attack_recovery(generation: int) -> void:
	if not await _await_source_impact(generation): return
	if generation != _generation or _attack_recovery.is_empty(): return
	var recovery := _attack_recovery
	_attack_recovery = {}
	if not is_instance_valid(recovery.view): return
	if int(recovery.epoch) != _view_epoch(recovery.view): return
	await _wait_for_action(recovery.view, generation, maxf(0.0, recovery.limit - recovery.elapsed))
	if not is_instance_valid(recovery.view) or int(recovery.epoch) != _view_epoch(recovery.view): return
	await _wait_for_motion(recovery.view,generation)

func _wait_for_motion(view: Node, generation: int) -> void:
	var elapsed := 0.0
	var view_epoch := _view_epoch(view)
	while is_instance_valid(view) and view.is_inside_tree() and view.has_method("is_melee_moving") and view.is_melee_moving():
		if generation != _generation or not is_inside_tree(): return
		if view_epoch != _view_epoch(view): return
		if elapsed >= 0.8:
			view.restore_melee_home()
			visual_warning.emit("近战返回等待超时，已恢复原站位")
			return
		var delta: float = await _frame_tick
		if generation != _generation: return
		elapsed += delta

# 只读已提交结果选择接近代表，不调用技能解析器，也不重算或新增任何命中。
func _melee_target(events: Array, start: int) -> Node2D:
	var command_event: Dictionary = events[start]
	if command_event.get("type") != "command_accepted": return null
	var kind := str(command_event.get("payload",{}).get("command",{}).get("kind",""))
	if kind not in ["attack_physical","skill"]: return null
	var source_id := str(command_event.get("actor_id",""))
	var source = _view(source_id)
	if source == null or not source.has_method("supports_melee_approach") or not source.supports_melee_approach(): return null
	for index in range(start+1,events.size()):
		var event: Dictionary = events[index]
		if event.get("type") == "command_accepted": break
		if event.get("type") != "damage" or event.get("actor_id") != source_id: continue
		if event.get("payload",{}).get("factors",{}).get("damage_type","") != "physical": continue
		var target = _view(str(event.get("target_id","")))
		if target == source or target == null or (target.has_method("is_downed") and target.is_downed()): continue
		return target as Node2D
	return null

func _wait_for_action(view: Node, generation: int, limit: float) -> void:
	var elapsed := 0.0
	var view_epoch := _view_epoch(view)
	while is_instance_valid(view) and view.is_inside_tree() and view.is_action_busy():
		if generation != _generation or not is_inside_tree(): return
		if view_epoch != _view_epoch(view): return
		if elapsed >= limit:
			view.cancel_action()
			visual_warning.emit("角色动作等待超时，已安全结束表现")
			return
		var delta: float = await _frame_tick
		if generation != _generation: return
		elapsed += delta

func _view(actor_id: String) -> Variant:
	var view = _views.get(actor_id)
	return view if is_instance_valid(view) and view.is_inside_tree() else null

func _view_epoch(view: Variant) -> int:
	return int(view.presentation_generation()) if is_instance_valid(view) and view.has_method("presentation_generation") else -1
