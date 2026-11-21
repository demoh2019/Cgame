extends RefCounted
## Regression checks for conservative MultiMesh spatial-culling batches.
const SceneryBatches = preload("res://scripts/client/scenery_batches.gd")


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
