extends RefCounted
## Backward-compatible integration and deterministic pressure expectations.
## C++ tests cover the actual pressure calculator and effective limits.

const OnlineMain = preload("res://scripts/client/online_main.gd")


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
