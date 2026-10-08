# 实地机关纯规则：只提交动作与位置证据；不播放剧情、不发物、不改剧情flag。
class_name CampaignMechanismRules
extends RefCounted
const DATA_PATH := "res://data/campaign/mechanisms.json"
const STORY_PATH := "res://data/campaign/saga.json"
const IDS := ["water_echo","ferry","junction","ward_test","driftwood","alley"]
const STATE_FIELDS := ["step","complete","first_actor"]
const HISTORY_FIELDS := ["mechanism_id","action_id","step","scene_id","choice_id","actor_id","position","events","battles","battle_id","revisit"]
static var _definitions: Dictionary = {}
static var _scenes: Dictionary = {}
static var _flag_defaults: Dictionary = {}

static func definitions() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id in IDS:
		var row := definition(id)
		if not row.is_empty(): rows.append(row)
	return rows

static func definition(id: String) -> Dictionary:
	_data()
	return _definitions.get(id, {}).duplicate(true)

static func initial() -> Dictionary:
	var states := {}
	for id in IDS: states[id] = {"step":0,"complete":false,"first_actor":""}
	return {"version":1,"legacy":{"events":0,"battles":0},"states":states,"history":[]}

static func migrate(saved: Dictionary) -> Dictionary:
	var result := initial()
	if not saved.get("saga") is Dictionary: return result
	var saga: Dictionary = saved.saga
	if not saga.get("events") is Array or not saga.get("battles") is Array: return result
	result.legacy = {"events":saga.events.size(),"battles":saga.battles.size()}
	result.states = _legacy_states(saved,result.legacy)
	return result

static func normalize(value: Dictionary) -> Dictionary:
	var state := value.duplicate(true)
	_int_fields(state,["version"])
	if state.get("legacy") is Dictionary: _int_fields(state.legacy,["events","battles"])
	if state.get("states") is Dictionary:
		for row in state.states.values():
			if row is Dictionary: _int_fields(row,["step"])
	if state.get("history") is Array:
		for row in state.history:
			if not row is Dictionary: continue
			_int_fields(row,["step","events","battles"])
			if _position(row.get("position")):
				row.position = [float(row.position[0]),float(row.position[1]),float(row.position[2])]
	return state

static func validate(saved: Dictionary) -> Array[String]:
	_data()
	var errors: Array[String] = []
	var state = saved.get("mechanisms")
	if not _fields(state,["version","legacy","states","history"]) or not _plain(state): return ["机关状态字段或JSON类型非法"]
	if not state.version is int or state.version != 1: return ["机关版本非法"]
	if not _fields(state.legacy,["events","battles"]) or not _natural(state.legacy.events) or not _natural(state.legacy.battles): return ["机关历史迁移前缀非法"]
	if not _fields(state.states,IDS) or not state.history is Array: return ["机关分状态或操作历史非法"]
	for id in IDS:
		var row = state.states[id]
		if not _fields(row,STATE_FIELDS) or not _natural(row.step) or row.step > definition(id).steps.size() or not row.complete is bool or not row.first_actor is String: return ["机关步骤/完成/操作者字段非法："+id]
	var legacy: Dictionary = state.legacy
	if not saved.get("saga") is Dictionary:
		return [] if state == initial() else ["首章不能含后章机关历史"]
	var facts := _facts(saved,legacy.events,legacy.battles)
	if not facts.ok: return ["机关迁移前缀不属于真实事件/胜利记录"]
	var facts_cache := {"%d:%d" % [legacy.events,legacy.battles]:facts}
	var baseline := _project_states(facts)
	var rebuilt := baseline.duplicate(true)
	var states_before_event: Dictionary = {}
	var last_events: int = legacy.events
	var last_battles: int = legacy.battles
	for record in state.history:
		if not _fields(record,HISTORY_FIELDS) or not _natural(record.step) or not _natural(record.events) or not _natural(record.battles) or not record.revisit is bool or not _position(record.position): return ["机关操作记录字段或类型非法"]
		for key in ["mechanism_id","action_id","scene_id","choice_id","actor_id","battle_id"]:
			if not record[key] is String: return ["机关历史字符串非法："+key]
		if record.events < last_events or record.battles < last_battles: return ["机关历史不能倒退到较早的事件/战斗前缀"]
		var at := _cached_facts(saved,record.events,record.battles,facts_cache)
		if not at.ok: return ["机关历史引用了未来事件或胜利"]
		var context := _context(record.mechanism_id,record.scene_id,record.choice_id)
		if context.is_empty() or not _actor(saved,record.actor_id): return ["机关历史场次/选择/操作者非法"]
		var revisit: bool = record.mechanism_id == "water_echo" and at.completed.has("C2-10")
		if record.revisit != revisit: return ["重复水口试验的来源标记非法"]
		if not revisit and not _scene_at(saved,record.scene_id,record.choice_id,record.events): return ["机关动作不属于当时活动场次/选择"]
		var action := _action(record.mechanism_id,record.action_id)
		if action.is_empty() or not action.positions.has(record.scene_id) or not _near(record.position,action.positions[record.scene_id],action.radius): return ["机关历史动作或操作位置非法"]
		var changed := _transition(rebuilt,record.mechanism_id,record.action_id,record.actor_id,at)
		if not changed.ok or record.step != rebuilt[record.mechanism_id].step or record.battle_id != changed.battle_id: return ["机关历史不能重演："+str(changed.get("error","步骤或胜利来源不符"))]
		last_events = record.events; last_battles = record.battles
		states_before_event[record.events] = rebuilt.duplicate(true)
	if rebuilt != state.states: errors.append("机关终态与迁移前缀及实际操作历史不符")
	if errors.is_empty():
		# 新版本的成功事件必须已在事件提交之前实际做完，不能靠未来操作补齐。
		# 严格动作已在上面单次重放；这里沿事件前缀推进快照，不再重跑全部history。
		var at_states: Dictionary = baseline
		for index in range(legacy.events,saved.saga.events.size()):
			var event = saved.saga.events[index]
			if not event is Dictionary or not event.get("id") is String or not event.get("choice") is String: return ["机关关联完成事件非法"]
			if states_before_event.has(index): at_states=states_before_event[index]
			if not _has_gates(event.id): continue
			var before := _cached_facts(saved,index,saved.saga.battles.size(),facts_cache)
			for gate in _missing(at_states,event.id,"",event.choice,before.flags): errors.append("完成事件早于实地验证：%s/%s" % [event.id,gate.mechanism_id])
	return errors

