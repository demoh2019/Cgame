extends RefCounted
## Server-owned classless healer weapon, reach, party and resource safety.
const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const RestorationStaff = preload("res://scripts/shared/restoration_staff.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "tiered restorative staffs are real crafted equipment"
	for tier in range(1, Defs.MAX_TIER + 1):
		var id: String = "restoration_staff_%d" % tier
		var data: Dictionary = Defs.item(id)
		var recipe: Dictionary = Defs.recipes().get(id, {})
		t.eq(data.get("kind", ""), "weapon", "healer equipment fits weapon slot")
		t.eq(data.get("weapon", ""), "melee", "normal weak hits keep melee rules")
		t.eq(data.get("tier", 0), tier, "staff uses matching crafting progression")
		t.eq(recipe.get("station", ""), "workbench", "staff needs a workbench")
		t.eq(recipe.get("inputs", {}), {"plank_%d" % tier: 2,
			"cloth_%d" % tier: 2, "bar_%d" % tier: 1,
			"field_antiseptic": 1}, "artisan gear consumes medical supplies")
		var active: Dictionary = Combat.active_skill(id)
		t.eq(active.get("id", ""), "restoration_pulse",
			"staff unlocks a restorative G ability")
		t.near(float(active.get("party_heal", -1.0)),
			RestorationStaff.heal_for_tier(tier), 0.001,
			"healing scales with craft tier, never client commands")
	t.eq(Combat.active_skill("machete_1").get("id", ""), "cleaving_arc",
		"restorative weapon does not replace existing combat skills")
	t.eq(Combat.active_skill("spear_1").get("id", ""), "piercing_thrust",
		"other weapon abilities are unchanged")
	t.check(RestorationStaff.can_reach(Vector3.ZERO, Vector3(8, 0, 0)),
		"pulse includes teammates at exactly its radius")
	t.check(not RestorationStaff.can_reach(Vector3.ZERO, Vector3(8.1, 0, 0)),
		"too-distant allies cannot receive healing")
	t.check(not RestorationStaff.can_reach(Vector3.ZERO, Vector3(0, 3, 0)),
		"pulse cannot cross high floors")
	t.check(not RestorationStaff.can_reach(Vector3(NAN, 0, 0), Vector3.ZERO),
		"invalid positions cannot bypass server range")
	t.eq(RestorationStaff.urgency(100.0, 100.0), 0.0,
		"fully healed characters have no priority")
	t.eq(RestorationStaff.urgency(NAN, 100.0), 0.0,
		"bad health values cannot select recipients")

	t.current = "materials are spent once; no field-crafting exploit"
	var bag := Inventory.new()
	bag.add("plank_1", 2)
	bag.add("cloth_1", 2)
	bag.add("bar_1", 1)
	bag.add("field_antiseptic", 1)
	t.eq(Crafting.craft(bag, "restoration_staff_1", false),
		Crafting.Result.NO_STATION, "field craft is forbidden")
	t.eq(bag.count("field_antiseptic"), 1, "failed craft preserves antiseptic")
	t.eq(Crafting.craft(bag, "restoration_staff_1", true),
		Crafting.Result.OK, "paid recipe creates one staff")
	t.eq(bag.count("restoration_staff_1"), 1, "weapon enters inventory")
	t.eq(bag.count("field_antiseptic"), 0, "craft spends medical input")
	t.eq(Crafting.craft(bag, "restoration_staff_1", true),
		Crafting.Result.MISSING_INPUTS, "replaying a recipe cannot duplicate staff")

	t.current = "server validates actual equipment, group and patient"
	var world := WorldGen.new(1198)
	var server := GameServer.new(world, 1198)
	var healer = server.add_player(701, "Restorer")
	var first = server.add_player(702, "Wounded")
	var second = server.add_player(703, "Critical")
	var third = server.add_player(704, "LightlyHurt")
	var outsider = server.add_player(705, "Outsider")
	healer.inventory = Inventory.new()
	healer.inventory.add("plank_1", 2)
	healer.inventory.add("cloth_1", 2)
	healer.inventory.add("bar_1", 1)
	healer.inventory.add("field_antiseptic", 1)
	healer.position = _at(world, 140.0, 140.0)
	t.eq(server.cmd_craft(701, "restoration_staff_1").get("reason", ""),
		"no_station", "server rejects distant crafting")
	healer.position = _at(world, GameServer.WORKBENCH_POSITION.x,
		GameServer.WORKBENCH_POSITION.y)
	t.check(server.cmd_craft(701, "restoration_staff_1").get("ok", false),
		"server accepts valid station craft")
	t.eq(server.cmd_craft(701, "restoration_staff_4").get("reason", ""),
		"need_skill", "advanced staff cannot bypass crafting mastery")
	t.check(healer.inventory.equip("restoration_staff_1"),
		"staff equips through standard inventory")
	t.eq(server.cmd_skill(701, 1.0, 0.0).get("reason", ""),
		"not_in_party", "no self-healing or imaginary allies")
	t.near(healer.combat_energy, 100.0, 0.001,
		"rejected solo skill spends no energy")
	for id in [702, 703, 704]:
		var member = server.players[id]
		member.position = healer.position + Vector3(0.2, 0.0, 0.2)
		t.check(server.cmd_party_invite(701, id).get("ok", false),
			"healer invites consenting group member")
		t.check(server.cmd_party_accept(id).get("ok", false),
			"member joins group")
	healer.position = _at(world, 200.0, 200.0)
	first.position = _at(world, 201.0, 200.0)
	second.position = _at(world, 201.8, 200.0)
	third.position = _at(world, 202.4, 200.0)
	outsider.position = _at(world, 201.2, 200.0)
	first.survival.hurt(30.0)
	second.survival.hurt(60.0)
	third.survival.hurt(10.0)
	outsider.survival.hurt(80.0)
	healer.survival.hurt(20.0)
	t.eq(server.cmd_skill(701, NAN, 0.0).get("reason", ""),
		"no_direction", "invalid aim does not activate a heal")
	var outcome: Dictionary = server.cmd_skill(701, 1.0, 0.0)
	t.check(outcome.get("ok", false), "staff pulse heals current group")
	t.eq(outcome.get("treated", 0), 2, "up to two most wounded allies selected")
	t.near(float(outcome.get("healed", 0.0)), 24.0, 0.001,
		"two injured allies each gain exactly twelve health")
	t.near(first.survival.health, 82.0, 0.001,
		"second-most injured ally is restored")
	t.near(second.survival.health, 52.0, 0.001,
		"most injured ally is restored")
	t.near(third.survival.health, 90.0, 0.001,
		"least wounded party member is not selected")
	t.near(outsider.survival.health, 20.0, 0.001,
		"nearby nonmember is never healed")
	t.near(healer.survival.health, 80.0, 0.001,
		"pulse does not self-heal")
	t.near(healer.combat_energy, 60.0, 0.001,
		"single pulse costs forty authoritative combat energy")
	t.near(healer.skill_timer, 12.0, 0.001,
		"single pulse starts a twelve-second cooldown")
	t.eq(server.cmd_skill(701, 1.0, 0.0).get("reason", ""),
		"cooldown", "replayed skill cannot heal again")
	var events: Array = server.drain_events()
	var found: bool = false
	for event in events:
		if event.get("type", "") == "restoration_pulse":
			found = true
			t.check(not event.has("recipients") and not event.has("health"),
				"public healing effect reveals no recipient health")
	t.check(found, "server announces the visual pulse")

	t.current = "failed healing consumes no energy or cooldown"
	healer.skill_timer = 0.0
	healer.attack_timer = 0.0
	first.survival.heal(100.0)
	second.survival.heal(100.0)
	third.survival.heal(100.0)
	t.eq(server.cmd_skill(701, 1.0, 0.0).get("reason", ""),
		"no_wounded_allies", "healthy squad cannot waste a pulse")
	t.near(healer.combat_energy, 60.0, 0.001,
		"no-effect pulse has no energy cost")
	first.survival.hurt(10.0)
	first.position = _at(world, 240.0, 240.0)
	t.eq(server.cmd_skill(701, 1.0, 0.0).get("reason", ""),
		"no_wounded_allies", "distant injured member is not targeted")
	first.position = _at(world, 201.0, 200.0)
	healer.combat_energy = 39.0
	t.eq(server.cmd_skill(701, 1.0, 0.0).get("reason", ""),
		"no_energy", "insufficient energy blocks healing")
	t.near(first.survival.health, 90.0, 0.001,
		"failed heal never changes patient health")
	healer.combat_energy = 100.0
	t.check(healer.inventory.remove("restoration_staff_1", 1),
		"carried healer gear can be removed")
	t.eq(server.cmd_skill(701, 1.0, 0.0).get("reason", ""),
		"no_skill", "stale equipment cannot cast spells")
	t.near(healer.combat_energy, 100.0, 0.001,
		"ghost weapon cannot consume energy")
