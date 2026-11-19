extends RefCounted
## Integrated classless spear family: T1–T4 recipes, reach and real server combat.
const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "tiered spears participate in the real crafting and equipment economy"
	for tier in range(1, Defs.MAX_TIER + 1):
		var spear_id: String = "spear_%d" % tier
		var data: Dictionary = Defs.item(spear_id)
		var recipe: Dictionary = Defs.recipes().get(spear_id, {})
		t.check(not data.is_empty(), "spear item exists at each resource tier")
		t.eq(data.get("kind", ""), "weapon", "spear is equipable weapon")
		t.eq(data.get("weapon", ""), "melee", "spear uses shared melee mastery")
		t.eq(Defs.tier_of(spear_id), tier, "spear requires matching craft mastery")
		t.eq(recipe.get("station", ""), "workbench", "spear needs real workbench")
		t.eq(recipe.get("output", ""), spear_id, "spear recipe produces its own tier")
		t.eq(recipe.get("inputs", {}), {
			"plank_%d" % tier: 2, "bar_%d" % tier: 1, "fiber_%d" % tier: 2},
			"recipe spends tier-matched wood, metal and fibre")
		t.near(Combat.weapon_reach(spear_id), 3.5, 0.001,
			"spear reaches farther than club at every tier")
	t.near(Combat.weapon_reach("club_1"), Defs.MELEE_RANGE, 0.001,
		"existing club reach remains unchanged")
	t.near(Combat.weapon_reach("pistol"), Defs.MELEE_RANGE, 0.001,
		"non-spear weapons cannot inherit extended melee reach")
	var thrust: Dictionary = Combat.active_skill("spear_1")
	t.eq(thrust.get("id", ""), "piercing_thrust", "equipping spear unlocks piercing thrust")
	t.near(float(thrust.get("energy_cost", 0.0)), 25.0, 0.001, "thrust costs 25 energy")
	t.near(float(thrust.get("range", 0.0)), 4.5, 0.001,
		"thrust extends regular spear attack by one metre")
	t.check(not bool(thrust.get("ranged", true)), "spear thrust is melee and uses no cartridges")
	t.eq(Combat.active_skill("club_1").get("id", ""), "heavy_strike",
		"existing club skill is retained")
	t.eq(Combat.active_skill("pistol").get("id", ""), "focused_shot",
		"existing pistol skill is retained")

	t.current = "materials must be paid and a workbench must be available"
	var bag := Inventory.new()
	bag.add("plank_1", 2)
	bag.add("bar_1", 1)
	bag.add("fiber_1", 2)
	t.eq(Crafting.craft(bag, "spear_1", false), Crafting.Result.NO_STATION,
		"cannot create weapon in field without workbench")
	t.eq(bag.count("plank_1"), 2, "failed forge keeps planks")
	t.eq(Crafting.craft(bag, "spear_1", true), Crafting.Result.OK,
		"equipping the workbench creates one real spear")
	t.eq(bag.count("spear_1"), 1, "crafting produces one usable spear")
	t.eq(bag.count("plank_1"), 0, "crafting consumes wood")
	t.eq(bag.count("bar_1"), 0, "crafting consumes metal")
	t.eq(bag.count("fiber_1"), 0, "crafting consumes fibre")
	t.eq(Crafting.craft(bag, "spear_1", true), Crafting.Result.MISSING_INPUTS,
		"repeat craft cannot duplicate gear")

	t.current = "authoritative game craft requires profession and workstation"
	var world := WorldGen.new(510)
	var server := GameServer.new(world, 510)
	var player = server.add_player(510, "SpearBearer")
	player.inventory = Inventory.new()
	player.inventory.add("plank_1", 2)
	player.inventory.add("bar_1", 1)
	player.inventory.add("fiber_1", 2)
	player.position = _at(world, 150.0, 150.0)
	t.eq(server.cmd_craft(510, "spear_1").get("reason", ""), "no_station",
		"server enforces actual crafting station")
	player.position = _at(world, GameServer.WORKBENCH_POSITION.x, GameServer.WORKBENCH_POSITION.y)
	t.check(server.cmd_craft(510, "spear_1").get("ok", false),
		"legitimate server bench craft creates spear")
	t.eq(player.inventory.count("spear_1"), 1, "server inventory contains actual crafted spear")
	t.eq(server.cmd_craft(510, "spear_1").get("reason", ""), "missing_inputs",
		"replaying a forge request cannot mint weapons")
	t.eq(server.cmd_craft(510, "spear_4").get("reason", ""), "need_skill",
		"tier four forging requires tier four crafting mastery")
	t.check(player.inventory.equip("spear_1"), "survivor equips crafted spear")

	t.current = "extended reach hits infected beyond club distance without ammunition"
	player.position = _at(world, 200.0, 200.0)
	var infected := Zombie.new(server.new_id(), "brute", _at(world, 203.2, 200.0))
	server.zombies[infected.id] = infected
	var hp_before: float = infected.health
	var hit: Dictionary = server.cmd_attack(510, 1.0, 0.0)
	t.check(hit.get("ok", false) and hit.get("hit", false), "spear hit lands at 3.2 metres")
	t.eq(hit.get("target", ""), "zombie", "real target is infected")
	t.near(infected.health, hp_before - Combat.weapon_damage("spear_1"), 0.001,
		"weapon base damage is applied once to infected")
	t.near(player.attack_timer, Combat.weapon_cooldown("spear_1"), 0.001,
		"server enforces spear attack cadence")
	player.attack_timer = 0.0
	player.inventory.add("club_1", 1)
	t.check(player.inventory.equip("club_1"), "club can replace spear without character respec")
	hp_before = infected.health
	t.check(not server.cmd_attack(510, 1.0, 0.0).get("hit", true),
		"club cannot hit the same distant target")
	t.near(infected.health, hp_before, 0.001, "missed club swing deals no damage")
	player.attack_timer = 0.0
	t.check(player.inventory.equip("spear_1"), "can freely re-equip spear")
	server.zombies.erase(infected.id)

	t.current = "piercing thrust spends server energy, locks attacks and uses melee mastery"
	var brute := Zombie.new(server.new_id(), "brute", _at(world, 204.25, 200.0))
	server.zombies[brute.id] = brute
	hp_before = brute.health
	var result: Dictionary = server.cmd_skill(510, 1.0, 0.0)
	t.check(result.get("ok", false) and result.get("hit", false),
		"server thrust connects outside regular spear distance")
	t.eq(result.get("target", ""), "zombie", "thrust targets real infected")
	t.near(brute.health, hp_before - Combat.weapon_damage("spear_1") * 1.45,
		0.001, "thrust uses server damage multiplier")
	t.near(player.combat_energy, 75.0, 0.001, "thrust charges exactly 25 energy")
	t.near(player.skill_timer, 5.5, 0.001, "skill cooldown is authoritative")
	t.eq(server.cmd_skill(510, 1.0, 0.0).get("reason", ""), "cooldown",
		"repeat skill cannot attack during cooldown")
	t.eq(server.cmd_attack(510, 1.0, 0.0).get("reason", ""), "cooldown",
		"regular attacks share thrust's lock")
	player.attack_timer = 0.0
	player.skill_timer = 0.0
	player.combat_energy = 24.0
	t.eq(server.cmd_skill(510, 1.0, 0.0).get("reason", ""), "no_energy",
		"no energy means no thrust")
	t.near(player.skill_timer, 0.0, 0.001, "failed skill cannot set cooldown")
	player.combat_energy = 100.0
	t.eq(server.cmd_skill(510, 0.0, 0.0).get("reason", ""), "no_direction",
		"invalid aim cannot start thrust")
	t.eq(server.cmd_skill(510, 1e300, 0.0).get("reason", ""), "no_direction",
		"overflowing finite aim magnitude is rejected")
	t.near(player.combat_energy, 100.0, 0.001, "invalid aim cannot spend energy")
	player.progression.award_combat("spear_1", 80)
	t.eq(player.progression.combat_level("melee"), 2, "spear victories share melee mastery")
	hp_before = brute.health
	t.check(server.cmd_skill(510, 1.0, 0.0).get("hit", false),
		"experienced survivor can still use the equipped ability")
	t.near(brute.health, hp_before - Combat.weapon_damage("spear_1") * 1.45 * 1.03,
		0.001, "thrust damage scales with server-held melee mastery")
	player.skill_timer = 0.0
	player.attack_timer = 0.0
	player.combat_energy = 100.0
	t.check(player.inventory.remove("spear_1", 1), "remove the equipped crafted spear")
	t.eq(server.cmd_skill(510, 1.0, 0.0).get("reason", ""), "no_skill",
		"stale equipment cannot grant free special attack")

	t.current = "safe settlement cannot be attacked through longer spear reach"
	player.inventory.add("spear_1", 1)
	t.check(player.inventory.equip("spear_1"), "re-equip spear")
	player.position = _at(world, 8.0, 0.0)
	var neighbor = server.add_player(511, "SafeNeighbor")
	neighbor.position = _at(world, 11.8, 0.0)
	var health_before: float = neighbor.survival.health
	var safe: Dictionary = server.cmd_skill(510, 1.0, 0.0)
	t.check(safe.get("ok", false) and not safe.get("hit", true),
		"extended spear skill respects the protected settlement")
	t.near(neighbor.survival.health, health_before, 0.001,
		"safe-hub player takes no melee skill damage")
