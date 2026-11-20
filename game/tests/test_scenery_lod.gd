extends RefCounted
## GPU-scene HLOD budgets preserve landmarks and actual gameplay nodes.

const SceneryLod = preload("res://scripts/client/scenery_lod.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")


func run(t) -> void:
	t.current = "scenery presets clamp and preserve stable mesh categories"
	t.eq(SceneryLod.preset(-5), SceneryLod.preset(0),
		"negative quality cannot create invalid LOD budgets")
	t.eq(SceneryLod.preset(99), SceneryLod.preset(3),
		"large quality level clamps to Ultra")
	var low: Dictionary = SceneryLod.preset(0)
	low["tree"] = -500.0
	t.check(float(SceneryLod.preset(0)["tree"]) > 0.0,
		"cached budgets cannot be modified by callers")
	t.eq(SceneryLod.category("tree:oak"), "tree", "foliage group recognized")
	t.eq(SceneryLod.category("ore:2"), "rock", "ore uses non-critical rock LOD")
	t.eq(SceneryLod.category("bush"), "bush", "bushes get near-cull distance")
	t.eq(SceneryLod.category("prop:3"), "prop", "scatter gets near-cull distance")
	t.eq(SceneryLod.category("decor:Flower_3"), "decor",
		"decor ranges are scaled instead of losing their author distance")
	for landmark in ["building:4", "wall:2", "tower:1", "ruin:0", "workbench", "monument:4"]:
		t.eq(SceneryLod.category(landmark), "landmark",
			"settlement building is kept for wayfinding")
		t.eq(SceneryLod.range_for(landmark, 0), 0.0,
			"landmarks are never culled by the scenery budget")

	t.current = "imported LOD and draw range scale with graphics quality"
	for kind in ["tree:pine", "rock:2", "bush", "prop:1"]:
		var last_distance := 0.0
		for quality in 4:
			var current_distance: float = SceneryLod.range_for(kind, quality)
			t.check(current_distance > last_distance,
				"high quality preserves more visible %s" % kind)
			last_distance = current_distance
	for quality in 4:
		var p: Dictionary = SceneryLod.preset(quality)
		t.check(float(p["lod_bias"]) > 0.0, "imported mesh LOD bias is valid")
		t.check(float(p["decor_scale"]) > 0.0, "decoration range scale is valid")
		t.check(SceneryLod.range_for("decor:fern", quality, 80.0) <= 100.0,
			"decor cannot escape its bounded authored draw range")
	t.eq(SceneryLod.range_for("tree:oak", 0), 112.0,
		"Performance reduces costly distant forest geometry")
	t.eq(SceneryLod.range_for("tree:oak", 3), 260.0,
		"Ultra retains distant forest silhouettes")
	t.eq(SceneryLod.range_for("decor:fern", 0, 90.0), 49.5,
		"Performance reduces undergrowth fill rate")
	t.eq(SceneryLod.range_for("decor:fern", 3, 90.0), 108.0,
		"Ultra keeps distant decoration")

	t.current = "quality applies to real MultiMesh nodes without rebuilding"
	var instance := MultiMeshInstance3D.new()
	SceneryLod.apply(instance, "tree:oak", 0)
	t.near(instance.lod_bias, 0.7, 0.00001,
		"low preset asks importer LODs for fewer triangles")
	t.eq(instance.visibility_range_end, 112.0,
		"far tree batches get frustum/range culled")
	SceneryLod.apply(instance, "tree:oak", 3)
	t.near(instance.lod_bias, 1.5, 0.00001,
		"Ultra retains the mesh silhouette farther away")
	t.eq(instance.visibility_range_end, 260.0,
		"quality change updates the already-created batch")
	SceneryLod.apply(instance, "building:2", 0)
	t.eq(instance.visibility_range_end, 0.0,
		"critical world landmarks have no artificial end range")
	ChunkView.configure_scenery(0)
	ChunkView.register_scenery(instance, "decor:fern", 80.0)
	t.eq(instance.visibility_range_end, 44.0,
		"newly streamed decor starts at the selected quality")
	ChunkView.configure_scenery(3)
	ChunkView.apply_scenery_detail(instance)
	t.eq(instance.visibility_range_end, 96.0,
		"existing batch changes LOD without reallocating its mesh")
	t.check(instance.is_in_group(ChunkView.SCENERY_GROUP),
		"batch is registered for quality switch updates")
	instance.free()
	ChunkView.configure_scenery(1)
