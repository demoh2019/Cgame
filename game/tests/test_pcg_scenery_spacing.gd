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

	t.current = "3D PCG: cliffs, determinism, and fallback/native parity"
	var points_3d := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0.25, 0, 0), Vector3(0.25, 3, 0),
		Vector3(2, 0, 0), Vector3(0, 0, 2), Vector3(-2, 0, 0),
		Vector3(0.25, 3, 0), Vector3(2, 0, 2)])
	var expected_3d := PackedInt32Array([0, 2, 3, 4, 5, 7])
	t.eq(SceneryBatches.pcg_filter_indices_3d(points_3d, 2.0, 4096, false),
		expected_3d, "3D fallback preserves stacked elevations")
	var transforms_3d: Array[Transform3D] = []
	for point in points_3d:
		transforms_3d.append(Transform3D(Basis.IDENTITY, point))
	var before_3d := transforms_3d.duplicate()
	var thin_3d: Array[Transform3D] = SceneryBatches.thin_cosmetic_transforms_3d(
		transforms_3d, 2.0, false)
	t.eq(thin_3d.size(), expected_3d.size(), "3D spacing output count")
	for i in expected_3d.size():
		t.eq(thin_3d[i], transforms_3d[expected_3d[i]], "stable 3D index %d" % i)
	t.eq(transforms_3d, before_3d, "3D source transforms unchanged")
	t.eq(SceneryBatches.thin_cosmetic_transforms_3d(transforms_3d, 0.0, false),
		before_3d, "zero 3D spacing preserves all candidates")
	t.eq(SceneryBatches.pcg_filter_indices_3d(points_3d, 2.0, 2, false),
		PackedInt32Array([0, 2]), "3D output cap preserves order")
	var bad_3d: PackedVector3Array = points_3d.duplicate()
	bad_3d.append(Vector3(0, NAN, 0))
	t.eq(SceneryBatches.pcg_filter_indices_3d(bad_3d, 2.0, 4096, false).size(),
		0, "invalid late 3D point rejects entire batch")
	var borders_3d := PackedVector3Array([
		Vector3(0.95, 0.95, 0.95), Vector3(1.05, 1.05, 1.05),
		Vector3(-0.1, -0.1, -0.1), Vector3(-0.25, -0.2, -0.2), Vector3(3, 3, 3)])
	t.eq(SceneryBatches.pcg_filter_indices_3d(borders_3d, 1.0, 4096, false),
		PackedInt32Array([0, 2, 4]), "3D cells handle negative positions and boundaries")
	if ClassDB.class_exists("PCGSpatialFilter3D"):
		var native_3d: Object = ClassDB.instantiate("PCGSpatialFilter3D")
		t.check(native_3d != null and native_3d.has_method("filter_indices"),
			"3D engine class is registered")
		if native_3d != null and native_3d.has_method("filter_indices"):
			t.eq(native_3d.call("filter_indices", points_3d, 2.0), expected_3d,
				"native spatial thinning retains different elevation layers")
			t.eq(SceneryBatches.thin_cosmetic_transforms_3d(transforms_3d, 2.0),
				thin_3d, "Albion uses native 3D filter")
			var rng_3d := RandomNumberGenerator.new()
			rng_3d.seed = 925311
			for sample in 24:
				var random_points_3d := PackedVector3Array()
				for i in 180:
					random_points_3d.append(Vector3(rng_3d.randf_range(-50.0, 50.0),
						rng_3d.randf_range(-20.0, 20.0), rng_3d.randf_range(-50.0, 50.0)))
				t.eq(native_3d.call("filter_indices", random_points_3d, 2.5),
					SceneryBatches.pcg_filter_indices_3d(random_points_3d, 2.5, 4096, false),
					"3D engine/script parity sample %d" % sample)
	else:
		t.eq(SceneryBatches.thin_cosmetic_transforms_3d(transforms_3d, 2.0),
			thin_3d, "stock Godot uses deterministic script fallback")
