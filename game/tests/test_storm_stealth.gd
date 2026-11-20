extends RefCounted
## Storm cover is a visual-only server effect, never an invisibility cheat.

const Weather = preload("res://scripts/shared/weather.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _target(position: Vector3, visibility: float, noise: float = 0.0,
		scent: float = 0.0, firelight: float = 0.0) -> Dictionary:
	return {77: {"position": position, "alive": true, "safe": false,
		"noise": noise, "scent": scent, "firelight": firelight,
		"notice_multiplier": 1.0, "visual_signature": 1.0,
		"weather_sight": visibility}}


func _decide(enemy, world, info: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	for _index in 6:
		enemy.think(world, info, 0.1, rng)


func run(t) -> void:
	t.current = "storm visual factor and anti-forgery bounds"
	t.eq(Weather.sight_multiplier({}), 1.0, "absent weather gives no cover")
	t.eq(Weather.sight_multiplier({"condition": "clear"}), 1.0,
		"clear sky means normal eyesight")
	t.eq(Weather.sight_multiplier({"condition": "storm", "sheltered": false}),
		Weather.STORM_SIGHT_MULTIPLIER, "outdoor storm reduces eyesight 30 percent")
	t.eq(Weather.sight_multiplier({"condition": "storm", "sheltered": true}),
		1.0, "roofed hub receives no storm cover")
	t.eq(Weather.sight_multiplier({"condition": "unknown"}), 1.0,
		"malformed conditions cannot hide players")

	t.current = "only sight impaired, no resetting existing combat"
	var world := WorldGen.new(442)
	var at := Vector3(13.0, WorldGen.HUB_HEIGHT, 0.0)
	var covered: float = Weather.STORM_SIGHT_MULTIPLIER
	var hidden := Zombie.new(701, "walker", Vector3(0.0, WorldGen.HUB_HEIGHT, 0.0))
	_decide(hidden, world, _target(at, covered))
	t.eq(hidden.target_id, -1, "quiet survivor can pass beyond storm visibility")
	var clear := Zombie.new(702, "walker", Vector3(0.0, WorldGen.HUB_HEIGHT, 0.0))
	_decide(clear, world, _target(at, 1.0))
	t.eq(clear.target_id, 77, "walker sees same player in clear weather")
	var noisy := Zombie.new(703, "walker", Vector3(0.0, WorldGen.HUB_HEIGHT, 0.0))
	_decide(noisy, world, _target(at, covered, Defs.SPRINT_NOISE_RADIUS))
	t.eq(noisy.target_id, 77, "sprinting is audible during storms")
	var bleeding := Zombie.new(704, "walker", Vector3(0.0, WorldGen.HUB_HEIGHT, 0.0))
	_decide(bleeding, world, _target(at, covered, 0.0, 20.0))
	t.eq(bleeding.target_id, 77, "blood scent still reveals the survivor")
	var lit := Zombie.new(705, "walker", Vector3(0.0, WorldGen.HUB_HEIGHT, 0.0))
	_decide(lit, world, _target(at, covered, 0.0, 0.0, 20.0))
	t.eq(lit.target_id, 77, "campfire light still reveals survivor")
	var malformed := Zombie.new(706, "walker", Vector3(0.0, WorldGen.HUB_HEIGHT, 0.0))
	_decide(malformed, world, _target(at, NAN))
	t.eq(malformed.target_id, 77, "NaN factor falls back to ordinary sight")
	var extreme := Zombie.new(707, "walker", Vector3(0.0, WorldGen.HUB_HEIGHT, 0.0))
	_decide(extreme, world, _target(at, 0.0))
	t.eq(extreme.target_id, -1, "zero factor is bounded to ordinary storm cover")
	_decide(clear, world, _target(at, covered))
	t.eq(clear.target_id, 77, "storm never cancels an existing chase")

	t.current = "real world weather drives network status and infected AI"
	var actual := WorldGen.new(443)
	var sim := GameServer.new(actual, 443)
	var survivor = sim.add_player(918, "Rain Scout")
	survivor.position = Vector3(300.0, actual.height_at(300.0, 0.0), 0.0)
	var storm_at: float = -1.0
	for phase in 120:
		var time: float = float(phase) * Weather.CHANGE_SECONDS + 1.0
		if Weather.conditions(actual, 300.0, 0.0, time).get("condition") == "storm":
			storm_at = time
			break
	t.check(storm_at >= 0.0, "seeded world provides a storm interval")
	if storm_at < 0.0:
		return
	sim.time = storm_at
	var state: Dictionary = sim.snapshot_for(918)["you"]
	t.eq(float(state.get("weather_sight", 1.0)),
		Weather.sight_multiplier(state["weather"]),
		"HUD receives the server's weather-derived eyesight factor")
	t.eq(float(state["weather_sight"]), Weather.STORM_SIGHT_MULTIPLIER,
		"storm status remains visible in a dangerous zone")
	var walker := Zombie.new(sim.new_id(), "walker",
		Vector3(319.0, actual.height_at(319.0, 0.0), 0.0))
	sim.zombies[walker.id] = walker
	sim.tick_count = 2
	sim._tick_zombies(0.1)
	t.eq(walker.target_id, -1, "quiet server survivor is concealed from 19m")
	survivor.noise_radius = Defs.SPRINT_NOISE_RADIUS
	survivor.noise_timer = Defs.SPRINT_NOISE_SECONDS
	walker.think_timer = 0.0
	sim._tick_zombies(0.1)
	t.eq(walker.target_id, 918, "real sprint noise breaks storm concealment")
