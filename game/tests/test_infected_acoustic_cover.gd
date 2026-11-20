extends RefCounted
## Unreal-style sound propagation is authoritative, geometry-aware and
## preserves threat/scent/sight channels. No audio-node or client RPC needed.
const Hearing = preload("res://scripts/shared/infected_hearing.gd")
const Wind = preload("res://scripts/shared/wind_hearing.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const CoverTest = preload("res://tests/test_ranged_cover.gd")


class TestWorld:
	extends RefCounted
	var solids: Array = []
	var queried: int = 0

	func blockers_near(_x: float, _z: float, _radius: float) -> Array:
		queried += 1
		return solids

	func height_at(_x: float, _z: float) -> float:
		return WorldGen.HUB_HEIGHT


func _at(world, xy: Vector2) -> Vector3:
	return Vector3(xy.x, world.height_at(xy.x, xy.y), xy.y)


func _actors(position: Vector3, noise: float, scent: float = 0.0,
		alive: bool = true, safe: bool = false) -> Dictionary:
	return {64: {"position": position, "alive": alive, "safe": safe,
		"noise": noise, "scent": scent, "wind": Vector2.ZERO}}


func run(t) -> void:
	t.current = "attenuation and native policy parity"
	t.near(Hearing.attenuation_radius(Defs.SPRINT_NOISE_RADIUS,
		Defs.SPRINT_NOISE_RADIUS, true), 13.02, 0.001,
		"low-frequency footstep propagation is limited by a solid wall")
	t.near(Hearing.attenuation_radius(Defs.GUNSHOT_NOISE_RADIUS,
		Defs.GUNSHOT_NOISE_RADIUS, true), 25.6, 0.001,
		"gunshots retain more low-frequency reach through obstacles")
	t.eq(Hearing.attenuation_radius(21.0, 21.0, false), 21.0,
		"sound in open air keeps the baseline 21m range")
	t.eq(Hearing.attenuation_radius(0.0, 21.0, true), 0.0,
		"silence cannot be amplified by cover")
	t.eq(Hearing.attenuation_radius(NAN, 21.0, true), 0.0,
		"nonfinite sound cannot create perception stimuli")
	t.check(Hearing.attenuation_radius(32.0, 29.0, true) < 29.0,
		"sound cannot escape an infected type's pursuit leash")
	if ClassDB.class_exists("SoundPropagation"):
		var native: Object = ClassDB.instantiate("SoundPropagation")
		if native != null and native.has_method("effective_radius"):
			for source in [1.0, 7.0, 21.0, 25.0, 32.0, 80.0]:
				for base in [3.0, 21.0, 30.0]:
					var expected: float = base * lerpf(
						Hearing.QUIET_TRANSMISSION, Hearing.LOUD_TRANSMISSION,
						clampf((source - Hearing.QUIET_REFERENCE) /
							(Hearing.LOUD_REFERENCE - Hearing.QUIET_REFERENCE),
							0.0, 1.0))
					t.near(float(native.call("effective_radius",
						source, base, true)), expected, 0.0005,
						"native and fallback sound transmission are numerically identical")

	t.current = "physics broadphase runs only for uncertain hearing"
	var world := TestWorld.new()
	var origin := Vector3(0.0, WorldGen.HUB_HEIGHT, 0.0)
	var source := Vector3(18.0, WorldGen.HUB_HEIGHT, 0.0)
	world.solids = [{"x": 9.0, "z": 0.0, "radius": 1.5, "blocks": true}]
	t.check(not Hearing.audible(world, source, origin, 21.0, 21.0),
		"sprint behind wall beyond occluded range is not heard")
	t.eq(world.queried, 1, "one world broadphase lookup per marginal sound")
	t.check(Hearing.audible(world, Vector3(12, origin.y, 0),
		origin, 21.0, 21.0),
		"nearby footsteps remain audible through one wall")
	t.eq(world.queried, 1,
		"near sounds do not perform unnecessary blocker queries")
	t.check(Hearing.audible(world, source, origin, 32.0, 32.0),
		"gunshots travel through the same wall farther than footsteps")
	t.eq(world.queried, 1,
		"strong noises do not require raycasts when already clearly audible")
	t.check(not Hearing.audible(world, Vector3(50.0, origin.y, 0),
		origin, 21.0, 21.0),
		"inaudible distant sounds are rejected without world physics")
	t.eq(world.queried, 1,
		"far sounds do not consume broadphase budget")
	world.solids.clear()
	t.check(Hearing.audible(world, source, origin, 21.0, 21.0),
		"opening a path immediately restores the normal hearing radius")
	world.solids = [{"x": 9.0, "z": 3.0, "radius": 1.0, "blocks": true}]
	t.check(Hearing.audible(world, source, origin, 21.0, 21.0),
		"off-axis obstacles never muffle sound")
	world.solids = [{"x": 9.0, "z": 0.0, "radius": 1.5, "blocks": false}]
	t.check(Hearing.audible(world, source, origin, 21.0, 21.0),
		"nonblocking decorations cannot hide a runner")
	world.solids = [{"x": 9.0, "z": 0.0, "radius": 0.9, "blocks": true}]
	t.check(Hearing.audible(world, source, origin, 21.0, 21.0),
		"small workbench and thin saplings do not behave like full soundproof walls")
	world.solids = [{"x": 9.0, "z": 0.0, "radius": 1.5, "blocks": true}]
	t.check(not Hearing.audible(world, source, origin, 21.0, 21.0),
		"replacing the prop with a substantial barricade blocks marginal hearing")
	t.check(not Hearing.audible(null, source, origin, 21.0, 21.0),
		"invalid world input cannot fabricate a successful hearing event")
	t.check(not Hearing.audible(world, source, origin, NAN, 21.0),
		"invalid acoustic source is never considered audible")

	t.current = "AI sensory channels and locked aggro remain independent"
	world.solids = [{"x": 9.0, "z": 0.0, "radius": 1.5, "blocks": true}]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8520
	var quiet := Zombie.new(700, "walker", origin)
	quiet.think(world, _actors(source, Defs.SPRINT_NOISE_RADIUS), 0.05, rng)
	t.eq(quiet.target_id, -1, "18m masked sprint does not trigger first aggro")
	var heard := Zombie.new(701, "walker", origin)
	heard.think(world, _actors(source, Defs.GUNSHOT_NOISE_RADIUS), 0.05, rng)
	t.eq(heard.target_id, 64, "loud shot remains effective at 18m behind wall")
	var smell := Zombie.new(702, "walker", origin)
	smell.think(world, _actors(source, 0.0, 20.0), 0.05, rng)
	t.eq(smell.target_id, 64, "blood scent is not filtered by acoustics")
	var target_locked := Zombie.new(703, "walker", origin)
	target_locked.threat[64] = 30.0
	target_locked.think(world, _actors(source, 0.0), 0.05, rng)
	t.eq(target_locked.target_id, 64,
		"confirmed combat damage always outranks muffled footstep discovery")
	var safe := Zombie.new(704, "walker", origin)
	safe.think(world, _actors(source, 32.0, 0.0, true, true), 0.05, rng)
	t.eq(safe.target_id, -1, "server safe zones are immune to sound leaks")
	var dead := Zombie.new(705, "walker", origin)
	dead.think(world, _actors(source, 32.0, 0.0, false, false), 0.05, rng)
	t.eq(dead.target_id, -1, "dead survivors cannot be heard by AI")

	t.current = "real destructible barricade changes authoritative AI hearing"
	var real_world := WorldGen.new(713)
	var lane: Vector2 = CoverTest.new()._open_lane(real_world)
	t.check(lane.is_finite(), "an open real-world danger-zone lane exists")
	if not lane.is_finite():
		return
	var server := GameServer.new(real_world, 713)
	var player = server.add_player(64, "Acoustic Scout")
	player.position = _at(real_world, lane + Vector2(18.0, 0.0))
	player.noise_radius = Defs.SPRINT_NOISE_RADIUS
	player.noise_timer = Defs.SPRINT_NOISE_SECONDS
	var hunter := Zombie.new(server.new_id(), "walker", _at(real_world, lane))
	server.zombies[hunter.id] = hunter
	var wall_id := 931541
	real_world.add_dynamic_blocker(wall_id, lane.x + 9.0, lane.y, 1.5)
	server.tick_count = 2
	server._tick_zombies(0.05)
	t.eq(hunter.target_id, -1,
		"server muffles real sprint footsteps behind constructed world barricade")
	real_world.remove_dynamic_blocker(wall_id)
	hunter.think_timer = 0.0
	server._tick_zombies(0.05)
	t.eq(hunter.target_id, player.id,
		"destroying the same barricade restores AI hearing without client input")
	t.check(not server.snapshot_for(player.id)["you"].has("hearing"),
		"server-private sensing results are never trusted to or exposed by a client")
