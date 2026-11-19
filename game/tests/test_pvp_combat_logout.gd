extends RefCounted
## Combat logout uses confirmed server PvP hits, not spoofed client timers.
const CombatLogout = preload("res://scripts/shared/combat_logout.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _at(world, player, x: float) -> void:
	player.position = Vector3(x, world.height_at(x, 0.0), 0.0)


func run(t) -> void:
	t.current = "finite server combat tag and zone protection"
	t.near(CombatLogout.remaining(30.0, 0.0), 30.0, 0.001, "thirty-second tag begins at hit")
	t.near(CombatLogout.remaining(30.0, 5.0), 25.0, 0.001, "server time ticks down")
	t.near(CombatLogout.remaining(30.0, 30.0), 0.0, 0.001, "expired tag has no penalty")
	t.near(CombatLogout.remaining(INF, 0.0), 0.0, 0.001, "infinite timer is not trusted")
	t.near(CombatLogout.remaining(30.0, NAN), 0.0, 0.001, "nonfinite clock is rejected")
	var world := WorldGen.new(420)
	var sim := GameServer.new(world, 420)
	var warrior = sim.add_player(201, "Warrior")
	var victim = sim.add_player(202, "Survivor")
	_at(world, warrior, 800.0)
	_at(world, victim, 801.0)
	victim.inventory.add("silver", 91)
	victim.stash.add("silver", 31)
	warrior.inventory.add("club_1", 1)
	warrior.inventory.equip("club_1")
	t.eq(sim.snapshot_for(warrior.id)["you"]["combat_tag_seconds"], 0.0,
		"joining a dangerous zone without fighting is not penalized")
	sim._damage_target(warrior, {"kind": "player", "id": victim.id}, 0.0)
	t.near(CombatLogout.remaining(victim.combat_tag_until, sim.time), 0.0, 0.001,
		"zero actual damage does not mark PvP")
	sim._damage_target(warrior, {"kind": "player", "id": victim.id}, 8.0)
	t.near(CombatLogout.remaining(warrior.combat_tag_until, sim.time), 30.0, 0.001,
		"real damaging attacker is tagged")
	t.near(CombatLogout.remaining(victim.combat_tag_until, sim.time), 30.0, 0.001,
		"real damaged survivor is tagged")
	t.check(CombatLogout.penalize_on_disconnect(victim, 2, sim.time),
		"red zone combat disconnect is full loot")
	t.check(CombatLogout.penalize_on_disconnect(warrior, 3, sim.time),
		"black zone combat disconnect is full loot")
	t.check(not CombatLogout.penalize_on_disconnect(victim, 0, sim.time),
		"safe hub never penalizes logout")
	t.check(not CombatLogout.penalize_on_disconnect(victim, 1, sim.time),
		"yellow PvE zone never penalizes logout")

	t.current = "real disconnect drops carried inventory once and saves respawn"
	var bag_count: int = sim.bags.size()
	t.check(sim.prepare_disconnect(victim.id), "combat disconnect is processed by server")
	t.eq(sim.bags.size(), bag_count + 1, "one ordinary public full-loot bag created")
	var found_bag := false
	for bag in sim.bags.values():
		if int(bag["items"].get("silver", 0)) == 91:
			found_bag = true
			t.check(not bag.has("allowed_tokens"), "combat logout bag is public PvP loot")
	t.check(found_bag, "all carried silver is dropped")
	t.eq(victim.inventory.count("silver"), 0, "victim has no duplicated carried silver")
	t.eq(victim.stash.count("silver"), 31, "account stash is never looted")
	t.eq(victim.deaths, 1, "the same full-loot death increments statistics")
	t.check(victim.survival.alive, "victim respawns at sanctuary before logout save")
	t.check(world.zone_at(victim.position.x, victim.position.z) <= 1,
		"respawn location is protected")
	t.eq(sim.character_data(victim)["inventory"], victim.inventory.to_dict(),
		"final saved inventory comes after the full-loot drop")
	t.check(not sim.prepare_disconnect(victim.id), "repeat prepare cannot mint loot")
	sim.remove_player(victim.id)
	t.eq(sim.bags.size(), bag_count + 1, "remove_player cannot duplicate bag after prepare")
	var reused = sim.add_player(202, "New Guest")
	t.eq(reused.combat_tag_until, 0.0, "recycled network peer does not inherit PvP tag")

	t.current = "safe returns, expired tags and PvE are logout-safe"
	_at(world, warrior, 9.0)
	var before_safe: int = sim.bags.size()
	t.check(not sim.prepare_disconnect(warrior.id), "tagged survivor who reaches hub can leave")
	t.eq(sim.bags.size(), before_safe, "safe logout creates no bags")
	_at(world, warrior, 800.0)
	sim.time = CombatLogout.TAG_SECONDS + 0.1
	t.check(not sim.prepare_disconnect(warrior.id), "tag expires after 30 seconds")
	t.eq(sim.bags.size(), before_safe, "expired combat cannot drop gear")
	var explorer = sim.add_player(203, "Zombie Hunter")
	_at(world, explorer, 800.0)
	sim._damage_target(explorer, {"kind": "zombie", "id": -123}, 100.0)
	t.near(explorer.combat_tag_until, 0.0, 0.001, "PvE damage never sets PvP combat tag")
	t.check(not sim.prepare_disconnect(explorer.id), "PvE alone does not penalize logout")
	warrior.survival.hurt(1000.0)
	t.check(not sim.prepare_disconnect(warrior.id), "already-dead characters are never double-penalized")
