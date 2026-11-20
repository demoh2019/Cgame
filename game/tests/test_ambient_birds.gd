extends RefCounted
## Ambient bird flock: visibility rules and boids steering.
const Birds = preload("res://scripts/client/ambient_birds.gd")


func run(t) -> void:
	test_plumage(t)
	t.current = "flock only in daylight, calm weather, Balanced and up"
	t.eq(Birds.flock_size(0, 1.0, 0.0), 0, "Performance pays nothing")
	t.eq(Birds.flock_size(1, 1.0, 0.0), 8, "Balanced gets a small flock")
	t.eq(Birds.flock_size(3, 1.0, 0.0), Birds.MAX_BIRDS, "Ultra full flock")
	t.eq(Birds.flock_size(3, 0.1, 0.0), 0, "birds roost at night")
	t.eq(Birds.flock_size(3, 1.0, 0.8), 0, "birds hide from storms")

	t.current = "boids separation pushes overlapping birds apart"
	var pos := PackedVector3Array([Vector3.ZERO, Vector3(0.5, 0, 0)])
	var vel := PackedVector3Array([Vector3.FORWARD, Vector3.FORWARD])
	var f := Birds.steer(0, pos, vel, 2, Vector3.ZERO)
	t.check(f.x < 0.0, "bird 0 is pushed away from its neighbour")
	var far := PackedVector3Array([Vector3(30, 0, 0)])
	var g := Birds.steer(0, far, PackedVector3Array([Vector3.FORWARD]), 1, Vector3.ZERO)
	t.check(g.x < 0.0, "a stray bird is pulled back towards home")


func test_plumage(t) -> void:
	t.current = "gulls on the coast, crows inland"
	t.check(Birds.plumage("beach").r > 0.7, "coastal birds are light gulls")
	t.check(Birds.plumage("forest").r < 0.2, "inland birds are dark corvids")
