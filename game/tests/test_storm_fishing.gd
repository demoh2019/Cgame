extends RefCounted
## Storm casting never trusts client weather, tier, bonus or claimed fish count.
const Fishing = preload("res://scripts/shared/fishing.gd")
const StormFishing = preload("res://scripts/shared/storm_fishing.gd")
const Weather = preload("res://scripts/shared/weather.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Net = preload("res://scripts/shared/net.gd")


class WeatherCoast:
	var world_seed: int = 1066
	var zone: int = 2
	func biome_at(_x: float, _z: float) -> String:
		return "mountain"
	func is_safe(_x: float, _z: float) -> bool:
		return false
	func zone_at(_x: float, _z: float) -> int:
		return zone


func _times(world, where: Vector3) -> Dictionary:
	var result: Dictionary = {}
	for phase in range(120):
		var at: float = float(phase) * Weather.CHANGE_SECONDS + 1.0
		var kind: String = str(Weather.conditions(world, where.x, where.z, at).get("condition", ""))
		if not result.has(kind):
			result[kind] = at
		if result.has("storm") and result.has("clear"):
			break
	return result


func _risky_shore(world) -> Vector3:
	for x in range(680, 900, 4):
		for z in range(-180, 181, 4):
			var px := float(x)
			var pz := float(z)
			if world.zone_at(px, pz) < 2 or world.is_water(px, pz):
				continue
			var here := Vector3(px, world.height_at(px, pz), pz)
			if Fishing.water_near(world, here) != Vector2.INF:
				return here
	return Vector3.INF


func run(t) -> void:
	t.current = "weather and zone are authoritative"
	var coast := WeatherCoast.new()
	var at := Vector3(700, 0, 50)
	var times := _times(coast, at)
	t.check(times.has("storm") and times.has("clear"), "storm and clear weather occur")
	if not times.has("storm") or not times.has("clear"):
		return
	var storm: float = float(times["storm"])
	t.check(StormFishing.qualifies(coast, at, storm), "valid risky storm shore")
	t.check(not StormFishing.qualifies(coast, at, float(times["clear"])), "clear rejected")
	coast.zone = 1
	t.check(not StormFishing.qualifies(coast, at, storm), "yellow zone rejected")
	coast.zone = 0
	t.check(not StormFishing.qualifies(coast, at, storm), "green zone rejected")
	coast.zone = 2
	t.check(not StormFishing.qualifies(coast, Vector3(INF, 0, 0), storm), "invalid position rejected")
	t.check(not StormFishing.qualifies(coast, at, NAN), "invalid clock rejected")
	t.current = "bonus never exceeds the actual backpack capacity"
	var bag := Inventory.new(2)
	bag.add("fishing_rod", 1)
	bag.add("raw_fish", 16)
	t.eq(StormFishing.bonus_for(bag, "raw_fish", 2), 2, "two base and two bonus fit")
	t.eq(StormFishing.bonus_for(bag, "raw_fish", 3), 0, "oversize base rejected")
	t.eq(StormFishing.bonus_for(bag, "silver", 1), 0, "non-fish cannot be rewarded")
	bag.add("raw_fish", 2)
	t.eq(StormFishing.bonus_for(bag, "raw_fish", 2), 0, "no partial bonus")
	t.current = "server cast and genuine fishing progression"
	var world := WorldGen.new(42)
	var sim := GameServer.new(world, 86)
	var fisher = sim.add_player(81, "Storm Angler")
	var shore: Vector3 = _risky_shore(world)
	t.check(shore.is_finite(), "full-loot fishable shore exists")
	if not shore.is_finite():
		return
	var forecast := _times(world, shore)
	t.check(forecast.has("storm") and forecast.has("clear"), "server coastline has both weathers")
	if not forecast.has("storm") or not forecast.has("clear"):
		return
	fisher.position = shore
	fisher.inventory.add("fishing_rod", 1)
	sim.time = float(forecast["clear"])
	t.eq(sim.cmd_fish(81, false, true).get("reason", ""), "not_storm_coast", "cannot fake a storm")
	t.check(fisher.action.is_empty(), "failed cast has no pending action")
	sim.time = float(forecast["storm"])
	t.eq(sim.cmd_fish(81, true, true).get("reason", ""), "incompatible_modes", "no bait stacking")
	var start: Dictionary = sim.cmd_fish(81, false, true)
	t.check(bool(start.get("ok", false)), "server starts the risky cast")
	if not bool(start.get("ok", false)):
		return
	t.near(float(start.get("seconds", 0.0)), StormFishing.CAST_SECONDS, 0.001, "8s timer")
	t.check(bool(fisher.action.get("storm_cast", false)), "server owns the pending mode")
	t.eq(fisher.inventory.count("raw_fish"), 0, "no immediate fish")
	t.eq(sim.cmd_fish(81, false, true).get("reason", ""), "busy", "no double casts")
	var xp_before: int = int(fisher.progression.gathering_xp["fishing"])
	for i in range(85):
		sim.time += 0.1
		sim._tick_players(0.1)
	t.check(fisher.action.is_empty(), "cast completes after eight seconds")
	var count: int = fisher.inventory.count("raw_fish")
	t.check(count >= 3 and count <= 4, "bounded 1-2 base plus 2 storm fish")
	t.eq(int(fisher.progression.gathering_xp["fishing"]) - xp_before,
		count * fisher.progression.GATHER_XP_PER_ITEM, "XP for credited fish only")
	var caught: Dictionary = {}
	for entry in sim.events:
		if entry.get("type", "") == "fished":
			caught = entry
	t.eq(caught.get("storm_bonus", -1), 2, "event declares actual storm bonus")
	t.eq(caught.get("amount", -1), count, "event contains credited catch")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net._event_visible_to(caught, 81), "catch event visible to fisher")
	t.check(not net._event_visible_to(caught, 82), "catch event hidden from strangers")
	net.free()
	t.current = "weather change interrupts risky action with no loot"
	sim.time = float(forecast["storm"]) + StormFishing.CAST_SECONDS + Fishing.COOLDOWN_SECONDS + 1.0
	t.check(bool(sim.cmd_fish(81, false, true).get("ok", false)), "second cast starts")
	var before: int = fisher.inventory.count("raw_fish")
	sim.time = float(forecast["clear"])
	sim._tick_players(0.1)
	t.check(fisher.action.is_empty(), "cast interrupted when storm ends")
	t.eq(fisher.inventory.count("raw_fish"), before, "cancellation grants no fish")
	var notified := false
	for entry in sim.events:
		if entry.get("type", "") == "storm_cast_lost":
			notified = true
	t.check(notified, "client gets interruption event")
