extends RefCounted
const LegacyPaths = preload("res://scripts/characters/legacy_asset_paths.gd")
## 保留第一幕逐帧节奏；整段通过校验后才装配，拒绝缺帧造成时长错配。
## 只弱共享相同PNG字节；SpriteFrames与动作状态仍各实例独立，不预载入其它形态。
static var _texture_cache: Dictionary = {}
const TEXTURE_CACHE_LIMIT := 512

static func _load_png_texture(path: String, width: int, height: int) -> Texture2D:
	path = LegacyPaths.resolve(path)
	for key in _texture_cache.keys():
		if _texture_cache[key].get_ref() == null: _texture_cache.erase(key)
	if not FileAccess.file_exists(path): return null
	var bytes := FileAccess.get_file_as_bytes(path)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	var signature := hashing.finish().hex_encode()
	if _texture_cache.has(signature):
		var cached: Texture2D = _texture_cache[signature].get_ref()
		if cached != null:
			return cached if cached.get_width() == width and cached.get_height() == height else null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK or image.get_width() != width or image.get_height() != height: return null
	var texture := ImageTexture.create_from_image(image)
	if _texture_cache.size() >= TEXTURE_CACHE_LIMIT: _texture_cache.erase(_texture_cache.keys()[0])
	_texture_cache[signature] = weakref(texture)
	return texture

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _failed(message: String) -> Dictionary:
	return {'ok': false, 'errors': [message]}

static func load_definition(path: String) -> Dictionary:
	path = LegacyPaths.resolve(path)
	if not FileAccess.file_exists(path): return _failed('清单不存在: ' + path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return _failed('清单不是 JSON 对象')
	var manifest: Dictionary = parsed
	if not manifest.get('canvas') is Dictionary: return _failed('canvas必须为对象')
	var canvas: Dictionary = manifest.canvas
	for key in ['w', 'h', 'content_height_px', 'height_m']:
		if not _number(canvas.get(key)) or float(canvas[key]) <= 0: return _failed('画布数值无效: ' + key)
	var width := int(canvas.w)
	var height := int(canvas.h)
	if width != float(canvas.w) or height != float(canvas.h) or width > 4096 or height > 4096:
		return _failed('画布须为不超过4096的整数')
	if not canvas.get('anchor') is Array or canvas.anchor.size() != 2: return _failed('脚点必须为二元数组')
	var anchor: Array = canvas.anchor
	if not _number(anchor[0]) or not _number(anchor[1]): return _failed('脚点必须为有限数')
	if float(anchor[0]) < 0 or float(anchor[0]) >= width or float(anchor[1]) < 0 or float(anchor[1]) >= height:
		return _failed('脚点越界')
	if not _number(manifest.get('move_speed_mps')) or float(manifest.move_speed_mps) <= 0:
		return _failed('参考移速无效')
	if not manifest.get('dir') is String or not manifest.get('anims') is Dictionary:
		return _failed('dir/anims类型无效')
	var animations: Dictionary = manifest.anims
	var errors: Array[String] = []
	for required in ['idle', 'walk', 'attack']:
		if not animations.has(required): errors.append('缺少必需动作: ' + required)
	var frames := SpriteFrames.new()
	frames.remove_animation('default')
	for state in animations:
		if not animations[state] is Dictionary:
			errors.append(str(state) + ': 动作必须为对象')
			continue
		var spec: Dictionary = animations[state]
		if not spec.get('frames') is Array or not spec.get('durations_ms') is Array:
			errors.append(str(state) + ': 帧/时长必须为数组')
			continue
		var names: Array = spec.frames
		var durations: Array = spec.durations_ms
		if names.is_empty() or names.size() != durations.size():
			errors.append(str(state) + ': 帧数与时长数量不符')
			continue
		var textures: Array[Texture2D] = []
		var valid := true
		for i in names.size():
			if not names[i] is String or not _number(durations[i]) or float(durations[i]) <= 0:
				errors.append('帧名/时长无效: ' + str(state))
				valid = false
				continue
			var frame_path: String = manifest.dir + names[i] + '.png'
			var texture := _load_png_texture(frame_path, width, height)
			if texture == null:
				errors.append('缺帧/不可读/画布不匹配: ' + frame_path)
				valid = false
				continue
			textures.append(texture)
		if not valid: continue
		frames.add_animation(state)
		frames.set_animation_speed(state, 1.0)
		frames.set_animation_loop(state, bool(spec.get('loop', state in ['idle', 'walk'])))
		for i in names.size(): frames.add_frame(state, textures[i], float(durations[i]) / 1000.0)
		if bool(spec.get('pingpong', false)):
			for i in range(names.size() - 2, 0, -1):
				frames.add_frame(state, textures[i], float(durations[i]) / 1000.0)
	if not errors.is_empty(): return {'ok': false, 'errors': errors}
	var layer_frames: Array[Dictionary] = []
	if not manifest.get('layers', []) is Array: return _failed('layers必须为数组')
	for spec in manifest.get('layers', []):
		if not spec is Dictionary: return _failed('图层必须为对象')
		if not spec.get('frames') is Array or spec.frames.size() != animations.idle.frames.size():
			return _failed('图层帧数必须匹配idle源帧')
		for key in ['amplitude_px', 'period_s', 'root_y', 'full_motion_y']:
			if not _number(spec.get(key)): return _failed('图层数值无效: ' + key)
		if spec.amplitude_px < 0 or spec.amplitude_px > 2 or spec.period_s <= 0 or spec.root_y < 0 or spec.full_motion_y <= spec.root_y or spec.full_motion_y >= height:
			return _failed('图层根部/幅度/周期越界')
		var textures: Array[Texture2D] = []
		for layer_path in spec.frames:
			if not layer_path is String or not FileAccess.file_exists(LegacyPaths.resolve(layer_path)): return _failed('图层路径无效')
			var texture := _load_png_texture(layer_path, width, height)
			if texture == null:
				return _failed('图层图像/尺寸无效')
			textures.append(texture)
		if bool(animations.idle.get('pingpong', false)):
			for i in range(textures.size()-2, 0, -1): textures.append(textures[i])
		layer_frames.append({'spec': spec, 'textures': textures})
	return {'ok': errors.is_empty(), 'errors': errors, 'manifest': manifest, 'frames': frames, 'layer_frames': layer_frames}