static func view_state(saved: Dictionary, id: String) -> Dictionary:
	if not IDS.has(id): return {}
	var row: Dictionary = saved.get("mechanisms",{}).get("states",{}).get(id,initial().states[id]).duplicate(true)
	var step: int = int(row.get("step",0))
	var done: bool = row.get("complete",false) == true
	var visual := {}
	match id:
		"water_echo": visual = {"blocked":step in [2,3],"bell_stopped":step in [2,3],"verified":done}
		"ferry": visual = {"wood_ready":step>=1,"pile_braced":step>=2,"rope_transferred":step>=3,"board_replaced":step>=4,"nails_flat":step>=5,"lamp_raised":step>=6,"boat_far":step==7,"route_open":done}
		"junction": visual = {"rod_supported":step>=1,"isolated":step>=2,"pin_removed":step>=3,"ordinary_lamp":step>=4}
		"ward_test": visual = {"outer_ready":step>=1,"inner_ready":step>=2,"pin_removed":step>=3,"outer_lamp":step>=1,"exit_open":step>=4,"second_checked":step>=5}
		"driftwood": visual = {"braced":step>=1,"right_cut":step>=2,"wood_cleared":step>=3,"stretcher_checkpoint":maxi(0,step-3),"route_open":done}
		"alley": visual = {"cloth_ready":step>=1,"near_covered":step>=2,"far_removed":step>=3,"exit_guarded":step>=4,"handed_over":step>=5}
	var legacy := _legacy_states(saved,saved.get("mechanisms",{}).get("legacy",{"events":0,"battles":0}))
	return {"step":step,"complete":done,"first_actor":row.get("first_actor",""),"legacy":legacy.get(id,{}).get("complete",false),"visual":visual}

