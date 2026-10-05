# 第一幕共享坐标与可走面登记；剧情夜次与玩家当前所在地区互相独立。
class_name CampaignActOneLayout
extends RefCounted
const ID := "act_one_connected_v1"
const TEMPLE_HEIGHT := 2.89
const OFFSETS := {
	1: Vector3.ZERO,
	2: Vector3(25.0, 2.86, -7.0),
	3: Vector3(43.0, 2.86, 4.0),
	4: Vector3(43.0, 2.86, -13.0),
	5: Vector3(61.0, 2.86, -5.0),
}
const APPROACH_POLYGON := [Vector2(-9.05, -0.72), Vector2(-0.25, -0.72), Vector2(0.6, -0.97), Vector2(7.18, -1.85), Vector2(9.6, -1.85), Vector2(9.6, 0.98), Vector2(7.18, 0.98), Vector2(0.6, 1.63), Vector2(-0.6, 2.12), Vector2(-9.05, 2.12)]

static func bounds() -> Dictionary:
	return {"x": [-9.05, 68.0], "z": [-18.0, 11.0], "y": [-0.5, 6.0]}

static func night_offset(id: int) -> Vector3:
	return OFFSETS.get(id, Vector3.ZERO)

static func to_world(position: Array, night_id: int) -> Array:
	var offset := night_offset(night_id)
	return [position[0] + offset.x, position[1] + offset.y, position[2] + offset.z]

# 只列寺内新地面，原上山路沿用坡道碰撞而非近似矩形平板。
# 具体建筑优先于重叠庭院，以便地区提示与剧情距离门控稳定。
static func walk_rects() -> Array[Dictionary]:
	return [
		{"id": "corridor", "rect": Rect2(18.2, -10.0, 13.6, 6.0), "height": TEMPLE_HEIGHT},
		{"id": "procession", "rect": Rect2(37.1, 1.0, 11.8, 6.0), "height": TEMPLE_HEIGHT},
		{"id": "mirror", "rect": Rect2(37.2, -16.1, 11.6, 6.1), "height": TEMPLE_HEIGHT},
		{"id": "honden", "rect": Rect2(55.2, -8.1, 11.6, 6.2), "height": TEMPLE_HEIGHT},
		{"id": "forecourt", "rect": Rect2(9.5, -5.0, 19.5, 13.0), "height": TEMPLE_HEIGHT},
		{"id": "central_court", "rect": Rect2(29.0, -10.0, 26.6, 11.0), "height": TEMPLE_HEIGHT},
		{"id": "north_walk", "rect": Rect2(31.0, -13.8, 24.0, 4.0), "height": TEMPLE_HEIGHT},
		{"id": "south_walk", "rect": Rect2(27.0, 1.0, 28.0, 6.5), "height": TEMPLE_HEIGHT},
	]

static func region_at(position: Vector3) -> String:
	if not position.is_finite(): return ""
	var point := Vector2(position.x, position.z)
	for entry in walk_rects():
		if entry.rect.has_point(point): return entry.id
	if Geometry2D.is_point_in_polygon(point, PackedVector2Array(APPROACH_POLYGON)): return "approach"
	return ""

static func surface_height(position: Vector3) -> float:
	var region := region_at(position)
	if region.is_empty(): return NAN
	if region != "approach": return TEMPLE_HEIGHT
	# 与原倾斜Box的顶平面一致；两端分别接0.03低台和2.89山门平台。
	var slope := 2.86 / 6.435
	var plane := 1.3686 + (position.x - 3.658) * slope + 0.1 * sqrt(1.0 + slope * slope)
	return clampf(plane, 0.03, TEMPLE_HEIGHT)
