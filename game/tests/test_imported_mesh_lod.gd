extends RefCounted
## Native per-surface mesh LODs must survive the client art/baking pipeline.
## Tests synthetic indexed geometry: no optional asset pack or GPU profiling needed.

const MeshLOD = preload("res://scripts/client/mesh_lod_preservation.gd")
const Catalog = preload("res://scripts/client/model_catalog.gd")
const Foliage = preload("res://scripts/client/foliage.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


static func _source() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-1.0, 0.0, -1.0), Vector3(1.0, 0.0, -1.0),
		Vector3(1.0, 0.0, 1.0), Vector3(-1.0, 0.0, 1.0)
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP
	])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [],
			{0.8: PackedInt32Array([0, 1, 2])})
	var material := StandardMaterial3D.new()
	mesh.surface_set_material(0, material)
	return mesh


func run(t) -> void:
	t.current = "native mesh LOD retention"
	# Synthetic encoded streams exercise both index widths independently of importer assets.
	var packed16 := PackedByteArray()
	packed16.resize(6)
	packed16.encode_u16(0, 0)
	packed16.encode_u16(2, 2)
	packed16.encode_u16(4, 1)
	t.eq(MeshLOD.decode_indices(packed16, 2, 4), PackedInt32Array([0, 2, 1]),
			"16-bit LOD indices decode exactly")
	var packed32 := PackedByteArray()
	packed32.resize(12)
	packed32.encode_u32(0, 0)
	packed32.encode_u32(4, 70000)
	packed32.encode_u32(8, 1)
	t.eq(MeshLOD.decode_indices(packed32, 4, 80000), PackedInt32Array([0, 70000, 1]),
			"32-bit LOD indices decode exactly")
	t.eq(MeshLOD.decode_indices(packed32, 4, 10).size(), 0,
			"out-of-range LOD vertex indices are rejected")
	var mesh: ArrayMesh = _source()
	var lods: Dictionary = MeshLOD.copy_lods(mesh, 0)
	t.eq(lods.size(), 1, "source has one simplified LOD")
	if lods.size() == 1:
		var threshold: float = float(lods.keys()[0])
		t.near(threshold, 0.8, 0.0001, "source edge-length threshold is intact")
		var short_indices: PackedInt32Array = lods[threshold]
		t.eq(short_indices.size(), 3, "the distant LOD draws one triangle")
	var doubled: Dictionary = MeshLOD.copy_lods(mesh, 0, 2.0)
	t.eq(doubled.size(), 1, "scaled LOD survives decoding")
	if doubled.size() == 1:
		t.near(float(doubled.keys()[0]), 1.6, 0.0001, "LOD edge threshold scales with geometry")

	var fitted: Mesh = Catalog._fit_mesh(mesh, "length", 4.0)
	var fitted_lods: Dictionary = MeshLOD.copy_lods(fitted, 0)
	t.eq(fitted_lods.size(), 1, "baked mesh keeps imported LOD indices")
	if fitted_lods.size() == 1:
		t.near(float(fitted_lods.keys()[0]), 1.6, 0.0001, "baking rescales geometric LOD error")
	var full_indices: PackedInt32Array = fitted.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	t.eq(full_indices.size(), 6, "full-resolution mesh stays available")

	var wind_mesh: Mesh = Foliage.swayed(mesh, "mesh_lod_pipeline:synthetic", 0.12)
	t.eq(MeshLOD.copy_lods(wind_mesh, 0).size(), 1, "wind shader conversion keeps LODs")

	t.current = "mesh LOD quality budget"
	var performance: float = float(GraphicsQuality.profile(0)["mesh_lod_threshold"])
	var balanced: float = float(GraphicsQuality.profile(1)["mesh_lod_threshold"])
	var high: float = float(GraphicsQuality.profile(2)["mesh_lod_threshold"])
	var ultra: float = float(GraphicsQuality.profile(3)["mesh_lod_threshold"])
	t.check(performance > balanced and balanced > high and high > ultra,
			"lower presets use more aggressive automatic geometry LOD")
	t.check(ultra > 0.0, "Ultra retains LOD rather than disabling it")
	t.eq(MeshLOD.copy_lods(null, 0).size(), 0, "null mesh is safe")
	t.eq(MeshLOD.copy_lods(mesh, 100).size(), 0, "out-of-range surface is safe")

	t.current = "native rebuild preserves custom vertex channel encodings"
	var custom_arrays: Array = mesh.surface_get_arrays(0)
	custom_arrays[Mesh.ARRAY_CUSTOM0] = PackedFloat32Array([
		1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0])
	var encoding: int = Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var custom_mesh := ArrayMesh.new()
	custom_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, custom_arrays,
		[], {}, encoding)
	t.eq(MeshLOD.vertex_encoding_flags(custom_mesh, 0), encoding,
		"float custom-channel format is retained instead of defaulting to RGBA8")
	var rebuilt_custom := ArrayMesh.new()
	rebuilt_custom.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		custom_mesh.surface_get_arrays(0), [], {}, MeshLOD.vertex_encoding_flags(custom_mesh, 0))
	t.eq(rebuilt_custom.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0],
		custom_mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0],
		"rebuilding geometry retains the original custom float stream")

	t.current = "scanned prop triangle budgets use importer LODs"
	# Synthetic indexed terrain is deterministic and needs no scanned plant asset pack.
	var grid_side := 16
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for z in grid_side + 1:
		for x in grid_side + 1:
			verts.append(Vector3(float(x) * 0.1, sin(float(x) * 0.2) * cos(float(z) * 0.3) * 0.03, float(z) * 0.1))
			normals.append(Vector3.UP)
			uv.append(Vector2(float(x) / float(grid_side), float(z) / float(grid_side)))
	for z in grid_side:
		for x in grid_side:
			var a: int = z * (grid_side + 1) + x
			indices.append_array(PackedInt32Array([a, a + 1, a + grid_side + 1,
				a + 1, a + grid_side + 2, a + grid_side + 1]))
	var source_arrays: Array = []
	source_arrays.resize(Mesh.ARRAY_MAX)
	source_arrays[Mesh.ARRAY_VERTEX] = verts
	source_arrays[Mesh.ARRAY_NORMAL] = normals
	source_arrays[Mesh.ARRAY_TEX_UV] = uv
	source_arrays[Mesh.ARRAY_INDEX] = indices
	var dense := ArrayMesh.new()
	dense.resource_name = "SyntheticGrassScatterLOD"
	dense.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source_arrays)
	var original_material := StandardMaterial3D.new()
	dense.surface_set_material(0, original_material)
	t.check(MeshLOD.with_generated_lods(dense, 10000) == dense,
		"strict threshold skips a small mesh")
	var generated_lod: Mesh = MeshLOD.with_generated_lods(dense, 1)
	t.check(generated_lod != dense,
		"earlier skipped threshold cannot poison a later LOD request")
	t.check(MeshLOD.with_generated_lods(dense, 1) == generated_lod,
		"same threshold reuses generated geometry")
	var budgeted: Mesh = MeshLOD.with_triangle_budget(dense, 80)
	t.check(budgeted != null, "triangle budget produces a usable mesh")
	t.check(budgeted == MeshLOD.with_triangle_budget(dense, 80),
		"budgeted meshes are cached by source and budget")
	if budgeted != null:
		var output_arrays: Array = budgeted.surface_get_arrays(0)
		var output_indices: PackedInt32Array = output_arrays[Mesh.ARRAY_INDEX]
		var output_vertices: PackedVector3Array = output_arrays[Mesh.ARRAY_VERTEX]
		t.check(output_indices.size() > 0 and output_indices.size() < indices.size(),
			"importer LODs reduce scanned-detail geometry")
		t.check(output_indices.size() % 3 == 0, "reduced mesh contains whole triangles")
		t.eq(output_vertices.size(), verts.size(), "simplification preserves vertex attributes")
		t.check(budgeted.surface_get_material(0) == original_material,
			"budgeted mesh keeps original PBR material")
		t.eq(budgeted.resource_name, "SyntheticGrassScatterLOD", "budgeted mesh keeps its name")
		for index in output_indices:
			t.check(index >= 0 and index < output_vertices.size(),
				"LOD indices reference valid original vertices")
	t.eq(dense.surface_get_arrays(0)[Mesh.ARRAY_INDEX], indices,
		"generating a budgeted mesh never mutates the source")
	t.check(MeshLOD.with_triangle_budget(dense, 0) == dense,
		"a disabled budget retains the original mesh")
