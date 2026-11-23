extends RefCounted
## Regression checks for conservative MultiMesh spatial-culling batches.
const SceneryBatches = preload("res://scripts/client/scenery_batches.gd")
const DensityLod = preload("res://scripts/client/scenery_density_lod.gd")


func run(t) -> void:
	t.current = "scenery partitioning"
	var empty: Array[Transform3D] = []
	t.eq(SceneryBatches.partition(empty).size(), 0, "no batches for no instances")
	var small: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 1.0)),
		Transform3D(Basis.IDENTITY, Vector3(60.0, 0.0, 60.0)),
	]
	t.eq(SceneryBatches.partition(small).size(), 1, "sparse objects keep one draw call")
	var dense: Array[Transform3D] = []
	for i in 60:
		var x: float = 5.0 + float(i % 6) * 10.0
		var z: float = 5.0 + float(int(i / 6)) * 6.0
		dense.append(Transform3D(Basis(Vector3.UP, float(i) * 0.19).scaled(Vector3.ONE * 1.2), Vector3(x, 4.0, z)))
	var groups: Array = SceneryBatches.partition(dense)
	t.eq(groups.size(), 4, "dense 64 m chunk splits into four 32 m groups")
	var count := 0
	for group in groups:
		count += group.size()
	t.eq(count, dense.size(), "spatial splitting preserves every object")

	t.current = "scenery visibility bounds"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.0, 3.0, 1.0)
	var parent := Node3D.new()
	var nodes: Array[MultiMeshInstance3D] = SceneryBatches.add(parent, mesh, dense, 90.0, false)
	t.eq(nodes.size(), 4, "render nodes match spatial groups")
	var found := 0
	for instance in nodes:
		t.check(instance.multimesh != null, "each batch has GPU instancing")
		t.near(instance.visibility_range_end, 90.0, 0.001, "range is maintained")
		t.check(instance.custom_aabb.size.x > 0.0 and instance.custom_aabb.size.y > 0.0, "custom bounds are nonempty")
		for i in instance.multimesh.instance_count:
			var transform: Transform3D = instance.multimesh.get_instance_transform(i)
			t.check(instance.custom_aabb.has_point(transform.origin), "visible instance center lies inside its bounds")
			found += 1
	t.eq(found, dense.size(), "all transforms reach the GPU")
	parent.free()

	t.current = "height-aware native instancing clusters"
	var stacked: Array[Transform3D] = []
	var positions := PackedVector3Array()
	for i in 80:
		var height := 0.0 if i % 2 == 0 else 75.0
		var point := Vector3(float(i % 20) * 0.3, height, float(i % 5) * 0.5)
		positions.append(point)
		stacked.append(Transform3D(Basis.IDENTITY, point))
	var original: Array[Transform3D] = stacked.duplicate()
	var expected: Array = SceneryBatches.partition_indices_3d(positions, 32.0, 48, 256, false)
	t.eq(expected.size(), 2, "two altitude layers form independent culled clusters")
	t.eq(expected[0].size(), 40, "lower cluster has forty instances")
	t.eq(expected[1].size(), 40, "upper cluster has forty instances")
	for i in 40:
		t.eq(expected[0][i], i * 2, "lower layer original index %d" % i)
		t.eq(expected[1][i], i * 2 + 1, "upper layer original index %d" % i)
	var actual: Array = SceneryBatches.partition(stacked)
	t.eq(actual.size(), 2, "Albion decoration invokes 3D partitioning")
	t.eq(stacked, original, "3D batching never mutates source transforms")
	for i in actual.size():
		for item in actual[i]:
			t.eq(int(item.origin.y), 0 if i == 0 else 75,
				"per-cluster transforms are height coherent")
	var stacked_parent := Node3D.new()
	var stacked_nodes: Array[MultiMeshInstance3D] = SceneryBatches.add(
		stacked_parent, mesh, stacked, 100.0, false)
	t.eq(stacked_nodes.size(), 2, "two separate render-cullable MultiMesh objects")
	for instance in stacked_nodes:
		t.eq(instance.multimesh.instance_count, 40, "render cluster instance count")
		t.check(instance.custom_aabb.size.y < 6.0,
			"vertical MultiMesh bounds do not span unrelated cliff elevations")
	stacked_parent.free()

	t.current = "native cluster anchors for HLOD and foliage projected sizing"
	var anchor_groups: Array = [
		PackedInt32Array([0, 2]), PackedInt32Array([1, 3])]
	var anchor_points := PackedVector3Array([
		Vector3(-2, 0, -1), Vector3(0, 80, 2),
		Vector3(2, 2, 5), Vector3(5, 82, 9)])
	var native_bounds: Array = SceneryBatches.cluster_point_bounds(
		anchor_points, anchor_groups)
	var fallback_bounds: Array = SceneryBatches.cluster_point_bounds(
		anchor_points, anchor_groups, 0.0, false)
	t.eq(native_bounds, fallback_bounds,
		"native cluster anchor bounds exactly match portable fallback")
	t.eq(native_bounds.size(), 2, "two independently bounded altitude layers")
	if native_bounds.size() == 2:
		var ground: AABB = native_bounds[0]
		var high: AABB = native_bounds[1]
		t.eq(ground.position, Vector3(-2, 0, -1),
			"anchor bounds preserve negative XYZ")
		t.eq(ground.size, Vector3(4, 2, 6),
			"anchor bounds tightly enclose the lower level")
		t.eq(high.position, Vector3(0, 80, 2),
			"anchor bounds track a separate upper level")
		t.check(ground.get_end().y < high.position.y,
			"native HLOD anchor bounds do not span separate elevations")
	var corrupt: Array = [
		PackedInt32Array([0, 1]), PackedInt32Array([1, 2, 3])]
	t.eq(SceneryBatches.cluster_point_bounds(anchor_points, corrupt).size(), 0,
		"duplicate source indices invalidate all native anchor boxes")
	t.eq(SceneryBatches.cluster_point_bounds(anchor_points, corrupt, 0.0, false).size(), 0,
		"fallback also rejects duplicate clusters")
	t.eq(SceneryBatches.cluster_point_bounds(anchor_points,
		[PackedInt32Array([0, 1])]).size(), 0,
		"missing cluster members never yield partial bounds")
	t.eq(SceneryBatches.cluster_point_bounds(anchor_points, anchor_groups, -1.0).size(), 0,
		"invalid margin is rejected")
	var found_anchor_meta := 0
	for batch in nodes:
		var anchor_meta: Variant = batch.get_meta("aa_pcg_anchor_bounds", null)
		t.check(anchor_meta is AABB,
			"real Albion scenery has native point-only cluster anchor metadata")
		if anchor_meta is AABB:
			var instance_anchors: AABB = anchor_meta
			var center: Vector3 = DensityLod._anchor_center(batch)
			t.check(center.distance_to(batch.to_global(instance_anchors.get_center())) < 0.00001,
				"projected foliage LOD reads native anchor center")
			t.check(batch.custom_aabb.has_point(instance_anchors.get_center()),
				"render bounds remain conservative around every anchor")
			found_anchor_meta += 1
	t.eq(found_anchor_meta, nodes.size(),
		"each real GPU batch has independently addressable native anchor metadata")

	t.current = "native cluster draw-call limit and invalid input safety"
	var widespread := PackedVector3Array()
	for i in 80:
		widespread.append(Vector3(float(i) * 33.0, 0, 0))
	var limited: Array = SceneryBatches.partition_indices_3d(
		widespread, 32.0, 48, 3, false)
	t.eq(limited.size(), 1, "excessive cell count falls back to one draw call")
	t.eq(limited[0].size(), 80, "overflow never drops geometry")
	for i in 80:
		t.eq(limited[0][i], i, "overflow preserves source index %d" % i)
	t.eq(SceneryBatches.partition_indices_3d(positions, 32.0, 100, 256, false).size(),
		1, "sparse batches remain unsplit")
	var invalid_points: PackedVector3Array = positions.duplicate()
	invalid_points.append(Vector3(0, NAN, 0))
	t.eq(SceneryBatches.partition_indices_3d(invalid_points, 32.0, 48, 256, false).size(),
		0, "late NaN invalidates the entire plan")
	t.eq(SceneryBatches.partition_indices_adaptive_3d(
		invalid_points, 32.0, 48, 256, 8, false).size(),
		0, "adaptive retries also reject a late invalid point")

	if ClassDB.class_exists("PCGInstanceCluster3D"):
		var native: Object = ClassDB.instantiate("PCGInstanceCluster3D")
		t.check(native != null and native.has_method("partition_indices"),
			"native 3D instancing planner registered")
		if native != null and native.has_method("partition_indices"):
			t.eq(native.call("partition_indices", positions, 32.0, 48, 256), expected,
				"native/stock-Godot height-layer parity")
			t.eq(SceneryBatches.partition_indices_3d(widespread, 32.0, 48, 3),
				limited, "native cluster budget parity")
			var rng := RandomNumberGenerator.new()
			rng.seed = 183014
			for sample in 16:
				var random_points := PackedVector3Array()
				for i in 240:
					random_points.append(Vector3(rng.randf_range(-90.0, 90.0),
						rng.randf_range(-60.0, 60.0), rng.randf_range(-90.0, 90.0)))
				t.eq(native.call("partition_indices", random_points, 32.0, 48, 256),
					SceneryBatches.partition_indices_3d(
						random_points, 32.0, 48, 256, false),
					"native/fallback three-axis parity sample %d" % sample)
	else:
		t.eq(SceneryBatches.partition_indices_3d(positions), expected,
			"stock Godot uses exactly the same index plan")

	t.current = "dense scenery fallback preserves packed source indices"
	var dense_points := PackedVector3Array()
	var expected_indices := PackedInt32Array()
	dense_points.resize(4096)
	expected_indices.resize(4096)
	for i in dense_points.size():
		dense_points[i] = Vector3(float(i % 32) * 0.25, 2.0,
			float(i % 16) * 0.25)
		expected_indices[i] = i
	var packed_groups: Array = SceneryBatches.partition_indices_3d(
		dense_points, 32.0, 48, 256, false)
	t.eq(packed_groups.size(), 1, "dense cell retains one MultiMesh batch")
	if packed_groups.size() == 1:
		t.check(packed_groups[0] is PackedInt32Array,
			"bucket building still produces packed indices")
		t.eq(packed_groups[0], expected_indices,
			"large dense cell preserves exact source ordering")

	t.current = "HISM-style adaptive cluster coarsening after draw-call overflow"
	var spaced_3d := PackedVector3Array()
	var transforms_3d: Array[Transform3D] = []
	for i in 80:
		var p := Vector3(float(i) * 33.0, 0.0, 0.0)
		spaced_3d.append(p)
		transforms_3d.append(Transform3D(Basis.IDENTITY, p))
	var adaptive: Array = SceneryBatches.partition_indices_adaptive_3d(
		spaced_3d, 32.0, 48, 3, 8, false)
	t.eq(adaptive.size(), 3, "adaptive grid coarsens to three draw-call groups")
	var recovered: Array[int] = []
	for group in adaptive:
		for original_index in group:
			recovered.append(original_index)
	t.eq(recovered.size(), 80, "adaptive clustering preserves every instance")
	for i in recovered.size():
		t.eq(recovered[i], i, "adaptive grouping preserves stable order %d" % i)
	t.eq(SceneryBatches.partition_indices_adaptive_3d(
		spaced_3d, 32.0, 48, 3, 0, false).size(),
		1, "zero coarsening retries keeps legacy unsplit safety")
	t.eq(SceneryBatches.partition_indices_adaptive_3d(
		spaced_3d, 32.0, 48, 3, 9, false).size(),
		0, "unbounded retry requests fail closed")
	t.eq(SceneryBatches.partition_indices_adaptive_3d(
		positions, 32.0, 48, 256, 8, false),
		expected, "under-budget cells retain original native grid plan")
	var many: Array[Transform3D] = []
	for i in 270:
		many.append(Transform3D(Basis.IDENTITY, Vector3(float(i) * 33.0, 0.0, 0.0)))
	var clustered: Array = SceneryBatches.partition(many)
	t.check(clustered.size() > 1 and clustered.size() <= 256,
		"Albion retains multiple cullable batches when first-pass grid overflows")
	var found_instances := 0
	for group in clustered:
		found_instances += group.size()
	t.eq(found_instances, many.size(), "Albion adaptive partition never drops transforms")
	var adaptive_native: Object = null
	if ClassDB.class_exists("PCGInstanceCluster3D"):
		adaptive_native = ClassDB.instantiate("PCGInstanceCluster3D")
	if adaptive_native != null and adaptive_native.has_method("partition_indices_adaptive"):
		t.eq(adaptive_native.call("partition_indices_adaptive",
			spaced_3d, 32.0, 48, 3, 8), adaptive,
			"native and fallback coarsening parity")
		var rng := RandomNumberGenerator.new()
		rng.seed = 621061
		for sample in 16:
			var random_points := PackedVector3Array()
			for i in 350:
				random_points.append(Vector3(rng.randf_range(-100.0, 100.0),
					rng.randf_range(-100.0, 100.0),
					rng.randf_range(-100.0, 100.0)))
			t.eq(adaptive_native.call("partition_indices_adaptive",
				random_points, 10.0, 48, 25, 8),
				SceneryBatches.partition_indices_adaptive_3d(
					random_points, 10.0, 48, 25, 8, false),
				"native/fallback adaptive parity sample %d" % sample)
	else:
		t.eq(SceneryBatches.partition_indices_adaptive_3d(spaced_3d, 32.0, 48, 3),
			adaptive, "stock Godot executes the deterministic adaptive fallback")
