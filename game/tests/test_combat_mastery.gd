extends RefCounted
## One shared game: server-owned equipment mastery, damage, persistence and XP safety.

const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const Progression = preload("res://scripts/shared/progression.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func run(t) -> void:
	t.current = "separate melee and ranged mastery"
	var mastery := Progression.new()
	t.eq(mastery.combat_level("melee"), 1, "new survivor begins with melee mastery 1")
	t.eq(mastery.combat_level("ranged"), 1, "new survivor begins with ranged mastery 1")
	t.near(mastery.combat_damage_multiplier(""), 1.0, 0.00001, "fists grant no mastery bonus")
	t.eq(mastery.award_combat("", 500), 0, "unarmed combat cannot farm weapon XP")
	t.eq(mastery.award_combat("unknown", 500), 0, "unknown gear grants no XP")
	t.eq(mastery.award_combat("club_1", -100), 0, "negative combat XP is rejected")
	t.eq(mastery.award_combat("club_1", 80), 80, "club victories raise melee XP")
	t.eq(mastery.combat_level("melee"), 2, "80 XP unlocks level 2 melee")
	t.eq(mastery.combat_level("ranged"), 1, "melee kills never level ranged weapons")
	t.near(mastery.combat_damage_multiplier("club_2"), 1.03, 0.00001,
		"mastery applies to the weapon family, not one item tier")
	t.near(mastery.combat_damage_multiplier("pistol"), 1.0, 0.00001,
		"untrained pistol damage is unchanged")
	t.eq(mastery.award_combat("pistol", 80), 80, "pistol victories raise ranged XP")
	t.eq(mastery.combat_level("ranged"), 2, "ranged mastery levels separately")
	mastery.combat_xp["melee"] = Progression.MAX_XP
	t.eq(mastery.combat_level("melee"), Progression.COMBAT_MAX_LEVEL,
		"level progression caps despite very large XP")
	t.near(mastery.combat_damage_multiplier("club_4"), 1.12, 0.00001,
		"mastery damage bonus is capped at twelve percent")
	t.eq(mastery.award_combat("club_1", 200), 0, "saturated XP cannot overflow")

	t.current = "atomic mastery save validation and legacy characters"
	var original: Dictionary = mastery.to_dict()
	var restored := Progression.new()
	t.check(restored.load_dict(original), "valid combat XP loads")
	t.eq(restored.combat_level("ranged"), 2, "ranged mastery survives saving")
	var invalid: Dictionary = {}
	for forged in [NAN, INF, -1, 0.5, 100000001, "80", true]:
		invalid = original.duplicate(true)
		invalid["combat"]["ranged"] = forged
		t.check(not restored.load_dict(invalid), "malformed saved combat XP rejected")
		t.eq(restored.combat_level("ranged"), 2, "invalid combat XP cannot change live state")
	invalid = original.duplicate(true)
	invalid["combat"]["archery"] = 100
	t.check(not restored.load_dict(invalid), "unexpected weapon family cannot load")
	invalid = original.duplicate(true)
	invalid["combat"].erase("ranged")
	t.check(not restored.load_dict(invalid), "missing ranged XP cannot load")
	var legacy: Dictionary = original.duplicate(true)
	legacy.erase("combat")
	t.check(restored.load_dict(legacy), "old characters without combat XP still load")
	t.eq(restored.combat_level("melee"), 1, "legacy melee level starts at one")
	t.eq(restored.combat_level("ranged"), 1, "legacy ranged level starts at one")

	t.current = "server awards mastery only after real infected kills"
	var world := WorldGen.new(2468)
	var server := GameServer.new(world, 194)
	var player = server.add_player(194, "Archer")
	player.position = Vector3(200.0, world.height_at(200.0, 200.0), 200.0)
	player.inventory.add("club_1", 1)
	t.check(player.inventory.equip("club_1"), "equips a real melee weapon")
	var miss: Dictionary = server.cmd_attack(194, 1.0, 0.0)
	t.check(miss.get("ok", false) and not miss.get("hit", true),
		"attack with no target misses cleanly")
	t.eq(player.progression.combat_xp["melee"], 0, "swinging at empty air earns no XP")
	player.attack_timer = 0.0
	var walker := Zombie.new(server.new_id(), "walker",
		Vector3(201.4, world.height_at(201.4, 200.0), 200.0))
	server.zombies[walker.id] = walker
	var first: Dictionary = server.cmd_attack(194, 1.0, 0.0)
	t.check(first.get("ok", false) and first.get("hit", false), "normal club hit connects")
	t.eq(player.progression.combat_xp["melee"], 0, "nonlethal hits cannot farm mastery XP")
	server._damage_target(player, {"kind": "zombie", "id": walker.id}, 500.0)
	t.eq(player.progression.combat_xp["melee"], int(walker.data["xp"]),
		"confirmed infected death grants its configured server XP")
	var earned: int = int(player.progression.combat_xp["melee"])
	server._damage_target(player, {"kind": "zombie", "id": walker.id}, 500.0)
	t.eq(player.progression.combat_xp["melee"], earned,
		"defeated infected cannot be killed repeatedly for XP")
	var reported := false
	for event in server.events:
		if event.get("type") == "mastery" and event.get("peer") == 194:
			reported = true
	t.check(reported, "earned weapon XP is announced to the owning survivor")

	t.current = "melee and ability damage use server level"
	# This test is about the weapon mastery multiplier alone: start the skill tree from scratch.
	player.skills.reset()
	server._apply_skill_bonuses(player)
	player.progression.award_combat("club_1", 80 - earned)
	t.eq(player.progression.combat_level("melee"), 2, "server combat XP reaches rank two")
	var brute := Zombie.new(server.new_id(), "brute",
		Vector3(201.4, world.height_at(201.4, 200.0), 200.0))
	server.zombies[brute.id] = brute
	player.attack_timer = 0.0
	var before_hp: float = brute.health
	t.check(server.cmd_attack(194, 1.0, 0.0).get("hit", false),
		"melee mastery hit resolves on the real combat path")
	t.near(brute.health, before_hp - Combat.weapon_damage("club_1") * 1.03, 0.001,
		"mastery multiplies actual melee damage")
	player.attack_timer = 0.0
	before_hp = brute.health
	t.check(server.cmd_skill(194, 1.0, 0.0).get("hit", false),
		"weapon active skill still resolves correctly")
	t.near(brute.health, before_hp - Combat.weapon_damage("club_1") * 1.6 * 1.03, 0.001,
		"active skill gains the same bounded melee bonus")

	t.current = "ranged mastery is separate and server-controlled"
	player.inventory.add("pistol", 1)
	player.inventory.add("ammo_9mm", 3)
	t.check(player.inventory.equip("pistol"), "player equips a carried pistol")
	player.progression.award_combat("pistol", 80)
	player.attack_timer = 0.0
	before_hp = brute.health
	t.check(server.cmd_attack(194, 1.0, 0.0).get("hit", false),
		"pistol fires after its normal cooldown")
	t.near(brute.health, before_hp - Combat.weapon_damage("pistol") * 1.03, 0.001,
		"ranged level multiplies pistol, not melee skill, damage")
	t.eq(player.progression.combat_level("melee"), 2,
		"pistol mastery never mutates melee progression")
	var snapshot: Dictionary = server.snapshot_for(194)
	t.eq(snapshot["you"]["combat_levels"]["melee"], 2, "owner snapshot shows melee level")
	t.eq(snapshot["you"]["combat_levels"]["ranged"], 2, "owner snapshot shows ranged level")

	t.current = "combat mastery survives account saves and full-loot death"
	var saved: Dictionary = server.character_data(player)
	t.check(saved["progression"].has("combat"), "character save includes mastery XP")
	player.progression.combat_xp["melee"] = 0
	t.check(server.apply_character(player, saved), "server restores saved mastery")
	t.eq(player.progression.combat_level("melee"), 2, "melee rank restored")
	var corrupted: Dictionary = saved.duplicate(true)
	corrupted["progression"]["combat"]["melee"] = INF
	var health_before: float = player.survival.health
	t.check(not server.apply_character(player, corrupted),
		"server rejects corrupt combat XP before changing survivor")
	t.near(player.survival.health, health_before, 0.0001,
		"corrupt combat save cannot partially change health")
	t.eq(player.progression.combat_level("melee"), 2,
		"corrupt combat XP cannot partially overwrite mastery")
	player.position = Vector3(700.0, world.height_at(700.0, 700.0), 700.0)
	player.survival.hurt(1000.0)
	server._on_player_death(player, -1)
	server._spawn_player(player)
	t.eq(player.progression.combat_level("melee"), 2,
		"full-loot death retains permanent combat XP")
	t.eq(player.inventory.count("pistol"), 0,
		"full-loot death still removes carried weapons")
