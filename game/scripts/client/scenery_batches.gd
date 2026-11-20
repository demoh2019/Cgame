extends RefCounted
## Chunk-local GPU instancing with spatial culling.
## A MultiMesh is culled as a whole, not per instance: large decoration batches
## unnecessarily draw all flowers when just one corner enters the view.
## Subdivide only busy meshes into 32 m tiles to keep draw-call costs bounded.

const TILE_SIZE := 32.0
const SPLIT_MIN_INSTANCES := 48
const BOUNDS_MARGIN := 0.6 # Mesh movement in wind and imprecise imported bounds.


## Preserves placement and input order; a small batch remains a single draw call.
static func partition(transforms: Array[Transform3D]) -> Array:
	if transforms.is_empty():
		return []
	if transforms.size() < SPLIT_MIN_INSTANCES:
		return [transforms]
	var buckets: Dictionary = {}
	var order: Array[Vector2i] = []
	for transform in transforms:
		var tile := Vector2i(floori(transform.origin.x / TILE_SIZE), floori(transform.origin.z / TILE_SIZE))
		if not buckets.has(tile):
			buckets[tile] = []
			order.append(tile)
		(buckets[tile] as Array).append(transform)
	var result: Array = []
	for tile in order:
		result.append(buckets[tile])
	return result


## Custom bounds are in the parent's local coordinates, matching MultiMesh transforms.
## Include full mesh extents and rotation; using only placement centers could clip trees.
static func bounds_for(mesh: Mesh, transforms: Array) -> AABB:
	var bounds: AABB = transforms[0] * mesh.get_aabb()
	for i in range(1, transforms.size()):
		bounds = bounds.merge(transforms[i] * mesh.get_aabb())
	return bounds.grow(BOUNDS_MARGIN)


## Visual-only props: instancing stays on the GPU and no physics/server nodes are made.
static func add(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D], draw_distance: float, cast_shadows: bool = false, fade_margin: float = 8.0) -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	if mesh == null or transforms.is_empty():
		return result
	for group in partition(transforms):
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = group.size()
		for i in group.size():
			multimesh.set_instance_transform(i, group[i])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.custom_aabb = bounds_for(mesh, group)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = draw_distance
		instance.visibility_range_end_margin = fade_margin
		parent.add_child(instance)
		result.append(instance)
	return result
