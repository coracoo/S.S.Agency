# 神经图只由Godot播放/位移/旋转/缩放/淡出；不画程序几何，也不驱动规则结算。
extends Node2D
const Manifests = preload("res://scripts/rpg/ui/imagegen_effect_manifest.gd")
const EventPolicy = preload("res://scripts/rpg/ui/skill_visual_event_policy.gd")
const MAX_TRANSIENTS := 48
const MAX_STATES := 96
const MAX_TEXTURE_BYTES := 64*1024*1024 # 十二套实际RGBA共45MiB；按需加载，不预载全套。
const STATUS_ART := {"burn":"burn_brand","slow":"ice_arrow"}
var preview_pending_art := false
var registry_path := Manifests.REGISTRY
var _definitions: Dictionary = {}
var _actions: Dictionary = {}
var _bursts: Array[Dictionary] = []
var _states: Dictionary = {}
var _positions: Dictionary = {}
var _cast_origins: Dictionary = {}
var _ground_positions: Dictionary = {}
var _layer_visuals: Dictionary = {}
var _event_policy := EventPolicy.new()
var _current_battle := ""
var _retired_battles:Dictionary = {}
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
	if battle_id.is_empty() or _retired_battles.has(battle_id) or (not _current_battle.is_empty() and _current_battle!=battle_id):return false
	var key := _key(context,battle_id)
	if key.is_empty() or _started.has(key) or _cancelled.has(key): return false
	var skill := str(context.get("ability_id",""))
	var impact := float(context.get("impact_delay",0))
	var duration := float(context.get("action_duration",0))
	if not is_finite(impact) or impact<=0 or not is_finite(duration) or duration<=impact: return false
	var effect := _definition(skill)
	if effect.is_empty(): return false
	var source_id := str(context.get("source_id",""))
	var layered:bool=not effect.get("event_layers",{}).is_empty()
	# 纯策略拒绝时不能先创建cast或占用命令去重；刚解码但无人使用的页立即释放。
	if layered and not _event_policy.begin_action(context,battle_id,effect.event_layers):
		_release_unused();return false
	_current_battle=battle_id
	_remember(_started,key)
	if not _positions.has(source_id):_positions[source_id]=source
	_actions[key]={"elapsed":0.0,"duration":duration,"skill":skill,"source_id":source_id,"context":context.duplicate(true),"battle_id":battle_id,"layered":layered}
	# 阶段只按原生命中窗重定标；到M也绝不自行创建hit。
	var launch := float(context.get("launch_seconds",impact*.55))
	if not is_finite(launch) or launch<=0 or launch>=impact:launch=impact*.55
	var cast_scale:=float(context.get("cast_scale",1.0))
	if not is_finite(cast_scale) or cast_scale<=0 or cast_scale>1:cast_scale=1.0
	_add({"key":key,"skill":skill,"phase":"cast","source_id":source_id,"target_id":source_id,"source":source,"target":source,"elapsed":0.0,"start":0.0,"end":launch,"presentation_scale":cast_scale})
	var valid_targets: Array[String] = []
	for target_id in targets:
		if targets[target_id] is Vector2:
			_positions[str(target_id)]=targets[target_id]
			# 封缄的真实MP返还目标也是来源，但不能为该补层额外发一条朝自己的飞弹。
			if layered and not context.get("target_ids",[]).is_empty() and not context.target_ids.has(target_id):continue
			valid_targets.append(str(target_id))
	if skill=="flame_wave" and valid_targets.size()>1:
		# 一个群体波前向最远实际目标推进，局部命中仍由各自真实事件产生。
		_add({"key":key,"skill":skill,"phase":"travel","source_id":source_id,"target_id":"__group__","group_targets":valid_targets,"source":source,"target":targets[valid_targets[0]],"elapsed":0.0,"start":launch,"end":impact})
	else:
		for target_id in valid_targets:
			_add({"key":key,"skill":skill,"phase":"travel","source_id":source_id,"target_id":target_id,"source":source,"target":targets[target_id],"elapsed":0.0,"start":launch,"end":impact,"placement":effect.get("placement",{}).get("travel_target","target_body"),"travel_mode":effect.get("placement",{}).get("travel_mode","projectile")})
	queue_redraw()
	return true

