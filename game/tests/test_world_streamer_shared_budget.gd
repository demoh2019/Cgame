extends RefCounted
## Native WorldStreamer regression, using real procedural scenes but no assets,
## GPU rendering, network traffic or authoritative server simulation.
const StreamingPolicy = preload("res://scripts/client/world_streaming_policy.gd")

var _calls: Array[Vector3i] = []


func _make_chunk(cell: Vector3i) -> Node:
	_calls.append(cell)
	return Node3D.new()


func run(t) -> void:
	t.current = "single streaming count budget across refresh phases"
	_calls.clear()
	var streamer := WorldStreamer.new()
	streamer.axes = WorldStreamer.AXES_XZ
	streamer.cell_size = 16.0
	streamer.focus_position = Vector3(0.5, 0.0, 0.5)
	streamer.load_radius = 32.0
	streamer.unload_radius = 44.0
	streamer.max_instantiations_per_frame = 1
	streamer.max_chunk_work_usec = 0 # Test count limit, independent of wall clock.
	streamer.update_interval = 100.0 # Refresh explicitly, never in a background tick.
	streamer.set_chunk_generator(Callable(self, "_make_chunk"))
	# refresh() can generate procedural chunks on a detached streamer.
	# This avoids a GPU/scene-tree dependency in the deterministic test.

	streamer.refresh()
	t.eq(_calls.size(), 1,
		"refresh must not generate one chunk during poll and another after updating the queue")
	t.eq(streamer.get_loaded_count(), 1,
		"one native procedural chunk is adopted during one refresh")
	t.check(streamer.get_queued_generation_count() > 0,
		"engine exposes the remaining generator backlog instead of reporting zero")
	t.check(streamer.is_cell_loaded(Vector3i(0, 0, 0)),
		"the player's current cell is prioritized before speculative loads")
	streamer.refresh()
	t.eq(_calls.size(), 2, "a second refresh gets a new one-chunk budget")
	t.eq(streamer.get_loaded_count(), 2, "the current world reuses loaded chunk nodes")

	t.current = "disable pauses queued work and larger budget resumes streaming"
	streamer.enabled = false
	streamer.refresh()
	t.eq(_calls.size(), 2,
		"disabled WorldStreamer must never create queued scenery behind the menu")
	streamer.enabled = true
	streamer.max_instantiations_per_frame = 2
	streamer.refresh()
	t.eq(_calls.size(), 4, "one refresh is capped at two additional cheap chunks")
	t.eq(streamer.get_loaded_count(), 4,
		"newly generated chunks are adopted without loading duplicates")
	t.check(streamer.get_queued_generation_count() >= 0,
		"backlog telemetry never becomes negative")

	t.current = "mount-sensitive future cell priority without residency growth"
	t.near(StreamingPolicy.lookahead_seconds(false, Vector3(5, 0, 0)), 2.0, 0.0001,
		"walking looks two seconds ahead")
	t.near(StreamingPolicy.lookahead_seconds(true, Vector3(14, 0, 0)), 3.0, 0.0001,
		"riding looks farther ahead without increasing the streaming radius")
	t.near(StreamingPolicy.lookahead_seconds(true, Vector3.ZERO), 0.0, 0.0001,
		"standing still returns to nearest-first priority")
	t.eq(StreamingPolicy.lookahead_seconds(true, Vector3(INF, 0, 0)), 0.0,
		"invalid server corrections do not steer background loading")
	StreamingPolicy.apply(streamer, true, Vector3(14, 0, 0))
	t.near(streamer.lookahead_seconds, 3.0, 0.0001,
		"live mounted policy reaches native WorldStreamer")
	StreamingPolicy.apply(streamer, false, Vector3(5, 0, 0))
	t.near(streamer.lookahead_seconds, 2.0, 0.0001,
		"dismount restores walking streaming prediction")
	StreamingPolicy.apply(streamer, false, Vector3.ZERO)
	t.eq(streamer.lookahead_seconds, 0.0,
		"stop/teleport resets prediction without clearing cached world chunks")

	t.current = "actual UI and network game consume the native scene queue"
	var online := FileAccess.get_file_as_string("res://scripts/client/online_main.gd")
	var ui := FileAccess.get_file_as_string("res://scripts/client/ui_accessibility_layer.gd")
	t.check(online.contains("WorldStreamingPolicy.apply(streamer"),
		"networked world forwards actual mounted state to streaming scheduling")
	t.check(online.contains("_access.set_world_streamer(streamer)"),
		"the HUD gets a reference to the single shared native streamer")
	t.check(ui.contains("_world_streamer.get_queued_generation_count()"),
		"FPS overlay displays real queued chunk work only when enabled")
	t.check(ui.contains("_world_streamer.get_loaded_count()"),
		"FPS overlay displays actual resident world chunks")

	streamer.free()
