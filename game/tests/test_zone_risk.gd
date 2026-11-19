extends RefCounted
## Server-enforced risk transitions and inventory retention.
const Defs = preload("res://scripts/shared/defs.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")

func _position(server, player, x: float, z: float) -> void:
	player.position = Vector3(x, server.world.height_at(x, z), z)

func run(t) -> void:
	t.current = "risk policy"
	t.check(not ZoneRisk.allows_pvp(0), "green is PvE")
	t.check(not ZoneRisk.allows_pvp(1), "yellow is PvE")
	t.check(ZoneRisk.allows_pvp(2), "red permits PvP")
	t.check(ZoneRisk.allows_pvp(3), "black permits PvP")
	t.check(not ZoneRisk.allows_pvp(5), "invalid zones fail closed")
	t.check(not ZoneRisk.can_pvp(2, 1), "red cannot hit yellow")
	t.check(not ZoneRisk.can_pvp(1, 2), "yellow cannot hit red")
	t.check(ZoneRisk.can_pvp(2, 3), "red can hit black")
	t.check(not ZoneRisk.full_loot(0), "green retains equipment")
	t.check(not ZoneRisk.full_loot(1), "yellow retains equipment")
	t.check(ZoneRisk.full_loot(2) and ZoneRisk.full_loot(3), "red/black drop equipment")

	t.current = "server PvP and safe border"
	var server = GameServer.new(WorldGen.new(71), 71)
	var attacker = server.add_player(201, "Attacker")
	var victim = server.add_player(202, "Victim")
	for pair in [[100.0, 101.5], [300.0, 301.5], [621.0, 619.0], [619.0, 621.0]]:
		_position(server, attacker, pair[0], 0.0)
		_position(server, victim, pair[1], 0.0)
		attacker.attack_timer = 0.0
		var direction := 1.0 if pair[1] > pair[0] else -1.0
		var outcome: Dictionary = server.cmd_attack(201, direction, 0.0)
		t.check(outcome["ok"] and not outcome["hit"], "protected zone or border forbids PvP")
	t.near(victim.survival.health, 100.0, 0.0001, "safe attacks do not deal damage")
	_position(server, attacker, 800.0, 0.0)
	_position(server, victim, 801.5, 0.0)
	attacker.attack_timer = 0.0
	var hit: Dictionary = server.cmd_attack(201, 1.0, 0.0)
	t.check(hit["ok"] and hit["hit"], "red zone enables PvP")
	t.check(victim.survival.health < 100.0, "PvP causes damage in red")
	t.check(server.snapshot_for(202)["you"].has("last_death_full_loot"), "HUD receives risk flag")

	t.current = "green and yellow deaths retain equipment"
	for zone in [0, 1]:
		var keeper = server.add_player(300 + zone, "Keeper")
		var x := 100.0 if zone == 0 else 300.0
		_position(server, keeper, x, 0.0)
		keeper.inventory.add("silver", 77)
		keeper.inventory.add("club_1", 1)
		keeper.inventory.equip("club_1")
		var food_before: int = keeper.inventory.count("canned_food")
		var bags_before: int = server.bags.size()
		keeper.survival.hurt(1000.0)
		server._on_player_death(keeper, -1)
		t.check(keeper.keep_inventory_on_respawn, "PvE death retains gear")
		t.eq(server.bags.size(), bags_before, "PvE death produces no full-loot bag")
		server._spawn_player(keeper)
		t.eq(keeper.inventory.count("silver"), 77, "silver retained")
		t.eq(keeper.inventory.weapon, "club_1", "equipped item retained")
		t.eq(keeper.inventory.count("canned_food"), food_before, "no free starter duplication")
		t.check(not keeper.last_death_full_loot, "death HUD shows protected inventory")

	t.current = "red and black drop gear, private stash survives"
	for zone in [2, 3]:
		var looter = server.add_player(400 + zone, "Risker")
		var x := 800.0 if zone == 2 else 1200.0
		_position(server, looter, x, 0.0)
		looter.inventory.add("silver", 83)
		looter.inventory.add("club_1", 1)
		looter.inventory.equip("club_1")
		looter.stash.add("silver", 11)
		looter.survival.hurt(1000.0)
		server._on_player_death(looter, -1)
		t.eq(looter.inventory.count("silver"), 0, "carried currency dropped")
		t.eq(looter.inventory.weapon, "", "weapon dropped")
		t.check(looter.last_death_full_loot, "risk marked full loot")
		var bag_found := false
		for bag in server.bags.values():
			if int(bag["items"].get("silver", 0)) == 83 and bag["items"].has("club_1"):
				bag_found = true
		t.check(bag_found, "death bag contains carried valuables")
		server._spawn_player(looter)
		t.eq(looter.inventory.count("canned_food"), 2, "full loot respawn grants starter kit")
		t.eq(looter.inventory.count("silver"), 0, "dropped silver does not return")
		t.eq(looter.stash.count("silver"), 11, "account bank is never dropped")