func present_event(event: Dictionary,_form: String,source: Vector2,target: Vector2,battle_id: String,context: Dictionary={}) -> bool:
	if not _enabled(): return false
	if battle_id.is_empty() or _retired_battles.has(battle_id) or battle_id!=_current_battle:return false
	var key := _key(context,battle_id)
	var kind := str(event.get("type",""))
	if _cancelled.has(key) and kind not in ["status_tick","shield_tick","status_removed","shield_removed","damage","periodic_damage","saga_reflected","actor_defeated","revived","outcome"]:return false
	var id := str(event.get("target_id",""))
	var payload: Dictionary = event.get("payload",{})
	var seen_key := "%s:%s:%s:%s:%s" % [battle_id,event.get("sequence",0),kind,event.get("actor_id",""),id]
	if _seen.has(seen_key): return false
	_remember(_seen,seen_key)
	_positions[id]=target
	var state_key := id+":"
	var shown := false
	var layer_intents:Array[Dictionary]=_event_policy.consume(event,context,battle_id)
	_apply_layer_intents(layer_intents,_actions.get(key,{}))
	shown=not layer_intents.is_empty()
	var managed:bool=str(context.get("ability_id","")) in EventPolicy.ABILITIES
	if managed and kind in ["damage","healed","shield_applied","shield_refreshed","status_applied","status_refreshed","status_removed","charge_interrupted","effect_ignored"]:_finish_flight(key,id)
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
			_bursts=_bursts.filter(func(burst):return burst.target_id!=id or burst.phase=="hit")
		"status_removed":
			_states.erase(state_key+str(payload.get("status",{}).get("id","")))
		"shield_removed": _states.erase(state_key+"shield")
		"shield_applied","shield_refreshed","shield_tick":
			var shield: Dictionary = payload.get("shield",payload.get("after",{}))
			if int(shield.get("amount",0))>0 and not managed and not _has_layer_state(id,"shield"): _state(id,"shield",shield,key,target)
			else: _states.erase(state_key+"shield")
		"status_applied","status_refreshed","status_tick":
			var status: Dictionary = payload.get("status",payload.get("after",{}))
			var status_id := str(status.get("id",""))
			if not status_id.is_empty():
				if managed:_states.erase(state_key+status_id)
				elif kind=="status_tick" and _states.has(state_key+status_id):_states[state_key+status_id].value=status.duplicate(true)
				elif kind!="status_tick":shown=_state(id,status_id,status,key,target,str(context.get("ability_id",""))) or shown
		"effect_ignored": _finish_flight(key,id)
		"periodic_damage":
			# 只增强已经存在的燃烧图层；周期事件不意味着新的施法/火弹/暴击。
			if _states.has(state_key+"burn"): _states[state_key+"burn"].pulse=.15
		"damage","saga_reflected":
			_finish_flight(key,id)
			var hit_key := key+":"+id
			if _actions.has(key) and not _actions[key].get("layered",false) and not _hits.has(hit_key):
				var action: Dictionary = _actions[key]
				var remaining := maxf(0.0,float(action.duration)-float(action.elapsed))
				if remaining>0:
					_remember(_hits,hit_key)
					_add({"key":key,"skill":action.skill,"phase":"hit","source_id":str(event.get("actor_id","")),"target_id":id,"source":source,"target":target,"elapsed":0.0,"start":0.0,"end":remaining})
					shown=true
		"healed","mp_restored":
			if int(payload.get("actual",0))>0 and not managed: _missing["heal_gain" if kind=="healed" else "mp_gain"]="unregistered_feedback_art"
		"saga_cancelled": cancel_action(context,battle_id)
		"outcome":clear()
	_release_unused()
	queue_redraw()
	return shown

