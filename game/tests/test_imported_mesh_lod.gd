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
	var mesh: ArrayMesh = _source()
	var lods: Dictionary = MeshLOD.copy_lods(mesh, 0)
	t.eq(lods.size(), 1, "source has one simplified LOD")
	if lods.size() == 1:
		var threshold: float = float(lods.keys()[0])
		t.near(threshold, 0.8, 0.0001, "source edge-length threshold is intact")
		t.eq((lods[threshold] as PackedInt32Array).size(), 3, "the distant LOD draws one triangle")
	var doubled: Dictionary = MeshLOD.copy_lods(mesh, 0, 2.0)
	t.eq(doubled.size(), 1, "scaled LOD survives decoding")
	if doubled.size() == 1:
		t.near(float(doubled.keys()[0]), 1.6, 0.0001, "LOD edge threshold scales with geometry")

	var fitted: Mesh = Catalog._fit_mesh(mesh, "length", 4.0)
	var fitted_lods: Dictionary = MeshLOD.copy_lods(fitted, 0)
	t.eq(fitted_lods.size(), 1, "baked mesh keeps imported LOD indices")
	if fitted_lods.size() == 1:
		t.near(float(fitted_lods.keys()[0]), 1.6, 0.0001, "baking rescales geometric LOD error")
	t.eq((fitted.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 6,
			"full-resolution mesh stays available")

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
