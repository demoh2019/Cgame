extends RefCounted
## PCG world dressing and PCG-placed loot/encounters: graph soundness, determinism, cell seamlessness, safe zones, caps and
## the graceful path on engines without the pcg_graph module.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const PcgGraphs = preload("res://scripts/shared/pcg_graphs.gd")
const PcgSpawns = preload("res://scripts/server/pcg_spawns.gd")
const PcgWorldDressing = preload("res://scripts/client/pcg_world_dressing.gd")

const SCAN_RADIUS := 7 # Chunks around the hub scanned for caches and encounters.


static func _bounds(x: float, z: float, w: float, h: float) -> AABB:
	return AABB(Vector3(x, -500.0, z), Vector3(w, 1500.0, h))


## Runs a graph over bounds; returns {"keys": sorted per-point strings, "count": n}.
static func _run(world, graph, bounds: AABB, seed_value: int, user_data: Dictionary = {}, exclusions: Array = [], overrides: Dictionary = {}) -> Dictionary:
	var executor = ClassDB.instantiate("PCGGraphExecutor")
	var context = ClassDB.instantiate("PCGContext")
	context.set_seed(seed_value)
	context.set_bounds(bounds)
	context.set_overrides(overrides)
	context.set_height_sampler(Callable(world, "height_at"))
	context.set_biome_sampler(Callable(world, "biome_at"))
	context.set_water_sampler(Callable(world, "is_water"))
	context.set_exclusions(exclusions)
	context.set_user_data(user_data)
	var result: Dictionary = executor.execute(graph, context)
	var points = result.get("output", null)
	var keys: PackedStringArray = []
	if points != null:
		for i in points.get_point_count():
			var p: Vector3 = points.get_position(i)
			keys.append("%.3f,%.3f|%d" % [p.x, p.z, int(points.get_attribute_value("asset", i, -1.0))])
	keys.sort()
	return {"keys": keys, "count": keys.size(), "points": points}


## First land cell near (x, z) with a non-empty clutter result, so the seam test has something to compare.
static func _land_origin(world) -> Vector2:
	for step in 40:
		var p := Vector2(300.0 + 64.0 * step, 260.0)
		if not world.is_water(p.x, p.y) and not world.is_water(p.x + 100.0, p.y + 30.0):
			return Vector2(floorf(p.x / 64.0) * 64.0, floorf(p.y / 64.0) * 64.0)
	return Vector2(320.0, 256.0)


func _chunks(world, radius: int) -> Array:
	var out: Array = []
	for cx in range(-radius, radius + 1):
		for cz in range(-radius, radius + 1):
			out.append(Vector2i(cx, cz))
	return out


func run(t) -> void:
	_test_missing_engine(t)
	if not PcgGraphs.available():
		t.current = "pcg unavailable"
		t.check(true, "engine has no pcg_graph module: graph checks skipped")
		return
	_test_graphs(t)
	var world := WorldGen.new(1337)
	_test_determinism_and_seams(t, world)
	_test_dressing_data(t, world)
	_test_spawns(t)


func _test_missing_engine(t) -> void:
	t.current = "no engine module"
	PcgGraphs.simulate_missing = true
	t.check(not PcgGraphs.available(), "simulated missing classes are reported")
	for name in PcgGraphs.all_builders():
		t.check(PcgGraphs.all_builders()[name].call() == null, "%s builder returns null" % name)
	t.check(PcgWorldDressing.budget(3).is_empty(), "dressing budget is empty without the module")
	var world := WorldGen.new(77)
	var classic := WorldGen.new(77)
	t.check(not PcgSpawns.attach(world), "attach is a no-op")
	t.check(world.spawn_extender == null, "no extender hooked")
	var cell := Vector2i(6, 4)
	var a: Dictionary = world.chunk(cell)
	var b: Dictionary = classic.chunk(cell)
	t.eq(a["crates"].size(), b["crates"].size(), "chunk crates stay classic")
	t.eq(a["spawns"].size(), b["spawns"].size(), "chunk spawns stay classic")
	var extender = PcgSpawns.new(world)
	t.check(not extender.active(), "extender inactive")
	var probe := {"crates": [], "spawns": [], "structures": [], "zone": 1, "ruin": false}
	extender.extend(cell, probe)
	t.eq(probe["crates"].size() + probe["spawns"].size(), 0, "extend adds nothing")
	PcgGraphs.simulate_missing = false


