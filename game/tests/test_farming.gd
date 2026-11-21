extends RefCounted
## Homestead farming: seeds, green-zone plots, real-time growth, owner-only harvest, persistence.

const Defs = preload("res://scripts/shared/defs.gd")
const Farming = preload("res://scripts/shared/farming.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Vendor = preload("res://scripts/shared/vendor.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldPersistence = preload("res://scripts/server/world_persistence.gd")


func _green_spot(world) -> Vector2:
	for x in range(20, 400, 5):
		for z in range(-40, 41, 5):
			if world.zone_at(float(x), float(z)) == 0 and not world.is_water(float(x), float(z)) \
					and not world.is_water(float(x), float(z) + 1.5):
				return Vector2(x, z)
	return Vector2.INF


func run(t) -> void:
	t.current = "farming data"
	for crop in Farming.CROPS:
		t.check(Defs.is_item(crop) and Defs.is_item(str(Farming.CROPS[crop]["seed"])), "%s and its seeds exist" % crop)
		t.check(Vendor.BUY_PRICES.has(str(Farming.CROPS[crop]["seed"])), "%s seeds are sold at the hub" % crop)
	t.eq(Farming.crop_for_seed("wheat_seeds"), "wheat", "seed maps to crop")
	t.check(Defs.recipes().has("farm_bread"), "wheat bakes into bread")
	t.eq(Farming.placement_refusal(2, false, Vector2.ZERO, {}, 0), "green_zone_only", "no farming in PvP zones")
	t.eq(Farming.placement_refusal(0, false, Vector2.ZERO, {}, Farming.MAX_PLOTS), "too_many_plots", "plot cap")

	t.current = "plant, grow, harvest"
	var world = WorldGen.new(11223)
	var server := GameServer.new(world, 31)
	var farmer = server.add_player(1301, "Farmer")
	var thief = server.add_player(1302, "Thief")
	farmer.user_id = "acct-farmer"
	for p in [farmer, thief]:
		p.inventory = Inventory.new()
	var spot := _green_spot(world)
	t.check(spot != Vector2.INF, "found green farmland")
	farmer.position = Vector3(spot.x, world.height_at(spot.x, spot.y), spot.y)
	farmer.yaw = 0.0
	t.eq(server.cmd_plant(1301, "carrot_seeds").get("reason"), "missing_seed", "needs a seed")
	farmer.inventory.add("carrot_seeds", 2)
	var planted: Dictionary = server.cmd_plant(1301, "carrot_seeds")
	t.check(bool(planted.get("ok", false)), "seed planted")
	t.eq(farmer.inventory.count("carrot_seeds"), 1, "seed consumed")
	t.eq(server.cmd_plant(1301, "carrot_seeds").get("reason"), "too_close", "plots need spacing")
	t.eq(server.cmd_harvest(1301).get("reason"), "not_ripe", "crops take time")
	thief.position = farmer.position
	server.time += 2000.0
	t.eq(server.cmd_harvest(1302).get("reason"), "no_plot", "only the owner can harvest")
	t.current = "persistence"
	var saved: Dictionary = WorldPersistence.capture(server)
	t.eq((saved["farm"] as Array).size(), 1, "plots are saved with the world")
	var harvest: Dictionary = server.cmd_harvest(1301)
	t.check(bool(harvest.get("ok", false)), "ripe crop harvested")
	t.check(farmer.inventory.count("carrot") >= 2, "carrots in the backpack")
	t.eq(server.farm_plots.size(), 0, "plot is cleared after harvest")
