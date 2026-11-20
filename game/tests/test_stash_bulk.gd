extends RefCounted
## Bank convenience is server-owned, private and lossless, including full slots.
const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const StashBulk = preload("res://scripts/shared/stash_bulk.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "only crafting ingredients may be banked in bulk"
	t.check(StashBulk.eligible("wood_1"), "gathered wood qualifies")
	t.check(StashBulk.eligible("cloth_1"), "refined cloth qualifies")
	for item_id in ["silver", "canned_food", "water_bottle", "bandage", "club_1", "axe_1"]:
		t.check(not StashBulk.eligible(item_id), "nonmaterials are excluded")

	var carried := Inventory.new()
	var bank := Inventory.new(Defs.STASH_SLOTS)
	carried.add("wood_1", 7)
	carried.add("ore_1", 9)
	carried.add("cloth_1", 4)
	carried.add("bandage", 3)
	carried.add("silver", 17)
	carried.add("club_1", 1)
	carried.equip("club_1")
	var original_weight: float = carried.total_weight()
	var receipt: Dictionary = StashBulk.deposit(carried, bank)
	t.check(bool(receipt.get("ok", false)), "resource deposit succeeds")
	t.eq(int(receipt["total"]), 20, "correct number of units moved")
	t.eq(int(receipt["remaining"]), 0, "nothing skipped when there is room")
	t.check(not bool(receipt["partial"]), "whole transfer reported")
	t.eq(carried.count("wood_1") + carried.count("ore_1") + carried.count("cloth_1"),
		0, "all raw and refined inputs left backpack")
	t.eq(bank.count("wood_1"), 7, "bank receives all wood")
	t.eq(bank.count("ore_1"), 9, "bank receives all ore")
	t.eq(bank.count("cloth_1"), 4, "bank receives all cloth")
	t.eq(carried.count("silver"), 17, "money always remains carried")
	t.eq(carried.count("bandage"), 3, "first aid stays available")
	t.eq(carried.count("club_1"), 1, "equipped weapon remains in bag")
	t.eq(carried.weapon, "club_1", "equipped state is not changed")
	t.check(carried.total_weight() < original_weight, "bank relieves encumbrance")
	t.eq(StashBulk.deposit(carried, bank).get("reason"), "no_materials",
		"replay without new materials does not mint items")

	t.current = "partial destination capacity is safe and deterministic"
	var overfilled := Inventory.new(Defs.STASH_SLOTS)
	var full_slots: Array = []
	for i in range(Defs.STASH_SLOTS - 1):
		full_slots.append({"id": "stone_1", "count": Defs.stack_size("stone_1")})
	full_slots.append({"id": "wood_1", "count": Defs.stack_size("wood_1") - 2})
	overfilled.slots = full_slots
	var packing := Inventory.new()
	packing.add("wood_1", 8)
	packing.add("ore_1", 5)
	var partial: Dictionary = StashBulk.deposit(packing, overfilled)
	t.check(bool(partial.get("ok", false)), "partial safe fill succeeds")
	t.eq(int(partial["total"]), 2, "only two units fit into existing stack")
	t.eq(int(partial["remaining"]), 11, "other eleven resources are carried")
	t.check(bool(partial["partial"]), "player receives partial message")
	t.eq(packing.count("wood_1"), 6, "remainder never disappears")
	t.eq(packing.count("ore_1"), 5, "no-space ore remains carried")
	t.eq(overfilled.count("wood_1"), Defs.stack_size("wood_1"),
		"existing stack filled precisely")
	var packed_before: Dictionary = packing.to_dict()
	var bank_before: Dictionary = overfilled.to_dict()
	t.eq(StashBulk.deposit(packing, overfilled).get("reason"), "no_space",
		"repeat at capacity is rejected")
	t.eq(packing.to_dict(), packed_before, "rejected bank action leaves bag untouched")
	t.eq(overfilled.to_dict(), bank_before, "rejected bank action leaves bank untouched")

	t.current = "authoritative station, snapshots, saves and death"
	var world := WorldGen.new(411)
	var server := GameServer.new(world, 411)
	var player = server.add_player(411, "Depositor")
	player.inventory.add("wood_1", 4)
	t.eq(server.cmd_stash_bulk(999).get("reason"), "dead",
		"no absent peer can issue bulk command")
	player.position = Vector3(180, world.height_at(180, 0), 0)
	t.eq(server.cmd_stash_bulk(411).get("reason"), "no_station",
		"no remote banking from dangerous zones")
	t.eq(player.inventory.count("wood_1"), 4,
		"rejected out-of-range banking does not debit resources")
	player.position = Vector3(9, world.height_at(9, 0), 0)
	t.check(bool(server.cmd_stash_bulk(411).get("ok", false)),
		"valid hub deposit uses server-owned position")
	t.eq(player.stash.count("wood_1"), 4, "bank owns transferred wood")
	t.eq(player.inventory.count("wood_1"), 0, "character carries no transferred wood")
	t.check(server.snapshot_for(411).has("stash"),
		"owner receives updated protected contents")
	t.check(not server.snapshot_for(411).has("stash"),
		"not re-sent after dirty flag cleared")
	var saved: Dictionary = server.character_data(player)
	var rejoined_server := GameServer.new(WorldGen.new(411), 411)
	var rejoined = rejoined_server.add_player(412, "Returning", "account-id", saved)
	t.eq(rejoined.stash.count("wood_1"), 4, "deposit persists across reconnects")
	t.eq(rejoined.inventory.count("wood_1"), 0, "reconnect never duplicates carried goods")
	var guarded_wood: int = rejoined.stash.count("wood_1")
	rejoined.position = Vector3(800, rejoined_server.world.height_at(800, 0), 0)
	rejoined.survival.health = 0.0
	rejoined_server._on_player_death(rejoined, -1)
	t.eq(rejoined.stash.count("wood_1"), guarded_wood,
		"protected stash survives full-loot death")
