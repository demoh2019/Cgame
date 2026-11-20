extends RefCounted
const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const ExpeditionLoadout = preload("res://scripts/shared/expedition_loadout.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _place(world, actor, x: float, z: float) -> void:
	actor.position = Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "only finite, bounded preset quantities and known items"
	for preset_id in ExpeditionLoadout.ORDER:
		t.check(ExpeditionLoadout.valid_preset(preset_id), "known preset")
		for key in ExpeditionLoadout.TARGETS[preset_id]:
			var id: String = str(key)
			var target: int = int(ExpeditionLoadout.TARGETS[preset_id][key])
			t.check(Defs.is_item(id), "defined supply item")
			t.check(target > 0 and target <= Defs.stack_size(id), "target is bounded")
	t.check(not ExpeditionLoadout.valid_preset("free_items"), "forged kit invalid")
	var bag := Inventory.new()
	var bank := Inventory.new(Defs.STASH_SLOTS)
	bag.add("bandage", 2)
	bag.add("canned_food", 6)
	bag.add("silver", 100)
	bag.add("club_1", 1)
	bag.equip("club_1")
	bank.add("bandage", 10)
	bank.add("water_bottle", 10)
	bank.add("field_antiseptic", 3)
	bank.add("field_splint", 2)
	bank.add("wound_sealant", 1)
	bank.add("canned_food", 5)
	var receipt: Dictionary = ExpeditionLoadout.restock(bag, bank, "scout")
	t.check(bool(receipt.get("ok", false)), "real bank supplies moved")
	t.eq(int(receipt["total"]), 8, "banked seal, bandages, water, antiseptic and splint move")
	t.eq(bag.count("wound_sealant"), 1, "scout receives one paid prophylactic dose")
	t.eq(bank.count("wound_sealant"), 0, "dose is withdrawn from the protected bank")
	t.eq(bag.count("bandage"), 4, "only missing bandages taken")
	t.eq(bag.count("water_bottle"), 3, "water top-up bounded")
	t.eq(bag.count("canned_food"), 6, "excess carried food preserved")
	t.eq(bank.count("canned_food"), 5, "unneeded food stays banked")
	t.eq(bank.count("bandage"), 8, "bank debited exactly")
	t.eq(bag.count("silver"), 100, "silver untouched")
	t.eq(bag.weapon, "club_1", "equipment unchanged")
	var old_bag: Dictionary = bag.to_dict()
	var old_bank: Dictionary = bank.to_dict()
	t.eq(ExpeditionLoadout.restock(bag, bank, "scout").get("reason"),
		"already_supplied", "repeat cannot drain more bank goods")
	t.eq(bag.to_dict(), old_bag, "bag unchanged after repeat")
	t.eq(bank.to_dict(), old_bank, "bank unchanged after repeat")
	t.eq(ExpeditionLoadout.restock(bag, bank, "free_items").get("reason"),
		"unknown_preset", "forged RPC preset fails")

	t.current = "partial, out-of-stock and full-backpack safety"
	var tight := Inventory.new(1)
	tight.add("bandage", 2)
	var stock := Inventory.new(Defs.STASH_SLOTS)
	stock.add("bandage", 5)
	stock.add("arrow", 50)
	var partial: Dictionary = ExpeditionLoadout.restock(tight, stock, "archer")
	t.check(bool(partial.get("ok", false)), "partial kit can still withdraw bandages")
	t.eq(tight.count("bandage"), 3, "only one bandage transferred")
	t.eq(stock.count("bandage"), 4, "real stock decremented")
	t.eq(stock.count("arrow"), 50, "arrows remain when bag full")
	t.check(bool(partial.get("partial", false)), "missing kit pieces reported")
	var blocked := Inventory.new(1)
	blocked.add("silver", 1)
	var available_stock := Inventory.new(Defs.STASH_SLOTS)
	available_stock.add("bandage", 5)
	var blocked_before: Dictionary = blocked.to_dict()
	var bank_before: Dictionary = available_stock.to_dict()
	t.eq(ExpeditionLoadout.restock(blocked, available_stock, "medic").get("reason"),
		"no_space", "full backpack denied safely")
	t.eq(blocked.to_dict(), blocked_before, "blocked bag untouched")
	t.eq(available_stock.to_dict(), bank_before, "blocked stash untouched")
	t.eq(ExpeditionLoadout.restock(Inventory.new(), Inventory.new(Defs.STASH_SLOTS), "scout").get("reason"),
		"no_stock", "empty stash cannot create supplies")

	t.current = "server-station ownership, saves and death"
	var world := WorldGen.new(192)
	var server := GameServer.new(world, 192)
	var actor = server.add_player(192, "Scavenger")
	actor.stash.add("bandage", 5)
	actor.stash.add("water_bottle", 4)
	actor.stash.add("canned_food", 3)
	_place(world, actor, 185.0, 0.0)
	t.eq(server.cmd_expedition_restock(9999, "scout").get("reason"),
		"dead", "unconnected peer denied")
	t.eq(server.cmd_expedition_restock(192, "scout").get("reason"),
		"no_station", "cannot restock in wilderness")
	t.eq(actor.stash.count("bandage"), 5, "remote access does not debit stash")
	_place(world, actor, 9.0, 0.0)
	t.eq(server.cmd_expedition_restock(192, "fake").get("reason"),
		"unknown_preset", "server never trusts a forged preset")
	t.check(bool(server.cmd_expedition_restock(192, "scout").get("ok", false)),
		"authenticated restock at hub")
	t.eq(actor.inventory.count("bandage"), 4, "starter kit 2 plus 2 bank bandages")
	t.eq(actor.stash.count("bandage"), 3, "2 bandages withdrawn, not all 5")
	t.check(server.snapshot_for(192).has("stash"), "private bank snapshot refreshed")
	t.check(not server.snapshot_for(192).has("stash"), "bank not re-sent when clean")
	var saved: Dictionary = server.character_data(actor)
	var restored_server := GameServer.new(WorldGen.new(192), 192)
	var restored = restored_server.add_player(193, "Returning", "account193", saved)
	t.eq(restored.inventory.count("bandage"), 4, "supplies persist through reconnect")
	t.eq(restored.stash.count("bandage"), 3, "stash preserves spent withdrawal")
	var protected_water: int = restored.stash.count("water_bottle")
	restored.position = Vector3(800, restored_server.world.height_at(800, 0), 0)
	restored.survival.health = 0.0
	restored_server._on_player_death(restored, -1)
	t.eq(restored.stash.count("water_bottle"), protected_water,
		"remaining bank supplies survive death")
