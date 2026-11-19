@tool
extends RefCounted
class_name HLODMeshBuilder
## Builds a static, material-preserving triangle-mesh proxy in cluster-local space.
## No engine core or renderer patches are needed.

const MAX_VERTICES := 250000
const MAX_INDICES := 1500000
const MAX_SURFACES := 1024
const PROXY_NAME := "__HLOD_PROXY__"


static func _collect(node: Node, result: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child.name == PROXY_NAME or (child is Node3D and child.has_method("get_proxy_surface_count")):
			continue
		if child is MeshInstance3D and child.mesh != null and child.visible:
			result.append(child)
		_collect(child, result)


static func get_sources(root: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root != null:
		_collect(root, result)
	return result


static func _invalid(message: String) -> Dictionary:
	return {"ok": false, "error": message, "mesh": null, "source_count": 0,
			"surface_count": 0, "vertex_count": 0}


static func _normals_for_surface(positions: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(positions.size())
	for i in range(0, indices.size(), 3):
		var a: int = indices[i]
		var b: int = indices[i + 1]
		var c: int = indices[i + 2]
		var normal: Vector3 = (positions[b] - positions[a]).cross(positions[c] - positions[a])
		normals[a] += normal
		normals[b] += normal
		normals[c] += normal
	for i in normals.size():
		normals[i] = normals[i].normalized() if not normals[i].is_zero_approx() else Vector3.UP
	return normals


static func build(root: Node3D, vertex_budget: int = MAX_VERTICES, use_bounds_proxy: bool = false) -> Dictionary:
	if root == null:
		return _invalid("HLOD cluster is null")
	if vertex_budget < 3 or vertex_budget > MAX_VERTICES:
		return _invalid("Invalid HLOD vertex budget")

	var sources := get_sources(root)
	if sources.is_empty():
		return _invalid("No visible MeshInstance3D sources")
	var groups: Dictionary = {}
	var total_vertices := 0
	var total_indices := 0
	var total_surfaces := 0
	if not root.global_transform.is_finite() or absf(root.global_transform.basis.determinant()) < 0.000001:
		return _invalid("Invalid HLOD cluster transform")
	var cluster_inverse: Transform3D = root.global_transform.affine_inverse()

	for source in sources:
		var source_transform: Transform3D = cluster_inverse * source.global_transform
		var source_mesh: Mesh = source.mesh
		if use_bounds_proxy:
			if source_mesh.get_surface_count() == 0:
				return _invalid("Mesh without any surfaces cannot make a bounds proxy")
			var bounds: AABB = source_mesh.get_aabb()
			if not bounds.position.is_finite() or not bounds.size.is_finite():
				return _invalid("Non-finite source mesh bounds")
			var box := BoxMesh.new()
			box.size = Vector3(maxf(bounds.size.x, 0.001),
					maxf(bounds.size.y, 0.001), maxf(bounds.size.z, 0.001))
			source_mesh = box
			source_transform = source_transform * Transform3D(Basis.IDENTITY, bounds.get_center())
		if not source_transform.is_finite():
			return _invalid("Non-finite source transform: %s" % source.name)
		var determinant: float = source_transform.basis.determinant()
		if absf(determinant) < 0.000001:
			return _invalid("Source transform is singular: %s" % source.name)
		var normal_basis: Basis = source_transform.basis.inverse().transposed()

		for surface in source_mesh.get_surface_count():
			if source_mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				return _invalid("HLOD only supports triangle surfaces")
			total_surfaces += 1
			if total_surfaces > MAX_SURFACES:
				return _invalid("Too many source surfaces")

			var arrays: Array = source_mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var original_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var original_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var original_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()

			if positions.size() < 3:
				return _invalid("Source surface has fewer than 3 vertices")
			if original_normals.size() != 0 and original_normals.size() != positions.size():
				return _invalid("Invalid source normal count")
			if original_uvs.size() != 0 and original_uvs.size() != positions.size():
				return _invalid("Invalid source UV count")
			if original_colors.size() != 0 and original_colors.size() != positions.size():
				return _invalid("Invalid source color count")
			if source_indices.is_empty():
				for index in positions.size():
					source_indices.append(index)
			if source_indices.size() % 3 != 0:
				return _invalid("Triangle indices are not a multiple of three")
			for index in source_indices:
				if index < 0 or index >= positions.size():
					return _invalid("Out-of-bounds triangle index")
			total_indices += source_indices.size()
			if total_indices > MAX_INDICES:
				return _invalid("HLOD proxy exceeds the index budget")

			total_vertices += positions.size()
			if total_vertices > vertex_budget:
				return _invalid("HLOD proxy exceeds the vertex budget")

			# Use the same effective material as the original renderer, even in
			# bounds mode where geometry is replaced by a synthetic BoxMesh.
			var material: Material = source.get_active_material(0 if use_bounds_proxy else surface)
			var key: int = material.get_instance_id() if material != null else 0
			if not groups.has(key):
				groups[key] = {
					"material": material,
					"vertices": PackedVector3Array(),
					"normals": PackedVector3Array(),
					"uvs": PackedVector2Array(),
					"colors": PackedColorArray(),
					"indices": PackedInt32Array()
				}
			var group: Dictionary = groups[key]
			var vertices: PackedVector3Array = group["vertices"]
			var normals: PackedVector3Array = group["normals"]
			var uvs: PackedVector2Array = group["uvs"]
			var colors: PackedColorArray = group["colors"]
			var indices: PackedInt32Array = group["indices"]
			var base_index := vertices.size()

			var transformed := PackedVector3Array()
			for point in positions:
				transformed.append(source_transform * point)

			var local_indices := PackedInt32Array()
			for triangle in range(0, source_indices.size(), 3):
				var a: int = source_indices[triangle]
				var b: int = source_indices[triangle + 1]
				var c: int = source_indices[triangle + 2]
				if determinant < 0.0:
					local_indices.append_array(PackedInt32Array([a, c, b]))
				else:
					local_indices.append_array(PackedInt32Array([a, b, c]))

			var computed_normals := PackedVector3Array()
			if original_normals.is_empty():
				computed_normals = _normals_for_surface(transformed, local_indices)

			for vertex_index in positions.size():
				vertices.append(transformed[vertex_index])
				if original_normals.is_empty():
					normals.append(computed_normals[vertex_index])
				else:
					normals.append((normal_basis * original_normals[vertex_index]).normalized())
				uvs.append(original_uvs[vertex_index] if not original_uvs.is_empty() else Vector2.ZERO)
				colors.append(original_colors[vertex_index] if not original_colors.is_empty() else Color.WHITE)
			for index in local_indices:
				indices.append(base_index + index)

			group["vertices"] = vertices
			group["normals"] = normals
			group["uvs"] = uvs
			group["colors"] = colors
			group["indices"] = indices
			groups[key] = group

	if groups.is_empty():
		return _invalid("No eligible geometry")
	var mesh := ArrayMesh.new()
	for group in groups.values():
		var surface_arrays := []
		surface_arrays.resize(Mesh.ARRAY_MAX)
		surface_arrays[Mesh.ARRAY_VERTEX] = group["vertices"]
		surface_arrays[Mesh.ARRAY_NORMAL] = group["normals"]
		surface_arrays[Mesh.ARRAY_TEX_UV] = group["uvs"]
		surface_arrays[Mesh.ARRAY_COLOR] = group["colors"]
		surface_arrays[Mesh.ARRAY_INDEX] = group["indices"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)
		var material: Material = group["material"]
		if material != null:
			mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return {"ok": true, "error": "", "mesh": mesh,
			"source_count": sources.size(), "surface_count": mesh.get_surface_count(),
			"vertex_count": total_vertices,
			"proxy_mode": "bounds" if use_bounds_proxy else "merged"}
