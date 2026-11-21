extends RefCounted
## House pieces snap to the 3 m grid, cost materials, occupy one slot each, block movement
## like walls (doorways leave a gap, floors and roofs do not block) and persist like barricades.
const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const HousePieces = preload("res://scripts/shared/house_pieces.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const BarricadesTest = preload("res://tests/test_barricades.gd")


func run(t) -> void:
	t.current = "grid snapping"
	var floor_spot: Vector3 = HousePieces.snap("floor", Vector2(100.4, 200.9))
	t.near(floor_spot.x, 100.5, 0.001, "floor snaps to the cell centre x")
	t.near(floor_spot.y, 201.0, 0.001, "floor snaps to the cell centre z")
	var east: Vector3 = HousePieces.snap("wall", Vector2(101.8, 201.0))
	t.near(east.x, 102.0, 0.001, "wall snaps to the east edge")
	t.near(east.z, 0.0, 0.001, "east wall runs north-south")
	var north: Vector3 = HousePieces.snap("wall", Vector2(100.5, 202.3))
	t.near(north.y, 202.5, 0.001, "wall snaps to the north edge")
	t.near(north.z, PI * 0.5, 0.001, "north wall runs east-west")
	var corner: Vector3 = HousePieces.snap("pillar", Vector2(98.8, 200.7))
	t.near(corner.x, 99.0, 0.001, "pillar snaps to a corner")
	t.eq(HousePieces.blockers("floor", 0, 0, 0).size(), 0, "floors do not block")
	t.eq(HousePieces.blockers("roof", 0, 0, 0).size(), 0, "roofs do not block")
	t.eq(HousePieces.blockers("door", 0, 0, 0).size(), 2, "doorways keep a gap in the middle")
	t.near(HousePieces.elevation("roof"), HousePieces.WALL_HEIGHT, 0.001, "roofs sit on top of the walls")

	t.current = "building a house on the server"
	var world := WorldGen.new(214)
	var server = GameServer.new(world, 314)
	var builder = server.add_player(101, "Builder")
	var site: Vector2 = BarricadesTest.new()._find_place(world)
	t.check(site != Vector2.ZERO, "found a dry build site")
	if site == Vector2.ZERO:
		return
	var cell_center: Vector3 = HousePieces.snap("floor", site)
	var stand := Vector2(cell_center.x - 4.0, cell_center.y)
	builder.position = Vector3(stand.x, world.height_at(stand.x, stand.y), stand.y)
	t.eq(server.cmd_build_piece(101, "floor", cell_center.x, cell_center.y).get("reason", ""), "missing_materials", "pieces cost materials")
	builder.inventory.add("wood_1", 40)
	builder.inventory.add("stone_1", 10)
	var floor_result: Dictionary = server.cmd_build_piece(101, "floor", cell_center.x, cell_center.y)
	t.check(bool(floor_result.get("ok", false)), "floor placed")
	t.eq(server.cmd_build_piece(101, "floor", cell_center.x + 0.3, cell_center.y).get("reason", ""), "occupied", "one floor per cell")
	var wall_aim := Vector2(cell_center.x + 1.3, cell_center.y)
	var wall_result: Dictionary = server.cmd_build_piece(101, "wall", wall_aim.x, wall_aim.y)
	t.check(bool(wall_result.get("ok", false)), "wall placed on the east edge (%s)" % str(wall_result.get("reason", "")))
	t.eq(server.cmd_build_piece(101, "door", wall_aim.x, wall_aim.y).get("reason", ""), "occupied", "a doorway cannot share the wall's edge")
	var roof_result: Dictionary = server.cmd_build_piece(101, "roof", cell_center.x, cell_center.y)
	t.check(bool(roof_result.get("ok", false)), "roof placed above the floor")
	if bool(roof_result.get("ok", false)):
		var roof: Dictionary = server.barricades[int(roof_result["id"])]
		t.check(float(roof["y"]) > world.height_at(cell_center.x, cell_center.y) + 2.5, "roof stands at wall height")
	t.eq(str(Structures_public(server, int(wall_result.get("id", -1))).get("piece", "")), "wall", "snapshots carry the piece kind")

	t.current = "walls block, floors do not"
	if bool(wall_result.get("ok", false)):
		var wall_x: float = cell_center.x + HousePieces.GRID * 0.5
		var before := Vector3(wall_x - 1.2, world.height_at(wall_x - 1.2, cell_center.y), cell_center.y)
		var after: Vector3 = Movement.step(world, before, {"x": 1.0, "z": 0.0}, 0.1)
		for i in 15:
			after = Movement.step(world, after, {"x": 1.0, "z": 0.0}, 0.1)
		t.check(after.x < wall_x, "a survivor cannot walk through a house wall")
	var floor_walk := Vector3(cell_center.x - 1.0, world.height_at(cell_center.x - 1.0, cell_center.y - 0.6), cell_center.y - 0.6)
	var moved: Vector3 = Movement.step(world, floor_walk, {"x": 1.0, "z": 0.0}, 0.1)
	t.check(moved.x > floor_walk.x, "a survivor walks across a floor")

	t.current = "doors open and close; beds are respawn points"
	builder.inventory.add("cloth_1", 5)
	var door_aim := Vector2(cell_center.x, cell_center.y - 1.3)
	var door_result: Dictionary = server.cmd_build_piece(101, "door", door_aim.x, door_aim.y)
	t.check(bool(door_result.get("ok", false)), "door placed (%s)" % str(door_result.get("reason", "")))
	if bool(door_result.get("ok", false)):
		var door_id: int = int(door_result["id"])
		var door: Dictionary = server.barricades[door_id]
		t.check(bool(door.get("open", false)), "new doors start open")
		builder.position = Vector3(door["x"], world.height_at(door["x"], door["z"] - 1.6), float(door["z"]) - 1.6)
		var shut: Dictionary = server.cmd_toggle_door(101, door_id)
		t.check(bool(shut.get("ok", false)) and not bool(shut.get("open", true)), "the owner shuts the door")
		t.eq(HousePieces.blockers_of(door).size(), 3, "a shut door fills the gap")
		var stranger = server.add_player(102, "Stranger")
		stranger.position = builder.position
		t.eq(server.cmd_toggle_door(102, door_id).get("reason", ""), "locked", "strangers cannot open it")
	var bed_result: Dictionary = server.cmd_build_piece(101, "bed", cell_center.x, cell_center.y)
	t.check(bool(bed_result.get("ok", false)), "bed placed (%s)" % str(bed_result.get("reason", "")))
	if bool(bed_result.get("ok", false)):
		var spot: Vector2 = server._bed_spawn(builder)
		t.check(spot.is_finite() and spot.distance_to(Vector2(cell_center.x, cell_center.y)) < HousePieces.BED_RESPAWN_RANGE + 0.5, "the bed gives a respawn spot beside it")

	t.current = "a chest opens your stash at home; a workbench is a crafting station"
	builder.inventory.add("wood_1", 20)
	builder.inventory.add("stone_1", 4)
	var chest_cell := Vector2(cell_center.x + HousePieces.GRID, cell_center.y)
	builder.position = Vector3(chest_cell.x - 1.5, world.height_at(chest_cell.x - 1.5, chest_cell.y), chest_cell.y)
	builder.inventory.add("fiber_1", 2)
	t.eq(server.cmd_stash(101, "fiber_1", 1, true).get("reason", ""), "no_station", "no stash access out in the wild")
	var chest_result: Dictionary = server.cmd_build_piece(101, "chest", chest_cell.x, chest_cell.y)
	t.check(bool(chest_result.get("ok", false)), "chest placed (%s)" % str(chest_result.get("reason", "")))
	if bool(chest_result.get("ok", false)):
		t.check(bool(server.cmd_stash(101, "fiber_1", 1, true).get("ok", false)), "deposit into the stash at your own chest")
		var other = server.add_player(103, "Visitor")
		other.position = builder.position
		other.inventory.add("fiber_1", 1)
		t.eq(server.cmd_stash(103, "fiber_1", 1, true).get("reason", ""), "no_station", "someone else's chest is not your stash")
	t.check(not server._near_piece(builder.position, "workbench"), "no workbench yet")
	var bench_result: Dictionary = server.cmd_build_piece(101, "workbench", chest_cell.x, chest_cell.y + HousePieces.GRID)
	t.check(bool(bench_result.get("ok", false)), "workbench placed (%s)" % str(bench_result.get("reason", "")))
	t.near(HousePieces.snap("roof", Vector2(1, 1), PI * 0.5 + 0.2).z, PI * 0.5, 0.001, "roofs turn in quarter turns toward the builder's facing")

	t.current = "dismantling removes the collision"
	if bool(wall_result.get("ok", false)):
		var id: int = int(wall_result["id"])
		server.cmd_dismantle(101, id)
		var still := false
		for blocker in world.blockers_near(cell_center.x + 1.5, cell_center.y, 1.0):
			if str(blocker.get("piece_owner", "")) == str(id):
				still = true
		t.check(not still, "no leftover wall circles after dismantling")


static func Structures_public(server, id: int) -> Dictionary:
	if not server.barricades.has(id):
		return {}
	return preload("res://scripts/shared/structures.gd").public_state(server.barricades[id])
