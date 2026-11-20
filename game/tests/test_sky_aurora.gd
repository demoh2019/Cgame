extends RefCounted
## Night aurora visibility rules.
const SkyAurora = preload("res://scripts/client/sky_aurora.gd")


func run(t) -> void:
	t.current = "aurora on clear High/Ultra nights only"
	t.near(SkyAurora.strength(3, 0.0, 0.0), 1.0, 0.0001, "clear Ultra night: full aurora")
	t.check(SkyAurora.strength(2, 0.0, 0.0) > 0.99, "High also shows it")
	t.eq(SkyAurora.strength(1, 0.0, 0.0), 0.0, "Balanced pays nothing")
	t.eq(SkyAurora.strength(3, 1.0, 0.0), 0.0, "never in daylight")
	t.eq(SkyAurora.strength(3, 0.0, 0.6), 0.0, "storm clouds hide it")
