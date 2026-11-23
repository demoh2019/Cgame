extends RefCounted
## Fish traps need a physical shore, cost, server time and private owner rights.
const Defs = preload("res://scripts/shared/defs.gd")
const FishTrap = preload("res://scripts/shared/shore_fish_trap.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const FishingTest = preload("res://tests/test_fishing.gd")
const Persist = preload("res://scripts/server/world_persistence.gd")


func run(t) -> void:
	var world := WorldGen.new(42)
	var sim := GameServer.new(world, 43)
	var shore: Vector3 = FishingTest.new()._shore(world)
	t.current = "shore fishing traps require real crafted equipment"
	t.check(shore.is_finite(), "shore found in procedural seed")
	if not shore.is_finite():
		return
	var player = sim.add_player(541, "Fisher")
	player.position = shore
	t.check(Defs.is_item(FishTrap.ITEM_ID), "trap item registered")
	t.check(Defs.recipes().has(FishTrap.ITEM_ID), "trap crafting recipe registered")
	t.eq(sim.cmd_place_fish_trap(999).get("reason", ""), "dead",
		"unregistered caller cannot create traps")
	t.eq(sim.cmd_place_fish_trap(541).get("reason", ""), "need_rod",
		"unarmed fishing is forbidden")
	player.inventory.add("fishing_rod", 1)
	t.eq(sim.cmd_place_fish_trap(541).get("reason", ""), "not_carried",
		"missing trap cannot be placed")
	player.inventory.add(FishTrap.ITEM_ID, 2)
	var result: Dictionary = sim.cmd_place_fish_trap(541)
	t.check(bool(result.get("ok", false)), "valid shoreline trap placed")
	if not bool(result.get("ok", false)):
		return
	var trap_id: int = int(result["id"])
	t.eq(player.inventory.count(FishTrap.ITEM_ID), 1, "single trap paid")
	t.eq(sim.fish_traps.size(), 1, "server creates one net")
	t.check(world.is_water(float(sim.fish_traps[trap_id]["x"]),
			float(sim.fish_traps[trap_id]["z"])), "buoy anchored in actual water")
	t.eq(int(sim.fish_traps[trap_id]["tier"]), 1,
		"starter fishing rod cannot generate high-tier catch")
	t.eq(sim.cmd_place_fish_trap(541).get("reason", ""), "owner_limit",
		"repeated trap deployment is limited")
	t.eq(player.inventory.count(FishTrap.ITEM_ID), 1,
		"rejected deployment spends nothing")
	t.current = "fish net collection is distance- and elevation-aware"
	var placed: Dictionary = sim.fish_traps[trap_id]
	t.check(FishTrap.collectable(player.position, placed),
		"owner can collect a nearby buoy at the same height")
	var upstairs: Vector3 = player.position + Vector3(0.0, FishTrap.COLLECT_HEIGHT + 1.0, 0.0)
	t.check(not FishTrap.collectable(upstairs, placed),
		"owner cannot collect a shoreline net from another floor")
	var lower: Vector3 = player.position - Vector3(0.0, FishTrap.COLLECT_HEIGHT + 1.0, 0.0)
	t.check(not FishTrap.collectable(lower, placed),
		"owner cannot collect a buoy from far below")
	t.check(not FishTrap.collectable(Vector3(INF, 0.0, 0.0), placed),
		"nonfinite collector position is rejected")
	t.check(not FishTrap.collectable(player.position,
		{"x": NAN, "y": player.position.y, "z": player.position.z}),
		"nonfinite net coordinates cannot bypass the reach gate")
	t.check(not FishTrap.collectable(player.position,
		{"x": player.position.x, "z": player.position.z}),
		"missing net height cannot silently disable vertical reach")

	t.current = "owner-only time-gated harvest, tier and experience"
	t.eq(sim.cmd_collect_fish_trap(541, trap_id).get("reason", ""), "not_ready",
		"cannot claim before two minutes")
	var rival = sim.add_player(542, "Rival")
	rival.position = shore
	t.eq(sim.cmd_collect_fish_trap(542, trap_id).get("reason", ""), "not_owner",
		"non-owner cannot steal catch")
	var public: Array = sim.snapshot_for(542)["fish_traps"]
	t.eq(public.size(), 1, "nearby buoy replicated")
	t.check(not public[0].has("owner") and not public[0].has("owner_account"),
		"account and peer identifiers do not leak")
	t.check(not bool(public[0].get("own", true)),
		"rival sees the net but cannot target it")
	var owned: Array = sim.snapshot_for(541)["fish_traps"]
	t.check(owned.size() == 1 and bool(owned[0].get("own", false)),
		"owner receives a private selectable net flag")
	t.check(not Persist.capture(sim).has("fish_traps"),
		"temporary fishing nets are not persistent structures")
	player.position = shore + Vector3(100.0, 0.0, 0.0)
	t.eq(sim.cmd_collect_fish_trap(541, trap_id).get("reason", ""), "out_of_range",
		"faraway owner cannot remotely cash the net")
	player.position = shore
	sim.time = float(sim.fish_traps[trap_id]["ready_at"]) - 0.1
	t.eq(sim.cmd_collect_fish_trap(541, trap_id).get("reason", ""), "not_ready",
		"timer threshold is exact")
	sim.time += 0.1
	var xp_before: int = int(player.progression.gathering_xp["fishing"])
	var catch: Dictionary = sim.cmd_collect_fish_trap(541, trap_id)
	t.check(bool(catch.get("ok", false)), "mature trap can be claimed")
	t.eq(int(catch.get("count", 0)), FishTrap.COUNT, "fixed, bounded catch")
	t.eq(player.inventory.count("raw_fish"), FishTrap.COUNT,
		"two fish earned once")
	t.eq(int(player.progression.gathering_xp["fishing"]) - xp_before,
		FishTrap.COUNT * player.progression.GATHER_XP_PER_ITEM,
		"only delivered fish award skill XP")
	t.eq(sim.cmd_collect_fish_trap(541, trap_id).get("reason", ""), "no_trap",
		"duplicate claim denied")
	t.check(sim.fish_traps.is_empty(), "claimed net disappears")
	t.current = "corrupt temporary traps are never replicated"
	var malformed: Dictionary = {
		1001: {"id": 1001, "x": NAN, "y": 0.0, "z": 0.0,
			"expires": sim.time + 100.0, "ready_at": sim.time + 10.0, "tier": 1},
		1002: {"id": 1002, "x": shore.x, "y": INF, "z": shore.z,
			"expires": sim.time + 100.0, "ready_at": sim.time + 10.0, "tier": 1},
		1003: {"id": 1003, "x": shore.x, "y": 0.0, "z": shore.z,
			"expires": sim.time + 100.0, "ready_at": NAN, "tier": 1},
	}
	t.eq(FishTrap.visible(malformed, shore, sim.time, 10.0), [],
		"invalid geometry and timers cannot leak into snapshots")

	t.current = "second trap and hard expiry"
	var second: Dictionary = sim.cmd_place_fish_trap(541)
	t.check(bool(second.get("ok", false)), "second paid net after first claim")
	if not bool(second.get("ok", false)):
		return
	var new_id: int = int(second["id"])
	sim.time = float(sim.fish_traps[new_id]["expires"]) + 0.1
	t.eq(sim.cmd_collect_fish_trap(541, new_id).get("reason", ""), "no_trap",
		"expired catch can never be collected")
	sim._tick_world(0.1)
	t.check(sim.fish_traps.is_empty(), "expired net garbage-collected")
