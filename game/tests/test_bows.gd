extends RefCounted
## Bow equipment from craftable T1-T4 through authoritative PvE/PvP and saves.

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
	t.current = "four bows use existing crafting tiers, ammo and ranged mastery"
	for tier in range(1, Defs.MAX_TIER + 1):
		var id: String = "bow_%d" % tier
		var data: Dictionary = Defs.item(id)
		var recipe: Dictionary = Defs.recipes().get(id, {})
		t.eq(data.get("weapon", ""), "ranged", "bow is ranged gear at every tier")
		t.eq(int(data.get("tier", 0)), tier, "bow tier matches its crafted ingredients")
		t.eq(data.get("ammo", ""), "arrow", "all bows use one craftable arrow type")
		t.eq(recipe.get("station", ""), "workbench", "bow crafting needs a workbench")
		t.eq(recipe.get("inputs", {}), {
			"plank_%d" % tier: 2, "fiber_%d" % tier: 2,
			"cloth_%d" % tier: 1}, "bow recipe consumes tier-matched materials")
		t.near(Combat.weapon_damage(id), 10.0 + 7.0 * (tier - 1),
			0.001, "archery damage grows with equipment tier")
		t.near(Combat.ranged_range(id), 27.0, 0.001, "bow reach is below a firearm")
		t.near(float(Combat.ranged_noise(id)["radius"]), 9.0, 0.001,
			"quiet bow noise is derived from the server item table")
	t.near(Combat.ranged_range("pistol"), Defs.PISTOL_RANGE, 0.001,
		"existing pistol retains its original reach")
	t.near(float(Combat.ranged_noise("pistol")["radius"]),
		Defs.GUNSHOT_NOISE_RADIUS, 0.001, "pistol still emits normal gunshot noise")
	t.eq(Defs.stack_size("arrow"), 80, "arrows stack for long expeditions")
	var special: Dictionary = Combat.active_skill("bow_3")
	t.eq(special.get("id", ""), "power_draw", "bow equips Power Draw")
	t.eq(special.get("ammo", ""), "arrow", "Power Draw consumes the same arrow type")
	t.check(bool(special.get("ranged", false)), "Power Draw uses ranged hit detection")
	t.near(float(special["range"]), 32.0, 0.001, "Power Draw extends bow range by 5m")
	t.near(float(special["energy_cost"]), 30.0, 0.001, "Power Draw costs thirty energy")
	t.eq(Combat.active_skill("pistol").get("id", ""), "focused_shot",
		"existing firearm ability remains available")
	t.eq(Combat.active_skill("spear_1").get("id", ""), "piercing_thrust",
		"existing melee reach ability is unchanged")

	t.current = "ordinary field crafting makes real arrows with no special station"
	var supplies := Inventory.new()
	supplies.add("wood_1", 2)
	supplies.add("fiber_1", 2)
	t.eq(Crafting.craft(supplies, "arrow", false), Crafting.Result.OK,
		"survivor can fletch arrows in the wilderness")
	t.eq(supplies.count("arrow"), 16, "one batch produces sixteen arrows")
	t.eq(supplies.count("wood_1"), 0, "field crafting consumes wood")
	t.eq(supplies.count("fiber_1"), 0, "field crafting consumes fibre")
	t.eq(Crafting.craft(supplies, "arrow", false), Crafting.Result.MISSING_INPUTS,
		"repeating an arrow craft cannot duplicate ammunition")

	t.current = "server crafting, weapon ownership and no-ammo gating"
	var world := WorldGen.new(781)
	var server := GameServer.new(world, 781)
	var archer = server.add_player(781, "WoodlandArcher")
	archer.inventory.add("plank_1", 2)
	archer.inventory.add("fiber_1", 4)
	archer.inventory.add("cloth_1", 1)
	archer.inventory.add("wood_1", 2)
	archer.position = _at(world, 180.0, 180.0)
	t.eq(server.cmd_craft(781, "bow_1").get("reason", ""), "no_station",
		"server does not forge a bow outside the workbench")
	t.eq(server.cmd_craft(781, "bow_4").get("reason", ""), "need_skill",
		"novice cannot bypass tier-four equipment mastery")
	t.check(server.cmd_craft(781, "arrow").get("ok", false),
		"server allows field arrow crafting")
	t.eq(archer.inventory.count("arrow"), 16, "server awarded sixteen real arrows")
	archer.position = _at(world, GameServer.WORKBENCH_POSITION.x,
		GameServer.WORKBENCH_POSITION.y)
	t.check(server.cmd_craft(781, "bow_1").get("ok", false), "server forges owned T1 bow")
	t.eq(server.cmd_craft(781, "bow_1").get("reason", ""), "missing_inputs",
		"replayed craft cannot create infinite bows")
	t.eq(archer.inventory.count("bow_1"), 1, "survivor carries exactly one crafted bow")
	t.check(archer.inventory.equip("bow_1"), "craftable bow can be equipped")
	archer.position = _at(world, 200.0, 200.0)
	t.check(archer.inventory.remove("arrow", 16), "remove crafted arrows for no-ammo check")
	t.eq(server.cmd_skill(781, 1.0, 0.0).get("reason", ""), "no_ammo",
		"server denies ranged ability without physical arrows")
	t.near(archer.combat_energy, 100.0, 0.001,
		"missing ammunition does not spend combat energy")
	t.near(archer.skill_timer, 0.0, 0.001,
		"no-ammo denial does not start ability cooldown")
	t.near(archer.noise_timer, 0.0, 0.001,
		"rejected arrow emits no threat-attracting noise")

	t.current = "quiet normal shot hits an infected at bow distance"
	archer.inventory.add("arrow", 4)
	var brute := Zombie.new(server.new_id(), "brute", _at(world, 225.0, 200.0))
	server.zombies[brute.id] = brute
	var before: float = brute.health
	var first: Dictionary = server.cmd_attack(781, 1.0, 0.0)
	t.check(first.get("ok", false) and first.get("hit", false),
		"authoritative arrow hits a brute at twenty-five metres")
	t.near(brute.health, before - Combat.weapon_damage("bow_1"),
		0.001, "normal bow attack deals the real equipment damage")
	t.eq(archer.inventory.count("arrow"), 3, "normal shot consumes one arrow")
	t.near(archer.noise_radius, 9.0, 0.001,
		"arrow shot is much quieter than a gunshot")
	t.near(archer.noise_timer, 0.8, 0.001,
		"quiet arrow only alerts infected briefly")
	t.near(archer.attack_timer, Combat.weapon_cooldown("bow_1"),
		0.001, "bow has its own slower attack interval")

	t.current = "power draw uses ammo, mastery, energy and extended range"
	server.zombies.erase(brute.id)
	var distant := Zombie.new(server.new_id(), "brute", _at(world, 230.0, 200.0))
	server.zombies[distant.id] = distant
	archer.attack_timer = 0.0
	before = distant.health
	var power: Dictionary = server.cmd_skill(781, 1.0, 0.0)
	t.check(power.get("ok", false) and power.get("hit", false),
		"Power Draw reaches infected beyond ordinary bow range")
	t.eq(power.get("hits", 0), 1, "Power Draw strikes only one target")
	t.near(distant.health, before - Combat.weapon_damage("bow_1") * 1.6,
		0.001, "Power Draw deals server-owned multiplied damage")
	t.eq(archer.inventory.count("arrow"), 2, "active ability costs one arrow")
	t.near(archer.combat_energy, 70.0, 0.001, "active ability spends thirty energy")
	t.near(archer.skill_timer, 6.0, 0.001, "server starts six-second ability cooldown")
	t.near(archer.noise_radius, 9.0, 0.001, "Power Draw is as quiet as a normal bow")
	t.eq(server.cmd_skill(781, 1.0, 0.0).get("reason", ""), "cooldown",
		"repeated ability requests cannot duplicate arrow damage")
	t.eq(archer.inventory.count("arrow"), 2, "cooldown denial preserves arrows")
	archer.attack_timer = 0.0
	archer.skill_timer = 0.0
	archer.progression.award_combat("bow_1", 80)
	t.eq(archer.progression.combat_level("ranged"), 2,
		"archery levels the existing persistent ranged mastery")
	before = distant.health
	t.check(server.cmd_skill(781, 1.0, 0.0).get("hit", false),
		"trained archer may use the same skill")
	t.near(distant.health, before - Combat.weapon_damage("bow_1") * 1.6 * 1.03,
		0.001, "ranged mastery buffs bow ability on the server")
	t.eq(archer.inventory.count("arrow"), 1, "mastery cannot bypass arrow consumption")

	t.current = "invalid aim, insufficient energy and stale gear remain atomic"
	archer.attack_timer = 0.0
	archer.skill_timer = 0.0
	archer.combat_energy = 100.0
	t.eq(server.cmd_skill(781, 0.0, 0.0).get("reason", ""), "no_direction",
		"zero aim is rejected")
	t.eq(server.cmd_skill(781, 1e300, 0.0).get("reason", ""), "no_direction",
		"overflowing finite aim is rejected")
	t.eq(archer.inventory.count("arrow"), 1, "invalid aim cannot waste arrows")
	archer.combat_energy = 29.0
	t.eq(server.cmd_skill(781, 1.0, 0.0).get("reason", ""), "no_energy",
		"server rejects insufficient combat energy")
	t.eq(archer.inventory.count("arrow"), 1, "energy denial does not remove arrows")
	t.near(archer.skill_timer, 0.0, 0.001, "energy denial does not start cooldown")
	archer.combat_energy = 100.0
	t.check(archer.inventory.remove("bow_1", 1), "remove actually equipped bow")
	t.eq(server.cmd_skill(781, 1.0, 0.0).get("reason", ""), "no_skill",
		"stale equipped item ID cannot grant bow ability")

	t.current = "safe settlement retains PvP protection and character persistence"
	archer.inventory.add("bow_1", 1)
	t.check(archer.inventory.equip("bow_1"), "return bow to inventory")
	archer.position = _at(world, 8.0, 0.0)
	var safe_player = server.add_player(782, "SafeNeighbor")
	safe_player.position = _at(world, 10.0, 0.0)
	var safe_health: float = safe_player.survival.health
	archer.skill_timer = 0.0
	archer.attack_timer = 0.0
	var safe: Dictionary = server.cmd_skill(781, 1.0, 0.0)
	t.check(safe.get("ok", false) and not safe.get("hit", true),
		"bow skill cannot attack players in safe settlement")
	t.near(safe_player.survival.health, safe_health, 0.001,
		"safe player takes no damage from bow abilities")
	t.eq(archer.inventory.count("arrow"), 0,
		"valid but missed shot still spends its one physical arrow")
	var saved: Dictionary = server.character_data(archer)
	t.check(server.valid_character_data(saved), "bow and arrow inventory passes save validation")
	archer.inventory.remove("bow_1", 1)
	t.check(server.apply_character(archer, saved), "server restores original bow inventory")
	t.eq(archer.inventory.count("bow_1"), 1, "owned bow survives logout")
	t.eq(archer.progression.combat_level("ranged"), 2,
		"earned ranged mastery persists after reload")
