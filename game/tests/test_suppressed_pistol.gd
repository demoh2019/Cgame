extends RefCounted
## Quiet scavenged firearm: real crafting, cartridges and server-owned infected noise.

const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")

const WEAPON := "suppressed_pistol"


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "quiet firearm uses a real scavenged pistol and advanced materials"
	var data: Dictionary = Defs.item(WEAPON)
	var recipe: Dictionary = Defs.recipes().get(WEAPON, {})
	t.eq(data.get("kind"), "weapon", "suppressed handgun is equipment")
	t.eq(data.get("weapon"), "ranged", "inherits standard firearm combat")
	t.eq(data.get("ammo"), "ammo_9mm", "uses actual craftable cartridges")
	t.eq(int(data.get("tier", 0)), 3, "requires tier-three crafting mastery")
	t.eq(recipe.get("station", ""), "workbench", "specialist upgrade needs a bench")
	t.eq(recipe.get("inputs", {}), {"pistol": 1, "bar_3": 2,
		"cloth_3": 2, "scrap": 6}, "base pistol is consumed with advanced materials")
	t.check(Combat.weapon_damage(WEAPON) < Combat.weapon_damage("pistol"),
		"quiet weapon trades damage for stealth")
	t.check(Combat.weapon_cooldown(WEAPON) > Combat.weapon_cooldown("pistol"),
		"quiet weapon has slower fire rate")
	t.check(Combat.ranged_range(WEAPON) < Combat.ranged_range("pistol"),
		"quiet weapon has shorter range")
	t.near(float(Combat.ranged_noise(WEAPON)["radius"]), 12.0, 0.001,
		"shot alerts enemies within twelve metres")
	t.near(float(Combat.ranged_noise(WEAPON)["seconds"]), 1.1, 0.001,
		"alert ends faster than loud pistol fire")
	t.check(float(Combat.ranged_noise(WEAPON)["radius"]) <
		float(Combat.ranged_noise("pistol")["radius"]),
		"existing pistol remains louder")
	var skill: Dictionary = Combat.active_skill(WEAPON)
	t.eq(skill.get("id", ""), "careful_shot", "unique charged precision shot")
	t.eq(skill.get("ammo", ""), "ammo_9mm", "special shot spends one real round")
	t.check(bool(skill.get("ranged", false)), "skill follows ranged hit checks")
	t.check(float(skill.get("range", 0.0)) <= Defs.PISTOL_RANGE,
		"precision shot cannot outrange a normal pistol")

	t.current = "atomic crafting and no-duplication"
	var inventory := Inventory.new()
	for item_id in recipe["inputs"]:
		inventory.add(str(item_id), int(recipe["inputs"][item_id]))
	t.eq(Crafting.craft(inventory, WEAPON, false), Crafting.Result.NO_STATION,
		"cannot forge the upgrade away from a workbench")
	t.eq(inventory.count("pistol"), 1, "refused upgrade keeps original firearm")
	t.eq(Crafting.craft(inventory, WEAPON, true), Crafting.Result.OK,
		"upgrade consumes the old pistol and real resources")
	t.eq(inventory.count(WEAPON), 1, "one physical suppressed weapon created")
	t.eq(inventory.count("pistol"), 0, "original pistol was consumed")
	t.eq(inventory.count("scrap"), 0, "scrap is spent")
	t.eq(Crafting.craft(inventory, WEAPON, true), Crafting.Result.MISSING_INPUTS,
		"repeated request cannot duplicate the upgrade")
	t.check(inventory.equip(WEAPON), "new weapon can be equipped in shared inventory")

	t.current = "server denies undertrained and remote workbench crafting"
	var world := WorldGen.new(781)
	var server := GameServer.new(world, 781)
	server.craft_quality_enabled = false # This suite checks the item itself, not quality rolls.
	var player = server.add_player(719, "QuietHunter")
	for item_id in recipe["inputs"]:
		player.inventory.add(str(item_id), int(recipe["inputs"][item_id]))
	player.position = _at(world, 180.0, 180.0)
	t.eq(server.cmd_craft(player.id, WEAPON).get("reason"), "need_skill",
		"novice cannot bypass tier-three mastery")
	player.progression.crafting_xp = 200
	t.eq(server.cmd_craft(player.id, WEAPON).get("reason"), "no_station",
		"skilled survivor still cannot craft from wilderness")
	t.eq(player.inventory.count("pistol"), 1, "invalid craft never consumes base gun")
	player.position = _at(world, GameServer.WORKBENCH_POSITION.x,
		GameServer.WORKBENCH_POSITION.y)
	t.check(bool(server.cmd_craft(player.id, WEAPON).get("ok", false)),
		"verified server crafting produces a suppressed firearm")
	t.eq(player.inventory.count(WEAPON), 1, "crafted gun belongs to the survivor")
	t.eq(player.inventory.count("pistol"), 0, "upgrade removes the original gun")
	t.eq(server.cmd_craft(player.id, WEAPON).get("reason"), "missing_inputs",
		"server rejects replayed crafting commands")
	t.check(player.inventory.equip(WEAPON), "server weapon is equipped")
	player.position = _at(world, 200.0, 200.0)

	t.current = "no ammo means no skill damage, energy cost or noise"
	var no_ammo: Dictionary = server.cmd_skill(player.id, 1.0, 0.0)
	t.eq(no_ammo.get("reason", ""), "no_ammo", "ranged ability requires a cartridge")
	t.near(player.combat_energy, Defs.COMBAT_ENERGY_MAX, 0.001,
		"refused shot does not spend combat energy")
	t.near(player.skill_timer, 0.0, 0.001, "refusal has no skill cooldown")
	t.near(player.noise_timer, 0.0, 0.001, "refusal does not attract infected")

	t.current = "genuine quiet fire and skill damage against infected"
	player.inventory.add("ammo_9mm", 3)
	var brute := Zombie.new(server.new_id(), "brute", _at(world, 225.0, 200.0))
	server.zombies[brute.id] = brute
	var hp_before: float = brute.health
	var shot: Dictionary = server.cmd_attack(player.id, 1.0, 0.0)
	t.check(bool(shot.get("ok", false)) and bool(shot.get("hit", false)),
		"existing server raycast reaches infected at 25 metres")
	t.eq(player.inventory.count("ammo_9mm"), 2, "ordinary shot spends one 9 mm round")
	t.near(brute.health, hp_before - Combat.weapon_damage(WEAPON), 0.001,
		"ordinary hit uses suppressor weapon damage")
	t.near(player.noise_radius, 12.0, 0.001,
		"server marks only twelve metre sound radius")
	t.near(player.noise_timer, 1.1, 0.001,
		"server marks limited sound duration")
	player.attack_timer = 0.0
	var energy_before: float = player.combat_energy
	var special: Dictionary = server.cmd_skill(player.id, 1.0, 0.0)
	t.check(bool(special.get("ok", false)) and bool(special.get("hit", false)),
		"unique skill uses the existing authoritative hit detection")
	t.eq(player.inventory.count("ammo_9mm"), 1, "special consumes one round")
	t.near(player.combat_energy, energy_before - float(skill["energy_cost"]), 0.001,
		"special spends configured combat energy")
	t.check(player.skill_timer > 0.0, "special starts a verified cooldown")
	t.eq(server.cmd_skill(player.id, 1.0, 0.0).get("reason"), "cooldown",
		"repeat skill packet cannot double-hit without delay")
	t.eq(player.inventory.count("ammo_9mm"), 1, "refused duplicate preserves ammo")

	t.current = "equipment and leftover ammunition survive save validation"
	var saved: Dictionary = server.character_data(player)
	t.check(server.valid_character_data(saved), "saved upgraded pistol is valid")
	var restored = server.add_player(720, "ReturnHunter", "", saved)
	t.eq(restored.inventory.count(WEAPON), 1, "reconnected survivor retains upgraded gun")
	t.eq(restored.inventory.weapon, WEAPON, "equipped upgrade is restored")
	t.eq(restored.inventory.count("ammo_9mm"), 1, "one remaining cartridge is restored")
