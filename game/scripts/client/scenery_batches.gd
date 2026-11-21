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