func _test_graphs(t) -> void:
	t.current = "pcg graphs"
	var names := PcgGraphs.all_builders()
	for name in names:
		var graph = names[name].call()
		t.check(graph != null, "%s builds" % name)
		if graph == null:
			continue
		t.eq(PcgGraphs.problems(graph).size(), 0, "%s validates" % name)
		t.check(not graph.has_cycle(), "%s has no cycle" % name)
		t.eq(graph.compute_order().size(), graph.get_node_count(), "%s orders every node" % name)
		t.check(graph.get_parameters().size() > 0, "%s exposes parameters" % name)
	var loot = PcgGraphs.loot_caches()
	loot.connect_nodes(loot.resolve_output_node_id(), 1, 0) # Logs an engine error: the cycle is refused.
	t.check(not loot.is_connected_to(loot.resolve_output_node_id(), 1, 0) and not loot.has_cycle(), "a back edge is refused (cycle)")
	t.check(PcgWorldDressing.budget(0).is_empty(), "Performance quality draws nothing")
	t.check(int(PcgWorldDressing.budget(3)["radius"]) > int(PcgWorldDressing.budget(1)["radius"]), "radius grows with quality")
	t.check(float(PcgWorldDressing.budget(3)["range"]) > float(PcgWorldDressing.budget(1)["range"]), "visibility range grows with quality")


func _test_determinism_and_seams(t, world) -> void:
	t.current = "pcg determinism"
	var origin := _land_origin(world)
	var clutter = PcgGraphs.biome_clutter()
	var cell := _bounds(origin.x, origin.y, 64.0, 64.0)
	var first := _run(world, clutter, cell, 1337)
	var second := _run(world, PcgGraphs.biome_clutter(), cell, 1337)
	t.check(first["count"] > 5, "clutter places something on land (%d)" % first["count"])
	t.eq(first["keys"], second["keys"], "same seed, same clutter")
	var other := _run(world, clutter, cell, 4242)
	t.check(other["keys"] != first["keys"], "another seed changes the clutter")
	var roadside = PcgGraphs.roadside_dressing()
	var roads := PcgWorldDressing.build_user_data(world)
	var wide := _bounds(-3200.0, -3200.0, 6400.0, 6400.0)
	var road_a := _run(world, roadside, wide, 1337, roads, PcgWorldDressing.build_exclusions(world))
	var road_b := _run(world, roadside, wide, 1337, roads, PcgWorldDressing.build_exclusions(world))
	t.check(road_a["count"] > 0, "roadside props exist (%d)" % road_a["count"])
	t.eq(road_a["keys"], road_b["keys"], "roadside dressing is deterministic")
	# Overrides tune a graph: a coarser lattice gives fewer points.
	var sparse := _run(world, clutter, cell, 1337, {}, [], {"spacing": 12.0})
	t.check(sparse["count"] < first["count"], "spacing override thins the clutter")

	t.current = "pcg cell seams"
	var left := _run(world, clutter, _bounds(origin.x, origin.y, 64.0, 64.0), 1337)
	var right := _run(world, clutter, _bounds(origin.x + 64.0, origin.y, 64.0, 64.0), 1337)
	var merged := _run(world, clutter, _bounds(origin.x, origin.y, 128.0, 64.0), 1337)
	var union: PackedStringArray = []
	union.append_array(left["keys"])
	union.append_array(right["keys"])
	union.sort()
	t.check(merged["count"] > 0, "merged region has clutter")
	t.eq(union, merged["keys"], "two adjacent cells equal one double-size region")
	var corner := _run(world, clutter, _bounds(origin.x, origin.y + 64.0, 64.0, 64.0), 1337)
	var quad := _run(world, clutter, _bounds(origin.x, origin.y, 64.0, 128.0), 1337)
	var vertical: PackedStringArray = []
	vertical.append_array(left["keys"])
	vertical.append_array(corner["keys"])
	vertical.sort()
	t.eq(vertical, quad["keys"], "vertical neighbours join without a seam")

	t.current = "pcg debris"
	var city := {"position": Vector3(origin.x + 32.0, world.height_at(origin.x + 32.0, origin.y + 32.0), origin.y + 32.0)}
	var debris := _run(world, PcgGraphs.ruin_debris(), _bounds(origin.x - 64.0, origin.y - 64.0, 192.0, 192.0), 1337, {"ruins": [city]})
	var near_only := true
	for i in debris["points"].get_point_count() if debris["points"] != null else 0:
		var p: Vector3 = debris["points"].get_position(i)
		if Vector2(p.x - city["position"].x, p.z - city["position"].z).length() > 70.5:
			near_only = false
	t.check(near_only, "debris stays within the radius of the ruin")


