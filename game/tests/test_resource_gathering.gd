extends RefCounted
## Client and server use the same Rust-like pickup/strike rules.

const Defs = preload("res://scripts/shared/defs.gd")
const ResourceGathering = preload("res://scripts/shared/resource_gathering.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const GameClient = preload("res://scripts/client/game_client.gd")


class FakeNet:
	extends RefCounted
	var client


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

	t.current = "resource reach stays bounded for invalid model data and aim"
	var large_rock: Dictionary = {"kind": "rock", "x": 3.3, "z": 0.0, "radius": 1.5}
	t.check(ResourceGathering.aimed_at(Vector3.ZERO, large_rock, Vector2.RIGHT, 2.0),
		"large mineable rock is reachable at the edge of its model")
	t.check(not ResourceGathering.aimed_at(Vector3.ZERO, large_rock, Vector2.LEFT, 2.0),
		"looking away cannot mine a distant model")
	t.check(not ResourceGathering.aimed_at(Vector3.ZERO, large_rock, Vector2.ZERO, 2.0),
		"zero aim cannot bypass a resource reach check")
	t.check(not ResourceGathering.aimed_at(Vector3.ZERO, large_rock, Vector2.RIGHT, NAN),
		"invalid reach cannot grant unlimited interaction")
	var malformed_rock: Dictionary = large_rock.duplicate()
	malformed_rock["radius"] = NAN
	t.eq(ResourceGathering.reach_margin(malformed_rock), 0.0,
		"nonfinite model radius does not expand interaction range")
	t.check(not ResourceGathering.aimed_at(Vector3.ZERO, malformed_rock, Vector2.RIGHT, 2.0),
		"malformed model bounds cannot extend mining reach")
	malformed_rock["radius"] = -10.0
	t.eq(ResourceGathering.reach_margin(malformed_rock), 0.0,
		"negative model radius is ignored")

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

	t.current = "real modeled rock strikes preserve shared collisions"
	var modeled: Dictionary = {}
	for cx in range(2, 10):
		if not modeled.is_empty():
			break
		for cz in range(2, 10):
			if not modeled.is_empty():
				break
			for candidate in world.chunk(Vector2i(cx, cz))["nodes"]:
				if str(candidate["kind"]) == "rock" and candidate.has("stone_model") and int(candidate["tier"]) == 1:
					modeled = candidate
					break
	t.check(not modeled.is_empty(), "tier-one model boulder exists for Rust-style mining")
	if not modeled.is_empty():
		var rock_x: float = float(modeled["x"])
		var rock_z: float = float(modeled["z"])
		var rock_id: int = int(modeled["id"])
		player.position = Vector3(rock_x + 1.5,
			world.height_at(rock_x + 1.5, rock_z), rock_z)
		var blocked := false
		for obstacle in world.blockers_near(rock_x, rock_z, 0.5):
			if int(obstacle.get("id", -1)) == rock_id:
				blocked = true
		t.check(blocked, "solid stone model blocks movement before mining")
		var stone_before: int = player.inventory.count("stone_1")
		var total_hits: int = ResourceGathering.strikes_needed("rock")
		for strike in range(1, total_hits + 1):
			var result: Dictionary = server.cmd_resource_hit(801, rock_id, -1.0, 0.0)
			t.check(bool(result.get("ok", false)), "real modeled rock accepts hit %d" % strike)
			t.eq(int(result.get("hit", -1)), strike, "model rock shares authoritative strike progress")
			if strike < total_hits:
				t.check(not server.depleted.has(rock_id), "partially mined rock is still present")
			server.time += ResourceGathering.swing_cooldown(0) + 0.01
		t.check(player.inventory.count("stone_1") >= stone_before + 4,
			"strikes give real stone resources")
		t.check(server.depleted.has(rock_id), "last strike depletes modeled boulder")
		var ghost := false
		for obstacle in world.blockers_near(rock_x, rock_z, 0.5):
			if int(obstacle.get("id", -1)) == rock_id:
				ghost = true
		t.check(not ghost, "depleted model has no invisible collision")
		server.time += float(Defs.node_info("rock")["respawn"]) + 1.0
		server.tick(0.05)
		var restored := false
		for obstacle in world.blockers_near(rock_x, rock_z, 0.5):
			if int(obstacle.get("id", -1)) == rock_id:
				restored = true
		t.check(restored, "model boulder collision returns with its respawn")


	t.current = "rotating weak point is deterministic, visible and has a strict aim check"
	var initial_spot: Vector3 = ResourceGathering.weakspot_position(tree, 0)
	var repeat_spot: Vector3 = ResourceGathering.weakspot_position(tree, 0)
	var moved_spot: Vector3 = ResourceGathering.weakspot_position(tree, 1)
	t.eq(initial_spot, repeat_spot, "same world node and progress produce the same target")
	t.check(initial_spot.distance_to(moved_spot) > 0.15,
		"gold marker changes position after each real hit")
	t.check(initial_spot.y > float(tree["y"]), "weak point appears on the model, not below the ground")
	var huge_id_node: Dictionary = tree.duplicate(true)
	huge_id_node["id"] = 9223372036854770000
	var wrapped_id_node: Dictionary = huge_id_node.duplicate(true)
	wrapped_id_node["id"] = posmod(int(huge_id_node["id"]), 360)
	t.eq(ResourceGathering.weakspot_position(huge_id_node, 2147483647),
		ResourceGathering.weakspot_position(wrapped_id_node, 2147483647),
		"large stable resource IDs use overflow-safe deterministic weak point rotation")
	var perfect_server := GameServer.new(world, 43)
	var accurate_player = perfect_server.add_player(811, "Miner")
	accurate_player.position = Vector3(x + 1.5, world.height_at(x + 1.5, z), z)
	var aim_spot: Vector2 = Vector2(initial_spot.x - accurate_player.position.x,
		initial_spot.z - accurate_player.position.z).normalized()
	t.check(ResourceGathering.precise_strike(accurate_player.position, tree, aim_spot, 0),
		"aimed direction toward the model's weak point qualifies")
	t.check(not ResourceGathering.precise_strike(
		accurate_player.position, tree, -aim_spot, 0),
		"aiming away cannot claim the resource bonus")
	var weak_result: Dictionary = perfect_server.cmd_resource_hit(
		811, int(tree["id"]), aim_spot.x, aim_spot.y)
	t.check(bool(weak_result.get("ok", false)), "valid marked strike is accepted")
	t.check(bool(weak_result.get("precise", false)), "only server decides whether hit is precise")
	t.eq(accurate_player.inventory.count("wood_1"),
		ResourceGathering.strike_yield("tree", 1) + 1,
		"perfect strike grants exactly one additional resource")
	t.eq(perfect_server.cmd_resource_hit(
		811, int(tree["id"]), aim_spot.x, aim_spot.y).get("reason", ""),
		"swing_cooldown", "replay of a precision hit cannot mint extra wood")
	var seen_progress: bool = false
	for item in perfect_server.snapshot_for(811).get("resource_hits", []):
		if int(item["id"]) == int(tree["id"]):
			seen_progress = int(item["hits"]) == 1
	t.check(seen_progress, "joining and nearby players receive server strike progress")

	t.current = "regular swings remain valid without sweet spot rewards"
	perfect_server.time += ResourceGathering.swing_cooldown(0) + 0.01
	var ordinary_aim := Vector2(-0.8, 0.6).normalized()
	var ordinary_result: Dictionary = perfect_server.cmd_resource_hit(
		811, int(tree["id"]), ordinary_aim.x, ordinary_aim.y)
	t.check(bool(ordinary_result.get("ok", false)), "ordinary swing still mines the tree")
	t.check(not bool(ordinary_result.get("precise", false)),
		"missing golden marker gives no bonus")
	t.eq(accurate_player.inventory.count("wood_1"),
		ResourceGathering.strike_yield("tree", 1) + 1
		+ ResourceGathering.strike_yield("tree", 2),
		"ordinary strike adds only its base resource amount")


	t.current = "held-E selector ignores trees, depletion and in-flight pickups"
	var picker = GameClient.new(FakeNet.new())
	picker.world = world
	var loose: Dictionary = _find(world, "branch")
	t.check(not loose.is_empty(), "pickup probe exists in generated world")
	if not loose.is_empty():
		var at_pickup := Vector3(float(loose["x"]), float(loose["y"]), float(loose["z"]))
		var loose_id: int = int(loose["id"])
		var chosen: Dictionary = picker.nearest_pickup_node(at_pickup, 0.1)
		t.eq(int(chosen.get("id", -1)), loose_id,
			"held-E finds a nearby real pickup with no other interaction kind")
		var pending: Dictionary = {}
		pending[loose_id] = true
		t.check(picker.nearest_pickup_node(at_pickup, 0.1, pending).is_empty(),
			"a pending request cannot be sent repeatedly while awaiting the server")
		picker.depleted[loose_id] = true
		t.check(picker.nearest_pickup_node(at_pickup, 0.1).is_empty(),
			"depleted loose resources are ignored")
	if not tree.is_empty():
		var at_tree := Vector3(float(tree["x"]), float(tree["y"]), float(tree["z"]))
		var tree_choice: Dictionary = picker.nearest_pickup_node(at_tree, 0.05)
		t.check(tree_choice.is_empty() or int(tree_choice.get("id", -1)) != int(tree["id"]),
			"holding E never turns into automatic tree chopping")

	t.current = "render revisions distinguish mining damage from world disappearance"
	var original_visibility_revision: int = picker.world_state_revision
	var original_damage_revision: int = picker.resource_damage_revision
	var sample_id: int = int(tree["id"])
	var progress_event: Dictionary = {"type": "gathered", "strike": true,
		"node": sample_id, "hit": 1, "final": false}
	picker.on_events([progress_event])
	t.eq(picker.world_state_revision, original_visibility_revision,
		"ordinary resource damage must not trigger a full chunk geometry rescan")
	t.eq(picker.resource_damage_revision, original_damage_revision + 1,
		"real strike invalidates the inexpensive per-instance tint")
	picker.on_events([progress_event])
	t.eq(picker.resource_damage_revision, original_damage_revision + 1,
		"duplicate strike events do not cause redundant GPU updates")
	picker.on_events([{"type": "gathered", "strike": true,
		"node": sample_id, "hit": 2, "final": false}])
	t.eq(picker.resource_damage_revision, original_damage_revision + 2,
		"the next strike updates the damage marker and tint")
	picker.on_events([{"type": "gathered", "strike": true,
		"node": sample_id, "hit": 3, "final": true}])
	t.check(not picker.resource_hits.has(sample_id), "depletion clears stale resource damage")
	t.eq(picker.resource_damage_revision, original_damage_revision + 3,
		"depletion clears damaged instance tint once")
