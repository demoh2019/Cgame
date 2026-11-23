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
		var indices: PackedInt32Array = decode_indices(encoded, stride, count)
		if indices.size() >= 3 and indices.size() % 3 == 0:
			var edge_length: float = float(lod["edge_length"]) * maxf(absf(world_scale), 0.0001)
			result[edge_length] = indices
	return result

## Index data uses 16-bit storage for small meshes and 32-bit for large meshes.
## Refuse malformed buffers instead of introducing out-of-range triangles.
static func decode_indices(encoded: PackedByteArray, stride: int, vertex_count: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	if vertex_count <= 0 or (stride != 2 and stride != 4):
		return result
	if encoded.is_empty() or encoded.size() % stride != 0:
		return result
	result.resize(int(encoded.size() / stride))
	for i in result.size():
		var offset: int = i * stride
		var index: int = int(encoded.decode_u16(offset)) if stride == 2 else int(encoded.decode_u32(offset))
		if index >= vertex_count or index < 0:
			return PackedInt32Array()
		result[i] = index
	return result


static var _generated: Dictionary = {} # source Mesh -> Mesh with LODs (or the source when not worth it)

## Gives a static ArrayMesh automatic LODs (meshoptimizer, as Godot's importer does) when it has none.
## Baked props lost their importer LODs when their surfaces were rebuilt, so every scattered rock and
## stick drew full detail at any distance. Small meshes (< min_triangles) and meshes that already have
## LODs are returned unchanged. Cached per source mesh; run once at load, never per frame.
static func with_generated_lods(mesh: Mesh, min_triangles: int = 200) -> Mesh:
	if mesh == null or not (mesh is ArrayMesh):
		return mesh
	if _generated.has(mesh):
		return _generated[mesh]
	var result: Mesh = mesh
	var triangles := 0
	var has_lods := false
	for s in mesh.get_surface_count():
		var data: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), s)
		has_lods = has_lods or not (data.get("lods", []) as Array).is_empty()
		triangles += int(data.get("index_count", data.get("vertex_count", 0))) / 3
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES or (mesh as ArrayMesh).get_blend_shape_count() > 0:
			has_lods = true # Not a plain static triangle mesh: leave it alone.
	if not has_lods and triangles >= min_triangles:
		var importer := ImporterMesh.new()
		for s in mesh.get_surface_count():
			importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(s), [], {},
				mesh.surface_get_material(s), (mesh as ArrayMesh).surface_get_name(s))
		importer.generate_lods(25.0, 60.0, [])
		var rebuilt: ArrayMesh = importer.get_mesh()
		if rebuilt != null and rebuilt.get_surface_count() == mesh.get_surface_count():
			rebuilt.resource_name = mesh.resource_name
			rebuilt.custom_aabb = (mesh as ArrayMesh).custom_aabb
			result = rebuilt
	_generated[mesh] = result
	return result


## Native meshopt simplification uses *normal and UV weighted error*, not
## positions only. The replacement index list references original vertices;
## all imported tangent, color, UV2, skin and custom channels remain intact.
## Only used once while caching one-surface static props with no existing
## importer LODs. Stock Godot and older Cgame use the original importer path.
static func with_native_attribute_budget(mesh: Mesh, max_triangles: int) -> Mesh:
	if mesh == null or not (mesh is ArrayMesh) or max_triangles < 1 or \
			mesh.get_surface_count() != 1 or \
			(mesh as ArrayMesh).get_blend_shape_count() > 0 or \
			mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES or \
			not ClassDB.class_exists("CgameClusterLOD"):
		return mesh
	var native: Object = ClassDB.instantiate("CgameClusterLOD")
	if native == null or not native.has_method("simplify_surface_arrays"):
		return mesh
	var lods: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), 0)
	if not (lods.get("lods", []) as Array).is_empty():
		return mesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var original: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] \
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
	if original.size() < 6 or original.size() <= max_triangles * 3:
		return mesh
	var candidate: Array = native.call("simplify_surface_arrays",
		arrays, max_triangles, 0.6, 0.6)
	if candidate.size() != Mesh.ARRAY_MAX:
		return mesh
	var reduced: PackedInt32Array = candidate[Mesh.ARRAY_INDEX] \
		if candidate[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
	# Only adopt if the native algorithm actually meets this scatter's
	# target; otherwise the existing ImporterMesh algorithm gets a chance.
	if reduced.size() < 3 or reduced.size() % 3 != 0 or \
			reduced.size() >= original.size() or reduced.size() > max_triangles * 3:
		return mesh
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, candidate)
	result.surface_set_material(0, mesh.surface_get_material(0))
	result.surface_set_name(0, (mesh as ArrayMesh).surface_get_name(0))
	result.custom_aabb = (mesh as ArrayMesh).custom_aabb
	result.resource_name = mesh.resource_name
	return result


