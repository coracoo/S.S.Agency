# 八组独立地图机关。只消费已提交状态；Tween结束不写档、不发奖、不自行提交下一步。
extends Node3D
const Rules = preload("res://scripts/campaign/mechanism_rules.gd")
const Region = preload("res://scripts/campaign/saga_world.gd")
var chapter := 0
var groups: Dictionary = {}
var parts: Dictionary = {}
var views: Dictionary = {}
var blockers:Dictionary={}
var _definitions: Dictionary = {}
var _materials: Dictionary = {}
var _clock := 0.0
var animating := false

func configure(saved: Dictionary) -> void:
	var requested := int(saved.get("saga",{}).get("chapter",0))
	if requested != chapter:
		for child in get_children(): child.queue_free()
		groups.clear(); parts.clear(); views.clear(); blockers.clear(); _definitions.clear()
		chapter = requested
		for definition in Rules.definitions():
			if not definition.chapters.has(chapter): continue
			_definitions[definition.id] = definition
			var group := Node3D.new()
			group.name = "Mechanism_"+str(definition.id)
			add_child(group)
			groups[definition.id] = group
			match str(definition.id):
				"water_echo": _build_water(group,definition)
				"ferry": _build_ferry(group,definition)
				"junction": _build_junction(group,definition)
				"ward_test": _build_ward(group,definition)
				"driftwood": _build_driftwood(group,definition)
				"alley": _build_alley(group,definition)
				"mirror_gap": _build_mirror_gap(group,definition)
				"clinic_trial": _build_clinic_trial(group,definition)
			var label_offset:=Vector3(0,3.2,-.6)
			if definition.id=="water_echo":label_offset.x=1.0
			if chapter==6 and definition.id=="ferry":label_offset.x=-2.7
			if chapter==6 and definition.id=="driftwood":label_offset.x=.7
			_label(group,str(definition.id)+":status",str(definition.name),_anchor(definition)+label_offset)
	sync(saved)

func sync(saved: Dictionary) -> void:
	for id in groups:
		views[id] = Rules.view_state(saved,id)
		_apply_visual(id,views[id].get("visual",{}))

func part(id: String, name: String) -> Node3D:
	return parts.get(id+":"+name)

func animate_commit(saved: Dictionary, action: Dictionary) -> void:
	var before := {}
	for key in parts:
		var node: Node3D = parts[key]
		before[key] = {"position":node.position,"rotation":node.rotation,"scale":node.scale,"visible":node.visible}
	sync(saved)
	var duration := clampf(float(action.get("visual_duration",.35)),.15,3.0)
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var changed := false
	animating = true
	for key in before:
		var node: Node3D = parts[key]
		for property in ["position","rotation","scale"]:
			var target: Vector3 = node.get(property)
			if target.is_equal_approx(before[key][property]): continue
			node.set(property,before[key][property])
			tween.tween_property(node,property,target,duration)
			changed = true
		if before[key].visible and not node.visible:
			node.visible = true
			tween.tween_property(node,"scale",node.scale*.02,duration)
			changed = true
	if not changed: tween.tween_interval(duration)
	await tween.finished
	if not is_inside_tree(): return
	# 持久状态是最终姿态的唯一来源，隐藏物件不能保留上次缩小的缩放值。
	for key in before: parts[key].scale = before[key].scale
	sync(saved)
	animating = false

func _process(delta: float) -> void:
	_clock += delta
	if groups.has("water_echo"):
		var stopped := bool(views.get("water_echo",{}).get("visual",{}).get("bell_stopped",false))
		var edge_material:StandardMaterial3D=part("water_echo","mirror_edge").material_override
		edge_material.emission_energy_multiplier=0.0 if stopped else .2+.06*sin(_clock*3.0)
		for index in 3:
			var ripple := part("water_echo","ripple_%d" % index)
			ripple.visible = not stopped
			ripple.scale.x = 1.0 if stopped else .72+.23*sin(_clock*2.1+index)

