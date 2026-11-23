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
	var crates: Array = []

	func chunk(cell: Vector2i) -> Dictionary:
		if cell == Vector2i.ZERO:
			return {"nodes": nodes, "crates": crates}
		return {"nodes": [], "crates": []}



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

	t.current = "held-E pickup and loot use bounded squared-distance queries"
	client.depleted.clear()
	client.crates_used.clear()
	stub.crates = [{"id": 3, "x": 1.5, "z": 0.0}, {"id": 4, "x": 2.5, "z": 0.0}]
	t.eq(int(client.nearest_loot(Vector3.ZERO, 2.0).get("id", -1)), 3,
		"nearest crate is selectable inside radius")
	client.crates_used[3] = true
	t.check(client.nearest_loot(Vector3.ZERO, 2.0).is_empty(),
		"used crate is ignored and distant crates stay out of range")
	client.bags[5] = {"id": 5, "x": 0.7, "z": 0.0}
	t.eq(int(client.nearest_loot(Vector3.ZERO, 2.0).get("id", -1)), 5,
		"reachable player loot remains selectable")
	t.check(client.nearest_loot(Vector3(INF, 0.0, 0.0), 2.0).is_empty(),
		"invalid predicted position must not query world chunks")
	t.check(client.nearest_pickup_node(Vector3.ZERO, INF).is_empty(),
		"non-finite pickup range cannot trigger unbounded collection")
	t.check(client.nearest_pickup_node(Vector3.ZERO, 0.0).is_empty(),
		"zero pickup range selects nothing")

	t.current = "new session clears previous character and replicated world state"
	client.players[101] = {"id": 101}
	client.depleted[1] = true
	client.resource_hits[2] = 3
	client.crates_used[3] = true
	client.you = {"x": 10.0}
	client.outposts.append({"id": 7})
	client.events.append({"type": "gathered"})
	client.last_results["market"] = {"ok": true}
	client.supply_beacon = {"expires": 999.0}
	client.inventory.add("wood_1", 2)
	client._seq = 14
	client._pending.append({"seq": 14})
	client.correction = Vector3.ONE
	var old_world_revision: int = client.world_state_revision
	var old_damage_revision: int = client.resource_damage_revision
	client._reset_session_state()
	t.check(client.players.is_empty() and client.bags.is_empty()
		and client.outposts.is_empty(), "old entities and player loot are discarded")
	t.check(client.depleted.is_empty() and client.resource_hits.is_empty()
		and client.crates_used.is_empty(), "old world's resource IDs do not leak across sessions")
	t.check(client.events.is_empty() and client.last_results.is_empty()
		and client.supply_beacon.is_empty(), "old notifications, results and party data disappear")
	t.check(client.you.is_empty() and client.inventory.count("wood_1") == 0,
		"previous character's inventory stays hidden until the first snapshot")
	t.eq(client._seq, 0, "input sequence restarts on the new connection")
	t.check(client._pending.is_empty() and client.correction == Vector3.ZERO,
		"unacknowledged movement and smoothing from old server are dropped")
	t.eq(client.world_state_revision, old_world_revision + 1,
		"new world invalidates visible geometry cache")
	t.eq(client.resource_damage_revision, old_damage_revision + 1,
		"new world invalidates mining damage tints")
