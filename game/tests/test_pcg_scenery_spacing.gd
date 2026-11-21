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
	t.current = "PCG scale-aware self-pruning: larger instances take precedence"
	var scaled_points := PackedVector2Array([
		Vector2(0, 0), Vector2(0.9, 0), Vector2(3, 0),
		Vector2(3.8, 0), Vector2(-2.6, 0)])
	var sizes := PackedFloat32Array([0.5, 2.0, 1.0, 0.5, 1.2])
	var expected_scaled := PackedInt32Array([1, 2, 3, 4])
	t.eq(SceneryBatches.pcg_filter_indices_scaled(
		scaled_points, sizes, 1.0, 4096, true, false),
		expected_scaled, "large-to-small priority, output in stable original order")
	t.eq(SceneryBatches.pcg_filter_indices_scaled(
		scaled_points, sizes, 1.0, 4096, false, false),
		PackedInt32Array([0, 2, 3, 4]), "input-order alternative is supported")
	t.eq(SceneryBatches.pcg_filter_indices_scaled(
		scaled_points, sizes, 0.0, 2, true, false),
		PackedInt32Array([0, 1]), "zero spacing bypasses pruning")
	t.eq(SceneryBatches.pcg_filter_indices_scaled(
		scaled_points, PackedFloat32Array([1.0]), 1.0, 4096, true, false).size(),
		0, "mismatched scale lengths reject all points")
	var bad_sizes: PackedFloat32Array = sizes.duplicate()
	bad_sizes[4] = NAN
	t.eq(SceneryBatches.pcg_filter_indices_scaled(
		scaled_points, bad_sizes, 1.0, 4096, true, false).size(),
		0, "invalid late scale rejects atomically")
	bad_sizes[4] = 2.01
	t.eq(SceneryBatches.pcg_filter_indices_scaled(
		scaled_points, bad_sizes, 1.0, 4096, true, false).size(),
		0, "unbounded footprints are rejected")
	var crossing_points := PackedVector2Array([Vector2(0.99, -1), Vector2(2.01, -1)])
	t.eq(SceneryBatches.pcg_filter_indices_scaled(
		crossing_points, PackedFloat32Array([2.0, 2.0]), 1.0, 4096, false, false),
		PackedInt32Array([0]), "5x5 grid catches overlaps across two cells")
	t.eq(SceneryBatches.pcg_filter_indices_scaled(
		PackedVector2Array([Vector2.ZERO, Vector2(1.25, 0)]),
		PackedFloat32Array([0.5, 2.0]), 1.0, 4096, true, false),
		PackedInt32Array([0, 1]), "pairwise exclusion boundary is inclusive")
	var size_transforms: Array[Transform3D] = []
	for i in scaled_points.size():
		var p: Vector2 = scaled_points[i]
		size_transforms.append(Transform3D(Basis.IDENTITY.scaled(
			Vector3.ONE * sizes[i]), Vector3(p.x, 0, p.y)))
	var expected_transforms: Array[Transform3D] = [
		size_transforms[1], size_transforms[2], size_transforms[3], size_transforms[4]]
	t.eq(SceneryBatches.thin_cosmetic_transforms_scaled(size_transforms, 1.0, false),
		expected_transforms, "actual varying-scale MultiMesh transforms are pruned")
	t.eq(SceneryBatches.thin_cosmetic_transforms_scaled(size_transforms, 0.0, false),
		size_transforms, "disabled scale-aware spacing retains every transform")
	var original_transform: Transform3D = size_transforms[0]
	SceneryBatches.thin_cosmetic_transforms_scaled(size_transforms, 1.0, false)
	t.eq(size_transforms[0], original_transform, "caller transforms never mutate")
	var chunk_source := FileAccess.get_file_as_string("res://scripts/client/chunk_view.gd")
	t.check(chunk_source.contains("SceneryBatches.thin_cosmetic_transforms_scaled("),
		"Albion streamed scenery is wired to the scale-aware API")

	if ClassDB.class_exists("PCGSpatialFilter2D"):
		var native: Object = ClassDB.instantiate("PCGSpatialFilter2D")
		t.check(native != null and native.has_method("filter_indices"), "native PCG class registered")
		if native != null and native.has_method("filter_indices_scaled"):
			t.eq(native.call("filter_indices_scaled", scaled_points, sizes, 1.0),
				expected_scaled, "new native scaled method is registered and correct")
			t.eq(SceneryBatches.thin_cosmetic_transforms_scaled(size_transforms, 1.0),
				expected_transforms, "game scale-aware path uses native engine")
			var scale_rng := RandomNumberGenerator.new()
			scale_rng.seed = 253201
			for sample in 16:
				var random_points := PackedVector2Array()
				var random_scales := PackedFloat32Array()
				for i in 180:
					random_points.append(Vector2(scale_rng.randf_range(-50.0, 50.0),
						scale_rng.randf_range(-50.0, 50.0)))
					random_scales.append(scale_rng.randf_range(0.5, 2.0))
				for priority in [false, true]:
					t.eq(native.call("filter_indices_scaled",
						random_points, random_scales, 1.5, 4096, priority),
						SceneryBatches.pcg_filter_indices_scaled(
							random_points, random_scales, 1.5, 4096, priority, false),
						"native/fallback scaled parity sample %d priority %s" % [
							sample, str(priority)])
		else:
			t.eq(SceneryBatches.thin_cosmetic_transforms_scaled(size_transforms, 1.0),
				expected_transforms, "older native builds use scaled GDScript fallback")
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


	t.current = "3D PCG: size-aware cliff vegetation and native/script parity"
	var cliff_points := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0.9, 0, 0), Vector3(3, 0, 0),
		Vector3(3.8, 0, 0), Vector3(-2.6, 0, 0), Vector3(0.9, 3, 0)])
	var cliff_scales := PackedFloat32Array([0.5, 2.0, 1.0, 0.5, 1.2, 2.0])
	var expected_cliff := PackedInt32Array([1, 2, 3, 4, 5])
	t.eq(SceneryBatches.pcg_filter_indices_3d_scaled(
		cliff_points, cliff_scales, 1.0, 4096, true, false),
		expected_cliff, "large bushes win nearby overlap and elevated terraces remain")
	t.eq(SceneryBatches.pcg_filter_indices_3d_scaled(
		cliff_points, cliff_scales, 1.0, 4096, false, false),
		PackedInt32Array([0, 2, 3, 4, 5]), "optional input-order priority")
	t.eq(SceneryBatches.pcg_filter_indices_3d_scaled(
		cliff_points, cliff_scales, 0.0, 2, true, false),
		PackedInt32Array([0, 1]), "zero spacing preserves the first two original points")
	t.eq(SceneryBatches.pcg_filter_indices_3d_scaled(
		cliff_points, PackedFloat32Array([1.0]), 1.0, 4096, true, false).size(),
		0, "mismatched footprint array rejected before selection")
	var malformed_scales := cliff_scales.duplicate()
	malformed_scales[5] = NAN
	t.eq(SceneryBatches.pcg_filter_indices_3d_scaled(
		cliff_points, malformed_scales, 1.0, 4096, true, false).size(),
		0, "invalid late scale fails entire batch")
	var big_3d := PackedVector3Array([
		Vector3(0.99, -1.0, 0.99), Vector3(2.01, -1.0, 0.99),
		Vector3(0.99, 1.2, 0.99)])
	t.eq(SceneryBatches.pcg_filter_indices_3d_scaled(
		big_3d, PackedFloat32Array([2.0, 2.0, 2.0]), 1.0, 4096, false, false),
		PackedInt32Array([0, 2]), "5x5x5 buckets catch long overlaps but permit height separation")
	var cliff_transforms: Array[Transform3D] = []
	for i in cliff_points.size():
		cliff_transforms.append(Transform3D(
			Basis.IDENTITY.scaled(Vector3.ONE * cliff_scales[i]), cliff_points[i]))
	var kept_cliff := SceneryBatches.thin_cosmetic_transforms_3d(cliff_transforms, 1.0, false)
	var expected_cliff_transforms: Array[Transform3D] = []
	for index in expected_cliff:
		expected_cliff_transforms.append(cliff_transforms[index])
	t.eq(kept_cliff, expected_cliff_transforms, "real game cliff-bush transforms use scale-aware selection")
	t.eq(cliff_transforms.size(), 6, "scenery source never mutates authored transforms")
	var chunk_script: String = FileAccess.get_file_as_string("res://scripts/client/chunk_view.gd")
	t.check(chunk_script.contains("SceneryBatches.thin_cosmetic_transforms_3d("),
		"actual streamed bushes use the updated three-dimensional pruning")

	if ClassDB.class_exists("PCGSpatialFilter3D"):
		var native_scaled: Object = ClassDB.instantiate("PCGSpatialFilter3D")
		if native_scaled != null and native_scaled.has_method("filter_indices_scaled"):
			t.eq(native_scaled.call("filter_indices_scaled", cliff_points, cliff_scales, 1.0),
				expected_cliff, "Cgame native API chooses the expected cliff foliage")
			t.eq(SceneryBatches.thin_cosmetic_transforms_3d(cliff_transforms, 1.0),
				kept_cliff, "Albion uses native scaled 3D path")
			var scaled_rng := RandomNumberGenerator.new()
			scaled_rng.seed = 932561
			for sample in 12:
				var random_points := PackedVector3Array()
				var random_scales := PackedFloat32Array()
				for i in 120:
					random_points.append(Vector3(scaled_rng.randf_range(-25.0, 25.0),
						scaled_rng.randf_range(-8.0, 8.0),
						scaled_rng.randf_range(-25.0, 25.0)))
					random_scales.append(scaled_rng.randf_range(0.5, 2.0))
				for size_priority in [false, true]:
					t.eq(native_scaled.call("filter_indices_scaled",
						random_points, random_scales, 1.2, 4096, size_priority),
						SceneryBatches.pcg_filter_indices_3d_scaled(
							random_points, random_scales, 1.2, 4096, size_priority, false),
						"native/script 3D scaled parity %d: %s" % [
							sample, str(size_priority)])
		else:
			t.eq(SceneryBatches.thin_cosmetic_transforms_3d(cliff_transforms, 1.0),
				kept_cliff, "older engine binaries take deterministic scaled fallback")
