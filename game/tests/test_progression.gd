extends RefCounted
## Classless gathering/crafting: tier gates, server transaction, persistence, death.
const Defs = preload("res://scripts/shared/defs.gd")
const Progression = preload("res://scripts/shared/progression.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "independent gathering and crafting skills"
	var prog := Progression.new()
	t.eq(prog.gathering_level("wood"), 1, "wood starts at T1")
	t.eq(prog.gathering_level("fiber"), 1, "fiber starts at T1")
	t.eq(prog.crafting_level(), 1, "crafting starts at T1")
	t.check(not prog.can_gather("tree", 2), "T2 tree initially locked")
	t.check(prog.can_gather("berry", 1), "berries are free to scavenge")
	t.eq(prog.award_gather("berry", 1, 100), 0, "berries do not level up tool skills")
	t.eq(prog.award_gather("tree", 1, 4), 32, "harvest awards XP based on actual item count")
	t.eq(prog.gathering_level("wood"), 1, "not yet level 2")
	prog.award_gather("tree", 1, 9)
	t.eq(prog.gathering_level("wood"), 2, "T2 wood unlocked")
	t.eq(prog.gathering_level("fiber"), 1, "wood XP never unlocks fiber")
	t.check(prog.can_gather("tree", 2), "leveled gathering gate opens")
	t.check(not prog.can_gather("tree", 5), "tiers above game maximum denied")
	prog.award_craft(1, 4)
	t.eq(prog.crafting_level(), 2, "four basic batches unlock level 2")
	t.check(prog.can_craft_tier(2), "T2 crafting unlocks")
	t.check(not prog.can_craft_tier(3), "T3 remains locked")

	t.current = "snapshot validation and compatibility"
	var data: Dictionary = prog.to_dict()
	var loaded := Progression.new()
	t.check(loaded.load_dict(data), "valid XP snapshot loads")
	t.eq(loaded.crafting_xp, 100, "craft XP restored")
	var bad: Dictionary = data.duplicate(true)
	bad["gathering"]["wood"] = -50
	t.check(not loaded.load_dict(bad), "negative XP rejected")
	t.eq(loaded.gathering_level("wood"), 2, "invalid update leaves skills unchanged")
	bad = data.duplicate(true)
	bad["crafting"] = NAN
	t.check(not loaded.load_dict(bad), "NaN XP rejected")
	t.eq(loaded.crafting_xp, 100, "invalid crafting XP not applied")
	bad = data.duplicate(true)
	bad["crafting"] = 100000001
	t.check(not loaded.load_dict(bad), "oversize crafting XP rejected")

	t.current = "server crafting gates and save migration"
	var world := WorldGen.new(8)
	var server := GameServer.new(world, 8)
	var player = server.add_player(101, "Ranger")
	player.position = Vector3(GameServer.WORKBENCH_POSITION.x,
		world.height_at(GameServer.WORKBENCH_POSITION.x, GameServer.WORKBENCH_POSITION.y),
		GameServer.WORKBENCH_POSITION.y)
	player.inventory.add("plank_2", 3)
	player.inventory.add("bar_2", 1)
	var blocked: Dictionary = server.cmd_craft(101, "club_2")
	t.eq(blocked.get("reason", ""), "need_skill", "T2 crafting forbidden at level 1")
	t.eq(player.inventory.count("plank_2"), 3, "blocked craft preserves components")
	player.progression.award_craft(1, 4)
	t.check(server.cmd_craft(101, "club_2")["ok"], "T2 craft unlocks at level 2")
	t.eq(player.inventory.count("club_2"), 1, "crafted item exists")
	t.check(player.progression.crafting_xp > 100, "successful craft grants experience")
	var snapshot: Dictionary = server.character_data(player)
	t.check(snapshot.has("progression"), "persistent character stores progression")
	var restored = server.add_player(102, "Return", "", snapshot)
	t.eq(restored.progression.crafting_level(), 2, "crafting mastery persists on login")
	var legacy: Dictionary = snapshot.duplicate(true)
	legacy.erase("progression")
	t.check(server.apply_character(restored, legacy), "old Nakama records without skills remain usable")
	t.eq(restored.progression.crafting_level(), 1, "legacy records start at level 1")
	var corrupt: Dictionary = snapshot.duplicate(true)
	corrupt["progression"]["gathering"]["wood"] = INF
	var before_health: float = restored.survival.health
	t.check(not server.apply_character(restored, corrupt), "corrupt XP rejects server load")
	t.near(restored.survival.health, before_health, 0.00001, "failed load does not mutate health")
	t.eq(restored.progression.crafting_level(), 1, "failed load does not change skills")

	t.current = "real resource awards and full loot"
	var novice = server.add_player(103, "Gatherer")
	server._finish_gather(novice, {"kind": "tree", "tier": 1, "id": 4200})
	t.check(novice.inventory.count("wood_1") >= 4, "harvest gives wood")
	t.check(novice.progression.gathering_xp["wood"] >= 32, "actual harvest gives gathering XP")
	t.eq(novice.progression.gathering_xp["fiber"], 0, "wood did not level fiber")
	var saved_xp: int = int(novice.progression.gathering_xp["wood"])
	# Full loot only applies in the red zone and beyond (yellow and green keep equipment).
	novice.position = Vector3(600.0, server.world.height_at(600.0, 600.0), 600.0)
	novice.survival.hurt(1000.0)
	server._on_player_death(novice, -1)
	server._spawn_player(novice)
	t.eq(novice.progression.gathering_xp["wood"], saved_xp, "mastery survives full-loot death")
	t.eq(novice.inventory.count("wood_1"), 0, "gear/resources do not survive full-loot death")
