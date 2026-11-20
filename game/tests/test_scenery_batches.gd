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
	for i in 30:
		var x: float = 5.0 + float(i % 6) * 10.0
		var z: float = 5.0 + float(int(i / 6)) * 12.0
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
