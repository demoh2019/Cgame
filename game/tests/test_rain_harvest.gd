extends RefCounted
## Timed, safe, item-paid stormwater collection and save roundtrip.

const RainHarvest = preload("res://scripts/shared/rain_harvest.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


class TestLand:
	var world_seed: int = 13
	var safe: bool = false
	var flooded: bool = false
	var slope: float = 1.0
	var biome: String = "forest"

	func is_safe(_x: float, _z: float) -> bool:
		return safe

	func is_water(_x: float, _z: float) -> bool:
		return flooded

	func normal_at(_x: float, _z: float) -> Vector3:
		return Vector3(0.0, slope, 0.0)

	func biome_at(_x: float, _z: float) -> String:
		return biome


func run(t) -> void:
	t.current = "storm requires authentic weather and safe ground"
	var fake := TestLand.new()
	var position := Vector3(100.0, 3.0, 200.0)
	var storm_time: float = -1.0
	var clear_time: float = -1.0
	for phase in range(120):
		var current: float = float(phase) * Weather.CHANGE_SECONDS + 1.0
		if Weather.conditions(fake, position.x, position.z, current)["condition"] == "storm":
			storm_time = current
		else:
			clear_time = current
		if storm_time > 0.0 and clear_time > 0.0:
			break
	t.check(storm_time > 0.0 and clear_time > 0.0, "seed produces both storm and clear")
	if storm_time < 0.0 or clear_time < 0.0:
		return
	t.eq(RainHarvest.site_reason(fake, position, clear_time), "no_storm",
		"sunny weather produces no water")
	t.eq(RainHarvest.site_reason(fake, position, storm_time), "",
		"storm permits rain collection on dry stable ground")
	t.eq(RainHarvest.site_reason(fake, Vector3(NAN, 0.0, 0.0), storm_time),
		"invalid_position", "cannot collect from nonfinite coordinates")
	t.eq(RainHarvest.site_reason(fake, position, INF),
		"invalid_position", "invalid clock cannot forge rain")
	fake.safe = true
	t.eq(RainHarvest.site_reason(fake, position, storm_time), "sheltered",
		"starter hub cannot harvest rain")
	fake.safe = false
	fake.flooded = true
	t.eq(RainHarvest.site_reason(fake, position, storm_time), "in_water",
		"water bodies cannot catch rain")
	fake.flooded = false
	fake.slope = 0.4
	t.eq(RainHarvest.site_reason(fake, position, storm_time), "bad_terrain",
		"steep terrain is not eligible")
	fake.slope = 1.0
	fake.biome = "swamp"
	t.check(RainHarvest.needs_filter(fake, position), "swamp runoff needs a filter")
	fake.biome = "forest"
	t.check(not RainHarvest.needs_filter(fake, position),
		"forest stormwater does not need a filter")

	t.current = "crafting inputs, atomic capacity and swamp filtering"
	t.check(Defs.is_item("rain_tarp") and Defs.recipes().has("rain_tarp"),
		"field rain catcher exists in craft catalog")
	var craft := Inventory.new()
	craft.add("cloth_1", 2)
	craft.add("fiber_1", 2)
	craft.add("plank_1", 1)
	t.eq(Crafting.craft(craft, "rain_tarp", false), Crafting.Result.OK,
		"catcher is craftable with actual resource costs")
	t.eq(craft.count("rain_tarp"), 1, "field craft produces one tarp")
	t.eq(RainHarvest.transact(craft, true)["reason"], "need_filter",
		"swamp cannot create clean bottles without a paid filter")
	t.eq(craft.count("rain_tarp"), 1, "denied operation preserves the tarp")
	var success: Dictionary = RainHarvest.transact(craft, false)
	t.check(bool(success.get("ok", false)), "rain catcher produces bottled water")
	t.eq(craft.count("water_bottle"), 2, "two bottles transferred")
	t.eq(craft.count("rain_tarp"), 0, "one tarp consumed")
	t.eq(RainHarvest.transact(craft, false)["reason"], "no_tarp",
		"replay does not duplicate clean water")
	var swamp_inv := Inventory.new()
	swamp_inv.add("rain_tarp", 1)
	swamp_inv.add("charcoal_filter", 1)
	t.check(bool(RainHarvest.transact(swamp_inv, true).get("ok", false)),
		"one filter plus one tarp produces safe swamp water")
	t.eq(swamp_inv.count("charcoal_filter"), 0, "filter is actually spent")
	var blocked := Inventory.new(1)
	blocked.add("water_bottle", 10)
	var state: Dictionary = blocked.to_dict()
	t.eq(RainHarvest.transact(blocked, false)["reason"], "no_tarp",
		"missing supplies never create free bottles")
	t.eq(blocked.to_dict(), state, "refusal leaves inventory unchanged")
	var tight := Inventory.new(2)
	tight.add("rain_tarp", 2)
	tight.add("stone_1", 100)
	state = tight.to_dict()
	t.eq(RainHarvest.transact(tight, false)["reason"], "no_space",
		"partial stack consumes no tarp when bottles cannot fit")
	t.eq(tight.to_dict(), state, "rollback preserves all items")
	var freed := Inventory.new(1)
	freed.add("rain_tarp", 1)
	t.check(bool(RainHarvest.transact(freed, false).get("ok", false)),
		"consuming final tarp frees a slot for clean water")

	t.current = "server-authorized site, cooldown, snapshot and persistence"
	var world := WorldGen.new(819)
	var site := Vector3.INF
	var world_time: float = -1.0
	for ring in [320.0, 540.0, 770.0]:
		for i in range(48):
			var candidate := Vector2.from_angle(float(i) * TAU / 48.0) * ring
			if world.is_water(candidate.x, candidate.y):
				continue
			var here := Vector3(candidate.x, world.height_at(candidate.x, candidate.y),
				candidate.y)
			for phase in range(40):
				var now := float(phase) * Weather.CHANGE_SECONDS + 1.0
				if RainHarvest.site_reason(world, here, now) == "":
					site = here
					world_time = now
					break
			if site.is_finite():
				break
		if site.is_finite():
			break
	t.check(site.is_finite(), "generated world provides a storm collection site")
	if not site.is_finite():
		return
	var server := GameServer.new(world, 819)
	var player = server.add_player(71, "Rain Scout")
	player.inventory.add("rain_tarp", 2)
	t.eq(server.cmd_collect_rain(999)["reason"], "dead",
		"unknown peer cannot collect")
	t.eq(server.cmd_collect_rain(71)["reason"], "sheltered",
		"hub cannot forge a rain reward")
	player.position = site
	server.time = world_time
	var needs_filter: bool = RainHarvest.needs_filter(world, site)
	if needs_filter:
		t.eq(server.cmd_collect_rain(71)["reason"], "need_filter",
			"contaminated region charges filter")
		player.inventory.add("charcoal_filter", 1)
	var before_water: int = player.inventory.count("water_bottle")
	var obtained: Dictionary = server.cmd_collect_rain(71)
	t.check(bool(obtained.get("ok", false)), "valid storm collection succeeds")
	t.eq(player.inventory.count("water_bottle"), before_water + 2,
		"server awards two real bottles")
	t.eq(player.inventory.count("rain_tarp"), 1, "only one tarp consumed")
	t.check(player.dirty_inventory and player.dirty_character,
		"server schedules inventory sync and save")
	t.eq(server.cmd_collect_rain(71)["reason"], "cooldown",
		"spammed command cannot immediately repeat")
	t.eq(float(server.snapshot_for(71)["you"]["rain_cooldown"]),
		RainHarvest.COOLDOWN_SECONDS, "client sees authoritative cooldown")
	var saved: Dictionary = server.character_data(player)
	t.eq(float(saved["rain_cooldown"]), RainHarvest.COOLDOWN_SECONDS,
		"cooldown persists across sessions")
	t.check(server.apply_character(player, saved), "load original state")
	t.eq(player.rain_cooldown, RainHarvest.COOLDOWN_SECONDS,
		"relogin cannot bypass harvest cooldown")
	for bad in [-1.0, NAN, INF, RainHarvest.COOLDOWN_SECONDS + 1.0, "90"]:
		var malformed: Dictionary = saved.duplicate(true)
		malformed["rain_cooldown"] = bad
		t.check(not server.apply_character(player, malformed),
			"malformed cooldown rejected atomically")
		t.eq(player.rain_cooldown, RainHarvest.COOLDOWN_SECONDS,
			"rejection does not mutate cooldown")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("rain_cooldown")
	t.check(server.apply_character(player, legacy), "legacy version-one save loads")
	t.eq(player.rain_cooldown, 0.0, "old characters start without timer")
	server._tick_players(0.1)
	t.check(server.snapshot_for(71)["you"].has("rain_cooldown"),
		"snapshot preserves new timer after gameplay tick")
