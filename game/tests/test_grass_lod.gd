extends RefCounted
## Checks the geometry budget and hysteresis of the grass LOD used by ChunkView.

const GrassField = preload("res://scripts/client/grass_field.gd")


func run(t) -> void:
	t.current = "grass geometry LOD"
	var previous_triangles := 999999
	for blades in GrassField.LOD_BLADES:
		var mesh: ArrayMesh = GrassField.clump_mesh(blades)
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		t.eq(vertices.size(), blades * 6, "%d blades have six vertices each" % blades)
		t.eq(indices.size(), blades * 12, "%d blades have four triangles each" % blades)
		t.check(indices.size() < previous_triangles, "lower LOD draws fewer triangles")
		previous_triangles = indices.size()
	t.check(GrassField.clump_mesh(18) == GrassField.clump_mesh(18), "near mesh is reused across tiles")
	t.check(GrassField.clump_mesh(4) == GrassField.clump_mesh(4), "far mesh is reused across tiles")

	t.current = "grass LOD hysteresis"
	t.eq(GrassField.lod_for_distance(0.0), 0, "close view uses highest geometry")
	t.eq(GrassField.lod_for_distance(26.0, 0), 0, "stay near until upper boundary")
	t.eq(GrassField.lod_for_distance(27.0, 0), 1, "cross upper boundary to medium")
	t.eq(GrassField.lod_for_distance(40.0, 1), 1, "medium stays stable")
	t.eq(GrassField.lod_for_distance(45.0, 1), 2, "switch to distant mesh")
	t.eq(GrassField.lod_for_distance(41.0, 2), 2, "far mesh does not thrash")
	t.eq(GrassField.lod_for_distance(39.0, 2), 1, "return to medium")
	t.eq(GrassField.lod_for_distance(21.0, 1), 0, "return to close mesh")
	t.eq(GrassField.lod_for_distance(100.0, 0), 2, "large camera jumps can skip tiers")
	t.eq(GrassField.lod_for_distance(0.0, 2), 0, "camera teleport restores detail")
