extends RefCounted
## Crafting and high-risk equipment-gated PvE execution, no PvP bonus.
const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const FinishingStrike = preload("res://scripts/shared/finishing_strike.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func _brute(server, world, wounded: bool = false, elite: bool = false,
		boss: bool = false):
	var enemy := Zombie.new(server.new_id(), "brute",
		_at(world, 202.0, 200.0))
	if elite:
		enemy.become_elite()
	enemy.raid_boss = boss
	if wounded:
		enemy.health = float(enemy.data["health"]) * 0.3
	server.zombies[enemy.id] = enemy
	return enemy


func run(t) -> void:
	t.current = "four craftable dagger tiers and classless execute ability"
	for tier in range(1, Defs.MAX_TIER + 1):
		var weapon: String = "dagger_%d" % tier
		var item: Dictionary = Defs.item(weapon)
		var recipe: Dictionary = Defs.recipes().get(weapon, {})
		t.eq(item.get("kind", ""), "weapon", "dagger is real carried gear")
		t.eq(item.get("weapon", ""), "melee", "daggers use melee mastery")
		t.eq(Defs.tier_of(weapon), tier, "dagger uses matching crafting tier")
		t.near(Combat.weapon_damage(weapon), 11.0 + 6.0 * (tier - 1),
			0.001, "base damage progresses across tiers")
		t.near(Combat.weapon_cooldown(weapon), 0.55, 0.001,
			"daggers trade reach and burst for quick normal strikes")
		t.eq(recipe.get("station", ""), "workbench",
			"smithing requires a workbench")
		t.eq(recipe.get("inputs", {}), {"bar_%d" % tier: 2,
			"plank_%d" % tier: 1, "cloth_%d" % tier: 1, "scrap": 1},
			"real tiered materials are consumed")
		var skill: Dictionary = Combat.active_skill(weapon)
		t.eq(skill.get("id", ""), "finishing_strike",
			"each tier unlocks the same precision finisher")
		t.near(float(skill.get("execute_threshold", 0.0)), 0.35, 0.001,
			"execution threshold is server equipment data")
		t.near(float(skill.get("damage", 0.0)),
			Combat.weapon_damage(weapon) * 1.4, 0.001,
			"base ability strength comes from forged weapon")
		t.eq(skill.get("ranged", true), false, "finisher uses melee hit cone")
	t.eq(Combat.active_skill("sledgehammer_1").get("id", ""),
		"concussive_blow", "heavy weapons still use stagger")
	t.eq(Combat.active_skill("machete_1").get("id", ""), "cleaving_arc",
		"machetes still cleave")
	t.eq(Combat.active_skill("spear_1").get("id", ""), "piercing_thrust",
		"spears retain piercing thrust")

	t.current = "execution threshold, enemy resistance, invalid values"
	t.near(FinishingStrike.multiplier(100, 100, false, false),
		1.0, 0.001, "healthy infected never suffer bonus")
	t.near(FinishingStrike.multiplier(36, 100, false, false),
		1.0, 0.001, "health above threshold is never executed")
	t.near(FinishingStrike.multiplier(35, 100, false, false),
		2.0, 0.001, "exact threshold triggers execution")
	t.near(FinishingStrike.multiplier(20, 100, true, false),
		1.5, 0.001, "elite infected resist part of execute bonus")
	t.near(FinishingStrike.multiplier(20, 100, true, true),
		1.2, 0.001, "boss resistance overrides elite calculation")
	for bad in [NAN, INF, -10.0, 0.0, 110.0]:
		t.near(FinishingStrike.multiplier(bad, 100.0, false, false),
			1.0, 0.001, "invalid or already-dead health cannot execute")
	t.near(FinishingStrike.multiplier(20.0, NAN, false, false),
		1.0, 0.001, "invalid maximum health prevents execution")
	t.near(FinishingStrike.multiplier(20.0, 0.0, false, false),
		1.0, 0.001, "zero maximum health cannot divide")

	t.current = "workbench inventory transaction is paid exactly once"
	var bag := Inventory.new()
	bag.add("bar_1", 2)
	bag.add("plank_1", 1)
	bag.add("cloth_1", 1)
	bag.add("scrap", 1)
	t.eq(Crafting.craft(bag, "dagger_1", false),
		Crafting.Result.NO_STATION, "field crafting is not allowed")
	t.eq(bag.count("scrap"), 1, "refused craft preserves ingredients")
	t.eq(Crafting.craft(bag, "dagger_1", true),
		Crafting.Result.OK, "workbench can forge a dagger")
	t.eq(bag.count("dagger_1"), 1, "one crafted weapon enters inventory")
	t.eq(bag.count("scrap"), 0, "crafting spends scavenged scrap")
	t.eq(Crafting.craft(bag, "dagger_1", true),
		Crafting.Result.MISSING_INPUTS, "craft retry never duplicates weapons")

	t.current = "server crafting and equipped inventory validation"
	var world := WorldGen.new(8921)
	var server := GameServer.new(world, 8921)
	var player = server.add_player(930, "DaggerHunter")
	player.inventory = Inventory.new()
	player.inventory.add("bar_1", 2)
	player.inventory.add("plank_1", 1)
	player.inventory.add("cloth_1", 1)
	player.inventory.add("scrap", 1)
	player.position = _at(world, 150.0, 150.0)
	t.eq(server.cmd_craft(930, "dagger_1").get("reason", ""),
		"no_station", "server prevents distant smithing")
	player.position = _at(world, GameServer.WORKBENCH_POSITION.x,
		GameServer.WORKBENCH_POSITION.y)
	t.check(server.cmd_craft(930, "dagger_1").get("ok", false),
		"server forges real dagger at a workbench")
	t.eq(server.cmd_craft(930, "dagger_4").get("reason", ""),
		"need_skill", "high tier requires learned crafting")
	t.check(player.inventory.equip("dagger_1"),
		"real dagger may be equipped")
	t.eq(server.cmd_skill(930, NAN, 0.0).get("reason", ""),
		"no_direction", "nonfinite direction cannot trigger execution")
	t.near(player.combat_energy, 100.0, 0.001,
		"invalid request never spends combat energy")

	t.current = "normal skill strikes a healthy infected without execute"
	player.position = _at(world, 200.0, 200.0)
	var healthy = _brute(server, world)
	var before: float = healthy.health
	var skill: Dictionary = server.cmd_skill(930, 1.0, 0.0)
	t.check(skill.get("ok", false) and skill.get("hit", false),
		"server resolves the actual melee target")
	t.eq(skill.get("hits", 0), 1, "one precision skill hits one target")
	t.eq(skill.get("finishers", -1), 0, "healthy infected never trigger finisher")
	t.near(healthy.health, before - Combat.weapon_damage("dagger_1") * 1.4,
		0.001, "healthy enemy receives ordinary skill damage")
	t.near(player.combat_energy, 70.0, 0.001,
		"ability spends 30 combat energy on genuine attack")
	t.near(player.skill_timer, 6.5, 0.001,
		"server starts normal skill cooldown")
	t.eq(server.cmd_skill(930, 1.0, 0.0).get("reason", ""),
		"cooldown", "rapid input cannot replay melee damage")

	t.current = "wounded infected takes pre-hit finisher bonus"
	server.zombies.clear()
	player.attack_timer = 0.0
	player.skill_timer = 0.0
	var wounded = _brute(server, world, true)
	before = wounded.health
	skill = server.cmd_skill(930, 1.0, 0.0)
	t.eq(skill.get("finishers", 0), 1, "server reports one verified finisher")
	t.near(wounded.health, maxf(0.0, before -
		Combat.weapon_damage("dagger_1") * 1.4 * 2.0), 0.001,
		"wounded normal infected takes double skill damage")
	t.near(player.combat_energy, 40.0, 0.001,
		"execution is not a free second attack")
	var announced := false
	for event in server.drain_events():
		if event.get("type", "") == "finishing_strike":
			announced = true
			t.eq(int(event.get("id", -1)), wounded.id,
				"visual marker refers only to actual struck enemy")
			t.check(not event.has("health") and not event.has("max_health"),
				"public finisher reveal does not leak exact health")
	t.check(announced, "verified execution emits a visible effect")

	t.current = "elite and boss executions are resistant but valid"
	server.zombies.clear()
	player.attack_timer = 0.0
	player.skill_timer = 0.0
	player.combat_energy = 100.0
	var elite = _brute(server, world, true, true)
	before = elite.health
	t.eq(server.cmd_skill(930, 1.0, 0.0).get("finishers", 0), 1,
		"elite may still be executed")
	t.near(elite.health, maxf(0.0, before -
		Combat.weapon_damage("dagger_1") * 1.4 * 1.5), 0.001,
		"elite receives reduced finisher bonus")
	server.zombies.clear()
	player.attack_timer = 0.0
	player.skill_timer = 0.0
	var boss = _brute(server, world, true, false, true)
	before = boss.health
	t.eq(server.cmd_skill(930, 1.0, 0.0).get("finishers", 0), 1,
		"wounded boss is hit by the same server logic")
	t.near(boss.health, maxf(0.0, before -
		Combat.weapon_damage("dagger_1") * 1.4 * 1.2), 0.001,
		"raid boss bonus capped at 20 percent")
	var net := Net.new()
	net.role = "server"
	net.sim = server
	t.check(net._event_visible_to({"type": "finishing_strike",
		"x": boss.position.x, "z": boss.position.z}, 930),
		"nearby players can see impact effects")
	net.free()

	t.current = "no free energy, ghost gear, or safe-zone PvP execution"
	server.zombies.clear()
	player.attack_timer = 0.0
	player.skill_timer = 0.0
	player.combat_energy = 29.0
	t.eq(server.cmd_skill(930, 1.0, 0.0).get("reason", ""),
		"no_energy", "low energy blocks the finisher")
	player.combat_energy = 100.0
	t.check(player.inventory.remove("dagger_1", 1),
		"dagger may be dropped like other full-loot equipment")
	t.eq(server.cmd_skill(930, 1.0, 0.0).get("reason", ""),
		"no_skill", "ghost equipment never grants active ability")
	t.near(player.combat_energy, 100.0, 0.001,
		"rejected ghost ability has no energy cost")
	player.inventory.add("dagger_1", 1)
	t.check(player.inventory.equip("dagger_1"),
		"survivor may re-equip valid dagger")
	var peaceful = server.add_player(931, "Protected")
	player.position = _at(world, 8.0, 0.0)
	peaceful.position = _at(world, 10.0, 0.0)
	peaceful.survival.hurt(80.0)
	before = peaceful.survival.health
	var safe: Dictionary = server.cmd_skill(930, 1.0, 0.0)
	t.check(safe.get("ok", false) and not safe.get("hit", true),
		"execute cannot hit protected survivor inside hub")
	t.near(peaceful.survival.health, before, 0.001,
		"safe-zone survivor receives no skill damage")
