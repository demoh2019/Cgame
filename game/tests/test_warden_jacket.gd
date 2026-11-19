extends RefCounted
## Rare expedition armor connects elite trophies, crafting and actual zombie wounds.
const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


## Recreate a confirmed server zombie hit without relying on client state.
func _infected_strike(server, player, world) -> void:
	server.zombies.clear()
	player.survival.reset()
	var infected := Zombie.new(server.new_id(), "walker",
		player.position + Vector3(1.1, 0.0, 0.0))
	infected.target_id = player.id
	infected.state = Zombie.State.ATTACK
	server.zombies[infected.id] = infected
	server._tick_zombies(0.1)


func run(t) -> void:
	t.current = "elite trophies produce specialized T3 armor"
	var id := "warden_jacket_3"
	var armor: Dictionary = Defs.item(id)
	t.eq(armor.get("kind"), "armor", "relic jacket is equippable armor")
	t.eq(Defs.tier_of(id), 3, "relic requires third-tier crafting")
	t.near(float(armor["armor"]), float(Defs.item("jacket_3")["armor"]),
		0.00001, "base damage armor is not stronger than normal T3 gear")
	var recipe: Dictionary = Defs.recipes()[id]
	t.eq(recipe["station"], "workbench", "field campfire cannot forge protective gear")
	t.eq(recipe["inputs"]["infected_core"], 3, "elite trophies are consumed")
	t.near(Combat.infected_wound_amount(10.0, id, true, "infection"), 6.0, 0.0001,
		"warden jacket reduces infected infection by 40 percent")
	t.near(Combat.infected_wound_amount(10.0, id, true, "bleeding"), 7.0, 0.0001,
		"warden jacket reduces infected bleeding by 30 percent")
	t.near(Combat.infected_wound_amount(10.0, id, false, "infection"), 10.0, 0.0001,
		"ghost equipment cannot provide protection")
	t.near(Combat.infected_wound_amount(10.0, "jacket_3", true, "infection"), 10.0, 0.0001,
		"regular armor offers no extra infection mitigation")

	t.current = "authoritative T3 crafting consumes rare materials exactly once"
	var world := WorldGen.new(318)
	var sim := GameServer.new(world, 71)
	var smith = sim.add_player(605, "Expedition Smith")
	smith.position = _at(world, 9.0, 0.0)
	for material in recipe["inputs"]:
		smith.inventory.add(str(material), int(recipe["inputs"][material]))
	var before: Dictionary = smith.inventory.to_dict()
	t.eq(sim.cmd_craft(605, id).get("reason"), "need_skill",
		"novice cannot forge relic armor")
	t.eq(smith.inventory.to_dict(), before, "denied crafting never consumes cores")
	smith.progression.crafting_xp = 200
	t.check(bool(sim.cmd_craft(605, id).get("ok", false)),
		"server allows trained T3 smith to forge one jacket")
	t.eq(smith.inventory.count(id), 1, "exactly one crafted jacket enters inventory")
	t.eq(smith.inventory.count("infected_core"), 0, "craft spends three rare cores")
	t.check(smith.inventory.equip(id), "wearer equips armor through normal inventory")

	t.current = "actual infected attack applies server-owned wound resistance"
	smith.position = _at(world, 200.0, 200.0)
	_infected_strike(sim, smith, world)
	t.near(smith.survival.infection, 4.8, 0.001,
		"real walker attack causes 60% of its usual infection")
	t.near(smith.survival.bleeding, 6.3, 0.001,
		"real walker attack causes 70% of its usual bleeding")
	t.check(smith.survival.health < Defs.MAX_HEALTH, "real server attack still hurts")

	t.current = "lost gear cannot grant passive wound resistance"
	t.check(smith.inventory.remove(id, 1), "jacket can leave the backpack")
	# Mimic stale equipped gear; server must not trust the armor slot alone.
	smith.inventory.armor = id
	_infected_strike(sim, smith, world)
	t.near(smith.survival.infection, 8.0, 0.001,
		"missing armor cannot mitigate zombie infection")
	t.near(smith.survival.bleeding, 9.0, 0.001,
		"missing armor cannot mitigate zombie bleeding")
	t.near(smith.survival.health, Defs.MAX_HEALTH - 9.0, 0.001,
		"stale armor cannot reduce direct zombie damage")

	t.current = "PvP wounds do not inherit infected-only mitigation"
	var rival = sim.add_player(606, "Rival Survivor")
	rival.position = _at(world, 801.0, 800.0)
	smith.position = _at(world, 800.0, 800.0)
	smith.inventory.add(id, 1)
	smith.inventory.equip(id)
	smith.survival.reset()
	rival.inventory.add("club_1", 1)
	rival.inventory.equip("club_1")
	sim._damage_target(rival, {"kind": "player", "id": 605}, 20.0)
	t.near(smith.survival.bleeding, Defs.PVP_MELEE_BLEEDING_PER_HIT, 0.001,
		"relic protects from infected wounds, not PvP bleeding")
	t.near(smith.survival.health, Defs.MAX_HEALTH -
		Combat.apply_armor(20.0, id), 0.001,
		"PvP uses unchanged ordinary armor damage reduction")
