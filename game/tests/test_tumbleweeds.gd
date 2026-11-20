extends RefCounted
## Tumbleweeds: biome/wind/quality rules and upwind spawning.
const Tumbleweeds = preload("res://scripts/client/tumbleweeds.gd")


func run(t) -> void:
	t.current = "tumbleweeds roll on windy plains only"
	t.eq(Tumbleweeds.weed_count(3, "plains", Vector2(1, 0)), Tumbleweeds.MAX_WEEDS, "windy plains")
	t.eq(Tumbleweeds.weed_count(3, "forest", Vector2(1, 0)), 0, "never in forests")
	t.eq(Tumbleweeds.weed_count(3, "plains", Vector2.ZERO), 0, "calm air keeps them still")
	t.eq(Tumbleweeds.weed_count(0, "plains", Vector2(1, 0)), 0, "Performance pays nothing")
	var p := Tumbleweeds.spawn_point(Vector3.ZERO, Vector2(1, 0), 0.0)
	t.check(p.x < -20.0, "weeds start upwind of the player")
