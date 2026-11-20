extends RefCounted
## Server-authoritative weather shelter: costs, security, privacy and expiration.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const PortableShelter = preload("res://scripts/shared/portable_shelter.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const Persist = preload("res://scripts/server/world_persistence.gd")
const BarricadeTest = preload("res://tests/test_barricades.gd")


func _at(world, at: Vector2) -> Vector3:
	return Vector3(at.x, world.height_at(at.x, at.y), at.y)


func run(t) -> void:
	var world := WorldGen.new(214)
	var sim := GameServer.new(world, 22)
	var spot: Vector2 = BarricadeTest.new()._find_place(world)
	t.current = "shelters require genuine materials and server-valid terrain"
	t.check(spot != Vector2.ZERO, "dry legal site exists")
	if spot == Vector2.ZERO:
		return
	var origin := spot + Vector2(-2.8, 0)
	var owner = sim.add_player(93, "Camper")
	owner.position = _at(world, origin)
	t.eq(sim.cmd_pitch_shelter(999, spot.x, spot.y).get("reason", ""),
		"dead", "unregistered peer cannot deploy")
	t.eq(sim.cmd_pitch_shelter(93, NAN, spot.y).get("reason", ""),
		"invalid_position", "forged NaN site is rejected")
	t.eq(sim.cmd_pitch_shelter(93, spot.x + 90.0, spot.y).get("reason", ""),
		"out_of_range", "cannot remotely deploy")
	t.eq(sim.cmd_pitch_shelter(93, spot.x, spot.y).get("reason", ""),
		"missing_materials", "no free construction")
	owner.inventory.add("cloth_1", 5)
	owner.inventory.add("fiber_1", 5)
	owner.inventory.add("plank_1", 3)
	var placed: Dictionary = sim.cmd_pitch_shelter(93, spot.x, spot.y)
	t.check(placed.get("ok", false), "real tarp built")
	if not placed.get("ok", false):
		return
	var id: int = int(placed["id"])
	t.eq(owner.inventory.count("cloth_1"), 3, "exact cloth cost")
	t.eq(owner.inventory.count("fiber_1"), 3, "exact fiber cost")
	t.eq(owner.inventory.count("plank_1"), 2, "exact plank cost")
	t.eq(sim.cmd_pitch_shelter(93, spot.x, spot.y).get("reason", ""),
		"owner_limit", "one tent per survivor")
	t.eq(owner.inventory.count("cloth_1"), 3, "failure does not debit items")
	t.check(not world.dynamic_blockers.has(id), "tarp cannot create invisible walls")
	t.current = "shared weather cover and private interest-limited snapshots"
	t.check(PortableShelter.covers(sim.shelters, owner.position, sim.time),
		"nearby owner sheltered")
	owner.position = _at(world, spot)
	var neighbor = sim.add_player(94, "Neighbor")
	neighbor.position = _at(world, spot + Vector2(1, 0))
	var distant = sim.add_player(95, "Far")
	distant.position = _at(world, spot + Vector2(200, 0))
	t.check(bool(sim.snapshot_for(94)["you"]["tent_sheltered"]),
		"unaffiliated neighbor shares shelter")
	t.check(not bool(sim.snapshot_for(95)["you"]["tent_sheltered"]),
		"distant player gets no cover")
	var visible: Array = sim.snapshot_for(94)["shelters"]
	t.eq(visible.size(), 1, "physical tarp appears nearby")
	t.eq(sim.snapshot_for(95)["shelters"].size(), 0, "far-away tarp is not replicated")
	t.check(not visible[0].has("owner") and not visible[0].has("owner_account"),
		"account and peer ownership remain secret")
	t.check(not Persist.capture(sim).has("shelters"), "temporary tarp never saved")
	t.near(PortableShelter.exposure_severity(0.8, true), 0.2, 0.0001,
		"exact 75-percent weather protection")
	t.near(PortableShelter.exposure_severity(0.8, false), 0.8, 0.0001,
		"no protection at a distance")
	t.eq(PortableShelter.exposure_severity(INF, true), 0.0,
		"malformed weather cannot make infinite exposure")
	t.current = "real server exposure scales during a storm"
	var storm_time := -1.0
	for phase in range(160):
		var when: float = 1.0 + float(phase) * Weather.CHANGE_SECONDS
		var weather: Dictionary = Weather.conditions(world, spot.x, spot.y, when)
		if str(weather.get("condition", "")) == "storm" and float(weather.get("severity", 0.0)) > 0.0:
			storm_time = when
			break
	t.check(storm_time >= 0.0, "deterministic storm with cold exposure")
	if storm_time >= 0.0:
		sim.time = storm_time
		sim.shelters[id]["expires"] = storm_time + PortableShelter.DURATION
		owner.survival.exposure = 20.0
		sim._tick_players(1.0)
		var sheltered_exposure: float = owner.survival.exposure
		var tarp: Dictionary = sim.shelters[id]
		sim.shelters.erase(id)
		owner.survival.exposure = 20.0
		sim._tick_players(1.0)
		t.check(sheltered_exposure < owner.survival.exposure,
			"actual server weather tick gives less exposure under a tarp")
		sim.shelters[id] = tarp
	t.current = "packing, ownership, and expiry"
	t.eq(sim.cmd_pack_shelter(94, id).get("reason", ""), "not_owner",
		"stranger cannot pack tarp")
	owner.position = _at(world, spot + Vector2(18, 0))
	t.eq(sim.cmd_pack_shelter(93, id).get("reason", ""), "out_of_range",
		"owner must be near tarp")
	owner.position = _at(world, spot)
	t.check(sim.cmd_pack_shelter(93, id).get("ok", false), "owner may pack tarp")
	t.eq(owner.inventory.count("cloth_1"), 3, "packing cannot refund materials")
	t.eq(sim.cmd_pack_shelter(93, id).get("reason", ""), "no_shelter",
		"stale entity ID is harmless")
	owner.position = _at(world, origin)
	t.check(sim.cmd_pitch_shelter(93, spot.x, spot.y).get("ok", false),
		"new tent allowed after packing")
	var second_id: int = int(sim.shelters.keys()[0])
	sim.time = float(sim.shelters[second_id]["expires"]) + 0.1
	t.check(not PortableShelter.covers(sim.shelters, owner.position, sim.time),
		"expired tarp gives no protection before cleanup")
	sim._tick_world(0.1)
	t.eq(sim.shelters.size(), 0, "server despawns expired shelters")
