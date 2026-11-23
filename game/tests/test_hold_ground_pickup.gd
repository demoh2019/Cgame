extends RefCounted
## Holding E never targets a rock to mine or an owned loot crate, and pending
## requests are excluded until a server snapshot can acknowledge depletion.

const Defs = preload("res://scripts/shared/defs.gd")
const GameClient = preload("res://scripts/client/game_client.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")


class NetStub:
	extends RefCounted
	var client


func run(t) -> void:
	t.current = "hold E selects only nearby stones and sticks"
	var client = GameClient.new(NetStub.new())
	client.world = WorldGen.new(42)
	var pickup: Dictionary = {}
	for cx in range(2, 9):
		if not pickup.is_empty():
			break
		for cz in range(2, 9):
			if not pickup.is_empty():
				break
			for node in client.world.chunk(Vector2i(cx, cz))["nodes"]:
				if str(node["kind"]) in ["pebble", "branch"]:
					pickup = node
					break
	t.check(not pickup.is_empty(), "seeded world offers hand pickups")
	if pickup.is_empty():
		return
	var point := Vector3(float(pickup["x"]), float(pickup["y"]), float(pickup["z"]))
	var near: Dictionary = client.nearest_ground_pickup(point, Defs.REACH)
	t.check(not near.is_empty(), "hold pickup selects an actual nearby resource")
	if near.is_empty():
		return
	t.check(str(near["kind"]) in ["pebble", "branch"],
		"hold pickup cannot start rock mining or tree chopping")
	var first_id: int = int(near["id"])
	var pending: Dictionary = {}
	pending[first_id] = true
	var second: Dictionary = client.nearest_ground_pickup(point, Defs.REACH, pending)
	t.check(second.is_empty() or int(second["id"]) != first_id,
		"pending pickup cannot be sent twice while snapshot is in flight")
	client.depleted[first_id] = true
	var next: Dictionary = client.nearest_ground_pickup(point, Defs.REACH)
	t.check(next.is_empty() or int(next["id"]) != first_id,
		"server-depleted stone cannot be collected again")
	t.check(client.nearest_ground_pickup(point + Vector3(10000.0, 0.0, 10000.0),
		Defs.REACH).is_empty(), "no artificial pickup from out of range")
