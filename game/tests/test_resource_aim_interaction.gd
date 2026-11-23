extends RefCounted
## E interaction targets the resource under the crosshair even when a
## different rock or stone is closer. Fallback preserves no-aim accessibility.

const GameClient = preload("res://scripts/client/game_client.gd")
const Defs = preload("res://scripts/shared/defs.gd")


class NetStub:
	extends RefCounted
	var client


class ChunkStub:
	extends RefCounted
	var nodes: Array = []
	var crates: Array = []
	var crates_by_cell: Dictionary = {}
	var calls: Array[Vector2i] = []

	func chunk(cell: Vector2i) -> Dictionary:
		calls.append(cell)
		if crates_by_cell.has(cell):
			return {"nodes": [], "crates": crates_by_cell[cell]}
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

	t.current = "aimed mining chooses the visible rock"
	var mine_stub := ChunkStub.new()
	mine_stub.nodes = [
		{"id": 31, "kind": "rock", "x": 1.0, "z": 1.0, "radius": 0.3},
		{"id": 32, "kind": "rock", "x": 2.0, "z": 0.0, "radius": 0.3},
	]
	client.world = mine_stub
	client.depleted.clear()
	t.eq(int(client.nearest_strike_node(Vector3.ZERO, Vector2.RIGHT, 2.6).get("id", -1)), 32,
		"aimed mineable beats the closer rock to the side")
	t.eq(int(client.nearest_strike_node(Vector3.ZERO, Vector2(1.0, 1.0), 2.6).get("id", -1)), 31,
		"turning to the other rock changes the target")
	t.check(client.nearest_strike_node(Vector3.ZERO, Vector2.ZERO, 2.6).is_empty(),
		"invalid mining direction cannot select a resource")

	t.current = "held E works at the edge of a modeled pebble"
	var loose_stub := ChunkStub.new()
	loose_stub.nodes = [{"id": 41, "kind": "pebble", "x": 3.0, "z": 0.0, "radius": 0.5}]
	client.world = loose_stub
	t.eq(int(client.nearest_pickup_node(Vector3.ZERO, 2.6).get("id", -1)), 41,
		"large visible pebble is reachable from its model boundary")
	t.check(client.nearest_pickup_node(Vector3(0.0, 0.0, INF), 2.6).is_empty(),
		"nonfinite positions cannot trigger any chunk lookup")
 
	t.current = "fishing net target respects ownership and stable reach"
	client.fish_traps = {
		30: {"id": 30, "x": 1.0, "z": 0.0, "own": true},
		20: {"id": 20, "x": 1.0, "z": 0.0, "own": true},
		10: {"id": 10, "x": 0.3, "z": 0.0, "own": false},
		50: {"id": 50, "x": NAN, "z": 0.0, "own": true},
	}
	t.eq(client.nearest_fish_trap(Vector3.ZERO, 2.0), 20,
		"other players' closer traps do not capture E interaction")
	t.eq(client.nearest_fish_trap(Vector3.ZERO, 0.5), -1,
		"owned nets outside reach cannot be selected")
	t.eq(client.nearest_fish_trap(Vector3.ZERO, INF), -1,
		"infinite search radius is rejected")
	t.eq(client.nearest_fish_trap(Vector3.ZERO, -1.0), -1,
		"negative search radius is rejected")
	t.eq(client.nearest_fish_trap(Vector3(NAN, 0.0, 0.0)), -1,
		"invalid player coordinates are rejected")
	client.fish_traps.erase(20)
	t.eq(client.nearest_fish_trap(Vector3.ZERO, 2.0), 30,
		"remaining owned net is selectable after one disappears")
	client.fish_traps[30].erase("own")
	t.eq(client.nearest_fish_trap(Vector3.ZERO, 2.0), 30,
		"legacy snapshots without rights flags remain compatible")

	t.current = "loot selection prefers the crate under the crosshair"
	var loot_stub := ChunkStub.new()
	loot_stub.crates = [{"id": 82, "x": 2.0, "z": 0.0}]
	client.world = loot_stub
	client.bags.clear()
	client.crates_used.clear()
	client.bags[81] = {"id": 81, "x": 0.8, "z": 0.8}
	client.bags[89] = {"id": 89, "x": NAN, "z": 0.0}
	t.eq(int(client.nearest_loot(Vector3.ZERO, 2.6).get("id", -1)), 81,
		"without aim, E still targets the nearest bag")
	t.eq(int(client.nearest_loot(Vector3.ZERO, 2.6, Vector2.RIGHT).get("id", -1)), 82,
		"aiming at the crate selects it despite a closer side bag")
	t.eq(int(client.nearest_loot(Vector3.ZERO, 2.6, Vector2(1.0, 1.0)).get("id", -1)), 81,
		"turning back to the bag selects the bag")
	client.crates_used[82] = true
	t.eq(int(client.nearest_loot(Vector3.ZERO, 2.6, Vector2.RIGHT).get("id", -1)), 81,
		"used crate is excluded even while aimed at")
	t.check(client.nearest_loot(Vector3.ZERO, 2.6, Vector2(INF, 0.0)).get("id", -1) == 81,
		"non-finite aim falls back to the nearest reachable loot")
	client.bags.clear()
	t.check(client.nearest_loot(Vector3.ZERO, 2.6, Vector2.RIGHT).is_empty(),
		"invalid replicated bag coordinates cannot produce phantom loot")

	t.current = "loot streaming searches only intersecting world chunks"
	var spatial := ChunkStub.new()
	client.world = spatial
	var middle: float = float(Defs.CHUNK_SIZE) * 0.5
	var center: Vector3 = Vector3(middle, 0.0, middle)
	t.check(client.nearest_loot(center, Defs.REACH).is_empty(),
		"empty center chunk has no phantom loot")
	t.eq(spatial.calls.size(), 1, "center-of-chunk E searches one chunk, not nine")
	spatial.calls.clear()
	spatial.crates_by_cell[Vector2i(1, 0)] = [
		{"id": 91, "x": float(Defs.CHUNK_SIZE) + 0.3, "z": middle}]
	var seam := Vector3(float(Defs.CHUNK_SIZE) - 0.5, 0.0, middle)
	t.eq(int(client.nearest_loot(seam, Defs.REACH).get("id", -1)), 91,
		"adjacent-chunk crate remains reachable")
	t.eq(spatial.calls.size(), 2,
		"query near seam reads two chunks, rather than generating nine")
	spatial.calls.clear()
	spatial.crates_by_cell[Vector2i(-1, 0)] = [
		{"id": 92, "x": -0.2, "z": middle}]
	t.eq(int(client.nearest_loot(Vector3(0.5, 0.0, middle), Defs.REACH).get("id", -1)), 92,
		"negative-coordinate seam remains functional")
	t.eq(spatial.calls.size(), 2, "negative seam search also reads only two chunks")