func _test_dressing_data(t, world) -> void:
	t.current = "pcg dressing data"
	var data := PcgWorldDressing.build_user_data(world)
	t.check(data["roads"].size() > 0, "road polylines for the spline sampler")
	t.check(data["roads"][0]["points"] is PackedVector3Array, "roads are 3D polylines")
	var exclusions := PcgWorldDressing.build_exclusions(world)
	t.check(exclusions.size() > 1, "hub and settlements are excluded")
	t.near(float(exclusions[0]["radius"]), Defs.HUB_SAFE_RADIUS + PcgWorldDressing.HUB_CLEARANCE, 0.001, "hub plaza radius")
	# A component streams one cell without a scene tree (graph + samplers + meshes wired like the client does).
	var component = ClassDB.instantiate("PCGComponent3D")
	component.set_graph(PcgGraphs.biome_clutter())
	component.set_generation_seed(world.world_seed)
	component.set_extents(Vector3(0.0, 200.0, 0.0))
	component.set_cell_size(64.0)
	component.set_height_sampler(Callable(world, "height_at"))
	component.set_biome_sampler(Callable(world, "biome_at"))
	component.set_water_sampler(Callable(world, "is_water"))
	var origin := _land_origin(world)
	var points = component.generate_cell(Vector2i(int(origin.x / 64.0), int(origin.y / 64.0)))
	t.check(points != null and points.get_point_count() > 0, "component generates a clutter cell")
	component.free()


func _scan(world, radius: int) -> Dictionary:
	var crates: Array = []
	var spawns: Array = []
	var per_chunk_crates := 0
	var per_chunk_spawns := 0
	var unique_ids := {}
	var duplicate := false
	for cell in _chunks(world, radius):
		var data: Dictionary = world.chunk(cell)
		var c := 0
		var s := 0
		for crate in data["crates"]:
			if bool(crate.get("pcg", false)):
				crates.append(crate)
				c += 1
			duplicate = duplicate or unique_ids.has(crate["id"])
			unique_ids[crate["id"]] = true
		for spawn in data["spawns"]:
			if bool(spawn.get("pcg", false)):
				spawns.append(spawn)
				s += 1
			duplicate = duplicate or unique_ids.has(spawn["id"])
			unique_ids[spawn["id"]] = true
		per_chunk_crates = maxi(per_chunk_crates, c)
		per_chunk_spawns = maxi(per_chunk_spawns, s)
	return {"crates": crates, "spawns": spawns, "max_crates": per_chunk_crates, "max_spawns": per_chunk_spawns, "duplicate": duplicate}


