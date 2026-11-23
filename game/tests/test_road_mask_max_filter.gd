extends RefCounted
## Native grayscale morphological dilation, scalar oracle and real grass
## source integration. Runs without loading any terrain scene.

const Filter = preload("res://scripts/client/road_mask_max_filter.gd")
const GrassField = preload("res://scripts/client/grass_field.gd")
const Defs = preload("res://scripts/shared/defs.gd")


func run(t) -> void:
	t.current = "native grayscale max-filter with square neighborhood"
	var size := Vector2i(7, 5)
	var mask := PackedByteArray()
	mask.resize(size.x * size.y)
	mask[2 * size.x + 3] = 220
	mask[4 * size.x + 6] = 75
	var original: PackedByteArray = mask.duplicate()
	for radius in [0, 1, 2, 4, 64]:
		var result: PackedByteArray = Filter.compute(mask, size, radius)
		var scalar: PackedByteArray = Filter.compute(mask, size, radius, true)
		t.eq(result, scalar, "native and stock Godot agree for each dilation radius")
		t.eq(result.size(), mask.size(), "all raster pixels retained")
		for y in size.y:
			for x in size.x:
				var expected: int = 0
				for sy in range(maxi(y - radius, 0), mini(y + radius, size.y - 1) + 1):
					for sx in range(maxi(x - radius, 0), mini(x + radius, size.x - 1) + 1):
						expected = maxi(expected, mask[sy * size.x + sx])
				t.eq(result[y * size.x + x], expected, "grayscale dilation matches brute force")
	t.eq(mask, original, "max filter does not mutate source road mask")
	t.current = "linear-time fallback matches scalar oracle on irregular road masks"
	var irregular_size := Vector2i(19, 11)
	var irregular := PackedByteArray()
	irregular.resize(irregular_size.x * irregular_size.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90215
	for i in irregular.size():
		irregular[i] = rng.randi_range(0, 255)
	for radius in [1, 2, 4, 9, 24, 64]:
		var fast: PackedByteArray = Filter._compute_linear(irregular, irregular_size, radius)
		var expected: PackedByteArray = Filter.compute(irregular, irregular_size, radius, true)
		t.eq(fast, expected, "linear fallback equals scalar radius %d" % radius)
		t.eq(Filter.compute(irregular, irregular_size, radius), expected,
			"game entry point matches scalar radius %d" % radius)
	t.eq(irregular.size(), irregular_size.x * irregular_size.y,
		"optimization does not resize the original road mask")
	t.eq(Filter.compute(mask, Vector2i(4, 5), 2).size(), 0, "invalid raster length rejected")
	t.eq(Filter.compute(mask, size, -1).size(), 0, "negative radius rejected")
	t.eq(Filter.compute(mask, size, 65).size(), 0, "large radius rejected")

	t.current = "road shoulders keep old roads but clear large plants"
	var side: int = int(Defs.CHUNK_SIZE)
	var road := PackedByteArray()
	road.resize(side * side)
	road[10 * side + 10] = 240
	var heights := PackedFloat32Array([5.0, 5.0, 5.0, 5.0])
	var biomes := PackedStringArray(["plains", "plains", "plains", "plains"])
	var source := GrassField.Source.new(Vector2(256.0, 256.0),
			heights, 2, biomes, 2, road, PackedVector4Array())
	t.eq(source.road, road, "road texture and authoritative road mask stay unchanged")
	t.eq(source.road_clearance[10 * side + 12], 240, "2m shoulder expands exclusion on the right")
	t.eq(source.road_clearance[12 * side + 12], 240, "diagonal road clearance uses Chebyshev metric")
	t.eq(source.road_clearance[10 * side + 13], 0, "outside clearance remains eligible")
	t.eq(bool(GrassField.sample(source, 12.0, 10.0)["ok"]), false,
			"scanned rocks and plants cannot straddle road shoulder")
	t.eq(bool(GrassField.sample(source, 13.0, 10.0)["ok"]), true,
			"ground cover beyond clearance continues to grow")
	var source_code: String = (GrassField as Script).source_code
	t.check(source_code.contains("RoadMaskMaxFilter.compute("),
			"real chunk grass source generates its own road clearance mask")
	t.check(source_code.contains("if not on_road and on_shoulder"),
			"procedural grass keeps a softer lower-density shoulder")
