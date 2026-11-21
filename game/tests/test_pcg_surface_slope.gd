extends RefCounted
## Unreal-inspired native PCG slope and elevation selection, stock-Godot parity.
const SceneryBatches = preload("res://scripts/client/scenery_batches.gd")


func run(t) -> void:
	t.current = "surface PCG normal and elevation limits"
	var positions := PackedVector3Array([
		Vector3(0, 10, 0), Vector3(2, 20, 0), Vector3(4, 30, 0),
		Vector3(6, 40, 0), Vector3(8, 50, 0)])
	var normals := PackedVector3Array([
		Vector3.UP, Vector3(0, 0.8660254, 0.5),
		Vector3(0, 0.5, 0.8660254), Vector3.RIGHT, Vector3.DOWN])
	var saved: PackedVector3Array = positions.duplicate()
	var flat := PackedInt32Array([0, 1])
	t.eq(SceneryBatches.pcg_surface_filter_indices(
		positions, normals, 0.0, 35.0, -10000000.0, 10000000.0,
		4096, false), flat, "flat ground and gentle slopes retained")
	t.eq(SceneryBatches.pcg_surface_filter_indices(
		positions, normals, 45.0, 90.0, 25.0, 45.0,
		4096, false), PackedInt32Array([2, 3]),
		"cliff and vertical selections respect elevation range")
	t.eq(SceneryBatches.pcg_surface_filter_indices(
		positions, normals, 0.0, 90.0, -10000000.0, 10000000.0,
		4096, false), PackedInt32Array([0, 1, 2, 3]),
		"downward-facing terrain normals are not selected")
	t.eq(SceneryBatches.pcg_surface_filter_indices(
		positions, normals, 0.0, 35.0, 20.0, 20.0,
		4096, false), PackedInt32Array([1]),
		"inclusive exact height bounds")
	t.eq(SceneryBatches.pcg_surface_filter_indices(
		positions, normals, 0.0, 35.0, -10000000.0, 10000000.0,
		1, false), PackedInt32Array([0]), "bounded results preserve input order")
	t.eq(SceneryBatches.pcg_surface_filter_indices(
		positions, normals, 0.0, 35.0, -10000000.0, 10000000.0,
		0, false).size(), 0, "zero selection budget")
	t.eq(positions, saved, "surface sampling never mutates source points")

	t.current = "surface PCG fail-closed validation"
	var late_bad: PackedVector3Array = normals.duplicate()
	late_bad[4] = Vector3.ZERO
	t.eq(SceneryBatches.pcg_surface_filter_indices(
		positions, late_bad, 0.0, 90.0, -10000000.0, 10000000.0,
		4096, false).size(), 0,
		"invalid late normal invalidates the entire input")
	late_bad[4] = Vector3(NAN, 1, 0)
	t.eq(SceneryBatches.pcg_surface_filter_indices(
		positions, late_bad, 0.0, 90.0, -10000000.0, 10000000.0,
		4096, false).size(), 0, "nonfinite normals rejected")
	t.eq(SceneryBatches.pcg_surface_filter_indices(
		positions, PackedVector3Array([Vector3.UP]), 0.0, 35.0,
		-10000000.0, 10000000.0, 4096, false).size(), 0,
		"mismatched normals rejected")
	t.eq(SceneryBatches.pcg_surface_filter_indices(
		positions, normals, 45.0, 35.0, -10000000.0, 10000000.0,
		4096, false).size(), 0, "inverted slope bounds rejected")
	t.eq(SceneryBatches.pcg_surface_filter_indices(
		positions, normals, 0.0, 91.0, -10000000.0, 10000000.0,
		4096, false).size(), 0, "over-vertical slope bounds rejected")

	t.current = "Albion cosmetic surface filter selection"
	var transforms: Array[Transform3D] = []
	for point in positions:
		transforms.append(Transform3D(Basis.IDENTITY, point))
	var before: Array[Transform3D] = transforms.duplicate()
	t.eq(SceneryBatches.filter_cosmetic_transforms_surface(
		transforms, normals, 0.0, 35.0, -10000000.0,
		10000000.0, false), [transforms[0], transforms[1]],
		"visual transforms honor the sampled slope")
	t.eq(SceneryBatches.filter_cosmetic_transforms_surface(
		transforms, normals, 0.0, 35.0, 20.0, 20.0,
		false), [transforms[1]], "visual transforms honor altitude constraints")
	t.eq(SceneryBatches.filter_cosmetic_transforms_surface(
		transforms, normals, 0.0, 10.0, 35.0, 40.0, false).size(),
		0, "valid no-match surface rules remove unsuitable cosmetic plants")
	t.eq(SceneryBatches.filter_cosmetic_transforms_surface(
		transforms, late_bad, 0.0, 35.0, -10000000.0,
		10000000.0, false), before,
		"bad normal input retains original visual objects rather than losing them")
	t.eq(transforms, before, "screening never changes seeded transform inputs")
	var scene: String = FileAccess.get_file_as_string("res://scripts/client/chunk_view.gd")
	t.check(scene.contains("SceneryBatches.filter_cosmetic_transforms_surface("),
		"streamed foliage is connected to surface PCG filter")
	t.check(scene.contains("_world.normal_at("),
		"actual terrain normals are sampled by streamed decoration")
	t.check(scene.contains("max_surface_slope") and scene.contains("max_surface_height"),
		"flora entries have explicit editable surface placement policies")

	t.current = "PCGSurfaceFilter3D native/stock-Godot parity"
	if ClassDB.class_exists("PCGSurfaceFilter3D"):
		var native: Object = ClassDB.instantiate("PCGSurfaceFilter3D")
		t.check(native != null and native.has_method("filter_indices"),
			"native surface selection API is registered")
		if native != null and native.has_method("filter_indices"):
			t.eq(native.call("filter_indices", positions, normals, 0.0, 35.0,
				-10000000.0, 10000000.0, 4096), flat,
				"native surface matches flat and gentle slope expectations")
			t.eq(native.call("filter_indices", positions, late_bad, 0.0, 35.0,
				-10000000.0, 10000000.0, 4096).size(), 0,
				"native rejects all late-invalid normals")
			var rng := RandomNumberGenerator.new()
			rng.seed = 194655
			for sample in 20:
				var random_points := PackedVector3Array()
				var random_normals := PackedVector3Array()
				for i in 240:
					random_points.append(Vector3(rng.randf_range(-60.0, 60.0),
						rng.randf_range(-70.0, 120.0), rng.randf_range(-60.0, 60.0)))
					random_normals.append(Vector3(rng.randf_range(-1.0, 1.0),
						rng.randf_range(-0.2, 1.0),
						rng.randf_range(-1.0, 1.0)))
				t.eq(native.call("filter_indices", random_points, random_normals,
					8.0, 52.0, -20.0, 95.0, 4096),
					SceneryBatches.pcg_surface_filter_indices(random_points,
						random_normals, 8.0, 52.0, -20.0, 95.0, 4096, false),
					"native/fallback randomized slope-height parity %d" % sample)
	else:
		t.eq(SceneryBatches.pcg_surface_filter_indices(positions, normals, 0.0,
			35.0), flat, "stock Godot uses deterministic fallback")
