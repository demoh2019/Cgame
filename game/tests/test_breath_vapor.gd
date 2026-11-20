extends RefCounted
## Breath vapor: when air is cold and how often the character exhales.
const Breath = preload("res://scripts/client/breath_vapor.gd")


func run(t) -> void:
	t.current = "visible breath only in cold air"
	t.eq(Breath.coldness(10.0, 1.0, "plains", 0.0), 0.0, "warm lowland day: no breath")
	t.eq(Breath.coldness(95.0, 1.0, "plains", 0.0), 1.0, "high peaks are cold")
	t.check(Breath.coldness(10.0, 0.0, "mountain", 0.0) > 0.9, "mountain nights are cold")
	t.eq(Breath.coldness(10.0, 0.0, "plains", 0.0), 0.0, "plains nights stay mild")
	t.eq(Breath.coldness(10.0, 1.0, "plains", 1.0), 1.0, "snowfall means cold")
	t.check(Breath.exhale_interval(6.0) < Breath.exhale_interval(0.0), "running pants faster")
