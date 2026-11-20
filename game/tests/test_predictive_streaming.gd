extends RefCounted
## Verify native WorldStreamer movement priority without loading assets or a world.
## Predictive streaming changes scheduling only, never authoritative world state.

func run(t) -> void:
	t.current = "native world partition movement budget"
	var streamer := WorldStreamer.new()
	t.near(streamer.lookahead_seconds, 0.0, 0.0001,
		"existing games retain nearest-first scheduling by default")
	t.eq(streamer.velocity_hint, Vector3.ZERO,
		"default hint does not pull queued world cells")
	streamer.lookahead_seconds = 2.0
	streamer.velocity_hint = Vector3(8.0, 0.0, -3.0)
	t.near(streamer.lookahead_seconds, 2.0, 0.0001,
		"online world provides a bounded forward prediction horizon")
	t.eq(streamer.velocity_hint, Vector3(8.0, 0.0, -3.0),
		"native streaming receives a world-space movement hint")
	streamer.velocity_hint = Vector3(INF, 0.0, 0.0)
	t.eq(streamer.velocity_hint, Vector3(8.0, 0.0, -3.0),
		"bad network velocity is ignored")
	streamer.lookahead_seconds = 50.0
	t.near(streamer.lookahead_seconds, 4.0, 0.0001,
		"engine prevents unbounded prediction")
	streamer.lookahead_seconds = -2.0
	t.near(streamer.lookahead_seconds, 0.0, 0.0001,
		"zero lookahead restores the original queue order")
	t.eq(streamer.max_chunk_work_usec, 0,
		"native streamer defaults to legacy count-only budget")
	streamer.max_chunk_work_usec = 2500
	t.eq(streamer.max_chunk_work_usec, 2500,
		"per-frame time slicing can be configured from GDScript")
	streamer.max_chunk_work_usec = -99
	t.eq(streamer.max_chunk_work_usec, 0,
		"negative CPU time budget cannot bypass the main-thread guard")
	streamer.max_chunk_work_usec = 1500000
	t.eq(streamer.max_chunk_work_usec, 1000000,
		"extreme CPU time budget is capped to one second")
	streamer.free()

	t.current = "actual online game integration and teleport safety"
	var online: String = FileAccess.get_file_as_string(
		"res://scripts/client/online_main.gd")
	t.check(online.contains("streamer.lookahead_seconds = 2.0"),
		"networked world explicitly opts into forward chunk prioritization")
	t.check(online.contains("streamer.velocity_hint = _stream_velocity"),
		"displayed authoritative player movement drives the native queue")
	t.check(online.contains("moved.length_squared() < 576.0"),
		"teleports and large server corrections reset motion prediction")
	t.check(online.contains("_stream_velocity = Vector3.ZERO"),
		"teleported or newly joined players do not predict obsolete directions")
	t.check(online.contains("streamer.max_instantiations_per_frame = 3"),
		"live generation can integrate up to three inexpensive chunks")
	t.check(online.contains("streamer.max_chunk_work_usec = 2500"),
		"live generation uses a 2.5 ms soft CPU time slice")
	t.check(online.contains("streamer.unload_radius = 220.0"),
		"moving forward does not change resident world memory hysteresis")
