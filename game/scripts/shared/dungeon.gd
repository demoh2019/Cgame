extends RefCounted
## Dungeons under the bunkers: each bunker has a hatch that leads down into an underground complex of stone rooms joined by
## doorways, with infected in every room, a chest in each, and the strongest of them in the room farthest from the stairs.
##
## The complexes live in their own part of the world's coordinates, far east of the island (UNDERGROUND_X and beyond), one
## per 256 m region of the surface, so WorldGen answers for them like for any ground: a flat stone floor, walls as
## blockers, spawns and crates in the chunks. Movement, combat, loot and prediction need nothing new. Everything here is
## derived from the world seed and the region, so the server and every client see the same rooms.

const UNDERGROUND_X := 6000.0 # Everything east of this is underground.
const REGION_SIZE := 256.0 # The surface region a dungeon belongs to (WorldPoi regions).
const SLOT := 160.0 # Room for one complex (at most 5 x 5 rooms of 12 m) in the underground grid.
const REGION_OFFSET := 16 # Surface regions -16..15 map to underground slots 0..31.
const TILE := 4.0 # One floor tile and one wall piece of the dungeon kit.
const ROOM_TILES := 3
const ROOM := TILE * ROOM_TILES # 12 m rooms.
const FLOOR_Y := 2.0
const GRID := 2 # Rooms lie on a grid from -GRID to GRID around the stairs room.
const WALL_POST := 0.55 # Radius of the posts that make up a wall for collision.
const HATCH_REACH := 2.6 # How close to the hatch or the stairs you must be to go down or up.


static func is_underground(x: float, _z: float = 0.0) -> bool:
	return x >= UNDERGROUND_X - 40.0


## The surface region whose bunker a point underground belongs to.
static func region_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x - UNDERGROUND_X) / SLOT) - REGION_OFFSET, floori(z / SLOT) - REGION_OFFSET)


## Centre of the stairs room of a region's complex.
static func origin(region: Vector2i) -> Vector2:
	return Vector2(UNDERGROUND_X + (float(region.x + REGION_OFFSET) + 0.5) * SLOT, (float(region.y + REGION_OFFSET) + 0.5) * SLOT)


static var _layouts: Dictionary = {}


## The rooms of a region's complex: {"rooms": [Vector2i], "links": {"a|b": true}, "boss": Vector2i}. A random walk from
## the stairs room (0, 0), six to nine rooms; every new room opens into the one it was reached from.
static func layout(world_seed: int, region: Vector2i) -> Dictionary:
	var key := "%d|%d|%d" % [world_seed, region.x, region.y]
	if _layouts.has(key):
		return _layouts[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) ^ 0x5d1f
	var rooms: Array = [Vector2i.ZERO]
	var links: Dictionary = {}
	var depth: Dictionary = {Vector2i.ZERO: 0}
	var wanted: int = rng.randi_range(6, 9)
	var steps := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var guard := 0
	while rooms.size() < wanted and guard < 400:
		guard += 1
		var from: Vector2i = rooms[rng.randi_range(0, rooms.size() - 1)]
		var to: Vector2i = from + steps[rng.randi_range(0, 3)]
		if absi(to.x) > GRID or absi(to.y) > GRID or depth.has(to):
			continue
		rooms.append(to)
		depth[to] = int(depth[from]) + 1
		links[_link_key(from, to)] = true
	var boss: Vector2i = Vector2i.ZERO
	for room in rooms:
		if int(depth[room]) > int(depth[boss]):
			boss = room
	var result := {"rooms": rooms, "links": links, "boss": boss}
	_layouts[key] = result
	return result


static func _link_key(a: Vector2i, b: Vector2i) -> String:
	var first: Vector2i = a if (a.x < b.x or (a.x == b.x and a.y < b.y)) else b
	var second: Vector2i = b if first == a else a
	return "%d,%d|%d,%d" % [first.x, first.y, second.x, second.y]