static func targets(saved: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not validate(saved).is_empty() or not saved.get("saga") is Dictionary or not saved.get("pending_battle",{}).is_empty(): return result
	for id in IDS:
		var context := _current_context(saved,id)
		if context.is_empty(): continue
		if id!="water_echo" and bool(saved.mechanisms.states[id].complete):continue
		for action in definition(id).actions:
			var states: Dictionary = saved.mechanisms.states.duplicate(true)
			var actor_id: String = _default_actor(saved)
			if action.id == "second_operator":
				for other in saved.get("roster",{}):
					if other != states.ward_test.first_actor: actor_id = other; break
			var check := _transition(states,id,action.id,actor_id,_facts(saved,saved.saga.events.size(),saved.saga.battles.size()))
			result.append({"id":"@mechanism:%s:%s"%[id,action.id],"mechanism_id":id,"action_id":action.id,"label":action.label,"position":action.positions[context.scene_id].duplicate(),"radius":action.radius,"hint":action.hint,"enabled":check.ok,"reason":check.get("error",""),"visual_duration":action.visual_duration})
	return result

static func gates(saved: Dictionary, scene_id: String, channel: String) -> Array[Dictionary]:
	if channel not in ["opening","choice","aftermath"]: return []
	var saga: Dictionary = saved.get("saga",{})
	return _missing(saved.get("mechanisms",{}).get("states",initial().states),scene_id,channel,str(saga.get("choices",{}).get(scene_id,"")),saga.get("flags",{}))

static func completion_errors(saved: Dictionary, scene_id: String) -> Array[String]:
	var errors: Array[String] = []
	for channel in ["opening","choice","aftermath"]:
		for gate in gates(saved,scene_id,channel):
			if not errors.has(gate.hint): errors.append(gate.hint)
	return errors

static func battle_errors(saved: Dictionary, scene_id: String) -> Array[String]:
	var errors:Array[String]=[]
	if scene_id=="C6-S04" and saved.get("saga",{}).get("choices",{}).get(scene_id,"")=="a" and int(saved.get("mechanisms",{}).get("states",{}).get("alley",{}).get("step",0))<2:
		errors.append("近镜还未遮妥，请先检查布与镜片的位置。")
	return errors

static func preview(saved: Dictionary, world: Dictionary, mechanism_id: String, action_id: String, actor_id: String) -> Dictionary:
	var failure := {"ok":false,"error":"当前不能操作这个物件","candidate":{}}
	var errors := validate(saved)
	if not errors.is_empty(): failure.error="；".join(errors); return failure
	if not _actor(saved,actor_id) or not saved.get("pending_battle",{}).is_empty(): return failure
	var context := _current_context(saved,mechanism_id)
	var action := _action(mechanism_id,action_id)
	if context.is_empty() or action.is_empty() or not saved.get("world") is Dictionary or not saved.get("world_history") is Dictionary: return failure
	var original: Dictionary = saved.world.duplicate(true)
	var supplied := world.duplicate(true)
	for key in ["position","player_x","facing","party_index"]: original.erase(key); supplied.erase(key)
	if original != supplied or not _position(world.get("position")) or not world.get("facing") is int or not world.facing in [-1,1] or not _natural(world.get("party_index")) or world.party_index >= saved.get("party",[]).size(): failure.error="位置记录不能改变剧情或地图来源"; return failure
	if not _near(world.position,action.positions[context.scene_id],action.radius): failure.error="请走到物件旁再操作"; return failure
	var candidate := saved.duplicate(true)
	var saga: Dictionary = saved.saga
	var facts := _facts(saved,saga.events.size(),saga.battles.size())
	var changed := _transition(candidate.mechanisms.states,mechanism_id,action_id,actor_id,facts)
	if not changed.ok: failure.error=changed.error; return failure
	var position := [float(world.position[0]),float(world.position[1]),float(world.position[2])]
	candidate.mechanisms.history.append({"mechanism_id":mechanism_id,"action_id":action_id,"step":candidate.mechanisms.states[mechanism_id].step,"scene_id":context.scene_id,"choice_id":context.choice_id,"actor_id":actor_id,"position":position,"events":saga.events.size(),"battles":saga.battles.size(),"battle_id":changed.battle_id,"revisit":mechanism_id=="water_echo" and facts.completed.has("C2-10")})
	candidate.world = world.duplicate(true)
	candidate.world.position = position
	candidate.world.player_x = position[0]
	candidate.world_history[candidate.world.scene_id] = candidate.world.duplicate(true)
	return {"ok":true,"error":"","candidate":candidate,"mechanism_id":mechanism_id,"action_id":action_id,"view":view_state(candidate,mechanism_id),"visual_duration":action.visual_duration}

static func _transition(states: Dictionary, id: String, action_id: String, actor_id: String, facts: Dictionary) -> Dictionary:
	var bad := {"ok":false,"error":"这里的物件还不能这样操作，请再看看受力与通路。","battle_id":""}
	if not IDS.has(id) or not facts.get("ok",false): return bad
	var row: Dictionary = states[id]
	var steps: Array = definition(id).steps
	if id == "water_echo":
		if action_id == "retry" and row.complete:
			row.step = 0
			return {"ok":true,"error":"","battle_id":""}
		if action_id == "unblock" and row.step == 2:
			row.step = 1
			return {"ok":true,"error":"","battle_id":""}
	if row.step >= steps.size() or steps[row.step] != action_id: return bad
	if id == "driftwood" and not states.ferry.complete: bad.error="先确认渡口的结构与空船航路。"; return bad
	if id == "ward_test" and action_id == "second_operator" and (row.first_actor.is_empty() or row.first_actor == actor_id): bad.error="请换一位同伴照记录复验。"; return bad
	var battle_id := ""
	if id == "alley" and row.step >= 2:
		battle_id = str(facts.battle_ids.get("C6-S04",""))
		if battle_id.is_empty(): bad.error="纸影尚未清开，先护住近镜与拆镜的人。"; return bad
	row.step += 1
	if id == "ward_test" and action_id == "pull_pin": row.first_actor=actor_id
	if row.step == steps.size(): row.complete=true
	return {"ok":true,"error":"","battle_id":battle_id}

static func _missing(states: Dictionary, scene: String, channel: String, choice: String, flags: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_data()
	for definition_row in _definitions.values():
		for gate in definition_row.gates:
			if gate.scene_id != scene or (not channel.is_empty() and gate.channel != channel) or (not gate.choice_id.is_empty() and gate.choice_id != choice): continue
			if gate.condition == "ferry_unrepaired" and flags.get("ferry_repaired",false): continue
			var state: Dictionary = states.get(gate.mechanism_id,initial().states[gate.mechanism_id])
			if (gate.require_complete and not state.complete) or (not gate.require_complete and state.step < gate.required_step): result.append(gate.duplicate(true))
	result.sort_custom(func(a,b): return a.before_source_index < b.before_source_index)
	return result

static func _has_gates(scene: String) -> bool:
	for row in _definitions.values():
		for gate in row.gates:
			if gate.scene_id == scene: return true
	return false

static func _current_context(saved: Dictionary, id: String) -> Dictionary:
	if not saved.get("saga") is Dictionary: return {}
	var saga: Dictionary = saved.saga
	var scene: String = str(saga.get("active_scene",""))
	var choice: String = str(saga.get("choices",{}).get(scene,""))
	var context := _context(id,scene,choice)
	if not context.is_empty() and saga.get("chapter") == context.chapter: return context
	if id == "water_echo" and saga.get("chapter") == 2 and saved.get("mechanisms",{}).get("states",{}).get(id,{}).get("complete",false) and saga.get("completed",[]).has("C2-10"): return _context(id,"C2-10","")
	return {}

static func _context(id: String, scene: String, choice: String) -> Dictionary:
	for context in definition(id).get("contexts",[]):
		if context.scene_id == scene and context.choice_id == choice: return context.duplicate(true)
	return {}

static func _action(id: String, action_id: String) -> Dictionary:
	for action in definition(id).get("actions",[]):
		if action.id == action_id: return action.duplicate(true)
	return {}

static func _scene_at(saved: Dictionary, scene: String, choice: String, events: int) -> bool:
	if events < saved.saga.events.size():
		var next = saved.saga.events[events]
		return next is Dictionary and next.get("id") == scene and next.get("choice") == choice
	return saved.saga.get("active_scene","") == scene and saved.saga.get("choices",{}).get(scene,"") == choice

static func _legacy_states(saved: Dictionary, legacy: Dictionary) -> Dictionary:
	var facts := _facts(saved,int(legacy.get("events",0)),int(legacy.get("battles",0)))
	return _project_states(facts)

static func _project_states(facts: Dictionary) -> Dictionary:
	var states: Dictionary = initial().states
	if not facts.ok: return states
	for row in _definitions.values():
		var complete: bool = facts.flags.get(row.legacy_flag,false) == true
		if row.id == "alley": complete = complete and facts.battle_ids.has("C6-S04")
		if complete: states[row.id].step=row.steps.size(); states[row.id].complete=true
	return states

static func _cached_facts(saved: Dictionary, events: int, battles: int, cache: Dictionary) -> Dictionary:
	var key := "%d:%d" % [events,battles]
	if not cache.has(key): cache[key]=_facts(saved,events,battles)
	return cache[key]

static func _facts(saved: Dictionary, events: int, battles: int) -> Dictionary:
	_data()
	var result := {"ok":false,"flags":_flag_defaults.duplicate(true),"completed":[],"battle_ids":{}}
	if not saved.get("saga") is Dictionary:
		result.ok = events==0 and battles==0
		return result
	var saga: Dictionary = saved.saga
	if not saga.get("events") is Array or not saga.get("battles") is Array or not saga.get("battle_encounters") is Dictionary or events<0 or battles<0 or events>saga.events.size() or battles>saga.battles.size(): return result
	var requires_alley_victory := false
	for index in events:
		var event = saga.events[index]
		if not event is Dictionary or not event.get("id") is String or not event.get("choice") is String or not _scenes.has(event.id): return result
		var entry: Dictionary = _scenes[event.id]
		var option: Dictionary = {}
		for row in entry.get("choices",[]):
			if row.id == event.choice: option=row; break
		if not event.choice.is_empty() and option.is_empty(): return result
		if event.id == "C6-S04" and event.choice == "a": requires_alley_victory=true
		for source in [entry,option]:
			for branch in source.get("conditional_effects",[]):
				if _matches(branch.get("requires",{}),result.flags,result.completed): result.flags.merge(branch.get("effects",{}),true)
			result.flags.merge(source.get("effects",{}),true)
		if not result.completed.has(event.id): result.completed.append(event.id)
	for index in battles:
		var scene = saga.battles[index]
		if not scene is String or result.battle_ids.has(scene) or not saved.get("applied_battle_ids") is Array or saved.applied_battle_ids.size() <= index+5: return result
		var battle_id = saved.applied_battle_ids[index+5]
		if not battle_id is String or battle_id != str(saved.get("run_id",""))+":"+str(index+6): return result
		if scene == "C6-S04" and saga.battle_encounters.get(scene) != "saga_c6_s04": return result
		result.battle_ids[scene] = battle_id
	if requires_alley_victory and not result.battle_ids.has("C6-S04"): return result
	result.ok=true
	return result

static func _matches(requirements: Dictionary, flags: Dictionary, completed: Array) -> bool:
	for key in requirements:
		var actual = completed.has(str(key).trim_prefix("done:")) if str(key).begins_with("done:") else flags.get(key)
		if actual != requirements[key]: return false
	return true

static func _actor(saved: Dictionary, id: String) -> bool:
	return saved.get("roster") is Dictionary and saved.roster.get(id) is Dictionary and saved.roster[id].get("actor_id") == id and saved.roster[id].get("side") == "player"

static func _default_actor(saved: Dictionary) -> String:
	for id in saved.get("party",[]):
		if _actor(saved,id): return id
	return ""

static func _fields(value: Variant, fields: Array) -> bool:
	return value is Dictionary and value.size() == fields.size() and value.has_all(fields)

static func _natural(value: Variant) -> bool:
	return value is int and value >= 0

static func _position(value: Variant) -> bool:
	if not value is Array or value.size()!=3: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(number): return false
	return true

static func _near(left: Array, right: Array, radius: float) -> bool:
	return Vector3(left[0],left[1],left[2]).distance_to(Vector3(right[0],right[1],right[2])) <= radius + 0.05

static func _plain(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if not key is String or not _plain(value[key]): return false
		return true
	if value is Array:
		for item in value:
			if not _plain(item): return false
		return true
	return value is String or value is int or value is bool or (value is float and is_finite(value))

static func _int_fields(value: Dictionary, fields: Array) -> void:
	for field in fields:
		var number = value.get(field)
		if number is float and is_finite(number) and number == floor(number): value[field]=int(number)

static func _data() -> void:
	if not _definitions.is_empty(): return
	var data = _integerize(JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)))
	if not data is Dictionary or data.get("schema_version") != 1 or data.get("rules_version") != "map-mechanisms-1": return
	for row in data.get("definitions",[]):
		if row is Dictionary and row.get("id") in IDS: _definitions[row.id] = row
	var story = JSON.parse_string(FileAccess.get_file_as_string(STORY_PATH))
	if not story is Dictionary: return
	_flag_defaults = story.get("flags",{}).duplicate(true)
	for chapter in story.get("chapters",[]):
		for scene in chapter.get("scenes",[]): _scenes[scene.id]=scene

static func _integerize(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floor(value): return int(value)
	if value is Array:
		var result: Array = []
		for item in value: result.append(_integerize(item))
		return result
	if value is Dictionary:
		var result := {}
		for key in value: result[key]=_integerize(value[key])
		return result
	return value
