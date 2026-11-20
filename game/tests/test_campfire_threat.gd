extends RefCounted
## Regression tests for authoritative night light and finite zombie investigation.

const CampfireThreat = preload("res://scripts/shared/campfire_threat.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func run(t) -> void:
	var night: float = WorldCycle.DAY_LENGTH * 0.75
	var day: float = WorldCycle.DAY_LENGTH * 0.25
	var site := Vector2(210.0, 145.0)
	var fire: Dictionary = {"id": 7, "x": site.x, "y": 0.0,
		"z": site.y, "expires": night + 100.0}
	var fires: Dictionary = {7: fire}

	t.current = "night-only and expiring firelight"
	t.check(WorldCycle.is_night(night) and not WorldCycle.is_night(day),
		"test timestamps match the actual day cycle")
	t.eq(CampfireThreat.reveal_radius(fires, Vector3(site.x, 0, site.y),
		night, true), CampfireThreat.REVEAL_RADIUS, "burning night fire reveals camper")
	t.eq(CampfireThreat.reveal_radius(fires, Vector3(site.x, 0, site.y),
		day, false), 0.0, "daylight does not reveal")
	t.eq(CampfireThreat.reveal_radius(fires, Vector3(site.x + 7, 0, site.y),
		night, true), 0.0, "farther than warmth radius stays hidden")
	t.eq(CampfireThreat.reveal_radius(fires, Vector3(site.x, 0, site.y),
		night + 100.0, true), 0.0, "exact expiry removes revealing light")
	t.eq(CampfireThreat.reveal_radius(fires, Vector3(NAN, 0, 0),
		night, true), 0.0, "invalid player positions never yield light")

	t.current = "bounded deterministic light index"
	var buckets: Dictionary = CampfireThreat.light_buckets(fires, night, true)
	t.eq(CampfireThreat.nearest_light(buckets,
		Vector3(site.x + 20.0, 0, site.y)).get("id", -1), 7,
		"nearby infected can investigate a burning fire")
	t.check(CampfireThreat.nearest_light(buckets,
		Vector3(site.x + 28.0, 0, site.y)).is_empty(), "distant fire is ignored")
	t.check(CampfireThreat.nearest_light(buckets, Vector3(NAN, 0, 0)).is_empty(),
		"invalid infected position yields no cue")
	t.check(CampfireThreat.light_buckets(fires, day, false).is_empty(),
		"daylight has no lure buckets")
	t.check(CampfireThreat.light_buckets(fires, night + 100.0, true).is_empty(),
		"expired light cannot lure before cleanup")
	var ties: Dictionary = {
		9: {"id": 9, "x": 10.0, "z": 0.0, "expires": night + 1},
		3: {"id": 3, "x": -10.0, "z": 0.0, "expires": night + 1}}
	t.eq(CampfireThreat.nearest_light(
		CampfireThreat.light_buckets(ties, night, true), Vector3.ZERO).get("id", -1),
		3, "equal-distance fires use stable ID tie-break")

	t.current = "server connects camp lighting to real infected AI"
	var world := WorldGen.new(841)
	var sim := GameServer.new(world, 841)
	var player = sim.add_player(71, "Camper")
	player.position = Vector3(site.x, world.height_at(site.x, site.y), site.y)
	sim.time = night
	sim.campfires[7] = fire.duplicate()
	var watcher := Zombie.new(sim.new_id(), "walker",
		Vector3(site.x + 26.0, world.height_at(site.x + 26.0, site.y), site.y))
	sim.zombies[watcher.id] = watcher
	sim.tick_count = 5
	sim._tick_zombies(0.05)
	t.eq(watcher.target_id, 71, "illuminated quiet survivor is visible beyond usual range")
	t.eq(watcher.state, Zombie.State.CHASE, "actual player is chased")

	t.current = "unattended campfire creates only an investigation"
	player.position = Vector3(site.x + 140, world.height_at(site.x + 140, site.y), site.y)
	var idle := Zombie.new(sim.new_id(), "walker",
		Vector3(site.x + 18.0, world.height_at(site.x + 18.0, site.y), site.y))
	sim.zombies.clear()
	sim.zombies[idle.id] = idle
	sim.tick_count = 5
	sim._tick_zombies(0.05)
	t.eq(idle.state, Zombie.State.INVESTIGATE, "idle zombie notices fire")
	t.eq(idle.target_id, -1, "no fabricated player target")
	t.check(idle.last_known_target.distance_to(site) < 0.01,
		"infection investigation has real fire destination")
	t.check(not watcher.investigate_decoy(site), "active chase cannot be redirected")

	t.current = "day and expiry suppress new lures"
	sim.zombies.clear()
	var daylight := Zombie.new(sim.new_id(), "walker",
		Vector3(site.x + 18, world.height_at(site.x + 18, site.y), site.y))
	sim.zombies[daylight.id] = daylight
	sim.time = day
	sim.tick_count = 5
	sim._tick_zombies(0.05)
	t.check(daylight.state != Zombie.State.INVESTIGATE, "camp is harmless by day")
	sim.zombies.clear()
	var expired := Zombie.new(sim.new_id(), "walker",
		Vector3(site.x + 18, world.height_at(site.x + 18, site.y), site.y))
	sim.zombies[expired.id] = expired
	sim.time = night + 100.0
	sim.tick_count = 5
	sim._tick_zombies(0.05)
	t.check(expired.state != Zombie.State.INVESTIGATE, "expired fire is no longer a lure")
