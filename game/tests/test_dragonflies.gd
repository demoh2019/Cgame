extends RefCounted
## Dragonflies budget.
const Dragonflies = preload("res://scripts/client/dragonflies.gd")


func run(t) -> void:
	t.current = "dragonflies on warm calm days"
	t.eq(Dragonflies.count(3, 1.0, 0.0), Dragonflies.MAX_FLIES, "Ultra day")
	t.eq(Dragonflies.count(1, 1.0, 0.0), 0, "Balanced pays nothing")
	t.eq(Dragonflies.count(3, 0.2, 0.0), 0, "not at night")
	t.eq(Dragonflies.count(3, 1.0, 0.5), 0, "not in storms")
