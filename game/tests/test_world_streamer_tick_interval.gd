extends RefCounted
## WorldStreamer native cosmetic tick tiers: opt-in, hysteresis, budgets,
## scene identity and Albion After graphics/cosmetic callback integration.
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")


class ProbeChunk extends Node3D:
	var applied_intervals: Array[float] = []
	var restores := 0
	var simulation_changes: Array[bool] = []

	func set_streaming_tick_interval(seconds: float) -> void:
		applied_intervals.append(seconds)

	func set_streaming_simulation_active(active: bool) -> void:
		simulation_changes.append(active)
		set_process(active)

	func can_cache_streaming_chunk() -> bool:
		return true

	func on_streaming_cache_restored() -> void:
		restores += 1


var generated: Array[Vector3i] = []
var transitioned: Array[Dictionary] = []


func _generate(cell: Vector3i) -> Node:
	generated.append(cell)
	return ProbeChunk.new()


func _on_tick_changed(cell: Vector3i, interval: float) -> void:
	transitioned.append({"cell": cell, "interval": interval})


func _streamer() -> WorldStreamer:
	var s := WorldStreamer.new()
	s.axes = WorldStreamer.AXES_XZ
	s.cell_size = 16.0
	s.load_radius = 24.0
	s.unload_radius = 96.0
	s.focus_position = Vector3(8, 0, 8)
	s.max_instantiations_per_frame = 64
	s.update_interval = 100.0
	s.set_chunk_generator(Callable(self, "_generate"))
	return s


