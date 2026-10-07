extends Node3D
## 单个演员拥有的短残影。只引用原帧像素，独立复制图集视图，不重绘人体。
## anchor 必须与 live Sprite3D 使用的有效逻辑脚锚相同（包括调用方已有的镜像补偿）。
## world_root 是拍摄当下的脚根全局变换，须包含近战闪身等实际位移。

const TightFrame = preload("res://scripts/characters/tight_sprite_frame.gd")

var ghost_alpha := .18
var ghost_scale := 1.05
var lifetime := .16
var max_ghosts := 3

var _actor_id := ""
var _ghosts: Array[Dictionary] = []

func _init() -> void:
	set_process(false)

func bind_actor(actor_id: String) -> void:
	# 同身份也可能已换场景/定义；每次绑定都释放上一批引用。
	cancel()
	_actor_id = actor_id

func capture(source: Texture2D, anchor: Vector2, world_root: Transform3D, pixel_size: float, flipped: bool = false, tint: Color = Color.WHITE) -> Sprite3D:
	if _actor_id.is_empty() or not is_inside_tree() or source == null or pixel_size <= 0:
		return null
	# 视口/动画纹理会在拍摄后继续改变，不可冒充被冻结的源帧。
	if source is ViewportTexture or source is AnimatedTexture:
		return null
	while _ghosts.size() >= clampi(max_ghosts, 3, 4):
		_retire(0)
	var body := Sprite3D.new()
	body.name = "SnapshotGhost_" + _actor_id
	body.top_level = true
	body.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	body.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	body.render_priority = -1
	body.texture = _snapshot_view(source)
	body.offset = TightFrame.offset_for(source, anchor, flipped)
	body.pixel_size = pixel_size
	body.flip_h = flipped
	var alpha := clampf(ghost_alpha, .12, .24) * clampf(tint.a, 0, 1)
	body.modulate = Color(tint.r, tint.g, tint.b, alpha)
	add_child(body)
	# 放大的是以脚根为原点的整张精灵，不能把偏移再乘一次或重定位到图像中心。
	# top_level 保证父节点和真人继续移动时，已拍残影不会被一起拖走。
	body.global_transform = world_root.scaled_local(Vector3.ONE * clampf(ghost_scale, 1.03, 1.08))
	_ghosts.append({"body":body, "age":0.0, "life":clampf(lifetime, .12, .20), "alpha":alpha})
	set_process(true)
	return body

func active_count() -> int:
	return _ghosts.size()

func cancel() -> void:
	while not _ghosts.is_empty():
		_retire(_ghosts.size() - 1)
	set_process(false)

func _process(delta: float) -> void:
	for index in range(_ghosts.size() - 1, -1, -1):
		var record := _ghosts[index]
		var body := record.body as Sprite3D
		record.age += maxf(delta, 0.0)
		if not is_instance_valid(body) or record.age >= record.life:
			_retire(index)
		else:
			var tint := body.modulate
			tint.a = record.alpha * (1.0 - record.age / record.life)
			body.modulate = tint
	if _ghosts.is_empty():
		set_process(false)

func _exit_tree() -> void:
	cancel()
	_actor_id = ""

func _retire(index: int) -> void:
	var record := _ghosts[index]
	_ghosts.remove_at(index)
	var body := record.body as Sprite3D
	if is_instance_valid(body):
		# 即刻断开纹理强引用并隐藏；节点留到安全的队列删除点，退出树时也可调用。
		body.texture = null
		body.hide()
		body.queue_free()

static func _snapshot_view(source: Texture2D) -> Texture2D:
	if not source is AtlasTexture:
		return source
	var view := AtlasTexture.new()
	view.atlas = source.atlas
	view.region = source.region
	view.filter_clip = source.filter_clip
	return view
