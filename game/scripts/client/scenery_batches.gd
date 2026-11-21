extends RefCounted
## Chunk-local GPU instancing with spatial culling.
## A MultiMesh is culled as a whole, not per instance: large decoration batches
## unnecessarily draw all flowers when just one corner enters the view.
## Subdivide only busy meshes into 32 m tiles to keep draw-call costs bounded.

const TILE_SIZE := 32.0
const SPLIT_MIN_INSTANCES := 48
const MAX_SCENERY_INSTANCES := 65536
const MAX_SCENERY_CLUSTERS := 256
const BOUNDS_MARGIN := 0.6 # Mesh movement in wind and imprecise imported bounds.

static var _cluster_native: Object = null
static var _cluster_checked := false


## Conservative fallback, matching the native Unreal HISM-inspired 3D grid.
## Small lists stay one MultiMesh draw call; pathological overpartitioning
## falls back to one draw call instead of dropping instances or exceeding budget.
static func _single_cluster_indices(count: int) -> Array:
	var result: Array = []
	if count == 0:
		return result
	var indices := PackedInt32Array()
	indices.resize(count)
	for i in count:
		indices[i] = i
	result.append(indices)
	return result


static func _cluster_indices_fallback(points: PackedVector3Array, cell_size: float,
		min_split_count: int, max_clusters: int) -> Array:
	var result: Array = []
	if points.size() > MAX_SCENERY_INSTANCES or min_split_count < 1 or \
			min_split_count > MAX_SCENERY_INSTANCES or max_clusters < 1 or \
			max_clusters > MAX_SCENERY_CLUSTERS or not is_finite(cell_size) or \
			cell_size < 0.5 or cell_size > 10000.0:
		return result
	for p in points:
		if not p.is_finite() or absf(p.x) > 10000000.0 or \
				absf(p.y) > 10000000.0 or absf(p.z) > 10000000.0:
			return result
	if points.is_empty():
		return result
	if points.size() < min_split_count or max_clusters == 1:
		return _single_cluster_indices(points.size())
	var buckets: Dictionary = {}
	var order: Array[Vector3i] = []
	for i in points.size():
		var p: Vector3 = points[i]
		var cell := Vector3i(floori(p.x / cell_size), floori(p.y / cell_size),
			floori(p.z / cell_size))
		if not buckets.has(cell):
			if order.size() >= max_clusters:
				return _single_cluster_indices(points.size())
			order.append(cell)
			buckets[cell] = PackedInt32Array()
		var indices: PackedInt32Array = buckets[cell]
		indices.append(i)
		buckets[cell] = indices
	for cell in order:
		result.append(buckets[cell])
	return result


## Native module computes the index buckets; no scene objects or RNG are touched.
## Use prefer_native=false to test the exact portable policy independently.
static func partition_indices_3d(points: PackedVector3Array, cell_size: float = TILE_SIZE,
		min_split_count: int = SPLIT_MIN_INSTANCES,
		max_clusters: int = MAX_SCENERY_CLUSTERS, prefer_native: bool = true) -> Array:
	if prefer_native:
		if not _cluster_checked:
			_cluster_checked = true
			if ClassDB.class_exists("PCGInstanceCluster3D"):
				var instance: Object = ClassDB.instantiate("PCGInstanceCluster3D")
				if instance != null and instance.has_method("partition_indices"):
					_cluster_native = instance
		if _cluster_native != null:
			return _cluster_native.call("partition_indices", points, cell_size,
				min_split_count, max_clusters)
	return _cluster_indices_fallback(points, cell_size, min_split_count, max_clusters)


## Native 3D spatial cells yield tighter cullable MultiMesh bounds on steep
## terrain; flat ground still produces the same stable 32 m XY-plane tiles.
## Every instance appears in exactly one batch, preserving its original order.
static func partition(transforms: Array[Transform3D]) -> Array:
	if transforms.is_empty():
		return []
	if transforms.size() < SPLIT_MIN_INSTANCES or transforms.size() > MAX_SCENERY_INSTANCES:
		return [transforms]
	var points := PackedVector3Array()
	points.resize(transforms.size())
	for i in transforms.size():
		points[i] = transforms[i].origin
	var index_groups: Array = partition_indices_3d(points)
	if index_groups.is_empty():
		return [transforms] # Fail open for cosmetic geometry; never drop transforms.
	var result: Array = []
	var assigned := 0
	for indices in index_groups:
		var group: Array[Transform3D] = []
		for index in indices:
			group.append(transforms[index])
		assigned += group.size()
		result.append(group)
	if assigned != transforms.size():
		return [transforms]
	return result



