# 校验运行清单及图集原字节。素材批准与游戏呈现批准是两道独立门。
extends RefCounted
const REGISTRY := "res://assets/effects/imagegen_spells/registry.json"
static func _failure(reason: String) -> Dictionary: return {"ok":false,"reason":reason}
static func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
static func _true(value: Variant) -> bool: return value is bool and value
static func load_effect(skill: String,registry_path: String = REGISTRY,preview_pending: bool = false) -> Dictionary:
	var registry := _json(registry_path)
	if registry.get("schema_version") != 2: return _failure("invalid_registry")
	if not preview_pending and not _true(registry.get("production_renderer_enabled")): return _failure("production_disabled")
	var entry: Variant = registry.get("effects",{}).get(skill)
	if not entry is Dictionary: return _failure("unregistered")
	if not _true(entry.get("approved_for_runtime")): return _failure("art_unapproved")
	if not preview_pending and entry.get("gameplay_qa_pending",true) != false: return _failure("gameplay_qa_pending")
	var path := str(entry.get("manifest",""))
	var manifest := _json(path)
	if manifest.get("schema_version") != 1 or manifest.get("skill_id") != skill: return _failure("invalid_manifest")
	if FileAccess.get_sha256(path) != entry.get("manifest_sha256"): return _failure("receipt_mismatch")
	var atlas_path := str(registry.get("asset_root","")).path_join(str(manifest.get("runtime_atlas","")))
	if not FileAccess.file_exists(atlas_path) or FileAccess.get_sha256(atlas_path) != manifest.get("runtime_atlas_sha256"): return _failure("atlas_hash_mismatch")
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(atlas_path)) != OK: return _failure("invalid_png")
	if image.get_width()*image.get_height()>16777216: return _failure("atlas_budget")
	var effect := compile_frames(manifest,ImageTexture.create_from_image(image),float(entry.get("runtime_scale",0)),float(entry.get("display_size_px",0)))
	if not effect.ok: return effect
	effect.merge({"skill_id":skill,"manifest_path":path,"atlas_path":atlas_path,"atlas_sha256":manifest.runtime_atlas_sha256,"texture_bytes":image.get_data_size(),"preview_pending":preview_pending,"particles":entry.get("particles",[])},true)
	return effect

# 清单明确坐标和阶段，不推测列数、格子尺寸或神经输出帧数。
static func compile_frames(manifest: Dictionary,atlas: Texture2D,runtime_scale: float,display_size: float) -> Dictionary:
	if atlas==null or not is_finite(runtime_scale) or runtime_scale<=0 or not is_finite(display_size) or display_size<=0: return _failure("invalid_scale")
	var source: Variant = manifest.get("frames")
	var phases: Variant = manifest.get("phases")
	if not source is Array or source.is_empty() or source.size()>256 or source.size()!=int(manifest.get("frame_count",0)) or not phases is Dictionary: return _failure("invalid_frames")
	var frames := {}
	for item in source:
		if not item is Dictionary: return _failure("invalid_frame")
		var id := int(item.get("frame",0))
		var rect: Variant = item.get("atlas_native_xywh")
		var anchor: Variant = item.get("anchor_runtime_px")
		var duration := float(item.get("nominal_duration_ms",0))
		if id<=0 or frames.has(id) or not rect is Array or rect.size()!=4 or not anchor is Array or anchor.size()!=2 or not is_finite(duration) or duration<=0: return _failure("invalid_frame")
		var coords: Array[float] = []
		for value in rect:
			if not (value is int or value is float) or not is_finite(float(value)) or not is_equal_approx(float(value)*runtime_scale,roundf(float(value)*runtime_scale)): return _failure("invalid_region")
			coords.append(float(value)*runtime_scale)
		var region := Rect2(coords[0],coords[1],coords[2],coords[3])
		if not region.has_area() or not Rect2(Vector2.ZERO,atlas.get_size()).encloses(region): return _failure("invalid_region")
		var point := Vector2(float(anchor[0]),float(anchor[1]))
		if not point.is_finite() or point.x<0 or point.y<0 or point.x>region.size.x or point.y>region.size.y: return _failure("invalid_anchor")
		var texture := AtlasTexture.new(); texture.atlas=atlas; texture.region=region
		frames[id] = {"frame":id,"phase":str(item.get("phase","")),"texture":texture,"anchor":point,"duration_ms":duration,"tail":bool(item.get("recovery_tail",false)),"scale":display_size/maxf(region.size.x,region.size.y)}
	for required in ["cast","travel","hit"]:
		if not phases.get(required) is Array or phases[required].is_empty(): return _failure("missing_phase")
	for phase in phases:
		if not phases[phase] is Array: return _failure("invalid_phase")
		var seen := {}
		for id in phases[phase]:
			var key := int(id)
			if not frames.has(key) or seen.has(key): return _failure("invalid_phase")
			if phase=="recovery_tail":
				if not frames[key].tail or frames[key].phase!="hit": return _failure("invalid_tail")
			elif frames[key].phase!=phase: return _failure("invalid_phase")
			seen[key]=true
	return {"ok":true,"frames":frames,"phases":phases.duplicate(true),"atlas":atlas,"display_size":display_size}

# 时间只重定标真实帧权重；p>=1结束。低频状态循环由调用者显式取模。
static func phase_frame(effect: Dictionary,phase: String,progress: float) -> Dictionary:
	if not is_finite(progress) or progress<0 or progress>=1: return {}
	var ids: Array = effect.get("phases",{}).get(phase,[])
	var total := 0.0
	for id in ids: total += float(effect.frames[int(id)].duration_ms)
	var at := progress*total
	for id in ids:
		var frame: Dictionary = effect.frames[int(id)]
		at -= float(frame.duration_ms)
		if at<0: return frame
	return {}
