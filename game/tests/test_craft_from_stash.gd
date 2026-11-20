extends RefCounted
## Workbench-only bank crafting without item creation, loss or duplicate XP.
const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const CraftFromStash = preload("res://scripts/shared/craft_from_stash.gd")
const Catalog = preload("res://scripts/shared/crafting_catalog.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _place(world, actor, x: float, z: float) -> void:
	actor.position = Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "mixed ingredient sources and exact atomic transaction"
	var bag := Inventory.new()
	var bank := Inventory.new(Defs.STASH_SLOTS)
	bag.add("wood_1", 3)
	bank.add("wood_1", 7)
	var first: Dictionary = bag.to_dict()
	var second: Dictionary = bank.to_dict()
	t.eq(Catalog.max_batches(bag, "plank_1", bank), 5,
		"catalog previews all five batches across both containers")
	t.eq(bag.to_dict(), first, "preview never debits backpack")
	t.eq(bank.to_dict(), second, "preview never debits protected stash")
	t.eq(CraftFromStash.craft(bag, bank, "plank_1", 4), Crafting.Result.OK,
		"mixed-source recipe can craft four batches")
	t.eq(bag.count("wood_1"), 0, "three carried wood consumed first")
	t.eq(bank.count("wood_1"), 2, "five banked wood consumed")
	t.eq(bag.count("plank_1"), 4, "finished planks go to backpack")
	t.eq(bank.count("plank_1"), 0, "outputs never appear in the stash")
	t.eq(CraftFromStash.craft(bag, bank, "plank_1", 2), Crafting.Result.MISSING_INPUTS,
		"cannot spend materials that do not exist")
	t.eq(bank.count("wood_1"), 2, "failed request does not debit the bank")
	t.eq(CraftFromStash.craft(bag, bank, "invalid", 1), Crafting.Result.UNKNOWN_RECIPE,
		"unregistered recipe cannot mint resources")
	t.eq(CraftFromStash.craft(bag, bank, "plank_1", 51), Crafting.Result.MISSING_INPUTS,
		"bounded to server-side maximum batch size")

	t.current = "full backpack and freed input slot"
	var blocked := Inventory.new(1)
	blocked.add("silver", 100)
	var stored := Inventory.new(Defs.STASH_SLOTS)
	stored.add("wood_1", 5)
	var blocked_before: Dictionary = blocked.to_dict()
	var stored_before: Dictionary = stored.to_dict()
	t.eq(CraftFromStash.craft(blocked, stored, "plank_1", 1), Crafting.Result.NO_SPACE,
		"must have an output slot even with abundant bank materials")
	t.eq(blocked.to_dict(), blocked_before, "no-space refund is atomic in backpack")
	t.eq(stored.to_dict(), stored_before, "no-space refund is atomic in bank")
	var one_slot := Inventory.new(1)
	one_slot.add("wood_1", 2)
	var empty := Inventory.new(Defs.STASH_SLOTS)
	t.eq(CraftFromStash.craft(one_slot, empty, "plank_1", 1), Crafting.Result.OK,
		"consuming entire carried stack frees output space")
	t.eq(one_slot.count("plank_1"), 1, "output occupies freed backpack slot")
	var present := Inventory.new(1)
	present.add("wood_1", 1)
	var saved := Inventory.new(Defs.STASH_SLOTS)
	saved.add("wood_1", 1)
	t.eq(CraftFromStash.craft(present, saved, "plank_1", 1), Crafting.Result.OK,
		"mixed last-carried-unit input opens output slot")

	t.current = "catalog respects bank mode and existing non-bank mode"
	var catalog_bag := Inventory.new()
	var catalog_bank := Inventory.new(Defs.STASH_SLOTS)
	catalog_bank.add("cloth_1", 4)
	t.eq(Catalog.max_batches(catalog_bag, "bandage"), 0,
		"original UI mode still ignores stash")
	t.eq(Catalog.max_batches(catalog_bag, "bandage", catalog_bank), 2,
		"bank mode previews two possible bandage batches")
	var rows: Array[Dictionary] = Catalog.entries(catalog_bag, "bandage", true, 1, catalog_bank)
	t.eq(rows.size(), 1, "available filter sees bank resources")
	t.check(bool(rows[0]["ready"]), "available filter retains tier restriction")

	t.current = "server hub authority and dirty snapshot"
	var world := WorldGen.new(207)
	var server := GameServer.new(world, 207)
	var actor = server.add_player(207, "Crafter")
	actor.stash.add("wood_1", 4)
	_place(world, actor, 180, 0)
	var initial_bag: int = actor.inventory.count("wood_1")
	t.eq(server.cmd_craft(207, "plank_1", 1, true).get("reason"),
		"no_station", "rural bench cannot use account stash")
	t.eq(actor.stash.count("wood_1"), 4, "remote request cannot debit bank")
	_place(world, actor, 9, 0)
	t.eq(server.cmd_craft(207, "plank_1", 1).get("reason"),
		"missing_inputs", "ordinary crafting still ignores protected stash")
	t.check(bool(server.cmd_craft(207, "plank_1", 2, true).get("ok", false)),
		"hub workbench can craft two batches directly from bank")
	t.eq(actor.inventory.count("plank_1"), 2, "newly crafted items carried")
	t.eq(actor.stash.count("wood_1"), 0, "exact four banked wood used")
	t.eq(actor.inventory.count("wood_1"), initial_bag, "carried unrelated material untouched")
	t.check(server.snapshot_for(207).has("stash"), "private bank state refreshed")
	t.check(not server.snapshot_for(207).has("stash"),
		"snapshot sends bank only when changed")
	t.eq(server.cmd_craft(207, "plank_1", 2, true).get("reason"),
		"missing_inputs", "repeat cannot duplicate materials or outputs")
	t.eq(actor.inventory.count("plank_1"), 2, "repeat never mints planks")

	t.current = "persistence after bank craft"
	var data: Dictionary = server.character_data(actor)
	var rejoined_server := GameServer.new(WorldGen.new(207), 207)
	var rejoined = rejoined_server.add_player(208, "Returning", "account-208", data)
	t.eq(rejoined.inventory.count("plank_1"), 2, "crafted items persist on reconnect")
	t.eq(rejoined.stash.count("wood_1"), 0, "spent ingredients remain spent")
