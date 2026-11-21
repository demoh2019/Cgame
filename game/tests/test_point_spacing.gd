extends RefCounted
## Ordered 2D self-pruning parity for seeded cosmetic foliage scatter.

const PointSpacing = preload("res://scripts/client/point_spacing.gd")
const GroundPlants = preload("res://scripts/client/ground_plants.gd")


func run(t) -> void:
	t.current = "ordered minimum-distance pruning"
	var points := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.4, 0.0), Vector2(1.0, 0.0),
		Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(-1.0, -1.0)
	])
	var expected := PackedInt32Array([0, 2, 4, 5])
	t.eq(PointSpacing.keep_indices(points, 1.0, -1, true), expected,
		"scalar pruning retains first point and exact-distance boundary")
	t.eq(PointSpacing.keep_indices(points, 1.0), expected,
		"native pruning matches stable scalar order")
	t.eq(PointSpacing.keep_indices(points, 1.0, 2), PackedInt32Array([0, 2]),
		"selection limit stops after accepted candidates")
	t.eq(PointSpacing.keep_indices(points, 0.0).size(), points.size(),
		"zero separation permits duplicates")
	t.eq(PointSpacing.keep_indices(points, 1.0, 0).size(), 0,
		"zero maximum keeps no points")
	t.eq(PointSpacing.keep_indices(points, -1.0).size(), 0, "invalid separation rejected")
	t.eq(PointSpacing.keep_indices(PackedVector2Array([Vector2(INF, 0)]), 2.0).size(),
		0, "infinite source coordinates rejected")

	t.current = "seeded decorative point scatter"
	var seed := 388711
	var rect := Rect2(Vector2(-13.0, 5.0), Vector2(16.0, 16.0))
	var random_a := RandomNumberGenerator.new()
	random_a.seed = seed
	var random_b := RandomNumberGenerator.new()
	random_b.seed = seed
	var native: PackedVector2Array = PointSpacing.candidates(random_a, rect, 128, 1.0, 32)
	var scalar: PackedVector2Array = PointSpacing.candidates(random_b, rect, 128, 1.0, 32, true)
	t.eq(native, scalar, "native and scalar retain precisely the same seeded candidates")
	t.check(native.size() >= 20 and native.size() <= 32,
		"reasonable decorative prop count respects maximum")
	for i in native.size():
		t.check(rect.has_point(native[i]), "kept point remains inside its tile")
		for j in range(i + 1, native.size()):
			t.check(native[i].distance_squared_to(native[j]) >= 1.0 - 0.00001,
				"all kept stones satisfy minimum spacing")
	var source: String = (GroundPlants as Script).source_code
	t.check(source.contains("PointSpacing.candidates(rng"),
		"real game tile scatter applies native point pruning")
	t.check(source.contains('"boulders"') and source.contains('"stones"'),
		"large rocks and small stone decals use spacing")
	t.check(source.contains("centers.is_empty()"),
		"flower clusters still use their original artistic scatter")