func _anchor(definition: Dictionary) -> Vector3:
	return _vector(definition.anchors[str(chapter)])

func _station(definition: Dictionary, action_id: String) -> Vector3:
	for action in definition.actions:
		if action.id != action_id: continue
		for context in definition.contexts:
			if int(context.chapter) == chapter and action.positions.has(str(context.scene_id)):
				return _vector(action.positions[str(context.scene_id)])
	return _anchor(definition)

static func _vector(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])

func _build_water(group: Node3D, definition: Dictionary) -> void:
	var at := _anchor(definition)
	_box(group,"water_echo:basin",at+Vector3(.3,.02,0),Vector3(1.6,.06,1.5),"water")
	for side in [-1,1]: _box(group,"water_echo:rim_%d" % side,at+Vector3(.3+side*.87,.12,0),Vector3(.16,.24,1.8),"stone")
	_box(group,"water_echo:block",at+Vector3(.5,1.03,.8),Vector3(1.15,.65,.12),"wood")
	for index in 3: _box(group,"water_echo:ripple_%d" % index,at+Vector3(.3,.07,-.5+index*.5),Vector3(1.35,.018,.04),"ripple")
	# 批准原文的钟绳仍捆着，回响来自水道镜边；这里不放一只正在敲响的实体钟。
	var edge:=_box(group,"water_echo:mirror_edge",at+Vector3(1.05,.28,-.5),Vector3(.64,.08,.23),"mirror")
	edge.rotation.y=.28;edge.rotation.z=-.18;edge.material_override=edge.material_override.duplicate()
	_box(group,"water_echo:mirror_chip",at+Vector3(.72,.19,-.57),Vector3(.2,.06,.14),"mirror")
	_label(group,"water_echo:water_label","同音回响",at+Vector3(.3,.6,-.4))

func _build_ferry(group: Node3D, definition: Dictionary) -> void:
	var wood := _station(definition,"dry_wood")+Vector3(0,.14,.45)
	for index in 3: _box(group,"ferry:wood_%d" % index,wood+Vector3(index*.15,index*.09,0),Vector3(.9,.12,.27),"wood")
	var pile := _station(definition,"brace_pile")+Vector3(.42,.45,.4)
	_cylinder(group,"ferry:pile",pile,.12,.17,.9,"wood")
	var brace := _box(group,"ferry:brace",pile+Vector3(.25,-.08,0),Vector3(.15,.85,.14),"wood")
	brace.rotation.z = -.6
	var rope_at := _station(definition,"transfer_rope")+Vector3(.2,.45,.45)
	_box(group,"ferry:rope",rope_at,Vector3(1.45,.07,.07),"cord")
	var board_at := _station(definition,"replace_board")+Vector3(0,.08,.48)
	_box(group,"ferry:old_board",board_at,Vector3(1.45,.13,.72),"dark_wood").rotation.z = -.13
	_box(group,"ferry:new_board",board_at,Vector3(1.45,.13,.72),"wood")
	_box(group,"ferry:nails",board_at+Vector3(.35,.15,0),Vector3(.07,.25,.07),"metal")
	_lamp(group,"ferry:lamp",_station(definition,"raise_lamp")+Vector3(.4,0,.5))
	var boat := Node3D.new()
	boat.name = "MechanismBoat"
	group.add_child(boat)
	parts["ferry:boat"] = boat
	_box(boat,"ferry:keel",Vector3(0,.16,0),Vector3(3.2,.26,.95),"wood",false)
	for side in [-1,1]:
		_box(boat,"ferry:side_%d" % side,Vector3(0,.39,side*.52),Vector3(3.4,.45,.13),"wood",false)
		var prow := _box(boat,"ferry:prow_%d" % side,Vector3(side*1.7,.29,0),Vector3(.45,.4,1.02),"wood",false)
		prow.rotation.z = side*.42
	for x in [-1,0,1]: _box(boat,"ferry:seat_%d" % x,Vector3(x,.51,0),Vector3(.22,.12,1.05),"wood",false)
	_label(boat,"ferry:boat_label","空船 · 核查航道",Vector3(0,1.15,0),false)
	_lamp(group,"ferry:far_lamp",_vector(definition.boat_paths[str(chapter)][1])+Vector3(0,.3,-.9))

