extends RefCounted
## Equipment-based party vulnerability with server-owned expiry, PvP safety.
const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const SunderMark = preload("res://scripts/shared/sunder_mark.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "four craftable support-damage axe tiers"
	for tier in range(1, Defs.MAX_TIER + 1):
		var name: String = "sunder_axe_%d" % tier
		var item: Dictionary = Defs.item(name)
		var recipe: Dictionary = Defs.recipes().get(name, {})
		t.eq(item.get("kind", ""), "weapon", "all axes are equipment")
		t.eq(item.get("weapon", ""), "melee", "axes train melee mastery")
		t.eq(Defs.tier_of(name), tier, "axe item tier matches resources")
		t.near(Combat.weapon_damage(name), 15.0 + 9.0 * (tier - 1),
			0.001, "axe damage scales with profession tier")
		t.near(Combat.weapon_cooldown(name), 0.94, 0.001,
			"slow axe balances team vulnerability")
		t.eq(recipe.get("station", ""), "workbench",
			"axes require workbench metalwork")
		t.eq(recipe.get("inputs", {}), {"bar_%d" % tier: 3,
			"plank_%d" % tier: 1, "fiber_%d" % tier: 2, "scrap": 1},
			"real tiered materials and scrap consumed")
		var ability: Dictionary = Combat.active_skill(name)
		t.eq(ability.get("id", ""), "sundering_chop", "axe unlocks mark")
		t.near(float(ability.get("sunder_seconds", 0.0)), 4.5,
			0.001, "mark has server-owned fixed duration")
		t.near(float(ability.get("damage", 0.0)),
			Combat.weapon_damage(name) * 1.25, 0.001,
			"skill power comes from physical weapon")
	t.eq(Combat.active_skill("dagger_1").get("id", ""),
		"finishing_strike", "dagger finisher remains distinct")

	t.current = "pure damage multiplier, time boundary and status safety"
	var target := Zombie.new(101, "brute", Vector3(201, 0, 200))
	t.near(SunderMark.amplify(20.0, target, 0.0), 20.0,
		0.001, "no mark means normal damage")
	t.check(not target.apply_sunder(0.0, INF),
		"nonfinite durations cannot mark")
	t.check(not target.apply_sunder(NAN, 2.0),
		"nonfinite server clock cannot mark")
	t.check(not target.apply_sunder(0.0, 9.0),
		"duration longer than skill limit rejected")
	t.check(target.apply_sunder(1.0, 4.5), "real target can be marked")
	t.near(SunderMark.remaining(target, 1.0), 4.5, 0.001,
		"mark lifetime begins from server clock")
	t.near(SunderMark.amplify(20.0, target, 1.0), 23.6,
		0.001, "normal infected suffer 18 percent bonus")
	t.check(target.apply_sunder(1.0, 4.5), "reapplying is permitted")
	t.near(target.sunder_until, 5.5, 0.001,
		"repeated skill cannot accumulate duration")
	t.near(SunderMark.remaining(target, 5.5), 0.0, 0.001,
		"effect expires exactly at deadline")
	t.near(SunderMark.amplify(20.0, target, 5.5), 20.0,
		0.001, "expired state is harmless even without AI tick")
	t.check(target.apply_sunder(5.5, 4.5), "later hit can refresh")
	t.near(SunderMark.remaining(target, 8.0), 2.0,
		0.001, "new deadline is bounded")
	t.check(target.apply_sunder(8.0, 2.0), "short refresh may be applied")
	t.near(target.sunder_until, 10.0, 0.001,
		"short refresh never stacks duration")
	var elite := Zombie.new(102, "brute", Vector3.ZERO)
	elite.become_elite()
	t.check(elite.apply_sunder(0.0, 4.5), "elites can be exposed")
	t.near(SunderMark.multiplier(elite, 1.0), 1.10,
		0.001, "elite vulnerability is capped at 10 percent")
	var boss := Zombie.new(103, "brute", Vector3.ZERO)
	boss.raid_boss = true
	t.check(boss.apply_sunder(0.0, 4.5), "boss may be marked")
	t.near(SunderMark.multiplier(boss, 1.0), 1.06,
		0.001, "boss vulnerability capped at 6 percent")
	boss.take_damage(100000.0)
	t.near(SunderMark.remaining(boss, 1.0), 0.0, 0.001,
		"death immediately cancels mark")
	t.check(not boss.apply_sunder(1.0, 4.5),
		"dead enemies cannot be marked")
	t.near(SunderMark.amplify(-1.0, elite, 1.0), 0.0, 0.001,
		"nonpositive fake damage remains zero")

	t.current = "workbench transactions and server profession validation"
	var bag := Inventory.new()
	bag.add("bar_1", 3)
	bag.add("plank_1", 1)
	bag.add("fiber_1", 2)
	bag.add("scrap", 1)
	t.eq(Crafting.craft(bag, "sunder_axe_1", false),
		Crafting.Result.NO_STATION, "cannot forge an axe in field")
	t.eq(bag.count("scrap"), 1, "failed craft preserves materials")
	t.eq(Crafting.craft(bag, "sunder_axe_1", true),
		Crafting.Result.OK, "workbench forges the weapon")
	t.eq(bag.count("sunder_axe_1"), 1,
		"craft places one axe in inventory")
	t.eq(Crafting.craft(bag, "sunder_axe_1", true),
		Crafting.Result.MISSING_INPUTS, "replay cannot duplicate gear")
	var world := WorldGen.new(8921)
	var sim := GameServer.new(world, 8921)
	var axeman = sim.add_player(911, "Axeman")
	axeman.inventory = Inventory.new()
	axeman.inventory.add("bar_1", 3)
	axeman.inventory.add("plank_1", 1)
	axeman.inventory.add("fiber_1", 2)
	axeman.inventory.add("scrap", 1)
	axeman.position = _at(world, 150.0, 150.0)
	t.eq(sim.cmd_craft(911, "sunder_axe_1").get("reason", ""),
		"no_station", "forging away from bench refused")
	axeman.position = _at(world, GameServer.WORKBENCH_POSITION.x,
		GameServer.WORKBENCH_POSITION.y)
	t.check(sim.cmd_craft(911, "sunder_axe_1").get("ok", false),
		"authentic workstation creates axe")
	t.eq(sim.cmd_craft(911, "sunder_axe_4").get("reason", ""),
		"need_skill", "tier four crafting needs progression")
	t.check(axeman.inventory.equip("sunder_axe_1"), "owned axe equips")
	t.eq(sim.cmd_skill(911, NAN, 0.0).get("reason", ""),
		"no_direction", "nonfinite aim is rejected")
	t.near(axeman.combat_energy, 100.0, 0.001,
		"invalid aim never consumes energy")

	t.current = "confirmed axe hit exposes server-owned infected"
	axeman.position = _at(world, 200.0, 200.0)
	var enemy := Zombie.new(sim.new_id(), "brute", _at(world, 202.0, 200.0))
	sim.zombies[enemy.id] = enemy
	var original: float = enemy.health
	var result: Dictionary = sim.cmd_skill(911, 1.0, 0.0)
	t.check(result.get("ok", false) and result.get("hit", false),
		"real melee hit applies a sunder strike")
	t.eq(result.get("hits", 0), 1, "single victim per ability")
	t.near(enemy.health, original - Combat.weapon_damage("sunder_axe_1") * 1.25,
		0.001, "first axe strike not amplified by its own mark")
	t.near(SunderMark.remaining(enemy, sim.time), 4.5, 0.001,
		"surviving enemy marked after actual damage")
	t.near(axeman.combat_energy, 66.0, 0.001,
		"server charges 34 combat energy")
	t.near(axeman.skill_timer, 9.0, 0.001,
		"server applies nine-second skill cooldown")
	t.eq(sim.cmd_skill(911, 1.0, 0.0).get("reason", ""),
		"cooldown", "replay cannot mark twice")
	var exposed: float = -1.0
	for record in sim.snapshot_for(911)["zombies"]:
		if int(record["id"]) == enemy.id:
			exposed = float(record.get("sunder_seconds", -1.0))
	t.near(exposed, 4.5, 0.001,
		"clients receive real remaining sunder duration")
	var emitted := false
	for event in sim.drain_events():
		if event.get("type", "") == "armor_sunder":
			emitted = true
			t.eq(int(event.get("id", -1)), enemy.id,
				"public effect names only the actually hit infected")
			t.check(not event.has("health") and not event.has("damage"),
				"mark event exposes no exact health or bonus calculation")
	t.check(emitted, "sunder emits one nearby visual event")

	t.current = "teammates receive temporary PvE benefit, no stacking"
	var teammate = sim.add_player(912, "Raider")
	teammate.inventory = Inventory.new()
	teammate.inventory.add("club_1", 1)
	t.check(teammate.inventory.equip("club_1"),
		"teammate owns its own melee weapon")
	teammate.position = _at(world, 200.0, 200.0)
	original = enemy.health
	var ally_hit: Dictionary = sim.cmd_attack(912, 1.0, 0.0)
	t.check(ally_hit.get("hit", false), "teammate physically strikes marked infected")
	t.near(enemy.health, original - Combat.weapon_damage("club_1") * 1.18,
		0.001, "teammate damage gains 18 percent server-only vulnerability")
	teammate.attack_timer = 0.0
	sim.time = 4.5
	original = enemy.health
	ally_hit = sim.cmd_attack(912, 1.0, 0.0)
	t.check(ally_hit.get("hit", false), "same target remains attackable after expiry")
	t.near(enemy.health, original - Combat.weapon_damage("club_1"),
		0.001, "vulnerability expires without zombie think ticks")
	t.near(SunderMark.remaining(enemy, sim.time), 0.0, 0.001,
		"expired target no longer marked in server logic")

	t.current = "boss vulnerability is capped and no PvP debuff exists"
	sim.zombies.clear()
	axeman.attack_timer = 0.0
	axeman.skill_timer = 0.0
	var raid := Zombie.new(sim.new_id(), "brute", _at(world, 202.0, 200.0))
	raid.raid_boss = true
	sim.zombies[raid.id] = raid
	t.check(sim.cmd_skill(911, 1.0, 0.0).get("hit", false),
		"boss can be marked by authentic axe strike")
	t.near(SunderMark.multiplier(raid, sim.time), 1.06, 0.001,
		"raid boss exposed bonus remains small")
	teammate.attack_timer = 0.0
	original = raid.health
	t.check(sim.cmd_attack(912, 1.0, 0.0).get("hit", false),
		"teammate lands hit on boss")
	t.near(raid.health, original - Combat.weapon_damage("club_1") * 1.06,
		0.001, "boss hit benefits only by the 6 percent cap")
	sim.zombies.clear()
	axeman.attack_timer = 0.0
	axeman.skill_timer = 0.0
	axeman.combat_energy = 100.0
	t.check(axeman.inventory.remove("sunder_axe_1", 1),
		"axe can be removed after casting")
	t.eq(sim.cmd_skill(911, 1.0, 0.0).get("reason", ""),
		"no_skill", "phantom weapon never applies vulnerability")
	axeman.inventory.add("sunder_axe_1", 1)
	t.check(axeman.inventory.equip("sunder_axe_1"),
		"real equipment can be re-equipped")
	var protected = sim.add_player(913, "Protected")
	axeman.position = _at(world, 8.0, 0.0)
	protected.position = _at(world, 10.0, 0.0)
	protected.survival.hurt(60.0)
	var health: float = protected.survival.health
	var attempt: Dictionary = sim.cmd_skill(911, 1.0, 0.0)
	t.check(attempt.get("ok", false) and not attempt.get("hit", true),
		"peaceful settlement rejects player execution")
	t.near(protected.survival.health, health, 0.001,
		"PvP victim receives neither damage nor sunder bonus")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net._event_visible_to({"type": "armor_sunder",
		"x": 200.0, "z": 200.0}, 912),
		"nearby witnesses receive exposure effect")
	t.check(not net._event_visible_to({"type": "armor_sunder",
		"x": 200.0, "z": 200.0}, 913),
		"distant recipients cannot spy on enemy positions")
	net.free()
