# 第一幕天气系统：夜雨 + 阵风 + 落叶 + 水滩。
# 雨丝/落叶用 MultiMesh 实例化在相机锚点周围的盒域内，GDScript 逐帧推进；
# 风是随时间起伏的向量，同时驱动雨丝倾斜与落叶漂移；水滩是静态涟漪面片（shader 圆形羽化）。
extends Node3D

const PUDDLE_SHADER := preload("res://scripts/campaign/puddle.gdshader")

const RAIN_COUNT := 700
const LEAF_COUNT := 26
const BOX := Vector3(46.0, 24.0, 40.0)
const FALL_SPEED := 14.0

var _rain: MultiMeshInstance3D
var _leaves: MultiMeshInstance3D
var _puddles: Array[MeshInstance3D] = []
var _flash: DirectionalLight3D
var _wind := Vector3.ZERO
var _rain_seed: Array[Vector3] = []
var _leaf_seed: Array[Vector3] = []
var _time := 0.0
# 当前档案强度（0~1），由 data/campaign/weather.json 的夜晚调度决定。
var _rain_level := .45
var _wind_level := .4
var _thunder_level := 0.0
var _thunder_timer := 0.0
var _flash_power := 0.0
static var _profiles_cache: Dictionary = {}

## 读天气档案表（运行时源，含缓存；读不到时退回小雨默认，绝不致游戏起不来）。
static func profiles() -> Dictionary:
	if not _profiles_cache.is_empty(): return _profiles_cache
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/weather.json"))
	if data is Dictionary and data.get("profiles") is Dictionary:
		_profiles_cache = data
	return _profiles_cache

static func profile_for_night(night_id: int) -> Dictionary:
	var data := profiles()
	var nights: Dictionary = data.get("nights", {})
	var profiles_map: Dictionary = data.get("profiles", {})
	var name: String = nights.get(str(night_id), "light_rain")
	if profiles_map.has(name) and profiles_map[name] is Dictionary:
		return profiles_map[name]
	return {"rain": .45, "wind": .4, "leaves": true, "puddles": true, "thunder": 0.0}

static func build(floor_y: float, night_id: int = 1) -> Node3D:
	var weather := new()
	weather.name = "ActOneWeather"
	weather._build_rain()
	weather._build_leaves()
	weather._build_puddles(floor_y)
	weather._build_flash()
	weather.apply_profile(profile_for_night(night_id))
	return weather

## 按天气档案调度强度：雨量决定可见雨丝数，风力缩放阵风，雷暴开闪电。
func apply_profile(profile: Dictionary) -> void:
	_rain_level = clampf(float(profile.get("rain", .45)), 0.0, 1.0)
	_wind_level = clampf(float(profile.get("wind", .4)), 0.0, 1.0)
	_thunder_level = clampf(float(profile.get("thunder", 0.0)), 0.0, 1.0)
	_rain.multimesh.visible_instance_count = int(RAIN_COUNT * _rain_level)
	_leaves.multimesh.visible_instance_count = LEAF_COUNT if profile.get("leaves", true) else 0
	for puddle in _puddles: puddle.visible = profile.get("puddles", true)
	_thunder_timer = randf_range(2.0, 6.0)
	if _rain_level <= 0.0: _rain.multimesh.visible_instance_count = 0

func _build_flash() -> void:
	_flash = DirectionalLight3D.new()
	_flash.name = "ThunderFlash"
	_flash.rotation_degrees = Vector3(-52,-18,0)
	_flash.light_color = Color("cfd9ee")
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	add_child(_flash)

## 每帧由 geometry.update_visibility 驱动：anchor=玩家位置，雨盒/叶盒跟随。
func update(anchor: Vector3, delta: float) -> void:
	_time += delta
	# 阵风：两个不同周期正弦叠加 + 基值，xz 方向摆动；风力档案缩放幅度。
	var gust := sin(_time * .43) * .5 + sin(_time * 1.17) * .22
	_wind = Vector3(gust * 2.4 + .8, 0.0, sin(_time * .61) * 1.8 - .6) * (.35 + _wind_level)
	_update_rain(anchor, delta)
	_update_leaves(anchor, delta)
	_update_thunder(delta)

func _update_thunder(delta: float) -> void:
	if _thunder_level <= 0.0:
		_flash.light_energy = 0.0
		return
	_thunder_timer -= delta
	if _thunder_timer <= 0.0:
		# 雷暴：3~8 秒一次随机闪电，先亮后衰。
		_flash_power = 2.4 * _thunder_level
		_thunder_timer = randf_range(3.0, 8.0)
	_flash_power = move_toward(_flash_power, 0.0, delta * 9.0)
	_flash.light_energy = _flash_power

