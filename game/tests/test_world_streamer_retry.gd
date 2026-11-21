extends RefCounted
## Native WorldStreamer recovery regression; requires a rebuilt Cgame binary.

var _transient_attempts := 0
var _exhausted_attempts := 0
var _empty_attempts := 0


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

	t.current = "WorldStreamer recovery defaults preserve legacy behavior"
	var legacy := WorldStreamer.new()
	t.eq(legacy.max_auto_retries, 0, "automatic recovery is opt-in")
	legacy.max_auto_retries = 100
	t.eq(legacy.max_auto_retries, 8, "attempt limit is clamped to eight")
	legacy.free()
