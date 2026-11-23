extends RefCounted
## Server ORCA crowd correction (CgameCrowdAvoidance) for infected chasing players.
## Native-only and flag-gated; deterministic (id order); never touches attack/leap/flank logic.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const ScriptORCA = preload("res://scripts/shared/crowd_avoidance.gd")


func _pack(server, world, ids: Array, target_id: int) -> Array:
	var out: Array = []
	for index in ids.size():
		var x: float = 200.0 + float(index % 3) * 0.6
		var z: float = 210.0 + floorf(float(index) / 3.0) * 0.6
		var infected := Zombie.new(int(ids[index]), "walker", Vector3(x, world.height_at(x, z), z))
		infected.state = Zombie.State.CHASE
		infected.target_id = target_id
		infected.think_timer = 100.0
		server.zombies[infected.id] = infected
		out.append(infected)
	return out


func _corrections(server, ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		out.append(server.zombies[id].get_chase_crowd_correction())
	return out


func run(t) -> void:
	var native: bool = ClassDB.class_exists("CgameCrowdAvoidance")

	t.current = "zombie applies the correction only to the flank-pursuit step"
	var world := WorldGen.new(113)
	var ground: float = world.height_at(0.0, 0.0)
	var chaser := Zombie.new(9001, "walker", Vector3(0.0, ground, 0.0))
	chaser.state = Zombie.State.CHASE
	chaser.set_chase_crowd_correction(Vector2(-10.0, 0.0))
	t.near(chaser.get_chase_crowd_correction().length(), Zombie.CHASE_CROWD_CORRECTION_MAX, 0.0001, "correction is bounded")
	chaser._move_toward(world, Vector2.ZERO, Vector2(0.0, 10.0), 1.0, 0.033)
	t.near(chaser.yaw, 0.0, 0.0001, "outside the pursuit step (attack approach) the correction is ignored")
	chaser._chase_avoidance_active = true
	chaser._move_toward(world, Vector2.ZERO, Vector2(0.0, 10.0), 1.0, 0.033)
	chaser._chase_avoidance_active = false
	t.check(chaser.yaw < 0.0, "pursuit step bends toward the ORCA velocity")
	var wanderer := Zombie.new(9002, "walker", Vector3(0.0, ground, 0.0))
	wanderer.state = Zombie.State.WANDER
	wanderer.set_chase_crowd_correction(Vector2(-0.7, 0.0))
	wanderer._chase_avoidance_active = true
	wanderer._move_toward(world, Vector2.ZERO, Vector2(0.0, 10.0), 1.0, 0.033)
	t.near(wanderer.yaw, 0.0, 0.0001, "passive states never use the chase correction")
	chaser.set_chase_crowd_correction(Vector2.INF)
	t.eq(chaser.get_chase_crowd_correction(), Vector2.ZERO, "non-finite corrections are rejected")

	t.current = "server flag defaults"
	var server := GameServer.new(WorldGen.new(113), 113)
	t.eq(server.crowd_avoidance_enabled, native, "crowd_avoidance_enabled defaults to native availability")

	t.current = "server ORCA pass"
	var sworld = server.world
	var player = server.add_player(4100, "Bait")
	player.position = Vector3(200.0, sworld.height_at(200.0, 200.0), 200.0)
	var ids: Array = [70005, 70001, 70004, 70002, 70003, 70006]
	var pack: Array = _pack(server, sworld, ids, 4100)
	var far := Zombie.new(70099, "walker", Vector3(600.0, sworld.height_at(600.0, 600.0), 600.0))
	far.state = Zombie.State.CHASE
	far.target_id = 4100
	server.zombies[far.id] = far
	var info: Dictionary = {4100: {"position": player.position, "alive": true}}
	server.crowd_avoidance_enabled = true
	server._refresh_chase_crowd_avoidance(server.zombies.values(), info)
	var stats: Dictionary = server.get_chase_avoidance_stats()
	t.eq(bool(stats["enabled"]), native, "runs only with the native class")
	if native:
		t.eq(int(stats["agents"]), pack.size(), "far infected are not ORCA agents")
		t.eq(int(stats["chasers"]), pack.size(), "every out-of-reach chaser takes part")
		t.check(int(stats.get("corrected", 0)) > 0, "overlapping chasers receive corrections")
		var bounded := true
		for infected in pack:
			bounded = bounded and infected.get_chase_crowd_correction().length() <= Zombie.CHASE_CROWD_CORRECTION_MAX + 0.0001
		t.check(bounded, "corrections stay bounded")
		t.eq(far.get_chase_crowd_correction(), Vector2.ZERO, "far chaser untouched")
		# Determinism: a server holding the same agents in another dictionary order computes identical results.
		var first: Array = _corrections(server, ids)
		var mirror := GameServer.new(WorldGen.new(113), 113)
		var mirror_player = mirror.add_player(4100, "Bait")
		mirror_player.position = player.position
		var reversed_ids: Array = ids.duplicate()
		reversed_ids.reverse()
		var mirror_pack: Array = _pack(mirror, mirror.world, ids, 4100)
		var shuffled: Array = []
		for id in reversed_ids:
			for infected in mirror_pack:
				if infected.id == id:
					shuffled.append(infected)
		mirror.crowd_avoidance_enabled = true
		mirror._refresh_chase_crowd_avoidance(shuffled, info)
		t.eq(_corrections(mirror, ids), first, "results do not depend on cohort order")
	server.crowd_avoidance_enabled = false
	server._refresh_chase_crowd_avoidance(server.zombies.values(), info)
	var cleared := true
	for infected in pack:
		cleared = cleared and infected.get_chase_crowd_correction() == Vector2.ZERO
	t.check(cleared, "turning the flag off clears every correction")
	t.check(not bool(server.get_chase_avoidance_stats()["enabled"]), "stats report disabled")

	t.current = "real tick smoke"
	server.crowd_avoidance_enabled = native
	server.tick_count = 2
	for infected in pack:
		infected.think_timer = 0.0
	server._tick_zombies(1.0 / 20.0)
	var finite := true
	for infected in pack:
		finite = finite and infected.position.is_finite()
	t.check(finite, "a full zombie tick with avoidance keeps positions finite")

	t.current = "script crowd avoidance survives malformed and sparse agents"
	var sites := PackedVector2Array([Vector2.ZERO, Vector2(0.6, 0.0)])
	var actual := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	var desired := PackedVector2Array([Vector2(3.0, 0.0), Vector2(-3.0, 0.0)])
	var plain: PackedVector2Array = ScriptORCA.compute_velocities(
		sites, actual, desired, 0.4, 2.0, 2.0, 3.0, 0)
	t.eq(plain, PackedVector2Array([Vector2(2.0, 0.0), Vector2(-2.0, 0.0)]),
		"zero neighbors returns bounded input without accessing empty indices")
	t.eq(ScriptORCA.compute_velocities(sites, actual, desired,
		0.4, 2.0, 0.0, 3.0, 8), plain,
		"zero horizon uses safe bounded movement rather than dividing by zero")
	t.eq(ScriptORCA.compute_velocities(sites, actual, desired,
		0.4, 2.0, 2.0, 0.0, 8), plain,
		"zero neighbor radius skips collision solver safely")
	var malformed: PackedVector2Array = ScriptORCA.compute_velocities(
		sites, PackedVector2Array([Vector2.ZERO]), desired, 0.4, 2.0, 2.0, 3.0, 8)
	t.eq(malformed, PackedVector2Array([Vector2.ZERO, Vector2.ZERO]),
		"mismatched packed arrays give safe stationary velocities")
	var crowd: PackedVector2Array = ScriptORCA.compute_velocities(
		sites, actual, desired, 0.4, 2.0, 2.0, 3.0, 8)
	t.eq(crowd.size(), sites.size(), "close NPCs still run the ORCA solver")
	for velocity in crowd:
		t.check(velocity.is_finite() and velocity.length() <= 2.0001,
			"collision correction is finite and within max speed")
	var contaminated := PackedVector2Array([Vector2(INF, 0.0), Vector2(1.0, 0.0)])
	var filtered: PackedVector2Array = ScriptORCA.compute_velocities(
		contaminated, actual, desired, 0.4, 2.0, 2.0, 3.0, 8)
	t.eq(filtered[0], Vector2.ZERO, "invalid NPC is excluded from spatial hash")
	t.eq(filtered[1], Vector2(-2.0, 0.0),
		"valid NPC keeps moving when another entity is invalid")
