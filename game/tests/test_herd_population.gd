extends RefCounted
## Off-zone horde simulation: free-roaming infected leaving the active radius fold into
## CgamePopulationLOD herds and promote back into real infected near players.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const CrowdFacade = preload("res://scripts/native/cgame_crowd_facade.gd")


## A dry, unsafe spot whose surroundings (60 m ring) are dry and unsafe too.
func _field(world) -> Vector2:
	for r in range(6, 40):
		for a in 16:
			var p := Vector2.from_angle(float(a) * TAU / 16.0) * float(r) * 60.0
			var ok := true
			for k in 8:
				var q: Vector2 = p + Vector2.from_angle(float(k) * TAU / 8.0) * 60.0
				if world.is_water(q.x, q.y) or world.is_safe(q.x, q.y):
					ok = false
					break
			if ok and not world.is_water(p.x, p.y) and not world.is_safe(p.x, p.y):
				return p
	return Vector2.INF


func _free_roamers(server) -> Array:
	var out: Array = []
	var ids: Array = server.zombies.keys()
	ids.sort()
	for id in ids:
		if server.zombies[id].spawn_id < 0:
			out.append(server.zombies[id])
	return out


## Folds one free roamer far from the player, then walks the player up to the herd.
func _scenario(seed_value: int) -> Dictionary:
	var server := GameServer.new(WorldGen.new(seed_value), seed_value)
	server.herd_simulation_enabled = true
	var field: Vector2 = _field(server.world)
	var player = server.add_player(5100, "Scout")
	player.position = Vector3(field.x - 600.0, server.world.height_at(field.x - 600.0, field.y), field.y)
	for k in 3:
		var roamer := Zombie.new(server.new_id(), "walker", Vector3(field.x + float(k), server.world.height_at(field.x, field.y), field.y), -1)
		server.zombies[roamer.id] = roamer
	server._manage_zombie_population()
	var folded: int = int(server.get_herd_stats().get("folded", 0))
	var abstract_before: int = int(server._herds.abstract_count())
	var herd: Dictionary = CrowdFacade.herd_info(server._herds, int(server._herds.herd_ids()[0]))
	var herd_pos: Vector2 = herd["pos"]
	player.position = Vector3(herd_pos.x - 60.0, server.world.height_at(herd_pos.x - 60.0, herd_pos.y), herd_pos.y)
	server._manage_zombie_population()
	var spots: Array = []
	for z in _free_roamers(server):
		spots.append(Vector2(z.position.x, z.position.z))
	return {"server": server, "player": player, "folded": folded, "abstract_before": abstract_before,
		"abstract_after": int(server._herds.abstract_count()), "spots": spots}


