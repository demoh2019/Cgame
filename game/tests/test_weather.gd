extends RefCounted
## Deterministic weather, server-owned cold exposure and save migration tests.

const Weather = preload("res://scripts/shared/weather.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Survival = preload("res://scripts/shared/survival.gd")


class ColdBiome:
	var world_seed: int = 20261119

	func biome_at(_x: float, _z: float) -> String:
		return "mountain"

	func is_safe(x: float, z: float) -> bool:
		return Vector2(x, z).length() < 45.0


func run(t) -> void:
	t.current = "weather conditions deterministic and spatially stable"
	var fake = ColdBiome.new()
	var initial: Dictionary = Weather.conditions(fake, 340.0, 210.0, 42.0)
	t.eq(Weather.conditions(fake, 340.0, 210.0, 42.0), initial, "same world seed and time always gives same weather")
	t.eq(Weather.conditions(fake, 345.0, 215.0, 42.0), initial, "adjacent points in one weather cell share conditions")
	t.check(Weather.conditions(fake, INF, 0.0, 1.0).is_empty(), "nonfinite position cannot supply trusted weather")
	var storm: Dictionary = {}
	for phase in range(150):
		var candidate: Dictionary = Weather.conditions(fake, 340.0, 210.0, float(phase) * Weather.CHANGE_SECONDS + 1.0)
		if candidate["condition"] == "storm":
			storm = candidate
			break
	t.check(not storm.is_empty(), "weather timeline contains storms")
	if storm.is_empty():
		return
	t.check(float(storm["temperature_c"]) < Weather.COLD_START_C, "winter storm is cold")
	t.check(float(storm["severity"]) > 0.5, "cold storm causes exposure")
	var shelter: Dictionary = Weather.conditions(fake, 0.0, 0.0, 42.0)
	t.check(bool(shelter["sheltered"]), "hub provides weather protection")
	t.eq(float(shelter["severity"]), 0.0, "shelter prevents weather damage")
	t.check(Weather.effective_severity(storm, "jacket_1") < Weather.effective_severity(storm, ""), "equipped coat reduces exposure")
	t.eq(Weather.effective_severity(shelter, ""), 0.0, "shelter still protects without armor")

	t.current = "cumulative survival exposure and recovery"
	var person = Survival.new()
	var weather_damage: float = person.weather_tick(120.0, Weather.effective_severity(storm, ""))
	t.check(person.exposure > 60.0, "prolonged unprotected storm builds exposure")
	t.check(weather_damage > 0.0 and person.health < 100.0, "severe exposure causes actual health damage")
	var previously: float = person.exposure
	person.weather_tick(15.0, 0.0)
	t.check(person.exposure < previously, "shelter dries and warms survivor")
	var reset = Survival.new()
	reset.weather_tick(35.0, 1.0)
	t.check(reset.exposure > 0.0, "weather raises exposure for living survivor")
	reset.reset()
	t.eq(reset.exposure, 0.0, "respawn resets weather exposure")
	reset.weather_tick(-3.0, 1.0)
	reset.weather_tick(10.0, NAN)
	t.eq(reset.exposure, 0.0, "invalid weather delta and NaN severity rejected")

	t.current = "actual game server owns weather and persistence"
	var world = WorldGen.new(311)
	var server = GameServer.new(world, 311)
	var player = server.add_player(17, "Weather Survivor", "account-17")
	var point := Vector2(280.0, 230.0)
	player.position = Vector3(point.x, world.height_at(point.x, point.y), point.y)
	var harsh: Dictionary = {}
	for phase in range(150):
		server.time = float(phase) * Weather.CHANGE_SECONDS + 1.0
		harsh = Weather.conditions(world, point.x, point.y, server.time)
		if float(harsh.get("severity", 0.0)) > 0.0:
			break
	t.check(float(harsh.get("severity", 0.0)) > 0.0, "server world reaches hazardous weather")
	if float(harsh.get("severity", 0.0)) <= 0.0:
		return
	var before: float = player.survival.exposure
	server._tick_players(20.0)
	t.check(player.survival.exposure > before, "authoritative tick accumulates weather exposure")
	var state: Dictionary = server.snapshot_for(17)["you"]
	t.check(state.has("weather") and state.has("exposure"), "client snapshot includes server-calculated weather")
	t.eq(float(state["exposure"]), player.survival.exposure, "client gets authoritative exposure value")
	var saved: Dictionary = server.character_data(player)
	t.check(saved.has("exposure"), "character save persists exposure")
	player.survival.exposure = 0.0
	t.check(server.apply_character(player, saved), "valid save restores weather exposure")
	t.eq(player.survival.exposure, float(saved["exposure"]), "restored exposure matches original")

	t.current = "malformed saves are atomic and legacy saves migrate"
	var original: float = player.survival.exposure
	var corrupt: Dictionary = saved.duplicate(true)
	corrupt["exposure"] = -3.0
	t.check(not server.apply_character(player, corrupt), "negative exposure is rejected")
	corrupt = saved.duplicate(true)
	corrupt["exposure"] = INF
	t.check(not server.apply_character(player, corrupt), "infinite exposure is rejected")
	corrupt = saved.duplicate(true)
	corrupt["exposure"] = "100"
	t.check(not server.apply_character(player, corrupt), "string exposure is rejected")
	corrupt = saved.duplicate(true)
	corrupt["exposure"] = 101.0
	t.check(not server.apply_character(player, corrupt), "overflow exposure is rejected")
	t.eq(player.survival.exposure, original, "invalid character save cannot change exposure")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("exposure")
	t.check(server.apply_character(player, legacy), "pre-weather character saves remain compatible")
	t.eq(player.survival.exposure, 0.0, "pre-weather character initializes fully sheltered")
