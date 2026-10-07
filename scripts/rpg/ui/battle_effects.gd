# 透明技能帧与独立确定性粒子；仅消费呈现上下文，绝不触碰模型/RNG/存档。
extends Node2D
const Profiles = preload("res://scripts/rpg/ui/skill_effect_profiles.gd")
const MAX_BURSTS := 24
const MAX_TEXTURES := 10
const CELL := 192
const COLUMNS := 6
const ATLAS_BYTES := CELL * CELL * 24 * 4
const PALETTES := {"rinne":Color("91eadb"), "mint":Color("f4d773"), "guard":Color("a9c9ed"), "homura_sword":Color("ffb278"), "homura_mage":Color("ff7960"), "healer":Color("9defbd"), "controller":Color("b5a7ed")}
var _bursts: Array[Dictionary] = []
var _seen: Dictionary = {}
var _actions: Dictionary = {}
var _hits: Dictionary = {}
var _cancelled: Dictionary = {}
var _textures: Dictionary = {}

static func ability_profile(ability_id: String) -> Dictionary:
	return Profiles.get_profile(ability_id)

static func profile(event: Dictionary, form: String, context: Dictionary = {}) -> Dictionary:
	var kind := str(event.get("type", ""))
	var ability := "" if kind == "periodic_damage" else str(context.get("ability_id", ""))
	var spec := ability_profile(ability)
	var payload: Dictionary = event.get("payload", {})
	var supplement := false
	if not spec.is_empty():
		if kind not in spec.events:
			var status: Dictionary = payload.get("status", payload.get("after", {}))
			# 护生/引火/追踪/震慑为小附加层，不能再次播放主技能。
			if ability == "heal" and kind in ["shield_applied", "shield_refreshed"]:
				spec = ability_profile("holy_shield"); supplement = true
			elif ability == "armor_break" and kind in ["status_applied", "status_refreshed"] and status.get("id") == "burn":
				spec = ability_profile("burn_brand"); supplement = true
			elif ability == "ambush" and kind in ["status_applied", "status_refreshed"] and status.get("id") == "mark":
				spec = ability_profile("mark"); supplement = true
			elif ability == "shield_bash" and kind in ["status_applied", "status_refreshed"] and status.get("id") == "weaken":
				spec = ability_profile("weaken"); supplement = true
			else: return {}
		if kind == "status_removed" and payload.get("reason") != "cleanse": return {}
	else:
		match kind:
			"damage":
				var basic := {"rinne":"heavy_slash", "mint":"hunt", "guard":"shield_bash", "homura_sword":"heavy_slash", "homura_mage":"firebolt", "healer":"magic_break", "controller":"magic_break"}
				spec = ability_profile(basic.get(form, "shield_bash"))
			"periodic_damage": spec = ability_profile("burn_brand"); supplement = true
			"healed", "revived", "mp_restored": spec = ability_profile("heal")
			"shield_applied", "shield_refreshed": spec = ability_profile("holy_shield")
			"status_applied", "status_refreshed":
				var status: Dictionary = payload.get("status", payload.get("after", {}))
				spec = ability_profile({"burn":"burn_brand", "slow":"slow", "stun":"seal", "defend":"iron_wall", "battle_spirit":"battle_spirit", "cover":"cover", "mark":"mark"}.get(status.get("id", ""), "weaken"))
			"status_removed":
				if payload.get("reason") != "cleanse": return {}
				spec = ability_profile("cleanse")
			"charge_interrupted": spec = ability_profile("shield_bash")
			_: return {}
	# 旧profile调用仍可查询shape/color/duration。
	spec.merge({"shape":spec.atlas, "color":Color(spec.color), "duration":0.5 if supplement else 0.64, "critical":bool(payload.get("critical", false)), "supplement":supplement}, true)
	if supplement: spec.size *= 0.60
	return spec

