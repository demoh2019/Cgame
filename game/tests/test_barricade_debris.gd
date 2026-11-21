extends RefCounted
## Broken barricades spawn cached, LOD-limited Voronoi debris.

const BarricadeDebris = preload("res://scripts/client/barricade_debris.gd")


func run(t) -> void:
	t.current = "barricade debris"
	t.check(BarricadeDebris.pieces_for(5.0) > BarricadeDebris.pieces_for(60.0), "near walls break into more pieces")
	t.check(BarricadeDebris.pieces_for(1.0) <= BarricadeDebris.MAX_PIECES, "piece count is capped")
	var first: Array = BarricadeDebris.fragments(6)
	t.eq(first.size(), 6, "one fragment per Voronoi cell")
	t.check(BarricadeDebris.fragments(6) == first, "fracture patterns are cached")
	var root := Node3D.new()
	var bodies: Array = BarricadeDebris.spawn(root, Vector3(10, 0, 10), Vector3(14, 2, 10))
	t.check(bodies.size() >= 2, "debris bodies spawn near the viewer")
	t.eq(root.get_child_count(), bodies.size(), "bodies are parented to the scene")
	t.eq(BarricadeDebris.spawn(root, Vector3(10, 0, 10), Vector3(500, 0, 500)).size(), 0, "distant walls spawn no bodies")
	root.free()
