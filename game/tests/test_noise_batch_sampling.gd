extends RefCounted
## Verifies world-map biome parity on Cgame's native batch and stock-Godot fallback.

const WorldGen = preload("res://scripts/shared/world_gen.gd")


func run(t) -> void:
	t.current = "noise batch fallback"
	var noise := FastNoiseLite.new()
	noise.seed = 81
	noise.frequency = 0.021
	var points := PackedVector2Array([Vector2(-7.75, 4.5), Vector2.ZERO, Vector2(23.5, -91.0), Vector2(-7.75, 4.5)])
	var scalar: PackedFloat64Array = WorldGen._sample_noise_2dv(noise, points, true)
	t.eq(scalar.size(), points.size(), "scalar fallback returns exactly one value per point")
	for i in points.size():
		t.near(scalar[i], noise.get_noise_2d(points[i].x, points[i].y), 0.000001, "scalar noise parity")
	if noise.has_method("get_noise_2dv_batch"):
		var native: PackedFloat64Array = WorldGen._sample_noise_2dv(noise, points)
		t.eq(native.size(), scalar.size(), "native batch sample count")
		for i in points.size():
			t.near(native[i], scalar[i], 0.000001, "native and fallback values agree")
	t.eq(WorldGen._sample_noise_2dv(noise, PackedVector2Array()).size(), 0, "empty batch is empty")

	t.current = "world map batch biome parity"
	var world := WorldGen.new(812)
	var locations := PackedVector2Array()
	var heights := PackedFloat64Array()
	for row in 5:
		for column in 19:
			var x: float = -3150.0 + float(column) * 347.5
			var z: float = -2800.0 + float(row) * 1327.5
			locations.append(Vector2(x, z))
			heights.append(world.height_at(x, z))
	var biomes: PackedStringArray = world.biomes_at_points(locations, heights)
	t.eq(biomes.size(), locations.size(), "one biome for every chart point")
	for i in locations.size():
		t.eq(biomes[i], world.biome_at(locations[i].x, locations[i].y), "batched biome matches scalar")
	t.eq(world.biomes_at_points(locations, PackedFloat64Array()).size(), 0, "mismatched point and height counts are rejected")
