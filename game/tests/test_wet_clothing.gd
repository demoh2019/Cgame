extends RefCounted
## Weather-driven persistent moisture, canopy and campfire drying.
const WetClothing = preload("res://scripts/shared/wet_clothing.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Survival = preload("res://scripts/shared/survival.gd")


func _weather(world, x: float, z: float, storm: bool) -> Dictionary:
	for i in 100:
		var at: float = float(i) * Weather.CHANGE_SECONDS + 1.0
		var conditions: Dictionary = Weather.conditions(world, x, z, at)
		if str(conditions.get("condition", "")) == ("storm" if storm else "clear"):
			return {"time": at, "conditions": conditions}
	return {}


func run(t) -> void:
	t.current = "real precipitation and shelter drying"
	var rain := {"condition": "storm", "temperature_c": -9.0, "sheltered": false}
	var clear := {"condition": "clear", "temperature_c": 3.0, "sheltered": false}
	t.near(WetClothing.next_wetness(0.0, 10.0, rain, "", false, false),
		9.0, 0.001, "unprotected storm adds 0.9 moisture per second")
	t.check(WetClothing.next_wetness(0.0, 10.0, rain, "jacket_1", false, false) < 9.0,
		"physical armor insulation delays soaking")
	t.eq(WetClothing.next_wetness(0.0, 300.0, rain, "", false, false), 100.0,
		"hours of rain cannot overflow the wetness scale")
	t.eq(WetClothing.next_wetness(40.0, 10.0, rain, "", true, false), 34.5,
		"tarp canopy blocks rain and dries the player")
	t.eq(WetClothing.next_wetness(40.0, 10.0, rain, "", false, true), 15.0,
		"lit campfire rapidly dries clothing despite a storm")
	t.eq(WetClothing.next_wetness(40.0, 10.0,
		{"condition": "storm", "sheltered": true}, "", false, false), 34.5,
		"hub or indoor shelter is protected from rainfall")
	t.eq(WetClothing.next_wetness(40.0, 10.0, clear, "", false, false), 38.4,
		"dry air slowly removes residual moisture")
	t.eq(WetClothing.next_wetness(40.0, 0.0, rain, "", false, false), 40.0,
		"zero simulation delta preserves wetness")
	t.eq(WetClothing.next_wetness(40.0, -50.0, rain, "", false, false), 40.0,
		"negative time cannot turn into infinite drying")
	t.eq(WetClothing.next_wetness(40.0, INF, rain, "", false, false), 0.0,
		"nonfinite delta cannot introduce infinite exposure")

	t.current = "rain penalty increases real cold exposure, never warmth"
	t.check(WetClothing.cold_penalty(100.0, clear, "") > 0.0,
		"wet gear is dangerous in cold air even after the rain")
	t.eq(WetClothing.cold_penalty(100.0,
		{"condition": "clear", "temperature_c": 20.0}, ""), 0.0,
		"warm weather cannot penalize wet travelers")
	t.eq(WetClothing.cold_penalty(100.0,
		{"condition": "storm", "temperature_c": -8.0, "sheltered": true}, ""), 0.0,
		"hub weather shelter eliminates cold wetness penalty")
	t.check(WetClothing.cold_penalty(90.0, rain, "jacket_1") <
		WetClothing.cold_penalty(90.0, rain, ""),
		"rain-resistant coat mitigates wet-chill")
	t.eq(WetClothing.cold_penalty(NAN, rain, ""), 0.0,
		"corrupt wetness cannot forge health damage")
	var dry_person := Survival.new()
	var wet_person := Survival.new()
	var base: float = Weather.effective_severity(clear, "")
	dry_person.weather_tick(40.0, base)
	wet_person.weather_tick(40.0, base +
		WetClothing.cold_penalty(100.0, clear, ""))
	t.check(wet_person.exposure > dry_person.exposure,
		"chilled wet survivor accumulates strictly more weather exposure")

	t.current = "live authoritative weather and snapshot sync"
	var world := WorldGen.new(342)
	var sim := GameServer.new(world, 342)
	var survivor = sim.add_player(44, "Cold Scout", "wet-account")
	var site := Vector2(490.0, 330.0)
	survivor.position = Vector3(site.x, world.height_at(site.x, site.y), site.y)
	var storm: Dictionary = _weather(world, site.x, site.y, true)
	var calm: Dictionary = _weather(world, site.x, site.y, false)
	t.check(not storm.is_empty() and not calm.is_empty(), "world seed has storms and clear weather")
	if storm.is_empty() or calm.is_empty():
		return
	t.check(not bool(storm["conditions"].get("sheltered", true)), "test site is exposed")
	sim.time = float(storm["time"])
	var before: float = survivor.survival.wetness
	sim._tick_players(10.0)
	t.check(survivor.survival.wetness > before,
		"server adds wetness using authentic world weather")
	t.eq(sim.snapshot_for(44)["you"]["wetness"], survivor.survival.wetness,
		"client receives only server-calculated wetness")
	var saved: Dictionary = sim.character_data(survivor)
	t.eq(saved["wetness"], survivor.survival.wetness,
		"character saves damp clothes across logout")
	var resumed := GameServer.new(WorldGen.new(342), 342)
	var restored = resumed.add_player(78, "Cold Scout", "wet-account", saved)
	t.eq(restored.survival.wetness, saved["wetness"],
		"relog cannot reset wetness for free")
	resumed.time = float(calm["time"])
	var prior: float = restored.survival.wetness
	resumed._tick_players(2.0)
	t.check(restored.survival.wetness < prior, "clothes dry once rainfall ends")
	t.check(restored.dirty_character, "wetness change is scheduled for persistence")
	var invalid: Dictionary = saved.duplicate(true)
	invalid["wetness"] = 101.0
	t.check(not resumed.apply_character(restored, invalid),
		"forged >100 wetness rejects the whole saved survivor")
	invalid = saved.duplicate(true)
	invalid["wetness"] = INF
	t.check(not resumed.apply_character(restored, invalid),
		"nonfinite wetness cannot enter character state")
	invalid = saved.duplicate(true)
	invalid["wetness"] = "dry"
	t.check(not resumed.apply_character(restored, invalid),
		"string wetness cannot bypass typed save validation")
	var previous: float = restored.survival.wetness
	t.eq(restored.survival.wetness, previous,
		"invalid saves leave live wetness untouched")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("wetness")
	t.check(resumed.apply_character(restored, legacy),
		"legacy characters without the wetness field remain valid")
	t.eq(restored.survival.wetness, 0.0,
		"old character saves begin dry")
