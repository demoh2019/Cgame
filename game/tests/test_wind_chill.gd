extends RefCounted
## Wind chill uses server-owned regional weather, with no synthetic client
## weather parameters or new persistent fields.
const WindChill = preload("res://scripts/shared/wind_chill.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const WetClothing = preload("res://scripts/shared/wet_clothing.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "cold, wet, wind and equipment interactions"
	var cold := {"condition": "storm", "temperature_c": -8.0, "sheltered": false}
	var hot := {"condition": "clear", "temperature_c": 22.0, "sheltered": false}
	var gust := Vector2(1.4, 0.0)
	var normal: float = WindChill.penalty(cold, gust, 0.0, "")
	t.check(normal > 0.0 and normal < 0.33, "cold wind adds bounded exposure intensity")
	t.check(WindChill.penalty(cold, gust, 100.0, "") > normal,
		"soaked clothing increases chilling exposure without adding a second damage system")
	t.check(WindChill.penalty(cold, gust, 100.0, "jacket_1") <
		WindChill.penalty(cold, gust, 100.0, ""),
		"worn insulated jacket mitigates wind chill")
	t.eq(WindChill.penalty(hot, gust, 100.0, ""), 0.0,
		"warm storms do not produce hypothermic wind")
	t.eq(WindChill.penalty(cold, Vector2.ZERO, 100.0, ""), 0.0,
		"calm conditions add no wind stress")
	t.eq(WindChill.penalty(cold, Vector2(0.2, 0.0), 100.0, ""), 0.0,
		"slow breezes do not add cold stress")
	t.eq(WindChill.penalty({"temperature_c": -8.0, "sheltered": true},
		gust, 100.0, ""), 0.0, "hub shelter completely blocks wind chill")
	t.eq(WindChill.penalty(cold, Vector2(NAN, 0.0), 100.0, ""), 0.0,
		"invalid wind cannot corrupt exposure")
	t.eq(WindChill.penalty(cold, gust, INF, ""), 0.0,
		"corrupted wetness cannot create infinite damage")
	t.eq(WindChill.penalty({"temperature_c": INF}, gust, 100.0, ""), 0.0,
		"invalid climate temperatures are ignored")
	t.check(WindChill.penalty(cold, Vector2(99.0, 0.0), 500.0, "") <= 0.33,
		"extreme wind and moisture remain capped")

	t.current = "real regional gusts are added only to real server exposure"
	var world := WorldGen.new(342)
	var server := GameServer.new(world, 342)
	var survivor = server.add_player(91, "Wind Scout", "wind-account")
	var site := Vector2(490.0, 330.0)
	survivor.position = Vector3(site.x, world.height_at(site.x, site.y), site.y)
	var climate: Dictionary = {}
	var wind: Vector2 = Vector2.ZERO
	var found: bool = false
	for i in range(150):
		server.time = float(i) * Weather.CHANGE_SECONDS + 1.0
		climate = Weather.conditions(world, site.x, site.y, server.time)
		wind = Weather.wind_at(world, site.x, site.y, server.time)
		if not bool(climate.get("sheltered", true)) and \
			float(climate.get("temperature_c", 99.0)) < Weather.COLD_START_C and \
			wind.length() > WindChill.MIN_WIND_MPS:
			found = true
			break
	t.check(found, "seeded world reaches exposed freezing gusts")
	if not found:
		return
	var next_wet: float = WetClothing.next_wetness(0.0, 10.0, climate, "", false, false)
	var mean_wet: float = 0.5 * next_wet
	var extra: float = WindChill.penalty(climate, wind, mean_wet, "")
	var expected: float = clampf(Weather.effective_severity(climate, "") +
		WetClothing.cold_penalty(mean_wet, climate, "") + extra, 0.0, 1.0)
	t.check(extra > 0.0, "actual server region produces a positive wind-chill penalty")
	server._tick_players(10.0)
	t.near(survivor.survival.wetness, next_wet, 0.001,
		"wind does not bypass or overwrite real rain-driven wetness")
	t.near(survivor.survival.exposure, 0.55 * 10.0 * expected, 0.01,
		"server applies the gust to the same protected survival weather tick")
	var view: Dictionary = server.snapshot_for(91)["you"]
	t.check(view.has("wind_chill"), "own snapshot exposes wind chill feedback")
	t.near(float(view["wind_chill"]["speed"]), wind.length(), 0.0001,
		"client sees only the speed of deterministic world wind")
	t.near(float(view["wind_chill"]["extra"]),
		WindChill.penalty(climate, wind, survivor.survival.wetness, ""), 0.0001,
		"client displays the current server-derived, not claimed, cold stress")
	var exposed: float = float(view["wind_chill"]["extra"])
	server.shelters[801] = {"id": 801, "owner": survivor.id, "x": site.x,
		"z": site.y, "expires": server.time + 120.0}
	var tarp: Dictionary = server.snapshot_for(91)["you"]["wind_chill"]
	t.check(float(tarp["extra"]) < exposed and float(tarp["extra"]) > 0.0,
		"real tarp sharply reduces visible wind stress")
	server.shelters.clear()
	server.campfires[802] = {"id": 802, "owner": survivor.id, "x": site.x,
		"z": site.y, "expires": server.time + 120.0}
	t.eq(server.snapshot_for(91)["you"]["wind_chill"]["extra"], 0.0,
		"standing at a lit campfire removes wind chill")
	var exposure_before: float = survivor.survival.exposure
	server._tick_players(5.0)
	t.check(survivor.survival.exposure < exposure_before,
		"real fire lowers existing exposure even in windy weather")
