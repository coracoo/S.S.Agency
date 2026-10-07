extends RefCounted
## 仅供3D绘制的轻量图集视图；原SpriteFrames/逻辑画布/时序完全不变。
## 缓存由当前演员拥有，换定义时clear，不建立全局强引用或复制PNG像素。
var _views: Dictionary = {}

func texture_for(source: Texture2D) -> Texture2D:
	if not source is AtlasTexture: return source
	if not _views.has(source):
		var view := AtlasTexture.new()
		view.atlas = source.atlas
		view.region = source.region
		view.filter_clip = source.filter_clip
		_views[source] = view
	return _views[source]

static func logical_rect(source: Texture2D) -> Rect2:
	if source is AtlasTexture: return Rect2(source.margin.position,source.region.size)
	return Rect2(Vector2.ZERO,source.get_size())

static func offset_for(source: Texture2D, anchor: Vector2, flipped: bool) -> Vector2:
	var rect := logical_rect(source)
	var center := rect.get_center()
	# 原2D合成将像素p翻到W-p，脚锚保持原anchor；不能只翻Sprite3D的UV。
	# 紧凑片内像素q: 非镜像x=offset+w*(-.5)+q；镜像x=offset+w*.5-q。
	# 令两式分别等于(x+q)-ax及W-(x+q)-ax，即得本固定锚补偿。
	if flipped: center.x = source.get_width()-center.x
	return Vector2(center.x-anchor.x,anchor.y-center.y)

func clear() -> void:
	_views.clear()
