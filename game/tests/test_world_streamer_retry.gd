extends RefCounted
## Native WorldStreamer recovery regression; requires a rebuilt Cgame binary.

var _transient_attempts := 0
var _exhausted_attempts := 0
var _empty_attempts := 0
var _batch_attempts: Dictionary = {}


func _sometimes_invalid(_cell: Vector3i) -> Variant:
	_transient_attempts += 1
	if _transient_attempts < 3:
		return 42 # Non-Node results are retryable errors, unlike null.
	return Node3D.new()


func _always_invalid(_cell: Vector3i) -> Variant:
	_exhausted_attempts += 1
	return "invalid chunk"


func _empty_chunk(_cell: Vector3i) -> Variant:
	_empty_attempts += 1
	return null


func _batch_invalid(cell: Vector3i) -> Variant:
	_batch_attempts[cell] = int(_batch_attempts.get(cell, 0)) + 1
	return "broken scene"


func _streamer(callback: String, retries: int) -> WorldStreamer:
	var streamer := WorldStreamer.new()
	streamer.axes = WorldStreamer.AXES_XZ
	streamer.cell_size = 16.0
	streamer.focus_position = Vector3(8, 0, 8)
	streamer.load_radius = 0.0
	streamer.unload_radius = 32.0
	streamer.update_interval = 100.0
	streamer.max_instantiations_per_frame = 1
	streamer.max_auto_retries = retries
	streamer.retry_initial_delay = 0.01
	streamer.retry_max_delay = 0.02
	streamer.set_chunk_generator(Callable(self, callback))
	return streamer


func run(t) -> void:
	t.current = "WorldStreamer transient failure retries with bounded exponential backoff"
	var transient := _streamer("_sometimes_invalid", 2)
	transient.refresh()
	t.eq(_transient_attempts, 1, "the first failed chunk is attempted once")
	t.eq(transient.get_retry_pending_count(), 1, "one failed cell awaits a retry")
	for i in 8:
		OS.delay_msec(25)
		transient.refresh()
	t.eq(_transient_attempts, 3, "two retries recover the previously invalid chunk")
	t.eq(transient.get_loaded_count(), 1, "recovered chunk is usable")
	t.eq(transient.get_retry_pending_count(), 0, "success clears retry state")
	transient.free()

	t.current = "WorldStreamer stops retrying after its finite failure limit"
	var exhausted := _streamer("_always_invalid", 1)
	exhausted.refresh()
	OS.delay_msec(25)
	exhausted.refresh()
	for i in 3:
		OS.delay_msec(25)
		exhausted.refresh()
	t.eq(_exhausted_attempts, 2, "one automatic retry then permanent failure")
	t.eq(exhausted.get_retry_pending_count(), 0, "exhausted cells do not spin")
	exhausted.refresh(true)
	t.eq(_exhausted_attempts, 3, "explicit retry resets the attempt limit")
	exhausted.free()

	t.current = "intentionally empty procedural cells are never retried"
	var empty := _streamer("_empty_chunk", 2)
	empty.refresh()
	for i in 3:
		OS.delay_msec(25)
		empty.refresh()
	t.eq(_empty_attempts, 1, "null chunks retain the existing empty-cell contract")
	t.eq(empty.get_retry_pending_count(), 0, "empty cells do not consume retry slots")
	empty.free()

	t.current = "correlated procedural failures release a bounded number of retries"
	var burst := _streamer("_batch_invalid", 1)
	burst.load_radius = 25.0
	burst.max_instantiations_per_frame = 16
	burst.retry_initial_delay = 0.01
	burst.retry_max_delay = 0.01
	burst.retry_delay_spread = 0.0 # All initial deadlines are near-identical.
	burst.max_retry_releases_per_update = 1
	burst.refresh()
	var initial_pending: int = burst.get_retry_pending_count()
	t.check(initial_pending >= 3, "multiple procedural cells enter retry backoff")
	OS.delay_msec(25)
	burst.refresh()
	t.eq(burst.get_last_retry_release_count(), 1,
		"only the oldest expired retry becomes eligible this refresh")
	t.eq(burst.get_last_retry_deferred_count(), initial_pending - 1,
		"all other expired cells remain retry-pending")
	t.eq(burst.get_retry_pending_count(), initial_pending - 1,
		"deferred retry tasks remain scheduled, rather than disappearing")
	for i in initial_pending - 1:
		burst.refresh()
	t.eq(burst.get_retry_pending_count(), 0,
		"all queued retry releases eventually progress under the one-per-pass cap")
	t.eq(burst.get_last_retry_deferred_count(), 0,
		"deferred retry telemetry clears after the last expired cell")
	for attempts in _batch_attempts.values():
		t.eq(attempts, 2, "each broken cell gets exactly one retry")
	burst.free()

	t.current = "deterministic retry jitter protects correlated failure bursts"
	var jittered := _streamer("_always_invalid", 2)
	t.eq(jittered.retry_delay_spread, 0.0,
		"retry spread is disabled by default to preserve previous scheduling")
	t.eq(jittered.max_retry_releases_per_update, 0,
		"uncapped automatic retries preserve old admission behavior")
	jittered.retry_delay_spread = 0.3
	jittered.max_retry_releases_per_update = 2
	t.near(jittered.retry_delay_spread, 0.3, 0.000001,
		"optional fraction is exposed as a native engine property")
	t.eq(jittered.max_retry_releases_per_update, 2,
		"optional retry-release cap is reflected in public API")
	var delay_a: float = WorldStreamer.calculate_retry_delay_seconds(
		Vector3i(1, 0, 1), 0, 0.5, 3.0, 0.3)
	var delay_b: float = WorldStreamer.calculate_retry_delay_seconds(
		Vector3i(-4, 0, 7), 0, 0.5, 3.0, 0.3)
	t.check(delay_a >= 0.35 and delay_a <= 0.5,
		"jitter never escapes the bounded exponential delay")
	t.check(delay_b >= 0.35 and delay_b <= 0.5,
		"another cell's retry delay stays within the same bounds")
	t.check(not is_equal_approx(delay_a, delay_b),
		"two different coordinates do not synchronize retry deadlines")
	t.near(WorldStreamer.calculate_retry_delay_seconds(
		Vector3i(1, 0, 1), 0, 0.5, 3.0, 0.3), delay_a, 0.0000001,
		"same cell and attempt deterministically reproduce the same delay")
	t.near(WorldStreamer.calculate_retry_delay_seconds(
		Vector3i(1, 0, 1), 2, 0.5, 3.0, 0.0), 2.0, 0.000001,
		"zero spread returns exact existing exponential backoff")
	t.eq(WorldStreamer.calculate_retry_delay_seconds(
		Vector3i(1, 0, 1), 0, 0.5, 3.0, 0.6), 0.0,
		"invalid jitter fraction cannot schedule a retry")
	jittered.free()
	var online_source: String = FileAccess.get_file_as_string("res://scripts/client/online_main.gd")
	t.check(online_source.contains("streamer.set_retry_delay_spread(0.30)"),
		"real game enables staggered retries for cosmetic world generation")
	t.check(online_source.contains("Albion/StreamRetryDeferred"),
		"real game exposes failed-chunk admission pressure in profiler")

	t.current = "WorldStreamer recovery defaults preserve legacy behavior"
	var legacy := WorldStreamer.new()
	t.eq(legacy.max_auto_retries, 0, "automatic recovery is opt-in")
	legacy.max_auto_retries = 100
	t.eq(legacy.max_auto_retries, 8, "attempt limit is clamped to eight")
	legacy.free()
