extends RefCounted
## Wounds influence infected awareness through server-authored, bounded scent.
const BloodScent = preload("res://scripts/shared/blood_scent.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Survival = preload("res://scripts/shared/survival.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func _players(position: Vector3, scent: float, safe: bool = false, alive: bool = true) -> Dictionary:
	return {7: {"position": position, "alive": alive, "safe": safe,
		"noise": 0.0, "notice_multiplier": 1.0, "scent": scent}}


func run(t) -> void:
	t.current = "bounded scent: bleeding, treatment and safe zones"
	t.eq(BloodScent.detection_radius(0.0), 0.0, "healthy survivor has no blood trail")
	t.eq(BloodScent.detection_radius(BloodScent.MIN_BLEEDING), 0.0,
		"minor wounds do not add extra detection")
	t.near(BloodScent.detection_radius(60.0), 25.2, 0.0001,
		"serious bleeding expands infected detection range")
	t.near(BloodScent.detection_radius(100.0), BloodScent.MAX_RANGE, 0.0001,
		"severe wounds do not exceed maximum scent radius")
	t.eq(BloodScent.detection_radius(1_000_000.0), BloodScent.MAX_RANGE,
		"unrealistically large wound values are clamped")
	for invalid in [NAN, INF, -INF, -1.0]:
		t.eq(BloodScent.detection_radius(invalid), 0.0,
			"invalid wound severity does not create scent")
	t.eq(BloodScent.detection_radius(100.0, false, false), 0.0,
		"dead survivor has no detectable blood scent")
	t.eq(BloodScent.detection_radius(100.0, true, true), 0.0,
		"safe-zone survivor never creates infected scent")

	t.current = "infected track blood outside normal sight or hearing"
	var world := WorldGen.new(111)
	var rng := RandomNumberGenerator.new()
	rng.seed = 334
	var ground: float = WorldGen.HUB_HEIGHT
	var origin := Vector3(0.0, ground, 0.0)
	var distant := Vector3(24.0, ground, 0.0)
	var quiet := Zombie.new(1, "walker", origin)
	for i in 5:
		quiet.think(world, _players(distant, 0.0), 0.1, rng)
	t.check(quiet.state != Zombie.State.CHASE and quiet.state != Zombie.State.ATTACK,
		"a quiet player beyond walker sight is not found")
	var bleeding := Zombie.new(2, "walker", origin)
	for i in 5:
		bleeding.think(world, _players(distant, BloodScent.detection_radius(60.0)), 0.1, rng)
	t.eq(bleeding.target_id, 7, "server-supplied blood scent attracts a walker")
	t.eq(bleeding.state, Zombie.State.CHASE, "infected pursues bleeding survivor")

	t.current = "first aid removes the acquisition signal"
	var survival := Survival.new()
	t.check(survival.add_bleeding(60.0), "real survivor takes a severe wound")
	t.check(BloodScent.detection_radius(survival.bleeding) > 24.0,
		"fresh wound produces detectable scent")
	t.check(survival.stop_bleeding(), "bandage-like treatment stops bleeding")
	var treated := Zombie.new(3, "walker", origin)
	for i in 5:
		treated.think(world, _players(distant, BloodScent.detection_radius(survival.bleeding)), 0.1, rng)
	t.check(treated.state != Zombie.State.CHASE and treated.state != Zombie.State.ATTACK,
		"treated survivor no longer acquires new infected")
	for case in [
		{"id": 4, "safe": true, "alive": true},
		{"id": 5, "safe": false, "alive": false},
	]:
		var protected := Zombie.new(int(case["id"]), "walker", origin)
		for i in 5:
			protected.think(world, _players(distant, 29.0, bool(case["safe"]),
				bool(case["alive"])), 0.1, rng)
		t.check(protected.state != Zombie.State.CHASE and protected.state != Zombie.State.ATTACK,
			"blood scent never bypasses safe/dead immunity")
	var outside := Zombie.new(6, "walker", origin)
	for i in 5:
		outside.think(world, _players(Vector3(40.0, ground, 0.0), 1000.0), 0.1, rng)
	t.check(outside.target_id == -1, "even forged scent cannot bypass pursuit leash")
	var invalid_scent := Zombie.new(8, "walker", origin)
	for i in 5:
		invalid_scent.think(world, _players(distant, NAN), 0.1, rng)
	t.eq(invalid_scent.target_id, -1, "nonfinite scent is ignored by the zombie brain")

	t.current = "authoritative world simulation and private snapshot"
	var live_world := WorldGen.new(314)
	var server := GameServer.new(live_world, 314)
	var survivor = server.add_player(456, "Wounded")
	survivor.position = _at(live_world, 300.0, 0.0)
	t.check(not live_world.is_safe(survivor.position.x, survivor.position.z),
		"test survivor is outside the settlement")
	t.check(survivor.survival.add_bleeding(60.0),
		"server owns actual bleeding severity")
	var infected := Zombie.new(server.new_id(), "walker", _at(live_world, 324.0, 0.0))
	server.zombies[infected.id] = infected
	server._tick_zombies(0.1)
	t.eq(infected.target_id, survivor.id,
		"ordinary server zombie tick detects injured distant survivor")
	var owner: Dictionary = server.snapshot_for(survivor.id)["you"]
	t.near(float(owner["blood_scent_radius"]), 25.2, 0.0001,
		"HUD receives the same authoritative scent calculation")
	t.check(survivor.survival.stop_bleeding(), "server wound treatment clears blood")
	t.eq(server.snapshot_for(survivor.id)["you"]["blood_scent_radius"], 0.0,
		"treated survivor sees no new scent risk")

	t.current = "PvE pursuit stays off when the survivor is healthy"
	var healthy_server := GameServer.new(WorldGen.new(315), 315)
	var healthy = healthy_server.add_player(458, "Healthy")
	healthy.position = _at(healthy_server.world, 300.0, 0.0)
	var idle := Zombie.new(healthy_server.new_id(), "walker",
		_at(healthy_server.world, 324.0, 0.0))
	healthy_server.zombies[idle.id] = idle
	healthy_server._tick_zombies(0.1)
	t.eq(idle.target_id, -1, "same location with no bleeding is not detected")