func _build_junction(group: Node3D, definition: Dictionary) -> void:
	var at := _anchor(definition)
	# 开放木架露出上下扣和杆销，实心前板会从正式镜头遮住整个操作过程。
	_box(group,"junction:frame",at+Vector3(0,.12,.55),Vector3(1.85,.18,.44),"wood")
	for side in [-1,1]:_box(group,"junction:post_%d"%side,at+Vector3(side*.86,.7,.55),Vector3(.1,1.3,.13),"wood")
	_box(group,"junction:top",at+Vector3(0,1.36,.55),Vector3(1.85,.1,.14),"wood")
	_box(group,"junction:rod",at+Vector3(0,1.07,.34),Vector3(1.9,.12,.12),"bronze")
	_box(group,"junction:support",at+Vector3(-.55,.47,.3),Vector3(.15,.86,.2),"wood")
	_box(group,"junction:upper",at+Vector3(0,.86,.37),Vector3(2.2,.055,.06),"ripple")
	_box(group,"junction:lower",at+Vector3(0,.65,.37),Vector3(2.2,.055,.06),"mirror")
	_box(group,"junction:latch",at+Vector3(.5,.65,.24),Vector3(.25,.08,.18),"bronze")
	_box(group,"junction:pin",_station(definition,"take_pin")+Vector3(0,.77,.35),Vector3(.1,.1,.45),"metal")
	_lamp(group,"junction:lamp",_station(definition,"light_lamp")+Vector3(-.4,0,.25))

func _build_ward(group: Node3D, definition: Dictionary) -> void:
	var at := _anchor(definition)
	_torus(group,"ward_test:outer",at+Vector3(0,.08,0),1.1,1.22,"ripple")
	_torus(group,"ward_test:inner",at+Vector3(0,.12,0),.56,.67,"mirror")
	_cylinder(group,"ward_test:jar",at+Vector3(0,.35,0),.24,.34,.7,"stone")
	_box(group,"ward_test:pin",_station(definition,"pull_pin")+Vector3(.3,.5,0),Vector3(.6,.07,.1),"metal")
	_lamp(group,"ward_test:outer_lamp",_station(definition,"position_outer")+Vector3(.65,0,0))
	var exit_at := _station(definition,"check_exit")
	for side in [-1,1]: _box(group,"ward_test:gate_%d" % side,exit_at+Vector3(side*.92,.68,0),Vector3(.12,1.36,.14),"wood")
	_box(group,"ward_test:crossbar",exit_at+Vector3(0,1.35,0),Vector3(1.96,.12,.14),"wood")
	_label(group,"ward_test:exit_label","退路可检查",exit_at+Vector3(0,1.8,0))

func _build_driftwood(group: Node3D, definition: Dictionary) -> void:
	var at := _anchor(definition)
	# 只挡住木堆本体；两侧仍可走到支点与切口，不封死原地区主干道。
	var body:=StaticBody3D.new();body.name="DriftwoodBlocker";body.position=at+Vector3(.8,.47,.3);group.add_child(body)
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(3.0,.85,.65)
	collision.shape=shape;body.add_child(collision);blockers["driftwood"]={"body":body,"shape":collision}
	for index in 3:
		var log_node := _cylinder(group,"driftwood:log_%d" % index,at+Vector3(.55+index*.17,.32+index*.17,.3),.13,.16,2.25,"wood")
		log_node.rotation.z = PI*.5
		log_node.rotation.y = -.18+index*.2
	_box(group,"driftwood:brace",at+Vector3(.2,.15,.35),Vector3(.32,.3,.8),"wood")
	_box(group,"driftwood:right_cut",at+Vector3(1.55,.35,.3),Vector3(.045,.5,.5),"cut")
	var stretcher := Node3D.new()
	stretcher.name = "EmptyStretcher"
	group.add_child(stretcher)
	parts["driftwood:stretcher"] = stretcher
	for side in [-1,1]: _box(stretcher,"driftwood:handle_%d" % side,Vector3(0,.55,side*.37),Vector3(1.9,.08,.07),"wood",false)
	_box(stretcher,"driftwood:cloth",Vector3(0,.55,0),Vector3(1.35,.035,.72),"cloth",false)
	for index in 3:
		var action: String = ["stretcher_start","stretcher_slope","stretcher_handoff"][index]
		_torus(group,"driftwood:checkpoint_%d" % index,_station(definition,action)+Vector3(0,.045,0),.38,.43,"ripple")

