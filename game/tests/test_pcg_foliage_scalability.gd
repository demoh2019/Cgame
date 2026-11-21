extends RefCounted
## Unreal foliage density scalability for cosmetic GPU MultiMesh batches.
const FoliageBudget = preload("res://scripts/client/scenery_density_lod.gd")
const SceneryBatches = preload("res://scripts/client/scenery_batches.gd")


func run(t) -> void:
	t.current = "native PCG foliage density: distributed stable instance prefixes"
	var expected_order := PackedInt32Array([0, 8, 4, 2, 6, 1, 9, 5, 3, 7])
	t.eq(FoliageBudget.spread_indices(10, false), expected_order,
		"non-power-of-two instance groups spread an ordered prefix")
	t.eq(FoliageBudget.spread_indices(0, false).size(), 0,
		"empty foliage group has no visible instances")
	t.eq(FoliageBudget.spread_indices(-1, false).size(), 0,
		"negative group sizes are rejected")
	t.eq(FoliageBudget.spread_indices(65537, false).size(), 0,
		"oversized instance groups are rejected")
	var sources: Array[Transform3D] = []
	for i in 10:
		sources.append(Transform3D(Basis.IDENTITY, Vector3(float(i), 0, 0)))
	var before: Array[Transform3D] = sources.duplicate()
	var distributed: Array[Transform3D] = FoliageBudget.distribute_transforms(
		sources, false)
	for i in 10:
		t.eq(distributed[i], sources[expected_order[i]],
			"stable spatial index order %d" % i)
	t.eq(sources, before, "ordering does not modify authored geometry or RNG")

	t.current = "Unreal foliage scalability quality tiers and far distance"
	var counts := PackedInt32Array([100, 100, 100, 0, 1])
	var distances := PackedFloat32Array([18.0, 71.5, 125.0, 70.0, 125.0])
	t.eq(FoliageBudget.plan_visible_counts(counts, distances, 0,
		18.0, 125.0, false), PackedInt32Array([42, 31, 20, 0, 1]),
		"Performance discards distant tiny cosmetic leaves")
	t.eq(FoliageBudget.plan_visible_counts(counts, distances, 1,
		18.0, 125.0, false), PackedInt32Array([68, 55, 42, 0, 1]),
		"Balanced retains more of the meadow")
	t.eq(FoliageBudget.plan_visible_counts(counts, distances, 2,
		18.0, 125.0, false), PackedInt32Array([88, 79, 70, 0, 1]),
		"High preserves more distant flowers")
	t.eq(FoliageBudget.plan_visible_counts(counts, distances, 3,
		18.0, 125.0, false), counts, "Ultra restores every original instance")
	t.eq(FoliageBudget.plan_visible_counts(counts, distances, 0,
		18.0, 125.0, false), FoliageBudget.plan_visible_counts(
			counts, distances, 0, 18.0, 125.0, false),
		"reversible changes are deterministic")
	t.eq(FoliageBudget.plan_visible_counts(
		PackedInt32Array([100, 100]), PackedFloat32Array([0.0, 1000.0]),
		0, 18.0, 125.0, false), PackedInt32Array([42, 20]),
		"distance endpoints clamp, no extrapolated negative counts")
	t.eq(FoliageBudget.plan_visible_counts(counts, distances, 4,
		18.0, 125.0, false).size(), 0, "invalid quality fails atomically")
	t.eq(FoliageBudget.plan_visible_counts(
		PackedInt32Array([10, -1]), PackedFloat32Array([10, 10]),
		1, 18.0, 125.0, false).size(), 0,
		"invalid late geometry counts fail atomically")
	t.eq(FoliageBudget.plan_visible_counts(
		PackedInt32Array([10, 10]), PackedFloat32Array([10, NAN]),
		1, 18.0, 125.0, false).size(), 0,
		"nonfinite late camera distances fail atomically")

	t.current = "GPU visibility count adjusts without changing mesh instance buffers"
	var mesh := BoxMesh.new()
	var parent := Node3D.new()
	var nodes: Array[MultiMeshInstance3D] = SceneryBatches.add(parent,
		mesh, sources, 100.0, false, 8.0, false, Vector2.ZERO, true)
	t.eq(nodes.size(), 1, "small flowers stay one GPU instancing draw batch")
	if nodes.size() == 1:
		var node: MultiMeshInstance3D = nodes[0]
		t.check(bool(node.get_meta("aa_density_scalable", false)),
			"scalable cosmetic instancing opts in explicitly")
		t.eq(node.multimesh.instance_count, 10, "full source buffer is retained")
		for i in 10:
			t.eq(node.multimesh.get_instance_transform(i).origin.x,
				float(expected_order[i]), "GPU buffer uses spread ordering %d" % i)
		var only_node: Array[MultiMeshInstance3D] = [node]
		FoliageBudget._apply_plan(only_node, PackedInt32Array([10]),
			PackedFloat32Array([20.0]), 0, false)
		t.eq(node.multimesh.visible_instance_count, 4,
			"Performance updates visible_instance_count, not source instances")
		t.eq(node.multimesh.instance_count, 10,
			"changing density never reallocates the GPU instance source")
		FoliageBudget._apply_plan(only_node, PackedInt32Array([10]),
			PackedFloat32Array([20.0]), 3, false)
		t.eq(node.multimesh.visible_instance_count, 10,
			"switching back to Ultra restores all foliage")
		t.eq(node.multimesh.get_instance_transform(1).origin.x, 8.0,
			"all authored transforms remain in the same buffer")
	parent.free()
	t.eq(sources, before, "game instancing never edits procedural positions")

	t.current = "Albion streamed cosmetic foliage is wired to density planner"
	var chunk_code := FileAccess.get_file_as_string(
		"res://scripts/client/chunk_view.gd")
	t.check(chunk_code.contains("SceneryDensityLod.update_instances("),
		"streaming chunks refresh GPU visible counts with native batch query")
	t.check(chunk_code.contains("DENSITY_LOD_INTERVAL := 0.6"),
		"visibility refresh is throttled independently of the render loop")
	t.check(chunk_code.contains('file.begins_with("Flower")') and
		chunk_code.contains('file.begins_with("Grass")'),
		"only small cosmetic vegetation opts into reversible density")
	t.check(chunk_code.contains("origin, density_scalable"),
		"Albion writes distributed static GPU instance buffer at placement time")

	t.current = "native C++ foliage scalability agrees with stock Godot fallback"
	if ClassDB.class_exists("PCGFoliageScalability3D"):
		var native: Object = ClassDB.instantiate("PCGFoliageScalability3D")
		t.check(native != null and native.has_method("plan_visible_counts") and
			native.has_method("spread_indices"), "new native engine class registered")
		if native != null and native.has_method("plan_visible_counts"):
			t.eq(native.call("spread_indices", 10), expected_order,
				"native bit reversal matches the script")
			var rng := RandomNumberGenerator.new()
			rng.seed = 910423
			for sample in 20:
				var batch_counts := PackedInt32Array()
				var batch_distances := PackedFloat32Array()
				for i in 32:
					batch_counts.append(rng.randi_range(0, 300))
					batch_distances.append(rng.randf_range(0.0, 300.0))
				for quality in 4:
					t.eq(native.call("plan_visible_counts", batch_counts,
						batch_distances, quality, 18.0, 125.0),
						FoliageBudget.plan_visible_counts(batch_counts,
							batch_distances, quality, 18.0, 125.0, false),
						"native / script foliage density parity sample %d tier %d" %
						[sample, quality])
	else:
		t.eq(FoliageBudget.spread_indices(10), expected_order,
			"stock Godot uses the same reversible prefix plan")
