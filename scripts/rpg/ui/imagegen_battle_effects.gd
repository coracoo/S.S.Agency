# 神经图只由Godot播放/位移/旋转/缩放/淡出；不画程序几何，也不驱动规则结算。
extends Node2D
const Manifests = preload("res://scripts/rpg/ui/imagegen_effect_manifest.gd")
const MAX_TRANSIENTS := 48
const MAX_STATES := 96
const MAX_TEXTURE_BYTES := 32*1024*1024
const STATUS_ART := {"burn":"burn_brand","slow":"ice_arrow"}
var preview_pending_art := false
var registry_path := Manifests.REGISTRY
var _definitions: Dictionary = {}
var _actions: Dictionary = {}
var _bursts: Array[Dictionary] = []
var _states: Dictionary = {}
var _positions: Dictionary = {}
var _cast_origins: Dictionary = {}
var _seen: Dictionary = {}
var _started: Dictionary = {}
var _cancelled: Dictionary = {}
var _hits: Dictionary = {}
var _missing: Dictionary = {}
var _drawn: Array[Dictionary] = []

func production_enabled() -> bool:
	return Manifests._true(Manifests._json(registry_path).get("production_renderer_enabled"))
func _enabled() -> bool: return preview_pending_art or production_enabled()
func _key(context: Dictionary,battle: String) -> String:
	var command := str(context.get("command_id",""))
	return "" if command.is_empty() else battle+":"+command
func _remember(memory: Dictionary,key: String) -> void:
	memory[key]=true
	if memory.size()>512: memory.erase(memory.keys()[0])
func _definition(skill: String) -> Dictionary:
	if _definitions.has(skill): return _definitions[skill]
	var effect := Manifests.load_effect(skill,registry_path,preview_pending_art)
	if not effect.ok:
		_missing[skill]=effect.reason
		return {}
	if texture_memory_bytes()+int(effect.texture_bytes)>MAX_TEXTURE_BYTES:
		_missing[skill]="texture_budget"
		return {}
	_definitions[skill]=effect
	return effect

func present_action(context: Dictionary,_form: String,source: Vector2,targets: Dictionary,battle_id: String) -> bool:
	if not _enabled() or context.get("kind")!="skill" or targets.is_empty(): return false
	var key := _key(context,battle_id)
	if key.is_empty() or _started.has(key) or _cancelled.has(key): return false
	var skill := str(context.get("ability_id",""))
	var impact := float(context.get("impact_delay",0))
	var duration := float(context.get("action_duration",0))
	if not is_finite(impact) or impact<=0 or not is_finite(duration) or duration<=impact: return false
	var effect := _definition(skill)
	if effect.is_empty(): return false
	_remember(_started,key)
	var source_id := str(context.get("source_id",""))
	_positions[source_id]=source
	_actions[key]={"elapsed":0.0,"duration":duration,"skill":skill,"source_id":source_id}
	# 阶段只按原生命中窗重定标；到M也绝不自行创建hit。
	var launch := impact*.55
	_add({"key":key,"skill":skill,"phase":"cast","source_id":source_id,"target_id":source_id,"source":source,"target":source,"elapsed":0.0,"start":0.0,"end":launch})
	for target_id in targets:
		if not targets[target_id] is Vector2: continue
		_positions[str(target_id)]=targets[target_id]
		_add({"key":key,"skill":skill,"phase":"travel","source_id":source_id,"target_id":str(target_id),"source":source,"target":targets[target_id],"elapsed":0.0,"start":launch,"end":impact})
	queue_redraw()
	return true

