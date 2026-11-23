extends RefCounted
## Seed-bound, once-only world discovery and migration regression.
const WorldDiscovery = preload("res://scripts/shared/world_discovery.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Net = preload("res://scripts/shared/net.gd")


func _site(world) -> Dictionary:
	for rx in range(-5, 6):
		for rz in range(-5, 6):
			var places: Array = world.poi.sites_in_region(rx, rz)
			if not places.is_empty():
				return places[0]
	return {}


class TestDiscoveryPoi:
	extends RefCounted
	var site: Dictionary = {}

	func site_at(_x: float, _z: float) -> Dictionary:
		return site


class TestDiscoveryWorld:
	extends RefCounted
	var poi: RefCounted


func run(t) -> void:
	t.current = "malformed generated POIs cannot corrupt discovery rewards"
	var broken_world := TestDiscoveryWorld.new()
	var fake_poi := TestDiscoveryPoi.new()
	broken_world.poi = fake_poi
	var fake_journal: Dictionary = {}
	for invalid_site in [
		{"id": 17, "x": NAN, "z": 256.0},
		{"id": 17, "x": 256.0, "z": INF},
		{"id": -1, "x": 256.0, "z": 256.0},
		{"id": WorldDiscovery.MAX_SITE_ID + 1, "x": 256.0, "z": 256.0},
		{"id": "17", "x": 256.0, "z": 256.0},
		{"id": 17, "x": "256", "z": 256.0},
		{"id": 17, "x": 256.0},
	]:
		fake_poi.site = invalid_site
		t.eq(WorldDiscovery.reveal(broken_world, Vector3.ZERO, fake_journal), {},
			"malformed generated site cannot be rewarded")
		t.check(fake_journal.is_empty(), "rejected site leaves explorer progress unchanged")
	fake_poi.site = {"id": 17, "x": 256.0, "z": 256.0}
	t.eq(WorldDiscovery.reveal(broken_world, Vector3.ZERO, fake_journal).get("id", -1), 17,
		"valid generated site still enters the explorer journal")
	t.eq(fake_journal.size(), 1, "one valid discovery is credited exactly once")

	t.current = "arrival at a real landmark; no free discoveries"
	var world := WorldGen.new(1337)
	var site: Dictionary = _site(world)
	t.check(not site.is_empty(), "world contains visitable landmarks")
	if site.is_empty():
		return
	var spot := Vector3(float(site["x"]), float(site["y"]), float(site["z"]))
	var journal: Dictionary = {}
	t.check(WorldDiscovery.reveal(world, Vector3.INF, journal).is_empty(),
		"nonfinite positions cannot discover a site")
	t.check(journal.is_empty(), "bad positions do not mutate journal")
	t.eq(WorldDiscovery.reveal(world, spot, journal).get("id"), site["id"],
		"entering generated bounds reveals the actual landmark")
	t.check(WorldDiscovery.reveal(world, spot, journal).is_empty(),
		"revisiting cannot trigger discovery twice")
	t.eq(journal.size(), 1, "journal has one site")
	t.check(WorldDiscovery.explorer_xp(3) > WorldDiscovery.explorer_xp(0),
		"high-risk landmarks award more explorer XP")
	t.check(WorldDiscovery.renown(3) > WorldDiscovery.renown(0),
		"high-risk landmarks award more renown")

	t.current = "squared-distance POI queries match the original geometric oracle"
	var query_x: float = float(site["x"]) + 12.5
	var query_z: float = float(site["z"]) - 9.5
	for radius in [0.0, 4.0, 30.0, 92.0]:
		var oracle: Array = []
		var margin: float = radius + 100.0
		for rx in range(floori((query_x - margin) / 256.0),
				floori((query_x + margin) / 256.0) + 1):
			for rz in range(floori((query_z - margin) / 256.0),
					floori((query_z + margin) / 256.0) + 1):
				for nearby_site in world.poi.sites_in_region(rx, rz):
					var position: Vector2 = Vector2(float(nearby_site["x"]),
						float(nearby_site["z"]))
					var site_limit: float = radius + float(nearby_site["radius"])
					if position.distance_to(Vector2(query_x, query_z)) <= site_limit:
						oracle.append(nearby_site)
		t.eq(world.poi.sites_near(query_x, query_z, radius), oracle,
			"distance-squared query preserves exact world candidates")
	t.eq(world.poi.site_at(float(site["x"]), float(site["z"]))["id"],
		site["id"], "site-center lookup still identifies the true landmark")
	t.check(world.poi.sites_near(NAN, 0.0, 1.0).is_empty(),
		"invalid coordinates never expand into unbounded region scans")
	t.check(world.poi.sites_near(0.0, 0.0, -1.0).is_empty(),
		"negative query radius is rejected")
	t.check(not world.poi.station_near(query_x, query_z, NAN),
		"invalid workbench reach grants no interaction")
	if bool(site.get("station", false)):
		t.check(world.poi.station_near(float(site["station_x"]), float(site["station_z"])),
			"settlement workbench remains reachable at its actual position")

	t.current = "save records are finite, unique and world-seed verified"
	var records: Array = WorldDiscovery.to_saved(journal)
	t.eq(records.size(), 1, "one entry persisted")
	t.eq(WorldDiscovery.ids(journal), [int(site["id"])], "map receives visited IDs")
	t.eq(WorldDiscovery.from_saved(JSON.parse_string(JSON.stringify(records)), world)
		.get("journal", {}), journal, "JSON numeric roundtrip is accepted")
	t.check(WorldDiscovery.from_saved([{"rx": 0, "rz": 0, "id": 0}], world).is_empty(),
		"fictional site rejected")
	var duplicate: Array = records.duplicate(true)
	duplicate.append(records[0].duplicate(true))
	t.check(WorldDiscovery.from_saved(duplicate, world).is_empty(),
		"duplicate regions are forbidden")
	var bad: Array = records.duplicate(true)
	bad[0]["rx"] = INF
	t.check(WorldDiscovery.from_saved(bad, world).is_empty(), "nonfinite region rejected")
	bad = records.duplicate(true)
	bad[0]["id"] = float(site["id"]) + 0.5
	t.check(WorldDiscovery.from_saved(bad, world).is_empty(), "fractional ID rejected")
	t.check(WorldDiscovery.from_saved(records, WorldGen.new(1338)).is_empty(),
		"same site record cannot be imported into foreign world seed")

	t.current = "journal serialization is canonical independent of insertion order"
	var first_journal: Dictionary = {
		Vector2i(2, 0): 8, Vector2i(-1, 1): 8, Vector2i(2, -1): 8,
		Vector2i(0, 0): 3,
	}
	var second_journal: Dictionary = {
		Vector2i(0, 0): 3, Vector2i(2, -1): 8,
		Vector2i(-1, 1): 8, Vector2i(2, 0): 8,
	}
	var canonical: Array = WorldDiscovery.to_saved(first_journal)
	t.eq(canonical, WorldDiscovery.to_saved(second_journal),
		"reordered journals persist in the same byte-stable record order")
	t.eq(canonical[0], {"rx": 0, "rz": 0, "id": 3},
		"site IDs remain the primary ordering field")
	t.eq(canonical[1], {"rx": -1, "rz": 1, "id": 8},
		"equal IDs sort by region coordinates")
	t.eq(canonical[2], {"rx": 2, "rz": -1, "id": 8},
		"equal-region X sorts by Z without relying on dictionary order")

	t.current = "live rewards only once and owner-only map status"
	var sim := GameServer.new(world, 1337)
	var explorer = sim.add_player(777, "Cartographer", "account-777")
	explorer.position = spot
	var renown_before: int = explorer.renown
	sim._tick_site_discoveries()
	t.eq(explorer.discovered_sites.size(), 1, "server visited site is recorded")
	t.eq(explorer.renown - renown_before,
		WorldDiscovery.renown(int(site["zone"])), "first visit gives fixed renown")
	var snap: Dictionary = sim.snapshot_for(777)["you"]
	t.eq(snap["discovered_count"], 1, "network map shows personal visit count")
	t.eq(snap["discovered_site_ids"], [int(site["id"])],
		"network sends only authenticated visited IDs")
	t.check(not snap.has("discovered_sites"), "region identity not exposed")
	var notices: Array = sim.drain_events().filter(
		func(e): return e.get("type") == "site_discovered")
	t.eq(notices.size(), 1, "only one first-visit announcement")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	if not notices.is_empty():
		t.check(net._event_visible_to(notices[0], 777), "owner sees discovery")
		t.check(not net._event_visible_to(notices[0], 888),
			"strangers cannot track personal exploration")
	net.free()
	sim._tick_site_discoveries()
	t.eq(explorer.renown, renown_before + WorldDiscovery.renown(int(site["zone"])),
		"repeat scan does not farm reputation")
	var saved: Dictionary = sim.character_data(explorer)
	var reconnect := GameServer.new(WorldGen.new(1337), 1337)
	var restored = reconnect.add_player(888, "Cartographer", "account-777", saved)
	t.eq(restored.discovered_sites.size(), 1, "reconnecting preserves journal")
	restored.position = spot
	reconnect._tick_site_discoveries()
	t.check(reconnect.drain_events().filter(
		func(e): return e.get("type") == "site_discovered").is_empty(),
		"reconnect cannot replay site rewards")

	t.current = "malformed saved landmarks fail atomically; legacy compatible"
	var corrupt: Dictionary = saved.duplicate(true)
	corrupt["discovered_sites"][0]["id"] = -1
	var good_renown: int = restored.renown
	var good_journal: Dictionary = restored.discovered_sites.duplicate()
	t.check(not reconnect.apply_character(restored, corrupt),
		"invalid world progress rejects whole save")
	t.eq(restored.renown, good_renown, "bad save leaves renown untouched")
	t.eq(restored.discovered_sites, good_journal,
		"bad save leaves current visited places intact")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("discovered_sites")
	t.check(reconnect.apply_character(restored, legacy),
		"version-one characters without journal remain valid")
	t.check(restored.discovered_sites.is_empty(), "legacy journal starts empty")
