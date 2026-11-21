extends RefCounted
## Source-backed Godot regression suite: tick telemetry and adaptive pacing.
const Governor = preload("res://scripts/server/server_tick_governor.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldIncidents = preload("res://scripts/shared/world_incidents.gd")


func run(t) -> void:
	t.current = "tick profiler: finite p95 and bounded defensive history"
	var empty: Array[float] = []
	t.eq(Governor.percentile_nearest_rank(empty, 0.95), 0.0, "empty p95 has no samples")
	var values: Array[float] = [1.0, 2.0, 3.0, 4.0, 10.0]
	t.eq(Governor.percentile_nearest_rank(values, 0.95), 10.0, "p95 nearest rank")
	t.eq(Governor.percentile_nearest_rank(values, 0.5), 3.0, "median nearest rank")
	t.eq(values[0], 1.0, "percentile does not mutate caller order")
	var history := Governor.new()
	for i in Governor.HISTORY_CAP + 2:
		history.observe_tick(i * 1000, 1)
	var snapshot: Dictionary = history.snapshot()
	t.eq(history.history_count(), Governor.HISTORY_CAP, "server sampling is bounded")
	t.eq(snapshot["total_ticks"], Governor.HISTORY_CAP + 2, "lifetime count survives eviction")
	var latest: Array[float] = history.samples_oldest_first()
	t.eq(latest[0], 2.0, "oldest ring sample is evicted")
	t.eq(latest[latest.size() - 1], 201.0, "latest ring sample is retained")
	latest[0] = -999.0
	t.eq(history.samples_oldest_first()[0], 2.0, "history reader returns a defensive copy")
	t.eq(history.snapshot()["tick_max_ms"], 201.0, "peak is measured from retained samples")

	t.current = "no adaptation on invalid/idle samples"
	var idle := Governor.new()
	idle.observe_tick(-1, 1)
	idle.observe_tick(61000000, 1)
	t.eq(idle.snapshot()["total_ticks"], 0, "invalid clock samples are ignored")
	for i in Governor.HISTORY_CAP + 15:
		idle.observe_tick(60000, 0)
	t.eq(idle.spawn_cap, Governor.MAX_SPAWN_CAP, "empty server never throttles")
	t.eq(idle.snapshot()["sample_count"], Governor.HISTORY_CAP,
		"even idle server history stays bounded")

	t.current = "sustained overload and recovery with hysteresis"
	var governor := Governor.new()
	for i in Governor.WINDOW_TICKS * (Governor.HIGH_WINDOWS - 1):
		governor.observe_tick(60000, 1)
	t.eq(governor.spawn_cap, Governor.MAX_SPAWN_CAP,
		"single performance spike window cannot reduce encounters")
	for i in Governor.WINDOW_TICKS:
		governor.observe_tick(60000, 1)
	t.eq(governor.spawn_cap, Governor.MAX_SPAWN_CAP - 2,
		"three sustained slow windows lower only future incident cap")
	for i in Governor.WINDOW_TICKS:
		governor.observe_tick(38000, 1)
	t.eq(governor.spawn_cap, Governor.MAX_SPAWN_CAP - 2,
		"CPU deadband prevents oscillating quality")
	for i in Governor.WINDOW_TICKS * Governor.LOW_WINDOWS:
		governor.observe_tick(10000, 1)
	t.eq(governor.spawn_cap, Governor.MAX_SPAWN_CAP - 1,
		"sustained healthy ticks restore budget gradually")
	for i in Governor.WINDOW_TICKS * Governor.HIGH_WINDOWS * 10:
		governor.observe_tick(60000, 1)
	t.eq(governor.spawn_cap, Governor.MIN_SPAWN_CAP, "minimum retains encounter identity")
	governor.set_enabled(false)
	t.eq(governor.spawn_cap, Governor.MAX_SPAWN_CAP,
		"fixed mode restores vanilla maximum")
	for i in Governor.WINDOW_TICKS * Governor.HIGH_WINDOWS * 3:
		governor.observe_tick(60000, 1)
	t.eq(governor.spawn_cap, Governor.MAX_SPAWN_CAP,
		"disabled governor never changes server game load")
	governor.set_enabled(true)
	t.eq(governor.spawn_cap, Governor.MAX_SPAWN_CAP, "reenabling starts clean")

	t.current = "GameServer applies operator cap to authoritative incidents"
	var world := WorldGen.new(17714)
	var server := GameServer.new(world, 17714)
	var survivor = server.add_player(101, "ProfilerTester")
	survivor.position = Vector3(350.0, world.height_at(350.0, 350.0), 350.0)
	t.check(not world.is_safe(survivor.position.x, survivor.position.z),
		"server integration character outside hub")
	t.eq(server.incident_spawn_cap, Governor.MAX_SPAWN_CAP, "default cap is vanilla")
	server.incident_spawn_cap = 0
	server.time = 1000.0
	server.next_incident_at = 0.0
	server._tick_world_incidents()
	t.eq(server.zombies.size(), 0, "operator hard cap prevents new random enemies")
	t.eq(server.events.size(), 0, "suppressed wave emits no fake incident")
	t.near(server.next_incident_at, 1000.0 + WorldIncidents.RETRY_SECONDS, 0.001,
		"rejected wave retries later instead of checking every tick")