static func linked(layout_data: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	return layout_data["links"].has(_link_key(a, b))


static func room_center(region: Vector2i, room: Vector2i) -> Vector2:
	return origin(region) + Vector2(room) * ROOM


## Whether a point lies inside one of the rooms of its complex.
static func inside_room(world_seed: int, x: float, z: float) -> bool:
	var region := region_of(x, z)
	var local: Vector2 = Vector2(x, z) - origin(region)
	var room := Vector2i(roundi(local.x / ROOM), roundi(local.y / ROOM))
	return layout(world_seed, region)["rooms"].has(room)


## Wall pieces of a complex, one per 4 m tile edge: [{"a": Vector2, "b": Vector2, "door": bool}]. Every room is closed
## all round; an edge into a linked room gets a doorway in its middle piece, an edge into an unlinked room is solid.
static func walls(world_seed: int, region: Vector2i) -> Array:
	var data: Dictionary = layout(world_seed, region)
	var pieces: Array = []
	var seen: Dictionary = {}
	var half: float = ROOM * 0.5
	for room in data["rooms"]:
		var center: Vector2 = room_center(region, room)
		for side in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbour: Vector2i = room + side
			var key: String = _link_key(room, neighbour)
			if seen.has(key):
				continue # The wall between two rooms is built once.
			seen[key] = true
			var door: bool = linked(data, room, neighbour)
			var normal := Vector2(side)
			var along := Vector2(-normal.y, normal.x)
			var edge_mid: Vector2 = center + normal * half
			for i in ROOM_TILES:
				var offset: float = (float(i) - float(ROOM_TILES - 1) * 0.5) * TILE
				var mid: Vector2 = edge_mid + along * offset
				pieces.append({"a": mid - along * TILE * 0.5, "b": mid + along * TILE * 0.5,
					"door": door and i == ROOM_TILES / 2})
	return pieces


## Collision posts of the walls near a point, as blockers (doorways keep only their side posts).
static func blockers_near(world_seed: int, x: float, z: float, radius: float) -> Array:
	var result: Array = []
	var region := region_of(x, z)
	var here := Vector2(x, z)
	if here.distance_to(origin(region)) > SLOT:
		return result
	for piece in walls(world_seed, region):
		var a: Vector2 = piece["a"]
		var b: Vector2 = piece["b"]
		var steps: int = int(TILE)
		for i in steps + 1:
			if piece["door"] and i > 0 and i < steps:
				continue
			var p: Vector2 = a.lerp(b, float(i) / float(steps))
			if absf(p.x - x) < radius + WALL_POST and absf(p.y - z) < radius + WALL_POST:
				result.append({"x": p.x, "z": p.y, "radius": WALL_POST, "blocks": true, "kind": "dungeon_wall"})
	return result


## What waits in a room: [{"type", "x", "z"}] infected and at most one chest. The stairs room is empty; the deepest room
## holds a brute with its escort.
static func room_contents(world_seed: int, region: Vector2i, room: Vector2i, zone: int) -> Dictionary:
	var data: Dictionary = layout(world_seed, region)
	var center: Vector2 = room_center(region, room)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%d|%d|%d|%d" % [world_seed, region.x, region.y, room.x, room.y])
	var infected: Array = []
	var chests: Array = []
	if room == Vector2i.ZERO:
		return {"infected": infected, "chests": chests}
	var boss: bool = room == data["boss"]
	var count: int = 3 if boss else rng.randi_range(2, 3)
	for i in count:
		var kind: String = ["walker", "runner", "walker", "spitter"][rng.randi_range(0, 3)] if zone < 3 else ["runner", "brute", "spitter"][rng.randi_range(0, 2)]
		var spot: Vector2 = center + Vector2(rng.randf_range(-3.5, 3.5), rng.randf_range(-3.5, 3.5))
		infected.append({"type": "brute" if boss and i == 0 else kind, "x": spot.x, "z": spot.y, "boss": boss and i == 0})
	chests.append({"x": center.x + rng.randf_range(-3.0, 3.0), "z": center.y + (3.6 if rng.randf() < 0.5 else -3.6),
		"tier": clampi(zone + (2 if boss else 1), 1, 4)})
	return {"infected": infected, "chests": chests}


## The hatch down into a bunker's complex: the first free spot on a ring round the bunker's centre.
static func hatch(world, site: Dictionary) -> Vector2:
	var center := Vector2(float(site["x"]), float(site["z"]))
	for ring in [6.0, 9.0, 12.0, 4.0]:
		for i in 8:
			var spot: Vector2 = center + Vector2.from_angle(float(i) * TAU / 8.0) * ring
			if world.blockers_near(spot.x, spot.y, 1.4).is_empty() and not world.is_water(spot.x, spot.y):
				return spot
	return center


## The bunker whose hatch is within reach of a surface point, or {}.
static func bunker_at(world, x: float, z: float) -> Dictionary:
	for site in world.poi.sites_near(x, z, 40.0):
		if str(site.get("kind", "")) == "bunker" and hatch(world, site).distance_to(Vector2(x, z)) <= HATCH_REACH:
			return site
	return {}


## Where you arrive below: in the stairs room, a little off the stairs.
static func arrival(region: Vector2i) -> Vector2:
	return origin(region) + Vector2(0, 2.5)


## Whether an underground point is at the stairs up.
static func at_stairs(x: float, z: float) -> bool:
	return Vector2(x, z).distance_to(origin(region_of(x, z))) <= HATCH_REACH


## Surface region of a site (the dungeon below it).
static func region_of_site(site: Dictionary) -> Vector2i:
	return Vector2i(floori(float(site["x"]) / REGION_SIZE), floori(float(site["z"]) / REGION_SIZE))
