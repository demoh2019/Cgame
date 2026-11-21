extends RefCounted
## Native PCGSpatialFilter2D vs deterministic stock-Godot cosmetic fallback.
const SceneryBatches = preload("res://scripts/client/scenery_batches.gd")


func run(t) -> void:
	t.current = "PCG decor spacing: deterministic stable candidate order"
	var transforms: Array[Transform3D] = []
	for at in [Vector2(0, 0), Vector2(0.5, 0), Vector2(2, 0),
			Vector2(-2, 0), Vector2(2, 1), Vector2(0, 0), Vector2(2, 2)]:
		transforms.append(Transform3D(Basis.IDENTITY, Vector3(at.x, 0, at.y)))
	var before: Array[Transform3D] = transforms.duplicate()
	var spaced: Array[Transform3D] = SceneryBatches.thin_cosmetic_transforms(transforms, 2.0, false)
	t.eq(spaced.size(), 4, "only points with at least two metres separation retained")
	t.eq(spaced[0], transforms[0], "first candidate is always retained")
	t.eq(spaced[1], transforms[2], "exact distance boundary is inclusive")
	t.eq(spaced[2], transforms[3], "negative coordinate candidate retained")
	t.eq(spaced[3], transforms[6], "later separated candidate retained")
	t.eq(transforms, before, "filter never mutates source transforms")
	t.eq(SceneryBatches.thin_cosmetic_transforms(transforms, 0.0, false),
		before, "zero spacing preserves every cosmetic transform")
	t.eq(SceneryBatches.thin_cosmetic_transforms(transforms, 2.0, false),
		spaced, "stream unload/reload is deterministic")

	t.current = "PCG minimum distance: native and fallback parity"
	var candidates := PackedVector2Array()
	for at in [Vector2(0.95, 0), Vector2(1.05, 0), Vector2(2.5, 0),
			Vector2(-1, 0), Vector2(-1.3, 0), Vector2(4.2, 0)]:
		candidates.append(at)
	var expected: PackedInt32Array = SceneryBatches.pcg_filter_indices(
		candidates, 1.0, 4096, false)
	t.eq(expected, PackedInt32Array([0, 2, 3, 5]), "negative and adjacent cells checked")
	t.eq(SceneryBatches.pcg_filter_indices(candidates, 1.0, 2, false),
		PackedInt32Array([0, 2]), "stable output cap")
	t.eq(SceneryBatches.pcg_filter_indices(candidates, -1.0, 4096, false).size(),
		0, "invalid spacing rejected")
	var bad: PackedVector2Array = candidates.duplicate()
	bad.append(Vector2(NAN, 0))
	t.eq(SceneryBatches.pcg_filter_indices(bad, 1.0, 4096, false).size(),
		0, "NaN in late candidate rejects entire input")
	if ClassDB.class_exists("PCGSpatialFilter2D"):
		var native: Object = ClassDB.instantiate("PCGSpatialFilter2D")
		t.check(native != null and native.has_method("filter_indices"), "native PCG class registered")
		if native != null and native.has_method("filter_indices"):
			t.eq(native.call("filter_indices", candidates, 1.0), expected,
				"native grid matches fallback for border cells")
			t.eq(SceneryBatches.thin_cosmetic_transforms(transforms, 2.0),
				spaced, "actual game filter invokes native class")
			var rng := RandomNumberGenerator.new()
			rng.seed = 253199
			for sample in 24:
				var random_points := PackedVector2Array()
				for i in 180:
					random_points.append(Vector2(rng.randf_range(-50.0, 50.0),
						rng.randf_range(-50.0, 50.0)))
				t.eq(native.call("filter_indices", random_points, 1.5),
					SceneryBatches.pcg_filter_indices(random_points, 1.5, 4096, false),
					"native/fallback parity sample %d" % sample)
				t.eq(native.call("filter_indices", random_points, 0.0, 25),
					SceneryBatches.pcg_filter_indices(random_points, 0.0, 25, false),
					"zero-spacing output cap parity sample %d" % sample)
	else:
		t.eq(SceneryBatches.thin_cosmetic_transforms(transforms, 2.0),
			spaced, "stock Godot uses identical cosmetic spacing fallback")
