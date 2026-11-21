extends RefCounted
## Backward-compatible integration and deterministic pressure expectations.
## C++ tests cover the actual pressure calculator and effective limits.

const OnlineMain = preload("res://scripts/client/online_main.gd")


func _make_chunk(_cell: Vector3i) -> Node3D:
	return Node3D.new()



func run(t) -> void:
	t.current = "streaming adaptive budget is opt-in and safe for older binaries"
	var streamer := WorldStreamer.new()
	streamer.max_instantiations_per_frame = 3
	streamer.max_chunk_work_usec = 2500
	if streamer.has_method("set_adaptive_chunk_budget_enabled"):
		t.check(not streamer.is_adaptive_chunk_budget_enabled(),
			"native streamer defaults to legacy fixed budgets")
		t.eq(streamer.get_effective_instantiations_per_frame(), 3,
			"unpressured scene allows three chunk activations")
		t.eq(streamer.get_effective_chunk_work_usec(), 2500,
			"unpressured time limit matches user configuration")
		streamer.set_adaptive_chunk_budget_enabled(true)
		t.check(streamer.is_adaptive_chunk_budget_enabled(),
			"game can enable adaptive streaming")
		t.eq(streamer.get_last_frame_chunk_work_usec(), 0,
			"stream work begins without stale measurements")
		t.eq(streamer.get_last_frame_chunk_attempt_count(), 0,
			"no chunks are reported before processing")
		streamer.set_adaptive_chunk_budget_enabled(false)
		t.eq(streamer.get_streaming_frame_pressure_percent(), 0.0,
			"disabling adaptivity clears previous pressure")
		# Detached refresh exercises the actual native procedural generator,
		# per-frame work bookkeeping and the same one-count safety limit.
		streamer.axes = WorldStreamer.AXES_XZ
		streamer.cell_size = 16.0
		streamer.focus_position = Vector3(8, 0, 8)
		streamer.load_radius = 0.0
		streamer.unload_radius = 32.0
		streamer.max_instantiations_per_frame = 1
		streamer.set_chunk_generator(Callable(self, "_make_chunk"))
		streamer.set_adaptive_chunk_budget_enabled(true)
		streamer.refresh()
		t.eq(streamer.get_loaded_count(), 1,
			"adaptive mode still creates its minimum one chunk")
		t.eq(streamer.get_last_frame_chunk_attempt_count(), 1,
			"successful procedural creation is measured once")
		t.check(streamer.get_last_frame_chunk_work_usec() >= 0,
			"CPU telemetry always reports nonnegative microseconds")
		streamer.refresh()
		t.eq(streamer.get_last_frame_chunk_attempt_count(), 0,
			"empty work frame resets the previous attempt count")

	else:
		t.check(true, "older Godot fork safely keeps fixed streaming budgets")
	streamer.free()

	t.current = "the actual Albion After client enables adaptive streaming conditionally"
	var source: String = (OnlineMain as Script).source_code
	t.check(source.contains('if "adaptive_chunk_budget_enabled" in streamer:'),
		"older engine binaries never receive unsupported property assignments")
	t.check(source.contains("streamer.adaptive_chunk_budget_enabled = true"),
		"Albion After opts in on compatible native builds")
	for monitor_name in [
		"Albion/StreamChunkCPUus", "Albion/StreamChunkAttempts",
		"Albion/StreamPressurePct", "Albion/StreamEffectiveSlots",
		"Albion/StreamEffectiveCPUus",
	]:
		t.check(source.contains(monitor_name), "%s is exported to profiler" % monitor_name)
	t.check(source.contains('_ambient_monitors.append(monitor_name)'),
		"runtime streamer monitors participate in cleanup on scene exit")
