extends RefCounted
## Regression tests for authoritative, pressure-aware world incidents.
## Loaded by res://tests/run_all.gd; no network connection is required.

const Director = preload("res://scripts/shared/world_encounter_director.gd")
const WorldIncidents = preload("res://scripts/shared/world_incidents.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func run(t) -> void:
	t.current = "encounter budget: global cap, zone, health and nearby pressure"
	t.eq(Director.spawn_budget(0, 0, 1.0, 0), 7,
		"quiet green zone retains meaningful encounters")
	t.eq(Director.spawn_budget(0, 0, 1.0, 3), 10,
		"black-zone base wave stays bounded")
	t.eq(Director.spawn_budget(0, 8, 1.0, 3), 4,
		"a nearby pack reduces reinforcement pressure")
	t.eq(Director.spawn_budget(0, 12, 1.0, 3), 2,
		"crowded regions admit only tiny reinforcements")
	t.eq(Director.spawn_budget(0, 20, 1.0, 3), 0,
		"hard local crowd cap blocks additional incidents")
	t.eq(Director.spawn_budget(0, 0, 0.20, 3), 2,
		"a badly wounded survivor receives an easier wave")
	t.eq(Director.spawn_budget(0, 0, 0.50, 3), 4,
		"half-health survivor receives reduced pressure")
	t.eq(Director.spawn_budget(0, 0, NAN, 3), 0,
		"nonfinite survivor health cannot mint an encounter")
	t.eq(Director.spawn_budget(-1, 0, 1.0, 3), 0,
		"invalid global count fails closed")
	t.eq(Director.spawn_budget(WorldIncidents.MAX_ACTIVE_INFECTED, 0, 1.0, 3), 0,
		"full server refuses new enemies")
	t.eq(Director.spawn_budget(WorldIncidents.MAX_ACTIVE_INFECTED - 1, 0, 1.0, 3), 1,
		"only one remaining global slot may be used")

	t.current = "deterministic roster cropping and bounded respite"
	var roster: Array = ["howler", "runner", "walker", "brute"]
	t.eq(Director.bounded_roster(roster, 2), ["howler", "runner"],
		"first scripted encounter unit stays in front")
	t.eq(Director.bounded_roster(roster, -1), [],
		"invalid negative cap cannot spawn enemies")
	t.eq(roster.size(), 4, "roster cropping does not mutate original")
	t.near(Director.respite_seconds(100.0, 0, 1.0), 100.0, 0.001,
		"calm scene keeps original cooldown")
	t.near(Director.respite_seconds(100.0, 8, 1.0), 120.0, 0.001,
		"pressure extends the cooldown")
	t.near(Director.respite_seconds(100.0, 12, 0.20), 175.0, 0.001,
		"wounded survivor in dense crowd gets bounded recovery")
	t.eq(Director.respite_seconds(NAN, 0, 1.0), 0.0,
		"nonfinite timers cannot escape the guard")

	t.current = "invalid encounter inputs are rejected before native dispatch"
	for invalid_health in [NAN, INF, -INF]:
		t.eq(Director.spawn_budget(0, 0, invalid_health, 2), 0,
			"nonfinite health cannot create a wave")
		t.eq(Director.respite_seconds(90.0, 8, invalid_health), 0.0,
			"nonfinite health cannot change the encounter cooldown")
	t.eq(Director.spawn_budget(0, -1, 1.0, 3), 0,
		"negative nearby population cannot request a wave")
	t.eq(Director.respite_seconds(INF, 8, 1.0), 0.0,
		"infinite cooldown cannot poison encounter pacing")
	t.eq(Director.respite_seconds(-1.0, 8, 1.0), 0.0,
		"negative cooldown is rejected")
	t.eq(Director.respite_seconds(NAN, 8, 1.0), 0.0,
		"NaN cooldown is rejected")

	t.current = "native encounter pacing and stock Godot parity"
	var native_budget: bool = Director.has_native_budget()
	t.eq(native_budget, ClassDB.class_exists("AIEncounterBudget"),
		"native budget policy is available only in the custom Cgame editor")
	for total in [0, 1, 140, 149, 150, 151]:
		for nearby in [-1, 0, 7, 8, 11, 12, 19, 20, 21]:
			for health in [-1.0, 0.0, 0.30, 0.50, 0.55, 0.8, 1.0, 2.0]:
				for zone in [-2, 0, 1, 2, 3, 5]:
					t.eq(Director.spawn_budget(total, nearby, health, zone),
						Director.spawn_budget(total, nearby, health, zone, false),
						"native admission matches authoritative reference at boundaries")
				for base_delay in [0.0, 90.0, 120.0]:
					t.near(Director.respite_seconds(base_delay, nearby, health),
						Director.respite_seconds(base_delay, nearby, health, false), 0.0001,
						"native recovery never diverges from stock Godot")
	t.eq(Director.spawn_budget(0, 0, INF, 3), 0,
		"positive infinity cannot be interpreted as a valid health fraction")
	t.eq(Director.spawn_budget(0, 0, -INF, 3), 0,
		"negative infinity cannot create a wave")
	t.eq(Director.respite_seconds(90.0, 8, INF), 0.0,
		"nonfinite recovery input fails closed")
	if native_budget:
		var policy: Object = ClassDB.instantiate("AIEncounterBudget")
		t.check(bool(policy.call("configure_limits", 300, 4, 6, 12, 3, 7, 4)),
			"encounter policy may be retuned atomically for other games")
		t.eq(int(policy.call("get_spawn_budget", 0, 0, 1.0, 4)), 7,
			"configured zone progression is used by native policy")
		t.eq(int(policy.call("get_spawn_budget", 0, 6, 1.0, 4)), 2,
			"configured local pressure limits cannot be bypassed")
		t.eq(int(policy.call("get_spawn_budget", 0, 12, 1.0, 4)), 0,
			"hard density cap works even for customized encounter policies")
		policy = null # RefCounted: release the temporary, never force free.

	t.current = "nearby infected: only living neighbors count"
	var enemies: Dictionary = {}
	enemies[1] = Zombie.new(1, "walker", Vector3(2.0, 0.0, 0.0))
	enemies[2] = Zombie.new(2, "runner", Vector3(200.0, 0.0, 0.0))
	enemies[3] = Zombie.new(3, "walker", Vector3(3.0, 0.0, 0.0))
	enemies[3].state = Zombie.State.DEAD
	t.eq(Director.nearby_infected(enemies, Vector3.ZERO), 1,
		"dead and faraway infected do not count as local pressure")
	t.eq(Director.nearby_infected(enemies, Vector3.INF), Director.LOCAL_HARD_CAP,
		"invalid source positions fail closed")

	t.current = "native 3D crowd pressure agrees with exact server distance"
	var close_enemy_positions: Dictionary = {}
	var random_grid := RandomNumberGenerator.new()
	random_grid.seed = 370121
	for index in range(45):
		var p := Vector3(random_grid.randf_range(-170.0, 170.0),
			random_grid.randf_range(-180.0, 180.0),
			random_grid.randf_range(-170.0, 170.0))
		close_enemy_positions[index] = Zombie.new(3000 + index, "walker", p)
	# A vertical separation exceeds 75 m, even when XZ coordinates overlap.
	var cave := Zombie.new(7001, "walker", Vector3(0.0, -100.0, 0.0))
	close_enemy_positions[7001] = cave
	var surface := Zombie.new(7002, "walker", Vector3(0.0, 100.0, 0.0))
	close_enemy_positions[7002] = surface
	var corpse := Zombie.new(7003, "walker", Vector3.ZERO)
	corpse.state = Zombie.State.DEAD
	close_enemy_positions[7003] = corpse
	t.eq(Director.nearby_infected(close_enemy_positions, Vector3.ZERO),
		Director.nearby_infected(close_enemy_positions, Vector3.ZERO, false),
		"2D map overlap cannot produce a false 3D local-pressure hit")
	for iteration in range(65):
		var center := Vector3(random_grid.randf_range(-220.0, 220.0),
			random_grid.randf_range(-210.0, 210.0),
			random_grid.randf_range(-220.0, 220.0))
		t.eq(Director.nearby_infected(close_enemy_positions, center),
			Director.nearby_infected(close_enemy_positions, center, false),
			"native counts match exact server game fallback at probe %d" % iteration)
	t.eq(Director.nearby_infected(close_enemy_positions, Vector3.INF),
		Director.LOCAL_HARD_CAP, "bad 3D centers fail closed before native indexing")
	if ClassDB.class_exists("SpatialPointGrid3D"):
		var grid3d: Object = ClassDB.instantiate("SpatialPointGrid3D")
		t.check(grid3d != null, "native reusable volumetric index instantiates")
		if grid3d != null:
			t.check(bool(grid3d.call("rebuild", [
				Vector3.ZERO, Vector3(0, 75, 0), Vector3(0, -75, 0),
				Vector3(0, 76, 0), Vector3(0, 0, 75)])),
				"native 3D index accepts finite volumetric points")
			t.eq(int(grid3d.call("count_within", Vector3.ZERO, 75.0, 20)), 4,
				"volume radius includes boundary but rejects elevated outlier")
			t.eq(int(grid3d.call("count_within", Vector3.ZERO, 75.0, 2)), 2,
				"early-exit count cap prevents unnecessary crowd scanning")
			var batches: PackedInt32Array = grid3d.call("count_within_batch",
				PackedVector3Array([Vector3.ZERO, Vector3(0, 1000, 0)]), 75.0, 20)
			t.eq(batches, PackedInt32Array([4, 0]),
				"native batched volume queries retain probe order")
			t.eq(int(grid3d.call("count_within", Vector3.INF, 75.0, 20)), -1,
				"invalid 3D center cannot produce a positive count")
	else:
		t.eq(Director.nearby_infected(close_enemy_positions, Vector3.ZERO),
			Director.nearby_infected(close_enemy_positions, Vector3.ZERO, false),
			"stock Godot preserves legacy encounter behavior")

	t.current = "integration: authoritative GameServer refuses saturated crowds"
	var world := WorldGen.new(17417)
	var server := GameServer.new(world, 17417)
	var survivor = server.add_player(81, "Explorer")
	survivor.position = Vector3(350.0, world.height_at(350.0, 350.0), 350.0)
	t.check(not world.is_safe(survivor.position.x, survivor.position.z),
		"test survivor is outside safe hub")
	for i in Director.LOCAL_HARD_CAP:
		var id: int = server.new_id()
		server.zombies[id] = Zombie.new(id, "walker",
			survivor.position + Vector3(float(i % 5), 0.0, float(i / 5)))
	var count_before: int = server.zombies.size()
	var events_before: int = server.events.size()
	server.time = 1000.0
	server.next_incident_at = 0.0
	server._tick_world_incidents()
	t.eq(server.zombies.size(), count_before,
		"server does not spawn incident into saturated local area")
	t.eq(server.events.size(), events_before,
		"blocked incident does not announce a fake wave")
	t.near(server.next_incident_at, 1000.0 + WorldIncidents.RETRY_SECONDS, 0.001,
		"saturated events retry later instead of spinning each server tick")