func present_event(event: Dictionary,_form: String,source: Vector2,target: Vector2,battle_id: String,context: Dictionary={}) -> bool:
	if not _enabled(): return false
	var key := _key(context,battle_id)
	if _cancelled.has(key): return false
	var kind := str(event.get("type",""))
	var id := str(event.get("target_id",""))
	var payload: Dictionary = event.get("payload",{})
	var seen_key := "%s:%s:%s:%s:%s" % [battle_id,event.get("sequence",0),kind,event.get("actor_id",""),id]
	if _seen.has(seen_key): return false
	_remember(_seen,seen_key)
	_positions[id]=target
	var state_key := id+":"
	var shown := false
	# 护盾耗尽可能没有shield_removed；真实伤害/周期/反射均须读取吸收结果。
	if kind in ["damage","periodic_damage","saga_reflected"]:
		var absorption: Dictionary = payload.get("absorption",{})
		if absorption.has("shield_after"):
			var after: Dictionary = absorption.get("shield_after",{})
			if after.is_empty() or int(after.get("amount",0))<=0: _states.erase(state_key+"shield")
			elif _states.has(state_key+"shield"): _states[state_key+"shield"].value=after.duplicate(true)
		for removed in absorption.get("removed_statuses",[]):
			_states.erase(state_key+str(removed.get("id","") if removed is Dictionary else removed))
	match kind:
		"actor_defeated":
			for entry in _states.keys():
				if _states[entry].target_id==id: _states.erase(entry)
			_bursts=_bursts.filter(func(burst):return burst.target_id!=id)
		"status_removed":
			_states.erase(state_key+str(payload.get("status",{}).get("id","")))
		"shield_removed": _states.erase(state_key+"shield")
		"shield_applied","shield_refreshed","shield_tick":
			var shield: Dictionary = payload.get("shield",payload.get("after",{}))
			if int(shield.get("amount",0))>0: _state(id,"shield",shield,key,target)
			else: _states.erase(state_key+"shield")
		"status_applied","status_refreshed","status_tick":
			var status: Dictionary = payload.get("status",payload.get("after",{}))
			var status_id := str(status.get("id",""))
			if not status_id.is_empty(): shown=_state(id,status_id,status,key,target)
		"effect_ignored": _finish_flight(key,id)
		"periodic_damage":
			# 只增强已经存在的燃烧图层；周期事件不意味着新的施法/火弹/暴击。
			if _states.has(state_key+"burn"): _states[state_key+"burn"].pulse=.15
		"damage","saga_reflected":
			_finish_flight(key,id)
			var hit_key := key+":"+id
			if _actions.has(key) and not _hits.has(hit_key):
				var action: Dictionary = _actions[key]
				var remaining := maxf(0.0,float(action.duration)-float(action.elapsed))
				if remaining>0:
					_remember(_hits,hit_key)
					_add({"key":key,"skill":action.skill,"phase":"hit","source_id":str(event.get("actor_id","")),"target_id":id,"source":source,"target":target,"elapsed":0.0,"start":0.0,"end":remaining})
					shown=true
		"healed","mp_restored":
			if int(payload.get("actual",0))>0: _missing["heal_gain" if kind=="healed" else "mp_gain"]="unregistered_feedback_art"
		"saga_cancelled": cancel_action(context,battle_id)
	_release_unused()
	queue_redraw()
	return shown

func _state(id: String,status: String,value: Dictionary,key: String,target: Vector2) -> bool:
	var skill := str(STATUS_ART.get(status,""))
	if skill.is_empty(): _missing[status]="unregistered_status_art"
	elif _definition(skill).get("phases",{}).get("status",[]).is_empty(): skill=""
	var state_key := id+":"+status
	if not _states.has(state_key) and _states.size()>=MAX_STATES: _states.erase(_states.keys()[0])
	_states[state_key]={"key":key,"target_id":id,"status":status,"value":value.duplicate(true),"skill":skill,"elapsed":0.0,"target":target,"pulse":0.0}
	return not skill.is_empty()
func _add(burst: Dictionary) -> void:
	if _bursts.size()>=MAX_TRANSIENTS: _bursts.pop_front()
	_bursts.append(burst)
func _finish_flight(key: String,target_id: String) -> void:
	_bursts=_bursts.filter(func(burst):return not (burst.key==key and burst.phase=="travel" and burst.target_id==target_id))
func cancel_action(context: Dictionary,battle_id: String) -> void:
	var key := _key(context,battle_id)
	if key.is_empty(): return
	_remember(_cancelled,key)
	finish_action(context,battle_id)
	for id in _states.keys():
		if _states[id].key==key: _states.erase(id)
	_release_unused()
func finish_action(context: Dictionary,battle_id: String) -> void:
	var key := _key(context,battle_id)
	_actions.erase(key)
	_bursts=_bursts.filter(func(burst):return burst.key!=key)
	_release_unused()
	queue_redraw()
func update_positions(positions: Dictionary,cast_origins: Dictionary={}) -> void:
	_positions=positions.duplicate()
	_cast_origins=cast_origins.duplicate()
	queue_redraw()