## Unreal PCG-style minimum-distance sampling for client-only decorations.
## The native filter uses a spatial hash; on older/stock engines the same
## greedy stable-input policy is implemented with GDScript buckets.
## Importantly, callers generate transforms before thinning, so the seeded
## RNG stream for subsequent scenery categories is unchanged.
static var _pcg_native: Object = null
static var _pcg_checked := false
const PCG_MAX_CANDIDATES := 16384
const PCG_MAX_SELECTED := 4096


static func _pcg_filter_fallback(candidates: PackedVector2Array,
		min_spacing: float, max_selected: int = PCG_MAX_SELECTED) -> PackedInt32Array:
	var result := PackedInt32Array()
	if candidates.size() > PCG_MAX_CANDIDATES or max_selected < 0 or \
			max_selected > PCG_MAX_SELECTED or not is_finite(min_spacing) or \
			min_spacing < 0.0 or min_spacing > 10000.0 or \
			(min_spacing > 0.0 and min_spacing < 0.05):
		return result
	for p in candidates:
		if not p.is_finite() or absf(p.x) > 10000000.0 or absf(p.y) > 10000000.0:
			return result
	if min_spacing == 0.0:
		for i in mini(max_selected, candidates.size()):
			result.append(i)
		return result
	var cells: Dictionary = {}
	var distance_sq: float = min_spacing * min_spacing
	for i in candidates.size():
		if result.size() >= max_selected:
			break
		var p: Vector2 = candidates[i]
		var cell := Vector2i(floori(p.x / min_spacing), floori(p.y / min_spacing))
		var blocked := false
		for cy in range(-1, 2):
			for cx in range(-1, 2):
				for index in cells.get(cell + Vector2i(cx, cy), []):
					if p.distance_squared_to(candidates[index]) < distance_sq:
						blocked = true
						break
				if blocked:
					break
			if blocked:
				break
		if blocked:
			continue
		result.append(i)
		var indices: Array = cells.get(cell, [])
		indices.append(i)
		cells[cell] = indices
	return result


## Returns original candidate indices; use prefer_native=false in parity tests.
static func pcg_filter_indices(candidates: PackedVector2Array,
		min_spacing: float, max_selected: int = PCG_MAX_SELECTED,
		prefer_native: bool = true) -> PackedInt32Array:
	if prefer_native:
		if not _pcg_checked:
			_pcg_checked = true
			if ClassDB.class_exists("PCGSpatialFilter2D"):
				var instance: Object = ClassDB.instantiate("PCGSpatialFilter2D")
				if instance != null and instance.has_method("filter_indices"):
					_pcg_native = instance
		if _pcg_native != null:
			return _pcg_native.call("filter_indices", candidates, min_spacing, max_selected)
	return _pcg_filter_fallback(candidates, min_spacing, max_selected)


## Scale-aware native/fallback PCG self-pruning (Unreal-style Large to Small).
## Spacing between points i and j is base_spacing * (scale_i + scale_j) / 2.
## Using a bounded 5x5 neighborhood prevents extra all-pairs checks.
static func _pcg_filter_scaled_fallback(candidates: PackedVector2Array,
		scales: PackedFloat32Array, min_spacing: float,
		max_selected: int = PCG_MAX_SELECTED,
		largest_first: bool = true) -> PackedInt32Array:
	var result := PackedInt32Array()
	if candidates.size() != scales.size() or candidates.size() > PCG_MAX_CANDIDATES or \
			max_selected < 0 or max_selected > PCG_MAX_SELECTED or \
			not is_finite(min_spacing) or min_spacing < 0.0 or \
			min_spacing > 10000.0 or (min_spacing > 0.0 and min_spacing < 0.05):
		return result
	for i in candidates.size():
		var p: Vector2 = candidates[i]
		var scale: float = scales[i]
		if not p.is_finite() or absf(p.x) > 10000000.0 or \
				absf(p.y) > 10000000.0 or not is_finite(scale) or \
				scale < 0.5 or scale > 2.0:
			return result
	if min_spacing == 0.0:
		for i in mini(max_selected, candidates.size()):
			result.append(i)
		return result

	var order: Array[int] = []
	for i in candidates.size():
		order.append(i)
	if largest_first:
		order.sort_custom(func(a: int, b: int) -> bool:
			return scales[a] > scales[b] if scales[a] != scales[b] else a < b
		)

	var cells: Dictionary = {}
	for index in order:
		if result.size() >= max_selected:
			break
		var p: Vector2 = candidates[index]
		var cell := Vector2i(floori(p.x / min_spacing), floori(p.y / min_spacing))
		var blocked := false
		for cy in range(-2, 3):
			for cx in range(-2, 3):
				for other in cells.get(cell + Vector2i(cx, cy), []):
					var threshold: float = min_spacing * (scales[index] + scales[other]) * 0.5
					if p.distance_squared_to(candidates[other]) < threshold * threshold:
						blocked = true
						break
				if blocked:
					break
			if blocked:
				break
		if blocked:
			continue
		result.append(index)
		var bucket: Array = cells.get(cell, [])
		bucket.append(index)
		cells[cell] = bucket
	if largest_first:
		result.sort() # Keep original transform/MultiMesh buffer ordering.
	return result


