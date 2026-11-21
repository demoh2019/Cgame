extends RefCounted

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _players(position: Vector3, alive := true, safe := false, noise := 0.0) -> Dictionary:
	return {1: {"position": position, "alive": alive, "safe": safe, "noise": noise}}


func run(t) -> void:
	var world := WorldGen.new(42)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	# A flat spot far from the hub, away from trees: use the hub itself for predictable ground.
	var ground := WorldGen.HUB_HEIGHT

	t.current = "notice and chase"
	var z := Zombie.new(1, "walker", Vector3(0, ground, 0))
	var players := _players(Vector3(10, ground, 0))
	for i in 10:
		z.think(world, players, 0.1, rng)
	t.eq(z.state, Zombie.State.CHASE, "a walker 10 m away notices the player")
	t.eq(z.target_id, 1, "it targets that player")
	var start_x := z.position.x
	for i in 20:
		z.think(world, players, 0.1, rng)
	t.check(z.position.x > start_x + 2.0, "it walks toward the player")
	t.check(z.position.x < start_x + Defs.ZOMBIES["walker"]["speed"] * 2.0 + 0.5, "at walker speed, not faster")

	t.current = "ignores the far"
	z = Zombie.new(2, "walker", Vector3(0, ground, 0))
	players = _players(Vector3(60, ground, 0))
	for i in 20:
		z.think(world, players, 0.1, rng)
	t.check(z.state != Zombie.State.CHASE, "a player 60 m away is not noticed")


	t.current = "Native AI simulation LOD only throttles passive remote target scans"
	var remote_a := Zombie.new(160, "walker", Vector3(0, ground, 0))
	var remote_b := Zombie.new(161, "walker", Vector3(0, ground, 0))
	var remote_same := Zombie.new(160, "walker", Vector3(0, ground, 0))
	var far_survivor := _players(Vector3(100, ground, 0))
	remote_a.think(world, far_survivor, 0.05, rng)
	remote_b.think(world, far_survivor, 0.05, rng)
	remote_same.think(world, far_survivor, 0.05, rng)
	if ClassDB.class_exists("AISimulationLOD2D"):
		t.check(remote_a.think_timer > 0.0 and remote_a.think_timer <= 1.0,
			"passive scan is bounded to a maximum one second")
		t.check(remote_a.think_timer != remote_b.think_timer,
			"consecutive zombie IDs stagger their first distant scan")
		t.near(remote_a.think_timer, remote_same.think_timer, 0.0001,
			"the same zombie ID has deterministic phase regardless of RNG")
		var combined_lod: Variant = Zombie._get_ai_lod_scheduler()
		if combined_lod != null and combined_lod.has_method("plan_passive_scan"):
			var passive_near: float = float(Defs.ZOMBIES["walker"]["lose"])
			var first_plan: Vector2 = combined_lod.plan_passive_scan(
				remote_a.id, 100.0, passive_near, passive_near + 24.0,
				0.0, 4.0, false)
			t.near(remote_a.think_timer, first_plan.y, 0.0001,
				"real infected uses one-call scheduled startup scan delay")
			t.near(remote_a._ai_lod_previous_interval, first_plan.x, 0.0001,
				"real infected remembers nominal tier, not staggered delay")
			t.check(remote_a._ai_lod_staggered,
				"server flags one-shot stagger after first remote scan")
			var next_plan: Vector2 = combined_lod.plan_passive_scan(
				remote_a.id, 100.0, passive_near, passive_near + 24.0,
				remote_a._ai_lod_previous_interval, 4.0, true)
			t.near(next_plan.x, next_plan.y, 0.0001,
				"subsequent remote scans use full LOD period, not startup phase")
			var close_plan: Vector2 = combined_lod.plan_passive_scan(
				remote_a.id, passive_near, passive_near, passive_near + 24.0,
				next_plan.x, 4.0, true)
			t.near(close_plan.y, 0.25, 0.0001,
				"survivor reaching pursuit range immediately restores fast scanning")
			var urgent_plan: Vector2 = combined_lod.plan_passive_scan(
				remote_a.id, 100.0, passive_near, passive_near + 24.0,
				next_plan.x, 4.0, false, true)
			t.near(urgent_plan.y, 0.25, 0.0001,
				"urgent work bypasses even the one-time startup stagger")
		var nearby_idle := Zombie.new(162, "walker", Vector3(0, ground, 0))
		nearby_idle.think(world, _players(Vector3(20, ground, 0)), 0.05, rng)
		t.near(nearby_idle.think_timer, 0.25, 0.0001,
			"nearby survivors keep the original four target scans per second")
		var empty_scan := Zombie.new(163, "walker", Vector3(0, ground, 0))
		empty_scan.think(world, {}, 0.05, rng)
		t.check(empty_scan.think_timer > 0.0 and empty_scan.think_timer <= 1.0,
			"an empty server is time-sliced safely")
		var alert_now := remote_a.receive_pack_alert(6,
			{6: {"position": Vector3(10, ground, 0), "alive": true, "safe": false}})
		t.check(alert_now and remote_a.target_id == 6,
			"authoritative pack alert interrupts passive LOD immediately")
		t.near(remote_a.think_timer, 0.25, 0.0001,
			"alerted infected resumes high-frequency target scanning")
	else:
		t.near(remote_a.think_timer, 0.25, 0.0001,
			"stock Godot preserves original passive target scan cadence")

	t.current = "Passive AI LOD reacquires a survivor within one second"
	var approaching := Zombie.new(167, "walker", Vector3(0, ground, 0))
	approaching.think(world, _players(Vector3(100, ground, 0)), 0.05, rng)
	for i in 25:
		approaching.think(world, _players(Vector3(10, ground, 0)), 0.05, rng)
	t.eq(approaching.target_id, 1,
		"passive time slicing cannot permanently miss a newly nearby survivor")
	t.eq(approaching.state, Zombie.State.CHASE,
		"approaching survivor transitions to ordinary active pursuit")

	t.current = "Aggression interrupts distant passive AI LOD for authoritative threat"
	var hit_remote := Zombie.new(165, "walker", Vector3(0, ground, 0))
	hit_remote.think(world, _players(Vector3(100, ground, 0)), 0.05, rng)
	t.check(not hit_remote.take_damage(1.0, 1),
		"verified nonlethal attack registers server combat threat")
	t.near(hit_remote.think_timer, 0.0, 0.0001,
		"confirmed damage interrupts any previously scheduled passive LOD")
	hit_remote.think(world, _players(Vector3(12, ground, 0)), 0.05, rng)
	t.eq(hit_remote.target_id, 1,
		"attacker is selected on the next authoritative tick")
	var rejected_damage := Zombie.new(166, "walker", Vector3(0, ground, 0))
	rejected_damage.think(world, _players(Vector3(100, ground, 0)), 0.05, rng)
	var previously_scheduled: float = rejected_damage.think_timer
	t.check(not rejected_damage.take_damage(-1.0, 1),
		"invalid negative attack does not register as damage")
	t.near(rejected_damage.think_timer, previously_scheduled, 0.0001,
		"invalid untrusted damage cannot force target recalculation")

	t.current = "noise attracts infected"
	z = Zombie.new(80, "walker", Vector3(0, ground, 0))
	players = _players(Vector3(20, ground, 0))
	for i in 5:
		z.think(world, players, 0.1, rng)
	t.check(z.state != Zombie.State.CHASE, "quiet survivor outside vision is ignored")
	players = _players(Vector3(20, ground, 0), true, false, Defs.SPRINT_NOISE_RADIUS)
	for i in 5:
		z.think(world, players, 0.1, rng)
	t.eq(z.state, Zombie.State.CHASE, "loud sprint makes survivor detectable")
	z = Zombie.new(81, "walker", Vector3(0, ground, 0))
	players = _players(Vector3(30, ground, 0), true, false, Defs.GUNSHOT_NOISE_RADIUS)
	for i in 5:
		z.think(world, players, 0.1, rng)
	t.eq(z.state, Zombie.State.CHASE, "gunshot attracts walker beyond sprint radius")
	z = Zombie.new(82, "walker", Vector3(0, ground, 0))
	players = _players(Vector3(30, ground, 0), true, true, Defs.GUNSHOT_NOISE_RADIUS)
	for i in 5:
		z.think(world, players, 0.1, rng)
	t.check(z.state != Zombie.State.CHASE, "safe hub prevents aggression despite gunshots")

	t.current = "native EQS tactical waypoint cache for large infected groups"
	var flanker := Zombie.new(220, "walker", Vector3.ZERO)
	var prey := Vector2(10.0, 0.0)
	var flank_first: Vector2 = flanker._flank_goal(Vector2.ZERO, prey)
	if ClassDB.class_exists("EnvironmentQuery3D"):
		t.near(flank_first.distance_to(prey), Zombie.FLANK_RING, 0.001,
			"native top-3 flanking keeps a deterministic circle around survivor")
		var owned_query: Resource = flanker._flank_query
		t.check(owned_query != null, "one native query resource is cached per infected")
		if owned_query != null and owned_query.has_method("set_direction_axis"):
			var candidate_side: Vector2 = (flank_first - prey).normalized()
			t.check(candidate_side.dot(prey.normalized()) >= -0.251,
				"directional EQS prevents a near-side-only flank")
			t.check(bool(owned_query.get("use_direction")),
				"flank replanning enables the reusable native directional test")
			if owned_query.has_method("set_max_direction_dot"):
				t.near(float(owned_query.get("max_direction_dot")), 0.75, 0.0001,
					"infected configures the native bounded side-flank sector")
				t.check(candidate_side.dot(Vector2.RIGHT) <= 0.751,
					"infected selects a side instead of the straight far-side slot")
		t.eq(flanker._flank_goal(Vector2(0.4, 0.0), Vector2(10.4, 0.0)),
			flank_first, "small positional changes retain a stable flank point")
		t.check(flanker._flank_query == owned_query,
			"repeated movement does not allocate new native query resources")
		var moved_prey := Vector2(12.0, 0.0)
		t.near(flanker._flank_goal(Vector2.ZERO, moved_prey).distance_to(moved_prey),
			Zombie.FLANK_RING, 0.001, "significant prey movement invalidates cached flank")
		flanker._flank_replan_remaining = 0.0
		t.check(flanker._flank_goal(Vector2.ZERO, moved_prey).is_finite(),
			"expired tactical cache replans to finite point")
		t.check(flanker._flank_query == owned_query,
			"expired cache still reuses the same native query")
	else:
		t.eq(flank_first, prey, "stock Godot directly chases without native EQS")
	t.eq(flanker._flank_goal(Vector2.ZERO, Vector2(2.0, 0.0)),
		Vector2(2.0, 0.0), "close melee pursuit bypasses expensive flank scoring")
	t.eq(flanker._flank_goal(Vector2.ZERO, Vector2(60.0, 0.0)),
		Vector2(60.0, 0.0), "distant pursuit bypasses flank scoring")
	t.current = "runner is faster"
	var runner := Zombie.new(3, "runner", Vector3(0, ground, 0))
	var walker := Zombie.new(4, "walker", Vector3(0, ground, 0))
	players = _players(Vector3(14, ground, 0))
	for i in 20:
		runner.think(world, players, 0.1, rng)
		walker.think(world, players, 0.1, rng)
	t.check(runner.position.x > walker.position.x + 2.0, "a runner outpaces a walker")

	t.current = "attack"
	z = Zombie.new(5, "walker", Vector3(0, ground, 0))
	players = _players(Vector3(1.2, ground, 0))
	var hits := 0
	var damage := 0.0
	var first_hit_time := -1.0
	for i in 80:
		var r := z.think(world, players, 0.05, rng)
		if not r.is_empty():
			hits += 1
			damage += r["damage"]
			if first_hit_time < 0.0:
				first_hit_time = i * 0.05
	t.eq(z.state, Zombie.State.ATTACK, "it attacks when close")
	t.check(hits >= 2 and hits <= 4, "hits are paced by the cooldown (%d hits in 4 s)" % hits)
	t.near(damage / hits, float(Defs.ZOMBIES["walker"]["damage"]), 0.0001, "each hit does the zombie's damage")

	t.current = "safe zone and the dead"
	z = Zombie.new(6, "walker", Vector3(0, ground, 0))
	players = _players(Vector3(2, ground, 0), true, true)
	for i in 30:
		t.check(z.think(world, players, 0.1, rng).is_empty(), "no damage to a player in the safe zone")
	t.check(z.state != Zombie.State.CHASE and z.state != Zombie.State.ATTACK, "a safe player is ignored")
	players = _players(Vector3(2, ground, 0), false, false)
	for i in 30:
		t.check(z.think(world, players, 0.1, rng).is_empty(), "no damage to a dead player")

	t.current = "losing interest"
	z = Zombie.new(7, "walker", Vector3(0, ground, 0))
	players = _players(Vector3(10, ground, 0))
	for i in 5:
		z.think(world, players, 0.1, rng)
	t.eq(z.state, Zombie.State.CHASE, "chasing")
	players = _players(Vector3(300, ground, 0))
	for i in 20:
		z.think(world, players, 0.1, rng)
	t.check(z.state != Zombie.State.CHASE, "it gives up when the player is far away")

	t.current = "investigate last known location after target escapes"
	z = Zombie.new(88, "walker", Vector3(0, ground, 0))
	players = _players(Vector3(10, ground, 0))
	for i in 5:
		z.think(world, players, 0.1, rng)
	var remembered: Vector2 = z.last_known_target
	t.near(remembered.distance_to(Vector2(10, 0)), 0.0, 0.01, "remembers last tracked point")
	players = _players(Vector3(200, ground, 0))
	z.think(world, players, 0.1, rng)
	t.eq(z.state, Zombie.State.INVESTIGATE, "lost target triggers a finite investigation")
	t.eq(z.target_id, -1, "escaping survivor is no longer targeted")
	var investigate_start: float = z.position.x
	for i in 12:
		z.think(world, players, 0.1, rng)
	t.check(z.position.x > investigate_start + 0.4, "search moves toward remembered position")
	for i in 65:
		z.think(world, players, 0.1, rng)
	t.check(z.state != Zombie.State.INVESTIGATE and z.target_id == -1, "search expires instead of lasting forever")
	z = Zombie.new(89, "walker", Vector3(0, ground, 0))
	t.check(z.receive_pack_alert(3, {3: {"position": Vector3(13, ground, 0), "alive": true, "safe": false}}), "alert recruits idle infected")
	t.eq(z.target_id, 3, "alert passes exact peer ID")
	t.check(not z.receive_pack_alert(4, {4: {"position": Vector3(2, ground, 0), "alive": true, "safe": false}}), "active target is not replaced")
	var safe_alert := Zombie.new(90, "walker", Vector3(0, ground, 0))
	t.check(not safe_alert.receive_pack_alert(4, {4: {"position": Vector3(2, ground, 0), "alive": true, "safe": true}}), "pack alarm cannot break safe-zone protection")
	t.check(not safe_alert.receive_pack_alert(5, {5: {"position": Vector3(50, ground, 0), "alive": true, "safe": false}}), "pack alert is bounded by leash")

	t.current = "damage and death"
	z = Zombie.new(8, "walker", Vector3(0, ground, 0))
	t.check(not z.take_damage(10.0), "a small hit does not kill")
	t.eq(z.state, Zombie.State.CHASE, "a hit makes it hostile")
	t.near(z.health, 35.0, 0.0001, "health goes down")
	t.check(z.take_damage(100.0), "a big hit kills")
	t.check(not z.is_alive(), "dead")
	t.check(not z.take_damage(5.0), "the dead cannot die twice")
	t.check(z.think(world, _players(Vector3(1, ground, 0)), 0.1, rng).is_empty(), "the dead do not think")

	t.current = "types"
	for type in Defs.ZOMBIES:
		var zombie := Zombie.new(9, type, Vector3(0, ground, 0))
		t.near(zombie.health, float(Defs.ZOMBIES[type]["health"]), 0.0001, "%s health" % type)
	t.check(float(Defs.ZOMBIES["brute"]["health"]) > float(Defs.ZOMBIES["walker"]["health"]) * 3.0, "brutes are tough")