func _build_alley(group: Node3D, definition: Dictionary) -> void:
	var near := _station(definition,"cover_near")+Vector3(0,.8,-.4)
	var far := _station(definition,"remove_far")+Vector3(0,.8,-.4)
	_box(group,"alley:near_frame",near,Vector3(.92,1.38,.16),"wood")
	_box(group,"alley:near_mirror",near+Vector3(0,0,.09),Vector3(.72,1.15,.02),"mirror")
	_box(group,"alley:near_cloth",near+Vector3(0,0,.13),Vector3(.88,1.35,.045),"cloth")
	_box(group,"alley:far_mirror",far,Vector3(.82,1.35,.1),"mirror")
	_box(group,"alley:removed_mirror",far+Vector3(.42,-.72,.12),Vector3(.85,.045,1.05),"mirror")
	_box(group,"alley:cloth_bundle",_station(definition,"prepare_cloth")+Vector3(.42,.3,0),Vector3(.45,.3,.4),"cloth")
	_torus(group,"alley:loop",(near+far)*.5-Vector3(0,.74,0),.6,.68,"mirror")
	_lamp(group,"alley:exit_lamp",_station(definition,"guard_exit")+Vector3(.7,0,0))
	_label(group,"alley:handoff_label","接应处",_station(definition,"handoff")+Vector3(0,1.6,0))

func _build_mirror_gap(group: Node3D, definition: Dictionary) -> void:
	var at := _anchor(definition)
	for side in [-1,1]:
		_box(group,"mirror_gap:frame_%d"%side,at+Vector3(side*1.45,.94,-.55),Vector3(.95,1.85,.16),"wood")
		_box(group,"mirror_gap:mirror_%d"%side,at+Vector3(side*1.45,.94,-.44),Vector3(.76,1.6,.025),"mirror")
	_box(group,"mirror_gap:cloth",at+Vector3(-1.45,.94,-.4),Vector3(.94,1.82,.035),"cloth")
	_box(group,"mirror_gap:rope",at+Vector3(-1,.07,1),Vector3(3,.025,.025),"cord")
	_box(group,"mirror_gap:seam",at+Vector3(1,.045,0),Vector3(.14,.035,1.5),"bronze")
	_box(group,"mirror_gap:brace",at+Vector3(.8,.32,-.2),Vector3(.13,.62,.2),"wood")
	_box(group,"mirror_gap:latch",at+Vector3(1.8,.73,-.6),Vector3(.12,.42,.12),"bronze")
	# 外扣未承力时，铜缝局部有实际阻挡；插销压稳后同步撤去阻挡与铜栅。
	# 不封住镜坊的其他观察路线，也不靠碰撞状态直接提交剧情。
	var body := StaticBody3D.new()
	body.name="MirrorSeamBlocker"; body.position=at+Vector3(2.45,.7,0)
	group.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new(); shape.size=Vector3(.18,1.4,2.8)
	collision.shape=shape; body.add_child(collision)
	blockers["mirror_gap"]={"body":body,"shape":collision}
	for index in 3:
		_box(group,"mirror_gap:bar_%d"%index,at+Vector3(2.45,.7,-.9+index*.9),Vector3(.12,1.4,.1),"bronze")
	_lamp(group,"mirror_gap:lamp",at+Vector3(0,0,.8))
	_label(group,"mirror_gap:route","入口绳待固定",at+Vector3(0,2.2,.5))
	_torus(group,"mirror_gap:exit",_station(definition,"cross_gap")+Vector3(0,.045,0),.36,.41,"ripple")

