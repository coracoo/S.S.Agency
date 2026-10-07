extends Node2D
## 只负责视觉，不读取战斗资源；保留原步态与收招，死亡优先于旧动作回调。
signal action_finished
signal action_marker(marker: StringName)
signal visual_warning(message: String)
var sprite := AnimatedSprite2D.new()
var definition: Dictionary = {}
var _speed := 0.0
var _facing := 1
var _locked := false
var _down := false
var _generation := 0
var _remaining := 0.0
var _idle_clock := 0.0
var _locomotion_mode: StringName = &"walk"
var _action_elapsed := 0.0
var _hit_stop_left := 0.0
var _hit_stop_speed := 1.0
var _pending_markers: Dictionary = {}
var _layers: Array[Sprite2D] = []
var _layer_specs: Array[Dictionary] = []
var _layer_textures: Array = []

func _init() -> void:
	add_child(sprite)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.animation_finished.connect(_on_animation_finished)

func configure(value: Dictionary) -> bool:
	if not value.get('ok', false): return false
	_generation += 1
	definition = value
	sprite.sprite_frames = value.frames
	var canvas: Dictionary = value.manifest.canvas
	# 2D画布左上角为原点。世界显示时统一使用清单脚锚，绝不逐帧裁边。
	sprite.position = Vector2(float(canvas.w), float(canvas.h)) * 0.5
	for layer in _layers: layer.queue_free()
	_layers.clear()
	_layer_specs.clear()
	_layer_textures.clear()
	for item in value.get('layer_frames', []):
		var spec: Dictionary = item.spec
		var layer := Sprite2D.new()
		layer.texture = item.textures[0]
		layer.position = sprite.position
		layer.z_index = int(spec.get('z_index', 1))
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var material := ShaderMaterial.new()
		material.shader = load('res://scripts/characters/pixel_hair_motion.gdshader')
		material.set_shader_parameter('canvas_size', Vector2(canvas.w, canvas.h))
		material.set_shader_parameter('root_y', float(spec.root_y))
		material.set_shader_parameter('full_motion_y', float(spec.full_motion_y))
		layer.material = material
		add_child(layer)
		_layers.append(layer)
		_layer_specs.append(spec)
		_layer_textures.append(item.textures)
	reset()
	return true

func set_motion(speed_mps: float, facing: int) -> void:
	_speed = maxf(0.0, speed_mps)
	_facing = 1 if facing >= 0 else -1
	var can_mirror: bool = definition.get('manifest', {}).get('mirror_allowed', true)
	sprite.flip_h = _facing < 0 and can_mirror
	for layer in _layers: layer.flip_h = sprite.flip_h
	_update_locomotion()

# 运动意图与实测速度分开：奔跑碰墙仍回idle，半速跑不能误切walk。
func set_locomotion_mode(mode: StringName) -> void:
	_locomotion_mode = &"run" if mode == &"run" else &"walk"
	_update_locomotion()

# 极短停顿只作用于本精灵；不改Engine.time_scale、模型时钟或其它队员。
func hit_stop(seconds: float = 0.045) -> void:
	if not _locked or _down or not is_finite(seconds) or seconds <= 0: return
	var duration := minf(seconds,0.08)
	if _hit_stop_left <= 0: _hit_stop_speed = sprite.speed_scale
	_hit_stop_left = maxf(_hit_stop_left,duration)
	sprite.speed_scale = 0.0

