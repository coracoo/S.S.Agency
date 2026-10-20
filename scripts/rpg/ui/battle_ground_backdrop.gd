extends "res://scripts/rpg/ui/battle_world_backdrop.gd"
## 战场地面接触：将屏幕脚点映射到已登记的真实地表。
## 原相机、二维站位、近战 home/return、资源和战斗规则均由原实现持有。

const STAGING_V4 = preload("res://scripts/rpg/ui/battle_scene_staging.gd")
const SURFACE_PREFIXES := ["01_Terrain_", "02_Path_Flat_Flagstones_", "03_Stone_Stairs_", "04_Upper_Landing"]
const GROUND_CELL_SIZE := 64.0
const RAY_EPSILON := 0.000001

var staging_v4_report: Dictionary = {}
var _ground_triangles: Array[Dictionary] = []
var _ground_cells: Dictionary = {}
var _ground_meshes: Array[Dictionary] = []
var _ground_cache_ready := false
var _ground_fallback_count := 0

func configure(world: Dictionary, depth_enabled: bool = true) -> void:
	super.configure(world, depth_enabled)
	if not _ground_cache_ready:
		_build_ground_cache()
	if staging_v4_report.is_empty():
		staging_v4_report = STAGING_V4.apply(self)

func _build_ground_cache() -> void:
	if not is_instance_valid(geometry) or not is_instance_valid(camera):
		return
	var approach := geometry.get_node_or_null("ApproachArt/OriginalApproach") as Node3D
	if approach == null:
		return
	_ground_triangles.clear()
	_ground_cells.clear()
	_ground_meshes.clear()
	for candidate in approach.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := candidate as MeshInstance3D
		var allowed := false
		for prefix in SURFACE_PREFIXES:
			if str(mesh_node.name).begins_with(prefix):
				allowed = true
				break
		if not allowed or mesh_node.mesh == null:
			continue
		var count_before := _ground_triangles.size()
		var source_faces := 0
		var missing_normals := false
		var normal_basis := mesh_node.global_basis.inverse().transposed()
		for surface in range(mesh_node.mesh.get_surface_count()):
			var arrays: Array = mesh_node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				indices = arrays[Mesh.ARRAY_INDEX]
			var count := indices.size() if not indices.is_empty() else vertices.size()
			source_faces += count / 3
			if normals.size() != vertices.size():
				missing_normals = true
				continue
			for index in range(0, count - 2, 3):
				var ia := indices[index] if not indices.is_empty() else index
				var ib := indices[index + 1] if not indices.is_empty() else index + 1
				var ic := indices[index + 2] if not indices.is_empty() else index + 2
				var a: Vector3 = mesh_node.global_transform * vertices[ia]
				var b: Vector3 = mesh_node.global_transform * vertices[ib]
				var c: Vector3 = mesh_node.global_transform * vertices[ic]
				var normal: Vector3 = normal_basis * (normals[ia] + normals[ib] + normals[ic])
				# 读源法线排除石板底面，避免双面材质/绕序差异误判可站面。
				if normal.length_squared() < 0.0000000001 or normal.normalized().y < 0.15:
					continue
				_cache_ground_triangle(a, b, c, normal.normalized(), str(geometry.get_path_to(mesh_node)))
		_ground_meshes.append({"node": str(geometry.get_path_to(mesh_node)), "source_faces": source_faces, "cached_faces": _ground_triangles.size() - count_before, "missing_normals": missing_normals})
	_ground_cache_ready = not _ground_triangles.is_empty()

func _cache_ground_triangle(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, node_path: String) -> void:
	var triangle_index := _ground_triangles.size()
	_ground_triangles.append({"a": a, "b": b, "c": c, "normal": normal, "node": node_path})
	var projected := Rect2(camera.unproject_position(a), Vector2.ZERO)
	projected = projected.expand(camera.unproject_position(b)).expand(camera.unproject_position(c))
	var first := _ground_cell(projected.position)
	var last := _ground_cell(projected.end)
	for cell_y in range(first.y, last.y + 1):
		for cell_x in range(first.x, last.x + 1):
			var cell := Vector2i(cell_x, cell_y)
			if not _ground_cells.has(cell):
				_ground_cells[cell] = []
			_ground_cells[cell].append(triangle_index)

func _ground_point(screen: Vector2) -> Vector3:
	var hit := sample_ground(screen)
	if hit.get("ok", false):
		return hit.point
	_ground_fallback_count += 1
	return super._ground_point(screen)

## 返回真实相机射线最近的合法地表；不包含石盆、灯、树或角色。
func sample_ground(screen: Vector2) -> Dictionary:
	if not _ground_cache_ready:
		_build_ground_cache()
	if not _ground_cache_ready:
		return {"ok": false, "reason": "approach surface cache unavailable", "screen": _point(screen)}
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen).normalized()
	var nearest := INF
	var selected := -1
	var candidates: Array = _ground_cells.get(_ground_cell(screen), [])
	for value in candidates:
		var index := int(value)
		var triangle: Dictionary = _ground_triangles[index]
		var distance := _ray_distance(origin, direction, triangle.a, triangle.b, triangle.c)
		if distance >= 0.0 and distance < nearest:
			nearest = distance
			selected = index
	if selected < 0:
		return {"ok": false, "reason": "camera ray misses whitelisted ground", "screen": _point(screen), "tested_faces": candidates.size()}
	var point := origin + direction * nearest
	return {"ok": true, "point": point, "node": _ground_triangles[selected].node, "normal": _vector(_ground_triangles[selected].normal), "screen": _point(screen), "distance": nearest, "tested_faces": candidates.size()}

