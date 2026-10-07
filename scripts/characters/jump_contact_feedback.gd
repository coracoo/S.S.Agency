extends Node3D
## 只读动作时间的独立接地反馈：不移动人物、不改源帧、不消耗随机数。
const PULSE_SECONDS := 0.22
const PULSE_SHADER = preload("res://scripts/characters/jump_landing_pulse.gdshader")
var pulse := MeshInstance3D.new()
var active := false
var _markers := Vector3.ZERO
var _landed := false
var _pulse_age := -1.0
var _pulse_basis := Basis.IDENTITY
func _init() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	pulse.mesh = plane
	pulse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = PULSE_SHADER
	pulse.material_override = material
	add_child(pulse)
	# 脉冲留在实际落地处，不随之后的移动漂走。
	pulse.top_level = true
	pulse.hide()
func start(events: Dictionary) -> bool:
	cancel()
	for key in ["takeoff","apex","landing"]:
		if not events.has(key) or not (events[key] is float or events[key] is int) or not is_finite(float(events[key])): return false
	_markers = Vector3(float(events.takeoff),float(events.apex),float(events.landing))/1000.0
	if _markers.x < 0 or _markers.y <= _markers.x or _markers.z <= _markers.y: return false
	active = true
	return true
func sample(elapsed: float) -> Vector2:
	if not active or _landed or not is_finite(elapsed) or elapsed <= _markers.x or elapsed >= _markers.z: return Vector2.ONE
	var height := smoothstep(_markers.x,_markers.y,elapsed) if elapsed <= _markers.y else 1.0-smoothstep(_markers.y,_markers.z,elapsed)
	return Vector2(1.0-height*.25,1.0-height*.5)
func land(point: Vector3, normal: Vector3) -> bool:
	if not active or _landed: return false
	_landed = true
	_pulse_age = 0.0
	_pulse_basis = Basis(Quaternion(Vector3.UP,normal.normalized()))
	pulse.global_position = point
	_update_pulse()
	pulse.show()
	return true
func cancel() -> void:
	active = false
	_landed = false
	_pulse_age = -1.0
	pulse.hide()
func _process(delta: float) -> void:
	if _pulse_age < 0: return
	_pulse_age += maxf(delta,0.0)
	if _pulse_age >= PULSE_SECONDS:
		_pulse_age = -1.0
		pulse.hide()
		return
	_update_pulse()
func _update_pulse() -> void:
	var progress := clampf(_pulse_age/PULSE_SECONDS,0.0,1.0)
	var spread := lerpf(1.0,1.6,progress)
	pulse.global_basis = _pulse_basis.scaled_local(Vector3(.72*spread,1.0,.40*spread))
	pulse.material_override.set_shader_parameter("opacity",.34*(1.0-progress))
