extends RefCounted
## Designer/debug bridge: convert the authoritative world height sampler to a
## native HeightmapTerrain3D preview with bounded, live-updated static collision.
## This is an offline/authoring helper, not an extra collision layer in the
## server-authoritative streamed gameplay world.
const EngineFeatures = preload("res://scripts/client/engine_features.gd")


static func build_patch(world, origin: Vector2, cells: int = 32,
		cell_size: float = 2.0, collision_step: int = 2) -> Node3D:
	if world == null or not world.has_method("height_at"):
		return null
	if not EngineFeatures.has("HeightmapTerrain3D"):
		return null
	if cells < 1 or cells > 128 or not is_finite(cell_size) or cell_size <= 0.0:
		return null
	if collision_step < 1 or collision_step > 16:
		return null
	var terrain: Node3D = EngineFeatures.make("HeightmapTerrain3D") as Node3D
	if terrain == null or not terrain.has_method("set_auto_collision_enabled"):
		return null
	var samples: int = cells + 1
	var heights := PackedFloat32Array()
	heights.resize(samples * samples)
	for z in samples:
		for x in samples:
			var y: float = float(world.height_at(origin.x + float(x) * cell_size,
				origin.y + float(z) * cell_size))
			if not is_finite(y):
				terrain.free()
				return null
			heights[z * samples + x] = y
	var heightmap = terrain.get("heightmap")
	heightmap.set_dimensions(samples, samples)
	heightmap.set_heights(heights)
	terrain.set("cell_size", cell_size)
	terrain.call("set_auto_collision_step", collision_step)
	terrain.call("set_auto_collision_enabled", true)
	terrain.position = Vector3(origin.x, 0.0, origin.y)
	terrain.name = "AlbionTerrainCollisionPreview"
	return terrain
