# 只读寺域总览：使用真实可走面的同一登记，不提供传送或剧情写入。
extends Control
const Layout = preload("res://scripts/campaign/act_one_layout.gd")
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
const FONT := preload("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
const REGION_LABELS := {"approach": "上山参道", "forecourt": "山门前庭", "corridor": "回廊", "procession": "纸棺庭", "mirror": "镜殿", "honden": "本殿", "central_court": "中庭", "north_walk": "侧径", "south_walk": "石径"}
var player_position := Vector3.ZERO
var definition: Dictionary = {}
var world: Dictionary = {}
func point(value: Vector3) -> Vector2:
	var scale_value := minf((size.x - 96) / 78.0, (size.y - 70) / 31.0)
	var origin := Vector2((size.x - 78.0 * scale_value) * 0.5, 26)
	return origin + Vector2(value.x + 10.0, value.z + 18.0) * scale_value
func _draw() -> void:
	# 真实可走面先合并，重叠庭院不再显示为一叠调试矩形。
	for outline in walk_outline():
		var projected := PackedVector2Array()
		for p in outline: projected.append(point(Vector3(p.x, 0, p.y)))
		draw_colored_polygon(projected, Color("223633"))
		projected.append(projected[0])
		draw_polyline(projected, Color(Kit.color("ui_line"), 0.8), 2.0, true)
	for route in route_paths():
		var projected := PackedVector2Array()
		for p in route: projected.append(point(Vector3(p.x, 0, p.y)))
		draw_polyline(projected, Color(Kit.color("ui_muted"), 0.46), 3.0, true)
	for entry in Layout.walk_rects():
		if entry.id not in ["corridor", "procession", "mirror", "honden"]: continue
		var a := point(Vector3(entry.rect.position.x, 0, entry.rect.position.y))
		var b := point(Vector3(entry.rect.end.x, 0, entry.rect.end.y))
		draw_rect(Rect2(a, b - a), Color("34443F"))
		draw_rect(Rect2(a, b - a), Color(Kit.color("ui_muted"), 0.42), false, 1.0)
	for entry in Layout.walk_rects():
		if entry.id in ["north_walk", "south_walk"]: continue
		var center: Vector2 = entry.rect.get_center()
		_label(point(Vector3(center.x, 0, center.y)) + Vector2(0, -8), str(REGION_LABELS.get(entry.id, entry.id)))
	_label(point(Vector3(-1.8, 0, -2.4)), "上山参道 · 石阶")
	for target in definition.get("interactions", []):
		if target.kind == "npc":
			draw_circle(point(Vector3(target.position[0], target.position[1], target.position[2])), 5, Kit.color("ui_selected_line"))
			continue
		var complete := false
		if target.kind == "dialogue": complete = world.get("event_flags", {}).has("dialogue:" + str(target.dialogue))
		elif target.kind == "ritual": complete = world.get("event_flags", {}).has(str(target.id))
		elif target.kind == "battle": complete = world.get("event_flags", {}).has("battle:cleared")
		if complete: continue
		var p := point(Vector3(target.position[0], target.position[1], target.position[2]))
		draw_arc(p, 7, 0, TAU, 24, Kit.color("ui_focus"), 2, true)
	var current := point(player_position)
	draw_circle(current, 10, Kit.color("ui_text"))
	draw_circle(current, 4, Kit.color("ui_accent_hover"))
	_label(current + Vector2(0, 33), "你在这里")
func walk_outline() -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = [PackedVector2Array(Layout.APPROACH_POLYGON)]
	for entry in Layout.walk_rects():
		var rect: Rect2 = entry.rect
		polygons.append(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]))
	var changed := true
	while changed:
		changed = false
		for first in range(polygons.size()):
			for second in range(first + 1, polygons.size()):
				var combined := Geometry2D.merge_polygons(polygons[first], polygons[second])
				if combined.size() == 1:
					polygons[first] = combined[0]
					polygons.remove_at(second)
					changed = true
					break
			if changed: break
	return polygons

# 中心连线只用于地图读图；每条路径均落在真实可走登记内，无传送逻辑。
func route_paths() -> Array[PackedVector2Array]:
	var centers: Dictionary = {}
	for entry in Layout.walk_rects(): centers[entry.id] = entry.rect.get_center()
	return [
		PackedVector2Array([Vector2(-8, 0.35), Vector2(8.6, 0.35), centers.forecourt, centers.corridor, centers.central_court, centers.honden]),
		PackedVector2Array([centers.mirror, centers.central_court, centers.procession]),
	]

# 轻量底托与安全边距只改善阅读，不改地图坐标或通行登记。
func label_rect(where: Vector2, label: String) -> Rect2:
	var text_size := FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	var label_size := text_size + Vector2(16, 10)
	var start := where - Vector2(label_size.x * 0.5, label_size.y - 6)
	start.x = clampf(start.x, 10.0, maxf(10.0, size.x - label_size.x - 10.0))
	start.y = clampf(start.y, 10.0, maxf(10.0, size.y - label_size.y - 10.0))
	return Rect2(start, label_size)
func _label(where: Vector2, label: String) -> void:
	var bounds := label_rect(where, label)
	draw_rect(bounds, Color(Kit.color("ui_ink"), 0.88))
	draw_string(FONT, bounds.position + Vector2(8, 5 + FONT.get_ascent(24)), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Kit.color("ui_text"))
