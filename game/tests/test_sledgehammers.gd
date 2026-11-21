extends RefCounted
## Integrated crafting, server hits and brief PvE-only stagger effects.
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
	t.current = "tiered hammers are craftable, equipment-granted PvE weapons"
	for tier in range(1, Defs.MAX_TIER + 1):
		var weapon_id: String = "sledgehammer_%d" % tier
		var item: Dictionary = Defs.item(weapon_id)
		var recipe: Dictionary = Defs.recipes().get(weapon_id, {})
		t.eq(item.get("weapon", ""), "melee", "hammer uses shared melee mastery")
		t.eq(int(item.get("tier", 0)), tier, "each hammer matches its resource tier")
		t.eq(recipe.get("station", ""), "workbench", "hammer needs real workbench")
		t.eq(recipe.get("inputs", {}), {"plank_%d" % tier: 1,
			"bar_%d" % tier: 3, "scrap": 2},
			"metalwork and scavenging supply the heavy head")
		t.eq(Combat.active_skill(weapon_id).get("id", ""), "concussive_blow",
			"each equipped hammer unlocks concussive blow")
	t.eq(Combat.active_skill("machete_1").get("id", ""), "cleaving_arc",
		"machete retains its different multi-target skill")
	t.eq(Combat.active_skill("spear_1").get("id", ""), "piercing_thrust",
		"spear retains its piercing skill")
	var skill: Dictionary = Combat.active_skill("sledgehammer_1")
	t.near(float(skill["stagger_seconds"]), 1.3, 0.001,
		"server config limits ordinary stagger duration")

	var bag := Inventory.new()
	bag.add("plank_1", 1)
	bag.add("bar_1", 3)
	bag.add("scrap", 2)
	t.eq(Crafting.craft(bag, "sledgehammer_1", false), Crafting.Result.NO_STATION,
		"remote crafting cannot spend resources")
	t.eq(bag.count("scrap"), 2, "refused craft keeps all scrap")
	t.eq(Crafting.craft(bag, "sledgehammer_1", true), Crafting.Result.OK,
		"workbench crafts one hammer")
	t.eq(bag.count("sledgehammer_1"), 1, "crafted hammer goes into inventory")
	t.eq(bag.count("scrap"), 0, "crafting spends both scrap")
	t.eq(Crafting.craft(bag, "sledgehammer_1", true), Crafting.Result.MISSING_INPUTS,
		"duplicate requests cannot mint extra weapons")

	t.current = "server requires actual materials, station and profession"
	var world := WorldGen.new(2345)
	var server := GameServer.new(world, 2345)
	server.craft_quality_enabled = false # This suite checks the item itself, not quality rolls.
	var player = server.add_player(777, "Smasher")
	player.inventory = Inventory.new()
	player.inventory.add("plank_1", 1)
	player.inventory.add("bar_1", 3)
	player.inventory.add("scrap", 2)
	player.position = _at(world, 140.0, 140.0)
	t.eq(server.cmd_craft(777, "sledgehammer_1").get("reason", ""), "no_station",
		"server rejects forging away from a workstation")
	player.position = _at(world, GameServer.WORKBENCH_POSITION.x,
		GameServer.WORKBENCH_POSITION.y)
	t.check(server.cmd_craft(777, "sledgehammer_1").get("ok", false),
		"materials become a real weapon at workbench")
	t.eq(server.cmd_craft(777, "sledgehammer_4").get("reason", ""), "need_skill",
		"higher tier crafting remains progression-gated")
	t.check(player.inventory.equip("sledgehammer_1"), "server equips carried hammer")
	t.eq(server.cmd_skill(777, NAN, 0.0).get("reason", ""), "no_direction",
		"nonfinite aim cannot trigger skill")
	t.near(player.combat_energy, 100.0, 0.001, "invalid direction never charges energy")

	t.current = "confirmed melee hit staggers a living infected only"
	player.position = _at(world, 200.0, 200.0)
	var brute := Zombie.new(server.new_id(), "brute", _at(world, 202.0, 200.0))
	server.zombies[brute.id] = brute
	var hp_before: float = brute.health
	var strike: Dictionary = server.cmd_skill(777, 1.0, 0.0)
	t.check(strike.get("ok", false) and strike.get("hit", false),
		"server computes valid heavy melee attack")
	t.eq(strike.get("hits", 0), 1, "concussive blow hits just one enemy")
	t.near(brute.health, hp_before - Combat.weapon_damage("sledgehammer_1") * 1.25,
		0.001, "damage uses the equipped weapon stats")
	t.near(brute.stagger_seconds, 1.3, 0.001,
		"real hit applies limited stagger to ordinary infected")
	t.near(player.combat_energy, 65.0, 0.001, "blow costs 35 combat energy")
	t.near(player.skill_timer, 9.0, 0.001, "server applies nine-second cooldown")
	t.eq(server.cmd_skill(777, 1.0, 0.0).get("reason", ""), "cooldown",
		"repeated command cannot stun-lock or double charge")
	var snapshot: Dictionary = server.snapshot_for(777)
	var public_stagger := -1.0
	for entry in snapshot["zombies"]:
		if int(entry["id"]) == brute.id:
			public_stagger = float(entry.get("stagger_seconds", -1.0))
	t.near(public_stagger, 1.3, 0.001,
		"replicated zombie exposes only server-owned stagger countdown")

	t.current = "stagger blocks AI actions temporarily and is bounded"
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	brute.target_id = 777
	brute.state = Zombie.State.CHASE
	var before: Vector3 = brute.position
	var active_players := {777: {"position": player.position, "alive": true,
		"safe": false, "noise": 0.0}}
	var action: Dictionary = brute.think(world, active_players, 0.5, rng)
	t.check(action.is_empty(), "stunned infected cannot attack")
	t.near(brute.position.x, before.x, 0.001, "stunned infected cannot walk")
	t.near(brute.stagger_seconds, 0.8, 0.001, "stun timer advances with server tick")
	brute.think(world, active_players, 0.8, rng)
	t.near(brute.stagger_seconds, 0.0, 0.001, "stagger expires rather than stacking")
	t.check(brute.apply_stagger(1.3), "another confirmed hit may refresh effect")
	t.near(brute.stagger_seconds, 1.3, 0.001, "new effects replace, never add durations")
	t.check(brute.apply_stagger(1.3), "reapplied stagger is valid")
	t.near(brute.stagger_seconds, 1.3, 0.001, "multiple effects do not accumulate")

	t.current = "elites resist; bosses and dead infected are immune"
	var elite := Zombie.new(server.new_id(), "brute", _at(world, 203.0, 200.0))
	elite.become_elite()
	t.check(elite.apply_stagger(1.3), "elite can be slowed briefly")
	t.near(elite.stagger_seconds, 0.65, 0.001, "elite halves crowd-control duration")
	var boss := Zombie.new(server.new_id(), "brute", _at(world, 204.0, 200.0))
	boss.raid_boss = true
	t.check(not boss.apply_stagger(1.3), "raid boss resists hard crowd control")
	t.near(boss.stagger_seconds, 0.0, 0.001, "immune boss has no stagger")
	t.check(not brute.apply_stagger(INF), "nonfinite and over-limit durations rejected")
	t.check(not brute.apply_stagger(5.0), "unbounded duration is refused")
	t.near(brute.stagger_seconds, 1.3, 0.001, "invalid durations do not alter timer")
	boss.take_damage(100000.0)
	t.check(not boss.apply_stagger(1.3), "dead enemies cannot be stunned")

	t.current = "concussive blow cancels spitter acid telegraph"
	var spitter := Zombie.new(server.new_id(), "spitter", _at(world, 201.8, 200.0))
	spitter.spit_pending = true
	spitter.spit_seconds = 0.2
	t.check(spitter.apply_stagger(1.3), "living spitter is staggerable")
	t.check(not spitter.spit_pending, "stagger cancels pending spit")
	t.near(spitter.spit_seconds, 0.0, 0.001, "interrupted spit cannot deal delayed acid")
	var acid_result: Dictionary = spitter.think(world, active_players, 0.5, rng)
	t.check(not acid_result.has("spit_impact"), "stunned spitter creates no acid impact")

	t.current = "equipped ownership, energy and safe-hub PvP remain enforced"
	player.skill_timer = 0.0
	player.attack_timer = 0.0
	player.combat_energy = 34.0
	t.eq(server.cmd_skill(777, 1.0, 0.0).get("reason", ""), "no_energy",
		"low combat energy cannot cast stun")
	t.check(player.inventory.remove("sledgehammer_1", 1), "can remove worn hammer")
	player.combat_energy = 100.0
	t.eq(server.cmd_skill(777, 1.0, 0.0).get("reason", ""), "no_skill",
		"ghost equipment cannot cause stun")
	t.near(player.combat_energy, 100.0, 0.001, "rejected ghost attack spends no energy")
	player.inventory.add("sledgehammer_1", 1)
	t.check(player.inventory.equip("sledgehammer_1"), "can re-equip owned hammer")
	server.zombies.clear()
	var safe_player = server.add_player(778, "Protected")
	player.position = _at(world, 8.0, 0.0)
	safe_player.position = _at(world, 10.0, 0.0)
	var protected_health: float = safe_player.survival.health
	var safe_strike: Dictionary = server.cmd_skill(777, 1.0, 0.0)
	t.check(safe_strike.get("ok", false) and not safe_strike.get("hit", true),
		"safe-hub player cannot be attacked by concussive blow")
	t.near(safe_player.survival.health, protected_health, 0.001,
		"player stun never bypasses zone risk protection")
