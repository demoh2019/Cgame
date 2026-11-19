extends RefCounted
## Real server-issued craftable distraction and infected investigation tests.

const Defs = preload("res://scripts/shared/defs.gd")
const NoiseDecoy = preload("res://scripts/shared/noise_decoy.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


func _origin(world) -> Vector3:
	for x in range(140, 300, 16):
		for z in range(140, 300, 16):
			var at := Vector3(float(x), world.height_at(float(x), float(z)), float(z))
			if not NoiseDecoy.landing(world, at, Vector2.RIGHT).is_empty():
				return at
	return Vector3.ZERO


func run(t) -> void:
	t.current = "crafted item and server-computed world landing"
	t.eq(str(Defs.item("noise_decoy").get("kind", "")), "decoy",
			"noise maker is a legitimate item")
	var recipe: Dictionary = Defs.recipes().get("noise_decoy", {})
	t.check(not recipe.is_empty(), "survivor can craft noise maker from resources")
	var world := WorldGen.new(721)
	var server := GameServer.new(world, 721)
	var actor = server.add_player(811, "Scout")
	var origin: Vector3 = _origin(world)
	t.check(origin != Vector3.ZERO, "found open wilderness for thrown lure")
	if origin == Vector3.ZERO:
		return
	actor.position = origin
	t.eq(server.cmd_throw_decoy(99, 1.0, 0.0).get("reason"), "dead",
			"nonexistent peer cannot create a lure")
	t.eq(server.cmd_throw_decoy(811, NAN, 0.0).get("reason"), "invalid_landing",
			"nonfinite direction rejected")
	t.eq(server.cmd_throw_decoy(811, INF, 0.0).get("reason"), "invalid_landing",
			"infinite direction rejected")
	t.eq(server.cmd_throw_decoy(811, 0.0, 0.0).get("reason"), "invalid_landing",
			"zero direction rejected")
	t.eq(server.cmd_throw_decoy(811, 1.0, 0.0).get("reason"), "not_carried",
			"crafted lure must really be in server inventory")
	t.eq(server.decoys.size(), 0, "rejected calls never create world sound")

	t.current = "atomic cost, short cooldown and private player ownership"
	actor.inventory.add("noise_decoy", 3)
	var before: int = actor.inventory.count("noise_decoy")
	var result: Dictionary = server.cmd_throw_decoy(811, 1.0, 0.0)
	t.check(result.get("ok", false), "valid item throw accepted")
	if not result.get("ok", false):
		return
	var decoy_id: int = int(result["id"])
	t.eq(actor.inventory.count("noise_decoy"), before - 1, "exactly one decoy spent")
	t.eq(server.decoys.size(), 1, "one temporary lure exists")
	t.check(actor.dirty_inventory and actor.dirty_character, "account changes marked dirty")
	t.eq(server.cmd_throw_decoy(811, 1.0, 0.0).get("reason"), "cooldown",
			"spam attempts cannot consume items")
	t.eq(actor.inventory.count("noise_decoy"), before - 1, "rejected spam costs nothing")
	var state: Dictionary = server.snapshot_for(811)
	t.eq(state["decoys"].size(), 1, "networked lure visible near survivor")
	t.check(not state["decoys"][0].has("owner"), "peer and account IDs remain private")
	t.check(not state["decoys"][0].has("expires"), "absolute world deadline not replicated")
	t.near(float(state["decoys"][0]["remaining"]), NoiseDecoy.DURATION,
			0.001, "client receives bounded time to live")
	var far = server.add_player(812, "Remote")
	far.position = Vector3(-500.0, world.height_at(-500.0, -500.0), -500.0)
	t.eq(server.snapshot_for(812)["decoys"].size(), 0,
			"far-away client cannot see unrelated lure")
	var packet: Dictionary = {}
	for event in server.events:
		if event.get("type") == "decoy_thrown":
			packet = event
			break
	t.check(not packet.is_empty(), "authoritative decoy sound event exists")
	var net := Net.new()
	net.role = "server"
	net.sim = server
	t.check(net._event_visible_to(packet, 811), "nearby survivor receives sound event")
	t.check(not net._event_visible_to(packet, 812),
			"sound event is hidden from distant clients")
	net.free()

	t.current = "idle infected investigate without acquiring a fake player target"
	var lure: Dictionary = server.decoys[decoy_id]
	var at := Vector3(float(lure["x"]) + 19.0,
			world.height_at(float(lure["x"]) + 19.0, float(lure["z"])),
			float(lure["z"]))
	var infected := Zombie.new(server.new_id(), "walker", at)
	server.zombies[infected.id] = infected
	t.check(NoiseDecoy.is_audible(lure, at, server.time),
			"inactive infected hears deployed lure")
	t.check(not NoiseDecoy.is_audible(lure,
			Vector3(NAN, 0.0, 0.0), server.time), "invalid auditory position rejected")
	server.tick_count = 5
	server._tick_zombies(0.05)
	t.eq(infected.state, Zombie.State.INVESTIGATE,
			"server directs idle infected to distraction site")
	t.eq(infected.target_id, -1, "decoy does not impersonate a real survivor")
	t.check(infected.last_known_target.distance_to(
			Vector2(float(lure["x"]), float(lure["z"]))) < 0.01,
			"investigation destination is authoritative impact position")

	t.current = "active combat threat and raid enemies ignore decoy"
	var chasing := Zombie.new(server.new_id(), "walker", at)
	chasing.state = Zombie.State.CHASE
	chasing.target_id = 811
	t.check(not chasing.investigate_decoy(Vector2(float(lure["x"]), float(lure["z"]))),
			"decoy cannot override active chase")
	t.eq(chasing.target_id, 811, "current enemy target unchanged")
	var boss := Zombie.new(server.new_id(), "brute", at)
	boss.raid_boss = true
	t.check(not boss.investigate_decoy(Vector2(float(lure["x"]), float(lure["z"]))),
			"raid boss is immune to cheap distractions")

	t.current = "expiry and no permanent entities or refunds"
	var end_time: float = float(lure["expires"])
	t.check(not NoiseDecoy.is_audible(lure, at, end_time),
			"exact expiry stops audible noise")
	server.time = end_time + 0.05
	server._tick_world(0.05)
	t.eq(server.decoys.size(), 0, "temporary world lure is erased after expiry")
	t.eq(server.snapshot_for(811)["decoys"].size(), 0,
			"expired lure disappears from client snapshots")
	t.eq(actor.inventory.count("noise_decoy"), before - 1,
			"expiry does not mint refunded supplies")
	t.check(not server.character_data(actor).has("decoys"),
			"ephemeral noise lures never persist in account data")
