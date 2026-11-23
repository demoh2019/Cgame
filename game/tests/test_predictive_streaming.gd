extends RefCounted
## Verify native WorldStreamer movement priority without loading assets or a world.
## Predictive streaming changes scheduling only, never authoritative world state.

const WorldStreamingPolicy = preload("res://scripts/client/world_streaming_policy.gd")

func run(t) -> void:
	t.current = "stream prefetch ignores impossible correction and teleport speeds"
	t.eq(WorldStreamingPolicy.lookahead_seconds(false, Vector3.ZERO), 0.0,
		"idling does not predict distant chunks")
	t.eq(WorldStreamingPolicy.lookahead_seconds(false, Vector3(8.0, 0.0, -3.0)),
		WorldStreamingPolicy.WALK_LOOKAHEAD,
		"walking still prioritizes chunks ahead of normal movement")
	t.eq(WorldStreamingPolicy.lookahead_seconds(true, Vector3(12.0, 0.0, 0.0)),
		WorldStreamingPolicy.RIDING_LOOKAHEAD,
		"riding keeps a longer, bounded world prefetch horizon")
	t.eq(WorldStreamingPolicy.lookahead_seconds(true, Vector3(50.0, 0.0, 0.0)), 0.0,
		"teleport-rate movement does not pull the queue far from the player")
	t.eq(WorldStreamingPolicy.lookahead_seconds(false, Vector3(1.0e30, 0.0, 0.0)), 0.0,
		"overflowing squared velocity cannot poison chunk scheduling")
	t.eq(WorldStreamingPolicy.lookahead_seconds(false, Vector3(INF, 0.0, 0.0)), 0.0,
		"non-finite network corrections have no lookahead")
	t.eq(WorldStreamingPolicy.lookahead_seconds(true, Vector3(48.0, 0.0, 0.0)),
		WorldStreamingPolicy.RIDING_LOOKAHEAD,
		"the conservative cap still accepts movement exactly at its boundary")
	t.check(WorldStreamingPolicy.plausible_velocity(Vector3(18.0, 0.0, 0.0)),
		"normal visual velocity is safe for prefetch")
	t.check(not WorldStreamingPolicy.plausible_velocity(Vector3(75.0, 0.0, 0.0)),
		"raw un-clamped teleport velocities are rejected")

	t.current = "native world partition movement budget"
	var streamer := WorldStreamer.new()
	t.near(streamer.lookahead_seconds, 0.0, 0.0001,
		"existing games retain nearest-first scheduling by default")
	t.eq(streamer.velocity_hint, Vector3.ZERO,
		"default hint does not pull queued world cells")
	t.eq(streamer.get_queued_generation_count(), 0,
		"new streamers start with no stale procedural requests")
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
	t.current = "native camera cone and cinematic compatibility"
	t.near(streamer.view_cone_half_angle_degrees, 180.0, 0.0001,
		"legacy WorldStreamer leaves view cone unbounded")
	streamer.view_cone_half_angle_degrees = 52.0
	t.near(streamer.view_cone_half_angle_degrees, 52.0, 0.0001,
		"game can set native horizontal camera cone")
	streamer.view_cone_half_angle_degrees = INF
	t.near(streamer.view_cone_half_angle_degrees, 52.0, 0.0001,
		"corrupt camera FOV cannot poison scheduling")
	streamer.view_cone_half_angle_degrees = 360.0
	t.near(streamer.view_cone_half_angle_degrees, 180.0, 0.0001,
		"native view cone is bounded")
	t.near(WorldStreamingPolicy.horizontal_cone_half_angle(60.0, 16.0 / 9.0, false),
		42.0, 0.001, "horizontal FOV for keep-width camera includes view margin")
	t.check(WorldStreamingPolicy.horizontal_cone_half_angle(60.0, 16.0 / 9.0, true) > 42.0,
		"keep-height perspective derives wider horizontal field on widescreen")
	t.near(WorldStreamingPolicy.horizontal_cone_half_angle(INF, 16.0 / 9.0, true),
		180.0, 0.001, "invalid projection falls back to the old heading-only mode")
	WorldStreamingPolicy.apply_view(streamer, null, 2)
	t.near(streamer.view_cone_half_angle_degrees, 180.0, 0.001,
		"missing camera never restricts the queue")
	var policy_source: String = FileAccess.get_file_as_string(
		"res://scripts/client/world_streaming_policy.gd")
	t.check(policy_source.contains("streamer.view_cone_half_angle_degrees = half_angle"),
		"live view policy forwards perspective camera FOV into native engine")
	streamer.free()

	t.current = "actual online game integration and teleport safety"
	var online: String = FileAccess.get_file_as_string(
		"res://scripts/client/online_main.gd")
	t.check(online.contains("streamer.lookahead_seconds = 2.0"),
		"networked world explicitly opts into forward chunk prioritization")
	t.check(online.contains("streamer.velocity_hint = _stream_velocity"),
		"displayed authoritative player movement drives the native queue")
	t.check(online.contains("WorldStreamingPolicy.plausible_velocity(raw_velocity)"),
		"real online client checks raw displacement before smoothing prefetch")
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
	t.check(online.contains("CLIENT streaming: loaded=%d queued=%d threaded=%d")
		and online.contains("streamer.get_queued_generation_count()"),
		"benchmark reports procedural backlog separately from GPU frame pacing")
