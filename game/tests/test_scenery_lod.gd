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
	t.current = "Unreal Cull Distance Volume: nearest bounds-size pair with authored cap"
	var profile_sizes := PackedFloat32Array([64.0, 1.0, 24.0, 4.0, 10.0])
	var profile_ranges := PackedFloat32Array([0.0, 45.0, 160.0, 75.0, 105.0])
	var cluster := AABB(Vector3(-100, 0, -50), Vector3(24, 2, 8))
	t.eq(SceneryLod.cull_range_for_bounds(cluster,
		profile_sizes, profile_ranges, 0.0, false), 160.0,
		"native-equivalent fallback measures longest AABB edge, not diagonal")
	t.eq(SceneryLod.cull_range_for_bounds(cluster,
		profile_sizes, profile_ranges, 90.0, false), 90.0,
		"per-instance author maximum cannot be extended")
	t.eq(SceneryLod.cull_range_for_bounds(AABB(Vector3.ZERO, Vector3(72, 2, 1)),
		profile_sizes, profile_ranges, 120.0, false), 120.0,
		"large profile uses zero to keep author's own draw range")
	t.eq(SceneryLod.cull_range_for_bounds(AABB(Vector3.ZERO, Vector3(72, 2, 1)),
		profile_sizes, profile_ranges, 0.0, false), 0.0,
		"true unlimited draw range remains distinguishable from invalid input")
	t.eq(SceneryLod.cull_range_for_bounds(AABB(Vector3.ZERO, Vector3(3, 1, 1)),
		PackedFloat32Array([4.0, 2.0, 2.0]),
		PackedFloat32Array([0.0, 50.0, 35.0]), 0.0, false), 35.0,
		"equal-size pairs take the smallest positive distance")
	t.eq(SceneryLod.cull_range_for_bounds(cluster,
		profile_sizes, PackedFloat32Array([1.0]), 0.0, false), -1.0,
		"invalid mismatched arrays reject, not silently cull")
	var invalid_ranges: PackedFloat32Array = profile_ranges.duplicate()
	invalid_ranges[4] = NAN
	t.eq(SceneryLod.cull_range_for_bounds(cluster,
		profile_sizes, invalid_ranges, 0.0, false), -1.0,
		"late NaN invalidates the entire native-equivalent profile")
	t.eq(SceneryLod.cull_range_for_bounds(cluster,
		profile_sizes, profile_ranges, -5.0, false), -1.0,
		"negative max draw distance rejected")

	t.current = "Albion streamed GPU batches: smaller cosmetic groups cull sooner"
	var small := AABB(Vector3.ZERO, Vector3.ONE)
	var big := AABB(Vector3.ZERO, Vector3(80, 1, 1))
	t.near(SceneryLod.decor_range_for_bounds(small, 0, 66.0, false), 24.75, 0.001,
		"Performance reduces long-lived tiny decor batches")
	t.near(SceneryLod.decor_range_for_bounds(small, 3, 144.0, false), 54.0, 0.001,
		"Ultra retains smaller decor farther than Performance")
	t.eq(SceneryLod.decor_range_for_bounds(big, 0, 66.0, false), 66.0,
		"wide batches preserve previous draw cap")
	t.eq(SceneryLod.decor_range_for_bounds(AABB(), 0, 66.0, false), 66.0,
		"unset AABB retains legacy behavior")
	var test_decoration := MultiMeshInstance3D.new()
	test_decoration.custom_aabb = small
	SceneryLod.apply(test_decoration, "decor:Fern_1", 0, 120.0)
	t.near(test_decoration.visibility_range_end, 24.75, 0.001,
		"actual MultiMesh node uses the size-aware range at quality 0")
	SceneryLod.apply(test_decoration, "decor:Fern_1", 3, 120.0)
	t.near(test_decoration.visibility_range_end, 54.0, 0.001,
		"quality changes recompute profile without rebuilding MultiMesh")
	SceneryLod.apply(test_decoration, "tree:oak", 0)
	t.eq(test_decoration.visibility_range_end, 112.0,
		"tree silhouettes and shader culling are untouched")
	SceneryLod.apply(test_decoration, "building:2", 0)
	t.eq(test_decoration.visibility_range_end, 0.0,
		"landmarks stay visible independent of their bounding size")
	test_decoration.free()

	if ClassDB.class_exists("CullDistanceProfile3D"):
		var native: Object = ClassDB.instantiate("CullDistanceProfile3D")
		t.check(native != null and native.has_method("get_cull_distance"),
			"engine class exposes native size-to-distance profile API")
		if native != null and native.has_method("get_cull_distance"):
			t.eq(native.call("get_cull_distance", cluster,
				profile_sizes, profile_ranges, 190.0),
				SceneryLod.cull_range_for_bounds(cluster,
					profile_sizes, profile_ranges, 190.0, false),
				"native and GDScript policies match for authored cap")
			t.near(SceneryLod.decor_range_for_bounds(small, 0, 66.0),
				SceneryLod.decor_range_for_bounds(small, 0, 66.0, false), 0.00001,
				"native Cgame and stock-Godot game ranges agree")
			var policy_rng := RandomNumberGenerator.new()
			policy_rng.seed = 91471
			for case_index in 64:
				var size_x: float = policy_rng.randf_range(0.01, 100.0)
				var author_cap: float = policy_rng.randf_range(0.0, 250.0)
				var generated_bounds := AABB(Vector3(-10, 0, 15),
					Vector3(size_x, policy_rng.randf_range(0.01, 40.0), 3.0))
				var ref_distance: float = SceneryLod.cull_range_for_bounds(
					generated_bounds, profile_sizes, profile_ranges, author_cap, false)
				t.eq(native.call("get_cull_distance", generated_bounds,
						profile_sizes, profile_ranges, author_cap),
					ref_distance, "native/fallback parity seeded sample %d" % case_index)
	else:
		t.near(SceneryLod.decor_range_for_bounds(small, 0, 66.0),
			24.75, 0.00001, "stock Godot uses deterministic size-profile fallback")
	instance.free()
	ChunkView.configure_scenery(1)
