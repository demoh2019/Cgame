extends RefCounted
## Server-owned PvPvE supply objective: guards, snapshots, anti-bypass, release.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const SupplyDrops = preload("res://scripts/shared/supply_drops.gd")
const LootLabel = preload("res://scripts/shared/loot_label.gd")


func run(t) -> void:
	t.current = "server-authoritative contested supply cache"
	var world := WorldGen.new(73)
	var server := GameServer.new(world, 73)
	var player = server.add_player(14, "Guard Tester")
	var cache_id: int = server._make_bag(player.position, {"silver": 12})
	var bag: Dictionary = server.bags[cache_id]
	bag["supply_drop"] = true
	var guard_id: int = server.new_id()
	var enemy = Zombie.new(guard_id, "runner", player.position + Vector3(12.0, 0.0, 0.0), -1)
	enemy.supply_cache_id = cache_id
	server.zombies[guard_id] = enemy
	bag["supply_guard_ids"] = [guard_id]

	var first: Dictionary = server.cmd_loot(14, cache_id)
	t.eq(first.get("reason", ""), "guards_alive", "alive escort blocks pickup")
	t.eq(int(first.get("remaining", 0)), 1, "client sees only a public guard count")
	t.eq(player.inventory.count("silver"), 0, "denied pickup cannot grant currency")
	var snapshot: Dictionary = server.snapshot_for(14)
	var found := false
	for entry in snapshot["bags"]:
		if int(entry["id"]) == cache_id:
			found = true
			t.check(not bool(entry["can_loot"]), "guarded cache cannot be claimed")
			t.eq(int(entry.get("guards_remaining", -1)), 1, "one guard is replicated")
			t.check(not entry.has("supply_guard_ids"), "private guard IDs stay on server")
	t.check(found, "guarded cache is visible in the nearby snapshot")
	t.eq(LootLabel.for_bag({"supply_drop": true, "guards_remaining": 1}),
		"SUPPLY DROP - guarded (1)", "label displays the remaining threat")

	t.current = "cannot bypass by leaving the event"
	player.position = Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	# Simulate leaving the cache behind after it spawns outside the safe hub.
	enemy.position = Vector3(800.0, world.height_at(800.0, 0.0), 0.0)
	server._manage_zombie_population()
	t.check(server.zombies.has(guard_id), "living escort is not unloaded while the cache exists")
	t.eq(SupplyDrops.living_guards(bag, server.zombies), 1, "lock remains active")

	t.current = "defeat unlocks public loot"
	player.position = Vector3(float(bag["x"]), float(bag["y"]), float(bag["z"]))
	t.check(enemy.take_damage(100000.0), "server-authorized combat kills the guard")
	t.eq(SupplyDrops.living_guards(bag, server.zombies), 0, "death releases the seal")
	t.eq(LootLabel.for_bag({"supply_drop": true, "guards_remaining": 0}),
		"SUPPLY DROP - public", "cache becomes public")
	var acquired: Dictionary = server.cmd_loot(14, cache_id)
	t.check(bool(acquired.get("ok", false)), "unguarded cache can be claimed")
	t.eq(player.inventory.count("silver"), 12, "loot transfers only after combat")
	t.check(not server.bags.has(cache_id), "looted cache is removed")
	t.eq(SupplyDrops.living_guards({"supply_drop": false, "supply_guard_ids": [guard_id]},
		server.zombies), 0, "ordinary loot is never gated by a guard")
