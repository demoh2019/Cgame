extends RefCounted
## P1 GPU virtual geometry groundwork: binary meshlet pages on actual Godot
## surfaces and streamed Albion MultiMesh render nodes.
const Inspector = preload("res://scripts/client/virtual_geometry_page_inspector.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")
const OnlineMain = preload("res://scripts/client/online_main.gd")


static func _make_mesh() -> ArrayMesh:
	const SIDE := 25
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for z in SIDE:
		for x in SIDE:
			vertices.append(Vector3(x, sin(float(x) * 0.10) * 0.2, z))
			normals.append(Vector3.UP)
			tangents.append_array(PackedFloat32Array([1, 0, 0, 1]))
			uv.append(Vector2(x, z) / float(SIDE - 1))
			uv2.append(Vector2(x + 0.5, z + 0.5) / float(SIDE))
			colors.append(Color(float(x) / SIDE, float(z) / SIDE, 0.8))
	for z in SIDE - 1:
		for x in SIDE - 1:
			var a: int = z * SIDE + x
			indices.append_array(PackedInt32Array([
				a, a + SIDE, a + 1, a + 1, a + SIDE, a + SIDE + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.65, 0.85)
	material.roughness = 0.33
	mesh.surface_set_material(0, material)
	return mesh


static func _coverage_key(a: int, b: int, c: int) -> String:
	var tri: Array[int] = [a, b, c]
	tri.sort()
	return "%d/%d/%d" % [tri[0], tri[1], tri[2]]


func run(t) -> void:
	t.current = "real streamed asset group and explicit debug command"
	t.check((ChunkView as Script).source_code.contains(
		'instance.add_to_group(SCENERY_GROUP)'),
		"actual Albion outdoor scenery registers its MultiMesh nodes")
	var online: String = (OnlineMain as Script).source_code
	t.check(online.contains("VirtualGeometryPageInspector.inspect_streamed_world("),
		"existing online client dispatches the new inspection helper")
	t.check(online.contains("event.keycode == KEY_F8") and
		online.contains("event.ctrl_pressed and event.shift_pressed") and
		online.contains("OS.is_debug_build()"),
		"Ctrl+Shift+F8 only runs in debug builds, preserving game parry")
	var mesh: ArrayMesh = _make_mesh()
	var original: Array = mesh.surface_get_arrays(0)
	var original_material: Material = mesh.surface_get_material(0)
	var native_available: bool = ClassDB.class_exists("CgameMeshletPages")
	var stats: Dictionary = Inspector.inspect_mesh(mesh, 1024)
	t.eq(bool(stats["supported"]), native_available,
		"stock Godot cleanly detects missing native pages module")
	if not native_available:
		t.check(not bool(stats["verified"]), "stock Godot performs no fake GPU page work")
		return

	t.current = "native bounded binary pages cover all geometry without losing attributes"
	t.check(bool(stats["verified"]), "renderer asset page structure validates")
	t.check(int(stats["pages"]) > 1, "large mesh splits into bounded physical pages")
	t.check(int(stats["meshlets"]) > 1, "actual imported geometry uses multiple clusters")
	var source_indices: PackedInt32Array = original[Mesh.ARRAY_INDEX]
	t.eq(int(stats["triangles"]), int(source_indices.size() / 3),
		"every original triangle survives packing once")
	t.check(int(stats["bytes"]) <= int(stats["pages"]) * 1024,
		"packed page payload obeys the strict byte limit")
	var builder: Object = ClassDB.instantiate("CgameMeshletPages")
	t.check(builder != null and builder.has_method("build_pages"),
		"native class exists and exposes its packed-page ABI")
	var pages: Array = builder.call("build_pages",
		original[Mesh.ARRAY_VERTEX], original[Mesh.ARRAY_INDEX], 1024)
	var original_coverage: Dictionary = {}
	var decoded_coverage: Dictionary = {}
	for i in range(0, source_indices.size(), 3):
		var key: String = _coverage_key(
			source_indices[i], source_indices[i + 1], source_indices[i + 2])
		original_coverage[key] = int(original_coverage.get(key, 0)) + 1
	var previous_first: int = 0
	for page in pages:
		var result: Dictionary = builder.call("inspect_page", page)
		t.check(not result.is_empty(), "packed live page passes strict native parsing")
		if result.is_empty():
			continue
		t.eq(int(result["first_meshlet"]), previous_first,
			"meshlet ordinals are contiguous across streamed asset pages")
		previous_first += int(result["meshlet_count"])
		for cluster in result["meshlets"]:
			var ids: PackedInt32Array = cluster["vertex_ids"]
			var local_indices: PackedByteArray = cluster["local_indices"]
			for j in range(0, local_indices.size(), 3):
				var key: String = _coverage_key(
					ids[local_indices[j]], ids[local_indices[j + 1]],
					ids[local_indices[j + 2]])
				decoded_coverage[key] = int(decoded_coverage.get(key, 0)) + 1
	t.eq(decoded_coverage, original_coverage,
		"page descriptors reference every original triangle exactly once")
	var bad: PackedByteArray = (pages[0] as PackedByteArray).duplicate()
	bad[0] = 0
	t.check((builder.call("inspect_page", bad) as Dictionary).is_empty(),
		"corrupted GPU page magic is rejected instead of decoded")
	t.check((builder.call("build_pages", original[Mesh.ARRAY_VERTEX],
		PackedInt32Array([0, 1, 999999]), 1024) as Array).is_empty(),
		"invalid source indices fail closed, never building a partial page")

	t.current = "original full PBR streams and material remain untouched"
	var after: Array = mesh.surface_get_arrays(0)
	for key in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT,
			Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
		t.eq(after[key], original[key], "original game vertex/texture data is preserved")
	t.eq(mesh.surface_get_material(0), original_material,
		"live PBR material remains owned by the original renderer mesh")

	t.current = "on-demand profiler sees loaded MultiMesh from real Albion scenery group"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 1
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = mm
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(instance)
	instance.add_to_group(Inspector.SCENERY_GROUP)
	var live: Dictionary = Inspector.inspect_streamed_world(tree, 1, 1024)
	t.check(bool(live["supported"]) and bool(live["verified"]),
		"actual world group is readable without modifying gameplay render state")
	t.check(int(live["meshes"]) >= 1 and int(live["pages"]) >= 1,
		"loaded MultiMesh source uses native compressed meshlet descriptors")
	t.eq(int(live["triangles"]), int(source_indices.size() / 3),
		"game level inspection reports correct actual geometry complexity")
	t.check(Inspector.format_report(live).contains("CPU packed only"),
		"inspection never misrepresents the format as finished GPU Nanite")
	instance.free()
