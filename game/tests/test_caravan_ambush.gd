extends RefCounted
## Dangerous-zone cargo escorts: genuine materials, terrain-safe waves,
## private warnings, bounded spawns, persistence and no duplicate ambush.
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const CaravanRoutes = preload("res://scripts/shared/caravan_routes.gd")
const CaravanAmbush = preload("res://scripts/shared/caravan_ambush.gd")
const NightHorde = preload("res://scripts/shared/night_horde.gd")
const Net = preload("res://scripts/shared/net.gd")


func _source(world) -> Dictionary:
	for rx in range(-4, 5):
		for rz in range(-4, 5):
			for site in world.poi.sites_in_region(rx, rz):
				if not CaravanRoutes.offer_for(world, site).is_empty():
					return site
	return {}


func _ambush_point(world, offer: Dictionary) -> Vector3:
	var source := Vector2(float(offer["src_x"]), float(offer["src_z"]))
	for radius in [760.0, 820.0, 900.0, 1100.0, 1200.0]:
		for i in range(96):
			var point := Vector2.from_angle(TAU * float(i) / 96.0) * radius
			if point.distance_to(source) < 120.0 or world.zone_at(point.x, point.y) != 2 \
					or world.is_water(point.x, point.y) or world.normal_at(point.x, point.y).y < 0.8:
				continue
			var position := Vector3(point.x, world.height_at(point.x, point.y), point.y)
			if not CaravanAmbush.eligible(world, position, offer, 1, false, true):
				continue
			var survivors: Array[Vector3] = [position]
			if NightHorde.sites(world, position, survivors, {}, 3).size() >= 2:
				return position
	return Vector3.INF


func run(t) -> void:
	t.current = "route progression and real carried cargo gate infected raids"
	var world := WorldGen.new(205)
	var site: Dictionary = _source(world)
	t.check(not site.is_empty(), "world has two eligible trade villages")
	if site.is_empty():
		return
	var offer: Dictionary = CaravanRoutes.offer_for(world, site)
	var route_saved: Dictionary = CaravanRoutes.saved_state(offer)
	var source_pos := Vector3(float(offer["src_x"]), 0, float(offer["src_z"]))
	t.check(not CaravanAmbush.eligible(world, source_pos, offer, 1, false, true),
		"starting merchant never ambushes the player")
	var position: Vector3 = _ambush_point(world, offer)
	t.check(position.is_finite(), "find walkable full-loot site with safe enemy spawns")
	if not position.is_finite():
		return
	t.check(CaravanAmbush.eligible(world, position, offer, 1, false, true),
		"real T2 cargo in the red PvP zone attracts roaming infected")
	t.check(not CaravanAmbush.eligible(world, position, offer, 0, false, true),
		"players without the contracted item never attract a route ambush")
	t.check(not CaravanAmbush.eligible(world, position, offer, 1, true, true),
		"completed-once encounter cannot repeat during same route")
	t.check(not CaravanAmbush.eligible(world, position, offer, 1, false, false),
		"dead survivors cannot trigger a caravan event")
	t.check(not CaravanAmbush.eligible(world, Vector3.INF, offer, 1, false, true),
		"nonfinite positions never spawn infected")
	t.eq(CaravanAmbush.available([{}, {}, {}, {}], {}), 0,
		"four active waves prevent unbounded server pressure")
	t.eq(CaravanAmbush.available([], {1: true}), CaravanAmbush.MAX_ACTIVE_INFECTED - 1,
		"active infected count is respected before spawning")

	t.current = "server spawns real enemies and one private warning"
	var sim := GameServer.new(world, 205)
	var owner = sim.add_player(901, "Caravan Survivor", "caravan-901")
	var stranger = sim.add_player(902, "Unrelated Survivor")
	stranger.position = Vector3(0, world.height_at(0, 0), 0)
	owner.position = position
	owner.caravan_state = route_saved
	owner.caravan_view = offer.duplicate(true)
	sim.tick_count = CaravanAmbush.CHECK_EVERY_TICKS
	sim.time = 500.0
	sim._tick_caravan_ambush()
	t.check(sim.caravan_ambushes.is_empty(), "empty cargo never spawns a patrol")
	owner.inventory.add(str(offer["cargo"]), 1)
	sim._tick_caravan_ambush()
	t.check(owner.caravan_ambushed, "successful wave marks route permanently")
	t.check(owner.dirty_character, "successful ambush mark schedules Nakama save")
	t.eq(sim.caravan_ambushes.size(), 1, "only one event is registered")
	if sim.caravan_ambushes.is_empty():
		return
	var spawned: Array = sim.caravan_ambushes[0]["ids"]
	t.check(spawned.size() >= 2 and spawned.size() <= 4,
		"the ambush is a small real 2-4 infected squad")
	for id in spawned:
		t.check(sim.zombies.has(int(id)), "the enemy is a server-owned simulated zombie")
		var infected = sim.zombies[int(id)]
		t.eq(infected.spawn_id, -1, "ambush enemies cannot overwrite natural respawn slots")
		t.check(not infected.raid_boss and not infected.elite,
			"caravan attackers do not impersonate raid loot")
	var alerts: Array = sim.drain_events().filter(
		func(e): return str(e.get("type", "")) == "caravan_ambushed")
	t.eq(alerts.size(), 1, "exactly one convoy warning emitted")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net._event_visible_to(alerts[0], 901),
		"the courier receives their private hazard alert")
	t.check(not net._event_visible_to(alerts[0], 902),
		"unrelated survivor cannot obtain private route threat notice")
	net.free()
	sim._tick_caravan_ambush()
	t.eq(sim.caravan_ambushes.size(), 1, "replayed tick cannot create another ambush")
	t.eq(sim.drain_events().size(), 0, "no repeat events after ambush latch")

	t.current = "per-route event latch survives logout and resists save tampering"
	var saved: Dictionary = sim.character_data(owner)
	t.check(bool(saved.get("caravan_ambushed", false)),
		"one-shot state persists separately from source/destination ID")
	var recovered = sim.add_player(903, "Recovered Courier")
	t.check(sim.apply_character(recovered, saved), "restored character loads real caravan")
	t.check(recovered.caravan_ambushed, "relogged courier cannot refarm a second attack")
	var invalid: Dictionary = saved.duplicate(true)
	invalid["caravan_ambushed"] = "yes"
	t.check(not sim.apply_character(recovered, invalid), "string flag is rejected before mutation")
	t.check(recovered.caravan_ambushed, "invalid save does not mutate restored status")
	invalid = saved.duplicate(true)
	invalid["caravan"] = {}
	t.check(not sim.apply_character(recovered, invalid),
		"client save cannot attach completed ambush flag to nonexistent route")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("caravan_ambushed")
	t.check(sim.apply_character(recovered, legacy), "old save without ambush flag stays compatible")
	t.check(not recovered.caravan_ambushed, "old caravan starts with no event mark")

	t.current = "expiry cleans event enemies and does not award free treasure"
	var initial_bags: int = sim.bags.size()
	sim.time = float(sim.caravan_ambushes[0]["expires"])
	sim.tick_count = CaravanAmbush.CHECK_EVERY_TICKS + 1
	sim._tick_caravan_ambush()
	t.eq(sim.caravan_ambushes.size(), 0, "expired wave record is removed")
	for id in spawned:
		t.check(not sim.zombies.has(int(id)), "expired summoned zombie is deleted")
	t.eq(sim.bags.size(), initial_bags,
		"expiry never generates a free public chest or duplicate reward")
