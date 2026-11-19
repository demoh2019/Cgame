extends RefCounted
## Trophy crafted equipment closes the raid -> artisan -> combat gameplay loop.
## All mastery gates, carried gear, cooldowns and damage remain server-owned.

const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _position(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "raid trophies become restricted T3 artisan weapon"
	var weapon_id := "purifier_maul_3"
	var item: Dictionary = Defs.item(weapon_id)
	t.eq(item.get("kind"), "weapon", "raid weapon is real equippable gear")
	t.eq(item.get("weapon"), "melee", "existing melee mastery applies")
	t.eq(Defs.tier_of(weapon_id), 3, "trophy weapon requires T3 crafting skill")
	var recipe: Dictionary = Defs.recipes()[weapon_id]
	t.eq(recipe["station"], "workbench", "no crafting the relic at an open campfire")
	t.eq(int(recipe["inputs"]["infected_core"]), 4, "rare elite trophies are required")
	t.eq(Combat.active_skill(weapon_id)["id"], "purifying_slam",
		"relic grants a dedicated weapon-based skill")
	t.eq(Combat.active_skill("club_3")["id"], "heavy_strike",
		"existing club skill still works")
	t.check(Combat.active_skill("pistol").is_empty(), "ranged weapons do not inherit relic skill")
	t.near(Combat.against_infected(100.0, weapon_id, true), 125.0, 0.0001,
		"owned relic gives exactly 25 percent PvE advantage")
	t.near(Combat.against_infected(100.0, weapon_id, false), 100.0, 0.0001,
		"phantom equipment never earns PvE advantage")
	t.near(Combat.against_infected(100.0, "club_3", true), 100.0, 0.0001,
		"normal weapons remain unmodified")

	t.current = "workbench, resources and profession are server-owned"
	var world := WorldGen.new(93)
	var sim := GameServer.new(world, 93)
	var smith = sim.add_player(451, "Relic Smith")
	smith.position = _position(world, 9.0, 0.0)
	for material in recipe["inputs"]:
		smith.inventory.add(str(material), int(recipe["inputs"][material]))
	var before: Dictionary = smith.inventory.to_dict()
	t.eq(sim.cmd_craft(451, weapon_id).get("reason"), "need_skill",
		"novice cannot craft the high-tier weapon despite owned ingredients")
	t.eq(smith.inventory.to_dict(), before, "failed craft spends no trophies")
	smith.progression.crafting_xp = 200
	t.check(bool(sim.cmd_craft(451, weapon_id).get("ok", false)),
		"master smith forges item from raid loot")
	t.eq(smith.inventory.count(weapon_id), 1, "craft grants exactly one relic")
	t.eq(smith.inventory.count("infected_core"), 0, "craft consumes earned rare cores")
	t.check(smith.inventory.equip(weapon_id), "weapon occupies normal equipment slot")

	t.current = "actual server attacks and skills versus infected"
	smith.position = _position(world, 200.0, 200.0)
	var brute := Zombie.new(sim.new_id(), "brute", _position(world, 202.0, 200.0))
	sim.zombies[brute.id] = brute
	var initial: float = brute.health
	var attack: Dictionary = sim.cmd_attack(451, 1.0, 0.0)
	t.check(bool(attack.get("ok", false)) and bool(attack.get("hit", false)),
		"server accepts a real equipped relic attack")
	t.near(initial - brute.health, 32.0 * 1.25, 0.001,
		"relic PvE bonus is applied to real infected combat")
	smith.attack_timer = 0.0
	var before_skill: float = brute.health
	var slam: Dictionary = sim.cmd_skill(451, 1.0, 0.0)
	t.check(bool(slam.get("ok", false)) and bool(slam.get("hit", false)),
		"server resolves special relic strike")
	t.near(before_skill - brute.health, 32.0 * 1.5 * 1.25, 0.001,
		"skill inherits only the bounded infected bonus")
	t.near(smith.combat_energy, Defs.COMBAT_ENERGY_MAX - 35.0, 0.001,
		"server charges ability energy")
	t.eq(sim.cmd_skill(451, 1.0, 0.0).get("reason"), "cooldown",
		"ability cannot be spammed")

	t.current = "unarmed ghost gear and PvP cannot apply infected bonus"
	var defender = sim.add_player(452, "Enemy Player")
	defender.position = _position(world, 800.0, 800.0)
	smith.position = _position(world, 801.0, 800.0)
	var hp_before: float = defender.survival.health
	sim._damage_target(smith, {"kind": "player", "id": 452}, 32.0)
	t.near(hp_before - defender.survival.health, 32.0, 0.001,
		"PvP receives base weapon damage, not infected-specific bonus")
	smith.inventory.remove(weapon_id, 1)
	smith.attack_timer = 0.0
	smith.skill_timer = 0.0
	t.eq(sim.cmd_skill(451, 1.0, 0.0).get("reason"), "no_skill",
		"lost weapon cannot cast relic ability")
	var safe := Zombie.new(sim.new_id(), "brute", _position(world, 803.0, 800.0))
	sim.zombies[safe.id] = safe
	var before_ghost: float = safe.health
	var ghost_attempt: Dictionary = sim.cmd_attack(451, 1.0, 0.0)
	t.check(bool(ghost_attempt.get("ok", false)) and bool(ghost_attempt.get("hit", false)),
		"ghost-equipped attacker uses existing unarmed combat")
	t.near(before_ghost - safe.health, 6.0, 0.001,
		"stale inventory weapon cannot deal relic or carry phantom PvE bonus")