func requires_source_attachment() -> bool: return true
func record_missing(key: String,reason: String) -> void: _missing[key]=reason
func _release_unused() -> void:
	var needed := {}
	for action in _actions.values(): needed[action.skill]=true
	for burst in _bursts: needed[burst.skill]=true
	for state in _states.values():
		if not state.skill.is_empty(): needed[state.skill]=true
	for skill in _definitions.keys():
		if not needed.has(skill): _definitions.erase(skill)
func _process(delta: float) -> void:
	if not is_finite(delta) or delta<0: return
	for key in _actions.keys():
		_actions[key].elapsed+=delta
		if float(_actions[key].elapsed)>=float(_actions[key].duration)-.000001: _actions.erase(key)
	for burst in _bursts: burst.elapsed+=delta
	_bursts=_bursts.filter(func(burst):return float(burst.elapsed)<float(burst.end)-.000001)
	for state in _states.values():
		state.elapsed+=delta;state.pulse=maxf(0,float(state.pulse)-delta)
	_release_unused()
	queue_redraw()
# 与实际draw_texture共享的采样：起手跟掌，投射物在首次发射绘制时固定其起点。
func sample_burst(burst: Dictionary) -> Dictionary:
	if float(burst.elapsed)<float(burst.start) or not _definitions.has(burst.skill): return {}
	var progress := clampf((float(burst.elapsed)-float(burst.start))/maxf(.001,float(burst.end)-float(burst.start)),0,1)
	var frame := Manifests.phase_frame(_definitions[burst.skill],burst.phase,progress)
	if frame.is_empty(): return {}
	var source: Vector2 = _cast_origins.get(burst.source_id,burst.source)
	var target: Vector2 = _positions.get(burst.target_id,burst.target)
	var position := source if burst.phase=="cast" else target
	var angle := 0.0
	var alpha := 1.0
	if burst.phase=="travel":
		if not burst.get("launched",false): burst.source=source;burst.launched=true
		source=burst.source
		position=source.lerp(target,progress);angle=(target-source).angle()
	if burst.phase=="cast": alpha=1.0-smoothstep(.8,1.0,progress)
	if burst.phase=="hit": alpha=1.0-smoothstep(.6,1.0,progress)
	return {"frame":frame,"position":position,"angle":angle,"scale":float(frame.scale),"alpha":alpha}

func _draw() -> void:
	_drawn.clear()
	for burst in _bursts:
		var sample := sample_burst(burst)
		if sample.is_empty(): continue
		_paint(sample.frame,sample.position,sample.angle,sample.scale,sample.alpha,str(burst.skill))
	for state in _states.values():
		if not _definitions.has(state.skill): continue
		var progress := fposmod(float(state.elapsed),1.4)/1.4
		var frame := Manifests.phase_frame(_definitions[state.skill],"status",progress)
		if frame.is_empty(): continue
		_paint(frame,_positions.get(state.target_id,state.target),0,float(frame.scale)*.6,.7 if state.pulse<=0 else 1.0,str(state.skill))
	draw_set_transform(Vector2.ZERO)
func _paint(frame: Dictionary,position: Vector2,angle: float,scale: float,alpha: float,skill: String) -> void:
	draw_set_transform(position,angle,Vector2.ONE*scale)
	draw_texture(frame.texture,-frame.anchor,Color(1,1,1,alpha))
	_drawn.append({"skill":skill,"phase":frame.phase,"frame":frame.frame,"position":[position.x,position.y],"anchor":[frame.anchor.x,frame.anchor.y],"angle":angle,"scale":scale,"alpha":alpha,"atlas_sha256":_definitions[skill].atlas_sha256})
func draw_snapshot() -> Array[Dictionary]: return _drawn.duplicate(true)
func active_count() -> int: return _bursts.size()+status_count()
func hit_count() -> int: return _bursts.filter(func(burst):return burst.phase=="hit").size()
func status_count() -> int: return _states.values().filter(func(state):return not state.skill.is_empty()).size()
func state_count() -> int: return _states.size()
func action_count() -> int: return _actions.size()
func missing_art() -> Dictionary: return _missing.duplicate()
func texture_memory_bytes() -> int:
	var total:=0
	for effect in _definitions.values(): total+=int(effect.texture_bytes)
	return total
func clear() -> void:
	_definitions.clear();_actions.clear();_bursts.clear();_states.clear();_positions.clear();_cast_origins.clear();_seen.clear();_started.clear();_cancelled.clear();_hits.clear();_missing.clear();_drawn.clear()
	queue_redraw()
func _exit_tree() -> void: clear()
