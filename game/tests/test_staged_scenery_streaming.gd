extends RefCounted
## GPU-free regressions for incremental cosmetic world decorations.
const ChunkView = preload("res://scripts/client/chunk_view.gd")
const DecorPolicy = preload("res://scripts/client/decor_streaming_policy.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


class VisualChunk:
	extends Node3D

	func has_pending_visual_detail() -> bool:
		return true


func _make_visual_chunk(_cell: Vector3i) -> Node:
	return VisualChunk.new()


func run(t) -> void:
	t.current = "scenery stream camera priority and atomic budget"
	t.near(DecorPolicy.rank(100.0, 1.0), 70.0, 0.001,
		"cosmetics in front of the player are prioritized within the same distance")
	t.near(DecorPolicy.rank(100.0, -1.0), 130.0, 0.001,
		"rearward scenery remains eligible, rather than being culled")
	t.eq(DecorPolicy.rank(-10.0, 0.0), 0.0,
		"invalid negative distance cannot outrank the current chunk")
	t.near(DecorPolicy.rank_ground(Vector2(0.0, -100.0), Vector2(0.0, -1.0)),
			70.0, 0.001, "the near camera-facing scenery keeps its original priority")
	t.near(DecorPolicy.rank_ground(Vector2(0.0, 100.0), Vector2(0.0, -1.0)),
			130.0, 0.001, "rearward scenery keeps its original priority")
	t.near(DecorPolicy.rank_ground(Vector2(30.0, 40.0), Vector2.ZERO),
			DecorPolicy.rank(50.0, 0.0), 0.001,
			"when camera is almost vertical, prioritize strictly by ground distance")
	var rank_rng := RandomNumberGenerator.new()
	rank_rng.seed = 12572
	var max_rank_error := 0.0
	for i in 500:
		var delta_xz := Vector2(rank_rng.randf_range(-200.0, 200.0),
				rank_rng.randf_range(-200.0, 200.0))
		var yaw: float = rank_rng.randf_range(0.0, TAU)
		var forward_xz: Vector2 = Vector2.from_angle(yaw)
		var old_facing: float = delta_xz.normalized().dot(forward_xz) \
				if delta_xz.length_squared() > 0.0001 else 0.0
		var old_rank: float = DecorPolicy.rank(delta_xz.length(), old_facing)
		var new_rank: float = DecorPolicy.rank_ground(delta_xz, forward_xz)
		max_rank_error = maxf(max_rank_error, absf(old_rank - new_rank))
	t.check(max_rank_error < 0.0001,
			"ground-plane queue ranking preserves per-chunk camera priority (%f)" % max_rank_error)
	t.check(DecorPolicy.can_continue(100000, 1000, 0),
		"first indivisible decorative mesh always builds to avoid starvation")
	t.check(DecorPolicy.can_continue(999, 1000, 2),
		"multiple cheap categories can complete within one shared time slice")
	t.check(not DecorPolicy.can_continue(1000, 1000, 2),
		"expensive categories defer the rest to subsequent frames")
	t.check(not DecorPolicy.can_continue(1, 0, 1),
		"zero-budget policy does not loop forever after first job")

	t.current = "gameplay world assets stay fully constructed before cosmetics"
	var initial := ChunkView.new()
	t.check(not initial.has_pending_visual_detail(),
		"an empty chunk has no cosmetic debt")
	initial._decor_tasks.append({"type": "nature", "entry": {}})
	t.check(initial.has_pending_visual_detail(),
		"only pending cosmetic categories control optional readiness")
	initial._decor_tasks.clear()
	t.check(not initial.has_pending_visual_detail(),
		"removing all decorative tasks restores fully ready state")
	initial.free()
	var source: String = (ChunkView as Script).source_code
	t.check(source.contains("func _build_terrain(")
		and source.contains("func _build_objects(")
		and source.contains("func _build_next_decor_entry("),
		"terrain and interactable object creation stay independent of delayed cosmetics")
	t.check(source.contains("_service_decor(self)") and
		source.contains("static var _decor_pending: Array[WeakRef]"),
		"one per-frame scheduler spans all loaded chunks without retaining unloaded scenes")
	t.check(source.contains("_decor_pending.append(weakref(self))"),
		"optional decor is queued using weak references")
	t.check(source.contains("streamer.mark_visual_details_ready("),
		"native streamer is notified when the last visual category completes")

	t.current = "graphics quality gates shared cosmetic CPU budget"
	var previous_budget := 0
	for level in 4:
		var profile: Dictionary = GraphicsQuality.profile(level)
		var budget: int = int(profile.get("decor_budget_usec", -1))
		t.check(budget > previous_budget and budget <= 12000,
			"higher graphics profiles grant a larger single-frame cosmetic work slice")
		previous_budget = budget
	ChunkView.configure_decor_budget(-100)
	t.eq(ChunkView.decor_budget_usec, 100, "invalid negative budget is clamped")
	ChunkView.configure_decor_budget(50000)
	t.eq(ChunkView.decor_budget_usec, 12000, "extreme cosmetic CPU budget is bounded")
	ChunkView.configure_decor_budget(
		int(GraphicsQuality.profile(1)["decor_budget_usec"]))
	t.eq(ChunkView.get_pending_decor_count(), 0,
		"completed and unadopted debug-only chunks do not pollute live backlog")

	t.current = "cached biome palettes preserve exact seeded tree selection"
	for biome_variant in ChunkView.TREES_BY_BIOME:
		var biome: String = str(biome_variant)
		var authored: Array = ChunkView.TREES_BY_BIOME[biome]
		var expected: Array = []
		for name_variant in authored:
			var name: String = str(name_variant)
			if not name.begins_with("painted"):
				expected.append(name)
		t.eq(ChunkView._tree_options_for_biome(biome, false), expected,
			"no-pack selection keeps original order, duplicates and weights for " + biome)
		t.eq(ChunkView._tree_options_for_biome(biome, false), expected,
			"repeat lookup reuses the same palette for " + biome)
		t.eq(ChunkView._tree_options_for_biome(biome, true), authored,
			"installed painted pack retains full biome palette for " + biome)
	t.eq(ChunkView._tree_options_for_biome("unknown", false),
		ChunkView._tree_options_for_biome("forest", false),
		"unrecognized biomes retain the forest fallback")
	t.eq(ChunkView._tree_options_for_biome("unknown", true),
		ChunkView.TREES_BY_BIOME["forest"],
		"painted-pack fallback still uses the original forest weighting")
	var chunk_source: String = (ChunkView as Script).source_code
	t.check(chunk_source.contains("transforms.resize(list.size())") and
		chunk_source.contains("tints.resize(list.size())") and
		chunk_source.contains("transforms[i] = transform") and
		chunk_source.contains("tints[i] = "),
		"streamed resource group preallocates transforms and colors before filling slots")
	t.check(chunk_source.contains("var painted_available: bool =") and
		chunk_source.contains("_tree_key(node, painted_available)"),
		"painted pack capability is checked once per chunk, not once per tree")

	t.current = "native streamer tracks optional visual staging separately"
	var world := WorldStreamer.new()
	world.axes = WorldStreamer.AXES_XZ
	world.cell_size = 16.0
	world.focus_position = Vector3(2.0, 0.0, 2.0)
	world.load_radius = 0.1
	world.unload_radius = 1.0
	world.max_instantiations_per_frame = 1
	world.set_chunk_generator(Callable(self, "_make_visual_chunk"))
	world.refresh()
	var focus_cell := Vector3i.ZERO
	t.eq(world.get_loaded_count(), 1, "world chunk becomes playable before cosmetics finish")
	t.eq(world.get_pending_visual_details_count(), 1,
		"native streamer records one cosmetically incomplete but loaded chunk")
	world.mark_visual_details_ready(focus_cell)
	t.eq(world.get_pending_visual_details_count(), 0,
		"cosmetic completion clears the native pending tracker")
	world.mark_visual_details_ready(focus_cell)
	t.eq(world.get_pending_visual_details_count(), 0,
		"duplicate completion signals remain idempotent")
	world.unload_all()
	t.eq(world.get_pending_visual_details_count(), 0,
		"unloading world cells also frees all visual tracking state")
	world.free()