func present_action(context: Dictionary, _form: String, source: Vector2, targets: Dictionary, battle_id: String) -> bool:
	var spec := ability_profile(str(context.get("ability_id", "")))
	if spec.is_empty() or targets.is_empty(): return false
	var key := _action_key(context, battle_id)
	if key.is_empty() or _actions.has(key) or _cancelled.has(key): return false
	_remember(_actions, key)
	var impact := clampf(float(context.get("impact_delay", 0.42)), 0.0, 12.0)
	# 长本体动作仅在命中前短窗施法，避免长蓄力遮挡。
	var flight := minf(0.30, impact * 0.6) if spec.projectile else 0.0
	var start := maxf(0.0, impact - flight - 0.24)
	var cast := spec.duplicate(true)
	cast.merge({"source":source, "target":source, "elapsed":0.0, "duration":maxf(0.01, impact-flight), "start":start, "phase":"cast", "action_key":key, "size":float(spec.size)*0.58, "color":Color(spec.color), "critical":false}, true)
	_add_burst(cast)
	if spec.projectile and flight > 0:
		var ids := targets.keys(); ids.sort()
		for id in ids.slice(0, 12):
			if not targets[id] is Vector2: continue
			var projectile := spec.duplicate(true)
			projectile.merge({"source":source, "target":targets[id], "target_id":str(id), "elapsed":0.0, "duration":impact, "start":impact-flight, "phase":"projectile", "action_key":key, "size":float(spec.size)*0.62, "color":Color(spec.color), "critical":false}, true)
			_add_burst(projectile)
	queue_redraw()
	return true

func present_event(event: Dictionary, form: String, source: Vector2, target: Vector2, battle_id: String, context: Dictionary = {}) -> bool:
	var action := "" if event.get("type") == "periodic_damage" else _action_key(context, battle_id)
	if _cancelled.has(action): return false
	if event.get("type") == "saga_cancelled":
		cancel_action(context, battle_id)
		return false
	if event.get("type") == "effect_ignored":
		_finish_flight(action, str(event.get("target_id", "")))
		return false
	var effect := profile(event, form, context)
	if effect.is_empty(): return false
	var key := "%s:%s:%s:%s:%s" % [battle_id,event.get("sequence",0),event.get("type",""),event.get("actor_id",""),event.get("target_id","")]
	if _seen.has(key): return false
	_remember(_seen, key)
	if not action.is_empty():
		var hit_key := "%s:%s:%s" % [action, event.get("target_id", ""), effect.atlas if effect.supplement else "main"]
		if _hits.has(hit_key): return false
		_remember(_hits, hit_key)
		effect.action_key = action
		_finish_flight(action, str(event.get("target_id", "")), false)
	effect.merge({"source":source, "target":target, "elapsed":0.0, "start":0.0, "phase":"impact"}, true)
	_add_burst(effect)
	queue_redraw()
	return true

func _finish_flight(action: String, target_id: String, release_textures: bool = true) -> void:
	if action.is_empty(): return
	_bursts = _bursts.filter(func(item): return item.get("action_key", "") != action or item.phase == "impact" or (item.phase == "projectile" and item.get("target_id", "") != target_id))
	if release_textures: _release_unused()
	queue_redraw()

func cancel_action(context: Dictionary, battle_id: String) -> void:
	var action := _action_key(context, battle_id)
	if action.is_empty(): return
	_remember(_cancelled, action)
	_bursts = _bursts.filter(func(item): return item.get("action_key", "") != action)
	_release_unused()
	queue_redraw()

func _action_key(context: Dictionary, battle_id: String) -> String:
	var command := str(context.get("command_id", ""))
	return "" if command.is_empty() else battle_id + ":" + command

func _remember(memory: Dictionary, key: String) -> void:
	memory[key] = true
	if memory.size() > 512: memory.erase(memory.keys()[0])

