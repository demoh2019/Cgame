extends RefCounted
## Unreal AlignToNormal-style native and stock-Godot parity for visual scenery.
const SceneryBatches = preload("res://scripts/client/scenery_batches.gd")


func run(t) -> void:
	t.current = "PCG terrain-normal alignment preserves seeded instance transforms"
	var original: Array[Transform3D] = [
		Transform3D(Basis(Vector3.UP, 0.3).scaled(Vector3.ONE * 1.5), Vector3(7, 13, -2)),
		Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3.ONE * 2.0), Vector3(11, 15, -8)),
		Transform3D(Basis(Vector3.UP, 1.2).scaled(Vector3.ONE * 0.5), Vector3(-3, 0, 9)),
	]
	var untouched: Array[Transform3D] = original.duplicate()
	var normals := PackedVector3Array([Vector3.UP,
		Vector3(0.0, 0.70710678, 0.70710678), Vector3.RIGHT])
	var aligned: Array[Transform3D] = SceneryBatches.align_cosmetic_transforms_surface(
		original, normals, 30.0, false)
	t.eq(aligned.size(), original.size(), "visual alignment keeps all source instances")
	t.eq(aligned[0], original[0], "flat surface preserves existing random yaw")
	t.eq(aligned[1].origin, original[1].origin, "sloped surface never moves geometry")
	t.eq(aligned[2].origin, original[2].origin, "cliff surface never moves geometry")
	t.near(aligned[1].basis.y.length(), 2.0, 0.0001,
		"yaw-scaled bushes and rocks preserve authored scaling")
	t.near(aligned[1].basis.y.normalized().y, cos(deg_to_rad(30.0)),
		0.0001, "45-degree normal is clamped to a 30-degree prop tilt")
	t.near(aligned[2].basis.y.normalized().y, cos(deg_to_rad(30.0)),
		0.0001, "vertical surface is also clamped to the maximum tilt")
	t.check(aligned[1].basis.y.normalized().z > 0.0,
		"lean direction matches the positive-Z downhill normal")
	t.eq(original, untouched, "procedural seed transforms remain unchanged")
	t.eq(SceneryBatches.align_cosmetic_transforms_surface(
		original, normals, 0.0, false), original,
		"zero tilt preserves existing orientation for every instance")
	t.eq(SceneryBatches.align_cosmetic_transforms_surface(
		original, normals, 30.0, false), aligned,
		"repeated chunk load computes deterministic transforms")

	t.current = "surface alignment rejects invalid batches atomically"
	var invalid: PackedVector3Array = normals.duplicate()
	invalid[2] = Vector3.ZERO
	t.eq(SceneryBatches.align_cosmetic_transforms_surface(
		original, invalid, 30.0, false), original,
		"bad late surface normal retains original visible decorations")
	invalid[2] = Vector3.DOWN
	t.eq(SceneryBatches.align_cosmetic_transforms_surface(
		original, invalid, 30.0, false), original,
		"downward-facing surface is not used as a valid terrain plane")
	invalid[2] = Vector3(0, NAN, 1)
	t.eq(SceneryBatches.align_cosmetic_transforms_surface(
		original, invalid, 30.0, false), original,
		"non-finite normal cannot corrupt the whole cosmetic group")
	t.eq(SceneryBatches.align_cosmetic_transforms_surface(
		original, PackedVector3Array([Vector3.UP]), 30.0, false),
		original, "mismatched normals keep original visual objects")
	t.eq(SceneryBatches.align_cosmetic_transforms_surface(
		original, normals, -1.0, false), original,
		"negative tilt caps safely fail open in gameplay")
	t.eq(SceneryBatches.align_cosmetic_transforms_surface(
		original, normals, 91.0, false), original,
		"over-vertical tilt caps safely fail open in gameplay")

	t.current = "PCG normal alignment is wired to actual streamable pebbles"
	var game_script := FileAccess.get_file_as_string("res://scripts/client/chunk_view.gd")
	t.check(game_script.contains("SceneryBatches.align_cosmetic_transforms_surface("),
		"streamed Albion decoration calls engine alignment")
	t.check(game_script.contains("alignment_normals.append(_world.normal_at("),
		"surface normals are sampled after cosmetic transform generation")
	t.check(game_script.contains('"file": "Pebble_Round_1"') and
		game_script.contains('"file": "Pebble_Square_2"') and
		game_script.contains('"max_surface_tilt": 35.0'),
		"both instanced pebble categories opt into gentle terrain alignment")

	t.current = "PCG AlignToNormal native/stock Godot parity"
	if ClassDB.class_exists("PCGSurfaceFilter3D"):
		var native: Object = ClassDB.instantiate("PCGSurfaceFilter3D")
		t.check(native != null and native.has_method("align_transforms"),
			"native C++ batch transform alignment is registered")
		if native != null and native.has_method("align_transforms"):
			var native_aligned: Array = native.call("align_transforms", original, normals, 30.0)
			t.eq(native_aligned.size(), aligned.size(), "native result preserves instance count")
			for i in aligned.size():
				var a: Transform3D = native_aligned[i]
				t.check(a.is_equal_approx(aligned[i]),
					"native and script agree on known surface normals %d" % i)
			var rng := RandomNumberGenerator.new()
			rng.seed = 298771
			for sample in 12:
				var points: Array[Transform3D] = []
				var slopes := PackedVector3Array()
				for i in 110:
					var size := rng.randf_range(0.5, 2.0)
					var yaw := rng.randf_range(-PI, PI)
					var loc := Vector3(rng.randf_range(-60, 60),
						rng.randf_range(-25, 100), rng.randf_range(-60, 60))
					points.append(Transform3D(Basis(Vector3.UP, yaw).scaled(
						Vector3.ONE * size), loc))
					slopes.append(Vector3(rng.randf_range(-1, 1),
						rng.randf_range(0.01, 1),
						rng.randf_range(-1, 1)))
				var expected: Array[Transform3D] = SceneryBatches.align_cosmetic_transforms_surface(
					points, slopes, 40.0, false)
				var actual: Array = native.call("align_transforms", points, slopes, 40.0)
				t.eq(actual.size(), expected.size(), "native count parity sample %d" % sample)
				if actual.size() == expected.size():
					for i in expected.size():
						var result: Transform3D = actual[i]
						t.check(result.is_equal_approx(expected[i]),
							"native GDScript orientation parity sample %d point %d" % [sample, i])
	else:
		t.eq(SceneryBatches.align_cosmetic_transforms_surface(
			original, normals, 30.0), aligned,
			"stock Godot uses equivalent deterministic surface alignment")
