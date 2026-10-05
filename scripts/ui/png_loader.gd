class_name PngLoader
extends RefCounted
const LegacyPaths = preload("res://scripts/characters/legacy_asset_paths.gd")
## PNG 贴图加载器：优先 FileAccess 直读原始字节（编辑器/目录直跑，无重压缩损耗）；
## 导出 pck 内 png 被导入器重映射、FileAccess 读不到原始文件 → 回退 ResourceLoader
## 取导入贴图（.ctex remap），两端行为一致。
## （ProjectSettings.globalize_path + Image.load 在导出包里是 OS 死路径——试玩包验证实锤）

static func _is_pot(v: int) -> bool:
	return v > 0 and (v & (v - 1)) == 0

static var _cache: Dictionary = {} # path -> Texture2D：同图不重复解码/生成 mipmap（出牌补牌/视差层高频复用）

static func clear_cache() -> void:
	_cache.clear()

static func load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path]
	var tex := _load_fresh(path)
	if tex != null:
		_cache[path] = tex
	return tex

static func _load_fresh(path: String) -> Texture2D:
	path = LegacyPaths.resolve(path)
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		var img := Image.new()
		if img.load_png_from_buffer(f.get_buffer(f.get_length())) == OK:
			# 手动建贴图无导入管线的 mipmap 链，大屏缩小时糊成一片：
			# 幂次尺寸图现场生成 mipmap，配合三线性过滤保清晰
			if _is_pot(img.get_width()) and _is_pot(img.get_height()) and not img.has_mipmaps():
				img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
		push_warning("[PngLoader] PNG 解码失败: %s" % path)
	# 导出 pck：原始文件不在包里，走导入器重映射
	if ResourceLoader.exists(path):
		var t: Resource = ResourceLoader.load(path)
		if t is Texture2D:
			return t
		push_warning("[PngLoader] 资源不是贴图: %s" % path)
		return null
	push_warning("[PngLoader] 文件打开失败: %s" % path)
	return null