## Uses the native engine when it has the new API, otherwise identical GDScript.
static func pcg_filter_indices_scaled(candidates: PackedVector2Array,
		scales: PackedFloat32Array, min_spacing: float,
		max_selected: int = PCG_MAX_SELECTED, largest_first: bool = true,
		prefer_native: bool = true) -> PackedInt32Array:
	if prefer_native:
		if not _pcg_checked:
			_pcg_checked = true
			if ClassDB.class_exists("PCGSpatialFilter2D"):
				var instance: Object = ClassDB.instantiate("PCGSpatialFilter2D")
				if instance != null and instance.has_method("filter_indices"):
					_pcg_native = instance
		if _pcg_native != null and _pcg_native.has_method("filter_indices_scaled"):
			return _pcg_native.call("filter_indices_scaled",
				candidates, scales, min_spacing, max_selected, largest_first)
	return _pcg_filter_scaled_fallback(candidates, scales, min_spacing,
		max_selected, largest_first)


## Runs exclusively on already built cosmetic MultiMesh transforms; does not
## modify terrain, interactive resource nodes, server spawns or collisions.
static func thin_cosmetic_transforms(transforms: Array[Transform3D],
		min_spacing: float, prefer_native: bool = true) -> Array[Transform3D]:
	if min_spacing <= 0.0 or transforms.is_empty() or transforms.size() > PCG_MAX_CANDIDATES:
		return transforms
	var points := PackedVector2Array()
	for transform in transforms:
		points.append(Vector2(transform.origin.x, transform.origin.z))
	var indices: PackedInt32Array = pcg_filter_indices(
		points, min_spacing, PCG_MAX_SELECTED, prefer_native)
	var result: Array[Transform3D] = []
	for index in indices:
		result.append(transforms[index])
	return result



## Height-aware PCG selection for stacked cliffs/terraces. On stock Godot
## the fallback uses the same deterministic greedy 3D spatial hash.
static var _pcg_native_3d: Object = null
static var _pcg_checked_3d := false


static func _pcg_filter_3d_fallback(candidates: PackedVector3Array,
		min_spacing: float, max_selected: int = PCG_MAX_SELECTED) -> PackedInt32Array:
	var result := PackedInt32Array()
	if candidates.size() > PCG_MAX_CANDIDATES or max_selected < 0 or \
			max_selected > PCG_MAX_SELECTED or not is_finite(min_spacing) or \
			min_spacing < 0.0 or min_spacing > 10000.0 or \
			(min_spacing > 0.0 and min_spacing < 0.05):
		return result
	# Invalid late points must not produce partially placed decoration.
	for p in candidates:
		if not p.is_finite() or absf(p.x) > 10000000.0 or \
				absf(p.y) > 10000000.0 or absf(p.z) > 10000000.0:
			return result
	if min_spacing == 0.0:
		for i in mini(max_selected, candidates.size()):
			result.append(i)
		return result
	var cells: Dictionary = {}
	var distance_sq: float = min_spacing * min_spacing
	for i in candidates.size():
		if result.size() >= max_selected:
			break
		var p: Vector3 = candidates[i]
		var cell := Vector3i(floori(p.x / min_spacing), floori(p.y / min_spacing),
			floori(p.z / min_spacing))
		var blocked := false
		for z in range(-1, 2):
			for y in range(-1, 2):
				for x in range(-1, 2):
					for index in cells.get(cell + Vector3i(x, y, z), []):
						if p.distance_squared_to(candidates[index]) < distance_sq:
							blocked = true
							break
					if blocked:
						break
				if blocked:
					break
			if blocked:
				break
		if blocked:
			continue
		result.append(i)
		var indices: Array = cells.get(cell, [])
		indices.append(i)
		cells[cell] = indices
	return result


