extends RefCounted
## Dynamic resource cell queries must be cheap without missing mineable edge geometry.

const GameClient = preload("res://scripts/client/game_client.gd")


class NetStub:
	extends RefCounted
	var client


class WorldStub:
	extends RefCounted
	var cells: Dictionary = {}
	var visited: Array[Vector2i] = []

	func chunk(cell: Vector2i) -> Dictionary:
		visited.append(cell)
		return {"nodes": cells.get(cell, [])}


func run(t) -> void:
	t.current = "short-range resource searches avoid generating distant chunks"
	var world := WorldStub.new()
	world.cells[Vector2i.ZERO] = [
		{"id": 11, "kind": "pebble", "tier": 1, "x": 32.4, "z": 32.4, "radius": 0.2},
		{"id": 12, "kind": "rock", "tier": 1, "x": 33.0, "z": 32.0, "radius": 0.5},
	]
	var player = GameClient.new(NetStub.new())
	player.world = world
	var point := Vector3(32.0, 0.0, 32.0)
	t.eq(int(player.nearest_node(point, 2.6).get("id", -1)), 11,
		"loose pebble still wins the nearest fallback")
	t.eq(world.visited, [Vector2i.ZERO], "nearest queries one world cell")
	world.visited.clear()
	t.eq(int(player.nearest_aimed_node(point, Vector2.RIGHT, 2.6).get("id", -1)), 12,
		"centered mineable stone wins camera aim")
	t.eq(world.visited, [Vector2i.ZERO], "aimed queries one world cell")
	world.visited.clear()
	t.eq(int(player.nearest_strike_node(point, Vector2.RIGHT, 2.6).get("id", -1)), 12,
		"mining still selects real rocks")
	t.eq(world.visited, [Vector2i.ZERO], "strike queries one world cell")
	world.visited.clear()
	t.eq(int(player.nearest_pickup_node(point, 2.6).get("id", -1)), 11,
		"pickup still selects loose pebbles")
	t.eq(world.visited, [Vector2i.ZERO], "pickup queries one world cell")

	t.current = "wide rock meshes retain their cross-chunk interaction"
	var neighbor := WorldStub.new()
	neighbor.cells[Vector2i(1, 0)] = [
		{"id": 13, "kind": "rock", "tier": 1, "x": 68.0, "z": 32.0,
			"radius": 3.0, "solid_model": 0},
	]
	var edge = GameClient.new(NetStub.new())
	edge.world = neighbor
	t.eq(int(edge.nearest_strike_node(Vector3(62.5, 0, 32), Vector2.RIGHT, 2.6).get("id", -1)), 13,
		"model's reachable surface is mineable even when its center is across a border")
	t.check(neighbor.visited.has(Vector2i(1, 0)), "adjacent cell is still searched at the border")

	t.current = "invalid interaction inputs cannot trigger remote chunk generation"
	var offline = GameClient.new(NetStub.new())
	t.check(offline.nearest_node(Vector3.ZERO, 2.6).is_empty(),
		"queries are safe before client world initialization")
	t.check(offline.nearest_strike_node(Vector3.ZERO, Vector2.RIGHT).is_empty(),
		"strikes are safe during reconnection")
	t.check(player.nearest_pickup_node(Vector3(INF, 0, 0), 2.6).is_empty(),
		"non-finite world coordinates cannot cause chunk lookups")
