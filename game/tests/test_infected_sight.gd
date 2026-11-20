extends RefCounted
## Visual first-contact uses the same world solids as ranged combat; noise and
## blood scent remain valid, while safe/dead players never become targets.

const Defs = preload("res://scripts/shared/defs.gd")
const Sight = preload("res://scripts/shared/infected_sight.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const CoverTest = preload("res://tests/test_ranged_cover.gd")


class TestWorld:
	extends RefCounted
	var solids: Array = []

	func blockers_near(_x: float, _z: float, _radius: float) -> Array:
		return solids

	func height_at(_x: float, _z: float) -> float:
		return WorldGen.HUB_HEIGHT


func _actors(pos: Vector3, noise: float = 0.0, scent: float = 0.0,
		firelight: float = 0.0, alive: bool = true, safe: bool = false) -> Dictionary:
	return {92: {"position": pos, "alive": alive, "safe": safe, "noise": noise,
		"scent": scent, "firelight": firelight}}


func _at(world, place: Vector2) -> Vector3:
	return Vector3(place.x, world.height_at(place.x, place.y), place.y)


func run(t) -> void:
	t.current = "line-of-sight geometry blocks only visual first contact"
	var world := TestWorld.new()
	var ground: float = WorldGen.HUB_HEIGHT
	var origin := Vector3(0.0, ground, 0.0)
	var survivor := Vector3(12.0, ground, 0.0)
	t.check(Sight.clear_path(world, origin, survivor), "open ground permits sight")
	world.solids = [{"x": 6.0, "z": 0.0, "radius": 1.4, "blocks": true}]
	t.check(not Sight.clear_path(world, origin, survivor),
		"solid wall obstructs the first sight ray")
	world.solids = [{"x": 6.0, "z": 3.0, "radius": 1.4, "blocks": true}]
	t.check(Sight.clear_path(world, origin, survivor), "off-axis trees do not obscure sight")
	world.solids = [{"x": 6.0, "z": 0.0, "radius": 1.4, "blocks": false}]
	t.check(Sight.clear_path(world, origin, survivor), "nonblocking props give no concealment")
	t.check(not Sight.clear_path(world, Vector3.INF, survivor),
		"invalid positions cannot bypass ray checks")
	t.check(not Sight.clear_path(world, origin, Vector3(NAN, 0.0, 0.0)),
		"invalid survivor position is never visible")
	t.check(Sight.clear_path(world, origin, origin), "close contact needs no ray query")

	t.current = "AI: quiet hidden survivor, audible survivor and bleeding survivor"
	world.solids = [{"x": 6.0, "z": 0.0, "radius": 1.4, "blocks": true}]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1942
	var quiet := Zombie.new(901, "walker", origin)
	quiet.think(world, _actors(survivor), 0.05, rng)
	t.eq(quiet.target_id, -1, "quiet survivor behind cover is not visually acquired")
	t.check(quiet.state != Zombie.State.CHASE, "covered survivor does not start a chase")
	var noisy := Zombie.new(902, "walker", origin)
	noisy.think(world, _actors(survivor, Defs.SPRINT_NOISE_RADIUS), 0.05, rng)
	t.eq(noisy.target_id, 92, "sprint footsteps are heard through a wall")
	var bleeding := Zombie.new(903, "walker", origin)
	bleeding.think(world, _actors(survivor, 0.0, 18.0), 0.05, rng)
	t.eq(bleeding.target_id, 92, "blood scent remains independent of cover")
	var lit := Zombie.new(904, "walker", origin)
	lit.think(world, _actors(survivor, 0.0, 0.0, 28.0), 0.05, rng)
	t.eq(lit.target_id, -1, "campfire and flare light do not penetrate solid walls")
	var protected := Zombie.new(905, "walker", origin)
	protected.think(world, _actors(survivor, Defs.GUNSHOT_NOISE_RADIUS,
		0.0, 0.0, true, true), 0.05, rng)
	t.eq(protected.target_id, -1, "safe-zone immunity survives noise and cover")
	var corpse := Zombie.new(906, "walker", origin)
	corpse.think(world, _actors(survivor, Defs.GUNSHOT_NOISE_RADIUS,
		0.0, 0.0, false, false), 0.05, rng)
	t.eq(corpse.target_id, -1, "dead survivors never draw aggro")
	t.check(quiet.receive_pack_alert(92, _actors(survivor)),
		"a trusted pack scout can still alert a nearby covered infected")
	t.eq(quiet.target_id, 92, "received pack aggro is not cancelled by visibility")

	t.current = "active attackers keep target when cover is erected"
	world.solids.clear()
	var hunter := Zombie.new(907, "walker", origin)
	hunter.think(world, _actors(survivor), 0.05, rng)
	t.eq(hunter.target_id, 92, "initial direct line of sight acquires a target")
	world.solids = [{"x": 6.0, "z": 0.0, "radius": 1.4, "blocks": true}]
	hunter.think_timer = 0.0
	hunter.think(world, _actors(survivor), 0.05, rng)
	t.eq(hunter.target_id, 92, "existing aggro survives moving behind cover")
	var retaliating := Zombie.new(908, "walker", origin)
	retaliating.take_damage(5.0, 92)
	retaliating.think(world, _actors(survivor), 0.05, rng)
	t.eq(retaliating.target_id, 92, "confirmed attacks provoke response through a wall")

	t.current = "live server uses destructible dynamic barricades"
	var live_world := WorldGen.new(713)
	var lane: Vector2 = CoverTest.new()._open_lane(live_world)
	t.check(lane.is_finite(), "a clear red-zone sight lane exists")
	if not lane.is_finite():
		return
	var server := GameServer.new(live_world, 713)
	var player = server.add_player(92, "Covered Scout")
	player.position = _at(live_world, lane + Vector2(12.0, 0.0))
	var guard := Zombie.new(server.new_id(), "walker", _at(live_world, lane))
	server.zombies[guard.id] = guard
	var barrier_id := 991214
	live_world.add_dynamic_blocker(barrier_id, lane.x + 6.0, lane.y, 1.4)
	server._tick_zombies(0.05)
	t.eq(guard.target_id, -1, "real game server honors freshly built barricade")
	live_world.remove_dynamic_blocker(barrier_id)
	guard.think_timer = 0.0
	server._tick_zombies(0.05)
	t.eq(guard.target_id, player.id, "destroying barricade restores visual acquisition")
