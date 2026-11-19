extends RefCounted
## Splits a mesh into its connected pieces. Kenney's "grass with trees" tiles hold several trees as
## separate islands of triangles sitting on a ground block, so splitting by connectivity gives the
## individual trees.

const QUANTIZE := 1000.0


static func _key(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x * QUANTIZE), roundi(v.y * QUANTIZE), roundi(v.z * QUANTIZE))


## Returns an array of {"mesh": ArrayMesh, "center": Vector3 (bottom center), "size": Vector3}, one per
## piece, for the triangles whose lowest vertex is at least `min_y` above the mesh origin.
static func split(source: Mesh, min_y: float = 0.0, merge_xz: float = 0.0) -> Array:
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		for i in vertices.size():
			indices.append(i)
	var triangle_count := indices.size() / 3
	# Union-find over triangles through shared (quantized) vertex positions.
	var parent := PackedInt32Array()
	parent.resize(triangle_count)
	for i in triangle_count:
		parent[i] = i
	var owner_of_key: Dictionary = {}
	var find := func(x: int) -> int:
		while parent[x] != x:
			parent[x] = parent[parent[x]]
			x = parent[x]
		return x
	for t in triangle_count:
		for k in 3:
			var key := _key(vertices[indices[t * 3 + k]])
			if owner_of_key.has(key):
				var a: int = find.call(t)
				var b: int = find.call(owner_of_key[key])
				if a != b:
					parent[a] = b
			else:
				owner_of_key[key] = t
	var groups: Dictionary = {}
	for t in triangle_count:
		var lowest := INF
		for k in 3:
			lowest = minf(lowest, vertices[indices[t * 3 + k]].y)
		if lowest < min_y - 0.0001:
			continue
		var root: int = find.call(t)
		groups.get_or_add(root, []).append(t)
	# Pieces stacked on top of each other (a trunk and its crown) are one object: merge the groups
	# whose centers lie within `merge_xz` of each other horizontally.
	var merged: Array = [] # [{"triangles": [...], "center": Vector2}]
	for root in groups:
		var list: Array = groups[root]
		var box := AABB(vertices[indices[list[0] * 3]], Vector3.ZERO)
		for t in list:
			for k in 3:
				box = box.expand(vertices[indices[t * 3 + k]])
		var center := Vector2(box.position.x + box.size.x * 0.5, box.position.z + box.size.z * 0.5)
		var target := -1
		if merge_xz > 0.0:
			for i in merged.size():
				if merged[i]["center"].distance_to(center) <= merge_xz:
					target = i
					break
		if target >= 0:
			merged[target]["triangles"].append_array(list)
		else:
			merged.append({"triangles": list.duplicate(), "center": center})
	var result: Array = []
	for entry in merged:
		var list: Array = entry["triangles"]
		var box := AABB(vertices[indices[list[0] * 3]], Vector3.ZERO)
		for t in list:
			for k in 3:
				box = box.expand(vertices[indices[t * 3 + k]])
		var origin := Vector3(box.position.x + box.size.x * 0.5, box.position.y, box.position.z + box.size.z * 0.5)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for t in list:
			for k in 3:
				var index := indices[t * 3 + k]
				if uvs.size() > index:
					surface.set_uv(uvs[index])
				if normals.size() > index:
					surface.set_normal(normals[index])
				surface.add_vertex(vertices[index] - origin)
		var mesh := surface.commit()
		mesh.surface_set_material(0, source.surface_get_material(0))
		result.append({"mesh": mesh, "center": origin, "size": box.size})
	return result
