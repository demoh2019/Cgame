extends RefCounted
## Generate seamless heightfield normals from the same deterministic world
## height function used by the terrain mesh. Only outside-edge samples invoke
## World.height_at, so this does not multiply world-generation work per vertex.
## Terrain source height min/range are applied before differentiation to match
## the normalized values submitted to the engine.

static func _height(raw: PackedFloat32Array, origin: Vector2,
		count: int, step: float, minimum: float, maximum: float,
		sample_world: Callable, x: int, z: int) -> float:
	if x >= 0 and z >= 0 and x < count and z < count:
		return clampf(raw[z * count + x], minimum, maximum)
	return clampf(float(sample_world.call(
		origin.x + float(x) * step, origin.y + float(z) * step)), minimum, maximum)


static func build(raw: PackedFloat32Array, origin: Vector2,
		count: int, step: float, minimum: float, height_range: float,
		sample_world: Callable) -> PackedVector3Array:
	var normals := PackedVector3Array()
	if count < 2 or raw.size() != count * count or step <= 0.0 or height_range <= 0.0:
		return normals
	if not sample_world.is_valid():
		return normals
	normals.resize(count * count)
	var maximum: float = minimum + height_range
	var spacing: float = 2.0 * step
	for z in count:
		for x in count:
			var left: float = _height(raw, origin, count, step, minimum,
				maximum, sample_world, x - 1, z)
			var right: float = _height(raw, origin, count, step, minimum,
				maximum, sample_world, x + 1, z)
			var down: float = _height(raw, origin, count, step, minimum,
				maximum, sample_world, x, z - 1)
			var up: float = _height(raw, origin, count, step, minimum,
				maximum, sample_world, x, z + 1)
			normals[z * count + x] = Vector3(-(right - left) / spacing,
				1.0, -(up - down) / spacing).normalized()
	return normals
