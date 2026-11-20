extends RefCounted
## Paid PvE scouting: nearest verified threat, private target and safe spending.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Rules = preload("res://scripts/shared/field_threat_scanner.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Radar = preload("res://scripts/client/survival_radar.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "tier-two scouting kit has a real, station-paid recipe"
	t.eq(str(Defs.item(Rules.ITEM_ID).get("kind", "")), "threat_scanner",
		"scanner cannot be used as ordinary healing or equipment")
	var recipe: Dictionary = Defs.recipes().get(Rules.ITEM_ID, {})
	t.eq(str(recipe.get("station", "")), "workbench", "one scan requires workshop crafting")
	t.eq(recipe.get("inputs", {}), {"scrap": 3, "bar_2": 1,
		"charcoal_filter": 1}, "scanning spends metal, scrap and water filter")
	var materials := Inventory.new()
	materials.add("scrap", 3)
	materials.add("bar_2", 1)
	materials.add("charcoal_filter", 1)
	t.eq(Crafting.craft(materials, Rules.ITEM_ID, false),
		Crafting.Result.NO_STATION, "no free field manufacture")
	t.eq(materials.count("scrap"), 3, "failed craft preserves raw materials")
	t.eq(Crafting.craft(materials, Rules.ITEM_ID, true),
		Crafting.Result.OK, "paid workshop crafting succeeds")
	t.eq(materials.count(Rules.ITEM_ID), 1, "scanner is a physical backpack item")
	t.eq(materials.count("bar_2"), 0, "metal is consumed, not duplicated")

	t.current = "scope ignores normals and invalid or dead targets"
	var world := WorldGen.new(455)
	var server := GameServer.new(world, 455)
	server.zombies.clear()
	var scout = server.add_player(411, "Scout")
	var outsider = server.add_player(412, "Outsider")
	scout.position = _at(world, 800.0, 100.0)
	outsider.position = _at(world, 805.0, 100.0)
	scout.inventory.add(Rules.ITEM_ID, 2)
	var normal := Zombie.new(server.new_id(), "walker", _at(world, 810.0, 100.0))
	server.zombies[normal.id] = normal
	t.eq(Rules.nearest(scout.position, server.zombies), {},
		"an ordinary infected does not reveal high-value enemies")
	t.eq(server.cmd_use(scout.id, Rules.ITEM_ID).get("reason", ""),
		"no_threat_nearby", "empty scans cannot waste equipment")
	t.eq(scout.inventory.count(Rules.ITEM_ID), 2,
		"no valid target means no consumed item")
	var elite := Zombie.new(server.new_id(), "brute", _at(world, 806.0, 100.0))
	elite.become_elite()
	server.zombies[elite.id] = elite
	var dead := Zombie.new(server.new_id(), "runner", _at(world, 801.0, 100.0))
	dead.become_elite()
	dead.state = Zombie.State.DEAD
	server.zombies[dead.id] = dead
	var far := Zombie.new(server.new_id(), "brute", _at(world, 970.0, 100.0))
	far.become_elite()
	far.raid_boss = true
	server.zombies[far.id] = far
	t.eq(int(Rules.nearest(scout.position, server.zombies).get("target", -1)),
		elite.id, "out-of-range bosses never override nearby elites")
	t.eq(Rules.nearest(Vector3(NAN, 0, 0), server.zombies), {},
		"non-finite scanner coordinates are not accepted")
	var raid := Zombie.new(server.new_id(), "brute", _at(world, 920.0, 100.0))
	raid.raid_boss = true
	server.zombies[raid.id] = raid
	t.eq(int(Rules.nearest(scout.position, server.zombies).get("target", -1)),
		raid.id, "in-range raid boss takes priority over common elite")
	t.eq(str(Rules.nearest(scout.position, server.zombies).get("kind", "")),
		"raid", "target class is server-derived")

	t.current = "safe-zone, mount and combat reject scans without item cost"
	scout.position = _at(world, 8.0, 8.0)
	t.eq(server.cmd_use(scout.id, Rules.ITEM_ID).get("reason", ""),
		"safe_zone", "hub scanning does not bypass wilderness risk")
	scout.position = _at(world, 800.0, 100.0)
	scout.mounted = true
	t.eq(server.cmd_use(scout.id, Rules.ITEM_ID).get("reason", ""),
		"mounted", "rider must dismount")
	scout.mounted = false
	scout.combat_tag_until = server.time + 5.0
	t.eq(server.cmd_use(scout.id, Rules.ITEM_ID).get("reason", ""),
		"in_combat", "scouting cannot activate during a fight")
	scout.combat_tag_until = 0.0
	t.eq(scout.inventory.count(Rules.ITEM_ID), 2,
		"rejected requests never debit the backpack")

	t.current = "confirmed scan spends once and gives only owner a moving map pin"
	var result: Dictionary = server.cmd_use(scout.id, Rules.ITEM_ID)
	t.check(bool(result.get("ok", false)) and bool(result.get("threat_scan", false)),
		"server scans its own world, without client-supplied target coordinates")
	t.eq(str(result.get("kind", "")), "raid", "server identifies boss encounter")
	t.near(float(result.get("x", 0)), raid.position.x, 0.001,
		"result reports actual, authoritative target coordinates")
	t.eq(scout.inventory.count(Rules.ITEM_ID), 1,
		"one successful scan consumes exactly one device")
	t.check(scout.dirty_inventory and scout.dirty_character,
		"inventory and survivor state are marked for save/sync")
	var private_mark: Dictionary = server.snapshot_for(scout.id)["you"].get("threat_scan", {})
	t.eq(str(private_mark.get("kind", "")), "raid", "owner receives target class")
	t.near(float(private_mark.get("remaining", 0.0)), Rules.MARK_SECONDS, 0.001,
		"snapshot marker has a strictly bounded lifetime")
	t.check(not private_mark.has("target") and not private_mark.has("expires"),
		"client sees only the target location, not internal tracking IDs or timestamps")
	t.eq(server.snapshot_for(outsider.id)["you"].get("threat_scan", {}), {},
		"nearby unrelated survivor never receives owner's scan")
	for seen in server.snapshot_for(outsider.id)["players"]:
		t.check(not seen.has("threat_scan"), "other actors' snapshots never expose tracking")

	var radar := Radar.new()
	radar.sim = server
	radar.actor_id = scout.id
	t.eq(radar.current_threat_scan(), private_mark,
		"offline live radar reads exactly the same private scan as online")
	radar.actor_id = outsider.id
	t.eq(radar.current_threat_scan(), {},
		"local radar cannot borrow another player's marker")
	radar.free()
	raid.position = _at(world, 940.0, 110.0)
	var following: Dictionary = server.snapshot_for(scout.id)["you"]["threat_scan"]
	t.near(float(following["x"]), 940.0, 0.001,
		"marker follows live authoritative target movement")
	raid.position = _at(world, 1000.0, 110.0)
	t.eq(server.snapshot_for(scout.id)["you"]["threat_scan"], {},
		"scout cannot track beyond maximum allowed follow range")
	raid.position = _at(world, 940.0, 110.0)
	raid.state = Zombie.State.DEAD
	t.eq(server.snapshot_for(scout.id)["you"]["threat_scan"], {},
		"dead boss immediately disappears from private tracker")
	raid.state = Zombie.State.IDLE
	server.time += Rules.MARK_SECONDS
	t.eq(server.snapshot_for(scout.id)["you"]["threat_scan"], {},
		"expired scanner never produces an eternal waypoint")
	t.eq(server.cmd_use(scout.id, Rules.ITEM_ID).get("ok", false), true,
		"second paid device may find a new live encounter")
	scout.inventory.remove(Rules.ITEM_ID, 1)
	t.eq(server.cmd_use(scout.id, Rules.ITEM_ID).get("reason", ""),
		"not_carried", "replay cannot request a free scan")
