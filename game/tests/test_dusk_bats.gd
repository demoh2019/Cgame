extends RefCounted
## Dusk bats: time, weather and quality rules.
const DuskBats = preload("res://scripts/client/dusk_bats.gd")


func run(t) -> void:
	t.current = "bats only at dusk/night, calm weather, Balanced and up"
	t.eq(DuskBats.bat_count(3, 1.0, 0.0), 0, "no bats at noon")
	t.eq(DuskBats.bat_count(3, 0.3, 0.0), DuskBats.MAX_BATS, "dusk on Ultra: full colony")
	t.eq(DuskBats.bat_count(1, 0.3, 0.0), 6, "Balanced: a few bats")
	t.eq(DuskBats.bat_count(0, 0.3, 0.0), 0, "Performance pays nothing")
	t.eq(DuskBats.bat_count(3, 0.3, 0.8), 0, "storms ground the bats")
