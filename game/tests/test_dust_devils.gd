extends RefCounted
## Dust devils: conditions and fade envelope.
const DustDevils = preload("res://scripts/client/dust_devils.gd")


func run(t) -> void:
	t.current = "dust devils on dry windy plains"
	t.check(DustDevils.allowed(2, "plains", Vector2(1, 0), 0.0, 1.0), "windy dry plains day")
	t.check(not DustDevils.allowed(2, "swamp", Vector2(1, 0), 0.0, 1.0), "not in swamps")
	t.check(not DustDevils.allowed(2, "plains", Vector2(1, 0), 0.5, 1.0), "not in rain")
	t.check(not DustDevils.allowed(0, "plains", Vector2(1, 0), 0.0, 1.0), "Performance pays nothing")
	t.eq(DustDevils.strength(0.0), 0.0, "fades in")
	t.near(DustDevils.strength(12.0), 1.0, 0.001, "full mid-life")
	t.eq(DustDevils.strength(DustDevils.LIFE), 0.0, "fades out")
