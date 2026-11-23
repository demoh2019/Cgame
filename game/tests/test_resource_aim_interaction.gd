extends RefCounted
## E interaction targets the resource under the crosshair even when a
## different rock or stone is closer. Fallback preserves no-aim accessibility.

const GameClient = preload("res://scripts/client/game_client.gd")


class NetStub:
	extends RefCounted
	var client


class ChunkStub:
	extends RefCounted
	var nodes: Array = []

	func chunk(cell: Vector2i) -> Dictionary:
		return {"nodes": nodes if cell == Vector2i.ZERO else []}


func run(t) -> void:
	t.current = "resource aiming prefers the visible model instead of nearest centre"
	var stub := ChunkStub.new()
	stub.nodes = [
		{"id": 1, "kind": "pebble", "tier": 1, "x": 0.8, "z": 0.8, "radius": 0.25},
		{"id": 2, "kind": "rock", "tier": 1, "x": 2.0, "z": 0.0, "radius": 0.3},
	]
	var client = GameClient.new(NetStub.new())
	client.world = stub
	var at := Vector3.ZERO
	t.eq(int(client.nearest_node(at, 2.6)["id"]), 1,
		"closest fallback sees the loose stone")
	t.eq(int(client.nearest_aimed_node(at, Vector2.RIGHT, 2.6)["id"]), 2,
		"looking at the rock prefers mining it over the closer loose stone")
	t.eq(int(client.nearest_aimed_node(at, Vector2(1.0, 1.0), 2.6)["id"]), 1,
		"looking at a pickup selects that stone")
	t.eq(int(client.nearest_aimed_node(at, Vector2.ZERO, 2.6)["id"]), 1,
		"camera aim unavailable: E still uses the nearest resource")
	t.eq(int(client.nearest_aimed_node(at, Vector2.LEFT, 2.6)["id"]), 1,
		"looking away falls back to the nearest reachable resource")
	client.depleted[2] = true
	t.eq(int(client.nearest_aimed_node(at, Vector2.RIGHT, 2.6)["id"]), 1,
		"depleted model cannot be retargeted")
	client.depleted[1] = true
	t.check(client.nearest_aimed_node(at, Vector2.RIGHT, 2.6).is_empty(),
		"no phantom target when all nearby models have disappeared")
