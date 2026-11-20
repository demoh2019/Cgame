extends RefCounted
## Night courier premium requires authentic cargo, night-time movement, valid
## route state and a single atomic delivery payout. No client-supplied travel.

const NightCaravan = preload("res://scripts/shared/night_caravan.gd")
const CaravanRoutes = preload("res://scripts/shared/caravan_routes.gd")
const CaravanEscortRewards = preload("res://scripts/shared/caravan_escort_rewards.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")


func _source(world) -> Dictionary:
	for rx in range(-4, 5):
		for rz in range(-4, 5):
			for site in world.poi.sites_in_region(rx, rz):
				if not CaravanRoutes.offer_for(world, site).is_empty():
					return site
	return {}


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func _walk_forward(state: Dictionary, offer: Dictionary, night: bool,
		zone: int, cargo: int, count: int = 120) -> void:
	var start := Vector2(float(offer["src_x"]), float(offer["src_z"]))
	var goal := Vector2(float(offer["dst_x"]), float(offer["dst_z"]))
	var heading: Vector2 = (goal - start).normalized()
	for n in range(count):
		var before: Vector2 = start + heading * float(n) * 1.5
		var after: Vector2 = before + heading * 1.5
		NightCaravan.record(state, offer, Vector3(before.x, 0, before.y),
			Vector3(after.x, 0, after.y), night, zone, cargo)