func _build_clinic_trial(group: Node3D, definition: Dictionary) -> void:
	var at := _anchor(definition)
	_box(group,"clinic_trial:bench",at+Vector3(-.5,.48,-.4),Vector3(1.65,.16,.78),"wood")
	_box(group,"clinic_trial:branch",at+Vector3(.2,.61,-.4),Vector3(2.3,.035,.05),"bronze")
	_box(group,"clinic_trial:latch",at+Vector3(-.7,.68,-.4),Vector3(.18,.1,.24),"metal")
	_box(group,"clinic_trial:screen",at+Vector3(1.3,.85,-.7),Vector3(.08,1.7,1.4),"cloth")
	_box(group,"clinic_trial:small_mirror",at+Vector3(.9,.76,-.4),Vector3(.46,.55,.04),"mirror")
	_torus(group,"clinic_trial:guard",at+Vector3(-.4,.045,-.3),.67,.74,"ripple")
	_lamp(group,"clinic_trial:lamp",at+Vector3(1.7,0,-.3))
	_label(group,"clinic_trial:reading","单床支路待检查",at+Vector3(0,1.8,.2))
	# 只摆交接站与空担架示意，不新增病人身份图，也不以动画提前提交醒来事实。
	for action_id in ["carry_door","handover_yard"]:
		_torus(group,"clinic_trial:"+action_id,_station(definition,action_id)+Vector3(0,.045,0),.48,.54,"ripple")
	var handoff := _station(definition,"handover_yard")
	_box(group,"clinic_trial:stretcher",handoff+Vector3(.8,.45,-.7),Vector3(1.8,.06,.75),"cloth")
	_label(group,"clinic_trial:handoff","后门石院接应处",handoff+Vector3(0,1.7,0))

