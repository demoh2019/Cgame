extends RefCounted
## Optional bait is paid only when a valid completed cast delivers an extra fish.
const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Fishing = preload("res://scripts/shared/fishing.gd")
const FishingBait = preload("res://scripts/shared/fishing_bait.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")


class TestShore:
	extends RefCounted
	var zone: int = 0
	func is_water(x: float, _z: float) -> bool:
		return x >= 2.0
	func zone_at(_x: float, _z: float) -> int:
		return zone


func _shore(world) -> Vector3:
	for x in range(-260, 261, 4):
		for z in range(-260, 261, 4):
			if world.is_water(float(x), float(z)):
				continue
			var pos := Vector3(float(x), world.height_at(float(x), float(z)), float(z))
			if Fishing.water_near(world, pos) != Vector2.INF:
				return pos
	return Vector3.INF


func run(t) -> void:
	t.current = "craftable bait for all shoreline fishing tiers"
	t.check(Defs.is_item(FishingBait.ITEM_ID), "real bait item exists")
	t.eq(Defs.item(FishingBait.ITEM_ID)["kind"], "material",
		"bait cannot be consumed for invented combat or medical effects")
	t.check(Defs.recipes().has(FishingBait.ITEM_ID), "gathered bait has a crafting recipe")
	t.eq(Defs.recipes()[FishingBait.ITEM_ID]["inputs"]["berries"], 2,
		"field bait consumes berries")
	t.eq(Defs.recipes()[FishingBait.ITEM_ID]["inputs"]["fiber_1"], 1,
		"field bait consumes fiber")
	t.eq(Defs.recipes()[FishingBait.ITEM_ID]["count"], 2,
		"field recipe returns two casts of bait")
	t.eq(Defs.recipes()[FishingBait.ITEM_ID]["station"], "",
		"bait can be crafted without a workbench")
	var materials := Inventory.new()
	materials.add("berries", 2)
	materials.add("fiber_1", 1)
	t.eq(Crafting.craft(materials, FishingBait.ITEM_ID, false), Crafting.Result.OK,
		"crafting actually debits the materials")
	t.eq(materials.count(FishingBait.ITEM_ID), 2, "exactly two baits created")
	t.eq(materials.count("berries"), 0, "berries consumed from real inventory")
	t.eq(materials.count("fiber_1"), 0, "fiber consumed from real inventory")

	t.current = "region, rod and fishing profession cap quality even with bait"
	var shore := TestShore.new()
	shore.zone = 3
	var rod := Inventory.new()
	rod.add("fishing_rod_4", 1)
	t.eq(Fishing.validate_start(shore, Vector3.ZERO, rod, 4, true)["reason"], "need_bait",
		"player cannot ask for free bait")
	t.eq(Fishing.validate_start(shore, Vector3.ZERO, rod, 4)["item"], "raw_fish_4",
		"ordinary fishing retains tier four without bait")
	rod.add(FishingBait.ITEM_ID, 1)
	var baited: Dictionary = Fishing.validate_start(shore, Vector3.ZERO, rod, 4, true)
	t.check(baited.get("ok", false), "valid baited cast starts")
	t.check(baited.get("baited", false), "server records an explicit baited choice")
	t.eq(baited["item"], "raw_fish_4", "bait never creates a higher fish tier")
	t.eq(Fishing.validate_start(shore, Vector3.ZERO, rod, 1, true)["item"], "raw_fish",
		"bait cannot bypass fishing profession gate")
	shore.zone = 0
	t.eq(Fishing.validate_start(shore, Vector3.ZERO, rod, 4, true)["item"], "raw_fish",
		"bait cannot bypass safe-zone coastal quality")
	shore.zone = 3
	var weak_rod := Inventory.new()
	weak_rod.add("fishing_rod", 1)
	weak_rod.add(FishingBait.ITEM_ID, 1)
	t.eq(Fishing.validate_start(shore, Vector3.ZERO, weak_rod, 4, true)["item"], "raw_fish",
		"bait cannot bypass the actual carried rod tier")

	t.current = "atomic cost and backpack capacity"
	t.check(not FishingBait.spend_for_bonus(rod, "raw_fish_4", 1, false),
		"ordinary cast never consumes bait")
	t.eq(rod.count(FishingBait.ITEM_ID), 1, "ordinary cast preserves stocked bait")
	t.check(not FishingBait.spend_for_bonus(rod, "raw_fish_4", 0, true),
		"invalid empty catch never spends bait")
	t.check(not FishingBait.spend_for_bonus(rod, "raw_fish_4", 3, true),
		"invalid oversized base catch never spends bait")
	var cramped := Inventory.new(3)
	cramped.add("fishing_rod", 1)
	cramped.add(FishingBait.ITEM_ID, 1)
	cramped.add("raw_fish", 19)
	t.eq(cramped.free_space_for("raw_fish"), 1, "only one fish will fit")
	t.check(not FishingBait.spend_for_bonus(cramped, "raw_fish", 1, true),
		"not enough space for two fish means no paid bonus")
	t.eq(cramped.count(FishingBait.ITEM_ID), 1,
		"too-small backpack cannot waste bait")
	t.check(FishingBait.spend_for_bonus(rod, "raw_fish_4", 2, true),
		"paid bonus is admitted only when all three fish can fit")
	t.eq(rod.count(FishingBait.ITEM_ID), 0, "one successful extra-fish reward debits one bait")
	t.check(not FishingBait.spend_for_bonus(rod, "raw_fish_4", 1, true),
		"second request with no bait cannot mint more fish")

	t.current = "server fishing action is item-paid and not instantly rewarded"
	var world := WorldGen.new(42)
	var sim := GameServer.new(world, 43)
	var player = sim.add_player(980, "Coastal Angler")
	var at: Vector3 = _shore(world)
	t.check(at.is_finite(), "deterministic playable shoreline exists")
	if not at.is_finite():
		return
	player.position = at
	player.inventory.add("fishing_rod", 1)
	t.eq(sim.cmd_fish(player.id, true).get("reason", ""), "need_bait",
		"real server rejects missing bait before any cast")
	t.check(player.action.is_empty(), "missing bait does not create an action")
	player.inventory.add(FishingBait.ITEM_ID, 2)
	var start: Dictionary = sim.cmd_fish(player.id, true)
	t.check(start.get("ok", false), "authorized baited cast starts with a carried rod")
	t.eq(start.get("baited", false), true, "server response echoes the actual cast mode")
	t.eq(player.inventory.count(FishingBait.ITEM_ID), 2, "start does not spend bait")
	t.eq(player.inventory.count("raw_fish"), 0, "start does not give instant fish")
	t.eq(player.action.get("baited", false), true, "authoritative action remembers bait request")
	t.eq(sim.cmd_fish(player.id, true).get("reason", ""), "busy",
		"duplicate cast request cannot schedule another reward")
	var before_xp: int = int(player.progression.gathering_xp["fishing"])
	for i in range(55):
		sim.time += 0.1
		sim._tick_players(0.1)
	t.check(player.action.is_empty(), "baited cast finishes after normal five seconds")
	var amount: int = player.inventory.count("raw_fish")
	t.check(amount >= 2 and amount <= 3, "single paid baited catch yields two or three fish")
	t.eq(player.inventory.count(FishingBait.ITEM_ID), 1,
		"one completed cast spends exactly one unit of bait")
	t.eq(int(player.progression.gathering_xp["fishing"]) - before_xp,
		amount * player.progression.GATHER_XP_PER_ITEM,
		"XP is awarded only for actually received fish")
	var event: Dictionary = {}
	for entry in sim.events:
		if entry.get("type", "") == "fished":
			event = entry
	t.eq(event.get("amount", 0), amount, "network event uses actual delivered catch")
	t.eq(event.get("bait_used", false), true, "event reports real bait consumption")

	t.current = "interruption and missing bait never pay a bonus"
	sim.time += Fishing.COOLDOWN_SECONDS + 1.0
	t.check(sim.cmd_fish(player.id, true).get("ok", false),
		"second baited cast may be scheduled after cooldown")
	var bait_before: int = player.inventory.count(FishingBait.ITEM_ID)
	var fish_before: int = player.inventory.count("raw_fish")
	player.position += Vector3(5.0, 0, 0)
	sim._tick_players(0.1)
	t.check(player.action.is_empty(), "moving cancels unfinished baited cast")
	t.eq(player.inventory.count(FishingBait.ITEM_ID), bait_before,
		"cancellation refunds nothing because no bait was charged")
	t.eq(player.inventory.count("raw_fish"), fish_before,
		"cancellation cannot create bonus fish")