func run(t) -> void:
	t.current = "live herd backend rejects invalid events and frame times"
	var population: Object = CrowdFacade.make_population_lod()
	population.setup(3, 3, 64.0, 42)
	var center: Vector2 = population.region_center(4)
	population.add_herd(4, {"walker": 3})
	population.add_attractor("noise", center, 2.0, 100.0, 1.0)
	var expected: float = population.attraction(4)
	population.add_attractor("noise", center, NAN, 100.0, 1.0)
	population.add_attractor("noise", Vector2.INF, 5.0, 100.0, 1.0)
	population.add_attractor("noise", center, 5.0, INF, 1.0)
	population.add_attractor("noise", center, 5.0, 100.0, INF)
	population.add_attractor("noise", center, 5.0, 100.0, 0.0)
	t.eq(population.active_attractor_count(), 1, "malformed event pulses never accumulate")
	t.near(population.attraction(4), expected, 0.00001, "bad pulses cannot poison attraction")
	var original: Dictionary = CrowdFacade.herd_info(population, int(population.herd_ids()[0]))
	for invalid_dt in [NAN, INF, -1.0, 0.0]:
		population.tick(invalid_dt)
	t.eq(CrowdFacade.herd_info(population, int(population.herd_ids()[0])), original,
		"invalid and paused ticks preserve the authoritative herd")
	t.eq(population.active_attractor_count(), 1, "invalid frames do not age live events")
	population.add_spawner(4, "walker", INF, 20)
	population.set_decay(4, NAN)
	population.tick(1.1)
	t.eq(population.active_attractor_count(), 0, "valid tick still expires temporary events")
	t.eq(population.abstract_count(), 3, "bad nest and decay values cannot change population")

	t.current = "flag defaults"
	var plain := GameServer.new(WorldGen.new(41), 41)
	t.eq(plain.herd_simulation_enabled, CrowdFacade.has_native_population_lod(), "herd_simulation_enabled defaults to native availability")

	t.current = "flag off keeps the old unload"
	plain.herd_simulation_enabled = false
	var p0 = plain.add_player(5000, "Off")
	p0.position = Vector3(0.0, plain.world.height_at(0.0, 0.0), 0.0)
	var lost := Zombie.new(plain.new_id(), "walker", Vector3(900.0, 0.0, 900.0), -1)
	plain.zombies[lost.id] = lost
	plain._manage_zombie_population()
	t.check(not plain.zombies.has(lost.id), "far free roamer unloaded as before")
	t.check(plain._herds == null, "no herd simulation allocated when off")

	t.current = "fold and promote"
	var s: Dictionary = _scenario(41)
	var server = s["server"]
	t.eq(int(s["folded"]), 3, "three far free roamers folded into a herd")
	t.eq(int(s["abstract_before"]), 3, "abstract population conserves them")
	var spots: Array = s["spots"]
	t.check(spots.size() > 0, "approaching the herd promotes real infected")
	t.eq(int(s["abstract_after"]) + spots.size(), 3, "promotion conserves the herd head count")
	var player_at := Vector2(s["player"].position.x, s["player"].position.z)
	var rules_ok := true
	for spot in spots:
		var d: float = (spot as Vector2).distance_to(player_at)
		rules_ok = rules_ok and d > GameServer.HERD_MIN_SPAWN_DISTANCE and d < GameServer.ZOMBIE_ACTIVE_RADIUS \
			and not server.world.is_water(spot.x, spot.y) and not server.world.is_safe(spot.x, spot.y)
	t.check(rules_ok, "promoted infected respect spawn distance, water, safe ground and the active radius")
	t.eq(int(server.get_herd_stats().get("promoted", 0)), spots.size(), "stats count promotions")

	t.current = "spawn-point infected keep their lifecycle"
	var keep := GameServer.new(WorldGen.new(42), 42)
	keep.herd_simulation_enabled = true
	var p1 = keep.add_player(5001, "Keep")
	p1.position = Vector3(0.0, keep.world.height_at(0.0, 0.0), 0.0)
	var bound := Zombie.new(keep.new_id(), "walker", Vector3(900.0, 0.0, 900.0), 777001)
	keep.spawn_state[777001] = {"zombie": bound.id, "next": 0.0}
	keep.zombies[bound.id] = bound
	var elite := Zombie.new(keep.new_id(), "walker", Vector3(910.0, 0.0, 900.0), -1)
	elite.become_elite()
	keep.zombies[elite.id] = elite
	keep._manage_zombie_population()
	t.eq(int(keep._herds.abstract_count()), 0, "spawn-point and elite infected are not folded")
	t.eq(int(keep.spawn_state[777001]["zombie"]), -1, "spawn point reset exactly as before")

	t.current = "determinism and throttle"
	var again: Dictionary = _scenario(41)
	t.eq(again["spots"], s["spots"], "same seed and inputs promote identical infected")
	var throttled := GameServer.new(WorldGen.new(41), 41)
	throttled.incident_spawn_cap = 0
	throttled.herd_simulation_enabled = true
	var field: Vector2 = _field(throttled.world)
	var p2 = throttled.add_player(5002, "Slow")
	p2.position = Vector3(field.x - 600.0, 0.0, field.y)
	var r := Zombie.new(throttled.new_id(), "walker", Vector3(field.x, 0.0, field.y), -1)
	throttled.zombies[r.id] = r
	throttled._manage_zombie_population()
	p2.position = Vector3(field.x - 60.0, throttled.world.height_at(field.x - 60.0, field.y), field.y)
	throttled._manage_zombie_population()
	t.eq(_free_roamers(throttled).size(), 0, "slow-server throttle blocks herd reinforcements")
	t.eq(int(throttled._herds.abstract_count()), 1, "the herd waits abstractly")