func run(t) -> void:
	t.current = "legacy worlds retain full cosmetic tick frequency"
	generated.clear()
	var legacy := _streamer()
	t.eq(legacy.tick_throttle_radius, -1.0, "tick LOD is disabled by default")
	legacy.refresh()
	var far_cell := Vector3i(1, 0, 0)
	var legacy_far := legacy.get_chunk(far_cell) as ProbeChunk
	t.check(legacy_far != null, "further visible chunk was generated")
	if legacy_far != null:
		t.eq(legacy_far.applied_intervals.size(), 0,
			"disabled engine does not call extra script methods")
	t.eq(legacy.get_tick_throttled_count(), 0,
		"full-rate legacy world records no throttled chunks")
	legacy.free()

	t.current = "initial cosmetic interval set before entering scene tree"
	generated.clear()
	transitioned.clear()
	var streamer := _streamer()
	streamer.tick_throttle_radius = 4.0
	streamer.tick_throttle_hysteresis = 0.0
	streamer.tick_throttle_interval = 0.125
	streamer.max_tick_throttle_transitions_per_update = 1
	streamer.chunk_tick_interval_changed.connect(Callable(self, "_on_tick_changed"))
	streamer.refresh()
	var resident_count: int = streamer.get_loaded_count()
	var close := streamer.get_chunk(Vector3i.ZERO) as ProbeChunk
	var distant := streamer.get_chunk(far_cell) as ProbeChunk
	t.check(close != null and distant != null,
		"near and distant procedural chunks both exist")
	if close != null:
		t.eq(close.applied_intervals, [0.0],
			"near chunk receives immediate full-rate preference")
	if distant != null:
		t.eq(distant.applied_intervals, [0.125],
			"distant chunk starts with a throttled cosmetic interval")
	t.check(streamer.is_cell_tick_throttled(far_cell),
		"native diagnostics track the distant callback")
	t.check(not streamer.is_cell_tick_throttled(Vector3i.ZERO),
		"native near chunk is not throttled")
	t.check(streamer.get_tick_throttled_count() > 0,
		"far resident chunk accounting is nonzero")
	t.eq(transitioned.size(), 0,
		"initial scene integration does not consume the transition quota")

	t.current = "nearest-first rate restoration and hysteresis"
	streamer.focus_position = Vector3(20, 0, 8)
	streamer.refresh()
	t.check(not streamer.is_cell_tick_throttled(far_cell),
		"nearer existing scene is restored first with one transition")
	t.eq(streamer.get_loaded_count(), resident_count,
		"cosmetic tick LOD never unloads visual chunks")
	if distant != null:
		t.eq(distant.applied_intervals, [0.125, 0.0],
			"the same chunk receives one full-rate recovery callback")
	t.eq(transitioned.size(), 1,
		"one native transition callback within the configured budget")
	streamer.tick_throttle_hysteresis = 12.0
	streamer.focus_position = Vector3(8, 0, 8)
	streamer.refresh()
	t.check(not streamer.is_cell_tick_throttled(far_cell),
		"hysteresis prevents demotion during small focus movement")
	streamer.tick_throttle_hysteresis = 0.0
	streamer.refresh()
	t.check(streamer.is_cell_tick_throttled(far_cell),
		"removing hysteresis eventually restores far update rate")

	t.current = "interval retuning and bounded work"
	transitioned.clear()
	streamer.tick_throttle_interval = 0.25
	streamer.refresh()
	t.eq(transitioned.size(), 1,
		"retuning a populated world changes at most one chunk per update")
	for i in resident_count + 2:
		streamer.refresh()
	if distant != null:
		t.near(distant.applied_intervals.back(), 0.25, 0.0001,
			"existing far scene eventually adopts new interval")
	t.check(streamer.get_tick_throttled_count() <= streamer.get_loaded_count(),
		"throttled scene counter cannot exceed loaded count")

	t.current = "disabling tick LOD converges without changing simulation"
	var count_before: int = streamer.get_loaded_count()
	streamer.tick_throttle_radius = -1.0
	for i in resident_count + 2:
		streamer.refresh()
	t.eq(streamer.get_tick_throttled_count(), 0,
		"legacy full-rate callbacks are restored for all scenes")
	t.eq(streamer.get_loaded_count(), count_before,
		"turning off cosmetic throttle never regenerates a chunk")
	t.check(not streamer.is_cell_tick_throttled(far_cell),
		"old throttle flags are discarded")
	streamer.unload_all()
	t.eq(streamer.get_tick_throttled_count(), 0,
		"unload_all clears native cosmetic LOD bookkeeping")
	streamer.free()

	t.current = "native cap and unsafe numeric inputs"
	var config := WorldStreamer.new()
	config.tick_throttle_radius = 200000.0
	t.eq(config.tick_throttle_radius, 100000.0, "near radius has a finite cap")
	config.tick_throttle_radius = -10.0
	t.eq(config.tick_throttle_radius, -1.0, "negative radius disables throttle")
	config.tick_throttle_interval = 99.0
	t.eq(config.tick_throttle_interval, 1.0, "script interval cannot exceed one second")
	config.tick_throttle_interval = -2.0
	t.eq(config.tick_throttle_interval, 0.0, "zero interval restores full-rate mode")
	config.tick_throttle_hysteresis = 10000.0
	t.eq(config.tick_throttle_hysteresis, 1000.0,
		"large hysteresis is safely clamped")
	config.max_tick_throttle_transitions_per_update = -10
	t.eq(config.max_tick_throttle_transitions_per_update, 1,
		"transition quota always grants at least one")
	config.max_tick_throttle_transitions_per_update = 1000
	t.eq(config.max_tick_throttle_transitions_per_update, 64,
		"transition quota has strict native maximum")
	config.free()

	t.current = "Albion After scene and quality profiles use real engine callbacks"
	var view := ChunkView.new()
	view.set_streaming_tick_interval(0.2)
	t.near(float(view.get("_streaming_tick_interval")), 0.2, 0.0001,
		"real ChunkView accepts native cosmetic interval")
	view.set_streaming_simulation_active(false)
	t.check(not view.is_processing(), "simulation pause still suspends cosmetics")
	view.set_streaming_simulation_active(true)
	t.check(view.is_processing(), "near-resumed scenes may process again")
	view.set_streaming_tick_interval(0.0)
	t.near(float(view.get("_streaming_tick_interval")), 0.0, 0.0001,
		"full-rate near tier restores the original per-frame process path")
	view.free()
	for level in 4:
		var radius: float = GraphicsQuality.streamed_tick_radius_for_quality(level)
		var interval: float = GraphicsQuality.streamed_tick_interval_for_quality(level)
		t.check(radius > 0.0 and radius < 110.0,
			"throttle tier stays within the game's simulation-active radius")
		t.check(interval >= 0.05 and interval <= 0.20,
			"quality profile selects a bounded cosmetic interval")
	var graphics_source := FileAccess.get_file_as_string("res://scripts/client/graphics_quality.gd")
	t.check(graphics_source.contains('streamer.has_method("set_tick_throttle_radius")') and
		graphics_source.contains("streamed_tick_interval_for_quality"),
		"quality settings update native tick tier during runtime quality changes")
	var online_source := FileAccess.get_file_as_string("res://scripts/client/online_main.gd")
	t.check(online_source.contains("Albion/StreamCosmeticTickThrottled") and
		online_source.contains("max_tick_throttle_transitions_per_update"),
		"online game enables rate transitions and exposes the native profiler count")
