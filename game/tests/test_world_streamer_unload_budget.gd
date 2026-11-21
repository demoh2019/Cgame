extends RefCounted
## Real WorldStreamer scene churn, teleport reversal and visual-profile wiring.
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")

var generated: Array[Vector3i] = []
var _unload_events: Array[Vector3i] = []


func _record_unload(cell: Vector3i) -> void:
	_unload_events.append(cell)


func _make_chunk(cell: Vector3i) -> Node:
	# Generate only the initial area; far-away teleports cannot introduce new
	# scenes that would hide an incorrect unload budget in the counts.
	if cell.x > 5 or cell.z > 5:
		return null
	generated.append(cell)
	return Node3D.new()


func _make_streamer() -> WorldStreamer:
	var s := WorldStreamer.new()
	s.axes = WorldStreamer.AXES_XZ
	s.cell_size = 16.0
	s.focus_position = Vector3(8, 0, 8)
	s.load_radius = 24.0
	s.unload_radius = 24.0
	s.max_instantiations_per_frame = 64
	s.update_interval = 100.0
	s.set_chunk_generator(Callable(self, "_make_chunk"))
	return s


static func _distance_to_cell(point: Vector3, cell: Vector3i, size: float) -> float:
	var x: float = clampf(point.x, float(cell.x) * size, float(cell.x + 1) * size)
	var z: float = clampf(point.z, float(cell.z) * size, float(cell.z + 1) * size)
	return Vector2(point.x - x, point.z - z).length()


