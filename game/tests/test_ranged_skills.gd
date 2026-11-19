extends RefCounted
## Pistol equipment ability is fully authoritative, including one real cartridge.
const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func run(t) -> void:
	t.current = "ranged active skill is equipment-granted and has bounded rules"
	var skill: Dictionary = Combat.active_skill("pistol")
	t.eq(str(skill.get("id", "")), "focused_shot", "pistol grants its own active skill")
	t.check(bool(skill.get("ranged", false)), "aimed shot is resolved as ranged combat")
	t.eq(str(skill.get("ammo", "")), "ammo_9mm", "pistol uses existing manufactured ammunition")
	t.near(float(skill["damage"]), Combat.weapon_damage("pistol") * 1.75, 0.001,
		"skill uses real pistol base damage")
	t.near(float(skill["range"]), Defs.PISTOL_RANGE + 4.0, 0.001,
		"aimed shot reaches four metres beyond normal pistol fire")
	t.check(Combat.active_skill("not_real").is_empty(), "unrecognized weapon has no active skill")

	var world := WorldGen.new(1107)
	var server := GameServer.new(world, 1107)
	var survivor = server.add_player(225, "Sharpshooter")
	survivor.inventory.add("pistol", 1)
	t.check(survivor.inventory.equip("pistol"), "player equips physically owned firearm")
	var no_ammo: Dictionary = server.cmd_skill(225, 1.0, 0.0)
	t.eq(no_ammo.get("reason", ""), "no_ammo", "no gunshot without a real cartridge")
	t.near(survivor.combat_energy, 100.0, 0.001, "failed shot does not spend energy")
	t.near(survivor.skill_timer, 0.0, 0.001, "no-ammo denial does not start cooldown")
	t.near(survivor.noise_timer, 0.0, 0.001, "no-ammo denial makes no gunshot noise")

	survivor.inventory.add("ammo_9mm", 4)
	t.eq(server.cmd_skill(225, 0.0, 0.0).get("reason", ""), "no_direction",
		"zero direction is rejected")
	t.eq(server.cmd_skill(225, 1e300, 0.0).get("reason", ""), "no_direction",
		"overflowing squared aim length is rejected")
	t.eq(survivor.inventory.count("ammo_9mm"), 4, "invalid aim cannot burn ammunition")
	t.near(survivor.combat_energy, 100.0, 0.001, "invalid aim cannot drain energy")

	t.current = "real infected hit consumes one round and energy, not two"
	survivor.position = Vector3(200.0, world.height_at(200.0, 200.0), 200.0)
	var brute := Zombie.new(server.new_id(), "brute",
		Vector3(206.0, world.height_at(206.0, 200.0), 200.0))
	server.zombies[brute.id] = brute
	var hp_before: float = brute.health
	var shot: Dictionary = server.cmd_skill(225, 1.0, 0.0)
	t.check(shot.get("ok", false) and shot.get("hit", false), "server performs a real ranged hit")
	t.eq(shot.get("target", ""), "zombie", "aimed shot targets infected")
	t.near(brute.health, hp_before - Combat.weapon_damage("pistol") * 1.75, 0.001,
		"real infected health loses exactly the server skill damage")
	t.eq(survivor.inventory.count("ammo_9mm"), 3, "one shot spends one cartridge")
	t.near(survivor.combat_energy, 60.0, 0.001, "one shot spends forty energy")
	t.near(survivor.skill_timer, 8.0, 0.001, "ranged cooldown starts at eight seconds")
	t.check(survivor.noise_timer > 0.0, "real gunshot makes infected-attracting noise")
	var emitted := false
	for event in server.events:
		if event.get("type") == "attack" and event.get("peer") == 225 and event.get("skill") == "focused_shot":
			t.check(bool(event.get("ranged", false)), "network attack event is flagged ranged")
			emitted = true
	t.check(emitted, "server emits focused-shot combat event")
	t.eq(server.cmd_skill(225, 1.0, 0.0).get("reason", ""), "cooldown",
		"rapid active-skill repeat denied")
	t.eq(server.cmd_attack(225, 1.0, 0.0).get("reason", ""), "cooldown",
		"ordinary firearm attack cannot bypass shared attack lock")
	t.eq(survivor.inventory.count("ammo_9mm"), 3, "repeated skill requests spend no ammo")
	t.near(survivor.combat_energy, 60.0, 0.001, "repeated skill requests spend no energy")

	t.current = "insufficient energy and ammunition are atomic failures"
	survivor.skill_timer = 0.0
	survivor.attack_timer = 0.0
	survivor.combat_energy = 39.0
	t.eq(server.cmd_skill(225, 1.0, 0.0).get("reason", ""), "no_energy",
		"energy requirement is enforced by the server")
	t.eq(survivor.inventory.count("ammo_9mm"), 3, "energy failure cannot consume bullets")
	t.near(survivor.skill_timer, 0.0, 0.001, "failed energy check does not start cooldown")
	survivor.combat_energy = 100.0
	t.check(survivor.inventory.remove("ammo_9mm", 3), "remove remaining rounds")
	t.eq(server.cmd_skill(225, 1.0, 0.0).get("reason", ""), "no_ammo",
		"skill cannot fire with an empty magazine supply")
	t.near(survivor.combat_energy, 100.0, 0.001, "missing ammo cannot drain energy")

	t.current = "ranged mastery scales focused shot and equipment ownership gates it"
	survivor.inventory.add("ammo_9mm", 2)
	survivor.progression.award_combat("pistol", 80)
	t.eq(survivor.progression.combat_level("ranged"), 2, "pistol expertise reaches level two")
	hp_before = brute.health
	var mastery_shot: Dictionary = server.cmd_skill(225, 1.0, 0.0)
	t.check(mastery_shot.get("hit", false), "trained gunner hits same infected")
	t.near(brute.health, hp_before - Combat.weapon_damage("pistol") * 1.75 * 1.03,
		0.001, "server grants the same bounded ranged mastery bonus")
	t.eq(survivor.inventory.count("ammo_9mm"), 1, "trained shot still consumes one round")
	survivor.skill_timer = 0.0
	survivor.attack_timer = 0.0
	survivor.combat_energy = 100.0
	t.check(survivor.inventory.remove("pistol", 1), "unequip by removing carried pistol")
	t.eq(server.cmd_skill(225, 1.0, 0.0).get("reason", ""), "no_skill",
		"carried ammunition alone cannot grant pistol ability")
	t.eq(survivor.inventory.count("ammo_9mm"), 1, "unowned weapon cannot consume ammo")

	t.current = "safe-hub group PvP protections still apply to ranged skills"
	survivor.inventory.add("pistol", 1)
	t.check(survivor.inventory.equip("pistol"), "re-equip returned pistol")
	survivor.position = Vector3(8.0, world.height_at(8.0, 0.0), 0.0)
	var neighbor = server.add_player(226, "Protected")
	neighbor.position = Vector3(10.0, world.height_at(10.0, 0.0), 0.0)
	var before_safe: float = neighbor.survival.health
	var safe_shot: Dictionary = server.cmd_skill(225, 1.0, 0.0)
	t.check(safe_shot.get("ok", false) and not safe_shot.get("hit", true),
		"firearm active skill cannot target safe hub survivor")
	t.near(neighbor.survival.health, before_safe, 0.001, "protected survivor takes no damage")
	t.eq(survivor.inventory.count("ammo_9mm"), 0, "misses still consume physical ammunition")
	survivor.survival.hurt(1000.0)
	t.eq(server.cmd_skill(225, 1.0, 0.0).get("reason", ""), "dead",
		"dead survivor cannot activate ranged ability")
	server._spawn_player(survivor)
	t.near(survivor.combat_energy, Defs.COMBAT_ENERGY_MAX, 0.001,
		"respawn restores combat energy")
	t.near(survivor.skill_timer, 0.0, 0.001, "respawn resets weapon skill cooldown")