static func pcg_filter_indices_3d(candidates: PackedVector3Array,
		min_spacing: float, max_selected: int = PCG_MAX_SELECTED,
		prefer_native: bool = true) -> PackedInt32Array:
	if prefer_native:
		if not _pcg_checked_3d:
			_pcg_checked_3d = true
			if ClassDB.class_exists("PCGSpatialFilter3D"):
				var instance: Object = ClassDB.instantiate("PCGSpatialFilter3D")
				if instance != null and instance.has_method("filter_indices"):
					_pcg_native_3d = instance
		if _pcg_native_3d != null:
			return _pcg_native_3d.call("filter_indices", candidates, min_spacing, max_selected)
	return _pcg_filter_3d_fallback(candidates, min_spacing, max_selected)


## Called after seeded transforms are generated, so thinning never changes
## the random stream for neighboring chunks or later decoration categories.
static func thin_cosmetic_transforms_3d(transforms: Array[Transform3D],
		min_spacing: float, prefer_native: bool = true) -> Array[Transform3D]:
	if min_spacing <= 0.0 or transforms.is_empty() or transforms.size() > PCG_MAX_CANDIDATES:
		return transforms
	var points := PackedVector3Array()
	for transform in transforms:
		points.append(transform.origin)
	var chosen: PackedInt32Array = pcg_filter_indices_3d(
		points, min_spacing, PCG_MAX_SELECTED, prefer_native)
	var result: Array[Transform3D] = []
	for index in chosen:
		result.append(transforms[index])
	return result


## Scale-adaptive visual spacing for random-size bushes and loose pebbles.
## All RNG draws and transforms are generated by ChunkView before this pass.
## Clamping to [0.5, 2.0] keeps a constant local lookup footprint.
static func thin_cosmetic_transforms_scaled(transforms: Array[Transform3D],
		min_spacing: float, prefer_native: bool = true) -> Array[Transform3D]:
	if min_spacing <= 0.0 or transforms.is_empty() or transforms.size() > PCG_MAX_CANDIDATES:
		return transforms
	var points := PackedVector2Array()
	var scales := PackedFloat32Array()
	for transform in transforms:
		points.append(Vector2(transform.origin.x, transform.origin.z))
		scales.append(clampf(transform.basis.x.length(), 0.5, 2.0))
	var indices: PackedInt32Array = pcg_filter_indices_scaled(
		points, scales, min_spacing, PCG_MAX_SELECTED, true, prefer_native)
	var result: Array[Transform3D] = []
	for index in indices:
		result.append(transforms[index])
	return result


## Custom bounds are in the parent's local coordinates, matching MultiMesh transforms.
## Include full mesh extents and rotation; using only placement centers could clip trees.
static func bounds_for(mesh: Mesh, transforms: Array) -> AABB:
	var bounds: AABB = transforms[0] * mesh.get_aabb()
	for i in range(1, transforms.size()):
		bounds = bounds.merge(transforms[i] * mesh.get_aabb())
	return bounds.grow(BOUNDS_MARGIN)


## GPU-instanced colour: same PBR material, no per-object nodes or variants.
## A coordinate-only hash is stable across chunk streaming and in any
## partition order; world_origin converts local MultiMesh transforms to world.
static func tint_at(world_xz: Vector2) -> Color:
	var cell: Vector2 = (world_xz * 4.0).floor()
	var h0: float = _hash(cell, 0.0)
	var h1: float = _hash(cell, 31.7)
	# Keep plant pigments recognizable while breaking the repeated tint.
	# Combined with Foliage's existing world-space leaf hue variation.
	return Color(lerpf(0.88, 1.05, h0), lerpf(0.91, 1.06, h1),
		lerpf(0.84, 1.02, h0 * 0.37 + h1 * 0.63), 1.0)


