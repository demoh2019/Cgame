extends RefCounted
## Atomic gear recycling, no dupe/refund exploits, server authority and saved inventory.

const Defs = preload("res://scripts/shared/defs.gd")
const GearSalvage = preload("res://scripts/shared/gear_salvage.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "recycle yields derive from real recipes"
	t.eq(GearSalvage.materials_for("bow_2"),
		{"plank_2": 1, "fiber_2": 1},
		"bow yields half of ingredients, rounded down")
	t.eq(GearSalvage.materials_for("jacket_1"), {"cloth_1": 2},
		"jacket recycles into its own crafting tier")
	t.eq(GearSalvage.materials_for("pistol"), {"scrap": 3},
		"scavenged pistol returns bounded scrap, not rare recipe materials")
	t.eq(GearSalvage.materials_for("silver"), {},
		"cannot recycle currency into itself")
	t.eq(GearSalvage.materials_for("field_antiseptic"), {},
		"medicine cannot be recycled as equipment")
	for tier in range(1, Defs.MAX_TIER + 1):
		var gear: String = "club_%d" % tier
		for ingredient in GearSalvage.materials_for(gear):
			t.check(Defs.is_item(str(ingredient)), "every refund is valid at tier %d" % tier)

	t.current = "atomic inventory transaction"
	var inventory := Inventory.new()
	t.eq(GearSalvage.transact(inventory, "jacket_1")["reason"], "not_carried",
		"absent jacket cannot mint cloth")
	t.eq(GearSalvage.transact(inventory, "silver")["reason"], "not_gear",
		"currency cannot be dismantled")
	inventory.add("bow_2", 1)
	t.check(inventory.equip("bow_2"), "can equip bow normally")
	t.eq(GearSalvage.transact(inventory, "bow_2")["reason"], "equipped",
		"cannot accidentally recycle equipped weapon")
	inventory.add("club_1", 1)
	t.check(inventory.equip("club_1"), "switching weapons frees the previous bow")
	var redeemed: Dictionary = GearSalvage.transact(inventory, "bow_2")
	t.check(bool(redeemed.get("ok", false)), "spare weapon can be recycled")
	t.eq(inventory.count("bow_2"), 0, "one weapon is consumed")
	t.eq(inventory.count("plank_2"), 1, "tiered planks returned")
	t.eq(inventory.count("fiber_2"), 1, "tiered fiber returned")
	t.eq(GearSalvage.transact(inventory, "bow_2")["reason"], "not_carried",
		"duplicate replay cannot claim another refund")
	var full := Inventory.new(2)
	full.add("bow_2", 1)
	full.add("stone_1", 100)
	var unchanged: Dictionary = full.to_dict()
	t.eq(GearSalvage.transact(full, "bow_2")["reason"], "no_space",
		"cannot partially refund a full backpack")
	t.eq(full.to_dict(), unchanged,
		"failed attempt preserves weapon, stacks and equipped slots")
	var small := Inventory.new(1)
	small.add("jacket_1", 1)
	t.check(bool(GearSalvage.transact(small, "jacket_1").get("ok", false)),
		"consuming a jacket frees its own slot for cloth")
	t.eq(small.count("cloth_1"), 2, "recovered cloth fits")
	t.eq(small.count("jacket_1"), 0, "jacket removed exactly once")

	t.current = "server validates living survivor, workbench and saved inventory"
	var world := WorldGen.new(119)
	var server := GameServer.new(world, 119)
	var player = server.add_player(61, "Recycler")
	player.inventory.add("bow_2", 1)
	t.eq(server.cmd_salvage_gear(61, "bow_2")["reason"], "no_station",
		"remote recycling is forbidden")
	player.position = Vector3(GameServer.WORKBENCH_POSITION.x,
		world.height_at(GameServer.WORKBENCH_POSITION.x, GameServer.WORKBENCH_POSITION.y),
		GameServer.WORKBENCH_POSITION.y)
	player.inventory.add("silver", 5)
	t.eq(server.cmd_salvage_gear(61, "silver")["reason"], "not_gear",
		"server refuses money-to-material exploit")
	var server_result: Dictionary = server.cmd_salvage_gear(61, "bow_2")
	t.check(bool(server_result.get("ok", false)), "workbench recycles spare bow")
	t.eq(player.inventory.count("bow_2"), 0, "server removes consumed item")
	t.eq(player.inventory.count("plank_2"), 1, "server credits exact recipe refund")
	t.check(player.dirty_character and player.dirty_inventory,
		"authorized transaction schedules save and inventory replication")
	t.eq(server.cmd_salvage_gear(61, "bow_2")["reason"], "not_carried",
		"server refuses repeated claim")
	var state: Dictionary = server.character_data(player)
	t.check(state.has("inventory"), "gear recycling uses existing save schema")
	var restored = server.add_player(62, "Restored")
	t.check(server.apply_character(restored, state), "character data can be reloaded")
	t.eq(restored.inventory.count("plank_2"), 1, "refund persists through save")
	t.eq(restored.inventory.count("bow_2"), 0, "removed bow remains removed")
