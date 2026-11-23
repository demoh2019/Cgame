extends RefCounted
## Private caravan and squad rally markers, compass accuracy and clipped
## minimap geometry. Nothing here is a gameplay authority or RPC.
const Nav = preload("res://scripts/shared/travel_navigation.gd")
const Radar = preload("res://scripts/client/survival_radar.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "north-up route compass and safe coordinate parsing"
	var origin := Vector2(12.0, 8.0)
	var vectors := [Vector2(0, -25), Vector2(20, -20), Vector2(30, 0),
		Vector2(20, 20), Vector2(0, 25), Vector2(-20, 20),
		Vector2(-30, 0), Vector2(-20, -20)]
	for i in vectors.size():
		t.eq(Nav.compass(origin, origin + vectors[i]), Nav.LABELS[i],
			"eight precise compass sectors, including north = negative Z")
	t.eq(Nav.compass(origin, origin), "ARRIVED",
		"standing at destination produces arrived heading")
	t.eq(Nav.distance_meters(Vector2.ZERO, Vector2(3, 4)), 5,
		"distance is exact straight-line meters")
	t.eq(Nav.distance_meters(Vector2.INF, Vector2.ZERO), -1,
		"invalid player position has no fake distance")
	t.eq(Nav.target({"dst_x": 9.0, "dst_z": -11.0}, "dst_x", "dst_z"),
		Vector2(9, -11), "authoritative snapshot fields are read literally")
	t.check(not Nav.target({"dst_x": 9.0}, "dst_x", "dst_z").is_finite(),
		"missing destination is not drawn")
	t.check(not Nav.target({"dst_x": NAN, "dst_z": 1.0},
		"dst_x", "dst_z").is_finite(), "nonfinite packet is ignored")
	t.check(not Nav.target({"dst_x": "0", "dst_z": 1.0},
		"dst_x", "dst_z").is_finite(), "text cannot turn into a waypoint")

	t.current = "world map ignores overflow coordinates instead of showing false directions"
	t.eq(Nav.distance_meters(Vector2.ZERO, Vector2(1.0e30, 0.0)), -1,
		"overflowing distance cannot be converted into a fake UI meter count")
	t.eq(Nav.compass(Vector2.ZERO, Vector2(1.0e30, 0.0)), "",
		"extreme finite coordinates cannot become a misleading compass sector")
	t.eq(Nav.compass(Vector2(-1.0e30, 0.0), Vector2(1.0e30, 0.0)), "",
		"finite endpoints with overflowing separation cannot create a compass heading")
	t.check(not Nav.valid_destination(Vector2(1.0e30, 0.0), 1.0e30),
		"overflowing world and position squares cannot mark a point as in-bounds")
	t.check(Nav.valid_destination(Vector2(25.0, 50.0), 100.0),
		"ordinary in-world map destinations stay selectable")

	t.current = "radar projection clips distant waypoints to map edge"
	var size := Vector2(200, 200)
	var near: Dictionary = Nav.project(Vector2.ZERO, Vector2(36, -36), size)
	t.check(bool(near.get("inside", false)), "nearby caravan destination is inside radar")
	t.near((near["point"] as Vector2).x, 144.0, 0.001,
		"east relative to player renders to the right")
	t.near((near["point"] as Vector2).y, 56.0, 0.001,
		"north relative to player renders towards screen top")
	var far: Dictionary = Nav.project(Vector2.ZERO, Vector2(900, 0), size)
	t.check(not bool(far.get("inside", true)), "distant caravan uses edge pointer")
	t.eq(far["point"], Vector2(186.0, 100.0), "arrow stays inside map boundary")
	t.eq(Nav.project(Vector2.ZERO, Vector2.INF, size), {},
		"invalid target never produces fake screen geometry")
	t.eq(Nav.project(Vector2.ZERO, Vector2.ONE, Vector2.ZERO), {},
		"zero-size radar does not divide by zero")
	t.eq(Nav.project(Vector2.ZERO, Vector2.ONE, size, 0.0), {},
		"invalid radar world radius is rejected")

	t.current = "only self or authenticated party sees navigation markers"
	var world := WorldGen.new(205)
	var sim := GameServer.new(world, 205)
	var leader = sim.add_player(701, "Navigator")
	var ally = sim.add_player(702, "Escort")
	# Authoritative invites require actual proximity: random spawns are
	# intentionally not relied on by this deterministic regression.
	ally.position = leader.position + Vector3(1.0, 0.0, 0.0)
	sim.add_player(703, "Stranger")
	var route := {"dst_id": 12, "dst_x": 500.0, "dst_z": -250.0}
	leader.caravan_view = route.duplicate()
	var radar := Radar.new()
	radar.world = world
	radar.sim = sim
	radar.actor_id = 701
	t.eq(radar.current_caravan(), route, "local character sees their personal caravan")
	radar.actor_id = 702
	t.eq(radar.current_caravan(), {}, "escort cannot read leader's private job")
	radar.actor_id = 703
	t.eq(radar.current_caravan(), {}, "stranger cannot read player's caravan")
	t.check(radar.current_rally().is_empty(), "unauthorized survivor has no group marker")
	t.check(sim.cmd_party_invite(701, 702).get("ok", false), "leader forms a real party")
	t.check(sim.cmd_party_accept(702).get("ok", false), "escort becomes a real member")
	t.check(sim.cmd_party_rally(701).get("ok", false),
		"leader sets rally using server-owned position, not chosen coordinates")
	radar.actor_id = 702
	var marker: Dictionary = radar.current_rally()
	t.check(not marker.is_empty(), "escort receives the live party-only rendezvous")
	t.eq(Vector2(float(marker["x"]), float(marker["z"])),
		Vector2(leader.position.x, leader.position.z),
		"party marker points to real leader server location")
	radar.actor_id = 703
	t.eq(radar.current_rally(), {}, "unrelated player sees no rally direction")
	sim.parties.leave(702)
	radar.actor_id = 702
	t.eq(radar.current_rally(), {}, "leaving a party immediately revokes rally")
	# A route is still personal even if its owner joins a party.
	t.eq(radar.current_caravan(), {}, "an ex-party member has no route leaked")
