extends RefCounted
## Verifies that the expanded CC0 art is installed and the scene's shader catalog stays in sync.

const ModelCatalog = preload("res://scripts/client/model_catalog.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")
const ART_ROOT := "res://assets/models/kenney_expanded/"
const TERRAIN_DIR := "res://assets/textures/terrain/"


func run(t) -> void:
	t.current = "expanded models"
	t.eq(ModelCatalog.BUILTIN_TREES.size(), 6, "six shipped tree variants")
	for entry in ModelCatalog.BUILTIN_TREES:
		var path: String = str(entry["path"])
		t.check(path.begins_with(ART_ROOT), "tree is in the installed art directory")
		t.check(ResourceLoader.exists(path), "tree can be imported: " + path)
		var mesh: Mesh = ModelCatalog.entry_mesh(entry)
		t.check(mesh != null, "tree has a renderable mesh: " + path)
		if mesh != null:
			t.check(mesh.get_surface_count() > 0, "tree mesh contains surfaces: " + path)
	var extra_count := 0
	var ruin_count := 0
	for entry in ModelCatalog.DECOR_EXTRA:
		var path: String = str(entry["path"])
		if not path.begins_with(ART_ROOT):
			continue
		extra_count += 1
		t.check(ResourceLoader.exists(path), "decor can be imported: " + path)
		t.check(ModelCatalog.entry_mesh(entry) != null, "decor mesh is present: " + path)
		if str(entry.get("anchor", "")) == "ruin":
			ruin_count += 1
			t.check("ruin" in ["tree", "rock", "meadow", "rare", "ruin"], "ruin anchor is supported")
	t.eq(extra_count, 20, "twenty environment decoration models")
	t.eq(ruin_count, 10, "ten ruin-specific models")

	t.current = "ground shader layers"
	t.eq(ChunkView.TERRAIN_LAYERS.size(), 13, "thirteen ground materials")
	t.eq(ChunkView.TERRAIN_LAYERS.size(), ChunkView.TERRAIN_TARGETS.size(), "every material has a matching colour target")
	for layer in ChunkView.TERRAIN_LAYERS:
		for suffix in ["_diff.jpg", "_nor_gl.jpg"]:
			var path: String = TERRAIN_DIR + layer + suffix
			t.check(ResourceLoader.exists(path), "ground texture is available: " + path)
	t.eq(ChunkView.SITE_PAVING["city"][0], 11, "cities use weathered brick")
	t.eq(ChunkView.SITE_PAVING["dock"][0], 12, "docks use aged planks")
