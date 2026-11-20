extends RefCounted
## New ranged infected: deterministic red/black spawns, 1.4s fixed
## telegraph, dodge/armor/infection, no instant or duplicate damage.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Server = preload("res://scripts/server/game_server.gd")
const Spitter = preload("res://scripts/shared/acid_spitter.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "dangerous-zone spawn and anatomy"
	t.check(Defs.ZOMBIES.has("spitter"), "new spitter registered in shared creature data")
	t.eq(Spitter.spawn_chance(0), 0.0, "no spitter in green zones")
	t.eq(Spitter.spawn_chance(1), 0.0, "no spitter in yellow zones")
	t.check(Spitter.spawn_chance(3) > Spitter.spawn_chance(2),
		"black zones are more likely to generate spitters")
	var seen_red := false
	for seed in 2000:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var kind: String = WorldGen._pick_zombie(2, rng)
		if kind == "spitter":
			seen_red = true
	t.check(seen_red, "red-zone generation actually includes spitters")
	var low_zone := RandomNumberGenerator.new()
	low_zone.seed = 33
	for i in 300:
		t.check(WorldGen._pick_zombie(0, low_zone) != "spitter",
			"protected zones never choose ranged acid infected")
	t.check(not Spitter.hits(Vector2.INF, Vector3.ZERO),
		"invalid impact coordinates cannot hit anyone")
	t.check(Spitter.hits(Vector2.ZERO, Vector3(2.0, 10.0, 0.0)),
		"impact circle uses horizontal distance only")
	t.check(not Spitter.hits(Vector2.ZERO, Vector3(5, 0, 0)),
		"survivors outside radius are safe")

	t.current = "frozen target location and one-shot countdown"
	var world := WorldGen.new(42)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var enemy = Zombie.new(99, "spitter", _at(world, 806, 0))
	var actors := {11: {"position": _at(world, 800, 0), "alive": true, "safe": false}}
	enemy.target_id = 11
	enemy.state = Zombie.State.CHASE
	enemy.think_timer = 1.0
	var warning: Dictionary = enemy.think(world, actors, 0.05, rng)
	t.check(warning.has("spit_warning"), "first ranged attack warns instead of damaging")
	t.check(not warning.has("hit") and enemy.spit_pending,
		"warning has no immediate target hit")
	t.near(enemy.spit_center.x, 800.0, 0.001, "landing position fixed on start")
	actors[11]["position"] = _at(world, 830, 0)
	t.eq(enemy.think(world, actors, 0.4, rng), {}, "pending spit needs its full windup")
	var outcome: Dictionary = enemy.think(world, actors, 1.05, rng)
	t.check(outcome.has("spit_impact"), "windup produces one resolved impact")
	t.near(float(outcome.get("x", -1)), 800.0, 0.001, "projectile does not home toward moving target")
	t.check(not enemy.spit_pending, "completed cast is cleared")
	t.eq(enemy.think(world, actors, 0.05, rng), {}, "completed cast cannot hit twice")
	var dying = Zombie.new(100, "spitter", _at(world, 806, 0))
	dying.spit_pending = true
	dying.spit_seconds = 0.1
	dying.take_damage(1000.0)
	t.check(not dying.spit_pending, "dead spitter cancels pending projectile")

	t.current = "server damage, area bounds and dodge"
	var sim := Server.new(world, 48)
	var target = sim.add_player(11, "Target")
	var dodge = sim.add_player(12, "Dodger")
	var outside = sim.add_player(13, "Outside")
	target.position = _at(world, 800, 0)
	dodge.position = _at(world, 801.5, 0)
	outside.position = _at(world, 809, 0)
	dodge.dodge_immunity = 2.0
	enemy = Zombie.new(sim.new_id(), "spitter", _at(world, 806, 0), -1)
	enemy.target_id = 11
	enemy.state = Zombie.State.CHASE
	enemy.think_timer = 1.0
	sim.zombies[enemy.id] = enemy
	sim._tick_zombies(0.05)
	t.check(enemy.spit_pending, "dedicated server starts telegraph")
	t.near(target.survival.health, Defs.MAX_HEALTH, 0.001, "warning is harmless")
	var before: Dictionary = sim.snapshot_for(11)
	t.eq(before["spit_zones"].size(), 1, "target receives a visible ground warning")
	t.eq(sim.snapshot_for(13)["spit_zones"].size(), 1,
		"nearby onlookers may see warning even when outside blast")
	t.check(not before["spit_zones"][0].has("target_id"),
		"client receives no private AI attack target")
	sim._tick_zombies(Spitter.WINDUP_SECONDS + 0.01)
	t.near(target.survival.health, Defs.MAX_HEALTH - 14.0, 0.001,
		"server applies damage after warning and armor")
	t.check(target.survival.infection > 0.0, "acid impact creates a real infected wound")
	t.near(dodge.survival.health, Defs.MAX_HEALTH, 0.001,
		"dodge immunity protects from corrosive attack")
	t.near(outside.survival.health, Defs.MAX_HEALTH, 0.001,
		"players outside the telegraphed radius take no damage")
	t.eq(sim.snapshot_for(11)["spit_zones"].size(), 0,
		"completed AoE does not remain in network snapshots")
	var health_after: float = target.survival.health
	sim._tick_zombies(0.05)
	t.near(target.survival.health, health_after, 0.001,
		"finished AoE does not apply again on repeated ticks")

	t.current = "safe zone and expired enemies"
	var in_hub = sim.add_player(14, "Hub")
	in_hub.position = _at(world, 10, 0)
	var hub_hp: float = in_hub.survival.health
	sim._resolve_spit_impact(enemy, Vector2(10, 0))
	t.near(in_hub.survival.health, hub_hp, 0.001,
		"safe-hub survivors cannot be attacked by an acid zone")
	enemy.take_damage(1000.0)
	sim._resolve_spit_impact(enemy, Vector2(800, 0))
	t.near(target.survival.health, health_after, 0.001,
		"dead zombie cannot inflict a delayed hit")
