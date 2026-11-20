extends RefCounted
## Predictable and server-owned crouching, checked against infected detection.
const Defs = preload("res://scripts/shared/defs.gd")
const StealthStance = preload("res://scripts/shared/stealth_stance.gd")
const Camouflage = preload("res://scripts/shared/camouflage.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func run(t) -> void:
	t.current = "crouching shares exactly the movement solver used in prediction"
	var world := WorldGen.new(42)
	var start := Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	var walk := Movement.step(world, start, {"x": 1.0}, 0.1)
	var crouch := Movement.step(world, start, {"x": 1.0, "crouch": true}, 0.1)
	var sprint_crouch := Movement.step(world, start,
		{"x": 1.0, "sprint": true, "crouch": true}, 0.1)
	t.near(crouch.x, walk.x * StealthStance.WALK_MULTIPLIER,
		0.001, "crouching slows actual movement")
	t.near(sprint_crouch.x, crouch.x, 0.001,
		"pressing sprint cannot bypass crouch slow-down")
	t.check(crouch.x > 0.0, "crouching is still walking")
	t.eq(StealthStance.speed_factor(false), 1.0, "ordinary movement unchanged")

	t.current = "visual stealth does not block sound, blood or existing aggro"
	t.near(StealthStance.visual_signature(1.0, true, 0.0), 0.60,
		0.001, "crouching reduces visual signature")
	var cloak: float = Camouflage.visual_signature("ghillie_cloak_2", true, 0.0)
	t.near(StealthStance.visual_signature(cloak, true, 0.0), 0.372,
		0.001, "earned cloak combines with stance")
	t.near(StealthStance.visual_signature(0.48, true, 0.0),
		StealthStance.MIN_VISUAL, 0.001, "minimum sight range stays bounded")
	t.eq(StealthStance.visual_signature(cloak, true, 1.0), 1.0,
		"active noise breaks all visual concealment")
	t.eq(StealthStance.visual_signature(cloak, true, INF), 1.0,
		"invalid noise never creates invisibility")
	t.eq(StealthStance.visual_signature(cloak, true, 0.0, false), 1.0,
		"dead survivor cannot hide")
	var ground: float = WorldGen.HUB_HEIGHT
	var pos := Vector3(13.0, ground, 0.0)
	var hidden := Zombie.new(1101, "walker", Vector3(0.0, ground, 0.0))
	var loud := Zombie.new(1102, "walker", Vector3(0.0, ground, 0.0))
	var normal := Zombie.new(1103, "walker", Vector3(0.0, ground, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	for step in 5:
		hidden.think(world, {10: {"position": pos, "alive": true, "safe": false,
			"noise": 0.0, "scent": 0.0,
			"visual_signature": StealthStance.visual_signature(1.0, true, 0.0)}}, 0.1, rng)
		loud.think(world, {10: {"position": pos, "alive": true, "safe": false,
			"noise": Defs.SPRINT_NOISE_RADIUS, "scent": 0.0,
			"visual_signature": 1.0}}, 0.1, rng)
		normal.think(world, {10: {"position": pos, "alive": true, "safe": false,
			"noise": 0.0, "scent": 0.0, "visual_signature": 1.0}}, 0.1, rng)
	t.eq(hidden.target_id, -1, "distant crouching target escapes vision")
	t.eq(loud.target_id, 10, "audible crouching still attracts infected")
	t.eq(normal.target_id, 10, "unhidden target is noticed")

	t.current = "server authorizes the posture, snapshots, stamina and respawn"
	var sim := GameServer.new(world, 311)
	var scout = sim.add_player(71, "Silent Scout")
	var spectator = sim.add_player(72, "Observer")
	scout.position = start
	spectator.position = start + Vector3(3.0, 0.0, 0.0)
	scout.input_budget = 0.1
	var stamina_before: float = scout.survival.stamina
	sim.submit_input(71, 1, 1.0, 0.0, true, 0.0, 0.1, true)
	t.check(scout.crouching, "server accepted crouch input")
	t.near(scout.position.x, Defs.WALK_SPEED * StealthStance.WALK_MULTIPLIER * 0.1,
		0.001, "server movement shares crouch speed")
	t.near(scout.survival.stamina, stamina_before, 0.001,
		"crouch with sprint key never consumes sprint stamina")
	t.check(bool(sim.snapshot_for(71)["you"]["crouching"]),
		"self snapshot reports authoritative stance")
	var others: Array = sim.snapshot_for(72)["players"]
	t.check(others.size() > 0 and bool(others[0].get("crouching", false)),
		"other players see crouching stance")
	t.near(float(sim.snapshot_for(71)["you"]["visual_signature"]), 0.60,
		0.001, "snapshot contains actual NPC visibility factor")
	sim.submit_input(71, 2, 0.0, 0.0, false, NAN, 0.1, false)
	t.check(scout.crouching, "invalid input cannot change stance")
	scout.input_budget = 0.1
	sim.submit_input(71, 2, 0.0, 0.0, false, 0.0, 0.1, false)
	t.check(not scout.crouching, "releasing crouch returns to standing")
	t.near(float(sim.snapshot_for(71)["you"]["visual_signature"]), 1.0,
		0.001, "standing restores normal visual detection")
	sim.submit_input(71, 2, 0.0, 0.0, false, 0.0, 0.1, true)
	t.check(not scout.crouching, "replayed input cannot change posture")
	scout.input_budget = 0.1
	sim.submit_input(71, 3, 0.0, 0.0, false, 0.0, 0.1, true)
	sim._spawn_player(scout)
	t.check(not scout.crouching, "respawn resets temporary crouch state")
	t.check(not sim.character_data(scout).has("crouching"),
		"crouching does not persist between logins")
