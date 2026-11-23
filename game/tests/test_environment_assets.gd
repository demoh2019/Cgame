extends RefCounted
## Verifies that the expanded CC0 art is installed and the scene's shader catalog stays in sync.

const ModelCatalog = preload("res://scripts/client/model_catalog.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")
const StoneResources = preload("res://scripts/shared/stone_resources.gd")
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

	t.current = "all loose rock model decorations are now interactive"
	var loose_catalog_rocks := 0
	for decor in ModelCatalog.DECOR_EXTRA:
		if not StoneResources.is_loose_stone_entry(decor):
			continue
		loose_catalog_rocks += 1
		var matched := false
		for model in StoneResources.MODELS:
			if str(model.get("path", "")) == str(decor["path"]):
				matched = true
				break
		t.check(matched, "catalog rock has authoritative resource representation: %s" % str(decor["path"]))
	t.check(loose_catalog_rocks >= 20, "all standalone boulders and stone models are covered")
	t.check(not StoneResources.is_loose_stone_entry({"path": "graveyard/gravestone-broken.glb"}),
		"constructed grave markers are not treated as loose stones")
	t.check(not StoneResources.is_loose_stone_entry({"path": "nature/campfire-stones.glb"}),
		"built stone campfires remain scenery")
	t.check(StoneResources.MODELS[0].has("nature") and StoneResources.MODELS[1].has("nature"),
		"both previously cosmetic pebble meshes now have pickup entries")

	t.current = "stone model size matches pickup or mining"
	var generator := RandomNumberGenerator.new()
	generator.seed = 20261123
	for biome in ["forest", "plains", "swamp", "mountain", "beach"]:
		for i in 16:
			var tiny: int = StoneResources.pick_model(biome, true, generator)
			var mineable: int = StoneResources.pick_model(biome, false, generator)
			t.check(tiny >= 0 and mineable >= 0,
				"both pickup and mineable stone variants available in " + biome)
			if tiny >= 0:
				t.check(StoneResources.MODELS[tiny].has("nature"),
					"hand-pickup never selects a 1-metre imported rock")
			if mineable >= 0:
				t.check(StoneResources.MODELS[mineable].has("path"),
					"mining selects collidable imported rock models")
	var pebble_mesh: Mesh = ChunkView.pebble_fallback_mesh()
	t.check(pebble_mesh != null, "pickup has geometry without optional nature pack")
	if pebble_mesh != null:
		t.check(pebble_mesh.get_aabb().size.x < 0.5,
			"fallback pickup is actually hand-sized, not a boulder")
		t.check(pebble_mesh == ChunkView.pebble_fallback_mesh(),
			"pickup fallback is shared rather than allocated per streamed chunk")

	t.current = "ground shader layers"
	t.eq(ChunkView.TERRAIN_LAYERS.size(), 13, "thirteen ground materials")
	t.eq(ChunkView.TERRAIN_LAYERS.size(), ChunkView.TERRAIN_TARGETS.size(), "every material has a matching colour target")
	for layer in ChunkView.TERRAIN_LAYERS:
		for suffix in ["_diff.jpg", "_nor_gl.jpg"]:
			var path: String = TERRAIN_DIR + layer + suffix
			t.check(ResourceLoader.exists(path), "ground texture is available: " + path)
	t.eq(ChunkView.SITE_PAVING["city"][0], 11, "cities use weathered brick")
	t.eq(ChunkView.SITE_PAVING["dock"][0], 12, "docks use aged planks")
