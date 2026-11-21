extends RefCounted
## Engine-side simulation LOD must not change chunk residency or load budgets.


class ProbeChunk extends Node3D:
	var transitions: Array[bool] = []

	func set_streaming_simulation_active(active: bool) -> void:
		transitions.append(active)
		set_process(active)


func _make_chunk(_cell: Vector3i) -> Node:
	return ProbeChunk.new()


func run(t) -> void:
	t.current = "native simulation tier defaults to legacy all-active chunks"
	var streamer := WorldStreamer.new()
	streamer.axes = WorldStreamer.AXES_XZ
	streamer.cell_size = 16.0
	streamer.load_radius = 24.0
	streamer.unload_radius = 32.0
	streamer.focus_position = Vector3(8.0, 0.0, 8.0)
	streamer.max_instantiations_per_frame = 64
	streamer.set_chunk_generator(Callable(self, "_make_chunk"))
	streamer.refresh()
	var initial_count: int = streamer.get_loaded_count()
	t.check(initial_count > 2, "test generated multiple world chunks")
	t.eq(streamer.simulation_radius, -1.0, "legacy opt-out remains the default")
	t.eq(streamer.get_simulation_active_count(), initial_count,
		"legacy simulation tracks all loaded chunks as active")
	var far_cell := Vector3i(1, 0, 0)
	var far_chunk := streamer.get_chunk(far_cell) as ProbeChunk
	t.check(far_chunk != null, "far visual chunk is resident")
	if far_chunk != null:
		t.eq(far_chunk.transitions.size(), 0,
			"opt-out never calls a chunk's simulation hook")

	t.current = "budgeted far-tier changes retain loaded terrain"
	streamer.max_simulation_transitions_per_update = 1
	streamer.simulation_hysteresis = 0.0
	streamer.simulation_radius = 4.0
	streamer.refresh()
	t.eq(streamer.get_loaded_count(), initial_count,
		"simulation LOD never unloads or regenerates chunks")
	t.eq(streamer.get_simulation_active_count(), initial_count - 1,
		"at most one existing chunk changes tier per update")
	for i in initial_count:
		streamer.refresh()
	t.eq(streamer.get_simulation_active_count(), 1,
		"far visual chunks eventually pause their own simulation")
	t.check(streamer.is_cell_simulation_active(Vector3i.ZERO),
		"focus chunk always retains its cosmetic simulation")
	t.check(not streamer.is_cell_simulation_active(far_cell),
		"far chunk has been demoted without unloading")
	if far_chunk != null:
		t.eq(far_chunk.transitions, [false],
			"far root receives exactly one pause callback")
		t.check(not far_chunk.is_processing(), "chunk opts out of idle CPU updates")

	t.current = "hysteresis retains previous tier while restoring nearby chunks"
	streamer.simulation_hysteresis = 12.0
	streamer.focus_position = Vector3(20.0, 0.0, 8.0)
	streamer.refresh()
	t.check(streamer.is_cell_simulation_active(far_cell),
		"nearby paused chunk activates first when focus approaches")
	t.check(streamer.is_cell_simulation_active(Vector3i.ZERO),
		"already-active neighbor remains active within hysteresis")
	t.eq(streamer.get_loaded_count(), initial_count,
		"moving within the existing loaded region does not change residency")
	if far_chunk != null:
		t.eq(far_chunk.transitions, [false, true],
			"activation callback resumes the same resident scene root")
		t.check(far_chunk.is_processing(), "reactivated root updates again")

	t.current = "opt-out restores simulation under the transition budget"
	streamer.simulation_radius = -1.0
	for i in initial_count + 1:
		streamer.refresh()
	t.eq(streamer.get_simulation_active_count(), streamer.get_loaded_count(),
		"disabling simulation LOD restores all resident chunks")
	streamer.unload_all()
	t.eq(streamer.get_simulation_active_count(), 0,
		"unload clears tier diagnostics and stale chunk state")
	t.check(not streamer.is_cell_simulation_active(far_cell),
		"unloaded coordinates never report simulation active")
	streamer.free()

	t.current = "new chunks select near and far simulation states before entering tree"
	var initial := WorldStreamer.new()
	initial.cell_size = 16.0
	initial.load_radius = 24.0
	initial.unload_radius = 32.0
	initial.focus_position = Vector3(8.0, 0.0, 8.0)
	initial.simulation_radius = 4.0
	initial.max_instantiations_per_frame = 64
	initial.set_chunk_generator(Callable(self, "_make_chunk"))
	initial.refresh()
	var new_far := initial.get_chunk(far_cell) as ProbeChunk
	t.check(new_far != null, "new far chunk remains visually resident")
	if new_far != null:
		t.eq(new_far.transitions, [false],
			"far chunk is paused during initial adoption without an extra frame")
		t.check(not new_far.is_processing(), "far script starts paused")
	t.check(initial.is_cell_simulation_active(Vector3i.ZERO),
		"new player chunk begins active")
	t.eq(initial.get_loaded_count() - initial.get_simulation_active_count(),
		initial.get_loaded_count() - 1, "initial tiering does not inflate loaded work")
	initial.free()
