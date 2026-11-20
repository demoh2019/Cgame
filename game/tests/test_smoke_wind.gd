extends RefCounted
## Wind changes smoke position and infected sight, never client-authorized cues.
const Weather = preload("res://scripts/shared/weather.gd")
const Smoke = preload("res://scripts/shared/field_smoke.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const EvasionTest = preload("res://tests/test_evasion.gd")
const WorldPersistence = preload("res://scripts/server/world_persistence.gd")


class FlatWorld:
	extends RefCounted
	var world_seed: int = 45
	var blocked: bool = false

	func biome_at(_x: float, _z: float) -> String:
		return "forest"

	func is_safe(x: float, z: float) -> bool:
		return blocked or Vector2(x, z).length() < 45.0

	func is_water(_x: float, _z: float) -> bool:
		return blocked

	func height_at(_x: float, _z: float) -> float:
		return 4.0


func _find_weather(world, site: Vector2, target: String) -> float:
	for epoch in range(100):
		var at: float = float(epoch) * Weather.CHANGE_SECONDS + 10.0
		if str(Weather.conditions(world, site.x, site.y, at).get("condition", "")) == target:
			return at
	return -1.0


func run(t) -> void:
	t.current = "seeded wind respects weather cells and hub boundaries"
	var world := FlatWorld.new()
	var spot := Vector2(300.0, 300.0)
	var storm_at: float = _find_weather(world, spot, "storm")
	var clear_at: float = _find_weather(world, spot, "clear")
	t.check(storm_at >= 0.0 and clear_at >= 0.0,
		"seeded forest experiences both clear weather and storms")
	if storm_at < 0.0 or clear_at < 0.0:
		return
	var storm_wind: Vector2 = Weather.wind_at(world, spot.x, spot.y, storm_at)
	var calm_wind: Vector2 = Weather.wind_at(world, spot.x, spot.y, clear_at)
	t.check(storm_wind.length() > calm_wind.length() and storm_wind.length() < 1.5,
		"storm gusts move smoke faster but remain bounded")
	t.eq(Weather.wind_at(world, spot.x, spot.y, storm_at), storm_wind,
		"same seed, place and time produce the same wind")
	t.eq(Weather.wind_at(world, spot.x + 1.0, spot.y + 1.0, storm_at),
		storm_wind, "wind remains coherent across nearby players")
	t.eq(Weather.wind_at(world, 0.0, 0.0, storm_at), Vector2.ZERO,
		"safe hub stays wind-free")
	t.eq(Weather.wind_at(world, INF, 0.0, storm_at), Vector2.ZERO,
		"infinite coordinates never create wind")
	t.eq(Weather.wind_at(world, spot.x, NAN, storm_at), Vector2.ZERO,
		"invalid weather input never produces a drift force")

	t.current = "server-side smoke motion, barriers and visual concealment"
	var cloud := {"id": 51, "x": spot.x, "y": 4.0, "z": spot.y,
		"expires": storm_at + 30.0, "owner": 2}
	var moved: Dictionary = Smoke.drift(cloud, world, storm_at + 1.0, 1.0)
	t.check(Vector2(float(moved["x"]), float(moved["z"])).distance_to(spot) > 1.0,
		"one paid cloud drifts more than one metre in a storm")
	t.eq(cloud["x"], spot.x, "advance never mutates the input cloud")
	t.eq(cloud["z"], spot.y, "advect cannot rewrite another reference")
	t.near(Vector2(float(moved["x"]), float(moved["z"])).distance_to(spot),
		storm_wind.length(), 0.00001, "drift equals seeded wind times server delta")
	t.eq(Smoke.drift(cloud, world, storm_at + 1.0, NAN)["x"], spot.x,
		"nonfinite time step grants no displacement")
	t.eq(Smoke.drift(cloud, world, storm_at + 1.0, -20.0)["z"], spot.y,
		"negative delta never reverses the wind")
	world.blocked = true
	t.eq(Smoke.drift(cloud, world, storm_at + 1.0, 1.0), cloud,
		"water or sanctuary boundaries stop smoke")
	world.blocked = false
	var rolling: Dictionary = cloud.duplicate(true)
	var now: float = storm_at
	for step in 7:
		now += 1.0
		rolling = Smoke.drift(rolling, world, now, 1.0)
	var drifted := Vector3(float(rolling["x"]), 4.0, float(rolling["z"]))
	var original := Vector3(spot.x, 4.0, spot.y)
	t.check(original.distance_to(drifted) > Smoke.RADIUS,
		"long storm drift moves cover away from its original cast position")
	var clouds := {51: rolling}
	t.check(not Smoke.inside(clouds, original, now),
		"survivor standing still loses visual protection when smoke blows away")
	t.check(Smoke.inside(clouds, drifted, now),
		"moving with the cloud restores its stealth benefit")
	t.eq(Smoke.signature(1.0, clouds, original, now, 0.0, true), 1.0,
		"original ground provides no lingering invisible protection")
	t.near(Smoke.signature(1.0, clouds, drifted, now, 0.0, true),
		Smoke.MULTIPLIER, 0.0001, "actual moving cloud suppresses infected vision")

	t.current = "real server ticks replicate drift, without owner information"
	var real_world := WorldGen.new(2090)
	var site: Vector2 = EvasionTest.new()._clear_red_zone_spot(real_world)
	t.check(site.is_finite(), "has legitimate exposed field position")
	if not site.is_finite():
		return
	var sim := GameServer.new(real_world, 2090)
	var player = sim.add_player(71, "Wind Scout")
	player.position = Vector3(site.x, real_world.height_at(site.x, site.y), site.y)
	var observed_storm: float = _find_weather(real_world, site, "storm")
	t.check(observed_storm >= 0.0, "real island has storm conditions")
	if observed_storm < 0.0:
		return
	sim.time = observed_storm
	player.inventory.add(Smoke.ITEM_ID, 1)
	t.check(bool(sim.cmd_use(71, Smoke.ITEM_ID).get("ok", false)),
		"real player pays one charge for a physical smoke cloud")
	if sim.smoke_clouds.is_empty():
		return
	var cloud_id: int = int(sim.smoke_clouds.keys()[0])
	var start := Vector2(float(sim.smoke_clouds[cloud_id]["x"]),
		float(sim.smoke_clouds[cloud_id]["z"]))
	sim.time += 0.5
	sim._tick_world(0.5)
	var public: Array = sim.snapshot_for(71)["smoke_clouds"]
	t.eq(public.size(), 1, "interest-limited snapshot contains moving smoke")
	if public.size() == 1:
		var actual := Vector2(float(public[0]["x"]), float(public[0]["z"]))
		t.eq(actual, Vector2(float(sim.smoke_clouds[cloud_id]["x"]),
			float(sim.smoke_clouds[cloud_id]["z"])),
			"network positions come from authoritative server cloud")
		t.check(actual.distance_to(start) > 0.0,
			"real smoke shifts with locally generated storm wind")
		t.check(not public[0].has("owner"),
			"only cloud coordinates reach clients, not private owner IDs")
	t.check(not WorldPersistence.capture(sim).has("smoke_clouds"),
		"windblown smoke never pollutes permanent world saves")
