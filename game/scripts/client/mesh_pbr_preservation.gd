extends RefCounted
## Tangent-space preservation when fitting imported glTF/GLB meshes into world units.
## A model-space transform can contain rotation, non-uniform scaling or a mirror.
## Normals need an inverse-transpose; tangents need a forward transform followed
## by re-orthogonalization. The tangent fourth component is bitangent handedness.
## Compute this once on the CPU during cached mesh construction, never per frame.


## Return true when a valid tangent frame remains after transformation.
## The caller owns the surface arrays; vertices are transformed separately.
static func transform_frame(arrays: Array, basis: Basis) -> bool:
	var normal_data = arrays[Mesh.ARRAY_NORMAL]
	if not (normal_data is PackedVector3Array):
		arrays[Mesh.ARRAY_TANGENT] = null
		return false
	var normals: PackedVector3Array = normal_data
	if normals.is_empty():
		arrays[Mesh.ARRAY_TANGENT] = null
		return false
	var determinant: float = basis.determinant()
	if absf(determinant) < 0.000001:
		arrays[Mesh.ARRAY_TANGENT] = null
		return false
	var normal_basis: Basis = basis.inverse().transposed()
	var transformed := PackedVector3Array()
	transformed.resize(normals.size())
	for i in normals.size():
		transformed[i] = (normal_basis * normals[i]).normalized()
	arrays[Mesh.ARRAY_NORMAL] = transformed

	var tangent_data = arrays[Mesh.ARRAY_TANGENT]
	if not (tangent_data is PackedFloat32Array):
		return false
	var tangents: PackedFloat32Array = tangent_data
	if tangents.size() != normals.size() * 4:
		arrays[Mesh.ARRAY_TANGENT] = null
		return false
	var transformed_tangents := PackedFloat32Array()
	transformed_tangents.resize(tangents.size())
	var handedness: float = -1.0 if determinant < 0.0 else 1.0
	for i in normals.size():
		var k: int = i * 4
		var tangent := basis * Vector3(tangents[k], tangents[k + 1], tangents[k + 2])
		var normal: Vector3 = transformed[i]
		# Gram-Schmidt: keep the mapped tangent orthogonal to the normal.
		tangent -= normal * tangent.dot(normal)
		if tangent.length_squared() <= 0.00000001:
			# Invalid source tangent frame must never create NaNs or flicker.
			arrays[Mesh.ARRAY_TANGENT] = null
			return false
		tangent = tangent.normalized()
		transformed_tangents[k] = tangent.x
		transformed_tangents[k + 1] = tangent.y
		transformed_tangents[k + 2] = tangent.z
		transformed_tangents[k + 3] = tangents[k + 3] * handedness
	arrays[Mesh.ARRAY_TANGENT] = transformed_tangents
	return true


## Preserve normal/ORM/albedo maps and physically based material parameters.
## Only disable normal mapping when the source geometry has no usable tangent frame.
## Materials are duplicated, so changing the baked mesh never modifies imported art.
static func material_for_bake(source: Material, tangent_frame_valid: bool, dungeon_style: bool = false) -> Material:
	if not (source is BaseMaterial3D):
		return source
	var result := (source as BaseMaterial3D).duplicate() as BaseMaterial3D
	if result.normal_enabled and not tangent_frame_valid:
		result.normal_enabled = false
	if dungeon_style:
		# Keep the established hand-painted dungeon palette as an explicit exception.
		result.albedo_color = Color(0.68, 0.64, 0.58)
		result.roughness = 1.0
	return result
