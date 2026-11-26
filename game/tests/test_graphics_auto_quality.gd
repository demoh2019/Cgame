extends RefCounted
## The FPS budget controller must be deterministic, use hysteresis and ignore single stalls.

const GraphicsAutoQuality = preload("res://scripts/client/graphics_auto_quality.gd")
const GraphicsVramBudget = preload("res://scripts/client/graphics_vram_budget.gd")
const GraphicsFramePacing = preload("res://scripts/client/graphics_frame_pacing.gd")


func run(t) -> void:
	var quality := GraphicsAutoQuality.new()
	t.current = "adaptive graphics presets"
	t.eq(quality.mode, "auto", "automatic quality is the default")
	t.eq(quality.level, 1, "start with balanced vegetation")
	t.eq(quality.preset()["grass_end"], 60.0, "default grass view distance")
	t.check(not quality.set_mode("ultra-unavailable"), "unknown preset is rejected")
	t.check(quality.set_mode("quality"), "manual quality preset can be selected")
	t.eq(quality.level, 2, "quality increases the detail budget")
	t.check(quality.set_mode("performance"), "manual performance preset can be selected")
	t.eq(quality.level, 0, "performance reduces the detail budget")
	for frame in 240:
		if frame == 0:
			t.check(not quality.sample_frame(1.0 / 15.0), "manual mode does not auto-switch")
		else:
			quality.sample_frame(1.0 / 15.0)
	t.eq(quality.level, 0, "manual setting survives low FPS")
	t.check(quality.set_mode("auto"), "auto mode can be selected")
	t.current = "adaptive hysteresis"
	var changed := false
	for frame in 150:
		changed = quality.sample_frame(1.0 / 30.0) or changed
	t.check(changed, "sustained 30 FPS reduces detail")
	t.eq(quality.level, 0, "low FPS selects performance")
	t.check(not quality.sample_frame(1.0), "single long stall is ignored")
	t.eq(quality.level, 0, "one stall does not change quality")
	changed = false
	for frame in 1320:
		changed = quality.sample_frame(1.0 / 60.0) or changed
	t.check(changed, "sustained good FPS eventually recovers detail")
	t.check(quality.level >= 1, "recovered settings are at least balanced")

	t.current = "GPU-bound workload, not CPU script stalls, drives graphics fidelity"
	var gpu_bound := GraphicsAutoQuality.new()
	t.check(not GraphicsAutoQuality.at_resolution_limit(true, false, false, 0.04, 34.0),
		"intermediate resolution always recovers pixel budget before changing objects")
	t.check(GraphicsAutoQuality.at_resolution_limit(true, true, false, 1.0 / 120.0, 34.0),
		"slow GPU at minimum resolution can lower scenery quality")
	t.check(not GraphicsAutoQuality.at_resolution_limit(true, true, false, 0.04, 7.0),
		"slow CPU with fast GPU never forces a graphics downgrade")
	t.check(not GraphicsAutoQuality.at_resolution_limit(true, false, true, 0.04, 7.0),
		"CPU-heavy scene does not add more scenery despite fast GPU")
	t.check(GraphicsAutoQuality.at_resolution_limit(true, false, true, 1.0 / 60.0, 7.0),
		"when CPU and GPU are both fast, extra visual detail may be restored")
	t.check(not GraphicsAutoQuality.at_resolution_limit(true, false, true, 1.0 / 120.0, 33.0),
		"GPU-heavy frame does not increase quality due to fast script timing")
	t.check(GraphicsAutoQuality.at_resolution_limit(false, false, false, 0.04),
		"Compatibility continues the original FPS-driven fallback")
	var changed_gpu := false
	for i in 510:
		# GPU 35 ms at a 120 Hz CPU rate: would look fast if using delta.
		changed_gpu = gpu_bound.sample_frame(1.0 / 120.0, 35.0) or changed_gpu
	t.check(changed_gpu and gpu_bound.level == 0,
		"sustained GPU load reduces world detail despite fast CPU updates")
	gpu_bound = GraphicsAutoQuality.new()
	changed_gpu = false
	for i in 180:
		# 25 FPS CPU-bound simulation and 7 ms GPU; preserve Balanced.
		changed_gpu = gpu_bound.sample_frame(1.0 / 25.0, 7.0) or changed_gpu
	t.check(not changed_gpu and gpu_bound.level == 1,
		"slow gameplay threads cannot steal visually affordable GPU detail")
	gpu_bound = GraphicsAutoQuality.new()
	changed_gpu = false
	for i in 560:
		changed_gpu = gpu_bound.sample_frame(1.0 / 60.0, 7.0) or changed_gpu
	t.check(changed_gpu and gpu_bound.level == 2,
		"healthy CPU and GPU budgets can restore higher world fidelity")
	gpu_bound = GraphicsAutoQuality.new()
	for dt in [NAN, INF, -1.0, 0.0, 0.3]:
		t.check(not gpu_bound.sample_frame(dt, 38.0),
			"invalid/paused frame times cannot drive quality changes")
	var after_bad := gpu_bound.level
	for i in 100:
		gpu_bound.sample_frame(1.0 / 30.0, NAN)
	t.check(gpu_bound.level <= after_bad,
		"unavailable GPU timers safely revert to the original frame-delta policy")
	t.check(GraphicsAutoQuality.at_resolution_limit(true, true, false, 1.0 / 30.0, INF),
		"missing GPU duration still permits legacy resolution-limit downgrade")
	t.check(not GraphicsAutoQuality.at_resolution_limit(true, false, true, 1.0 / 30.0, INF),
		"invalid GPU readings do not allow a premature quality upgrade")
	t.current = "VRAM budget ignores suspended frames and unavailable telemetry"
	var vram := GraphicsVramBudget.new()
	var high_usage: float = GraphicsVramBudget.budget_bytes(1) * 0.96
	t.check(GraphicsVramBudget.valid_sample(high_usage, 1.0 / 60.0),
		"finite positive memory during normal rendering is measurable")
	for invalid_memory in [NAN, INF, -1.0, 0.0]:
		t.check(not GraphicsVramBudget.valid_sample(invalid_memory, 1.0 / 60.0),
			"unavailable VRAM readings are not interpreted as sustained pressure")
		t.check(not vram.sample(invalid_memory, 1, 1.0 / 60.0),
			"invalid VRAM never forces a graphics downgrade")
	for bad_delta in [NAN, INF, -1.0, 0.0, 0.3, 1.0]:
		t.check(not GraphicsVramBudget.valid_sample(high_usage, bad_delta),
			"paused or invalid frame time never counts toward the VRAM timer")
		t.check(not vram.sample(high_usage, 1, bad_delta),
			"VRAM budget ignores a loading stall")
	for i in 80:
		t.check(not vram.sample(high_usage, 1, 0.016),
			"early high-memory samples cannot cause premature quality switching")
	t.check(not vram.sample(high_usage, 1, 0.9),
		"one asset-loading hitch cannot complete the memory pressure timer")
	var sustained := false
	for i in 80:
		sustained = vram.sample(high_usage, 1, 0.016) or sustained
	t.check(sustained, "sustained real memory pressure still lowers detail")

	var source: String = FileAccess.get_file_as_string(
		"res://scripts/client/online_main.gd")
	t.check(source.contains("GraphicsAutoQuality.at_resolution_limit("),
		"online client uses GPU-aware outer quality boundary")
	t.check(source.contains("_auto_quality.sample_frame(delta, gpu_ms)"),
		"GPU timing is forwarded to the actual quality controller")
	t.check(source.contains("_adaptive_resolution.sample_frame(delta, gpu_ms)"),
		"pixel budget uses the same GPU timer as world detail quality")
	t.check(source.contains("GraphicsVramBudget.valid_sample(vram_used, delta)"),
		"live client filters VRAM samples before the native or script pressure policy")

	t.current = "VRAM recovery and display timing guards"
	var next_budget: float = GraphicsVramBudget.budget_bytes(2)
	t.check(not GraphicsVramBudget.allows_auto_upgrade(next_budget * 0.9, 1),
		"known memory pressure prevents a speculative FPS-based upgrade")
	t.check(GraphicsVramBudget.allows_auto_upgrade(next_budget * 0.5, 1),
		"healthy residency permits an upgrade")
	t.check(GraphicsVramBudget.allows_auto_upgrade(0.0, 1),
		"unavailable residency preserves compatibility FPS adaptation")
	t.check(not GraphicsVramBudget.upgrade_allowed(NAN, 1),
		"strict upgrade API requires a valid reading")
	vram.sample(high_usage, 1, 0.125)
	vram.reset()
	for i in 15:
		t.check(not vram.sample(high_usage, 1, 0.125),
			"new tier receives a fresh pressure window")
	t.check(vram.sample(high_usage, 1, 0.125), "new tier lowers only after 2 valid seconds")
	t.check(source.contains("GraphicsVramBudget.allows_auto_upgrade(vram_used, previous_level)"),
		"live quality upgrade honors memory availability")
	for hz in [NAN, INF, -1.0, 1.0e20]:
		t.eq(GraphicsFramePacing.settings(1, hz)["max_fps"], 60,
			"invalid monitor frequency falls back to a finite cap")
	t.eq(GraphicsFramePacing.settings(0, 144.0)["max_fps"], 72,
		"normal high-refresh performance profile remains half rate")
	t.eq(GraphicsFramePacing.settings(1, 480.0)["max_fps"], 480,
		"valid modern high-refresh displays are supported")
