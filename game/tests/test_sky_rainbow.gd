extends RefCounted
## Post-rain rainbow visibility rules.
const SkyRainbow = preload("res://scripts/client/sky_rainbow.gd")


func run(t) -> void:
	t.current = "rainbow only while a storm clears in daylight with a low sun"
	t.check(SkyRainbow.strength(0.3, false, 1.0, 0.3) > 0.9, "clearing storm, low sun: full bow")
	t.eq(SkyRainbow.strength(0.3, true, 1.0, 0.3), 0.0, "never while the storm is building")
	t.eq(SkyRainbow.strength(0.0, false, 1.0, 0.3), 0.0, "clear sky has no rain to refract")
	t.eq(SkyRainbow.strength(1.0, false, 1.0, 0.3), 0.0, "full overcast hides the sun")
	t.eq(SkyRainbow.strength(0.3, false, 0.1, 0.3), 0.0, "no rainbow at night")
	t.eq(SkyRainbow.strength(0.3, false, 1.0, 0.9), 0.0, "high noon sun puts the bow below the horizon")
	t.eq(SkyRainbow.strength(0.3, false, 1.0, -0.1), 0.0, "sun below horizon")
