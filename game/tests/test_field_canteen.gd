extends RefCounted
## Survival lake refilling: a real crafted canteen and a paid charcoal filter,
## with atomic inventory capacity and one shared persistent lake cooldown.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const FieldWater = preload("res://scripts/shared/field_water.gd")
const FieldCanteen = preload("res://scripts/shared/field_canteen.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _shore(world) -> Vector3:
	for x in range(-260, 261, 4):
		for z in range(-260, 261, 4):
			var position := Vector3(float(x), world.height_at(float(x), float(z)), float(z))
			if FieldWater.can_access_lake(world, position):
				return position
	return Vector3.INF


func run(t) -> void:
	t.current = "craftable reusable canteen and one-use carbon filtration"
	t.check(Defs.is_item(FieldCanteen.CANTEEN_ITEM), "canteen exists in real item definitions")
	t.eq(Defs.item(FieldCanteen.CANTEEN_ITEM)["kind"], "tool",
		"canteen is carried gear, not a free healing consumable")
	t.eq(Defs.item(FieldCanteen.CANTEEN_ITEM)["tool"], "canteen",
		"tool is intentionally not an equippable weapon")
	var recipe: Dictionary = Defs.recipes().get(FieldCanteen.CANTEEN_ITEM, {})
	t.check(not recipe.is_empty(), "reusable canteen has a crafting recipe")
	t.eq(recipe["station"], "", "canteen may be crafted in the field")
	t.eq(recipe["inputs"], {"cloth_1": 2, "fiber_1": 3, "wood_1": 1},
		"crafting uses real T1 survival resources")
	var supplies := Inventory.new()
	supplies.add("cloth_1", 2)
	supplies.add("fiber_1", 3)
	t.eq(Crafting.craft(supplies, FieldCanteen.CANTEEN_ITEM, false),
		Crafting.Result.MISSING_INPUTS, "missing wood cannot mint a canteen")
	t.eq(supplies.count("cloth_1"), 2, "failed craft preserves material stacks")
	supplies.add("wood_1", 1)
	t.eq(Crafting.craft(supplies, FieldCanteen.CANTEEN_ITEM, false),
		Crafting.Result.OK, "field recipe consumes supplies and creates one tool")
	t.eq(supplies.count(FieldCanteen.CANTEEN_ITEM), 1, "one reusable canteen created")
	t.eq(supplies.count("cloth_1"), 0, "real cloth was debited")
	t.eq(supplies.count("fiber_1"), 0, "real fiber was debited")

	t.current = "pure inventory transaction cannot invent clean water"
	var sample := Inventory.new()
	t.eq(FieldCanteen.fill(sample), "need_canteen", "empty pack is not a source of bottled water")
	sample.add(FieldCanteen.CANTEEN_ITEM, 1)
	t.eq(FieldCanteen.fill(sample), "need_filter", "carried canteen needs a real carbon filter")
	sample.add(FieldCanteen.FILTER_ITEM, 2)
	t.eq(FieldCanteen.fill(sample), "", "first successful filtration returns a water bottle")
	t.eq(sample.count(FieldCanteen.CANTEEN_ITEM), 1, "canteen is retained after filling")
	t.eq(sample.count(FieldCanteen.FILTER_ITEM), 1, "one filter debited per bottle")
	t.eq(sample.count(FieldCanteen.OUTPUT_ITEM), 1, "exactly one clean water bottle credited")
	t.eq(FieldCanteen.fill(sample), "", "same tool may be used again with new filter")
	t.eq(sample.count(FieldCanteen.FILTER_ITEM), 0, "second use spends remaining filter")
	t.eq(sample.count(FieldCanteen.OUTPUT_ITEM), 2, "second use produces one more bottle")
	t.eq(FieldCanteen.fill(sample), "need_filter", "replay with empty filters cannot mint water")

	t.current = "capacity including the vacated single-filter slot"
	var cramped := Inventory.new(3)
	cramped.add(FieldCanteen.CANTEEN_ITEM, 1)
	cramped.add(FieldCanteen.FILTER_ITEM, 2)
	cramped.add(FieldCanteen.OUTPUT_ITEM, Defs.stack_size(FieldCanteen.OUTPUT_ITEM))
	var before: Dictionary = cramped.to_dict()
	t.eq(FieldCanteen.fill(cramped), "no_space", "full packs cannot waste an expensive filter")
	t.eq(cramped.to_dict(), before, "failed filtration is an atomic no-op")
	var freed := Inventory.new(2)
	freed.add(FieldCanteen.CANTEEN_ITEM, 1)
	freed.add(FieldCanteen.FILTER_ITEM, 1)
	t.eq(freed.free_space_for(FieldCanteen.OUTPUT_ITEM), 0,
		"the backpack has no spare slot before debit")
	t.eq(FieldCanteen.fill(freed), "", "emptying the last filter stack frees room for water")
	t.eq(freed.count(FieldCanteen.OUTPUT_ITEM), 1, "freed slot holds bottled water")
	t.eq(freed.count(FieldCanteen.CANTEEN_ITEM), 1, "permanent canteen remains carried")

	t.current = "server-controlled lake access and persistent shared cooldown"
	var world := WorldGen.new(42)
	var sim := GameServer.new(world, 42)
	var player = sim.add_player(843, "Water Gatherer")
	t.eq(sim.cmd_refill_canteen(999).get("reason", ""), "dead",
		"unknown client cannot ask for free bottles")
	t.eq(sim.cmd_refill_canteen(player.id).get("reason", ""), "no_water",
		"safe-town spawn cannot magically access a distant lake")
	var shore: Vector3 = _shore(world)
	t.check(shore.is_finite(), "deterministic accessible shore exists")
	if not shore.is_finite():
		return
	player.position = shore
	t.eq(sim.cmd_refill_canteen(player.id).get("reason", ""), "need_canteen",
		"shoreline alone cannot mint water")
	player.inventory.add("cloth_1", 2)
	player.inventory.add("fiber_1", 3)
	player.inventory.add("wood_1", 1)
	t.check(sim.cmd_craft(player.id, FieldCanteen.CANTEEN_ITEM).get("ok", false),
		"server crafts a permanent field canteen from real resources")
	t.eq(sim.cmd_refill_canteen(player.id).get("reason", ""), "need_filter",
		"real server requires water filtration")
	player.inventory.add(FieldCanteen.FILTER_ITEM, 2)
	var water_before: int = player.inventory.count(FieldCanteen.OUTPUT_ITEM)
	var result: Dictionary = sim.cmd_refill_canteen(player.id)
	t.check(result.get("ok", false), "server successfully fills at a real shoreline")
	t.eq(result.get("item", ""), FieldCanteen.OUTPUT_ITEM, "only clean bottled water is awarded")
	t.eq(result.get("count", 0), 1, "network result cannot claim two bottles")
	t.eq(player.inventory.count(FieldCanteen.OUTPUT_ITEM), water_before + 1,
		"one real water bottle enters shared backpack")
	t.eq(player.inventory.count(FieldCanteen.FILTER_ITEM), 1,
		"server spends exactly one carbon filter")
	t.eq(player.inventory.count(FieldCanteen.CANTEEN_ITEM), 1,
		"server does not destroy the reusable tool")
	t.check(player.dirty_inventory and player.dirty_character,
		"account saves mark both inventory and cooldown dirty")
	t.eq(sim.cmd_refill_canteen(player.id).get("reason", ""), "cooldown",
		"spam cannot refill the second bottle immediately")
	t.eq(player.inventory.count(FieldCanteen.FILTER_ITEM), 1,
		"rejected repeat call spends no filter")
	player.survival.thirst = 10.0
	t.eq(sim.cmd_drink_water(player.id).get("reason", ""), "cooldown",
		"lake drinking cannot bypass the refill cooldown")
	t.eq(sim.snapshot_for(player.id)["you"]["lake_drink_cooldown"],
		FieldWater.COOLDOWN_SECONDS, "owner sees the existing cooldown")

	t.current = "character saving, legacy v1, invalid timer and repeat refill"
	var data: Dictionary = sim.character_data(player)
	t.eq(data["lake_drink_cooldown"], FieldWater.COOLDOWN_SECONDS,
		"save stores same anti-relogin timer as lake drinking")
	t.eq(player.inventory.count(FieldCanteen.OUTPUT_ITEM), water_before + 1,
		"safe water inventory stays consistent before save")
	player.lake_drink_cooldown = 0.0
	t.check(sim.apply_character(player, data), "saved canteen cooldown and inventory restore")
	t.eq(player.lake_drink_cooldown, FieldWater.COOLDOWN_SECONDS,
		"relogin cannot reset refill timer")
	t.eq(player.inventory.count(FieldCanteen.CANTEEN_ITEM), 1,
		"canteen owner can retain the crafted tool across sessions")
	t.eq(player.inventory.count(FieldCanteen.OUTPUT_ITEM), water_before + 1,
		"bottled water survives a character reload")
	for invalid in [-1.0, INF, NAN, FieldWater.COOLDOWN_SECONDS + 1.0, "12"]:
		var corrupt: Dictionary = data.duplicate(true)
		corrupt["lake_drink_cooldown"] = invalid
		t.check(not sim.apply_character(player, corrupt),
			"malformed refill cooldown is rejected before changing character")
		t.eq(player.lake_drink_cooldown, FieldWater.COOLDOWN_SECONDS,
			"invalid save cannot weaken refill anti-spam protection")
	var legacy: Dictionary = data.duplicate(true)
	legacy.erase("lake_drink_cooldown")
	t.check(sim.apply_character(player, legacy), "old version-one characters still load")
	t.eq(player.lake_drink_cooldown, 0.0, "legacy character has no unsupported timer")
	t.check(sim.apply_character(player, data), "original character state restores")
	sim._tick_players(FieldWater.COOLDOWN_SECONDS)
	t.eq(player.lake_drink_cooldown, 0.0, "server releases shared cooldown on time")
	t.check(sim.cmd_refill_canteen(player.id).get("ok", false),
		"second paid bottle can be filled after cooldown")
	t.eq(player.inventory.count(FieldCanteen.FILTER_ITEM), 0,
		"remaining filter is spent only on successful second fill")
	t.eq(player.inventory.count(FieldCanteen.OUTPUT_ITEM), water_before + 2,
		"refilling creates exactly one more clean bottle")
	player.survival.hurt(1000.0)
	t.eq(sim.cmd_refill_canteen(player.id).get("reason", ""), "dead",
		"dead survivor cannot mint water or consume filters")
