extends RefCounted
## Benchmarks BoxContainer layout cache under mixed visibility, caps and reversals.


func run(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var horizontal := HBoxContainer.new()
	var vertical := VBoxContainer.new()
	horizontal.add_theme_constant_override("separation", 1)
	vertical.add_theme_constant_override("separation", 1)
	tree.root.add_child(horizontal)
	tree.root.add_child(vertical)

	var controls := mini(64 * scale, 2048)
	var expected_visible := 0
	for i in range(controls):
		var h := Control.new()
		var v := Control.new()
		h.custom_minimum_size = Vector2(3 + i % 7, 4 + i % 5)
		v.custom_minimum_size = Vector2(4 + i % 5, 3 + i % 7)
		if i % 3 == 0:
			h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.size_flags_vertical = Control.SIZE_EXPAND_FILL
			h.set_stretch_ratio(1.0 + float(i % 5))
			v.set_stretch_ratio(1.0 + float(i % 5))
		if i % 9 == 0:
			h.set_custom_maximum_size(Vector2(20, -1))
			v.set_custom_maximum_size(Vector2(-1, 20))
		if i % 11 == 0:
			h.hide()
			v.hide()
		else:
			expected_visible += 1
		horizontal.add_child(h)
		vertical.add_child(v)

	var latencies: Array[float] = []
	var peak_process_ms := 0.0
	for frame in range(frames):
		horizontal.set_reverse_sort(frame % 2 != 0)
		vertical.set_reverse_sort(frame % 2 == 0)
		horizontal.set_size(Vector2(1200 + frame % 7, 360))
		vertical.set_size(Vector2(360, 1200 + frame % 7))
		var started := Time.get_ticks_usec()
		await tree.process_frame
		latencies.append(float(Time.get_ticks_usec() - started) / 1000.0)
		peak_process_ms = maxf(peak_process_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)

	var min_h := horizontal.get_minimum_size()
	var min_v := vertical.get_minimum_size()
	var valid := horizontal.get_child_count() == controls and vertical.get_child_count() == controls
	valid = valid and expected_visible > 0 and min_h.x > 0 and min_v.y > 0
	valid = valid and is_finite(min_h.x) and is_finite(min_v.y)
	horizontal.queue_free()
	vertical.queue_free()
	await tree.process_frame
	if not valid:
		return {"error": "BoxContainer reflow produced invalid measurements"}

	latencies.sort()
	var p95_index := maxi(0, int(ceil(float(latencies.size()) * 0.95)) - 1)
	return {
		"controls_per_container": controls,
		"visible_per_container": expected_visible,
		"reflows": frames * 2,
		"p95_reflow_ms": latencies[p95_index],
		"peak_reflow_ms": latencies.back(),
		"peak_process_ms": peak_process_ms,
	}
