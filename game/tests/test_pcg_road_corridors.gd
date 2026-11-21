extends RefCounted
## Native PCGPathFalloff3D batch segment clearance vs Albion's scalar policy.
const SceneryBatches = preload("res://scripts/client/scenery_batches.gd")


func run(t) -> void:
	t.current = "PCG road corridor: source-order retention and inclusive clearance edge"
	var roads: Array = [
		[Vector2(0, 0), Vector2(10, 0)],
		[Vector2(10, 0), Vector2(10, 10)]]
	var spots: Array = [
		Vector2(5, 0), Vector2(5, 2), Vector2(5, 1.99),
		Vector2(10, 5), Vector2(12, 5), Vector2(12.01, 5),
		Vector2(0, -2), Vector2(0, -1), Vector2(50, 50)]
	var before: Array = spots.duplicate()
	var expected: Array = [spots[1], spots[4], spots[5], spots[6], spots[8]]
	var scalar: Array = SceneryBatches.filter_cosmetic_spots_outside_roads(
		spots, roads, 2.0, false)
	t.eq(scalar, expected, "nearby road points removed, exact boundary retained")
	t.eq(spots, before, "filter never edits a seeded candidate array")
	t.eq(SceneryBatches.filter_cosmetic_spots_outside_roads(
		spots, roads, 2.0, false), scalar, "repeatably deterministic road selection")
	t.eq(SceneryBatches.filter_cosmetic_spots_outside_roads(
		spots, [], 2.0, false), spots, "no road segments leaves all decor points")
	t.eq(SceneryBatches.filter_cosmetic_spots_outside_roads(
		spots, roads, 0.0, false), spots, "zero clearance excludes no candidates")

	t.current = "PCG independent segments and degenerate endpoint safety"
	var short_roads: Array = [
		[Vector2.ZERO, Vector2.ZERO],
		[Vector2(100, 100), Vector2(100, 100)]]
	var short_spots: Array = [
		Vector2.ZERO, Vector2(1, 0), Vector2(1.01, 0),
		Vector2(100, 100), Vector2(102, 100)]
	t.eq(SceneryBatches.filter_cosmetic_spots_outside_roads(
		short_spots, short_roads, 1.0, false),
		[short_spots[1], short_spots[2], short_spots[4]],
		"degenerate segments become circular exclusion disks")
	var many_segments: Array = []
	for i in 280:
		many_segments.append([Vector2(i * 2.0, 0), Vector2(i * 2.0, 5)])
	t.eq(SceneryBatches.filter_cosmetic_spots_outside_roads(
		spots, many_segments, 2.0, true),
		SceneryBatches.filter_cosmetic_spots_outside_roads(
			spots, many_segments, 2.0, false),
		"over-budget road graphs safely use old scalar checks")

	t.current = "Albion decoration uses the native corridor without changing RNG"
	var chunk_source := FileAccess.get_file_as_string("res://scripts/client/chunk_view.gd")
	t.check(chunk_source.contains("SceneryBatches.filter_cosmetic_spots_outside_roads("),
		"live streamed decoration routes candidate points through native PCG")
	t.check(chunk_source.contains("return SceneryBatches.filter_cosmetic_spots_outside_roads("),
		"road rejection runs after generation and all seeded draws")
	var generator := RandomNumberGenerator.new()
	generator.seed = 420721
	var random_before := generator.state
	SceneryBatches.filter_cosmetic_spots_outside_roads(spots, roads, 2.0, false)
	t.eq(generator.state, random_before, "road filtering never advances gameplay RNG")

	t.current = "Native batched road clearance matches independent scalar implementation"
	if ClassDB.class_exists("PCGPathFalloff3D"):
		var native: Object = ClassDB.instantiate("PCGPathFalloff3D")
		if native != null and native.has_method("filter_indices_outside_segments"):
			var points3 := PackedVector3Array()
			for point in spots:
				points3.append(Vector3(point.x, 0.0, point.y))
			var segments3 := PackedVector3Array([
				Vector3(0, 0, 0), Vector3(10, 0, 0),
				Vector3(10, 0, 0), Vector3(10, 0, 10)])
			t.eq(native.call("filter_indices_outside_segments",
				points3, segments3, 2.0, 16384),
				PackedInt32Array([1, 4, 5, 6, 8]),
				"native engine preserves exact original point indices")
			t.eq(SceneryBatches.filter_cosmetic_spots_outside_roads(
				spots, roads, 2.0), expected, "actual game uses native selector")
			var rng := RandomNumberGenerator.new()
			rng.seed = 193217
			for sample in 14:
				var random_roads: Array = []
				for road in 22:
					var a := Vector2(rng.randf_range(-35, 35),
						rng.randf_range(-35, 35))
					var b := a + Vector2(rng.randf_range(-15, 15),
						rng.randf_range(-15, 15))
					random_roads.append([a, b])
				var random_spots: Array = []
				for i in 180:
					random_spots.append(Vector2(rng.randf_range(-40, 40),
						rng.randf_range(-40, 40)))
				var expected_random: Array = SceneryBatches.filter_cosmetic_spots_outside_roads(
					random_spots, random_roads, 2.75, false)
				var actual_random: Array = SceneryBatches.filter_cosmetic_spots_outside_roads(
					random_spots, random_roads, 2.75)
				t.eq(actual_random, expected_random,
					"native/script batched corridor parity sample %d" % sample)
	else:
		t.eq(SceneryBatches.filter_cosmetic_spots_outside_roads(
			spots, roads, 2.0), expected,
			"stock Godot retains existing scalar decoration behavior")
