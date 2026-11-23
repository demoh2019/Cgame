extends RefCounted
## Directional sound detection must follow the actual regional weather, but
## never modify combat threat, sight, smell or saved player identity.
const WindHearing = preload("res://scripts/shared/wind_hearing.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _at(world, p: Vector2) -> Vector3:
	return Vector3(p.x, world.height_at(p.x, p.y), p.y)


func _hear(enemy, world, player_position: Vector3, wind: Vector2) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90
	var players: Dictionary = {1: {"position": player_position, "alive": true,
		"safe": false, "noise": Defs.SPRINT_NOISE_RADIUS, "wind": wind}}
	for i in 5:
		enemy.think(world, players, 0.1, rng)
	return enemy.target_id


func run(t) -> void:
	t.current = "wind direction changes only actual hearing distance"
	var source := Vector2.ZERO
	var downwind := Vector2(23.0, 0.0)
	var upwind := Vector2(-23.0, 0.0)
	var crosswind := Vector2(0.0, 23.0)
	var gust := Vector2(1.6, 0.0)
	var sound: float = Defs.SPRINT_NOISE_RADIUS
	t.check(WindHearing.radius(sound, gust, source, downwind, 33.0) > 23.0,
		"loud footsteps travel beyond ordinary sprint hearing downwind")
	t.check(WindHearing.radius(sound, gust, source, upwind, 33.0) < 21.0,
		"same footsteps carry less far against the wind")
	t.near(WindHearing.radius(sound, gust, source, crosswind, 33.0), sound, 0.0001,
		"crosswind does not change original hearing range")
	t.eq(WindHearing.radius(0.0, gust, source, downwind, 33.0), 0.0,
		"wind does not reveal an actually silent survivor")
	t.near(WindHearing.radius(sound, Vector2.ZERO, source, downwind, 33.0),
		sound, 0.0001, "clear calm weather preserves existing hearing")
	t.near(WindHearing.radius(sound, Vector2(NAN, 0.0), source, downwind, 33.0),
		sound, 0.0001, "invalid wind cannot forge a larger detection range")
	t.eq(WindHearing.radius(NAN, gust, source, downwind, 33.0), 0.0,
		"invalid noise never becomes valid hearing")
	t.eq(WindHearing.radius(INF, gust, source, downwind, 33.0), 0.0,
		"nonfinite noise does not become an infinite hearing radius")
	t.check(WindHearing.radius(1000.0, gust * 100.0, source, downwind, 33.0) <= 33.0,
		"extreme gusts and sound remain bounded by each infected leash")

	t.current = "extreme but finite vectors cannot distort infected hearing"
	t.near(WindHearing.radius(sound, Vector2(1.0e30, 0.0),
		source, downwind, 33.0), sound, 0.0001,
		"overflowing squared wind velocity falls back to original sound range")
	t.near(WindHearing.radius(sound, gust, Vector2(-1.0e30, 0.0),
		Vector2(1.0e30, 0.0), 33.0), sound, 0.0001,
		"huge finite actor separation cannot produce a directional hearing bonus")
	t.near(WindHearing.radius(sound, gust, Vector2(-1.0e30, 0.0),
		Vector2(1.0e30, 0.0), sound), sound, 0.0001,
		"numeric edge cases remain limited by the infected's hearing leash")

	t.current = "initial infected aggro uses wind, not an everlasting combat buff"
	var world := WorldGen.new(114)
	var ground := WorldGen.HUB_HEIGHT
	var source_pos := Vector3(0.0, ground, 0.0)
	var down := Zombie.new(10, "walker", Vector3(23.0, ground, 0.0))
	t.eq(_hear(down, world, source_pos, gust), 1,
		"unengaged walker detects sprinting downwind from 23m")
	var up := Zombie.new(11, "walker", Vector3(-23.0, ground, 0.0))
	t.eq(_hear(up, world, source_pos, gust), -1,
		"same walker does not detect same noise upwind from 23m")
	var calm := Zombie.new(12, "walker", Vector3(23.0, ground, 0.0))
	t.eq(_hear(calm, world, source_pos, Vector2.ZERO), -1,
		"without wind baseline 21m sprint noise still applies")
	var seen := Zombie.new(13, "walker", Vector3(10.0, ground, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	seen.think(world, {1: {"position": source_pos, "alive": true,
		"safe": false, "noise": 0.0, "wind": -gust}}, 0.1, rng)
	t.eq(seen.target_id, 1, "upwind noise modifier cannot mask ordinary eyesight")
	var attacker := Zombie.new(14, "walker", Vector3(-23.0, ground, 0.0))
	attacker.threat[1] = 30.0
	t.eq(_hear(attacker, world, source_pos, gust), 1,
		"earned damage threat still overrides directional sound")

	t.current = "real server storm wind flows to infected sense processing"
	var sim_world := WorldGen.new(342)
	var sim := GameServer.new(sim_world, 342)
	var player = sim.add_player(18, "Runner", "wind-runner")
	var site := Vector2(900.0, 910.0)
	player.position = _at(sim_world, site)
	var actual_wind := Vector2.ZERO
	var found := false
	for phase in range(120):
		sim.time = float(phase) * Weather.CHANGE_SECONDS + 1.0
		var conditions: Dictionary = Weather.conditions(sim_world, site.x, site.y, sim.time)
		actual_wind = Weather.wind_at(sim_world, site.x, site.y, sim.time)
		if str(conditions.get("condition", "")) == "storm" and \
			actual_wind.length() > 1.05 and not bool(conditions.get("sheltered", true)):
			found = true
			break
	t.check(found, "seeded world produces exposed directional storm gusts")
	if not found:
		return
	var axis: Vector2 = actual_wind.normalized()
	var down_site: Vector2 = site + axis * 23.0
	var up_site: Vector2 = site - axis * 23.0
	var down_zombie := Zombie.new(sim.new_id(), "walker", _at(sim_world, down_site), -1)
	var up_zombie := Zombie.new(sim.new_id(), "walker", _at(sim_world, up_site), -1)
	sim.zombies[down_zombie.id] = down_zombie
	sim.zombies[up_zombie.id] = up_zombie
	player.noise_radius = Defs.SPRINT_NOISE_RADIUS
	player.noise_timer = Defs.SPRINT_NOISE_SECONDS
	sim.tick_count = 2 # Prevent unrelated population management during this pass.
	sim._tick_zombies(0.1)
	t.eq(down_zombie.target_id, player.id,
		"server-derived wind carries real sprint noise farther downwind")
	t.eq(up_zombie.target_id, -1,
		"actual upwind infected is not alerted by same movement")
	t.check(not sim.snapshot_for(player.id)["you"].has("wind"),
		"server-only hearing vectors are not exposed as trusted player input")
