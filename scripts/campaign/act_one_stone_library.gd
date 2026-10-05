# 从原山路石组提取真实独立石块；保留每个顶点的原法线、UV和材质。
# 原石组沿山阶升高，不能作为一整排搬到平庭院，否则高石会悬空。
extends RefCounted

static func extract(source: MeshInstance3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for surface in range(source.mesh.get_surface_count()):
		var arrays := source.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for index in range(vertices.size()): indices.append(index)
		var parents: Array[int] = []
		var welded: Dictionary = {}
		for index in range(vertices.size()):
			parents.append(index)
			var key := str(vertices[index].snapped(Vector3(.0001,.0001,.0001)))
			if welded.has(key): parents[index] = welded[key]
			else: welded[key] = index
		for index in range(0,indices.size(),3):
			_union(parents,indices[index],indices[index+1]); _union(parents,indices[index],indices[index+2])
		var groups: Dictionary = {}
		for index in range(0,indices.size(),3):
			var root := _find(parents,indices[index])
			if not groups.has(root): groups[root] = []
			groups[root].append_array([indices[index],indices[index+1],indices[index+2]])
		for group in groups.values():
			var bounds := AABB(vertices[group[0]],Vector3.ZERO)
			for index in group: bounds = bounds.expand(vertices[index])
			var center := Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
			var mesh := ArrayMesh.new(); var out: Array = []; out.resize(Mesh.ARRAY_MAX)
			var positions := PackedVector3Array(); var faces := PackedVector3Array(); var texture := PackedVector2Array()
			for index in group:
				positions.append(vertices[index]-center)
				faces.append(normals[index]); texture.append(uvs[index])
			out[Mesh.ARRAY_VERTEX] = positions; out[Mesh.ARRAY_NORMAL] = faces; out[Mesh.ARRAY_TEX_UV] = texture
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,out)
			mesh.surface_set_material(0,source.mesh.surface_get_material(surface))
			result.append({"mesh":mesh,"source_bounds":bounds,"source_center":center})
	return result

static func _find(parents: Array[int], index: int) -> int:
	while parents[index] != index:
		parents[index] = parents[parents[index]]; index = parents[index]
	return index

static func _union(parents: Array[int], a: int, b: int) -> void:
	parents[_find(parents,b)] = _find(parents,a)
