extends RefCounted
## Ruin awakening is a server-only consequence of real dangerous-zone looting.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const RuinAmbush = preload("res://scripts/shared/ruin_ambush.gd")
const Scavenging = preload("res://scripts/shared/scavenging.gd")
const SupplyDrops = preload("res://scripts/shared/supply_drops.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


class FlatDangerWorld:
	extends RefCounted
	var blocked := false

	func zone_at(_x: float, _z: float) -> int:
		return 2

	func is_safe(_x: float, _z: float) -> bool:
		return false

	func is_water(_x: float, _z: float) -> bool:
		return false

	func normal_at(_x: float, _z: float) -> Vector3:
		return Vector3.UP

	func height_at(_x: float, _z: float) -> float:
		return 3.0

	func blockers_near(_x: float, _z: float, _radius: float) -> Array:
		return [{"x": 250.0, "z": 200.0, "radius": 1000.0}] if blocked else []


## Find a genuinely reachable red/black crate with terrain-safe ambush sites;
## the test never injects a forged crate into the server's loot map.
func _real_crate(world) -> Dictionary:
	for cx in range(8, 20):
		for cz in range(0, 16):
			var chunk: Dictionary = world.chunk(Vector2i(cx, cz))
			if int(chunk["zone"]) < 2:
				continue
			for raw in chunk["crates"]:
				var crate: Dictionary = raw.duplicate(true)
				crate["zone"] = int(chunk["zone"])
				var x: float = float(crate["x"])
				var z: float = float(crate["z"])
				var player_position := Vector3(x - 1.0, world.height_at(x - 1.0, z), z)
				if world.zone_at(player_position.x, player_position.z) != int(crate["zone"]):
					continue
				var survivors: Array[Vector3] = []
				survivors.append(player_position)
				if not RuinAmbush.sites(world, crate, survivors, {}, 3).is_empty():
					return crate
	return {}


func run(t) -> void:
	t.current = "ruin ambush: stable, risk-dependent awakening rolls"
	t.check(not RuinAmbush.awakens(0, 1, 3141, true),
		"safe-zone lockpicks cannot wake infected")
	t.check(not RuinAmbush.awakens(1, 1, 3141, true),
		"yellow-zone caches cannot wake an ambush")
	t.check(not RuinAmbush.awakens(3, -1, 3141, true),
		"invalid crate identity cannot create a wave")
	t.check(RuinAmbush.awakens(2, 12345, 3141, true),
		"breaking a red sealed compartment guarantees a wake-up")
	t.check(RuinAmbush.awakens(3, 12345, 3141, true),
		"breaking a black sealed compartment guarantees a wake-up")
	t.eq(RuinAmbush.awakens(2, 12345, 3141, false),
		RuinAmbush.awakens(2, 12345, 3141, false),
		"reopening or relogging cannot reroll crate danger")
	t.check(RuinAmbush.available([], {}) == RuinAmbush.MAX_ACTIVE_INFECTED,
		"global living-infected capacity is enforced")
	var saturated: Array = []
	for i in RuinAmbush.MAX_ACTIVE_WAVES:
		saturated.append({"ids": [], "expires": 1000.0})
	t.eq(RuinAmbush.available(saturated, {}), 0,
		"active wave limit prevents chain-spawn abuse")
	var near_limit: Dictionary = {}
	for i in range(RuinAmbush.MAX_ACTIVE_INFECTED - 1):
		near_limit[i] = true
	t.eq(RuinAmbush.available([], near_limit), 1,
		"only one more infected can spawn at the global cap")

	t.current = "ruin ambush: strict confirmed-kill ledger"
	var ledger := {"ids": [11, 12], "defeated": [], "cleared": false}
	t.check(not RuinAmbush.record_kill(ledger, 99),
		"a kill outside the original mob roster cannot count")
	t.check(not RuinAmbush.record_kill(ledger, 11),
		"a partial pack kill is not a victory")
	t.check(not RuinAmbush.record_kill(ledger, 11),
		"duplicate death callback never increments progress")
	t.check(RuinAmbush.record_kill(ledger, 12),
		"final real enemy completes the original pack")
	t.check(not RuinAmbush.record_kill(ledger, 12),
		"victory is announced only once")
	t.check(not RuinAmbush.record_kill({"ids": [], "defeated": []}, 11),
		"an empty or missing encounter cannot win")

	t.current = "ruin ambush: collision, terrain and player separation"
	var flat := FlatDangerWorld.new()
	var site := {"x": 250.0, "z": 200.0, "zone": 2}
	var survivors: Array[Vector3] = []
	survivors.append(Vector3(249.0, 3.0, 200.0))
	var placements: Array[Dictionary] = RuinAmbush.sites(
		flat, site, survivors, {}, 3)
	t.check(placements.size() >= 1 and placements.size() <= 2,
		"red ruins spawn at most two valid infected")
	for spot in placements:
		var point := Vector2(float(spot["x"]), float(spot["z"]))
		t.check(point.distance_to(Vector2(249.0, 200.0)) >=
			SupplyDrops.MIN_SURVIVOR_DISTANCE - 0.001,
			"spawn is not directly on the looting player")
		t.check(str(spot["kind"]) in ["walker", "runner"],
			"red-zone types match existing infected catalog")
	t.check(RuinAmbush.sites(flat, {"x": NAN, "z": 200, "zone": 2},
		survivors, {}, 3).is_empty(), "invalid coordinates are rejected")
	t.check(RuinAmbush.sites(flat, {"x": 250, "z": 200, "zone": 1},
		survivors, {}, 3).is_empty(), "forged zone cannot spawn mobs")
	t.eq(RuinAmbush.sites(flat, site, survivors, {}, 0).size(), 0,
		"zero available capacity forbids spawning")
	flat.blocked = true
	t.check(RuinAmbush.sites(flat, site, survivors, {}, 3).is_empty(),
		"terrain obstacles prevent spawns inside solid geometry")

	t.current = "ruin ambush: genuine sealed cache and event lifecycle"
	var world := WorldGen.new(3141)
	var crate: Dictionary = _real_crate(world)
	t.check(not crate.is_empty(), "generated danger-zone cache supports ambush")
	if crate.is_empty():
		return
	var server := GameServer.new(world, 3141)
	var looter = server.add_player(729, "Ruin Scavenger")
	var x: float = float(crate["x"])
	var z: float = float(crate["z"])
	looter.position = Vector3(x - 1.0, world.height_at(x - 1.0, z), z)
	looter.inventory.add(Scavenging.LOCKPICK_ITEM, 1)
	var crate_id: int = int(crate["id"])
	t.eq(server.cmd_loot(looter.id, crate_id + 999999).get("reason", ""),
		"nothing_there", "fake crate cannot create an ambush")
	t.eq(server.ruin_ambushes.size(), 0, "rejected loot creates no waves")
	t.eq(looter.inventory.count(Scavenging.LOCKPICK_ITEM), 1,
		"invalid loot request does not spend the lockpick")
	var looted: Dictionary = server.cmd_loot(looter.id, crate_id)
	t.check(bool(looted.get("ok", false)), "real reachable sealed cache opened")
	t.eq(looter.inventory.count(Scavenging.LOCKPICK_ITEM), 0,
		"one confirmed sealed cache consumes the carried lockpick")
	t.eq(server.ruin_ambushes.size(), 1,
		"the server registered exactly one limited ruin encounter")
	if server.ruin_ambushes.is_empty():
		return
	var ids: Array = server.ruin_ambushes[0]["ids"]
	t.check(ids.size() >= 1 and ids.size() <= 3,
		"spawned count is positive and strictly bounded")
	var announcement_count := 0
	for event in server.events:
		if str(event.get("type", "")) == "ruin_ambush":
			announcement_count += 1
			t.eq(int(event.get("peer", -1)), looter.id,
				"warning belongs to genuine crate opener")
			t.eq(int(event.get("count", -1)), ids.size(),
				"warning reports exactly the spawned enemies")
	t.eq(announcement_count, 1, "one warning per committed encounter")
	for id in ids:
		t.check(server.zombies.has(id), "all announced infected are real entities")
		var enemy = server.zombies.get(id)
		if enemy == null:
			continue
		t.eq(enemy.spawn_id, -1, "temporary enemies never claim renewable spawn slots")
		t.check(not enemy.raid_boss and not enemy.elite,
			"ambush mobs cannot fabricate raid rewards")
		var distance := Vector2(enemy.position.x, enemy.position.z).distance_to(
			Vector2(looter.position.x, looter.position.z))
		t.check(distance >= SupplyDrops.MIN_SURVIVOR_DISTANCE - 0.001,
			"real-world spawn keeps a safe warning distance")
	t.eq(server.cmd_loot(looter.id, crate_id).get("reason", ""), "empty",
		"repeated loot cannot create a second wave or duplicate rewards")
	t.eq(server.ruin_ambushes.size(), 1,
		"duplicate interaction does not bypass the wave limit")
	server._trigger_ruin_ambush(looter, crate, true)
	t.eq(server.ruin_ambushes.size(), 1,
		"server-wide cooldown blocks chained sealed-cache awakenings")
	t.check(not server.character_data(looter).has("ruin_ambushes"),
		"temporary encounters are never serialized into player data")
	# Confirm actual server zombie deaths, not timer expiry or fake IDs.
	for id in ids:
		var enemy = server.zombies.get(id)
		if enemy == null:
			continue
		enemy.take_damage(100000.0, looter.id)
		server._on_zombie_death(enemy, looter)
	var victories := 0
	for event in server.events:
		if str(event.get("type", "")) == "ruin_ambush_cleared":
			victories += 1
			t.eq(int(event.get("count", -1)), ids.size(),
				"victory is based on every spawned enemy")
	t.eq(victories, 1, "all confirmed infected deaths announce one victory")
	server.time += RuinAmbush.LIFETIME_SECONDS + 1.0
	server._tick_ruin_ambush()
	t.eq(server.ruin_ambushes.size(), 0,
		"expired encounter is removed without requiring a relog")
	for id in ids:
		t.check(not server.zombies.has(id),
			"all remaining temporary enemies despawn on encounter expiry")