static func _hash(cell: Vector2, salt: float) -> float:
	return fposmod(sin(cell.dot(Vector2(127.1, 311.7)) + salt) *
		43758.5453, 1.0)


## Native RD MultiMesh data: 3x4 row-major transform (12 floats), followed
## by RGBA colour (four floats) only on opted-in foliage. One GPU upload
## replaces O(n) separate instance transform/colour RenderingServer calls.
static func packed_group(transforms: Array, tinted: bool = false,
		world_origin: Vector2 = Vector2.ZERO) -> PackedFloat32Array:
	var stride: int = 16 if tinted else 12
	var floats := PackedFloat32Array()
	floats.resize(transforms.size() * stride)
	for i in transforms.size():
		var t: Transform3D = transforms[i]
		var o: int = i * stride
		floats[o + 0] = t.basis.x.x
		floats[o + 1] = t.basis.y.x
		floats[o + 2] = t.basis.z.x
		floats[o + 3] = t.origin.x
		floats[o + 4] = t.basis.x.y
		floats[o + 5] = t.basis.y.y
		floats[o + 6] = t.basis.z.y
		floats[o + 7] = t.origin.y
		floats[o + 8] = t.basis.x.z
		floats[o + 9] = t.basis.y.z
		floats[o + 10] = t.basis.z.z
		floats[o + 11] = t.origin.z
		if tinted:
			var pigment: Color = tint_at(
				world_origin + Vector2(t.origin.x, t.origin.z))
			floats[o + 12] = pigment.r
			floats[o + 13] = pigment.g
			floats[o + 14] = pigment.b
			floats[o + 15] = pigment.a
	return floats


## Use the fork's bulk native packing when present. Unlike N*12 script
## writes, Cgame marshals matrices into linear GPU-ready memory in one pass.
## Stock Godot uses the unchanged original layout and seeded pigment logic.
static func packed_group_for(multimesh: MultiMesh, transforms: Array,
		tinted: bool = false, world_origin: Vector2 = Vector2.ZERO) -> PackedFloat32Array:
	if multimesh != null and multimesh.has_method("pack_transform_buffer"):
		var colors := PackedColorArray()
		if tinted:
			colors.resize(transforms.size())
			for i in transforms.size():
				var t: Transform3D = transforms[i]
				colors[i] = tint_at(world_origin + Vector2(t.origin.x, t.origin.z))
		var packed: PackedFloat32Array = multimesh.call("pack_transform_buffer", transforms, colors)
		if packed.size() == transforms.size() * (16 if tinted else 12):
			return packed
	return packed_group(transforms, tinted, world_origin)


## Correct world-space AABBs are essential: Godot culls a whole MultiMesh
## cluster, never individual trees. Use native union if available.
static func bounds_for_instance(multimesh: MultiMesh, mesh: Mesh,
		transforms: Array) -> AABB:
	if multimesh != null and multimesh.has_method("transformed_mesh_bounds"):
		return multimesh.call("transformed_mesh_bounds", transforms, BOUNDS_MARGIN)
	return bounds_for(mesh, transforms)


## The mesh shader must opt in to using the instance COLOR attribute.
## Only leaves/flowers/grass/ferns/green plants have this enabled in
## ChunkView. Rocks, buildings, mushrooms and original PBR art are unchanged.
static func colorful_plant(name: String) -> bool:
	return name.begins_with("Fern") or name.begins_with("Bush") or \
		name.begins_with("Plant") or name.begins_with("Flower") or \
		name.begins_with("Grass")


## Visual-only props: instancing stays on the GPU and no physics/server nodes are made.
static func add(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D], draw_distance: float, cast_shadows: bool = false, fade_margin: float = 8.0,
		tint_variation: bool = false, world_origin: Vector2 = Vector2.ZERO) -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	if mesh == null or transforms.is_empty():
		return result
	for group in partition(transforms):
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = tint_variation
		multimesh.mesh = mesh
		multimesh.instance_count = group.size()
		multimesh.buffer = packed_group_for(multimesh, group, tint_variation, world_origin)
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.custom_aabb = bounds_for_instance(multimesh, mesh, group)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = draw_distance
		instance.visibility_range_end_margin = fade_margin
		parent.add_child(instance)
		result.append(instance)
	return result
