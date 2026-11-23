extends RefCounted
## Authoritative fallen logs: the server and client see exactly one object,
## it blocks movement until gathered, and it can be chopped from the edge.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const SolidScenery = preload("res://scripts/shared/solid_scenery.gd")
const ResourceGathering = preload("res://scripts/shared/resource_gathering.gd")
const Defs = preload("res://scripts/shared/defs.gd")


func run(t) -> void:
	t.current = "fallen wood manifest"
	t.eq(SolidScenery.MODELS.size(), 3, "three scanned logs have authoritative variants")
	for entry in SolidScenery.MODELS:
		t.eq(str(entry["resource"]), "tree", "all logs yield wood through normal gathering")
		t.check(SolidScenery.is_promoted_path(str(entry["path"])), "each visual-only log is promoted")
		t.check(SolidScenery.radius(0, 1.0) > 2.0, "large logs have a solid footprint")
	t.check(not SolidScenery.is_promoted_path("res://assets/models/polyhaven/baked/stone_scatter.res"),
		"stone deposits stay owned by the existing StoneResources generator")
	t.check(SolidScenery.available_variants("mountain").is_empty(),
		"wood debris does not appear in mountain rock fields")

	t.current = "seeded collidable and mineable fallen logs"
	var world := WorldGen.new(431)
	var other := WorldGen.new(431)
	var found: Dictionary = {}
	var home := Vector2i.ZERO
	for cx in range(2, 10):
		if not found.is_empty():
			break
		for cz in range(2, 10):
			var cell := Vector2i(cx, cz)
			for node in world.chunk(cell)["nodes"]:
				if node.has("solid_model"):
					found = node
					home = cell
					break
			if not found.is_empty():
				break
	t.check(not found.is_empty(), "generated world contains solid fallen wood")
	if found.is_empty():
		return
	var id: int = int(found["id"])
	t.check(id == WorldGen.entity_id(home, WorldGen.FALLEN_WOOD_ID_BASE),
		"fallen wood uses a stable collision and depletion ID")
	t.eq(found, other.chunk(home)["nodes"].filter(func(n): return n.has("solid_model"))[0],
		"same seed gives identical model, location and footprint on every peer")
	t.check(bool(found["blocks"]) and str(found["kind"]) == "tree", "wood is both blocking and harvestable")
	var x: float = float(found["x"])
	var z: float = float(found["z"])
	var neighbors: Array = world.blockers_near(x, z, 0.5)
	var seen := false
	for blocker in neighbors:
		if int(blocker.get("id", -1)) == id:
			seen = true
			break
	t.check(seen, "server movement sees the visible log as a collision obstacle")

	t.current = "resource depletion removes invisible blockers"
	world.set_depleted_resources({id: true})
	seen = false
	for blocker in world.blockers_near(x, z, 0.5):
		if int(blocker.get("id", -1)) == id:
			seen = true
	t.check(not seen, "harvested log cannot leave an invisible wall")
	world.set_depleted_resources({})
	seen = false
	for blocker in world.blockers_near(x, z, 0.5):
		if int(blocker.get("id", -1)) == id:
			seen = true
	t.check(seen, "respawn restores collision at the exact same position")

	t.current = "mining edge reach"
	var radius: float = float(found["radius"])
	var player_pos := Vector3(x + radius + Defs.PLAYER_RADIUS + 0.04, 0.0, z)
	t.check(ResourceGathering.reach_margin(found) >= radius - 0.001,
		"the full log collision radius counts toward interaction reach")
	t.check(ResourceGathering.aimed_at(player_pos, found, Vector2.LEFT),
		"a player standing outside the log can chop it")
	var small_tree := {"kind": "tree", "radius": 0.5}
	t.eq(ResourceGathering.reach_margin(small_tree), 0.0,
		"ordinary trees retain their original short interaction radius")
