extends RefCounted
## Client and server use the same Rust-like pickup/strike rules.

const Defs = preload("res://scripts/shared/defs.gd")
const ResourceGathering = preload("res://scripts/shared/resource_gathering.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _find(world, kind: String) -> Dictionary:
	for cx in range(3, 8):
		for cz in range(3, 8):
			for node in world.chunk(Vector2i(cx, cz))["nodes"]:
				if str(node["kind"]) == kind and int(node["tier"]) == 1:
					return node
	return {}


func run(t) -> void:
	t.current = "pickup/strike classification and exact resource conservation"
	t.check(ResourceGathering.is_pickup("pebble") and ResourceGathering.is_pickup("branch"),
		"ground stones and sticks are instant pickups")
	t.check(ResourceGathering.is_pickup("bush") and ResourceGathering.is_pickup("berry"),
		"wild fiber and berries are gathered immediately")
	t.check(ResourceGathering.is_strike("tree") and ResourceGathering.is_strike("rock")
		and ResourceGathering.is_strike("ore"), "all hard resources are mined by hitting")
	t.check(not ResourceGathering.is_strike("pebble"), "small stones cannot require pickaxe hits")
	for kind in ["tree", "rock", "ore"]:
		var total: int = 0
		for hit in range(1, ResourceGathering.strikes_needed(kind) + 1):
			total += ResourceGathering.strike_yield(kind, hit)
		t.eq(total, int(Defs.node_info(kind)["amount"]), "hits cannot multiply %s yield" % kind)
	t.check(ResourceGathering.swing_cooldown(0) > ResourceGathering.swing_cooldown(1),
		"an appropriate tool gathers faster")
	t.check(ResourceGathering.swing_cooldown(4) < ResourceGathering.swing_cooldown(1),
		"upgraded tools gather faster still")

	t.current = "server-validated mining with incremental grants and shared depletion"
	var world := WorldGen.new(42)
	var tree: Dictionary = _find(world, "tree")
	t.check(not tree.is_empty(), "a tier-one harvestable tree exists")
	if tree.is_empty():
		return
	var server := GameServer.new(world, 42)
	var player = server.add_player(801, "Woodcutter")
	var x: float = float(tree["x"])
	var z: float = float(tree["z"])
	player.position = Vector3(x + 1.5, world.height_at(x + 1.5, z), z)
	var aim := Vector2(-1.0, 0.0)
	t.eq(server.cmd_resource_hit(801, int(tree["id"]), 1.0, 0.0).get("reason", ""),
		"too_far_or_not_aimed", "cannot mine a tree while aiming away")
	var starting: int = player.inventory.count("wood_1")
	var hits: int = ResourceGathering.strikes_needed("tree")
	for hit in range(1, hits + 1):
		var result: Dictionary = server.cmd_resource_hit(801, int(tree["id"]), aim.x, aim.y)
		t.check(bool(result.get("ok", false)), "validated swing %d succeeds" % hit)
		t.eq(int(result.get("hit", -1)), hit, "server tracks shared strike progress")
		if hit == 1:
			t.eq(server.cmd_resource_hit(801, int(tree["id"]), aim.x, aim.y).get("reason", ""),
				"swing_cooldown", "spamming RPC cannot mint another hit")
		if hit < hits:
			t.check(not server.depleted.has(int(tree["id"])), "tree survives partial damage")
		server.time += ResourceGathering.swing_cooldown(0) + 0.01
	t.check(server.depleted.has(int(tree["id"])), "last strike depletes the world node")
	t.check(player.inventory.count("wood_1") - starting >= int(Defs.node_info("tree")["amount"]),
		"resources are credited over multiple hits")
	t.eq(server.cmd_resource_hit(801, int(tree["id"]), aim.x, aim.y).get("reason", ""),
		"depleted", "a depleted tree cannot be farmed twice")

	t.current = "loose stones and sticks are picked up once"
	for kind in ["pebble", "branch"]:
		var pickup: Dictionary = _find(world, kind)
		t.check(not pickup.is_empty(), "%s exists as a real generated resource" % kind)
		if pickup.is_empty():
			continue
		player.position = Vector3(float(pickup["x"]),
			float(pickup["y"]), float(pickup["z"]))
		var item: String = "stone_1" if kind == "pebble" else "wood_1"
		var before: int = player.inventory.count(item)
		var picked: Dictionary = server.cmd_resource_pickup(801, int(pickup["id"]))
		t.check(bool(picked.get("ok", false)), "E pickup of %s succeeds" % kind)
		t.check(player.inventory.count(item) > before, "pickup adds to inventory")
		t.eq(server.cmd_resource_pickup(801, int(pickup["id"])).get("reason", ""),
			"depleted", "pickup cannot be collected twice")
