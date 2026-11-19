extends RefCounted
## Tiered classless polearms with deterministic, authoritative line penetration.

const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func run(t) -> void:
	t.current = "tiered spear recipes and combat definitions"
	for tier in range(1, Defs.MAX_TIER + 1):
		var spear_id: String = "spear_%d" % tier
		var recipe: Dictionary = Defs.recipes().get(spear_id, {})
		t.check(Defs.is_item(spear_id), "spear tier exists")
		t.eq(str(recipe.get("output", "")), spear_id, "spear is craftable")
		t.eq(str(recipe.get("station", "")), "workbench", "spear requires workbench")
		t.eq(str(Defs.item(spear_id).get("weapon", "")), "melee", "spear grants melee mastery")
	t.near(Combat.weapon_range("club_1"), Defs.MELEE_RANGE, 0.001, "club range retained")
	t.near(Combat.weapon_range("spear_1"), 3.2, 0.001, "spears reach farther")
	t.near(Combat.weapon_range("unknown"), Defs.MELEE_RANGE, 0.001, "unknown reach is safe")
	t.eq(Combat.active_skill("spear_2").get("id", ""), "piercing_thrust", "spear skill")
	t.eq(int(Combat.active_skill("spear_4").get("pierce_targets", 0)), 3, "bounded hit count")
	t.eq(Combat.active_skill("club_1").get("id", ""), "heavy_strike", "club ability unchanged")
	t.eq(Combat.active_skill("pistol").get("id", ""), "focused_shot", "pistol ability unchanged")

	var world := WorldGen.new(514)
	var server := GameServer.new(world, 25)
	var player = server.add_player(600, "PolearmTester")
	player.position = Vector3(9.0, world.height_at(9.0, 0.0), 0.0)
	player.inventory.add("plank_1", 2)
	player.inventory.add("fiber_1", 2)
	player.inventory.add("stone_1", 2)
	t.eq(server.cmd_craft(600, "spear_2").get("reason", ""), "need_skill",
		"high-tier recipes retain crafting mastery gate")
	t.check(server.cmd_craft(600, "spear_1").get("ok", false), "T1 spear crafted")
	t.eq(player.inventory.count("spear_1"), 1, "crafted spear carried")
	t.check(server.cmd_use(600, "spear_1").get("ok", false), "spear equipped")

	t.current = "basic spear reaches beyond club; phantom gear cannot extend reach"
	player.position = Vector3(200.0, world.height_at(200.0, 200.0), 200.0)
	var target := Zombie.new(server.new_id(), "brute",
		Vector3(203.0, world.height_at(203.0, 200.0), 200.0))
	server.zombies[target.id] = target
	var before_hp: float = target.health
	t.check(server.cmd_attack(600, 1.0, 0.0).get("hit", false), "spear strike lands at 3 m")
	t.near(target.health, before_hp - Combat.weapon_damage("spear_1"), 0.001,
		"normal damage comes from the server")
	player.attack_timer = 0.0
	t.check(player.inventory.remove("spear_1", 1), "removing equipped spear succeeds")
	t.check(not server.cmd_attack(600, 1.0, 0.0).get("hit", true),
		"ghost equipment uses fists reach")
	player.attack_timer = 0.0
	player.inventory.add("spear_1", 1)
	t.check(server.cmd_use(600, "spear_1").get("ok", false), "re-equipped carried spear")

	t.current = "piercing thrust hits three distinct forward targets"
	server.zombies.clear()
	var targets: Array = []
	for x_pos in [202.0, 203.0, 203.6, 204.0]:
		var zombie := Zombie.new(server.new_id(), "brute",
			Vector3(x_pos, world.height_at(x_pos, 200.0), 200.0))
		server.zombies[zombie.id] = zombie
		targets.append(zombie)
	var off_axis := Zombie.new(server.new_id(), "brute",
		Vector3(202.0, world.height_at(202.0, 202.0), 202.0))
	server.zombies[off_axis.id] = off_axis
	var behind := Zombie.new(server.new_id(), "brute",
		Vector3(199.0, world.height_at(199.0, 200.0), 200.0))
	server.zombies[behind.id] = behind
	t.eq(server.cmd_skill(600, 0.0, 0.0).get("reason", ""), "no_direction", "bad aim rejected")
	t.near(player.combat_energy, Defs.COMBAT_ENERGY_MAX, 0.001, "invalid aim costs no energy")
	var thrust: Dictionary = server.cmd_skill(600, 1.0, 0.0)
	t.check(thrust.get("ok", false) and thrust.get("hit", false), "server executes piercing skill")
	t.eq(int(thrust.get("hits", -1)), 3, "three target cap")
	for i in 3:
		t.check(targets[i].health < float(Defs.ZOMBIES["brute"]["health"]), "each target damaged")
	t.near(targets[3].health, float(Defs.ZOMBIES["brute"]["health"]), 0.001, "fourth target untouched")
	t.near(off_axis.health, float(Defs.ZOMBIES["brute"]["health"]), 0.001, "off-axis untargeted")
	t.near(behind.health, float(Defs.ZOMBIES["brute"]["health"]), 0.001, "rear target untouched")
	t.near(player.combat_energy, 65.0, 0.001, "35 energy paid once")
	t.near(player.skill_timer, 8.0, 0.001, "eight second cooldown")
	t.eq(server.cmd_skill(600, 1.0, 0.0).get("reason", ""), "cooldown", "cannot spam")
	player.skill_timer = 0.0
	player.attack_timer = 0.0
	player.combat_energy = 34.0
	t.eq(server.cmd_skill(600, 1.0, 0.0).get("reason", ""), "no_energy", "energy-gated")
	t.near(player.combat_energy, 34.0, 0.001, "denied casts cost nothing")

	t.current = "safe hub and full-loot zone PvP restrictions"
	server.zombies.clear()
	var opponent = server.add_player(601, "Opponent")
	player.combat_energy = 100.0
	player.position = Vector3(8.0, world.height_at(8.0, 0.0), 0.0)
	opponent.position = Vector3(10.0, world.height_at(10.0, 0.0), 0.0)
	var safe: Dictionary = server.cmd_skill(600, 1.0, 0.0)
	t.check(safe.get("ok", false) and not safe.get("hit", true), "hub stops PvP")
	t.near(opponent.survival.health, Defs.MAX_HEALTH, 0.001, "hub victim unharmed")
	player.position = Vector3(700.0, world.height_at(700.0, 0.0), 0.0)
	opponent.position = Vector3(702.0, world.height_at(702.0, 0.0), 0.0)
	player.attack_timer = 0.0
	player.skill_timer = 0.0
	player.combat_energy = 100.0
	t.check(server.cmd_skill(600, 1.0, 0.0).get("hit", false), "red-zone PvP permitted")
	t.check(opponent.survival.health < Defs.MAX_HEALTH, "red-zone PvP damage applies")

	t.current = "existing save and owner snapshot preserve spear equipment"
	var snapshot: Dictionary = server.character_data(player)
	t.check(server.apply_character(player, snapshot), "spear character can reconnect")
	t.eq(player.inventory.weapon, "spear_1", "spear survives save/load")
	t.eq(str(server.snapshot_for(600).get("you", {}).get("weapon", "")),
		"spear_1", "spear appears in network snapshot")
