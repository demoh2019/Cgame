extends RefCounted
## Real pack ergonomics, server movement, recipe authority, mounts and PvP drop.
const TrailBackpack = preload("res://scripts/shared/trail_backpack.gd")
const BikeCargo = preload("res://scripts/shared/bike_cargo.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")


func run(t) -> void:
	t.current = "crafted T2 pack consumes true workbench materials"
	t.eq(Defs.item(TrailBackpack.ITEM_ID)["kind"], "carry_pack",
		"backpack is a real registered item")
	t.eq(Defs.stack_size(TrailBackpack.ITEM_ID), 1,
		"pack occupies a physical inventory slot")
	var recipe: Dictionary = Defs.recipes()[TrailBackpack.ITEM_ID]
	t.eq(recipe["station"], "workbench", "T2 pack needs an actual workbench")
	var parts := Inventory.new()
	for id in recipe["inputs"]:
		parts.add(str(id), int(recipe["inputs"][id]))
	t.eq(Crafting.craft(parts, TrailBackpack.ITEM_ID, false),
		Crafting.Result.NO_STATION, "cannot craft freely anywhere")
	t.eq(parts.count(TrailBackpack.ITEM_ID), 0, "refusal mints nothing")
	t.eq(Crafting.craft(parts, TrailBackpack.ITEM_ID, true),
		Crafting.Result.OK, "paid workbench craft succeeds")
	t.eq(parts.count(TrailBackpack.ITEM_ID), 1, "one physical pack is made")
	t.eq(Crafting.craft(parts, TrailBackpack.ITEM_ID, true),
		Crafting.Result.MISSING_INPUTS, "no repeated free craft")

	t.current = "bounded foot assistance, real mass and zero stack exploit"
	var backpack := Inventory.new()
	backpack.add("stone_1", 25)
	var raw: float = backpack.total_weight()
	var base: float = backpack.movement_factor()
	t.check(base < 1.0, "50 kg slows normal walking")
	t.eq(TrailBackpack.support_kg(backpack), 0.0, "no pack no bonus")
	backpack.add(TrailBackpack.ITEM_ID, 1)
	t.check(backpack.total_weight() > raw, "backpack itself weighs 2.5 kg")
	t.near(TrailBackpack.effective_weight(backpack),
		backpack.total_weight() - TrailBackpack.SUPPORTED_KG,
		0.0001, "14 kg supported without deleting physical mass")
	t.check(backpack.movement_factor() > base, "craftable pack improves mobility")
	t.near(BikeCargo.movement_factor(backpack, 0.0, false),
		backpack.movement_factor(), 0.0001,
		"on-foot server, client and inventory derive identical speed")
	backpack.add(TrailBackpack.ITEM_ID, 2)
	t.eq(TrailBackpack.support_kg(backpack), 14.0,
		"three packs still grant exactly one finite benefit")
	backpack.remove(TrailBackpack.ITEM_ID, 3)
	t.eq(TrailBackpack.support_kg(backpack), 0.0,
		"selling or losing every pack instantly removes help")
	t.near(backpack.total_weight(), raw, 0.0001, "all mass accounted for")
	t.near(backpack.movement_factor(), base, 0.0001,
		"heavy movement returns with no pack")

	t.current = "foot pack and bicycle panniers never double count"
	backpack.add("salvage_bike", 1)
	backpack.add("bike_panniers", 1)
	backpack.add(TrailBackpack.ITEM_ID, 1)
	t.near(BikeCargo.effective_weight(backpack, true),
		maxf(0.0, backpack.total_weight() - BikeCargo.SUPPORTED_KG),
		0.0001, "mounted gets ONLY pannier 28 kg support")
	t.eq(TrailBackpack.support_kg(backpack, true), 0.0,
		"foot support disabled while mounted")
	t.check(BikeCargo.movement_factor(backpack, 0.0, true) >
		BikeCargo.movement_factor(backpack, 0.0, false),
		"mount retains stronger but exclusive load support")
	backpack.remove("bike_panniers", 1)
	t.near(BikeCargo.effective_weight(backpack, true), backpack.total_weight(),
		0.0001, "no panniers: bike load receives zero trail-pack help")

	t.current = "authoritative server movement and true full-loot drop"
	var world := WorldGen.new(42)
	var sim := GameServer.new(world, 42)
	var player = sim.add_player(711, "Porter")
	player.position = Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	player.inventory.add("stone_1", 20)
	var place: Vector3 = player.position
	t.check(BikeCargo.movement_factor(player.inventory, 0.0, false) < 1.0,
		"40 kg without pack disables sprint")
	player.input_budget = 0.1
	sim.submit_input(711, 1, 1.0, 0.0, true, 0.0, 0.1)
	var slow: float = player.position.distance_to(place)
	t.check(slow > 0.0, "actual heavy input resolves movement")
	player.position = place
	player.inventory.add(TrailBackpack.ITEM_ID, 1)
	t.near(BikeCargo.movement_factor(player.inventory, 0.0, false),
		1.0, 0.0001, "real pack now permits sprint")
	player.input_budget = 0.1
	sim.submit_input(711, 2, 1.0, 0.0, true, 0.0, 0.1)
	t.check(player.position.distance_to(place) > slow,
		"server-only inventory decides faster movement")
	var view: Dictionary = sim.snapshot_for(711)["you"]
	t.near(float(view["trail_pack_kg"]), 14.0, 0.0001,
		"owner snapshot reports actual active support")
	t.near(float(view["carry_kg"]), player.inventory.total_weight(), 0.0001,
		"client still sees unmodified physical carry weight")
	t.near(float(view["cargo_factor"]), player.inventory.movement_factor(), 0.0001,
		"movement prediction and authority agree")
	var saved: Dictionary = sim.character_data(player)
	var restored = sim.add_player(712, "Reloaded", "porter-account", saved)
	t.eq(restored.inventory.count(TrailBackpack.ITEM_ID), 1,
		"saved inventory retains real tradable item")
	t.near(restored.inventory.total_weight(), player.inventory.total_weight(),
		0.0001, "relogging cannot evade the pack's own mass")
	player.position = Vector3(850.0, world.height_at(850.0, 0.0), 0.0)
	player.survival.reset()
	t.check(world.zone_at(850.0, 0.0) >= 2, "test site is red/black loot zone")
	sim._on_player_death(player, -1)
	t.eq(player.inventory.count(TrailBackpack.ITEM_ID), 0,
		"full-loot death drops the carried pack")
	t.eq(TrailBackpack.support_kg(player.inventory), 0.0,
		"death cannot retain old movement capacity")
	var found := false
	for bag in sim.bags.values():
		if int((bag["items"] as Dictionary).get(TrailBackpack.ITEM_ID, 0)) > 0:
			found = true
	t.check(found, "other players can loot the real dropped pack")
