extends RefCounted
## Lineage-style elite PvE, without letting clients or ordinary zombies mint rewards.
const Defs = preload("res://scripts/shared/defs.gd")
const EliteInfected = preload("res://scripts/shared/elite_infected.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "deterministic elite selection restricted to risky ruins"
	var eligible := 0
	for id in range(1, 150):
		var yes: bool = EliteInfected.is_elite_spawn(id, 2, true, 123)
		t.eq(yes, EliteInfected.is_elite_spawn(id, 2, true, 123),
			"world seed and spawn id give stable elite eligibility")
		eligible += 1 if yes else 0
		t.check(not EliteInfected.is_elite_spawn(id, 0, true, 123),
			"safe and green zones have no champions")
		t.check(not EliteInfected.is_elite_spawn(id, 1, true, 123),
			"yellow zones have no champions")
		t.check(not EliteInfected.is_elite_spawn(id, 3, false, 123),
			"wilderness without ruins has no champions")
	t.check(eligible >= 5 and eligible <= 45, "elite selection is rare, not ubiquitous")

	t.current = "individual stats are cloned; ordinary infected unchanged"
	var normal := Zombie.new(20, "walker", Vector3(800, 0, 0))
	var champion := Zombie.new(21, "walker", Vector3(800, 0, 0))
	var base_health: float = normal.health
	var base_damage: float = float(normal.data["damage"])
	champion.become_elite()
	t.check(champion.elite, "marked elite")
	t.near(champion.health, base_health * EliteInfected.HEALTH_MULTIPLIER, 0.0001,
		"elite has increased health")
	t.near(float(champion.data["damage"]), base_damage * EliteInfected.DAMAGE_MULTIPLIER, 0.0001,
		"elite melee hits harder")
	t.eq(int(champion.data["xp"]), int(normal.data["xp"]) * EliteInfected.MASTERY_XP_MULTIPLIER,
		"elite mastery rewards scale with the encounter")
	champion.become_elite()
	t.near(champion.health, base_health * EliteInfected.HEALTH_MULTIPLIER, 0.0001,
		"repeated promotion never stacks multipliers")
	t.eq(normal.health, base_health, "normal mob health is unaffected")
	t.near(float(Defs.ZOMBIES["walker"]["damage"]), base_damage, 0.0001,
		"immutable global zombie definitions are not modified")

	t.current = "server snapshots and real kill reward"
	var world := WorldGen.new(41)
	var sim := GameServer.new(world, 42)
	var player = sim.add_player(601, "Ruin Hunter")
	player.position = Vector3(800.0, world.height_at(800.0, 0.0), 0.0)
	champion.position = player.position + Vector3(1.0, 0.0, 0.0)
	sim.zombies[champion.id] = champion
	var shown: Array = sim.snapshot_for(601)["zombies"]
	var found := false
	for enemy in shown:
		if int(enemy["id"]) == champion.id and bool(enemy.get("elite", false)):
			found = true
	t.check(found, "clients receive visible elite marker")
	var raw: Dictionary = {"silver": 4, "scrap": 1}
	var bonus: Dictionary = EliteInfected.enhanced_loot(raw, 2)
	t.eq(int(raw["silver"]), 4, "elite reward cannot alter regular loot tables")
	t.eq(int(bonus["infected_core"]), 1, "elite always drops one infected core")
	t.check(int(bonus["silver"]) > int(raw["silver"]), "elite yields more silver")
	sim._damage_target(player, {"kind": "zombie", "id": champion.id}, champion.health + 5.0)
	t.check(not champion.is_alive(), "real server damage kills the elite")
	t.eq(player.kills, 1, "elite kill counts exactly once")
	var core_found := false
	for bag in sim.bags.values():
		if int(bag["items"].get("infected_core", 0)) == 1:
			core_found = true
	t.check(core_found, "server drops valuable core in ordinary loot bag")
	sim._damage_target(player, {"kind": "zombie", "id": champion.id}, 10000.0)
	t.eq(player.kills, 1, "dead elite cannot be farmed repeatedly")
	t.eq(sim.bags.size(), 1, "second hit does not duplicate boss drops")

	t.current = "elite trophies feed infection survival loop"
	t.check(Defs.is_item("infected_core") and Defs.is_item("purified_serum"),
		"trophy and medicinal output are registered tradeable items")
	t.eq(Defs.recipes()["purified_serum"]["inputs"]["infected_core"], 2,
		"serum requires two dangerous-ruin trophies")
	t.eq(Defs.recipes()["purified_serum"]["station"], "workbench",
		"serum must be refined at a real hub workshop")
