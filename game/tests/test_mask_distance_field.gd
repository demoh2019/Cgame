extends RefCounted
## Exact eight-connected raster distances and native/GDScript parity.

const MaskDistanceField = preload("res://scripts/client/mask_distance_field.gd")


func run(t) -> void:
	t.current = "mask distance transform finite grid"
	var size := Vector2i(7, 5)
	var mask := PackedByteArray()
	mask.resize(size.x * size.y)
	for point in [Vector2i(2, 2), Vector2i(6, 0), Vector2i(0, 4)]:
		mask[point.y * size.x + point.x] = 100
	var before: PackedByteArray = mask.duplicate()
	for limit in [0, 1, 2, 7]:
		var scalar: PackedByteArray = MaskDistanceField.compute(mask, size, limit, true)
		var actual: PackedByteArray = MaskDistanceField.compute(mask, size, limit)
		t.eq(actual, scalar, "native and fallback produce identical chessboard distances")
		for y in size.y:
			for x in size.x:
				var expected: int = 255
				for row in size.y:
					for column in size.x:
						if mask[row * size.x + column] == 0:
							continue
						var distance: int = maxi(absi(x - column), absi(y - row))
						if distance <= limit:
							expected = mini(expected, distance)
				t.eq(actual[y * size.x + x], expected, "two-pass result matches brute-force nearest land")
	t.eq(mask, before, "input binary mask is unchanged")
	t.eq(MaskDistanceField.compute(mask, Vector2i(5, 5)).size(), 0, "mismatched dimensions rejected")
	t.eq(MaskDistanceField.compute(mask, size, 255).size(), 0, "invalid radius rejected")
	t.eq(MaskDistanceField.compute(mask, Vector2i.ZERO).size(), 0, "empty dimensions rejected")
	var all_water := PackedByteArray()
	all_water.resize(size.x * size.y)
	var all_distant: PackedByteArray = MaskDistanceField.compute(all_water, size, 7)
	t.eq(all_distant.count(255), all_distant.size(), "empty feature mask returns all unreachable cells")
	var all_land := PackedByteArray()
	all_land.resize(size.x * size.y)
	all_land.fill(1)
	var all_zero: PackedByteArray = MaskDistanceField.compute(all_land, size, 7)
	t.eq(all_zero.count(0), all_zero.size(), "all features have zero distance")

	t.current = "world map coastline from sampled heights"
	var heights := PackedFloat32Array()
	heights.resize(25)
	heights.fill(-12.0)
	heights[12] = 6.0
	var shore: PackedByteArray = MaskDistanceField.from_heights(heights, Vector2i(5, 5), 0.0, 2)
	t.eq(shore.size(), heights.size(), "chart heightmap produces one distance per pixel")
	t.eq(shore[12], 0, "land pixel has zero distance")
	t.eq(shore[0], 2, "diagonal coastline falls at two pixels")
	t.eq(shore[2 * 5 + 3], 1, "coastline reaches side-adjacent sea pixel")
	t.eq(shore, MaskDistanceField.from_heights(heights, Vector2i(5, 5), 0.0, 2, true),
		"sampled coastlines agree on native and stock-Godot paths")
	t.eq(MaskDistanceField.from_heights(PackedFloat32Array([NAN]), Vector2i(1, 1), 0.0).size(),
		0, "nonfinite height values are rejected")