func run(t) -> void:
	t.current = "night courier uses real deterministic NPC routes"
	var world := WorldGen.new(205)
	var site: Dictionary = _source(world)
	t.check(not site.is_empty(), "generated world offers an authentic caravan")
	if site.is_empty():
		return
	var offer: Dictionary = CaravanRoutes.offer_for(world, site)
	var state: Dictionary = NightCaravan.initial(offer)
	t.check(NightCaravan.valid_state(state, offer), "new journal is canonical")
	t.eq(NightCaravan.earned_bonus(offer, state), 0,
		"accepting a route cannot itself pay a premium")
	var start := Vector2(float(offer["src_x"]), float(offer["src_z"]))
	var goal := Vector2(float(offer["dst_x"]), float(offer["dst_z"]))
	var heading: Vector2 = (goal - start).normalized()
	var p0 := Vector3(start.x, 0, start.y)
	var p1 := Vector3(start.x + heading.x * 2.0, 0, start.y + heading.y * 2.0)
	t.check(not NightCaravan.record(state, offer, p0, p0, true, 2, 3),
		"standing still cannot earn route progress")
	t.check(not NightCaravan.record(state, offer, p0, p1, true, 2, 2),
		"partial cargo cannot earn a night premium")
	t.check(NightCaravan.record(state, offer, p0, p1, false, 2, 3),
		"real daytime movement advances the maximum forward checkpoint")
	t.near(float(state["night_meters"]), 0.0, 0.00001,
		"daylight progress never counts for nighttime bonus")
	t.check(not NightCaravan.record(state, offer, p0, p1, true, 2, 3),
		"replaying a covered segment cannot mint night credit")
	var p2 := Vector3(start.x + heading.x * 4.0, 0, start.y + heading.y * 4.0)
	t.check(NightCaravan.record(state, offer, p1, p2, true, 0, 3),
		"travel in the green zone advances covered distance")
	t.near(float(state["night_meters"]), 0.0, 0.00001,
		"safe green travel is ineligible for the risk premium")
	var p3 := Vector3(start.x + heading.x * 6.0, 0, start.y + heading.y * 6.0)
	t.check(NightCaravan.record(state, offer, p2, p3, true, 2, 3, true),
		"crossing a safe point updates forward progress")
	t.near(float(state["night_meters"]), 0.0, 0.00001,
		"safe settlements never contribute to hazardous travel")
	var p4 := Vector3(start.x + heading.x * 8.0, 0, start.y + heading.y * 8.0)
	t.check(NightCaravan.record(state, offer, p3, p4, true, 2, 3),
		"dangerous nighttime travel with full cargo qualifies for progress")
	t.near(float(state["night_meters"]), 2.0, 0.00001,
		"only the confirmed 2m step earns 2m")
	t.check(not NightCaravan.record(state, offer, p4, p3, true, 2, 3),
		"walking backwards cannot accumulate progress")
	t.check(not NightCaravan.record(state, offer, p3, p4, true, 2, 3),
		"walking forwards over the same ground cannot farm repeated credit")
	t.eq(NightCaravan.earned_bonus(offer, state), 0,
		"a handful of nighttime metres never pays a bonus")

	t.current = "night quota and bounded NPC silver premium"
	_walk_forward(state, offer, true, 2, 3)
	var needed: float = NightCaravan.required_meters(offer)
	t.check(float(state["night_meters"]) >= needed,
		"night quota requires 25 percent of the route or at least 80m")
	var expected_bonus: int = mini(28, roundi(float(offer["silver"]) * 0.20))
	t.eq(NightCaravan.earned_bonus(offer, state), expected_bonus,
		"fully qualified night run earns capped 20% silver from NPC")
	t.eq(NightCaravan.public_state(offer, state)["qualified"], true,
		"HUD sees qualified status from server, not client")
	t.check(NightCaravan.public_state(offer, state)["required_meters"] >= 80,
		"player gets an inspectable, finite target")
	var wrong: Dictionary = offer.duplicate()
	wrong["dst_id"] = int(offer["dst_id"]) + 1
	t.eq(NightCaravan.earned_bonus(wrong, state), 0,
		"bonus from an old or swapped route cannot be reused")
	var near_max: Dictionary = state.duplicate(true)
	near_max["night_meters"] = float(near_max["forward"]) + 3.0
	t.check(not NightCaravan.valid_state(near_max, offer),
		"impossible saved progress beyond measured distance is rejected")
	var malformed: Dictionary = state.duplicate(true)
	malformed["forward"] = INF
	t.check(not NightCaravan.valid_state(malformed, offer),
		"infinite saved progress cannot bypass quota")
	malformed = state.duplicate(true)
	malformed["night_meters"] = "1000"
	t.check(not NightCaravan.valid_state(malformed, offer),
		"stringified paid distance cannot bypass strict state validation")
	t.check(NightCaravan.valid_state({}, offer),
		"legacy save missing new journal remains compatible")
	t.check(not NightCaravan.valid_state(state, {}),
		"premium cannot attach to an inactive route")

	t.current = "existing guarded caravan payout is atomic"
	var server := GameServer.new(world, 205)
	var courier = server.add_player(821, "NightCourier")
	var guard = server.add_player(822, "Guard")
	courier.inventory.add(str(offer["cargo"]), int(offer["quantity"]))
	var before_courier: int = courier.inventory.count("silver")
	var before_guard: int = guard.inventory.count("silver")
	var result: Dictionary = CaravanEscortRewards.settle(courier, [guard],
		offer, true, state)
	t.eq(result["night_bonus"], expected_bonus,
		"night courier receives premium in same atomic settlement")
	var original_fare: int = int(offer["silver"])
	var defense: int = mini(21, roundi(float(original_fare) * 0.15))
	var guard_share: int = floori(float(original_fare) * 0.20)
	t.eq(result["silver"], original_fare - guard_share + defense + expected_bonus,
		"courier receives base less guard share plus two independent premiums")
	t.eq(courier.inventory.count("silver") - before_courier,
		original_fare - guard_share + defense + expected_bonus,
		"all NPC bonuses enter the actual backpack only once")
	t.eq(guard.inventory.count("silver") - before_guard, guard_share,
		"escort pay remains a fraction of the original fare only")
	t.eq(courier.inventory.count("silver") - before_courier +
		guard.inventory.count("silver") - before_guard,
		original_fare + defense + expected_bonus,
		"no duplicate silver across convoy members")
	t.eq(CaravanEscortRewards.settle(courier, [], offer, false, state).get("reason"),
		"missing_cargo", "replaying settled delivery cannot pay a second night premium")

	t.current = "real movement-input integration"
	var traveler = server.add_player(820, "MeasuredNightTravel")
	traveler.position = _at(world, float(site["station_x"]), float(site["station_z"]))
	t.eq(server.cmd_caravan(820, "accept").get("ok"), true,
		"the measured rider has an authentic NPC contract")
	traveler.inventory.add(str(offer["cargo"]), int(offer["quantity"]))
	server.time = WorldCycle.DAY_LENGTH * 0.75
	var measured := false
	for offset in range(24, 128, 8):
		var at: Vector2 = start + heading * float(offset)
		if world.zone_at(at.x, at.y) < NightCaravan.MIN_DANGER_ZONE or world.is_safe(at.x, at.y):
			continue
		var departure := _at(world, at.x, at.y)
		var predicted: Vector3 = Movement.step(world, departure,
			{"x": heading.x, "z": heading.y, "weather_time": server.time}, 0.1)
		if Vector2(predicted.x - departure.x, predicted.z - departure.z).length() < 0.05:
			continue
		traveler.position = departure
		traveler.input_budget = 0.1
		server.submit_input(820, 1, heading.x, heading.y, false, 0.0, 0.1)
		var actual_distance: float = Vector2(traveler.position.x - departure.x,
			traveler.position.z - departure.z).length()
		var credited: float = float(traveler.caravan_night["night_meters"])
		t.check(actual_distance > 0.01,
			"server authorizes a real forward movement under movement budget")
		t.check(credited > 0.01 and credited <= actual_distance + 0.001,
			"night credit never exceeds actual server-observed displacement")
		t.eq(int(server.snapshot_for(820)["you"]["caravan_night"]["night_meters"]),
			floori(credited), "private HUD reflects measured night travel")
		traveler.inventory.remove(str(offer["cargo"]), int(offer["quantity"]))
		traveler.input_budget = 0.1
		server.submit_input(820, 2, heading.x, heading.y, false, 0.0, 0.1)
		t.near(float(traveler.caravan_night["night_meters"]), credited, 0.0001,
			"losing required cargo immediately blocks additional night credit")
		measured = true
		break
	t.check(measured, "world provides a real night route for server integration test")

	t.current = "server command, journal save, private HUD and clear-on-delivery"
	var real = server.add_player(823, "AuthenticatedCourier")
	real.position = _at(world, float(site["station_x"]), float(site["station_z"]))
	t.eq(server.cmd_caravan(823, "accept").get("ok"), true,
		"only an authenticated NPC merchant activates a job")
	t.eq(real.caravan_night.get("night_meters"), 0.0,
		"new assignment begins at zero")
	real.inventory.add(str(offer["cargo"]), int(offer["quantity"]))
	_walk_forward(real.caravan_night, offer, true, 2, 3)
	t.eq(server.snapshot_for(823)["you"]["caravan_night"]["qualified"], true,
		"only owning player sees server-owned bonus qualification")
	var saved: Dictionary = server.character_data(real)
	var restored = server.add_player(824, "ReloggedNightCourier")
	t.check(server.apply_character(restored, saved),
		"valid night route progress survives relog")
	t.eq(restored.caravan_night, real.caravan_night,
		"paid distance does not restart or vanish on login")
	var tampered: Dictionary = saved.duplicate(true)
	tampered["caravan_night"]["src_id"] = -7
	t.check(not server.apply_character(restored, tampered),
		"forged route identity is rejected before any player mutation")
	t.eq(restored.caravan_night, real.caravan_night,
		"failed save load leaves valid progress intact")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("caravan_night")
	t.check(server.apply_character(restored, legacy),
		"old caravan saves without a night journal still load")
	t.eq(float(restored.caravan_night["night_meters"]), 0.0,
		"legacy load never awards premium retroactively")
	real.position = _at(world, float(offer["dst_x"]), float(offer["dst_z"]))
	var actual: Dictionary = server.cmd_caravan(823, "deliver")
	t.eq(actual.get("night_bonus", -1), expected_bonus,
		"real server payout uses its own verified route journal")
	t.check(real.caravan_night.is_empty(), "successful delivery clears premium journal")
	t.eq(server.cmd_caravan(823, "deliver").get("reason"), "no_active",
		"replaying claim cannot collect a second payment")
	real.position = _at(world, float(site["station_x"]), float(site["station_z"]))
	t.eq(server.cmd_caravan(823, "accept").get("ok"), true,
		"same courier may accept a fresh route")
	t.eq(NightCaravan.earned_bonus(offer, real.caravan_night), 0,
		"new contract does not reuse previous night credit")
	real.position = _at(world, float(offer["dst_x"]), float(offer["dst_z"]))
	real.inventory.add(str(offer["cargo"]), int(offer["quantity"]))
	t.eq(server.cmd_caravan(823, "deliver").get("night_bonus", -1), 0,
		"teleporting to destination and waiting never earns premium")
	real.position = _at(world, float(site["station_x"]), float(site["station_z"]))
	t.eq(server.cmd_caravan(823, "accept").get("ok"), true,
		"abandon test starts a new valid caravan")
	_walk_forward(real.caravan_night, offer, true, 2, 3)
	t.check(server.cmd_caravan(823, "abandon").get("ok", false),
		"live courier can cancel the route without reward")
	t.check(real.caravan_night.is_empty(), "abandon clears all earned night progress")
	t.eq(server.cmd_caravan(823, "accept").get("ok"), true,
		"death test starts a fresh real NPC caravan")
	_walk_forward(real.caravan_night, offer, true, 2, 3)
	real.survival.hurt(100000.0)
	server._on_player_death(real, -1)
	t.eq(float(real.caravan_night["night_meters"]), 0.0,
		"death wipes all unclaimed night premium progress")
	t.eq(server.cmd_caravan(823, "abandon").get("reason"), "dead",
		"dead courier cannot interact with an NPC trader"
)