func _test_spawns(t) -> void:
	t.current = "pcg spawns"
	var classic := WorldGen.new(1337)
	var world := WorldGen.new(1337)
	t.check(PcgSpawns.attach(world), "extender attaches")
	var base := _scan(classic, SCAN_RADIUS)
	var scan := _scan(world, SCAN_RADIUS)
	t.eq(base["crates"].size() + base["spawns"].size(), 0, "classic chunks carry no PCG content")
	t.check(scan["crates"].size() > 0, "PCG caches appear (%d)" % scan["crates"].size())
	t.check(scan["spawns"].size() > 0, "PCG encounters appear (%d)" % scan["spawns"].size())
	t.check(not scan["duplicate"], "entity ids stay unique")
	t.check(scan["max_crates"] <= PcgSpawns.MAX_CACHES_PER_CHUNK, "caches capped per chunk (%d)" % scan["max_crates"])
	t.check(scan["max_spawns"] <= PcgSpawns.MAX_ENCOUNTER_SPAWNS_PER_CHUNK, "encounters capped per chunk (%d)" % scan["max_spawns"])

	var extender = world.spawn_extender
	var exclusions: Array = extender.safe_exclusions(Vector2.ZERO, Defs.CHUNK_SIZE * 0.75 + 60.0)
	var all_safe := true
	var all_land := true
	for crate in scan["crates"]:
		all_safe = all_safe and not world.is_safe(float(crate["x"]), float(crate["z"])) and not extender._in_safe_area(float(crate["x"]), float(crate["z"]), extender.safe_exclusions(Vector2(float(crate["x"]), float(crate["z"])), 8.0))
		all_land = all_land and not world.is_water(float(crate["x"]), float(crate["z"]))
		all_safe = all_safe and int(crate["tier"]) >= 1 and int(crate["tier"]) <= Defs.MAX_TIER
	for spawn in scan["spawns"]:
		all_safe = all_safe and not world.is_safe(float(spawn["x"]), float(spawn["z"])) and not extender._in_safe_area(float(spawn["x"]), float(spawn["z"]), extender.safe_exclusions(Vector2(float(spawn["x"]), float(spawn["z"])), 8.0))
		all_land = all_land and not world.is_water(float(spawn["x"]), float(spawn["z"]))
		all_safe = all_safe and Vector2(float(spawn["x"]), float(spawn["z"])).length() > Defs.HUB_SAFE_RADIUS + 20.0
	t.check(all_safe, "no cache or encounter inside the hub safe zone or a settlement")
	t.check(all_land, "no cache or encounter in water")
	t.check(exclusions.size() >= 1, "safe exclusions include the hub")

	# Deterministic for the same seed, different for another.
	var again := WorldGen.new(1337)
	PcgSpawns.attach(again)
	var scan_again := _scan(again, SCAN_RADIUS)
	t.eq(JSON.stringify(scan_again["crates"]), JSON.stringify(scan["crates"]), "same seed gives the same caches")
	t.eq(JSON.stringify(scan_again["spawns"]), JSON.stringify(scan["spawns"]), "same seed gives the same encounters")
	var other := WorldGen.new(9001)
	PcgSpawns.attach(other)
	var scan_other := _scan(other, SCAN_RADIUS)
	t.check(JSON.stringify(scan_other["spawns"]) != JSON.stringify(scan["spawns"]), "another seed moves the encounters")

	# Classic content is untouched: same nodes and classic crates/spawns in every chunk.
	var same := true
	for cell in _chunks(world, 3):
		var a: Dictionary = world.chunk(cell)
		var b: Dictionary = classic.chunk(cell)
		var classic_crates: Array = a["crates"].filter(func(c): return not bool(c.get("pcg", false)))
		var classic_spawns: Array = a["spawns"].filter(func(s): return not bool(s.get("pcg", false)))
		same = same and a["nodes"].size() == b["nodes"].size() and classic_crates.size() == b["crates"].size() and classic_spawns.size() == b["spawns"].size()
	t.check(same, "classic chunk content is unchanged")
