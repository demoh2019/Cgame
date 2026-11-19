extends RefCounted
## Projection, clipping and local/online live-position binding.

const Radar = preload("res://scripts/client/survival_radar.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "north-up radar projection"
	var px: Vector2 = Radar.map_point(Vector2.ZERO, Vector2(36, -36), Vector2(200, 200))
	t.near(px.x, 144.0, 0.001, "east is right on the map")
	t.near(px.y, 56.0, 0.001, "north (-Z) is up on the map")
	t.check(Radar.in_range(Vector2.ZERO, Vector2(72, 0)), "radius edge is included")
	t.check(not Radar.in_range(Vector2.ZERO, Vector2(72.5, 0)), "outside radius is excluded")
	t.check(not Radar.in_range(Vector2.ZERO, Vector2(INF, 0)), "invalid coordinates are excluded")
	t.eq(Radar.map_point(Vector2.ZERO, Vector2.ONE, Vector2(200, 200), 0),
		Vector2(100, 100), "invalid radius safely centers projection")

	t.current = "same simulation data powers radar"
	var world := WorldGen.new(217)
	var sim := GameServer.new(world, 217)
	var player = sim.add_player(301, "Explorer")
	var radar := Radar.new()
	radar.world = world
	radar.sim = sim
	radar.actor_id = 301
	t.eq(radar.current_position(), Vector2(player.position.x, player.position.z),
		"radar reads authoritative initial position")
	player.position = Vector3(80, world.height_at(80, -30), -30)
	t.eq(radar.current_position(), Vector2(80, -30),
		"live movement updates radar position without duplicated state")
	player.yaw = PI * 0.5
	t.near(radar.current_yaw(), PI * 0.5, 0.0001,
		"heading uses authoritative player orientation")
	radar.actor_id = 9999
	t.check(not radar.current_position().is_finite(),
		"unknown spectator has no invented player position")
