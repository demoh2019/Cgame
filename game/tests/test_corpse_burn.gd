extends RefCounted
## Corpse burn-away timing.
const CorpseBurn = preload("res://scripts/client/corpse_burn.gd")


func run(t) -> void:
	t.current = "corpse burn-away timing"
	t.eq(CorpseBurn.progress(0.0, 5.0, 1.5), 0.0, "a fresh ragdoll is untouched")
	t.check(CorpseBurn.progress(5.5, 5.0, 1.5) > 0.0, "burning starts as it sinks")
	t.eq(CorpseBurn.progress(6.5, 5.0, 1.5), 1.0, "fully burnt when it is removed")