func _build_rain() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(.035, .62)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("9fb6d8", .34)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	_rain = MultiMeshInstance3D.new()
	_rain.name = "RainStreaks"
	_rain.multimesh = MultiMesh.new()
	_rain.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_rain.multimesh.mesh = quad
	_rain.multimesh.instance_count = RAIN_COUNT
	_rain_seed.clear()
	for index in range(RAIN_COUNT):
		var seed := Vector3(randf() * BOX.x, randf() * BOX.y - 8.0, randf() * BOX.z)
		_rain_seed.append(seed)
		_rain.multimesh.set_instance_transform(index, Transform3D(Basis(), seed))
	add_child(_rain)

func _update_rain(anchor: Vector3, delta: float) -> void:
	var origin := anchor + Vector3(-BOX.x * .5, 6.0, -BOX.z * .5)
	# 雨丝整体顺风向倾斜（绕垂直于风向的水平轴旋转）。
	var tilt_axis := Vector3(-_wind.z, 0.0, _wind.x)
	if tilt_axis.length() < .01: tilt_axis = Vector3.RIGHT
	var tilt := clampf(_wind.length() * .028, 0.0, .45)
	var basis := Basis(tilt_axis.normalized(), tilt)
	for index in range(RAIN_COUNT):
		var p: Vector3 = _rain_seed[index]
		p.y -= (FALL_SPEED + _wind.length()) * delta * (.85 + float(index % 5) * .06)
		p += _wind * delta
		if p.y < -8.0:
			p.y += BOX.y
			p.x = randf() * BOX.x
			p.z = randf() * BOX.z
		p.x = wrapf(p.x, 0.0, BOX.x)
		p.z = wrapf(p.z, 0.0, BOX.z)
		_rain_seed[index] = p
		_rain.multimesh.set_instance_transform(index, Transform3D(basis, origin + p))

func _build_leaves() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(.16, .11)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("a8763e", .85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	_leaves = MultiMeshInstance3D.new()
	_leaves.name = "WindLeaves"
	_leaves.multimesh = MultiMesh.new()
	_leaves.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_leaves.multimesh.mesh = quad
	_leaves.multimesh.instance_count = LEAF_COUNT
	for index in range(LEAF_COUNT):
		var seed := Vector3(randf() * BOX.x, randf() * 10.0 + 1.0, randf() * BOX.z)
		_leaf_seed.append(seed)
	add_child(_leaves)

func _update_leaves(anchor: Vector3, delta: float) -> void:
	var origin := anchor + Vector3(-BOX.x * .5, 0.0, -BOX.z * .5)
	for index in range(LEAF_COUNT):
		var p: Vector3 = _leaf_seed[index]
		# 落叶顺风漂移 + 缓慢下落 + 横向摇摆，旋转翻滚。
		p += (_wind * 1.6 + Vector3(sin(_time * 2.1 + index) * .5, -1.1, 0.0)) * delta
		if p.y < .2:
			p.y = 9.0 + randf() * 3.0
			p.x = randf() * BOX.x
			p.z = randf() * BOX.z
		p.x = wrapf(p.x, 0.0, BOX.x)
		p.z = wrapf(p.z, 0.0, BOX.z)
		_leaf_seed[index] = p
		var spin := Basis.from_euler(Vector3(_time * (1.3 + float(index % 3) * .4), _time * .9 + index, 0.0))
		_leaves.multimesh.set_instance_transform(index, Transform3D(spin, origin + p))

func _build_puddles(floor_y: float) -> void:
	# 水滩贴在庭院石板低处：山门前庭两片、中庭两片、镜殿前一片。
	var spots := [
		{"at": Vector2(16.2, 1.6), "r": 1.5},
		{"at": Vector2(22.6, -2.4), "r": 1.0},
		{"at": Vector2(37.5, -4.6), "r": 1.8},
		{"at": Vector2(46.0, -6.6), "r": 1.2},
		{"at": Vector2(44.5, -1.2), "r": .9},
		{"at": Vector2(58.5, -5.2), "r": 1.4},
	]
	var material := ShaderMaterial.new()
	material.shader = PUDDLE_SHADER
	for index in range(spots.size()):
		var spot: Dictionary = spots[index]
		var puddle := MeshInstance3D.new()
		puddle.name = "Puddle_%02d" % index
		# 单位 Quad（shader 内做圆形径向羽化），按半径缩放。
		var quad := QuadMesh.new()
		quad.size = Vector2(2.0, 2.0)
		puddle.mesh = quad
		puddle.material_override = material
		var at: Vector2 = spot.at
		puddle.position = Vector3(at.x, floor_y + .015, at.y)
		puddle.rotation.x = -PI / 2
		puddle.scale = Vector3(spot.r, spot.r, 1.0)
		add_child(puddle)
		_puddles.append(puddle)
