extends RefCounted
## Ammo progression and pistol resupply use the same authoritative crafting
## and combat paths as the canonical multiplayer game.

const Defs = preload("res://scripts/shared/defs.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")


func run(t) -> void:
	t.current = "reloading recipe and balance"
	var recipe: Dictionary = Defs.recipes().get("ammo_9mm", {})
	t.check(not recipe.is_empty(), "9mm ammunition has a crafting recipe")
	if recipe.is_empty():
		return
	t.eq(int(recipe["count"]), 12, "one batch reloads 12 rounds")
	t.eq(recipe["inputs"], {"scrap": 2, "bar_2": 1}, "requires scavenged scrap and refined metal")
	t.eq(recipe["station"], "workbench", "ammunition needs settlement equipment")
	t.eq(Defs.tier_of("ammo_9mm"), 2, "requires tier-two crafting mastery")
	t.check(Defs.stack_size("ammo_9mm") >= int(recipe["count"]), "one batch fits one stack")

	t.current = "shared atomic crafting rules"
	var bench_only := Inventory.new()
	bench_only.add("scrap", 4)
	bench_only.add("bar_2", 2)
	t.eq(Crafting.craft(bench_only, "ammo_9mm", false), Crafting.Result.NO_STATION,
		"cannot reload in the wilderness")
	t.eq(bench_only.count("scrap"), 4, "refused craft keeps all scrap")
	t.eq(Crafting.craft(bench_only, "ammo_9mm", true, 2), Crafting.Result.OK,
		"two batches craft together")
	t.eq(bench_only.count("ammo_9mm"), 24, "two batches produce 24 rounds")
	t.eq(bench_only.count("scrap"), 0, "two batches consume exact scrap")
	t.eq(bench_only.count("bar_2"), 0, "two batches consume refined metal")
	t.eq(Crafting.craft(bench_only, "ammo_9mm", true), Crafting.Result.MISSING_INPUTS,
		"empty inventory cannot mint more bullets")

	t.current = "full bag cannot consume reload materials"
	var full := Inventory.new(2)
	full.add("scrap", 3)
	full.add("bar_2", 2)
	var before: Dictionary = full.to_dict()
	t.eq(Crafting.craft(full, "ammo_9mm", true), Crafting.Result.NO_SPACE,
		"unspent partial stacks block incoming ammunition")
	t.eq(full.to_dict(), before, "failed reload rolls back every ingredient")
	t.eq(full.count("ammo_9mm"), 0, "failed reload produces no rounds")

	t.current = "authoritative mastery, station and firearm"
	var world := WorldGen.new(103)
	var server := GameServer.new(world, 103)
	var survivor = server.add_player(609, "Gunsmith")
	survivor.inventory = Inventory.new()
	survivor.inventory.add("scrap", 2)
	survivor.inventory.add("bar_2", 1)
	survivor.position = Vector3(180, world.height_at(180, 180), 180)
	t.eq(server.cmd_craft(609, "ammo_9mm").get("reason"), "need_skill",
		"novice cannot craft advanced rounds even with ingredients")
	survivor.progression.crafting_xp = 100
	t.eq(server.cmd_craft(609, "ammo_9mm").get("reason"), "no_station",
		"skilled survivor still needs a workbench")
	t.eq(survivor.inventory.count("scrap"), 2, "station denial does not consume scrap")
	var hub: Vector2 = GameServer.WORKBENCH_POSITION
	survivor.position = Vector3(hub.x, world.height_at(hub.x, hub.y), hub.y)
	t.check(bool(server.cmd_craft(609, "ammo_9mm").get("ok", false)),
		"server approves skilled crafting at the hub")
	t.eq(survivor.inventory.count("ammo_9mm"), 12, "server awarded exactly 12 rounds")
	t.eq(survivor.inventory.count("scrap"), 0, "server consumed input once")
	t.eq(survivor.inventory.count("bar_2"), 0, "refined metal consumed once")
	t.eq(server.cmd_craft(609, "ammo_9mm").get("reason"), "missing_inputs",
		"replayed craft cannot mint ammo")

	survivor.inventory.add("pistol", 1)
	t.check(survivor.inventory.equip("pistol"), "scavenged pistol can be equipped")
	t.check(bool(server.cmd_attack(609, 1.0, 0.0).get("ok", false)),
		"crafted ammunition can be fired by existing firearm combat")
	t.eq(survivor.inventory.count("ammo_9mm"), 11,
		"server consumes one round on actual shot")
	t.current = "manufactured ammo survives character persistence"
	var saved: Dictionary = server.character_data(survivor)
	t.check(server.valid_character_data(saved), "crafted ammo snapshot validates")
	t.check(survivor.inventory.remove("ammo_9mm", 11), "test removes ammo before restore")
	t.check(server.apply_character(survivor, saved), "character can restore ammo from save")
	t.eq(survivor.inventory.count("ammo_9mm"), 11,
		"server restores crafted rounds without duplication")