func _add_burst(burst: Dictionary) -> void:
	if _bursts.size() >= MAX_BURSTS: _bursts.pop_front()
	_bursts.append(burst)
	# 强制预算时丢最旧视觉，不影响模型。
	_release_unused()
	if not _textures.has(burst.atlas):
		while _textures.size() >= MAX_TEXTURES:
			var oldest: String = str(_textures.keys()[0])
			_bursts = _bursts.filter(func(item): return item.atlas != oldest)
			_textures.erase(oldest)
		var path := "res://assets/effects/illustrated_spells/%s.png" % burst.atlas
		if FileAccess.file_exists(path):
			var bytes := FileAccess.get_file_as_bytes(path)
			var decoded := Image.new()
			if decoded.load_png_from_buffer(bytes) == OK:
				_textures[burst.atlas] = ImageTexture.create_from_image(decoded)

func _release_unused() -> void:
	var needed: Dictionary = {}
	for burst in _bursts: needed[burst.atlas] = true
	for key in _textures.keys():
		if not needed.has(key): _textures.erase(key)

func active_count() -> int: return _bursts.size()
func texture_memory_bytes() -> int: return _textures.size() * ATLAS_BYTES
func clear() -> void:
	_bursts.clear(); _seen.clear(); _actions.clear(); _hits.clear(); _cancelled.clear(); _textures.clear()
	queue_redraw()
func _process(delta: float) -> void:
	if _bursts.is_empty(): return
	for burst in _bursts: burst.elapsed += maxf(0.0, delta)
	_bursts = _bursts.filter(func(burst): return burst.elapsed < burst.duration)
	_release_unused()
	queue_redraw()

func _draw() -> void:
	for burst in _bursts:
		if burst.elapsed < burst.start: continue
		var t := clampf((float(burst.elapsed)-float(burst.start))/maxf(0.001,float(burst.duration)-float(burst.start)),0,1)
		var center: Vector2 = burst.target
		var angle := 0.0
		var frame := 12 + mini(11, floori(t*12.0))
		var effect_size: float = burst.size * (1.12 if burst.critical else 1.0)
		if burst.phase == "cast": frame = mini(5, floori(t*6.0))
		elif burst.phase == "projectile":
			frame = 6 + mini(5, floori(t*6.0))
			center = burst.source.lerp(burst.target, t)
			if burst.atlas in ["firebolt", "ice_arrow", "burn_brand", "weaken", "seal", "magic_break", "hunt"]:
				angle = (burst.target-burst.source).angle()
		if _textures.has(burst.atlas):
			var region := Rect2((frame % COLUMNS)*CELL, floori(float(frame)/COLUMNS)*CELL, CELL, CELL)
			draw_set_transform(center, angle)
			draw_texture_rect_region(_textures[burst.atlas], Rect2(Vector2.ONE*(-effect_size*.5),Vector2.ONE*effect_size), region)
			draw_set_transform(Vector2.ZERO)
		if burst.phase == "impact": _draw_particles(burst, t)

func _draw_particles(burst: Dictionary, t: float) -> void:
	var tint: Color = burst.color
	tint.a = pow(1.0-t,1.4)*0.72
	var count := 4 if burst.get("supplement", false) else 8
	for i in range(count):
		var direction := Vector2.from_angle(float(i)*2.399963+0.2)
		var radius := (12.0+58.0*t)*float(burst.size)/232.0
		var pos: Vector2 = burst.target+direction*radius
		if burst.particle in ["petal", "ember"]: pos.y -= 24*t
		var size := 2.5+2*(1-t)
		if burst.particle == "shard":
			draw_colored_polygon(PackedVector2Array([pos+direction*size*2,pos+direction.orthogonal()*size*.5,pos-direction*size,pos-direction.orthogonal()*size*.5]),tint)
		elif burst.particle == "paper":
			draw_set_transform(pos, float(i)+t)
			draw_rect(Rect2(-size,-size*.6,size*2,size*1.2),tint)
			draw_set_transform(Vector2.ZERO)
		else:
			draw_line(pos-direction*size,pos+direction*size,tint,1.6,true)