func _apply_visual(id: String, visual: Dictionary) -> void:
	var definition: Dictionary = _definitions[id]
	match id:
		"water_echo":
			part(id,"block").position.y = .38 if visual.get("blocked",false) else 1.03
			part(id,"water_label").text = "钟声停住 · 水口静下" if visual.get("bell_stopped",false) else "同音回响 · 水纹仍动"
		"ferry":
			for index in 3: part(id,"wood_%d" % index).visible = not visual.get("wood_ready",false)
			part(id,"brace").visible = visual.get("pile_braced",false)
			part(id,"rope").rotation.y = -.42 if visual.get("rope_transferred",false) else .4
			part(id,"old_board").visible = not visual.get("board_replaced",false)
			part(id,"new_board").visible = visual.get("board_replaced",false)
			part(id,"nails").scale.y = .12 if visual.get("nails_flat",false) else 1.0
			part(id,"lamp_glass").position.y = 1.75 if visual.get("lamp_raised",false) else 1.12
			part(id,"lamp_post").scale.y = 1.5 if visual.get("lamp_raised",false) else 1.0
			_lamp_on(id+":lamp",visual.get("lamp_raised",false))
			_lamp_on(id+":far_lamp",visual.get("lamp_raised",false))
			part(id,"boat").position = _vector(definition.boat_paths[str(chapter)][1 if visual.get("boat_far",false) else 0])
		"junction":
			part(id,"support").visible = visual.get("rod_supported",false)
			part(id,"rod").rotation.z = 0 if visual.get("rod_supported",false) else -.13
			part(id,"latch").rotation.y = PI*.5 if visual.get("isolated",false) else 0
			part(id,"lower").visible = not visual.get("isolated",false)
			part(id,"pin").visible = not visual.get("pin_removed",false)
			_lamp_on(id+":lamp",visual.get("ordinary_lamp",false))
		"ward_test":
			part(id,"outer").visible = visual.get("outer_ready",false)
			part(id,"inner").visible = visual.get("inner_ready",false) and not visual.get("pin_removed",false)
			part(id,"pin").visible = not visual.get("pin_removed",false)
			_lamp_on(id+":outer_lamp",visual.get("outer_lamp",false))
			part(id,"exit_label").text = "换手复验完成 · 退路仍通" if visual.get("second_checked",false) else ("退路仍通 · 等待换手复验" if visual.get("exit_open",false) else "退路待实地检查")
		"driftwood":
			part(id,"brace").visible = visual.get("braced",false)
			part(id,"right_cut").visible = visual.get("right_cut",false) and not visual.get("wood_cleared",false)
			for index in 3:
				part(id,"log_%d" % index).position.x = _anchor(definition).x+.55+index*.17+(5.0 if visual.get("wood_cleared",false) else 0.0)
				part(id,"log_%d" % index).position.z = _anchor(definition).z+.3+(2.2 if visual.get("wood_cleared",false) else 0.0)
			if blockers.has(id):
				blockers[id].body.collision_layer=0 if visual.get("wood_cleared",false) else 1
				blockers[id].shape.set_deferred("disabled",bool(visual.get("wood_cleared",false)))
			var checkpoint := int(visual.get("stretcher_checkpoint",0))
			var action: String = ["stretcher_start","stretcher_slope","stretcher_handoff"][clampi(checkpoint-1,0,2)]
			part(id,"stretcher").position = _station(definition,action)
			for index in 3: part(id,"checkpoint_%d" % index).visible = checkpoint > index
		"alley":
			part(id,"cloth_bundle").visible = not visual.get("cloth_ready",false)
			part(id,"near_cloth").visible = visual.get("near_covered",false)
			part(id,"far_mirror").visible = not visual.get("far_removed",false)
			part(id,"removed_mirror").visible = visual.get("far_removed",false)
			part(id,"loop").visible = not visual.get("far_removed",false)
			_lamp_on(id+":exit_lamp",visual.get("exit_guarded",false))
			part(id,"handoff_label").text = "已到接应处 · 渡河状态以现场记录为准" if visual.get("handed_over",false) else "接应处"
		"mirror_gap":
			part(id,"rope").visible = visual.get("rope_ready",false) and not visual.get("crossed",false)
			part(id,"cloth").visible = visual.get("left_covered",false)
			part(id,"seam").visible = visual.get("lamp_received",false)
			part(id,"brace").visible = visual.get("seam_braced",false)
			part(id,"latch").position.y = .38 if visual.get("latch_pressed",false) else .73
			part(id,"exit").visible = visual.get("latch_pressed",false)
			for index in 3: part(id,"bar_%d"%index).visible = not visual.get("latch_pressed",false)
			if blockers.has(id):
				blockers[id].body.collision_layer=0 if visual.get("latch_pressed",false) else 1
				blockers[id].shape.set_deferred("disabled",bool(visual.get("latch_pressed",false)))
			part(id,"lamp_glass").position.y = .55 if visual.get("lamp_received",false) else 1.12
			part(id,"lamp_post").scale.y = .5 if visual.get("lamp_received",false) else 1.0
			_lamp_on(id+":lamp",visual.get("lamp_received",false))
			part(id,"route").text = "同伴已通过 · 绳索收回" if visual.get("crossed",false) else ("外扣已承力 · 沿铜缝通过" if visual.get("latch_pressed",false) else ("铜缝露出 · 仍需支撑" if visual.get("lamp_received",false) else "系绳、遮镜，再接灯"))
		"clinic_trial":
			part(id,"branch").visible = not visual.get("disconnected",false)
			part(id,"latch").rotation.y = PI*.5 if visual.get("disconnected",false) else 0
			part(id,"screen").position.z = _anchor(definition).z+(-.7 if visual.get("isolated",false) else -2.1)
			part(id,"guard").visible = visual.get("guarded",false)
			part(id,"carry_door").visible = visual.get("disconnected",false) and not visual.get("at_door",false)
			part(id,"handover_yard").visible = visual.get("at_door",false) and not visual.get("handed_over",false)
			part(id,"stretcher").visible = visual.get("handed_over",false)
			_lamp_on(id+":lamp",not visual.get("disconnected",false))
			part(id,"reading").text = "撤防后裂纹收缩 · 仅此支路已复测" if visual.get("measured",false) else ("防护已撤 · 等水纹稳定后量看" if visual.get("guard_removed",false) else ("单床铜扣已脱开 · 护送与复测尚待完成" if visual.get("disconnected",false) else "照明与单床支路分开 · 保留后门"))
			part(id,"handoff").text = "已交接医工 · 病仍需继续照护" if visual.get("handed_over",false) else "后门石院接应处"

