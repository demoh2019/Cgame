extends RefCounted
## Native terrain derivative batches vs the original scalar atlas hillshade.

const HeightfieldGradients = preload("res://scripts/client/heightfield_gradients.gd")
const WorldMap = preload("res://scripts/client/world_map.gd")


func run(t) -> void:
	t.current = "heightfield gradient plane and clamped borders"
	var size := Vector2i(6, 5)
	var heights := PackedFloat32Array()
	heights.resize(size.x * size.y)
	for y in size.y:
		for x in size.x:
			heights[y * size.x + x] = float(2 * x + 3 * y)
	var original: PackedFloat32Array = heights.duplicate()
	var slopes: PackedVector2Array = HeightfieldGradients.compute(heights, size, 1.0)
	t.eq(slopes.size(), heights.size(), "one gradient returned per height sample")
	t.eq(slopes[2 * size.x + 2], Vector2(2.0, 3.0), "interior plane gradient")
	t.eq(slopes[2 * size.x], Vector2(1.0, 3.0), "left edge uses clamped neighbor")
	t.eq(slopes[2], Vector2(2.0, 1.5), "top edge uses clamped neighbor")
	t.eq(slopes[0], Vector2(1.0, 1.5), "corner uses two clamped directions")
	t.eq(heights, original, "calculation does not modify sampled world heights")
	var normal: Vector3 = HeightfieldGradients.surface_normal(Vector2(2.0, 3.0))
	t.near(normal.length(), 1.0, 0.00001, "world normal remains unit length")
	t.check(normal.y > 0.0 and normal.x < 0.0 and normal.z < 0.0,
		"gradient yields an upward-facing terrain normal")

	t.current = "native and fallback preserve atlas hillshade math"
	var varied := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 448129
	varied.resize(size.x * size.y)
	for i in varied.size():
		varied[i] = rng.randf_range(-15.0, 38.0)
	for spacing in [0.25, 1.0, 12.0]:
		var actual: PackedVector2Array = HeightfieldGradients.compute(varied, size, spacing)
		var scalar: PackedVector2Array = HeightfieldGradients.compute(varied, size, spacing, true)
		t.eq(actual.size(), varied.size(), "native output includes every pixel")
		for i in actual.size():
			t.check(actual[i].distance_to(scalar[i]) < 0.00002,
				"batch result matches GDScript central differences")
			var x: int = i % size.x
			var y: int = i / size.x
			var dx: float = (varied[y * size.x + mini(x + 1, size.x - 1)] 					- varied[y * size.x + maxi(x - 1, 0)]) / (2.0 * spacing)
			var dy: float = (varied[mini(y + 1, size.y - 1) * size.x + x] 					- varied[maxi(y - 1, 0) * size.x + x]) / (2.0 * spacing)
			t.check(actual[i].distance_to(Vector2(dx, dy)) < 0.00002,
				"original atlas stencil and batch slope match")
	t.eq(HeightfieldGradients.compute(PackedFloat32Array([7.0]), Vector2i.ONE, 1.0)[0],
		Vector2.ZERO, "singleton terrain gradient has zero slope")
	t.eq(HeightfieldGradients.compute(varied, Vector2i(5, 5), 1.0).size(), 0,
		"mismatched dimensions are rejected")
	t.eq(HeightfieldGradients.compute(varied, size, 0.0).size(), 0,
		"zero spacing is rejected")
	t.eq(HeightfieldGradients.compute(varied, size, -2.0).size(), 0,
		"negative spacing is rejected")
	var invalid := varied.duplicate()
	invalid[3] = NAN
	t.eq(HeightfieldGradients.compute(invalid, size, 1.0).size(), 0,
		"NaN heightmaps do not reach the renderer")
	var atlas_script: String = (WorldMap as Script).source_code
	t.check(atlas_script.contains("HeightfieldGradients.compute("),
		"actual map precomputes the native gradient field")
	t.check(atlas_script.contains("_height_slopes[row * PIXELS + column]"),
		"hillshade consumes precomputed gradients rather than sampling neighbors")
