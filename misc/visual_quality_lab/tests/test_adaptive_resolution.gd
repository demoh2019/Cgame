extends SceneTree

const Adaptive = preload("res://addons/visual_quality/adaptive_resolution.gd")


func _initialize() -> void:
	var scale: float
	# A sustained performance drop reduces render pixels, never UI resolution.
	scale = Adaptive.calculate_next_scale(1.0, 45.0, 60.0, 0.67, 1.0, 0.05, 0.025, 0.90, 0.985)
	assert(is_equal_approx(scale, 0.95), "Should scale down after an FPS drop")
	# Stable FPS inside the hysteresis band must not make the image pulse.
	scale = Adaptive.calculate_next_scale(0.80, 56.0, 60.0, 0.67, 1.0, 0.05, 0.025, 0.90, 0.985)
	assert(is_equal_approx(scale, 0.80), "Must keep resolution inside hysteresis band")
	# Recovery near the cap restores image quality without exceeding configured maximum.
	scale = Adaptive.calculate_next_scale(0.80, 60.0, 60.0, 0.67, 1.0, 0.05, 0.025, 0.90, 0.985)
	assert(is_equal_approx(scale, 0.825), "Should improve image quality with spare headroom")
	scale = Adaptive.calculate_next_scale(0.68, 20.0, 60.0, 0.67, 1.0, 0.05, 0.025, 0.90, 0.985)
	assert(is_equal_approx(scale, 0.67), "Must never exceed minimum scale")
	scale = Adaptive.calculate_next_scale(1.0, 200.0, 60.0, 0.67, 1.0, 0.05, 0.025, 0.90, 0.985)
	assert(is_equal_approx(scale, 1.0), "Must never exceed maximum scale")
	scale = Adaptive.calculate_next_scale(0.80, 0.0, 60.0, 0.67, 1.0, 0.05, 0.025, 0.90, 0.985)
	assert(is_equal_approx(scale, 0.80), "Invalid samples should not change scale")
	# Conservative CPU guard: do not sacrifice pixels for game-logic bottlenecks.
	assert(Adaptive.is_cpu_bound(0.018, 60.0, 0.90), "18ms CPU frame is CPU-limited")
	assert(not Adaptive.is_cpu_bound(0.003, 60.0, 0.90), "3ms CPU frame can be GPU-limited")
	assert(not Adaptive.is_cpu_bound(0.0, 60.0, 0.90), "Unmeasured CPU time must not block scaling")
	# Hardware GPU timer, when supported, overrides V-Sync-capped FPS.
	assert(is_equal_approx(Adaptive.calculate_next_scale_from_gpu(1.0, 22.0, 60.0, 0.67, 1.0, 0.05, 0.025, 1.03, 0.85), 0.95))
	assert(is_equal_approx(Adaptive.calculate_next_scale_from_gpu(0.8, 10.0, 60.0, 0.67, 1.0, 0.05, 0.025, 1.03, 0.85), 0.825))
	assert(is_equal_approx(Adaptive.calculate_next_scale_from_gpu(0.8, 16.0, 60.0, 0.67, 1.0, 0.05, 0.025, 1.03, 0.85), 0.8))
	assert(is_equal_approx(Adaptive.calculate_next_scale_from_gpu(0.8, 0.0, 60.0, 0.67, 1.0, 0.05, 0.025, 1.03, 0.85), 0.8))
	print("AdaptiveResolution3D: 13 checks passed")
	quit(0)