func _state(id: String,status: String,value: Dictionary,key: String,target: Vector2,origin_ability:String="") -> bool:
	var mage_art:bool=(status=="burn" and origin_ability in ["firebolt","flame_wave","burn_brand"]) or (status=="slow" and origin_ability=="ice_arrow")
	var skill := str(STATUS_ART.get(status,"")) if mage_art else ""
	if skill.is_empty(): _missing[status]="unregistered_status_art"
	elif _definition(skill).get("phases",{}).get("status",[]).is_empty(): skill=""
	var state_key := id+":"+status
	if not _states.has(state_key) and _states.size()>=MAX_STATES: _states.erase(_states.keys()[0])
	_states[state_key]={"key":key,"target_id":id,"status":status,"value":value.duplicate(true),"skill":skill,"origin_ability":origin_ability,"elapsed":0.0,"target":target,"pulse":0.0}
	return not skill.is_empty()
func _add(burst: Dictionary) -> void:
	if _bursts.size()>=MAX_TRANSIENTS: _bursts.pop_front()
	_bursts.append(burst)
func _finish_flight(key: String,target_id: String) -> void:
	_bursts=_bursts.filter(func(burst):return not (burst.key==key and burst.phase=="travel" and (burst.target_id==target_id or burst.get("group_targets",[]).has(target_id))))
func cancel_action(context: Dictionary,battle_id: String) -> void:
	var key := _key(context,battle_id)
	if key.is_empty(): return
	_remember(_cancelled,key)
	finish_action(context,battle_id)
	# 演出取消不撤销已提交的持续状态；整场退出由clear统一释放。
	_release_unused()
func finish_action(context: Dictionary,battle_id: String) -> void:
	var key := _key(context,battle_id)
	_apply_layer_intents(_event_policy.finish_action(context,battle_id))
	_actions.erase(key)
	_bursts=_bursts.filter(func(burst):return burst.key!=key)
	_release_unused()
	queue_redraw()
func update_positions(positions: Dictionary,cast_origins: Dictionary={}) -> void:
	_positions=positions.duplicate()
	_cast_origins=cast_origins.duplicate()
	queue_redraw()
func update_ground_positions(positions:Dictionary)->void:
	_ground_positions=positions.duplicate();queue_redraw()
func requires_source_attachment() -> bool: return true
func record_missing(key: String,reason: String) -> void: _missing[key]=reason
func _release_unused() -> void:
	var needed := {}
	for action in _actions.values(): needed[action.skill]=true
	for burst in _bursts: needed[burst.skill]=true
	for state in _states.values():
		if not state.skill.is_empty(): needed[state.skill]=true
	for layer in _layer_visuals.values():needed[layer.ability_id]=true
	for skill in _definitions.keys():
		if not needed.has(skill): _definitions.erase(skill)
func _process(delta: float) -> void:
	if not is_finite(delta) or delta<0: return
	for key in _actions.keys():
		_actions[key].elapsed+=delta
		if float(_actions[key].elapsed)>=float(_actions[key].duration)-.000001:
			var ending:Dictionary=_actions[key];finish_action(ending.context,ending.battle_id)
	for burst in _bursts: burst.elapsed+=delta
	_bursts=_bursts.filter(func(burst):return float(burst.elapsed)<float(burst.end)-.000001)
	for state in _states.values():
		state.elapsed+=delta;state.pulse=maxf(0,float(state.pulse)-delta)
	for layer in _layer_visuals.values():layer.elapsed+=delta
	_release_unused()
	queue_redraw()
