extends RefCounted
## Regression for server-only, bounded ordinary-PvE bag collection.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Sweep = preload("res://scripts/shared/loot_sweep.gd")
const Net = preload("res://scripts/shared/net.gd")
const GameClient = preload("res://scripts/client/game_client.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	var world := WorldGen.new(246)
	var server := GameServer.new(world, 246)
	server.zombies.clear()
	var owner = server.add_player(801, "Owner")
	var stranger = server.add_player(802, "Stranger")
	owner.position = _at(world, 201.0, 200.0)
	stranger.position = _at(world, 202.0, 200.0)

	t.current = "nearby PvE candidates are ordered and reserved"
	var a: int = server._make_bag(owner.position + Vector3(1.0, 0, 0), {"wood_1": 2}, owner.id)
	var b: int = server._make_bag(owner.position + Vector3(-1.0, 0, 0), {"fiber_1": 3}, owner.id)
	var c: int = server._make_bag(owner.position + Vector3(2.0, 0, 0), {"scrap": 4}, owner.id)
	var far: int = server._make_bag(owner.position + Vector3(9.0, 0, 0), {"ore_1": 3}, owner.id)
	var locked: int = server._make_bag(owner.position, {"bar_1": 5}, stranger.id)
	var pvp: int = server._make_bag(owner.position, {"club_1": 1})
	var raid: int = server._make_bag(owner.position, {"infected_core": 2}, owner.id)
	server.bags[raid]["raid_reserved_until"] = server.time + 30.0
	var supply: int = server._make_bag(owner.position, {"water_bottle": 2}, owner.id)
	server.bags[supply]["supply_drop"] = true
	var death: int = server._make_bag(owner.position, {"jacket_1": 1}, owner.id)
	server.bags[death]["death_recovery_owner"] = "private"
	t.eq(Sweep.candidates(server.bags, owner.position, owner, server.time), [a, b, c],
		"nearer bags first, equal distance by stable ID, no protected rewards")
	t.eq(Sweep.candidates(server.bags, owner.position, stranger, server.time), [locked],
		"other survivors only see their own reachable ordinary bags")
	t.eq(Sweep.candidates(server.bags, Vector3(NAN, 0, 0), owner, server.time), [],
		"invalid position has no eligible bags")
	t.eq(Sweep.candidates(server.bags, owner.position, owner, INF), [],
		"invalid server time has no eligible bags")

	t.current = "corrupt PvE bags cannot appear in the nearby auto-loot list"
	var malformed: Dictionary = {}
	var ordinary: Dictionary = server.bags[a].duplicate(true)
	ordinary["id"] = 1001
	ordinary["x"] = owner.position.x + 0.25
	ordinary["z"] = owner.position.z
	malformed[1001] = ordinary
	var nonnumeric_x: Dictionary = ordinary.duplicate(true)
	nonnumeric_x["id"] = 1002
	nonnumeric_x["x"] = str(ordinary["x"])
	malformed[1002] = nonnumeric_x
	var nonnumeric_expiry: Dictionary = ordinary.duplicate(true)
	nonnumeric_expiry["id"] = 1003
	nonnumeric_expiry["expires"] = "999999"
	malformed[1003] = nonnumeric_expiry
	var invalid_id: Dictionary = ordinary.duplicate(true)
	invalid_id["id"] = "1004"
	malformed[1004] = invalid_id
	var squared_overflow: Dictionary = ordinary.duplicate(true)
	squared_overflow["id"] = 1005
	squared_overflow["x"] = 1.0e30
	malformed[1005] = squared_overflow
	t.eq(Sweep.candidates(malformed, owner.position, owner, server.time), [1001],
		"only a genuinely nearby numeric server bag enters the bounded selection")
	t.eq(Sweep.candidates(malformed, owner.position, owner, -1.0), [],
		"negative simulated time does not permit automatic collection")

	t.current = "dense loot piles choose exact nearest five without a full sort"
	var crowded: Dictionary = {}
	for i in 80:
		var bag_copy: Dictionary = server.bags[a].duplicate(true)
		var bag_id: int = 2000 + i
		bag_copy["id"] = bag_id
		bag_copy["x"] = owner.position.x + float(80 - i) * 0.01
		bag_copy["z"] = owner.position.z
		crowded[bag_id] = bag_copy
	var equal_nearest: Dictionary = crowded[2079].duplicate(true)
	equal_nearest["id"] = 1
	crowded[1] = equal_nearest
	var slightly_farther: Dictionary = equal_nearest.duplicate(true)
	slightly_farther["id"] = 0
	slightly_farther["x"] = owner.position.x + 0.010001
	crowded[0] = slightly_farther
	t.eq(Sweep.candidates(crowded, owner.position, owner, server.time),
		[1, 2079, 0, 2078, 2077],
		"equal distances use ID, but a slightly nearer drop beats lower IDs")

	t.current = "dense drops keep nearest five with deterministic ID ties"
	var dense: Dictionary = {}
	var reference: Array[Dictionary] = []
	for i in 260:
		var id: int = 10000 + 259 - i # Inverse insertion order checks stable ID ties.
		var ox: float = float((i * 17) % 31 - 15) * 0.14
		var oz: float = float((i * 19) % 29 - 14) * 0.13
		dense[id] = {"id": id, "x": owner.position.x + ox,
			"z": owner.position.z + oz, "items": {"fiber_1": 1},
			"allowed_tokens": [], "reserved_until": 0.0,
			"expires": server.time + 20.0}
		var bag_at := Vector2(float(dense[id]["x"]), float(dense[id]["z"]))
		var distance: float = Vector2(owner.position.x, owner.position.z).distance_squared_to(bag_at)
		if distance <= Sweep.RADIUS * Sweep.RADIUS:
			reference.append({"id": id, "distance": distance})
	reference.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if is_equal_approx(float(left["distance"]), float(right["distance"])):
			return int(left["id"]) < int(right["id"])
		return float(left["distance"]) < float(right["distance"]))
	var expected: Array[int] = []
	for i in mini(reference.size(), Sweep.MAX_BAGS):
		expected.append(int(reference[i]["id"]))
	t.eq(Sweep.candidates(dense, owner.position, owner, server.time), expected,
		"bounded nearest search agrees with full sorting of a crowded drop area")
	var tied: Dictionary = {}
	for id in [21, 15, 40, 8, 31, 2, 17]:
		tied[id] = {"id": id, "x": owner.position.x + 1.0,
			"z": owner.position.z, "items": {"fiber_1": 1},
			"allowed_tokens": [], "reserved_until": 0.0,
			"expires": server.time + 20.0}
	t.eq(Sweep.candidates(tied, owner.position, owner, server.time), [2, 8, 15, 17, 21],
		"equidistant bags use stable server IDs even when inserted out of order")
	dense[99999] = {"id": 99999, "x": NAN, "z": owner.position.z,
		"items": {"fiber_1": 1}, "allowed_tokens": [], "expires": server.time + 20.0}
	t.eq(Sweep.candidates(dense, owner.position, owner, server.time), expected,
		"invalid drop coordinates cannot contaminate the top-five ranking")

	t.current = "one command uses actual item transfers and preserves exclusions"
	var got: Dictionary = server.cmd_loot_sweep(owner.id)
	t.check(got.get("ok", false), "owner can collect eligible drops")
	t.eq(got.get("items", -1), 9, "exact items moved")
	t.eq(got.get("bags", -1), 3, "exact ordinary bags opened")
	t.eq(got.get("emptied", -1), 3, "exact ordinary bags removed")
	t.eq(owner.inventory.count("wood_1"), 2, "no duplication of wood")
	t.eq(owner.inventory.count("fiber_1"), 3, "no duplication of fiber")
	t.eq(owner.inventory.count("scrap"), 4, "no duplication of scrap")
	for id in [a, b, c]:
		t.check(not server.bags.has(id), "empty bag is removed")
	for id in [far, locked, pvp, raid, supply, death]:
		t.check(server.bags.has(id), "other bags remain untouched")
	t.eq(server.cmd_loot_sweep(owner.id).get("reason", ""), "cooldown",
		"same-second repeated RPC is throttled")
	server.time += Sweep.COOLDOWN
	t.eq(server.cmd_loot_sweep(owner.id).get("reason", ""), "nothing_to_sweep",
		"empty sweep cannot create loot")

	t.current = "full inventory keeps original world bag"
	owner.inventory = Inventory.new(1)
	owner.inventory.add("stone_1", 100)
	var overflow: int = server._make_bag(owner.position, {"wood_1": 8}, owner.id)
	server.time += Sweep.COOLDOWN
	t.eq(server.cmd_loot_sweep(owner.id).get("reason", ""), "inventory_full",
		"no phantom item transfer")
	t.eq(server.bags[overflow]["items"], {"wood_1": 8},
		"full backpack leaves complete original bag")
	owner.inventory = Inventory.new()
	server.time += Sweep.COOLDOWN
	t.check(server.cmd_loot_sweep(owner.id).get("ok", false),
		"bag can be collected after freeing inventory")
	t.eq(owner.inventory.count("wood_1"), 8, "no loss on retry")

	t.current = "bounded batch and real cooldown lifecycle"
	for i in range(8):
		server._make_bag(owner.position + Vector3(float(i) * 0.1, 0, 0), {"fiber_1": 1}, owner.id)
	t.eq(Sweep.candidates(server.bags, owner.position, owner, server.time).size(), 5,
		"one sweep is limited to five bags")
	server.time += Sweep.COOLDOWN
	t.eq(server.cmd_loot_sweep(owner.id).get("bags", -1), 5,
		"first sweep claims at most five")
	server.time += Sweep.COOLDOWN
	t.eq(server.cmd_loot_sweep(owner.id).get("bags", -1), 3,
		"another sweep is needed for remaining bags")
	t.eq(owner.inventory.count("fiber_1"), 8, "eight real items total")

	t.current = "reused peer cannot inherit cooldown or loot rights"
	var newcomer = server.add_player(803, "Newcomer")
	newcomer.position = owner.position
	var protected: int = server._make_bag(newcomer.position, {"scrap": 3}, newcomer.id)
	server.remove_player(owner.id)
	var replacement = server.add_player(801, "Replacement")
	replacement.position = newcomer.position
	t.eq(server.cmd_loot_sweep(replacement.id).get("reason", ""), "nothing_to_sweep",
		"new session has no stale cooldown or access to prior loot")
	t.eq(server.bags[protected]["items"], {"scrap": 3},
		"other account's reserved goods cannot be swept")
	var net := Net.new()
	t.check(net.has_method("c_loot_sweep"), "authenticated zero-argument RPC is installed")
	var client := GameClient.new(net)
	t.check(client.has_method("loot_sweep"), "live client exposes the sweep action")
	net.free()
