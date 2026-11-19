extends RefCounted
## Reflow pressure for horizontal and vertical wrapped Control layouts.


func run(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var hflow := HFlowContainer.new()
	var vflow := VFlowContainer.new()
	hflow.add_theme_constant_override("h_separation", 1)
	hflow.add_theme_constant_override("v_separation", 1)
	vflow.add_theme_constant_override("h_separation", 1)
	vflow.add_theme_constant_override("v_separation", 1)
	tree.root.add_child(hflow)
	tree.root.add_child(vflow)

	var controls := mini(80 * scale, 1600)
	for i in range(controls):
		var h := Control.new()
		var v := Control.new()
		h.custom_minimum_size = Vector2(13 + (i % 7) * 3, 8 + i % 5)
		v.custom_minimum_size = Vector2(8 + i % 5, 13 + (i % 7) * 3)
		if i % 3 == 0:
			h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.size_flags_vertical = Control.SIZE_EXPAND_FILL
			h.set_stretch_ratio(1.0 + float(i % 4))
			v.set_stretch_ratio(1.0 + float(i % 4))
		if i % 9 == 0:
			h.set_custom_maximum_size(Vector2(70, -1))
			v.set_custom_maximum_size(Vector2(-1, 70))
		if i % 11 == 0:
			h.hide()
			v.hide()
		hflow.add_child(h)
		vflow.add_child(v)

	var latencies: Array[float] = []
	var peak_process_ms := 0.0
	var total_lines := 0
	for frame in range(frames):
		hflow.set_size(Vector2(220 + (frame % 9) * 48, 1800))
		vflow.set_size(Vector2(1800, 220 + (frame % 9) * 48))
		hflow.set_reverse_fill(frame % 2 == 0)
		vflow.set_reverse_fill(frame % 2 != 0)
		var started := Time.get_ticks_usec()
		await tree.process_frame
		latencies.append(float(Time.get_ticks_usec() - started) / 1000.0)
		peak_process_ms = maxf(peak_process_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		total_lines += hflow.get_line_count() + vflow.get_line_count()

	var valid := hflow.get_child_count() == controls and vflow.get_child_count() == controls
	valid = valid and total_lines >= frames * 2
	hflow.queue_free()
	vflow.queue_free()
	await tree.process_frame
	if not valid:
		return {"error": "FlowContainer reflow produced invalid line counts"}
	latencies.sort()
	var p95_index := maxi(0, int(ceil(float(latencies.size()) * 0.95)) - 1)
	return {
		"controls_per_container": controls,
		"reflows": frames * 2,
		"line_count_checksum": total_lines,
		"p95_reflow_ms": latencies[p95_index],
		"peak_reflow_ms": latencies.back(),
		"peak_process_ms": peak_process_ms,
	}