func _material(id: String) -> StandardMaterial3D:
	if _materials.has(id): return _materials[id]
	var material := StandardMaterial3D.new()
	var colors := {"wood":"9f8665","dark_wood":"49463b","cord":"baaa7c","stone":"858a80","bronze":"b7a76b","metal":"adb8ba","water":"244d57","ripple":"81bfc0","mirror":"899fbe","cloth":"404f59","cut":"e2c587"}
	material.albedo_color = Color(colors.get(id,"b6ad93"))
	material.roughness = .8
	if id in ["wood","dark_wood","stone"]: material.albedo_texture = Region.TEXTURES["wood" if id.contains("wood") else "stone"]
	if id in ["ripple","mirror"]:
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy_multiplier = .3
	_materials[id] = material
	return material

func _mesh(parent: Node3D, key: String, mesh: Mesh, at: Vector3, material: String, registered: bool = true) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = key.replace(":","_")
	node.mesh = mesh
	node.position = at
	node.material_override = _material(material)
	parent.add_child(node)
	if registered: parts[key] = node
	return node

func _box(parent: Node3D, key: String, at: Vector3, size: Vector3, material: String, registered: bool = true) -> MeshInstance3D:
	var mesh := BoxMesh.new(); mesh.size = size
	return _mesh(parent,key,mesh,at,material,registered)

func _cylinder(parent: Node3D, key: String, at: Vector3, top: float, bottom: float, height: float, material: String) -> MeshInstance3D:
	var mesh := CylinderMesh.new(); mesh.top_radius = top;mesh.bottom_radius = bottom;mesh.height = height;mesh.radial_segments = 12
	return _mesh(parent,key,mesh,at,material)

func _torus(parent: Node3D, key: String, at: Vector3, inner: float, outer: float, material: String) -> MeshInstance3D:
	var mesh := TorusMesh.new(); mesh.inner_radius = inner;mesh.outer_radius = outer;mesh.rings = 24;mesh.ring_segments = 8
	return _mesh(parent,key,mesh,at,material)

func _lamp(parent: Node3D, key: String, at: Vector3) -> void:
	_cylinder(parent,key+"_post",at+Vector3(0,.6,0),.045,.065,1.2,"wood")
	var glass := _box(parent,key+"_glass",at+Vector3(0,1.12,0),Vector3(.19,.27,.19),"bronze")
	glass.material_override = glass.material_override.duplicate()
	glass.set_meta("base_y",at.y)

func _lamp_on(key: String, enabled: bool) -> void:
	var node: MeshInstance3D = parts[key+"_glass"]
	var material: StandardMaterial3D = node.material_override
	material.albedo_color = Color("f2d99a") if enabled else Color("4d5350")
	material.emission_enabled = enabled
	material.emission = Color("ffd087")
	material.emission_energy_multiplier = 1.1 if enabled else 0.0

func _label(parent: Node3D, key: String, text: String, at: Vector3, registered: bool = true) -> Label3D:
	var label := Label3D.new()
	label.name = key.replace(":","_")
	label.text = text
	label.position = at
	label.font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
	label.font_size = 25; label.pixel_size = .005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("e7d8aa"); label.outline_size = 5
	parent.add_child(label)
	if registered: parts[key] = label
	return label
