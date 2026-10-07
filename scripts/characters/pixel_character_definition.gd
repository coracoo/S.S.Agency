extends RefCounted
const LegacyPaths = preload("res://scripts/characters/legacy_asset_paths.gd")
## 保留第一幕逐帧节奏；整段通过校验后才装配，拒绝缺帧造成时长错配。
## 只弱共享相同PNG字节；SpriteFrames与动作状态仍各实例独立，不预载入其它形态。
static var _texture_cache: Dictionary = {}
const TEXTURE_CACHE_LIMIT := 512
const CONTEXT_ACTIONS := {
	"world": ["idle", "walk", "run", "jump", "interact", "pickup"],
	"battle": ["idle", "battle_dash", "attack", "item", "down", "hit", "defend", "recover"]
}

static func valid_context(context: String) -> bool:
	return context == "full" or CONTEXT_ACTIONS.has(context)

static func supports_context(definition: Dictionary, context: String) -> bool:
	# 无上下文标签的既有完整定义/小型注入夹具仍保持兼容，不触发正式大图加载。
	var loaded := str(definition.get("context", "full"))
	return definition.get("ok", false) and (not definition.has("context") or loaded == context)


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

static func _integer_array(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count: return false
	for number in value:
		if not _number(number) or float(number) != floor(float(number)): return false
	return true

# 图集每页在本次定义加载中只读一次，避免每帧重复读取和哈希大型PNG。
static func _load_packed_frames(value: Variant, width: int, height: int, references: Dictionary) -> Dictionary:
	if not value is Dictionary: return _failed('packed_frames必须为对象')
	var pages: Dictionary = {}
	var textures: Dictionary = {}
	# 清单可保留未采用的源视频帧作为追溯信息；运行与发布只依赖实际动作引用。
	for name in references:
		if not value.has(name): return _failed('动作引用的图集帧缺失: ' + str(name))
		if not name is String or name.is_empty() or not value[name] is Dictionary: return _failed('图集帧名/描述无效')
		var spec: Dictionary = value[name]
		if not spec.get('atlas') is String or spec.atlas.is_empty(): return _failed('图集路径无效: ' + name)
		if not _integer_array(spec.get('atlas_size'), 2): return _failed('图集尺寸必须为整数二元数组: ' + name)
		var size: Array = spec.atlas_size
		if size[0] <= 0 or size[1] <= 0 or size[0] > 16384 or size[1] > 16384: return _failed('图集尺寸越界: ' + name)
		if not _integer_array(spec.get('region'), 4) or not _integer_array(spec.get('offset'), 2): return _failed('图集区域/偏移类型无效: ' + name)
		var region: Array = spec.region
		var offset: Array = spec.offset
		if region[0] < 0 or region[1] < 0 or region[2] <= 0 or region[3] <= 0 or region[0] + region[2] > size[0] or region[1] + region[3] > size[1]:
			return _failed('图集区域越界: ' + name)
		if offset[0] < 0 or offset[1] < 0 or offset[0] + region[2] > width or offset[1] + region[3] > height:
			return _failed('图集帧超出虚拟画布: ' + name)
		var path := LegacyPaths.resolve(str(spec.atlas))
		if not pages.has(path): pages[path] = _load_png_texture(path, int(size[0]), int(size[1]))
		var page: Texture2D = pages[path]
		if page == null or page.get_width() != int(size[0]) or page.get_height() != int(size[1]): return _failed('图集缺失/不可读/尺寸不匹配: ' + path)
		var texture := AtlasTexture.new()
		texture.atlas = page
		texture.region = Rect2(region[0], region[1], region[2], region[3])
		# margin.size是两侧透明边距总量；固定虚拟画布才能保持脚锚和镜像一致。
		texture.margin = Rect2(offset[0], offset[1], width - region[2], height - region[3])
		texture.filter_clip = true
		textures[name] = texture
	return {'ok': true, 'textures': textures}

static func load_definition(path: String, context: String = "full") -> Dictionary:
	if not valid_context(context): return _failed("人物资源上下文无效: " + context)
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
	if manifest.has("run_speed_mps") and (not _number(manifest.run_speed_mps) or float(manifest.run_speed_mps) <= 0):
		return _failed("奔跑参考移速无效")
	var packed := manifest.has('packed_frames')
	if (not packed and not manifest.get('dir') is String) or not manifest.get('anims') is Dictionary:
		return _failed('dir/anims类型无效')
	var animations: Dictionary = manifest.anims
	var selected: Dictionary = {}
	for state in animations:
		if context == "full" or CONTEXT_ACTIONS[context].has(state): selected[state] = animations[state]
	var packed_textures: Dictionary = {}
	if packed:
		var references: Dictionary = {}
		for state in selected:
			if not animations[state] is Dictionary or not animations[state].get('frames') is Array: continue
			for name in animations[state].frames:
				if name is String: references[name] = true
		var packed_result := _load_packed_frames(manifest.packed_frames, width, height, references)
		if not packed_result.ok: return packed_result
		packed_textures = packed_result.textures
	var errors: Array[String] = []
	for required in ['idle', 'walk', 'attack']:
		if not animations.has(required): errors.append('缺少必需动作: ' + required)
	var frames := SpriteFrames.new()
	frames.remove_animation('default')
	for state in selected:
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
			var frame_path: String = str(names[i]) if packed else manifest.dir + names[i] + '.png'
			var texture: Texture2D = packed_textures.get(names[i]) if packed else _load_png_texture(frame_path, width, height)
			if texture == null:
				errors.append('缺帧/不可读/画布不匹配: ' + frame_path)
				valid = false
				continue
			textures.append(texture)
		if not valid: continue
		var duration_ms := 0.0
		for duration in durations: duration_ms += float(duration)
		if bool(spec.get('pingpong', false)):
			for i in range(durations.size() - 2, 0, -1): duration_ms += float(durations[i])
		if spec.has("events"):
			if not spec.events is Dictionary:
				errors.append(str(state) + ": 动作标记必须为字典")
				continue
			var marker_valid := true
			for marker in spec.events:
				if not marker is String or marker.is_empty() or not _number(spec.events[marker]) or float(spec.events[marker]) < 0 or float(spec.events[marker]) >= duration_ms:
					marker_valid = false
			if not marker_valid:
				errors.append(str(state) + ": 动作标记必须有名称且位于动作时长以内")
				continue
		if spec.has('impact_ms'):
			if not _number(spec.impact_ms) or float(spec.impact_ms) <= 0 or float(spec.impact_ms) >= duration_ms:
				errors.append(str(state) + ': 命中时刻必须位于动作时长以内')
				continue
		frames.add_animation(state)
		# 毫秒为权重，避免SpriteFrames把小于0.01的秒权重截成最小时长。
		frames.set_animation_speed(state, 1000.0)
		frames.set_animation_loop(state, bool(spec.get('loop', state in ['idle', 'walk', 'run'])))
		for i in names.size(): frames.add_frame(state, textures[i], float(durations[i]))
		if bool(spec.get('pingpong', false)):
			for i in range(names.size() - 2, 0, -1):
				frames.add_frame(state, textures[i], float(durations[i]))
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
	return {'ok': errors.is_empty(), 'errors': errors, 'manifest': manifest, 'context': context, 'frames': frames, 'layer_frames': layer_frames}