func run(t) -> void:
	t.current = "legacy whole-world unloads remain unlimited"
	var legacy := _make_streamer()
	t.eq(legacy.max_unloads_per_update, 0, "engine default is unchanged")
	legacy.refresh()
	var original_count: int = legacy.get_loaded_count()
	t.check(original_count > 4, "multiple initial procedural cells load")
	legacy.focus_position = Vector3(512, 0, 512)
	legacy.refresh()
	t.eq(legacy.get_loaded_count(), 0,
		"legacy single refresh unloads every distant chunk")
	t.eq(legacy.get_last_unload_count(), original_count,
		"diagnostics count actual immediate chunk retirements")
	t.eq(legacy.get_last_deferred_unload_count(), 0,
		"unlimited mode has no deferred cleanup")
	legacy.free()

	t.current = "strict per-update count and deterministic farthest-first order"
	generated.clear()
	var streamer := _make_streamer()
	streamer.max_unloads_per_update = 2
	streamer.refresh()
	var count: int = streamer.get_loaded_count()
	t.check(count > 4, "multiple chunks are ready before teleport")
	_unload_events.clear()
	streamer.chunk_unloaded.connect(Callable(self, "_record_unload"))
	var destination := Vector3(512, 0, 512)
	streamer.focus_position = destination
	streamer.refresh()
	t.eq(streamer.get_last_unload_count(), 2,
		"exactly two out-of-range chunks retire on this update")
	t.eq(streamer.get_last_deferred_unload_count(), count - 2,
		"remaining stale chunks are deferred instead of being dropped at once")
	t.eq(streamer.get_loaded_count(), count - 2,
		"deferred cells remain in the regular resident set until next update")
	t.eq(_unload_events.size(), 2, "only two native unload signals fire")
	for removed in _unload_events:
		var removed_distance: float = _distance_to_cell(destination, removed, 16.0)
		for resident in streamer.get_loaded_cells():
			t.check(removed_distance + 0.0001 >= _distance_to_cell(destination, resident, 16.0),
				"farthest cells always retire ahead of nearer retained cells")

	t.current = "teleport reversal cancels deferred unloads"
	streamer.focus_position = Vector3(8, 0, 8)
	streamer.refresh()
	t.eq(streamer.get_last_unload_count(), 0,
		"returning to the old focus does not release newly wanted chunks")
	t.eq(streamer.get_last_deferred_unload_count(), 0,
		"stale backlog disappears on the next reevaluation")
	t.eq(streamer.get_loaded_count(), count,
		"the two missing chunks can regenerate under the ordinary frame budget")

	t.current = "progressive draining and explicit cleanup bypass the budget"
	streamer.focus_position = destination
	var previous_count: int = streamer.get_loaded_count()
	for i in count + 4:
		streamer.refresh()
		t.check(streamer.get_last_unload_count() <= 2,
			"every update enforces its own unload cap")
		t.check(streamer.get_loaded_count() <= previous_count,
			"far-area generation cannot hide delayed scene cleanup")
		previous_count = streamer.get_loaded_count()
		if streamer.get_loaded_count() == 0:
			break
	t.eq(streamer.get_loaded_count(), 0,
		"repeated ticks eventually remove every obsolete scene")
	t.eq(streamer.get_last_deferred_unload_count(), 0,
		"all deferred retirements are drained")
	streamer.focus_position = Vector3(8, 0, 8)
	streamer.refresh()
	streamer.max_unloads_per_update = 1
	streamer.unload_all()
	t.eq(streamer.get_loaded_count(), 0,
		"manual unload_all remains an immediate full reset")
	t.eq(streamer.get_last_deferred_unload_count(), 0,
		"manual reset clears the pending-work diagnostic")
	streamer.free()

	t.current = "secondary source retains requested cells despite unload budget"
	var auxiliary := _make_streamer()
	auxiliary.max_unloads_per_update = 1
	auxiliary.refresh()
	t.check(auxiliary.is_cell_loaded(Vector3i.ZERO),
		"the home visual cell is loaded")
	auxiliary.set_auxiliary_source(Vector3(8, 0, 8), 12.0)
	auxiliary.focus_position = Vector3(48, 0, 8)
	for i in 40:
		auxiliary.refresh()
	t.check(auxiliary.is_cell_loaded(Vector3i.ZERO),
		"nearby auxiliary source keeps home cell even beyond main unload radius")
	auxiliary.clear_auxiliary_source()
	for i in 40:
		auxiliary.refresh()
	t.check(not auxiliary.is_cell_loaded(Vector3i.ZERO),
		"removing source eventually releases its former resident cells")
	auxiliary.free()

	t.current = "native hard cap and preset-driven game integration"
	var config := WorldStreamer.new()
	config.max_unloads_per_update = -30
	t.eq(config.max_unloads_per_update, 0, "negative unload limits restore legacy mode")
	config.max_unloads_per_update = 10000
	t.eq(config.max_unloads_per_update, 64, "native budget never exceeds 64 cells")
	config.max_unloads_per_update = 3
	t.eq(config.max_unloads_per_update, 3, "valid custom count is preserved")
	t.eq(config.get_last_unload_count(), 0,
		"configuration does not fabricate unloaded work")
	config.free()
	var expected: Array[int] = [12, 20, 32, 48]
	for tier in expected.size():
		t.eq(GraphicsQuality.unload_budget_for_quality(tier), expected[tier],
			"the actual graphics profile selects a bounded cleanup budget")
	t.eq(GraphicsQuality.unload_budget_for_quality(-50), 12,
		"invalid low-quality value cannot disable cleanup unintentionally")
	t.eq(GraphicsQuality.unload_budget_for_quality(500), 48,
		"invalid high-quality value is clamped")
	var graphics_source := FileAccess.get_file_as_string("res://scripts/client/graphics_quality.gd")
	t.check(graphics_source.contains("streamer.has_method(\"set_max_unloads_per_update\")")
		and graphics_source.contains("set_max_unloads_per_update"),
		"real game applies native limits whenever graphics quality changes")
	var online := FileAccess.get_file_as_string("res://scripts/client/online_main.gd")
	t.check(online.contains("Albion/StreamUnloadsDeferred")
		and online.contains("Albion/StreamUnloadedLastUpdate"),
		"performance profiler tracks actual deferred and completed cleanup")
