extends RefCounted
## Dungeons under the bunkers: a hatch at every bunker leads down into a complex of rooms that is the same for everyone,
## walls hold, the rooms hold infected (a champion in the deepest) and chests, the dungeon is a zone deeper than the land
## above, and the stairs lead back up to the hatch.

const Dungeon = preload("res://scripts/shared/dungeon.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _first_bunker(world) -> Dictionary:
	for rx in range(-10, 11):
		for rz in range(-10, 11):
			for site in world.poi.sites_in_region(rx, rz):
				if str(site.get("kind", "")) == "bunker":
					return site
	return {}


func run(t) -> void:
	var world := WorldGen.new(42)
	var bunker: Dictionary = _first_bunker(world)
	t.check(not bunker.is_empty(), "the island has a bunker")
	if bunker.is_empty():
		return
	var region: Vector2i = Dungeon.region_of_site(bunker)

	t.current = "the complex is the same for everyone and holds together"
	var layout: Dictionary = Dungeon.layout(world.world_seed, region)
	t.check(layout["rooms"].size() >= 6 and layout["rooms"].size() <= 9, "six to nine rooms (%d)" % layout["rooms"].size())
	var remembered: Dictionary = layout.duplicate(true)
	Dungeon._layouts.clear()
	t.eq(Dungeon.layout(world.world_seed, region), remembered, "same seed, same rooms, every time")
	t.eq(layout["links"].size(), layout["rooms"].size() - 1, "every room is reached by exactly one new doorway (a tree)")
	t.check(layout["boss"] != Vector2i.ZERO, "the guardian is not in the stairs room")
	var origin: Vector2 = Dungeon.origin(region)
	t.check(Dungeon.is_underground(origin.x) and Dungeon.region_of(origin.x, origin.y) == region, "the complex maps back to its bunker")
	t.near(world.height_at(origin.x, origin.y), Dungeon.FLOOR_Y, 0.0001, "a flat stone floor")
	t.check(not world.is_water(origin.x, origin.y), "no sea underground")
	t.eq(world.biome_at(origin.x, origin.y), "dungeon", "its own biome (no grass, no trees)")

	t.current = "walls hold and doorways let through"
	var walker := Vector3(origin.x, Dungeon.FLOOR_Y, origin.y)
	for step in 80: # Walk at a closed or open wall of the stairs room for eight seconds.
		walker = Movement.step(world, walker, {"x": 0.0, "z": -1.0}, 0.1)
	var start_has_south: bool = layout["links"].has("0,-1|0,0")
	if start_has_south:
		t.check(walker.z < origin.y - Dungeon.ROOM * 0.5, "a doorway lets you into the next room")
	else:
		t.check(walker.z > origin.y - Dungeon.ROOM * 0.5, "a wall stops you")
	t.check(not world.blockers_near(origin.x, origin.y - Dungeon.ROOM * 0.5, 2.0).is_empty(), "walls are blockers")

	t.current = "rooms hold infected, a champion and chests; deeper than the land above"
	var surface_zone: int = world.zone_at(float(bunker["x"]), float(bunker["z"]))
	t.eq(world.zone_at(origin.x, origin.y), mini(3, surface_zone + 1), "a zone deeper")
	var spawns := 0
	var bosses := 0
	var chests := 0
	var seen_cells: Dictionary = {}
	for room in layout["rooms"]:
		var center: Vector2 = Dungeon.room_center(region, room)
		var cell: Vector2i = WorldGen.cell_of(center.x, center.y)
		if seen_cells.has(cell):
			continue
		seen_cells[cell] = true
		var data: Dictionary = world.chunk(cell)
		t.check(bool(data.get("dungeon", false)) and data["nodes"].is_empty(), "an underground chunk has no trees or rocks")
		spawns += data["spawns"].size()
		chests += data["crates"].size()
		for spawn in data["spawns"]:
			if bool(spawn.get("dungeon_boss", false)):
				bosses += 1
	t.check(spawns >= (layout["rooms"].size() - 1) * 2, "infected in every room but the first (%d)" % spawns)
	t.eq(bosses, 1, "one guardian")
	t.eq(chests, layout["rooms"].size() - 1, "a chest in every room but the first")

	t.current = "down the hatch and up the stairs"
	var sim := GameServer.new(world, 7)
	var diver = sim.add_player(3, "Diver")
	diver.position = Vector3(float(bunker["x"]) + 30.0, 0.0, float(bunker["z"]))
	t.eq(sim.cmd_dungeon(3, true).get("reason", ""), "no_hatch", "only at the hatch")
	var hatch: Vector2 = Dungeon.hatch(world, bunker)
	diver.position = Vector3(hatch.x, world.height_at(hatch.x, hatch.y), hatch.y)
	t.check(bool(sim.cmd_dungeon(3, true).get("ok", false)), "down")
	t.check(Dungeon.is_underground(diver.position.x), "the diver is below")
	t.check(Dungeon.at_stairs(diver.position.x, diver.position.z), "arriving by the stairs")
	t.eq(sim.cmd_dungeon(3, true).get("reason", ""), "already_below", "no second way down")
	diver.position.x += 4.5
	t.eq(sim.cmd_dungeon(3, false).get("reason", ""), "no_stairs", "only up the stairs")
	diver.position.x -= 4.5
	t.check(bool(sim.cmd_dungeon(3, false).get("ok", false)), "up")
	t.check(not Dungeon.is_underground(diver.position.x), "back on the surface")
	t.check(Vector2(diver.position.x, diver.position.z).distance_to(hatch) < 3.0, "by the hatch")
