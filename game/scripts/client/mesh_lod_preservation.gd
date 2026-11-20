extends RefCounted
## Preserve Godot-imported mesh LODs while baking/resizing art into world-space meshes.
##
## Godot generates per-surface LOD index buffers during glTF/FBX import, but
## ArrayMesh.add_surface_from_arrays() does not inherit those buffers implicitly.
## The public Mesh API exposes vertex arrays but not their LOD dictionary, so
## read the surface's encoded index buffers through RenderingServer once, while
## a static model is being cached. No per-frame CPU/GPU transfer is performed.


## Returns a Dictionary[float, PackedInt32Array] for add_surface_from_arrays().
## Edge-length thresholds scale with baked model size; indices themselves
## remain valid because baking changes positions but not vertex order.
static func copy_lods(mesh: Mesh, surface: int, world_scale: float = 1.0) -> Dictionary:
	if mesh == null or not (mesh is ArrayMesh):
		return {}
	if surface < 0 or surface >= mesh.get_surface_count():
		return {}
	var data: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), surface)
	var raw_lods: Array = data.get("lods", [])
	if raw_lods.is_empty():
		return {}
	var count: int = int(data.get("vertex_count", 0))
	var stride: int = RenderingServer.mesh_surface_get_format_index_stride(
		int(data.get("format", 0)), count)
	if count <= 0 or (stride != 2 and stride != 4):
		return {}
	var result := {}
	for lod in raw_lods:
		var encoded: PackedByteArray = lod.get("index_data", PackedByteArray())
		if encoded.is_empty() or encoded.size() % stride != 0:
			continue
		var indices := PackedInt32Array()
		indices.resize(encoded.size() / stride)
		var valid := true
		for i in indices.size():
			var offset := i * stride
			var index: int = int(encoded.decode_u16(offset)) if stride == 2 else int(encoded.decode_u32(offset))
			if index >= count or index < 0:
				valid = false
				break
			indices[i] = index
		if valid and indices.size() >= 3 and indices.size() % 3 == 0:
			var edge_length: float = float(lod["edge_length"]) * maxf(absf(world_scale), 0.0001)
			result[edge_length] = indices
	return result