# 与实际draw_texture共享的采样：起手跟掌，投射物在首次发射绘制时固定其起点。
func sample_burst(burst: Dictionary) -> Dictionary:
	if float(burst.elapsed)<float(burst.start) or not _definitions.has(burst.skill): return {}
	var progress := clampf((float(burst.elapsed)-float(burst.start))/maxf(.001,float(burst.end)-float(burst.start)),0,1)
	var frame := Manifests.phase_frame(_definitions[burst.skill],burst.phase,progress)
	if frame.is_empty(): return {}
	var source: Vector2 = _cast_origins.get(burst.source_id,burst.source)
	var target: Vector2 = _layer_position(str(burst.target_id),str(burst.get("placement","target_body")),burst.target)
	var position := source if burst.phase=="cast" else target
	var angle := 0.0
	var alpha := 1.0
	var stretch := Vector2.ONE
	if burst.phase=="travel":
		if burst.get("travel_mode","")=="target_drop":source=_positions.get(burst.target_id,target)*2.0-_ground_positions.get(burst.target_id,target)
		if not burst.get("launched",false): burst.source=source;burst.launched=true
		source=burst.source
		if burst.has("group_targets"):
			if not burst.has("group_leader"):
				var distance := -1.0
				for id in burst.group_targets:
					var point: Vector2 = _positions.get(id,burst.target)
					if source.distance_squared_to(point)>distance: distance=source.distance_squared_to(point);burst.group_leader=id
			target=_positions.get(burst.group_leader,burst.target)
			var axis := (target-source).normalized()
			var low := INF;var high := -INF
			for id in burst.group_targets:
				var point: Vector2 = _positions.get(id,burst.target)
				var projected := point.dot(axis);low=minf(low,projected);high=maxf(high,projected)
			var width := float(_definitions[burst.skill].display_size)
			stretch.x=lerpf(1.0,clampf(1.0+(high-low)/width,1.0,3.0),progress)
		position=source.lerp(target,progress);angle=0.0 if burst.get("travel_mode","")=="target_drop" else (target-source).angle()
	if burst.phase=="cast": alpha=1.0-smoothstep(.8,1.0,progress)
	if burst.phase=="hit": alpha=1.0-smoothstep(.6,1.0,progress)
	return {"frame":frame,"position":position,"angle":angle,"scale":float(frame.scale)*float(burst.get("presentation_scale",1.0)),"stretch":stretch,"alpha":alpha}

func _draw() -> void:
	_drawn.clear()
	for burst in _bursts:
		var sample := sample_burst(burst)
		if sample.is_empty(): continue
		_paint(sample.frame,sample.position,sample.angle,sample.scale,sample.alpha,str(burst.skill),sample.stretch)
	for state in _states.values():
		if not _definitions.has(state.skill): continue
		var progress := fposmod(float(state.elapsed),1.4)/1.4
		var frame := Manifests.phase_frame(_definitions[state.skill],"status",progress)
		if frame.is_empty(): continue
		_paint(frame,_positions.get(state.target_id,state.target),0,float(frame.scale)*.6,.7 if state.pulse<=0 else 1.0,str(state.skill))
	for layer in _layer_visuals.values():
		var sample:Dictionary=_sample_layer(layer)
		if not sample.is_empty():_paint(sample.frame,sample.position,0,sample.scale,sample.alpha,str(layer.ability_id))
	draw_set_transform(Vector2.ZERO)
func _paint(frame: Dictionary,position: Vector2,angle: float,scale: float,alpha: float,skill: String,stretch: Vector2=Vector2.ONE) -> void:
	draw_set_transform(position,angle,stretch*scale)
	draw_texture(frame.texture,-frame.anchor,Color(1,1,1,alpha))
	_drawn.append({"skill":skill,"phase":frame.phase,"frame":frame.frame,"position":[position.x,position.y],"anchor":[frame.anchor.x,frame.anchor.y],"angle":angle,"scale":scale,"stretch":[stretch.x,stretch.y],"alpha":alpha,"atlas_sha256":_definitions[skill].atlas_sha256})
func draw_snapshot() -> Array[Dictionary]: return _drawn.duplicate(true)
func active_count() -> int: return _bursts.size()+_states.values().filter(func(state):return not state.skill.is_empty()).size()+_layer_visuals.size()
func hit_count() -> int: return _bursts.filter(func(burst):return burst.phase=="hit").size()
func status_count() -> int: return _states.values().filter(func(state):return not state.skill.is_empty()).size()+_layer_visuals.values().filter(func(layer):return layer.lifetime!="action").size()
func state_count() -> int: return _states.size()+_layer_visuals.values().filter(func(layer):return layer.lifetime!="action").size()
func action_count() -> int: return _actions.size()
func missing_art() -> Dictionary: return _missing.duplicate()
func texture_memory_bytes() -> int:
	var total:=0
	for effect in _definitions.values(): total+=int(effect.texture_bytes)
	return total
