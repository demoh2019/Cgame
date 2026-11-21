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
