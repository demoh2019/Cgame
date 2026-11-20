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
	print("AdaptiveResolution3D: 6 checks passed")
	quit(0)
