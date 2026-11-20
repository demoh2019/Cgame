extends RefCounted
## Regression coverage for timed server-authoritative public PvP supply crates.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const SupplyDrops = preload("res://scripts/shared/supply_drops.gd")
const LootLabel = preload("res://scripts/shared/loot_label.gd")


func run(t) -> void:
	t.current = "supply drop reward bounds"
	var loot_rng := RandomNumberGenerator.new()
	loot_rng.seed = 37
	var red_loot: Dictionary = SupplyDrops.loot_for_zone(2, loot_rng)
	t.eq(int(red_loot["silver"]), 120, "red zone pays a T3 supply reward")
	for id in red_loot:
		t.check(Defs.is_item(str(id)), "all supply contents exist in the item database: %s" % id)
		t.check(int(red_loot[id]) > 0 and int(red_loot[id]) <= Defs.stack_size(str(id)),
			"each reward fits a normal stack: %s" % id)
	var black_loot: Dictionary = SupplyDrops.loot_for_zone(3, loot_rng)
	t.check(black_loot.has("bar_4") and black_loot.has("cloth_4"),
		"black-zone supplies use T4 materials")

	t.current = "server time and safe zones"
	var world := WorldGen.new(17)
	var server := GameServer.new(world, 17)
	var player = server.add_player(93, "Supply Scout")
	server.time = SupplyDrops.INTERVAL_SECONDS
	server._tick_world(0.0)
	t.eq(server.bags.size(), 0, "no supply appears if everyone is in the safe hub")
	t.eq(server.next_supply_drop_at, SupplyDrops.INTERVAL_SECONDS + SupplyDrops.RETRY_SECONDS,
		"empty-server attempt backs off instead of spawning a free cache")
	t.eq(SupplyDrops.site_near(world, player.position, loot_rng).size(), 0,
		"site selection refuses the safe hub")

	var anchor := Vector2.ZERO
	for i in 72:
		var candidate := Vector2.from_angle(float(i) * TAU / 72.0) * 800.0
		if not world.is_water(candidate.x, candidate.y) and world.normal_at(candidate.x, candidate.y).y > 0.85:
			anchor = candidate
			break
	t.check(anchor != Vector2.ZERO, "a traversable red-zone test site exists")
	if anchor == Vector2.ZERO:
		return
	player.position = Vector3(anchor.x, world.height_at(anchor.x, anchor.y), anchor.y)
	server.time = server.next_supply_drop_at - 0.01
	server._tick_world(0.0)
	t.eq(server.bags.size(), 0, "a supply cannot spawn before its deadline")
	server.time = server.next_supply_drop_at
	server._tick_world(0.0)
	t.eq(server.bags.size(), 1, "one public cache spawns for an eligible survivor")
	if server.bags.is_empty():
		return
	var bag_id: int = int(server.bags.keys()[0])
	var bag: Dictionary = server.bags[bag_id]
	t.check(bool(bag.get("supply_drop", false)), "the drop is marked for clients")
	t.check(not bag.has("allowed_tokens"), "the drop is public, not party-reserved")
	t.eq(world.zone_at(float(bag["x"]), float(bag["z"])), 2,
		"loot lands in the red PvP zone")
	var distance: float = Vector2(player.position.x, player.position.z).distance_to(
		Vector2(float(bag["x"]), float(bag["z"])))
	t.check(distance >= SupplyDrops.MIN_DISTANCE and distance <= SupplyDrops.MAX_DISTANCE + 0.01,
		"cache arrives within the player's nearby visibility radius")
	t.eq(float(bag["expires"]), server.time + SupplyDrops.LIFETIME_SECONDS,
		"public cache expires after a bounded interval")
	var view: Dictionary = server.snapshot_for(93)
	var found := false
	for visible in view["bags"]:
		if int(visible["id"]) == bag_id:
			found = bool(visible.get("supply_drop", false)) and bool(visible["can_loot"])
	t.check(found, "nearby clients see a clearly marked, lootable supply crate")
	t.eq(LootLabel.for_bag({"supply_drop": true}), "SUPPLY DROP - public",
		"the world label distinguishes supply from ordinary death loot")

	var announced := false
	for event in server.drain_events():
		if event.get("type", "") == "supply_drop":
			announced = int(event.get("id", -1)) == bag_id
	t.check(announced, "a world announcement is emitted after server creation")

	player.position = Vector3(float(bag["x"]), float(bag["y"]), float(bag["z"]))
	var result: Dictionary = server.cmd_loot(93, bag_id)
	t.check(bool(result.get("ok", false)), "the legitimate nearby player can loot it")
	t.check(not server.bags.has(bag_id), "a fully looted supply cache is removed")
	t.check(player.inventory.count("silver") >= 120, "supply was actually transferred")
	server._tick_world(0.0)
	t.eq(server.bags.size(), 0, "checking the same tick cannot duplicate the reward")