func request_action(state: StringName) -> bool:
	if definition.is_empty(): return false
	if state == &'down':
		_generation += 1
		_down = true
		_locked = true
	elif state == &'recover':
		if not _down: return false
		_generation += 1
		_down = false
		_locked = false
	elif _locked or _down:
		return false
	_generation += 1
	_locked = true
	_remaining = 0.0
	_action_elapsed = 0.0
	_hit_stop_left = 0.0
	_pending_markers = definition.manifest.get("anims", {}).get(str(state), {}).get("events", {}).duplicate(true)
	sprite.speed_scale = 1.0
	if not sprite.sprite_frames.has_animation(state):
		visual_warning.emit('缺少 %s 帧：使用明确 neutral 表现' % state)
		sprite.play('idle')
		sprite.pause()
		_finish_neutral.call_deferred(_generation)
		return true
	sprite.play(state)
	for i in sprite.sprite_frames.get_frame_count(state):
		_remaining += sprite.sprite_frames.get_frame_duration(state, i) / sprite.sprite_frames.get_animation_speed(state)
	_remaining += 0.15
	_update_layers()
	return true

func _finish_neutral(generation: int) -> void:
	if generation != _generation: return
	_complete_action()

func _on_animation_finished() -> void:
	if not _locked: return
	_complete_action()

func _complete_action() -> void:
	_remaining = 0.0
	_pending_markers.clear()
	if _down:
		# watchdog或迟到信号都必须停在真正末帧。
		if sprite.sprite_frames.has_animation(sprite.animation):
			sprite.set_frame_and_progress(sprite.sprite_frames.get_frame_count(sprite.animation) - 1, 1.0)
		sprite.pause()
		return
	_locked = false
	_update_locomotion()
	action_finished.emit()

func _update_locomotion() -> void:
	if definition.is_empty() or _locked or _down: return
	var reference := float(definition.manifest.move_speed_mps)
	var moving := _speed > reference * 0.03
	var desired := "idle"
	if moving:
		desired = "run" if _locomotion_mode == &"run" and sprite.sprite_frames.has_animation("run") else "walk"
		if desired == "run": reference = float(definition.manifest.get("run_speed_mps", 4.2))
	if sprite.animation != desired or not sprite.is_playing(): sprite.play(desired)
	sprite.speed_scale = clampf(_speed / reference, 0.0, 2.0) if desired in ['walk', 'run'] else 1.0
	_update_layers()

func _process(delta: float) -> void:
	if _hit_stop_left > 0:
		var consumed := minf(delta,_hit_stop_left)
		_hit_stop_left -= consumed
		delta -= consumed
		if _hit_stop_left <= 0: sprite.speed_scale = _hit_stop_speed
		if delta <= 0: return
	if _locked and _remaining > 0:
		_action_elapsed += delta
		var generation := _generation
		for marker in _pending_markers.keys():
			if _action_elapsed * 1000.0 >= float(_pending_markers[marker]):
				_pending_markers.erase(marker)
				action_marker.emit(StringName(marker))
				# 交互回调可能换场、取消或重配；旧栈不能继续发标记。
				if generation != _generation: return
	if _remaining > 0:
		_remaining -= delta
		if _remaining <= 0:
			visual_warning.emit('动作结束通知超时，视觉安全解锁')
			_complete_action()
	_idle_clock += delta
	_update_layers()

func _update_layers() -> void:
	for i in _layers.size():
		var layer := _layers[i]
		layer.visible = not _locked and not _down and sprite.animation == 'idle'
		var spec := _layer_specs[i]
		var amplitude := clampf(float(spec.get('amplitude_px', 1.0)), 0, 2)
		var dx := roundf(sin(_idle_clock * TAU / maxf(float(spec.get('period_s', 3)), 0.1)) * amplitude)
		layer.position = sprite.position
		layer.texture = _layer_textures[i][mini(sprite.frame, _layer_textures[i].size()-1)]
		(layer.material as ShaderMaterial).set_shader_parameter('offset_px', dx)

func reset() -> void:
	_generation += 1
	_locked = false
	_down = false
	_speed = 0.0
	_remaining = 0.0
	_idle_clock = 0.0
	_action_elapsed = 0.0
	_hit_stop_left = 0.0
	_pending_markers.clear()
	_locomotion_mode = &"walk"
	_update_locomotion()

func is_action_locked() -> bool: return _locked or _down
func is_downed() -> bool: return _down
