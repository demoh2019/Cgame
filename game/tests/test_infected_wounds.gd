extends RefCounted
## Regression: low-health infected behavior is decided by server health,
## represented in interest snapshots, and isolated from other enemy types.

const InfectedWounds = preload("res://scripts/shared/infected_wounds.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _wounded(id: int, kind: String, ground: float):
	var enemy = Zombie.new(id, kind, Vector3(0, ground, 0))
	enemy.health = float(enemy.data["health"]) * 0.30
	return enemy


func _players(x: float, ground: float) -> Dictionary:
	return {1: {"position": Vector3(x, ground, 0.0),
		"alive": true, "safe": false, "noise": 0.0}}


func run(t) -> void:
	var ground: float = WorldGen.HUB_HEIGHT
	t.current = "low-health gait is bounded by enemy type and effective max health"
	var walker = Zombie.new(101, "walker", Vector3(0, ground, 0))
	t.eq(InfectedWounds.phase(walker), "", "unhurt walker moves normally")
	walker.health = float(walker.data["health"]) * (InfectedWounds.WOUND_THRESHOLD + 0.01)
	t.eq(InfectedWounds.phase(walker), "", "damage above threshold has no effect")
	walker.health = float(walker.data["health"]) * InfectedWounds.WOUND_THRESHOLD
	t.eq(InfectedWounds.phase(walker), "limping", "exact threshold starts limp")
	t.near(InfectedWounds.speed_factor(walker), 0.65, 0.001,
		"regular walkers slow their movement, not their damage")
	t.eq(InfectedWounds.phase(_wounded(102, "spitter", ground)), "limping",
		"wounded spitters walk slowly")
	var runner = _wounded(103, "runner", ground)
	t.eq(InfectedWounds.phase(runner), "frenzied", "runner gets final sprint")
	t.near(InfectedWounds.speed_factor(runner), 1.18, 0.001,
		"runner frenzy never becomes an arbitrary multiplier")
	t.eq(InfectedWounds.phase(_wounded(104, "brute", ground)), "",
		"brutes retain their established behavior")
	runner.become_elite()
	runner.health = float(runner.data["health"]) * 0.30
	t.near(InfectedWounds.speed_factor(runner), 1.09, 0.001,
		"elite runner gains only a capped half-strength sprint")
	var elite_walker = _wounded(105, "walker", ground)
	elite_walker.become_elite()
	elite_walker.health = float(elite_walker.data["health"]) * 0.30
	t.near(InfectedWounds.speed_factor(elite_walker), 0.82, 0.001,
		"elite walker has less severe slow")
	elite_walker.raid_boss = true
	t.eq(InfectedWounds.phase(elite_walker), "",
		"raid boss ignores regular infected wound gait")
	walker.health = NAN
	t.eq(InfectedWounds.phase(walker), "", "nonfinite health cannot trigger buffs")
	walker.health = 0.0
	t.eq(InfectedWounds.phase(walker), "", "zero health cannot grant a sprint")
	t.check(walker.take_damage(5.0), "a normally wounded infected can die")
	t.eq(InfectedWounds.speed_factor(walker), 1.0,
		"dead infected cannot retain an active movement modifier")

	t.current = "actual chase movement uses wound gait but attack power is untouched"
	var world := WorldGen.new(42)
	var rng := RandomNumberGenerator.new()
	rng.seed = 89
	var normal_walker = Zombie.new(200, "walker", Vector3(0, ground, 0))
	var limping_walker = _wounded(201, "walker", ground)
	for i in 20:
		normal_walker.think(world, _players(12.0, ground), 0.1, rng)
		limping_walker.think(world, _players(12.0, ground), 0.1, rng)
	t.check(normal_walker.position.x > limping_walker.position.x + 0.6,
		"wounded walker really moves slower during server simulation")
	t.eq(float(limping_walker.data["damage"]), float(Defs.ZOMBIES["walker"]["damage"]),
		"limping does not reduce attack damage")
	var normal_runner = Zombie.new(202, "runner", Vector3(0, ground, 0))
	var frenzied_runner = _wounded(203, "runner", ground)
	for i in 15:
		normal_runner.think(world, _players(18.0, ground), 0.1, rng)
		frenzied_runner.think(world, _players(18.0, ground), 0.1, rng)
	t.check(frenzied_runner.position.x > normal_runner.position.x + 0.55,
		"wounded runner really catches up faster in combat")
	t.near(float(frenzied_runner.data["attack_cooldown"]),
		float(Defs.ZOMBIES["runner"]["attack_cooldown"]), 0.001,
		"runner frenzy cannot accelerate damage ticks")

	t.current = "authoritative snapshots expose only observable gait state"
	var sim := GameServer.new(world, 312)
	var viewer = sim.add_player(44, "Scout")
	viewer.position = Vector3(0.0, ground, 0.0)
	sim.zombies.clear()
	var target = _wounded(4321, "runner", ground)
	target.position = Vector3(7.0, ground, 0.0)
	sim.zombies[target.id] = target
	var visible: Array = sim.snapshot_for(44)["zombies"]
	t.eq(visible.size(), 1, "a nearby living wounded infected is visible")
	t.eq(str(visible[0].get("wound_phase", "")), "frenzied",
		"client sees the server-derived warning")
	t.check(not visible[0].has("threat") and not visible[0].has("target_id"),
		"warning does not disclose hidden threat or private aggro")
	target.health = float(target.data["health"])
	visible = sim.snapshot_for(44)["zombies"]
	t.eq(str(visible[0].get("wound_phase", "unknown")), "",
		"client warning disappears when health is restored")
	target.take_damage(target.health + 1.0)
	t.eq(sim.snapshot_for(44)["zombies"].size(), 0,
		"dead infected do not linger in visible snapshots")
