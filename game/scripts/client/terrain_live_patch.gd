extends RefCounted
## Debug-only authored terrain brush for the REAL streamed ChunkedTerrain3D.
## It never changes authoritative ground height, physics or player state.
## Uses the engine's validated rectangular patch, not set_height_data(), so
## unrelated terrain chunks keep their meshes, LOD caches and collision RIDs.


static func apply_visual_brush(terrain: Node3D, world_point: Vector3,
		radius_m: float = 2.0, raise_m: float = 0.75) -> bool:
	if terrain == null or not terrain.has_method("apply_height_patch") or \
			not terrain.has_method("is_over_terrain") or \
			not terrain.has_method("get_height_data") or \
			not terrain.has_method("get_height_dimensions"):
		return false
	if not world_point.is_finite() or not is_finite(radius_m) or \
			not is_finite(raise_m) or radius_m <= 0.0 or \
			radius_m > 4.0 or absf(raise_m) > 3.0 or raise_m == 0.0:
		return false
	if not bool(terrain.call("is_over_terrain", world_point)):
		return false

	var dimensions: Vector2i = terrain.call("get_height_dimensions")
	var world_size: Vector2 = terrain.get("size")
	var height_scale: float = float(terrain.get("height_scale"))
	if dimensions.x < 2 or dimensions.y < 2 or \
			not world_size.is_finite() or world_size.x <= 0.0 or world_size.y <= 0.0 or \
			not is_finite(height_scale) or absf(height_scale) <= 0.00001:
		return false
	var stride := Vector2(world_size.x / float(dimensions.x - 1),
		world_size.y / float(dimensions.y - 1))
	var local: Vector3 = terrain.to_local(world_point)
	var center := Vector2(local.x / stride.x, local.z / stride.y)
	var extent := Vector2(radius_m / stride.x, radius_m / stride.y)
	var min_x: int = maxi(0, floori(center.x - extent.x))
	var min_z: int = maxi(0, floori(center.y - extent.y))
	var max_x: int = mini(dimensions.x - 1, ceili(center.x + extent.x))
	var max_z: int = mini(dimensions.y - 1, ceili(center.y + extent.y))
	var patch_size := Vector2i(max_x - min_x + 1, max_z - min_z + 1)
	if patch_size.x <= 0 or patch_size.y <= 0 or \
			patch_size.x * patch_size.y > 4096:
		return false

	# The full height array is read ONLY when the debug hotkey is pressed.
	# The native engine consumes only this small rectangular replacement.
	var source: PackedFloat32Array = terrain.call("get_height_data")
	if source.size() != dimensions.x * dimensions.y:
		return false
	var patch := PackedFloat32Array()
	patch.resize(patch_size.x * patch_size.y)
	for z in patch_size.y:
		for x in patch_size.x:
			var sample_x: int = min_x + x
			var sample_z: int = min_z + z
			var original: float = source[sample_z * dimensions.x + sample_x]
			var separation: float = Vector2(
				(float(sample_x) - center.x) * stride.x,
				(float(sample_z) - center.y) * stride.y).length()
			var influence: float = maxf(0.0, 1.0 - separation / radius_m)
			patch[z * patch_size.x + x] = clampf(
				original + raise_m / height_scale * influence, 0.0, 1.0)
	return bool(terrain.call("apply_height_patch",
		Rect2i(Vector2i(min_x, min_z), patch_size), patch))


static func apply_to_streamed_world(tree: SceneTree, world_point: Vector3) -> bool:
	if tree == null:
		return false
	# A single explicitly requested debug brush. Normal gameplay performs
	# no group iteration or terrain data copies. Only cosmetic terrain moves:
	# server-owned collision and movement rules are never touched.
	for candidate in tree.get_nodes_in_group("aa_chunked_terrain_lod"):
		if candidate is Node3D and bool(candidate.call("is_over_terrain", world_point)):
			if apply_visual_brush(candidate, world_point):
				candidate.call("force_update")
				return true
			return false
	return false
