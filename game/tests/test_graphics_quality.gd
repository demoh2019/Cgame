extends RefCounted
## Graphics presets stay bounded and keep expensive effects off on low-end hardware.

const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")


func run(t) -> void:
	t.current = "graphics preset bounds"
	t.eq(GraphicsQuality.profile(-1), GraphicsQuality.profile(0), "below range clamps to Performance")
	t.eq(GraphicsQuality.profile(99), GraphicsQuality.profile(3), "above range clamps to Ultra")
	t.check(not GraphicsQuality.profile(0)["shadows"], "Performance omits shadow maps")
	t.check(GraphicsQuality.profile(0)["blur_quality"] == 0, "Performance uses one screen sample")
	t.check(GraphicsQuality.profile(1)["blur_quality"] == 1, "Balanced uses five screen samples")
	t.check(GraphicsQuality.profile(2)["blur_quality"] == 2, "High retains the nine-sample diorama")
	t.check(GraphicsQuality.profile(3)["shadow_distance"] > GraphicsQuality.profile(1)["shadow_distance"], "Ultra draws distant shadows")
	t.check(GraphicsQuality.profile(3)["msaa"] != GraphicsQuality.profile(1)["msaa"], "Ultra enables MSAA")
	GraphicsQuality.set_level(99, false)
	t.eq(GraphicsQuality.level(), 3, "setting level is clamped")
	t.eq(GraphicsQuality.get_name(), "Ultra", "level has a display name")
	GraphicsQuality.set_level(1, false)
