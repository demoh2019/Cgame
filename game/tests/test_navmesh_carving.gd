extends RefCounted
## Navmesh obstacle carving (tile cache) and compact destruction replication.

const NavmeshCarving = preload("res://scripts/shared/navmesh_carving.gd")
const DestructionReplication = preload("res://scripts/shared/destruction_replication.gd")


func _path_len(path: PackedVector2Array) -> float:
	var s := 0.0
	for i in path.size() - 1:
		s += path[i].distance_to(path[i + 1])
	return s


func _wall() -> PackedVector2Array:
	return PackedVector2Array([Vector2(19.5, 0.0), Vector2(20.5, 0.0), Vector2(20.5, 30.0), Vector2(19.5, 30.0)])


func run(t) -> void:
	t.current = "carving blocks area"
	var nav := NavmeshCarving.new()
	nav.setup(Rect2(0, 0, 40, 40), 10.0, 0.5)
	t.check(nav.is_walkable(Vector2(5, 5)), "open ground walkable")
	nav.add_obstacle("pillar", {"center": Vector2(5, 5), "radius": 1.0, "segments": 12})
	nav.update(0)
	t.check(not nav.is_walkable(Vector2(5, 5)), "pillar centre blocked")
	t.check(not nav.is_walkable(Vector2(6.3, 5)), "agent radius margin blocked")
	t.check(nav.is_walkable(Vector2(1, 1)), "far corner still walkable")
	var area := 0.0
	var all_convex := true
	for p in nav.polygons_in_tile(Vector2i(0, 0)):
		area += NavmeshCarving._area(p)
		all_convex = all_convex and NavmeshCarving.is_convex(p)
	t.check(area > 91.5 and area < 94.0, "tile area minus the carved disc (%f)" % area)
	t.check(all_convex, "carved polygons stay convex")
	t.check(nav.polygons_in_tile(Vector2i(0, 0)).size() > 1, "hole forced decomposition")
	nav.on_destroyed("pillar")
	nav.update(0)
	t.check(nav.is_walkable(Vector2(5, 5)), "destroyed pillar is walkable again")
	t.eq(nav.polygons_in_tile(Vector2i(0, 0)).size(), 1, "tile back to a single polygon")

	t.current = "detour and reopening"
	var n2 := NavmeshCarving.new()
	n2.setup(Rect2(0, 0, 40, 40), 10.0, 0.5)
	var straight := n2.find_path(Vector2(5, 20), Vector2(35, 20))
	t.eq(straight.size(), 2, "open field path is a straight segment")
	n2.add_obstacle("barricade", _wall())
	n2.update(0)
	t.check(not n2.is_walkable(Vector2(20, 10)), "barricade blocks its footprint")
	var detour := n2.find_path(Vector2(5, 20), Vector2(35, 20))
	t.check(detour.size() >= 3, "path bends around the wall")
	t.check(_path_len(detour) > 35.0, "detour is longer than the straight line (%f)" % _path_len(detour))
	t.check(_path_len(detour) < 52.0, "detour is reasonably tight (%f)" % _path_len(detour))
	var clear := true
	for i in detour.size() - 1:
		for s in 11:
			var pt := detour[i].lerp(detour[i + 1], float(s) / 10.0)
			clear = clear and n2.is_walkable(pt)
	t.check(clear, "detour stays on walkable polygons")
	n2.consume_changed_tiles()
	n2.on_destroyed("barricade")
	n2.update(0)
	var reopened := n2.find_path(Vector2(5, 20), Vector2(35, 20))
	t.eq(reopened.size(), 2, "destroying the barricade reopens the straight route")
	t.near(_path_len(reopened), 30.0, 0.01, "straight length restored")
	t.check(n2.path_affected(detour, n2.consume_changed_tiles()), "AI repath notification covers old path")
	t.eq(n2.find_path(Vector2(-5, 20), Vector2(35, 20)).size(), 0, "outside the mesh gives no path")
	n2.add_obstacle("full", PackedVector2Array([Vector2(19.5, -1), Vector2(20.5, -1), Vector2(20.5, 41), Vector2(19.5, 41)]))
	n2.update(0)
	t.eq(n2.find_path(Vector2(5, 20), Vector2(35, 20)).size(), 0, "fully walled map is unreachable")

	t.current = "budget and locality"
	var n3 := NavmeshCarving.new()
	n3.setup(Rect2(0, 0, 40, 40), 10.0, 0.5)
	var v_far := n3.tile_version(Vector2i(3, 3))
	var v_hit := n3.tile_version(Vector2i(1, 1))
	n3.add_obstacle("w", _wall())
	var pending := n3.pending_tiles()
	t.check(pending >= 4 and pending < 16, "only tiles under the wall are queued (%d)" % pending)
	t.eq(n3.update(2), 2, "update obeys the per-call budget")
	t.eq(n3.pending_tiles(), pending - 2, "remaining tiles stay queued")
	t.eq(n3.consume_changed_tiles().size(), 2, "events list the rebuilt tiles")
	while n3.pending_tiles() > 0:
		n3.update(2)
	t.eq(n3.tile_version(Vector2i(3, 3)), v_far, "unaffected tile untouched")
	t.eq(n3.tile_version(Vector2i(0, 0)), 0, "neighbouring clear tile untouched")
	t.check(n3.tile_version(Vector2i(1, 1)) > v_hit, "affected tile rebuilt")
	t.eq(n3.update(2), 0, "nothing left to do")
	n3.add_obstacle("w", _wall())
	t.check(n3.pending_tiles() > 0, "re-adding an id requeues its tiles")

	t.current = "destruction replication"
	var server := DestructionReplication.new()
	server.setup(1000, 77)
	var client := DestructionReplication.new()
	client.setup(1000, 77)
	t.eq(server.delta_since(0).size(), 3, "no changes: header only")
	t.check(server.apply_damage(5, 10.0, Vector2(3, 4)), "damage changes bucket")
	t.check(server.apply_damage(400, 60.0, Vector2(9, 1)), "heavy damage fractures")
	t.check(server.apply_damage(999, 200.0, Vector2(1, 1)), "overkill destroys")
	var d := server.delta_since(0)
	t.check(d.size() < 64, "3 changed of 1000 objects fit in %d bytes" % d.size())
	t.check(server.full_state_size() == d.size(), "full state equals delta from zero")
	t.eq(client.apply_delta(d), DestructionReplication.Result.APPLIED, "delta applies")
	t.eq(client.version, server.version, "client version follows")
	for id in [5, 400, 999, 0, 500]:
		t.eq(client.health_bucket(id), server.health_bucket(id), "bucket mirrors %d" % id)
		t.eq(client.is_fractured(id), server.is_fractured(id), "fractured mirrors %d" % id)
		t.eq(client.fracture_seed(id), server.fracture_seed(id), "seed mirrors %d" % id)
		t.eq(client.broken_chunks(id), server.broken_chunks(id), "chunks mirror %d" % id)
	t.check(client.is_destroyed(999) and client.is_fractured(400), "states survive the wire")
	var fx := client.consume_fracture_events()
	t.eq(fx.size(), 2, "client sees two fracture events")
	t.eq(client.consume_destroyed(), [999] as Array[int], "client reports destroyed ids for navmesh")

	t.current = "determinism and versions"
	t.eq(DestructionReplication.make_fracture_seed(77, 400, Vector2(9, 1)), server.fracture_seed(400), "seed is a pure function")
	t.check(DestructionReplication.make_fracture_seed(77, 400, Vector2(9, 1)) != DestructionReplication.make_fracture_seed(77, 401, Vector2(9, 1)), "seed differs per object")
	t.eq(DestructionReplication.initial_chunk_mask(1234), DestructionReplication.initial_chunk_mask(1234), "chunk mask deterministic")
	var acked := server.version
	server.apply_damage(5, 90.0, Vector2(3, 4))
	var d2 := server.delta_since(acked)
	t.check(d2.size() < 16, "single follow-up change is tiny (%d)" % d2.size())
	t.eq(server.apply_damage(5, 0.0), false, "zero damage ignored")
	server.apply_damage(7, 5.0, Vector2.ZERO)
	var d3 := server.delta_since(acked)
	t.eq(client.apply_delta(d3), DestructionReplication.Result.APPLIED, "cumulative delta applies")
	t.eq(client.apply_delta(d3), DestructionReplication.Result.STALE, "duplicate delta ignored")
	t.eq(client.apply_delta(d2), DestructionReplication.Result.STALE, "older delta after newer ignored")
	t.eq(client.apply_delta(d), DestructionReplication.Result.STALE, "very old delta ignored")
	t.eq(client.health_bucket(7), server.health_bucket(7), "newer state kept after stale deltas")
	var c2 := DestructionReplication.new()
	c2.setup(1000, 77)
	t.eq(c2.apply_delta(d3), DestructionReplication.Result.GAP, "delta with unseen baseline rejected")
	t.eq(c2.version, 0, "rejected delta changes nothing")
	t.eq(c2.apply_delta(server.delta_since(0)), DestructionReplication.Result.APPLIED, "resync from baseline 0")
	t.eq(c2.apply_delta(PackedByteArray([0xFF])), DestructionReplication.Result.MALFORMED, "truncated packet rejected")
	var st := server.stats()
	t.check(int(st["deltas_sent"]) >= 4 and int(st["bytes_sent"]) > 0, "bandwidth stats counted")
