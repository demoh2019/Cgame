extends RefCounted
## Real server-authoritative scrap machetes and multi-target cone attacks.
const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "machete tiers use scrap and real crafting professions"
	for tier in range(1, Defs.MAX_TIER + 1):
		var id: String = "machete_%d" % tier
		var item: Dictionary = Defs.item(id)
		var recipe: Dictionary = Defs.recipes().get(id, {})
		t.eq(item.get("kind", ""), "weapon", "each tier registers a weapon")
		t.eq(item.get("weapon", ""), "melee", "machetes share melee mastery")
		t.eq(Defs.tier_of(id), tier, "item tier matches metalwork tier")
		t.eq(recipe.get("station", ""), "workbench", "requires a workbench")
		t.eq(recipe.get("inputs", {}), {
			"plank_%d" % tier: 2, "bar_%d" % tier: 2, "scrap": 1},
			"recipe combines scavenged scrap with tiered materials")
		t.eq(Combat.active_skill(id).get("id", ""), "cleaving_arc",
			"all machete tiers provide a cleave")
	var arc: Dictionary = Combat.active_skill("machete_1")
	t.eq(int(arc["cleave_targets"]), 3, "arc has bounded target count")
	t.eq(bool(arc["ranged"]), false, "arc uses melee collision, not a projectile")
	t.eq(Combat.active_skill("spear_1").get("id", ""), "piercing_thrust",
		"the existing spear still uses piercing thrust")

	var inventory := Inventory.new()
	inventory.add("plank_1", 2)
	inventory.add("bar_1", 2)
	inventory.add("scrap", 1)
	t.eq(Crafting.craft(inventory, "machete_1", false), Crafting.Result.NO_STATION,
		"field crafting is rejected without consuming materials")
	t.eq(inventory.count("scrap"), 1, "failed crafting preserves scrap")
	t.eq(Crafting.craft(inventory, "machete_1", true), Crafting.Result.OK,
		"bench produces the paid-for machete")
	t.eq(inventory.count("machete_1"), 1, "crafted weapon enters inventory")
	t.eq(inventory.count("scrap"), 0, "crafting consumes scavenged metal")
	t.eq(Crafting.craft(inventory, "machete_1", true), Crafting.Result.MISSING_INPUTS,
		"replay cannot duplicate a crafted machete")

	t.current = "server enforces bench, mastery and actual equipment"
	var world := WorldGen.new(8921)
	var server := GameServer.new(world, 8921)
	var player = server.add_player(920, "Cleaver")
	player.inventory = Inventory.new()
	player.inventory.add("plank_1", 2)
	player.inventory.add("bar_1", 2)
	player.inventory.add("scrap", 1)
	player.position = _at(world, 150.0, 150.0)
	t.eq(server.cmd_craft(920, "machete_1").get("reason", ""), "no_station",
		"server rejects remote workbench requests")
	player.position = _at(world, GameServer.WORKBENCH_POSITION.x,
		GameServer.WORKBENCH_POSITION.y)
	t.check(server.cmd_craft(920, "machete_1").get("ok", false),
		"server crafts machete from real materials at workbench")
	t.eq(server.cmd_craft(920, "machete_4").get("reason", ""), "need_skill",
		"tier four needs the matching crafting level")
	t.check(player.inventory.equip("machete_1"), "crafting result can be equipped")
	t.eq(server.cmd_skill(920, 0.0, 0.0).get("reason", ""), "no_direction",
		"invalid direction does not trigger a sweep")
	t.near(player.combat_energy, 100.0, 0.001, "invalid arc costs no energy")

	t.current = "one server-owned frontal cone hits three infected, not enemies behind"
	player.position = _at(world, 200.0, 200.0)
	var targets: Array = []
	for offset in [Vector2(1.7, 0.0), Vector2(1.7, 1.3),
			Vector2(1.7, -1.3)]:
		var infected := Zombie.new(server.new_id(), "brute",
			_at(world, 200.0 + offset.x, 200.0 + offset.y))
		server.zombies[infected.id] = infected
		targets.append(infected)
	var flank := Zombie.new(server.new_id(), "brute", _at(world, 200.0, 202.0))
	server.zombies[flank.id] = flank
	var behind := Zombie.new(server.new_id(), "brute", _at(world, 198.0, 200.0))
	server.zombies[behind.id] = behind
	var expected_damage: float = Combat.weapon_damage("machete_1") * 1.35
	var hit: Dictionary = server.cmd_skill(920, 1.0, 0.0)
	t.check(hit.get("ok", false) and hit.get("hit", false), "cleave resolves a real hit")
	t.eq(hit.get("hits", 0), 3, "one cast hits at most three different targets")
	for infected in targets:
		t.near(infected.health, float(infected.data["health"]) - expected_damage,
			0.001, "each infected takes damage exactly once")
	t.near(flank.health, float(flank.data["health"]), 0.001,
		"enemy outside the melee cone remains unharmed")
	t.near(behind.health, float(behind.data["health"]), 0.001,
		"enemy behind the player remains unharmed")
	t.near(player.combat_energy, 72.0, 0.001, "one sweep spends 28 energy")
	t.near(player.skill_timer, 7.0, 0.001, "one sweep starts a seven-second cooldown")
	t.eq(server.cmd_skill(920, 1.0, 0.0).get("reason", ""), "cooldown",
		"replayed swing does not hit or charge energy again")
	player.skill_timer = 0.0
	player.attack_timer = 0.0
	player.combat_energy = 27.0
	t.eq(server.cmd_skill(920, 1.0, 0.0).get("reason", ""), "no_energy",
		"insufficient energy blocks the whole cast")
	t.near(player.combat_energy, 27.0, 0.001, "failed cast cannot subtract energy")

	t.current = "no ghost gear and protected settlement PvP"
	player.combat_energy = 100.0
	t.check(player.inventory.remove("machete_1", 1),
		"owned melee weapon can be removed")
	t.eq(server.cmd_skill(920, 1.0, 0.0).get("reason", ""), "no_skill",
		"stale equipped ID cannot cast Cleaving Arc")
	t.near(player.combat_energy, 100.0, 0.001, "ghost weapon does not cost energy")
	player.inventory.add("machete_1", 1)
	t.check(player.inventory.equip("machete_1"), "re-equip carried machete")
	var peaceful = server.add_player(921, "Protected")
	player.position = _at(world, 8.0, 0.0)
	peaceful.position = _at(world, 9.6, 0.0)
	var before_health: float = peaceful.survival.health
	var safe: Dictionary = server.cmd_skill(920, 1.0, 0.0)
	t.check(safe.get("ok", false) and not safe.get("hit", true),
		"cleave does not hit another survivor in the safe settlement")
	t.near(peaceful.survival.health, before_health, 0.001,
		"safe-zone protection applies to every potential cone target")
