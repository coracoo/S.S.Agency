# 统一使用已批准高清帧的原始像素；AtlasTexture只是UI取景，不生成或改绘素材。
class_name IdentityPortraits
extends RefCounted
const Bundle = preload("res://scripts/characters/party_asset_bundle.gd")
const Definition = preload("res://scripts/characters/pixel_character_definition.gd")
const SPEAKERS := {"rinne": "rinne", "hakuyo": "mint", "mint": "mint", "guard": "guard", "homura": "homura", "healer": "healer", "controller": "controller"}
# 用户要求对话统一腰部半身。仅收紧已认可原帧的UI窗口，保持2:3；头像/地图/战斗原图均不改。
const REGIONS := {
	"rinne": {"portrait": Rect2(510, 24, 344, 516), "avatar": Rect2(560, 45, 240, 240)},
	"mint": {"portrait": Rect2(456, 24, 368, 552), "avatar": Rect2(520, 25, 220, 220)},
	"guard": {"portrait": Rect2(408, 32, 352, 528), "avatar": Rect2(485, 60, 240, 240)},
	"homura_mage": {"portrait": Rect2(330, 24, 336, 504), "avatar": Rect2(380, 24, 240, 240)},
	"homura_sword": {"portrait": Rect2(664, 24, 352, 528), "avatar": Rect2(700, 50, 240, 240)},
	"healer": {"portrait": Rect2(360, 24, 360, 540), "avatar": Rect2(370, 35, 240, 240)},
	"controller": {"portrait": Rect2(392, 24, 352, 528), "avatar": Rect2(390, 35, 240, 240)}
}
static func identity_for_speaker(speaker: String) -> String:
	return SPEAKERS.get(speaker, "")
static func from_definition(definition: Dictionary, identity_id: String, kind: String) -> Dictionary:
	if not definition.get("ok", false) or not definition.get("frames") is SpriteFrames or not definition.get("manifest") is Dictionary: return _failure("已选高清人物尚未加载")
	var manifest: Dictionary = definition.get("manifest", {})
	var key := Bundle.asset_key(identity_id, str(manifest.get("form_id", "")))
	if key.is_empty() or not REGIONS.has(key) or not REGIONS[key].has(kind): return _failure("人物或UI取景未登记")
	if manifest.get("identity_id") != identity_id: return _failure("人物立绘与已选高清身份不符")
	if manifest.has("portrait_source_manifest"):
		var portrait_definition := _load_portrait_source(manifest, identity_id, key)
		if not portrait_definition.get("ok", false): return portrait_definition
		return from_definition(portrait_definition, identity_id, kind)
	if manifest.get("identity_id") != identity_id or manifest.get("dir") != "res://assets/chars/pixel/%s/high_detail_complete/frames/" % key: return _failure("人物立绘与已选高清身份不符")
	if not manifest.get("anims") is Dictionary or not manifest.anims.get("idle") is Dictionary or not manifest.anims.idle.get("frames") is Array or manifest.anims.idle.frames.is_empty() or not manifest.anims.idle.frames[0] is String: return _failure("人物首帧来源不完整")
	var frames: SpriteFrames = definition.frames
	if not frames.has_animation(&"idle") or frames.get_frame_count(&"idle") < 1: return _failure("人物待机首帧缺失")
	var texture := frames.get_frame_texture(&"idle", 0)
	if texture == null: return _failure("人物首帧不可用")
	var region: Rect2 = REGIONS[key][kind]
	if not Rect2(Vector2.ZERO, texture.get_size()).encloses(region): return _failure("人物取景超出真实画布")
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = region
	atlas.filter_clip = true
	return {"ok": true, "error": "", "texture": atlas, "identity_id": identity_id, "region": region, "key": "identity:%s:%s" % [key, kind], "source_path": str(manifest.dir) + str(manifest.anims.idle.frames[0]) + ".png"}
