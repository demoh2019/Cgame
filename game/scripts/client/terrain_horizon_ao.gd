extends RefCounted
## Native terrain-horizon AO for high-quality open-world landscape.
## A small outer height halo makes the same border vertex see exactly the
## same surrounding relief when neighbouring chunks stream independently.

const RADIUS_STEPS := 6


static func build(raw: PackedFloat32Array, origin: Vector2, side: int,
		spacing: float, world_height: Callable,
		height_min: float, height_max: float) -> PackedFloat32Array:
	var output := PackedFloat32Array()
	if side < 2 or raw.size() != side * side or not is_finite(spacing) \
			or spacing <= 0.0 or not world_height.is_valid() or height_min >= height_max:
		return output
	var halo: int = RADIUS_STEPS
	var extended_side: int = side + halo * 2
	var grid := PackedFloat32Array()
	grid.resize(extended_side * extended_side)
	for z in extended_side:
		var source_z: int = z - halo
		var world_z: float = origin.y + float(source_z) * spacing
		for x in extended_side:
			var source_x: int = x - halo
			var height: float
			if source_x >= 0 and source_z >= 0 and source_x < side and source_z < side:
				height = raw[source_z * side + source_x]
			else:
				height = float(world_height.call(
					origin.x + float(source_x) * spacing, world_z))
			grid[z * extended_side + x] = clampf(height, height_min, height_max)
	# The forked engine does this eight-direction horizon integration in C++.
	# No pixel shader or texture samples are involved during gameplay.
	var padded_sky: PackedFloat32Array = ChunkedTerrain3D.bake_horizon_visibility(
		grid, Vector2i(extended_side, extended_side), spacing, halo)
	if padded_sky.size() != grid.size():
		return output
	output.resize(side * side)
	for z in side:
		for x in side:
			output[z * side + x] = padded_sky[
				(z + halo) * extended_side + x + halo]
	return output
