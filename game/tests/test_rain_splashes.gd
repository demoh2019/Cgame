extends RefCounted
## Rain splash density.
const RainSplashes = preload("res://scripts/client/rain_splashes.gd")


func run(t) -> void:
	t.current = "ground splashes follow rain intensity"
	t.eq(RainSplashes.density(0.1, false), 0.0, "drizzle barely splashes")
	t.eq(RainSplashes.density(1.0, false), 1.0, "downpour boils the ground")
	t.eq(RainSplashes.density(1.0, true), 0.0, "nothing under cover")
	t.eq(RainSplashes.AMOUNTS[0], 0, "Performance draws none")