# 标题只读取凛音idle，不提前加载其余角色或整套战斗动作；共享Definition弱纹理缓存。
static func load_idle_definition(identity_id: String, form_id: String = "") -> Dictionary:
	var key := Bundle.asset_key(identity_id, form_id)
	if not Bundle.MANIFESTS.has(key): return _failure("标题人物未登记")
	var path: String = Bundle.MANIFESTS[key]
	if not FileAccess.file_exists(path): return _failure("高清人物清单缺失")
	return from_idle_manifest(JSON.parse_string(FileAccess.get_file_as_string(path)), identity_id)
static func from_idle_manifest(value: Variant, identity_id: String) -> Dictionary:
	if not value is Dictionary: return _failure("高清人物清单身份无效")
	var key := Bundle.asset_key(identity_id, str(value.get("form_id", "")))
	if not Bundle.MANIFESTS.has(key) or value.get("identity_id") != identity_id: return _failure("高清人物清单身份无效")
	var manifest: Dictionary = value
	if manifest.has("portrait_source_manifest"): return _load_portrait_source(manifest, identity_id, key)
	if not manifest.get("canvas") is Dictionary or not manifest.get("anims") is Dictionary or not manifest.anims.get("idle") is Dictionary: return _failure("高清人物清单缺少画布或待机")
	var canvas: Dictionary = manifest.canvas
	for field in ["w", "h", "content_height_px", "height_m"]:
		if not Definition._number(canvas.get(field)) or float(canvas[field]) <= 0: return _failure("高清画布数值非法：" + field)
	if canvas.w != floor(canvas.w) or canvas.h != floor(canvas.h) or canvas.w > 4096 or canvas.h > 4096 or canvas.content_height_px > canvas.h: return _failure("高清画布尺寸非法")
	if not canvas.get("anchor") is Array or canvas.anchor.size() != 2 or not Definition._number(canvas.anchor[0]) or not Definition._number(canvas.anchor[1]): return _failure("高清脚锚类型非法")
	if canvas.anchor[0] < 0 or canvas.anchor[0] >= canvas.w or canvas.anchor[1] < 0 or canvas.anchor[1] >= canvas.h: return _failure("高清脚锚超出画布")
	var idle: Dictionary = manifest.anims.idle
	if manifest.get("dir") != "res://assets/chars/pixel/%s/high_detail_complete/frames/" % key or not idle.get("frames") is Array or not idle.get("durations_ms") is Array or idle.frames.is_empty() or idle.frames.size() != idle.durations_ms.size(): return _failure("高清待机路径或时序非法")
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"idle")
	frames.set_animation_speed(&"idle", 1.0)
	frames.set_animation_loop(&"idle", true)
	for index in range(idle.frames.size()):
		if not idle.frames[index] is String or not Definition._number(idle.durations_ms[index]) or float(idle.durations_ms[index]) <= 0: return _failure("高清待机元素类型非法")
		var name: String = idle.frames[index]
		if name.is_empty() or name.contains("/") or name.contains("\\") or name.contains(".."): return _failure("高清待机帧名或时长非法")
		var texture := Definition._load_png_texture(str(manifest.dir) + name + ".png", int(canvas.w), int(canvas.h))
		if texture == null: return _failure("高清待机帧缺失：" + name)
		frames.add_frame(&"idle", texture, float(idle.durations_ms[index]) / 1000.0)
	if idle.get("pingpong", false):
		for index in range(idle.frames.size() - 2, 0, -1): frames.add_frame(&"idle", frames.get_frame_texture(&"idle", index), float(idle.durations_ms[index]) / 1000.0)
	return {"ok": true, "errors": [], "manifest": manifest, "frames": frames, "layer_frames": []}

# 视频动作的画布和取景不同，UI只能显式回到同身份已批准的原始高清立绘。
static func _load_portrait_source(manifest: Dictionary, identity_id: String, key: String) -> Dictionary:
	var path := "res://assets/chars/pixel/%s/high_detail_complete/manifest.json" % key
	if manifest.get("portrait_source_manifest") != path or not FileAccess.file_exists(path): return _failure("人物立绘原始来源无效")
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not source is Dictionary or source.has("portrait_source_manifest") or Bundle.asset_key(str(source.get("identity_id", "")), str(source.get("form_id", ""))) != key:
		return _failure("人物立绘原始身份无效")
	return from_idle_manifest(source, identity_id)

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "errors": [message], "texture": null}