func clear() -> void:
	if not _current_battle.is_empty():_remember(_retired_battles,_current_battle)
	_current_battle=""
	_event_policy.clear();_layer_visuals.clear();_ground_positions.clear()
	_definitions.clear();_actions.clear();_bursts.clear();_states.clear();_positions.clear();_cast_origins.clear();_seen.clear();_started.clear();_cancelled.clear();_hits.clear();_missing.clear();_drawn.clear()
	queue_redraw()
func _exit_tree() -> void: clear()

# 纯policy只发意图；此处拥有图集与播放时钟。tick不重置循环或改回Mage通用图。
func _apply_layer_intents(intents:Array[Dictionary],action:Dictionary={})->void:
	for intent in intents:
		var key:=str(intent.layer_key)
		if intent.op=="remove":_layer_visuals.erase(key);continue
		if intent.op=="update" and not _layer_visuals.has(key):continue
		var effect:Dictionary=_definition(str(intent.ability_id))
		if effect.is_empty() or not effect.phases.has(intent.phase):continue
		var previous:Dictionary=_layer_visuals.get(key,{})
		var layer:Dictionary=intent.duplicate(true)
		layer["elapsed"]=float(previous.get("elapsed",0)) if intent.op=="update" else 0.0
		layer["activation_duration"]=float(previous.get("activation_duration",0)) if intent.op=="update" else maxf(.001,float(action.get("duration",0))-float(action.get("elapsed",0)))
		if intent.op=="update" and not previous.get("activation_frames",[]).is_empty() and intent.activation_frames.is_empty():layer.elapsed=0.0;layer.activation_duration=0.0
		_layer_visuals[key]=layer
func _has_layer_state(target:String,status:String)->bool:
	return _layer_visuals.values().any(func(layer):return layer.target_id==target and layer.status_id==status and layer.lifetime!="action")
func _layer_position(id:String,placement:String,fallback:Vector2=Vector2.ZERO)->Vector2:
	return _ground_positions.get(id,_positions.get(id,fallback)) if placement=="target_ground" else _positions.get(id,fallback)
func _sample_layer(layer:Dictionary)->Dictionary:
	if not _definitions.has(layer.ability_id):return {}
	var effect:Dictionary=_definitions[layer.ability_id]
	var ids:Array=layer.activation_frames
	var progress:=float(layer.elapsed)/maxf(.001,float(layer.activation_duration))
	var alpha:=1.0
	if layer.lifetime!="action" and (ids.is_empty() or progress>=1.0):
		ids=layer.loop_frames
		var seconds:=0.0
		for id in ids:seconds+=float(effect.frames[int(id)].duration_ms)/1000.0
		var period:=maxf(1.2,seconds)
		progress=fposmod(maxf(0,float(layer.elapsed)-float(layer.activation_duration)),period)/period
		alpha=.7
	elif layer.lifetime=="action":alpha=1.0-smoothstep(.65,1.0,progress)
	var frame:Dictionary=Manifests.phase_frame({"frames":effect.frames,"phases":{str(layer.phase):ids}},str(layer.phase),progress)
	if frame.is_empty():return {}
	return {"frame":frame,"position":_layer_position(str(layer.target_id),str(layer.placement)),"scale":float(frame.scale),"alpha":alpha}
func layer_snapshot()->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for layer in _layer_visuals.values():
		var sample:Dictionary=_sample_layer(layer)
		var row:Dictionary=layer.duplicate(true)
		row["position"]=_layer_position(str(layer.target_id),str(layer.placement))
		row["frame"]=int(sample.frame.frame) if not sample.is_empty() else -1
		result.append(row)
	return result
