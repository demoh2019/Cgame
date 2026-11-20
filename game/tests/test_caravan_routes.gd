extends RefCounted
## Region-authenticated caravan missions: travel, cost, atomic payout,
## deterministic routing and save/load without forged destinations.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const CaravanRoutes = preload("res://scripts/shared/caravan_routes.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")


func _source(world) -> Dictionary:
	for rx in range(-4, 5):
		for rz in range(-4, 5):
			for site in world.poi.sites_in_region(rx, rz):
				if not CaravanRoutes.offer_for(world, site).is_empty():
					return site
	return {}


func _at(server, player, x: float, z: float) -> void:
	player.position = Vector3(x, server.world.height_at(x, z), z)


func run(t) -> void:
	t.current = "caravan routes are real and cannot be forged by the client"
	var world := WorldGen.new(205)
	var source: Dictionary = _source(world)
	t.check(not source.is_empty(), "procedural world has two reachable merchant settlements")
	if source.is_empty():
		return
	var offer: Dictionary = CaravanRoutes.offer_for(world, source)
	t.check(float(offer["distance"]) >= CaravanRoutes.MIN_ROUTE_DISTANCE,
		"destination is a meaningful journey, not the same workstation")
	t.check(float(offer["distance"]) <= CaravanRoutes.MAX_ROUTE_DISTANCE,
		"routes never leave the bounded world travel search")
	t.eq(offer["quantity"], CaravanRoutes.CARGO_COUNT,
		"server picks exact amount; no caller-supplied reward or cargo")
	t.check(offer["silver"] >= 50 and offer["silver"] <= 140,
		"server payout is capped at a balanced range")
	var canonical: Dictionary = CaravanRoutes.saved_state(offer)
	t.check(CaravanRoutes.valid_state(world, canonical), "canonical saved route is accepted")
	t.check(CaravanRoutes.valid_state(world, {}), "legacy empty route is accepted")
	var wrong: Dictionary = canonical.duplicate()
	wrong["dst_id"] = int(wrong["dst_id"]) + 1
	t.check(not CaravanRoutes.valid_state(world, wrong),
		"saved destination cannot be changed to a closer reward station")
	wrong = canonical.duplicate()
	wrong["src_rx"] = 400
	t.check(not CaravanRoutes.valid_state(world, wrong),
		"unbounded saved region fails without generating unsafe world tiles")
	wrong = canonical.duplicate()
	wrong["silver"] = 999999
	t.check(not CaravanRoutes.valid_state(world, wrong),
		"persisted silver cannot be minted by injecting an extra field")
	t.check(not CaravanRoutes.valid_state(world, []),
		"malformed journal cannot be loaded")

	t.current = "accept only at NPC workbench; deliver only at canonical destination"
	var sim := GameServer.new(world, 205)
	var merchant = sim.add_player(801, "Caravan Trader")
	t.eq(sim.cmd_caravan(801, "accept").get("reason", ""), "no_station",
		"safe starter hub is not an inter-settlement caravan terminal")
	_at(sim, merchant, float(source["station_x"]), float(source["station_z"]))
	var accepted: Dictionary = sim.cmd_caravan(801, "accept")
	t.check(bool(accepted.get("ok", false)), "accepted at real world village merchant")
	t.eq(sim.cmd_caravan(801, "accept").get("reason", ""),
		"already_active", "duplicate acceptance cannot create extra assignments")
	t.eq(sim.cmd_caravan(801, "deliver").get("reason", ""),
		"wrong_destination", "source NPC cannot award the delivery prize")
	t.eq(sim.snapshot_for(801)["you"]["caravan"]["dst_id"], offer["dst_id"],
		"player alone receives the canonical destination coordinates")

	t.current = "active route survives re-login; corrupted saves are atomic rejects"
	var save: Dictionary = sim.character_data(merchant)
	t.eq(save["caravan"], canonical, "character persistence includes only route IDs")
	var second = sim.add_player(802, "Restored Courier")
	t.check(sim.apply_character(second, save), "caravan persists across server sessions")
	t.eq(second.caravan_view["dst_id"], offer["dst_id"],
		"reloaded view reconstructs destination from trusted procedural world")
	wrong = save.duplicate(true)
	wrong["caravan"]["dst_id"] = -7777
	t.check(not sim.apply_character(second, wrong), "forged saved destination rejected")
	t.eq(second.caravan_view["dst_id"], offer["dst_id"],
		"invalid save does not mutate active route")
	var legacy: Dictionary = save.duplicate(true)
	legacy.erase("caravan")
	t.check(sim.apply_character(second, legacy), "older account saves without jobs still load")
	t.check(second.caravan_view.is_empty(), "legacy accounts start without a route")

	t.current = "NPC cargo transaction is atomic and rewards only at arrival"
	_at(sim, merchant, float(offer["dst_x"]), float(offer["dst_z"]))
	var silver_before: int = merchant.inventory.count("silver")
	t.eq(sim.cmd_caravan(801, "deliver").get("reason", ""), "missing_cargo",
		"arrival without actual goods never pays silver")
	t.eq(merchant.inventory.count("silver"), silver_before,
		"rejected trip leaves wallet untouched")
	var cramped := Inventory.new(2)
	cramped.add(str(offer["cargo"]), CaravanRoutes.CARGO_COUNT + 1)
	cramped.add("stone_1", 1)
	var before: Dictionary = cramped.to_dict()
	t.eq(CaravanRoutes.deliver(cramped, offer).get("reason", ""), "no_space",
		"full inventory returns no prize if silver cannot fit")
	t.eq(cramped.to_dict(), before, "failed transaction rolls back all inputs")
	merchant.inventory.add(str(offer["cargo"]), CaravanRoutes.CARGO_COUNT)
	var result: Dictionary = sim.cmd_caravan(801, "deliver")
	t.check(bool(result.get("ok", false)), "cargo is delivered in the right settlement")
	t.eq(merchant.inventory.count(str(offer["cargo"])), 0,
		"exact items removed after successful delivery")
	t.eq(merchant.inventory.count("silver"), silver_before + int(offer["silver"]),
		"server awards exactly the promised capped payout")
	t.check(merchant.caravan_state.is_empty(), "successful route clears persistent assignment")
	t.eq(sim.cmd_caravan(801, "deliver").get("reason", ""),
		"no_active", "replayed delivery cannot mint duplicate silver")
	t.eq(merchant.inventory.count("silver"), silver_before + int(offer["silver"]),
		"repeated claim does not raise silver balance")

	t.current = "cancellation is an explicit no-fee state transition"
	_at(sim, merchant, float(source["station_x"]), float(source["station_z"]))
	t.check(sim.cmd_caravan(801, "accept").get("ok", false),
		"another route may be undertaken after a real prior delivery")
	t.check(sim.cmd_caravan(801, "abandon").get("ok", false),
		"player can abandon a route without paying cargo")
	t.check(merchant.caravan_state.is_empty(), "cancelled route is forgotten")
	t.eq(sim.cmd_caravan(801, "abandon").get("reason", ""), "no_active",
		"repeated cancellation is harmless")
