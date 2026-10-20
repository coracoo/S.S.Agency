extends RefCounted
## 仅改变本次场景实例；不修改资源、角色脚点、相机或深度模式。

const BASIN_MESH_NAMES := [
	"30_Basin_Carved_Stone_And_Bamboo",
	"30_Basin_Cold_Water_Reflection",
	"31_Basin_Rim_Petals",
	"32_Basin_Stone_Setting",
]
const BASIN_LIGHT_POSITION := Vector3(0.12, 1.25, 1.7)

static func apply(backdrop: Node) -> Dictionary:
	var result := {
		"status": "blocked",
		"hidden_meshes": [],
		"hidden_lights": [],
		"missing_meshes": [],
		"errors": [],
		"camera_changed": false,
		"actor_positions_changed": false,
		"ground_contact_changed": false,
		"depth_mode_changed": false,
	}
	if not is_instance_valid(backdrop):
		result.errors.append("backdrop unavailable")
		return result
	var geometry := backdrop.get("geometry") as Node3D
	if geometry == null:
		result.errors.append("configured geometry unavailable")
		return result
	var art := geometry.get_node_or_null("ApproachArt") as Node3D
	var approach := geometry.get_node_or_null("ApproachArt/OriginalApproach") as Node3D
	if art == null or approach == null:
		result.errors.append("this trial requires ApproachArt/OriginalApproach")
		return result
	for mesh_name in BASIN_MESH_NAMES:
		var piece := approach.find_child(mesh_name, true, false) as MeshInstance3D
		if piece == null:
			result.missing_meshes.append(mesh_name)
			continue
		var record := {
			"node": str(geometry.get_path_to(piece)),
			"visible_before": piece.visible,
			"local_position": _vector(piece.position),
			"surface_count": piece.mesh.get_surface_count() if piece.mesh != null else 0,
		}
		piece.hide()
		record["visible_after"] = piece.visible
		result.hidden_meshes.append(record)
	for child in art.get_children():
		var light := child as OmniLight3D
		if light == null or light.position.distance_to(BASIN_LIGHT_POSITION) > 0.001:
			continue
		var record := {
			"node": str(geometry.get_path_to(light)),
			"visible_before": light.visible,
			"local_position": _vector(light.position),
			"color": [light.light_color.r, light.light_color.g, light.light_color.b, light.light_color.a],
			"energy": light.light_energy,
			"range": light.omni_range,
		}
		light.hide()
		record["visible_after"] = light.visible
		result.hidden_lights.append(record)
	if result.hidden_lights.size() != 1:
		result.errors.append("expected exactly one basin light at (0.12, 1.25, 1.7)")
	if result.missing_meshes.is_empty() and result.errors.is_empty():
		result.status = "pass"
	return result

static func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