static var _budgeted: Dictionary = {} # "instance_id|budget" -> Mesh decimated to the budget

## Ground scatter (pebbles a few centimetres across, sticks) was drawn with full scanned detail
## (up to ~3000 triangles each, hundreds per tile), and MultiMesh LOD cannot help near the camera
## because it is chosen per tile, not per instance. Returns a copy whose full-detail level is the
## first meshoptimizer LOD within `max_triangles`, with its own LODs below that. Cached; load-time only.
static func with_triangle_budget(mesh: Mesh, max_triangles: int) -> Mesh:
	if mesh == null or not (mesh is ArrayMesh) or max_triangles <= 0:
		return mesh
	var key: String = "%d|%d" % [mesh.get_instance_id(), max_triangles]
	if _budgeted.has(key):
		return _budgeted[key]
	var source := mesh as ArrayMesh
	var total := 0
	for s in source.get_surface_count():
		if source.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES or source.get_blend_shape_count() > 0:
			_budgeted[key] = mesh
			return mesh
		var data: Dictionary = RenderingServer.mesh_get_surface(source.get_rid(), s)
		total += int(data.get("index_count", data.get("vertex_count", 0))) / 3
	if total <= max_triangles:
		_budgeted[key] = mesh
		return mesh
	# Prefer one native attribute-aware pass for the small static single-
	# surface props populating actual Albion scenery MultiMeshes. Avoid
	# normal-map and UV drift from a purely position-based simplifier.
	var native_budgeted: Mesh = with_native_attribute_budget(source, max_triangles)
	if native_budgeted != source:
		_budgeted[key] = native_budgeted
		return native_budgeted
	# The importer owns meshoptimizer's current, non-deprecated simplification path.
	# Generate a full LOD ladder once and promote the best level under each surface's
	# share of the triangle budget to its new base mesh. If no level fits, use the
	# smallest valid generated LOD; never increase the source's triangle count.
	var generated := ImporterMesh.new()
	for s in source.get_surface_count():
		generated.add_surface(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(s), [], {},
			source.surface_get_material(s), source.surface_get_name(s))
	generated.generate_lods(25.0, 60.0, [])
	var reduced := ImporterMesh.new()
	var any_reduced := false
	for s in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(s)
		var full: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var share: int = maxi(12, int(float(max_triangles) * float(full.size() / 3) / float(total)))
		var best_under_budget := PackedInt32Array()
		var smallest_available := PackedInt32Array()
		if full.size() > share * 3:
			for level in generated.get_surface_lod_count(s):
				var candidate: PackedInt32Array = generated.get_surface_lod_indices(s, level)
				if candidate.size() < 3 or candidate.size() % 3 != 0 or candidate.size() >= full.size():
					continue
				if candidate.size() <= share * 3:
					if best_under_budget.is_empty() or candidate.size() > best_under_budget.size():
						best_under_budget = candidate
				elif smallest_available.is_empty() or candidate.size() < smallest_available.size():
					smallest_available = candidate
		var chosen: PackedInt32Array = best_under_budget if not best_under_budget.is_empty() else smallest_available
		if not chosen.is_empty():
			arrays[Mesh.ARRAY_INDEX] = chosen
			any_reduced = true
		reduced.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
			source.surface_get_material(s), source.surface_get_name(s))
	if not any_reduced:
		_budgeted[key] = mesh
		return mesh
	# Regenerate distance/error thresholds for the new base geometry.
	reduced.generate_lods(25.0, 60.0, [])
	var rebuilt: ArrayMesh = reduced.get_mesh()
	var result: Mesh = mesh
	if rebuilt != null and rebuilt.get_surface_count() == source.get_surface_count():
		rebuilt.resource_name = source.resource_name
		rebuilt.custom_aabb = source.custom_aabb
		result = rebuilt
	_budgeted[key] = result
	return result
