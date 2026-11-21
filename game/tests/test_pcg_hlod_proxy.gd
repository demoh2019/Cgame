extends RefCounted
## Native/stock-Godot merged low-poly HLOD proxy for streamed cosmetic stones.
const Hlod = preload("res://scripts/client/scenery_hlod_proxy.gd")


func run(t) -> void:
	t.current = "HLOD builds one shared low-poly surface from multiple stone sources"
	var source_transforms: Array[Transform3D] = []
	var centers := PackedVector3Array()
	var half_extents := PackedVector3Array()
	for i in 12:
		var size := 0.5 if i % 2 == 0 else 1.25
		var basis := Basis(Vector3.UP, float(i) * 0.2).scaled(Vector3.ONE * size)
		source_transforms.append(Transform3D(basis, Vector3(float(i * 4), 2, 0)))
		centers.append(Vector3.ZERO if i % 2 == 0 else Vector3(0, 0.5, 0))
		half_extents.append(Vector3(1, 1, 1) if i % 2 == 0 else Vector3(2, 1, 1))
	var unchanged: Array[Transform3D] = source_transforms.duplicate()
	var proxy_mesh: ArrayMesh = Hlod.build_proxy_mesh(
		source_transforms, centers, half_extents, 12, false)
	t.check(proxy_mesh != null, "stock Godot generates actual combined proxy geometry")
	if proxy_mesh != null:
		t.eq(proxy_mesh.get_surface_count(), 1,
			"all near stone batches become one far draw surface")
		t.eq(proxy_mesh.surface_get_array_len(0), 12 * 8 * 3,
			"each faceted distant stone uses exactly eight triangles")
		var arrays: Array = proxy_mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		t.eq(verts.size(), 288, "merged geometry is actual triangle vertex data")
		t.check(verts[0].is_finite() and verts[287].is_finite(),
			"merged triangle positions are valid")
		t.check(proxy_mesh.get_aabb().size.x > 40.0,
			"combined proxy covers both categories throughout the chunk")
		t.eq(proxy_mesh.surface_get_primitive_type(0), Mesh.PRIMITIVE_TRIANGLES,
			"proxy uses renderable 3D triangles, not only an LOD index plan")
	t.eq(source_transforms, unchanged,
		"merging leaves close-range meshes, transforms and seeded world untouched")

	t.current = "HLOD source sampling and atomic input limits"
	var sampled: ArrayMesh = Hlod.build_proxy_mesh(
		source_transforms, centers, half_extents, 3, false)
	t.check(sampled != null, "small optional geometry budget still produces a proxy")
	if sampled != null:
		t.eq(sampled.surface_get_array_len(0), 72, "three samples use 24 triangles")
		var verts: PackedVector3Array = sampled.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		t.near(verts[0].x, 0.0, 0.0001,
			"proxy samples the first original authored stone")
		t.near(verts[24].x, 16.0, 0.0001,
			"proxy selects a stable original position at one-third of input")
		t.near(verts[48].x, 32.0, 0.0001,
			"proxy selects a stable original position at two-thirds of input")
	t.check(Hlod.build_proxy_mesh(source_transforms,
		PackedVector3Array(), half_extents, 12, false) == null,
		"mismatched centers never create partial proxy meshes")
	t.check(Hlod.build_proxy_mesh(source_transforms,
		centers, half_extents, 0, false) == null,
		"zero primitive budget rejected")
	t.check(Hlod.build_proxy_mesh(source_transforms,
		centers, half_extents, 513, false) == null,
		"unbounded primitive budget rejected")
	var bad_extents: PackedVector3Array = half_extents.duplicate()
	bad_extents[11] = Vector3.ZERO
	t.check(Hlod.build_proxy_mesh(source_transforms,
		centers, bad_extents, 12, false) == null,
		"invalid late geometry dimensions fail atomically")
	var invalid_positions: Array[Transform3D] = source_transforms.duplicate()
	invalid_positions[11] = Transform3D(Basis.IDENTITY, Vector3(NAN, 0, 0))
	t.check(Hlod.build_proxy_mesh(invalid_positions,
		centers, half_extents, 12, false) == null,
		"invalid late positions fail atomically")
	t.eq(source_transforms, unchanged,
		"all rejection paths leave original close-range geometry intact")

	t.current = "HLOD distant/near switch uses reversible visibility and hysteresis"
	var parent := Node3D.new()
	var near1 := MultiMeshInstance3D.new()
	var near2 := MultiMeshInstance3D.new()
	parent.add_child(near1)
	parent.add_child(near2)
	var near_batches: Array[MultiMeshInstance3D] = [near1, near2]
	var proxy: MeshInstance3D = Hlod.attach_proxy(
		parent, source_transforms, centers, half_extents, 12, false)
	t.check(proxy != null, "two authored stone categories share the merged HLOD mesh")
	if proxy != null:
		t.eq(parent.get_child_count(), 3,
			"HLOD reuses one draw node rather than twelve additional 3D nodes")
		t.check(proxy.mesh is ArrayMesh and proxy.material_override != null,
			"far geometry has one merged resource and its own shared material")
		t.check(not proxy.visible, "new HLOD proxy defaults to hidden near view")
		t.eq(int(proxy.get_meta("aa_hlod_source_count")), 12,
			"proxy metadata reports count of original visual stones")
		t.eq(int(proxy.get_meta("aa_hlod_triangle_count")), 96,
			"proxy metadata reports low-poly triangle count")
		t.check(Hlod.should_use_proxy(57.0, 80.0, false),
			"distant camera selects lower-polygon merged geometry")
		t.check(not Hlod.should_use_proxy(52.0, 80.0, false),
			"hysteresis holds full detail before entering far range")
		t.check(Hlod.should_use_proxy(52.0, 80.0, true),
			"existing far proxy persists during tiny camera motion")
		t.check(not Hlod.should_use_proxy(48.0, 80.0, true),
			"returning closer than deadband restores full source geometry")
		var far: bool = Hlod.switch_visible(near_batches, proxy, 60.0, 80.0, false)
		t.check(far and proxy.visible and not near1.visible and not near2.visible,
			"far camera replaces both MultiMesh draw batches with one proxy")
		far = Hlod.switch_visible(near_batches, proxy, 49.0, 80.0, far)
		t.check(not far and not proxy.visible and near1.visible and near2.visible,
			"near camera restores every original GPU instanced source")
		t.eq(Hlod.should_use_proxy(40.0, 44.0, false), false,
			"performance-level low draw range avoids a near-field proxy")
		t.check(Hlod.should_use_proxy(40.0, 44.0, true),
			"low-tier far proxy stays stable until a meaningful zoom")
	parent.free()

	t.current = "C++ HLOD output matches stock Godot and real Albion chunk wiring"
	var chunk_source := FileAccess.get_file_as_string("res://scripts/client/chunk_view.gd")
	t.check(chunk_source.contains("_finalize_hlod_stones()") and
		chunk_source.contains("SceneryHlodProxy.attach_proxy("),
		"Albion constructs the merged mesh after streamed pebble categories")
	t.check(chunk_source.contains("_hlod_stone_sources.append(decor_batch)") and
		chunk_source.contains("file.begins_with(\"Pebble\")"),
		"only decorative stone MultiMesh groups are replaced at distance")
	t.check(chunk_source.contains("SceneryHlodProxy.switch_visible("),
		"Albion chunk LOD toggles proxy and all source batches together")
	if ClassDB.class_exists("PCGHLODProxyBuilder3D"):
		var native: Object = ClassDB.instantiate("PCGHLODProxyBuilder3D")
		t.check(native != null and native.has_method("build_octahedral_proxy"),
			"native merged HLOD builder is registered")
		if native != null and native.has_method("build_octahedral_proxy"):
			var native_mesh: ArrayMesh = native.call("build_octahedral_proxy",
				source_transforms, centers, half_extents, 12)
			t.check(native_mesh != null, "native HLOD constructs a 3D proxy mesh")
			if native_mesh != null and proxy_mesh != null:
				t.eq(native_mesh.get_surface_count(), 1,
					"native proxy has exactly one draw surface")
				var p: PackedVector3Array = proxy_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				var q: PackedVector3Array = native_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				t.eq(q.size(), p.size(), "native/GDScript merged vertex count parity")
				if q.size() == p.size():
					for i in q.size():
						t.check(q[i].is_equal_approx(p[i]),
							"native and script produce the same proxy vertex %d" % i)
	else:
		t.check(Hlod.build_proxy_mesh(source_transforms,
			centers, half_extents, 12) != null,
			"stock Godot retains deterministic merged proxy geometry")
