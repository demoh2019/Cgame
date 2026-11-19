extends RefCounted
## Deterministic dense and sparse GridContainer reflow pressure.
## The million-column check catches allocation storms in sparse grids.

const COLUMN_COUNTS = [8, 16, 32, 64]


func run(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var grid := GridContainer.new()
	grid.columns = 16
	grid.custom_minimum_size = Vector2.ZERO
	grid.size = Vector2(1280, 720)
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	tree.root.add_child(grid)

	var controls := 100 * scale
	for i in range(controls):
		var control := Control.new()
		control.custom_minimum_size = Vector2(8 + i % 9, 10 + i % 7)
		if (i % 3) == 0:
			control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if (i % 5) == 0:
			control.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(control)

	var samples: Array[float] = []
	var peak_process_ms := 0.0
	for frame in range(frames):
		grid.columns = COLUMN_COUNTS[frame % 4]
		var started := Time.get_ticks_usec()
		await tree.process_frame
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		peak_process_ms = maxf(peak_process_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)

	# This used to insert almost a million RBSet nodes every reflow.
	grid.columns = 1000000
	var sparse_started := Time.get_ticks_usec()
	await tree.process_frame
	var sparse_reflow_ms := float(Time.get_ticks_usec() - sparse_started) / 1000.0

	var correct_count := grid.get_child_count() == controls
	var min_size := grid.get_minimum_size()
	var sensible_size := min_size.x > 0 and min_size.y > 0 and is_finite(min_size.x) and is_finite(min_size.y)
	grid.queue_free()
	await tree.process_frame
	if not correct_count or not sensible_size:
		return {"error": "GridContainer lost children or returned invalid minimum size"}

	samples.sort()
	var p95_index := maxi(0, int(ceil(float(samples.size()) * 0.95)) - 1)
	return {
		"controls": controls,
		"reflows": frames + 1,
		"p95_reflow_ms": samples[p95_index],
		"peak_reflow_ms": samples.back(),
		"sparse_reflow_ms": sparse_reflow_ms,
		"peak_process_ms": peak_process_ms,
	}
