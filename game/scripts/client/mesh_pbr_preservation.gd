extends RefCounted
## Tangent-space preservation when fitting imported glTF/GLB meshes into world units.
## A model-space transform can contain rotation, non-uniform scaling or a mirror.
## Normals need an inverse-transpose; tangents need a forward transform followed
## by re-orthogonalization. The tangent fourth component is bitangent handedness.
## Compute this once on the CPU during cached mesh construction, never per frame.

const StoneMicrodetail = preload("res://scripts/client/graphics_stone_microdetail.gd")


## Only normal/height/detail/anisotropy features need tangent-space geometry.
## Never spend startup work generating frames for plain vertex-coloured props.
static func needs_tangents(material: Material) -> bool:
	if not (material is BaseMaterial3D):
		return false
	var pbr := material as BaseMaterial3D
	return pbr.normal_enabled or pbr.anisotropy_enabled or pbr.heightmap_enabled or pbr.detail_enabled


## Recover missing imported MikkTSpace frames without rebuilding the final mesh.
## Copy ONLY the tangent channel: all original indices (including native LODs),
## blend/skin/UV and custom vertex attributes must retain their exact positions.
## Missing UVs or a generator that changes vertex order fail closed; the caller
## then disables normal-mapped features on a private material copy.
static func ensure_tangents(arrays: Array) -> bool:
	if arrays.size() != Mesh.ARRAY_MAX:
		return false
	var vertices_data: Variant = arrays[Mesh.ARRAY_VERTEX]
	var normals_data: Variant = arrays[Mesh.ARRAY_NORMAL]
	if not (vertices_data is PackedVector3Array) or not (normals_data is PackedVector3Array):
		arrays[Mesh.ARRAY_TANGENT] = null
		return false
	var vertices: PackedVector3Array = vertices_data
	var normals: PackedVector3Array = normals_data
	if vertices.is_empty() or normals.size() != vertices.size():
		arrays[Mesh.ARRAY_TANGENT] = null
		return false
	var current_data: Variant = arrays[Mesh.ARRAY_TANGENT]
	if current_data is PackedFloat32Array:
		var current: PackedFloat32Array = current_data
		if _finite_tangent_buffer(current, vertices.size()):
			return true
	arrays[Mesh.ARRAY_TANGENT] = null
	var uvs_data: Variant = arrays[Mesh.ARRAY_TEX_UV]
	if not (uvs_data is PackedVector2Array):
		return false
	var uvs: PackedVector2Array = uvs_data
	if uvs.size() != vertices.size():
		return false
	for i in vertices.size():
		if not vertices[i].is_finite() or not normals[i].is_finite() or not uvs[i].is_finite():
			return false
	# Godot uses MikkTSpace here, matching imported normal-map texture baking.
	# Work is done once per cached model, not once per frame/instance.
	var input_mesh := ArrayMesh.new()
	input_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface := SurfaceTool.new()
	surface.create_from(input_mesh, 0)
	surface.generate_tangents()
	var generated: Array = surface.commit_to_arrays()
	if generated.size() != Mesh.ARRAY_MAX or 			generated[Mesh.ARRAY_VERTEX] != vertices or 			generated[Mesh.ARRAY_INDEX] != arrays[Mesh.ARRAY_INDEX]:
		return false
	var tangent_data: Variant = generated[Mesh.ARRAY_TANGENT]
	if not (tangent_data is PackedFloat32Array):
		return false
	var tangents: PackedFloat32Array = tangent_data
	if not _finite_tangent_buffer(tangents, vertices.size()):
		return false
	arrays[Mesh.ARRAY_TANGENT] = tangents
	return true


static func _finite_tangent_buffer(tangents: PackedFloat32Array, vertex_count: int) -> bool:
	if tangents.size() != vertex_count * 4:
		return false
	for component in tangents:
		if not is_finite(component):
			return false
	return true


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
static func material_for_bake(source: Material, tangent_frame_valid: bool,
		dungeon_style: bool = false, masonry_detail: bool = false) -> Material:
	if not (source is BaseMaterial3D):
		return source
	var result := (source as BaseMaterial3D).duplicate() as BaseMaterial3D
	# Better glancing-angle detail on imported glTF PBR surfaces without extra
	# texture fetches in shaders. The viewport presets cap anisotropy at 2/4/8/16x.
	# Do not override intentionally pixelated or explicitly anisotropic art.
	if result.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
		result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if not tangent_frame_valid:
		# Each of these features can make the renderer request ARRAY_TANGENT.
		# Disable them on the copied material only when UV tangent recovery fails.
		result.normal_enabled = false
		result.anisotropy_enabled = false
		result.heightmap_enabled = false
		result.detail_enabled = false
	if dungeon_style:
		# Keep the established hand-painted dungeon palette as an explicit exception.
		result.albedo_color = Color(0.68, 0.64, 0.58)
		result.roughness = 1.0
	# Native detail-normal layering is limited to true masonry with a valid
	# tangent basis. Quality changes toggle this copied PBR material in place.
	if masonry_detail:
		StoneMicrodetail.register(result, tangent_frame_valid)
	return result
