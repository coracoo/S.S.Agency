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
var _parallel_scope: Dictionary = {}
var _target_reactions: Dictionary = {}
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
	_parallel_scope.clear()
	_target_reactions.clear()
	_busy = false
	# 先唤醒当前代次的等待栈，让嵌套协程在节点释放前同步返回。
	_frame_tick.emit(0.0)
	for view in _views.values():
		if is_instance_valid(view): view.cancel_action()
	cancelled.emit()

func _process(delta: float) -> void:
	_step_target_reactions(delta)
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
			if event.get("type")=="command_accepted": _parallel_scope=_direct_impact_scope(batch.events,index)
			await _play_event(event, generation, _melee_target(batch.events,index))
		# 全重复批次连同它的旧快照都忽略，避免重试旧致死包覆盖后来的复苏。
		if not has_new_events: continue
		# 伤害已在命中点显示，来源仍须完整收招后才同步快照或解锁下一批。
		await _finish_attack_recovery(generation)
		await _wait_target_reactions(generation)
		_parallel_scope.clear()
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
	var target_id := str(event.get("target_id",""))
	if event.get("type") in ["periodic_damage","saga_reflected"]: await _wait_target_reactions(generation)
	elif event.get("type") in ["damage","revived"]: await _wait_target_reactions(generation,target_id)
	if generation != _generation: return
	var payload: Dictionary = event.get("payload", {})
	var view = _view(str(event.get("target_id", "")))
	var action: StringName = &""
	var approach_elapsed := 0.0
	var view_epoch := _view_epoch(view)
	match event.get("type", ""):
		"command_accepted":
			var command: Dictionary = payload.get("command", {})
			var id := str(command.get("command_id", ""))
			if id.is_empty() or _played_commands.has(id): return
			await _finish_attack_recovery(generation)
			await _wait_target_reactions(generation)
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
			if view != null and _target_reactions.has(target_id) and view.has_method("set_downed_after_hit"):
				view.set_downed_after_hit()
				if generation != _generation: return
				_target_reactions[target_id].epoch=_view_epoch(view)
				event_presented.emit(event)
				return
			if view != null: view.set_downed(true)
			if generation != _generation: return
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
	# 呈现信号可能触发换场、取消或目标重绑；旧栈不能覆盖新的目标姿态。
	if generation != _generation or not is_inside_tree() or not is_instance_valid(view): return
	if view_epoch != _view_epoch(view): return
	if not view.play_action(action):
		if view.has_method("restore_melee_home"): view.restore_melee_home()
		visual_warning.emit("角色动作未接受：%s" % action)
		return
	if event.get("type")=="damage" and _parallel_scope.get("source_id","")==str(event.get("actor_id","")) and _parallel_scope.get("targets",{}).has(target_id):
		_target_reactions[target_id]={"view":view,"epoch":_view_epoch(view),"elapsed":0.0,"limit":view.action_timeout(),"action":"hit"}
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

# 只并行每个目标恰好一次的直接伤害；多击/周期/反射命令继续原串行边界。
func _direct_impact_scope(events: Array,start: int) -> Dictionary:
	var source := str(events[start].get("actor_id",""))
	var targets := {}
	for index in range(start+1,events.size()):
		var event: Dictionary = events[index]
		if event.get("type")=="command_accepted": break
		if event.get("type") in ["periodic_damage","saga_reflected"]: return {}
		if event.get("type")!="damage" or str(event.get("actor_id",""))!=source: continue
		var id := str(event.get("target_id",""))
		if id==source or targets.has(id): return {}
		targets[id]=true
	return {"source_id":source,"targets":targets} if targets.size()>1 else {}

func _step_target_reactions(delta: float) -> void:
	for id in _target_reactions.keys():
		if not _target_reactions.has(id): continue
		var reaction: Dictionary = _target_reactions[id]
		var view = reaction.view
		if not is_instance_valid(view) or not view.is_inside_tree() or int(reaction.epoch)!=_view_epoch(view):
			_target_reactions.erase(id);continue
		if not view.is_action_busy(): _target_reactions.erase(id);continue
		var animator = view.get("animator")
		var action := str(animator.sprite.animation) if animator!=null else str(view.get("_action"))
		if action!=reaction.action:
			reaction.action=action;reaction.elapsed=0.0;reaction.limit=view.action_timeout()
		reaction.elapsed+=delta
		if float(reaction.elapsed)>=float(reaction.limit):
			view.cancel_action();_target_reactions.erase(id)
			visual_warning.emit("目标反应等待超时，已安全停止该反应")

func _wait_target_reactions(generation: int,target: String="") -> void:
	while not _target_reactions.is_empty() and (target.is_empty() or _target_reactions.has(target)):
		if generation!=_generation or not is_inside_tree(): return
		await _frame_tick
		if generation!=_generation: return

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
