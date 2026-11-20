extends RefCounted
## Walking into legitimate shallow water now soaks clothing. No client-sent
## moisture/depth is trusted; cold stress and persistence remain unchanged.
const Defs = preload("res://scripts/shared/defs.gd")
const WadingWetness = preload("res://scripts/shared/wading_wetness.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


class WaterTerrain:
	extends RefCounted
	var elevation: float = -0.5
	func height_at(_x: float, _z: float) -> float:
		return elevation


func _find_wade(world) -> Vector2:
	# The large island is encircled by ocean. Scan radial crossings from land
	# and bisect the 0.35 m depth crossing for legal shallow water.
	for ray in range(24):
		var axis := Vector2.from_angle(TAU * float(ray) / 24.0)
		var land: Vector2 = axis * 150.0
		var land_h: float = world.height_at(land.x, land.y)
		for n in range(1, 63):
			var sea: Vector2 = axis * (150.0 + float(n) * 52.0)
			var sea_h: float = world.height_at(sea.x, sea.y)
			if land_h >= Defs.WATER_LEVEL - 0.35 and sea_h < Defs.WATER_LEVEL - 0.35:
				var a: Vector2 = land
				var b: Vector2 = sea
				# Target a submerged-but-walkable point instead of deep ocean.
				for k in range(18):
					var middle: Vector2 = (a + b) * 0.5
					if world.height_at(middle.x, middle.y) < Defs.WATER_LEVEL - 0.35:
						b = middle
					else:
						a = middle
				var depth: float = WadingWetness.depth_at(world,
					Vector3(b.x, world.height_at(b.x, b.y), b.y))
				if depth >= 0.35 and depth <= 1.0 and Movement._is_free(world, b):
					return b
			land = sea
			land_h = sea_h
	return Vector2.INF


func run(t) -> void:
	t.current = "wading depth determined only from real water surface"
	var terrain := WaterTerrain.new()
	t.near(WadingWetness.depth_at(terrain, Vector3.ZERO), 0.5, 0.0001,
		"half-meter shallows are walkable and soak the survivor")
	terrain.elevation = 2.0
	t.eq(WadingWetness.depth_at(terrain, Vector3.ZERO), 0.0,
		"dry shore does not apply immersion")
	terrain.elevation = -1.01
	t.eq(WadingWetness.depth_at(terrain, Vector3.ZERO), 0.0,
		"uncrossable deep water cannot count as wading")
	terrain.elevation = NAN
	t.eq(WadingWetness.depth_at(terrain, Vector3.ZERO), 0.0,
		"invalid terrain heights cannot modify persistent moisture")
	t.eq(WadingWetness.depth_at(terrain, Vector3(NAN, 0, 0)), 0.0,
		"invalid positions cannot fabricate water immersion")

	t.current = "immersed clothes soak despite rain shelter or nearby fire"
	t.near(WadingWetness.after_weather(20.0, 15.0, 10.0, 0.5), 50.0, 0.0001,
		"water overrides fire drying: 20% plus 3% per second")
	t.near(WadingWetness.after_weather(20.0, 25.0, 10.0, 0.5), 55.0, 0.0001,
		"storm rainfall still contributes before physical wading")
	t.eq(WadingWetness.after_weather(20.0, 15.0, 10.0, 0.0), 15.0,
		"on dry land existing campfire drying is unchanged")
	t.check(WadingWetness.after_weather(0.0, 0.0, 10.0, 0.9) >
		WadingWetness.after_weather(0.0, 0.0, 10.0, 0.2),
		"deeper but passable water soaks clothing faster")
	t.eq(WadingWetness.after_weather(90.0, 90.0, 300.0, 0.8), 100.0,
		"remaining in water cannot overflow wetness")
	t.eq(WadingWetness.after_weather(40.0, 40.0, -1.0, 0.8), 40.0,
		"negative simulation time cannot create free soaking")
	t.eq(WadingWetness.after_weather(40.0, 40.0, NAN, 0.8), 40.0,
		"NaN time cannot alter character state")
	t.eq(WadingWetness.after_weather(40.0, 40.0, 10.0, INF), 40.0,
		"nonfinite depth never creates infinite moisture")

	t.current = "real ocean shore, live server and character save"
	var world := WorldGen.new(42)
	var shore: Vector2 = _find_wade(world)
	t.check(shore.is_finite(), "seeded island contains accessible shallow ocean")
	if not shore.is_finite():
		return
	var sim := GameServer.new(world, 42)
	var player = sim.add_player(201, "Beach Explorer", "beach-account")
	player.position = Vector3(shore.x, world.height_at(shore.x, shore.y), shore.y)
	var depth: float = WadingWetness.depth_at(world, player.position)
	t.check(depth >= 0.35 and depth <= 1.0,
		"server survivor is genuinely standing in passable water")
	var clear_time := 1.0
	for phase in range(100):
		var at: float = float(phase) * Weather.CHANGE_SECONDS + 1.0
		if str(Weather.conditions(world, shore.x, shore.y, at).get("condition", "")) == "clear":
			clear_time = at
			break
	sim.time = clear_time
	player.survival.wetness = 5.0
	sim._tick_players(10.0)
	t.check(player.survival.wetness > 5.0,
		"server applies real shallow-water wetting even without rain")
	t.check(player.dirty_character,
		"new immersion moisture is marked for persistence")
	var snapshot: Dictionary = sim.snapshot_for(player.id)["you"]
	t.near(float(snapshot["wading_depth_m"]), depth, 0.0001,
		"HUD sees a server-measured water depth, not client claims")
	t.eq(float(snapshot["wetness"]), player.survival.wetness,
		"snapshot and authoritative moisture are identical")
	var saved: Dictionary = sim.character_data(player)
	var restored := GameServer.new(WorldGen.new(42), 42)
	var survivor = restored.add_player(202, "Beach Explorer", "beach-account", saved)
	t.near(survivor.survival.wetness, player.survival.wetness, 0.0001,
		"reconnecting cannot erase immersion wetness")
	# A safe dry position retains the old atmospheric drying rates.
	survivor.position = Vector3(0, world.height_at(0, 0), 0)
	restored.time = clear_time
	var prior: float = survivor.survival.wetness
	restored._tick_players(2.0)
	t.check(survivor.survival.wetness < prior,
		"leaving water lets old dry-land recovery resume")
	t.eq(float(restored.snapshot_for(202)["you"]["wading_depth_m"]), 0.0,
		"dry settlement reports zero immersion")