func ground_contact_error(world_foot: Vector3) -> float:
	var record := ground_contact_record(world_foot)
	return float(record.get("error_m", INF))

func ground_contact_record(world_foot: Vector3) -> Dictionary:
	var screen := camera.unproject_position(world_foot)
	var hit := sample_ground(screen)
	if not hit.get("ok", false):
		return {"ok": false, "world_foot": _vector(world_foot), "screen": _point(screen), "error_m": INF, "reason": hit.get("reason", "ground miss")}
	var expected: Vector3 = hit.point
	return {"ok": true, "world_foot": _vector(world_foot), "surface_point": _vector(expected), "screen": _point(screen), "surface_node": hit.node, "error_m": world_foot.distance_to(expected), "vertical_error_m": absf(world_foot.y - expected.y), "tested_faces": hit.tested_faces}

## 当前真正使用的紧凑 Atlas 片；中央 alpha 下缘只是诊断，不能自动当作鞋底。
func visual_anchor_diagnostics(actor_id: String) -> Dictionary:
	if not actor_entries.has(actor_id):
		return {"ok": false, "reason": "actor not bound"}
	var body: Sprite3D = actor_entries[actor_id].body
	if body.texture == null:
		return {"ok": false, "reason": "body texture unavailable"}
	var image: Image = body.texture.get_image()
	if image == null or image.is_empty():
		return {"ok": false, "reason": "body texture image unavailable"}
	var anchor_x := float(image.get_width()) * 0.5 + (body.offset.x if body.flip_h else -body.offset.x)
	var anchor_y := float(image.get_height()) * 0.5 + body.offset.y
	var pixels_per_world_y := absf(camera.unproject_position(body.global_position + Vector3.UP).y - camera.unproject_position(body.global_position).y)
	var rows: Array[Dictionary] = []
	for half_width in [20, 40, 60, 80]:
		var left := maxi(0, floori(anchor_x - half_width))
		var right := mini(image.get_width() - 1, ceili(anchor_x + half_width))
		for threshold in [0.2, 0.8]:
			var bottom := -1
			for y in range(image.get_height() - 1, -1, -1):
				for x in range(left, right + 1):
					if image.get_pixel(x, y).a >= threshold:
						bottom = y
						break
				if bottom >= 0:
					break
			var gap := anchor_y - float(bottom + 1) if bottom >= 0 else INF
			rows.append({"half_width_texture_px": half_width, "alpha_threshold": threshold, "x_range": [left, right], "bottom_row": bottom, "registered_minus_alpha_edge_texture_px": gap, "registered_minus_alpha_edge_screen_px": gap * body.pixel_size * pixels_per_world_y})
	var logical: Rect2 = body.get_meta("logical_frame_rect", Rect2())
	return {"ok": true, "actor_id": actor_id, "rendered_action": body.get_meta("rendered_action", ""), "rendered_frame": body.get_meta("rendered_action_frame", -1), "texture_size": [image.get_width(), image.get_height()], "logical_frame_rect": [logical.position.x, logical.position.y, logical.size.x, logical.size.y], "registered_anchor_texture_local": [anchor_x, anchor_y], "body_offset": _point(body.offset), "flip_h": body.flip_h, "rows": rows, "qualification": "current packed-frame alpha-band diagnostics only; cape or weapon pixels may extend below visible boot soles"}

func ground_diagnostics() -> Dictionary:
	return {"trial_only": true, "method": "cached upward source-normal triangles / actual camera ray / nearest double-sided intersection", "camera_changed": false, "source_screen_feet_changed": false, "native_melee_changed": false, "physics_colliders_added": false, "scene_region": scene_region, "cache_ready": _ground_cache_ready, "surface_prefixes": SURFACE_PREFIXES, "surface_meshes": _ground_meshes.duplicate(true), "cached_triangles": _ground_triangles.size(), "screen_cells": _ground_cells.size(), "flat_plane_fallback_count": _ground_fallback_count, "staging": staging_v4_report.duplicate(true)}

static func _ground_cell(screen: Vector2) -> Vector2i:
	return Vector2i(floori(screen.x / GROUND_CELL_SIZE), floori(screen.y / GROUND_CELL_SIZE))

## 双面 Moller-Trumbore；不依赖物理世界下一帧同步，也不创建碰撞体。
static func _ray_distance(origin: Vector3, direction: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var edge_one := b - a
	var edge_two := c - a
	var h := direction.cross(edge_two)
	var determinant := edge_one.dot(h)
	if absf(determinant) < RAY_EPSILON:
		return -1.0
	var inverse := 1.0 / determinant
	var offset := origin - a
	var u := inverse * offset.dot(h)
	if u < -RAY_EPSILON or u > 1.0 + RAY_EPSILON:
		return -1.0
	var q := offset.cross(edge_one)
	var v := inverse * direction.dot(q)
	if v < -RAY_EPSILON or u + v > 1.0 + RAY_EPSILON:
		return -1.0
	var distance := inverse * edge_two.dot(q)
	return distance if distance >= 0.0 else -1.0

static func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func _point(value: Vector2) -> Array:
	return [value.x, value.y]
