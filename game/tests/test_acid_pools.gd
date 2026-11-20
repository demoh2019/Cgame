extends RefCounted
## Lingering acid is visible, bounded, anti-stacking and dodgeable. Server
## timers must not mint extra PvP rewards or apply delayed damage in a hub.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Server = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Acid = preload("res://scripts/shared/acid_spitter.gd")
const Defs = preload("res://scripts/shared/defs.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func _dry_red(world) -> Vector2:
	for x in range(730, 990, 12):
		for z in range(-95, 96, 12):
			if world.zone_at(float(x), float(z)) >= Acid.MIN_ZONE 					and not world.is_water(float(x), float(z)) 					and not world.is_safe(float(x), float(z)):
				return Vector2(x, z)
	return Vector2.INF


func run(t) -> void:
	t.current = "hazard construction bounds"
	t.eq(Acid.make_pool(0, Vector2.ZERO, 0.0, 1.0, 2), {},
		"invalid entity ID cannot create hazard")
	t.eq(Acid.make_pool(1, Vector2.INF, 0.0, 1.0, 2), {},
		"nonfinite center cannot spawn a pool")
	t.eq(Acid.make_pool(1, Vector2.ZERO, 0.0, 1.0, -2), {},
		"invalid creature source cannot spawn hazard")
	t.near(Acid.pool_remaining({}, 0.0), 0.0, 0.001,
		"missing pools never last forever")
	var sample: Dictionary = Acid.make_pool(9, Vector2(11, 12), 2.0, 10.0, 5)
	t.near(Acid.pool_remaining(sample, 10.0), Acid.POOL_SECONDS, 0.001,
		"pool has finite five-second duration")
	t.near(Acid.pool_remaining(sample, 16.0), 0.0, 0.001,
		"pool expires after its deadline")

	t.current = "single shared pool and client visibility"
	var world := WorldGen.new(44)
	var spot: Vector2 = _dry_red(world)
	t.check(spot.is_finite(), "finds an exposed dry red-zone location")
	if not spot.is_finite():
		return
	var sim := Server.new(world, 44)
	var victim = sim.add_player(61, "Survivor")
	var evader = sim.add_player(62, "Dodger")
	var far = sim.add_player(63, "FarAway")
	victim.position = _at(world, spot.x, spot.y)
	evader.position = _at(world, spot.x + 1.0, spot.y)
	far.position = _at(world, 0, 0)
	var zombie = Zombie.new(sim.new_id(), "spitter", _at(world, spot.x + 7.0, spot.y), -1)
	sim.zombies[zombie.id] = zombie
	evader.dodge_immunity = 10.0
	sim._resolve_spit_impact(zombie, spot)
	t.eq(sim.acid_pools.size(), 1, "confirmed spit creates one bounded pool")
	t.near(victim.survival.health, Defs.MAX_HEALTH - 14.0, 0.001,
		"initial direct attack retains its existing damage")
	t.near(evader.survival.health, Defs.MAX_HEALTH, 0.001,
		"the telegraphed splash remains dodgeable")
	t.eq(sim.snapshot_for(61)["acid_pools"].size(), 1,
		"nearby survivor sees the ground hazard")
	t.eq(sim.snapshot_for(63)["acid_pools"].size(), 0,
		"distant clients do not learn hazard coordinates")
	var public: Dictionary = sim.snapshot_for(61)["acid_pools"][0]
	t.check(not public.has("source") and not public.has("next_tick"),
		"private AI source and scheduling never leave server")
	t.eq(public["id"], int(sim.acid_pools.keys()[0]),
		"public hazard ID is stable")

	t.current = "once-per-second puddle and global overlap limit"
	var first: float = victim.survival.health
	sim._tick_acid_pools()
	t.near(victim.survival.health, first, 0.001,
		"pool cannot damage immediately after the direct splash")
	sim.time += Acid.POOL_TICK_SECONDS
	sim._tick_acid_pools()
	t.near(victim.survival.health, first - Acid.POOL_DAMAGE, 0.001,
		"first lingering tick causes armor-checked direct damage")
	t.near(evader.survival.health, Defs.MAX_HEALTH, 0.001,
		"dodge immunity also blocks lingering damage")
	var after: float = victim.survival.health
	sim._tick_acid_pools()
	t.near(victim.survival.health, after, 0.001,
		"repeated simulation call at same time cannot double hit")
	var second_id: int = sim.new_id()
	var second: Dictionary = Acid.make_pool(second_id, spot,
		world.height_at(spot.x, spot.y), sim.time - 1.0, zombie.id)
	sim.acid_pools[second_id] = second
	sim._tick_acid_pools()
	t.near(victim.survival.health, after, 0.001,
		"two overlapping pools cannot stack damage within one second")
	victim.position = _at(world, spot.x + Acid.RADIUS + 4.0, spot.y)
	sim.time += Acid.POOL_TICK_SECONDS
	sim._tick_acid_pools()
	t.near(victim.survival.health, after, 0.001,
		"stepping out of the pool stops periodic damage")
	victim.position = _at(world, spot.x, spot.y)
	sim.time += Acid.POOL_SECONDS + 0.01
	sim._tick_acid_pools()
	t.eq(sim.acid_pools.size(), 0, "expired pools are removed")
	t.near(victim.survival.health, after, 0.001,
		"expiry cannot apply catch-up damage")

	t.current = "protected hub and safe cleanup"
	var hub = sim.add_player(64, "HubResident")
	hub.position = _at(world, 5, 0)
	var hub_hp: float = hub.survival.health
	sim._resolve_spit_impact(zombie, Vector2(5, 0))
	t.eq(sim.acid_pools.size(), 0, "protected hub cannot collect acid pools")
	t.near(hub.survival.health, hub_hp, 0.001,
		"safe settlement is immune to lingering acid")
	var another = Acid.make_pool(sim.new_id(), spot,
		world.height_at(spot.x, spot.y), sim.time, zombie.id)
	sim.acid_pools[int(another["id"])] = another
	sim.remove_player(61)
	t.check(not sim._acid_last_hit.has(61),
		"disconnection cleans peer-scoped acid hit cooldown")
