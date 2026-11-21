extends RefCounted
## Game-side regression: changed server resource IDs update GPU instances only.
const Updates = preload("res://scripts/client/multimesh_resource_updates.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")

func run(t) -> void:
	t.current = "prevalidated sparse MultiMesh visibility updates"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = 3
	var original: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3(1, 0, 0)),
		Transform3D(Basis.IDENTITY, Vector3(3, 0, 0)),
		Transform3D(Basis.IDENTITY, Vector3(5, 0, 0))]
	for n in 3:
		mm.set_instance_transform(n, original[n])
	var changes: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3(7, 0, 0)),
		Transform3D(Basis.IDENTITY, Vector3(9, 0, 0))]
	t.check(Updates.apply(mm, PackedInt32Array([2, 0]), changes), "unsorted sparse batch succeeds")
	t.eq(mm.get_instance_transform(2).origin, Vector3(7, 0, 0), "slot 2 changed")
	t.eq(mm.get_instance_transform(0).origin, Vector3(9, 0, 0), "slot 0 changed")
	t.check(not Updates.apply(mm, PackedInt32Array([1, 1]), changes), "duplicates rejected")
	t.check(not Updates.apply(mm, PackedInt32Array([0, 3]), changes), "invalid slot rejected")
	t.check(not Updates.apply(mm, PackedInt32Array([0]), changes), "mismatched lengths rejected")
	t.eq(mm.get_instance_transform(1), original[1], "unrelated slot preserved")
	t.eq(mm.get_instance_transform(0).origin, Vector3(9, 0, 0), "invalid batch is non-mutating")

	t.current = "actual chunk server-depleted resources hide and recover"
	var view := ChunkView.new()
	view.set("_groups", {"tree:1": {
		"multimesh": mm, "index": {1001: 0, 1002: 1, 1003: 2},
		"transforms": original}})
	for n in 3:
		mm.set_instance_transform(n, original[n])
	view.apply_state({1001: true, 1003: true})
	t.eq((view.get("_hidden") as Dictionary).size(), 2, "two stable server IDs are hidden")
	t.near(mm.get_instance_transform(0).basis.x.length(), 0.001, 0.00001, "first tree disappears")
	t.eq(mm.get_instance_transform(1), original[1], "healthy neighbor stays visible")
	view.apply_state({1003: true})
	t.eq(mm.get_instance_transform(0), original[0], "first tree restored without resampling")
	t.near(mm.get_instance_transform(2).basis.x.length(), 0.001, 0.00001, "second tree stays hidden")
	view.apply_state({})
	t.eq(mm.get_instance_transform(2), original[2], "second tree restored")
	t.eq((view.get("_hidden") as Dictionary).size(), 0, "hidden cache is empty")
	view.free()
