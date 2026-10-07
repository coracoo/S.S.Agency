# 仅按整段动画的保守边界内收友方编队；不改原帧、脚锚、身高或槽间距。
extends RefCounted
const Stature = preload("res://scripts/characters/character_stature.gd")
const Definition = preload("res://scripts/characters/pixel_character_definition.gd")
const EDGE_MARGIN := 16.0

static func animation_bounds(definition: Dictionary) -> Rect2:
	var manifest: Dictionary = definition.get("manifest", {})
	var canvas: Dictionary = manifest.get("canvas", {})
	var full := Rect2(0,0,float(canvas.get("w",0)),float(canvas.get("h",0)))
	# 未裁紧的旧PNG保留整个画布，不能通过alpha阈值删掉半透明特效。
	if not manifest.has("packed_frames"): return full
	var bounds := Rect2()
	var found := false
	for action in Definition.CONTEXT_ACTIONS.battle:
		for frame in manifest.get("anims", {}).get(action, {}).get("frames", []):
			var packed: Dictionary = manifest.packed_frames.get(frame, {})
			if packed.is_empty(): return full
			var part := Rect2(float(packed.offset[0]),float(packed.offset[1]),float(packed.region[2]),float(packed.region[3]))
			bounds = bounds.merge(part) if found else part
			found = true
	return bounds if found else full

static func projected_bounds(camera: Camera3D, ground: Vector3, definition: Dictionary, mirrored: bool) -> Rect2:
	var bounds := animation_bounds(definition)
	var anchor := Stature.body_anchor(definition)
	var pixel_size := Stature.world_pixel_size(definition)
	# 与正式fixed-Y billboard一致；俯角只压缩纵向，横向不能套用2D的190px/m。
	var right := Vector3(camera.global_basis.x.x,0,camera.global_basis.x.z).normalized()
	var result := Rect2()
	var first := true
	for x in [bounds.position.x,bounds.end.x]:
		for y in [bounds.position.y,bounds.end.y]:
			var horizontal: float = (x-anchor.x)*(-1.0 if mirrored else 1.0)
			var point := camera.unproject_position(ground+(right*horizontal+Vector3.UP*(anchor.y-y))*pixel_size)
			result = Rect2(point,Vector2.ZERO) if first else result.expand(point)
			first = false
	return result

static func inward_translation(bounds: Array[Rect2], width: float = 1920.0) -> float:
	if bounds.is_empty(): return 0.0
	var left := INF
	var right := -INF
	for rectangle in bounds:
		left = minf(left,rectangle.position.x)
		right = maxf(right,rectangle.end.x)
	var minimum := EDGE_MARGIN-left
	var maximum := width-EDGE_MARGIN-right
	if minimum > maximum:
		push_warning("友方动画总宽度超出镜头，需检查新素材的固定身高/画布登记")
		return (minimum+maximum)*.5
	return clampf(0.0,minimum,maximum)
