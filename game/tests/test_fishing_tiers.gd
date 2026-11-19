extends RefCounted
## Tiered coastline rewards, classless crafting and risk-graded fish economy.
## The simulated shoreline lets us deterministically test all four risk zones.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Fishing = preload("res://scripts/shared/fishing.gd")
const Vendor = preload("res://scripts/shared/vendor.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


class TestShore:
	extends RefCounted
	var zone: int = 0

	func is_water(x: float, _z: float) -> bool:
		return x >= 2.0

	func zone_at(_x: float, _z: float) -> int:
		return zone


func run(t) -> void:
	t.current = "tiered fishing catalog"
	for tier in range(1, Defs.MAX_TIER + 1):
		var rod: String = "fishing_rod" if tier == 1 else "fishing_rod_%d" % tier
		var raw_id: String = Fishing.catch_item(tier)
		var meal: String = "cooked_fish" if tier == 1 else "cooked_fish_%d" % tier
		t.check(Defs.is_item(rod), "registered rod tier " + str(tier))
		t.check(Defs.is_item(raw_id), "registered regional fish tier " + str(tier))
		t.check(Defs.is_item(meal), "registered regional meal tier " + str(tier))
		t.eq(int(Defs.item(rod).get("tier", 0)), tier, "matching rod gear tier")
		t.eq(int(Defs.item(raw_id).get("tier", 0)), tier, "matching catch tier")
		t.check(Defs.recipes().has(rod) and Defs.recipes().has(meal),
			"fishing and cooking recipes are registered at each tier")
		t.eq(Defs.recipes()[meal]["inputs"][raw_id], 1, "cooking consumes matching fish")
		t.eq(Defs.item(meal)["kind"], "food", "cooked fish is consumable")
	t.eq(Fishing.catch_item(0), "", "invalid negative/zero tier cannot mint fish")
	t.eq(Fishing.catch_item(5), "", "tier above catalog cannot mint fish")

	t.current = "region, rod and skill each cap catch quality"
	var coast := TestShore.new()
	var at := Vector3.ZERO
	var rod4 := Inventory.new()
	rod4.add("fishing_rod_4", 1)
	coast.zone = 0
	var result: Dictionary = Fishing.validate_start(coast, at, rod4, 4)
	t.eq(result.get("item", ""), "raw_fish", "safe green coast never produces rare fish")
	t.eq(result.get("tier", 0), 1, "green zone tier cap")
	coast.zone = 1
	result = Fishing.validate_start(coast, at, rod4, 4)
	t.eq(result.get("item", ""), "raw_fish_2", "yellow shores support T2")
	coast.zone = 2
	result = Fishing.validate_start(coast, at, rod4, 4)
	t.eq(result.get("item", ""), "raw_fish_3", "red shores support T3")
	coast.zone = 3
	result = Fishing.validate_start(coast, at, rod4, 4)
	t.eq(result.get("item", ""), "raw_fish_4", "black shores support T4")
	result = Fishing.validate_start(coast, at, rod4, 1)
	t.eq(result.get("item", ""), "raw_fish", "novice cannot receive T4 fish with gifted rod")
	result = Fishing.validate_start(coast, at, rod4, 2)
	t.eq(result.get("item", ""), "raw_fish_2", "T2 fishing mastery caps catch")
	var rod2 := Inventory.new()
	rod2.add("fishing_rod_2", 1)
	result = Fishing.validate_start(coast, at, rod2, 4)
	t.eq(result.get("item", ""), "raw_fish_2", "T2 rod caps an expert fisher")
	var full := Inventory.new(1)
	full.add("fishing_rod_4", 1)
	t.eq(Fishing.validate_start(coast, at, full, 4).get("reason", ""), "no_space",
		"cannot start without capacity for the chosen catch item")

	t.current = "authoritative tiered crafting and fish economy"
	var world := WorldGen.new(57)
	var server := GameServer.new(world, 57)
	var survivor = server.add_player(925, "Coast Crafter")
	var hub: Vector2 = GameServer.WORKBENCH_POSITION
	survivor.position = Vector3(hub.x, world.height_at(hub.x, hub.y), hub.y)
	survivor.inventory.add("plank_4", 2)
	survivor.inventory.add("cloth_4", 2)
	survivor.inventory.add("bar_4", 1)
	var before: Dictionary = survivor.inventory.to_dict()
	t.eq(server.cmd_craft(925, "fishing_rod_4").get("reason", ""), "need_skill",
		"cannot craft T4 rod without advanced crafting profession")
	t.eq(survivor.inventory.to_dict(), before, "rejected rod recipe preserves materials")
	survivor.progression.award_craft(1, 12)
	t.eq(survivor.progression.crafting_level(), 4, "classless crafting unlocks fourth tier")
	t.check(bool(server.cmd_craft(925, "fishing_rod_4").get("ok", false)),
		"trained survivor manufactures advanced fishing gear")
	t.eq(survivor.inventory.count("fishing_rod_4"), 1, "rod is in the shared backpack")

	survivor.inventory.add("raw_fish_4", 3)
	survivor.inventory.add("wood_4", 1)
	t.check(bool(server.cmd_craft(925, "cooked_fish_4").get("ok", false)),
		"crafting cooks matching high-tier fish and fuel")
	t.eq(survivor.inventory.count("raw_fish_4"), 2, "cooking consumes exactly one fish")
	survivor.survival.hunger = 20.0
	t.check(bool(server.cmd_use(925, "cooked_fish_4").get("ok", false)),
		"cooked fish uses the existing authoritative food path")
	t.check(survivor.survival.hunger > 20.0, "T4 meal actually restores survival hunger")

	var silver_before: int = survivor.inventory.count("silver")
	t.check(bool(server.cmd_vendor(925, "raw_fish_4", 2, false).get("ok", false)),
		"fisher sells coastal catch through the existing camp vendor")
	t.eq(survivor.inventory.count("raw_fish_4"), 0, "sale debits both fish")
	t.eq(survivor.inventory.count("silver") - silver_before, 44,
		"T4 regional fishing returns server-priced silver")
	t.eq(server.cmd_vendor(925, "raw_fish_4", 2, false).get("reason", ""),
		"missing_items", "cannot resell previously sold fish")
	t.eq(survivor.inventory.count("silver") - silver_before, 44,
		"repeat sale cannot duplicate silver")
	t.eq(int(Vendor.SELL_PRICES["raw_fish"]), 4, "ordinary T1 fish has lower price")
	t.eq(int(Vendor.SELL_PRICES["raw_fish_4"]), 22, "high-risk fish has bounded higher price")
