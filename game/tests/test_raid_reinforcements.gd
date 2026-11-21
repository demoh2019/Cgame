extends RefCounted
## Two server-owned raid phases, safe spawns, bounded adds and cleanup.
const RaidReinforcements = preload("res://scripts/shared/raid_reinforcements.gd")
const RaidEncounter = preload("res://scripts/shared/raid_encounter.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


class RidgeWorld:
	extends RefCounted
	var world_seed: int = 721
	func zone_at(x: float, _z: float) -> int:
		return 2 if x > 100.0 else 0
	func is_safe(x: float, _z: float) -> bool:
		return x <= 100.0
	func is_water(_x: float, _z: float) -> bool:
		return false
	func height_at(x: float, _z: float) -> float:
		return 11.0 if x > 215.0 else 3.0
	func blockers_near(_x: float, _z: float, _r: float) -> Array:
		return []


class FlatWorld:
	extends RefCounted
	var world_seed: int = 721
	var queried_sites: Array[Vector2] = []
	func zone_at(x: float, z: float) -> int:
		queried_sites.append(Vector2(x, z))
		return 2 if x > 100.0 else 0
	func is_safe(x: float, _z: float) -> bool:
		return x <= 100.0
	func is_water(_x: float, _z: float) -> bool:
		return false
	func height_at(_x: float, _z: float) -> float:
		return 3.0
	func blockers_near(_x: float, _z: float, _r: float) -> Array:
		return []


func at(x: float, z: float) -> Vector3:
	return Vector3(x, 3.0, z)


func run(t) -> void:
	t.current = "finite health thresholds and no phase replay"
	t.eq(RaidReinforcements.next_phase(600.0, 600.0, 0), 0, "full HP is idle")
	t.eq(RaidReinforcements.next_phase(390.0, 600.0, 0), 1, "65% triggers phase 1")
	t.eq(RaidReinforcements.next_phase(300.0, 600.0, 1), 0, "phase 2 is not premature")
	t.eq(RaidReinforcements.next_phase(180.0, 600.0, 1), 2, "30% triggers phase 2")
	t.eq(RaidReinforcements.next_phase(100.0, 600.0, 2), 0, "completed phases do not replay")
	t.eq(RaidReinforcements.next_phase(0.0, 600.0, 0), 0, "dead boss summons nobody")
	t.eq(RaidReinforcements.next_phase(NAN, 600.0, 0), 0, "NaN cannot summon")
	t.eq(RaidReinforcements.kinds(2).size(), 2, "final wave is bounded")


	t.current = "native EQS Donut generator and portable ring-source parity"
	var ring_center := Vector2(215.0, 200.0)
	for phase_id in [1, 2]:
		var scripted_ring: PackedVector2Array = RaidReinforcements.candidate_ring_points(
			ring_center, phase_id, false)
		var native_ring: PackedVector2Array = RaidReinforcements.candidate_ring_points(
			ring_center, phase_id, true)
		t.eq(scripted_ring.size(), RaidReinforcements.RADII.size() * RaidReinforcements.ANGLES,
			"portable raid sampling retains every original site in every encounter phase")
		t.eq(native_ring.size(), scripted_ring.size(),
			"native EQS donut path preserves the exact candidate budget")
		for index in scripted_ring.size():
			t.check(native_ring[index].distance_to(scripted_ring[index]) < 0.001,
				"all ring candidate coordinates and their phase-rotated source indices agree")
			var ring_index: int = index / RaidReinforcements.ANGLES
			t.near(native_ring[index].distance_to(ring_center),
				float(RaidReinforcements.RADII[ring_index]), 0.001,
				"candidates retain the correct server-owned raid distance band")
	t.eq(RaidReinforcements.candidate_ring_points(Vector2(INF, 0), 1).size(), 0,
		"nonfinite raid centers cannot generate native or script candidates")
	t.eq(RaidReinforcements.candidate_ring_points(ring_center, 3).size(), 0,
		"invalid raid phase cannot generate positions")

	t.current = "EQS Cone forward-sector parity and bounded geometry"
	var cone_center := Vector2(215.0, 200.0)
	var cone_axis := Vector2(4.0, 1.0)
	var script_cone := RaidReinforcements.candidate_cone_points(cone_center, cone_axis, false)
	var native_cone := RaidReinforcements.candidate_cone_points(cone_center, cone_axis, true)
	t.eq(script_cone.size(), RaidReinforcements.CONE_RINGS * RaidReinforcements.CONE_RAYS,
		"portable cone has the exact bounded candidate count")
	t.eq(native_cone.size(), script_cone.size(),
		"native and stock Godot use the same cone sampling budget")
	var cone_centerline := cone_axis.normalized()
	for index in script_cone.size():
		t.check(native_cone[index].distance_to(script_cone[index]) <= 0.001,
			"native sector positions match the stock Godot fallback")
		var displacement: Vector2 = (native_cone[index] - cone_center)
		var expected_radius: float = float(RaidReinforcements.RADII[0]) if index < RaidReinforcements.CONE_RAYS else float(RaidReinforcements.RADII[-1])
		t.near(displacement.length(), expected_radius, 0.001,
			"all cone candidates remain within authoritative raid rings")
		t.check(displacement.normalized().dot(cone_centerline) >= cos(deg_to_rad(RaidReinforcements.CONE_DEGREES / 2.0)) - 0.001,
			"sector points stay inside the designated forward arc")
	t.eq(RaidReinforcements.candidate_cone_points(cone_center, Vector2.ZERO).size(), 0,
		"undefined cone heading cannot create spawn points")
	t.eq(RaidReinforcements.candidate_cone_points(Vector2(INF, 0), Vector2.RIGHT).size(), 0,
		"nonfinite cone center fails closed")
	
	t.current = "bounded deterministic spread ranking"
	var candidates: Array[Vector2] = [
		Vector2(8, 0), Vector2(8, 1), Vector2(16, 0),
		Vector2(16, 1), Vector2(25, 0)]
	var threats: Array[Vector2] = [Vector2(0, 0), Vector2(3, 0)]
	var scripted: Array[Vector2] = RaidReinforcements.spread_sites(
		candidates, threats, Vector2.ZERO, 2, 4.0, false)
	t.eq(scripted.size(), 2, "two locations are selected")
	t.eq(scripted[0], Vector2(25, 0), "safest candidate is first")
	t.eq(scripted[1], Vector2(16, 0), "spread finds next distinct candidate")
	t.check(scripted[0].distance_to(scripted[1]) >= 4.0, "raid sites keep minimum spacing")
	var actual: Array[Vector2] = RaidReinforcements.spread_sites(
		candidates, threats, Vector2.ZERO, 2, 4.0, true)
	t.eq(actual, scripted, "native and stock Godot must select the same sites")
	t.eq(RaidReinforcements.spread_sites(
		candidates, threats, Vector2.ZERO, 0, 4.0).size(), 0, "invalid count rejected")
	t.eq(RaidReinforcements.spread_sites(
		candidates, threats, Vector2.ZERO, 2, NAN).size(), 0, "nonfinite spacing rejected")
	var no_threats: Array[Vector2] = RaidReinforcements.spread_sites(
		candidates, Array[Vector2](), Vector2.ZERO, 2, 4.0)
	t.eq(no_threats[0], Vector2(8, 0), "no threats preserves source order")
	t.eq(no_threats[1], Vector2(16, 0), "empty threats still respects spacing")


	t.current = "server EQS height-filtered spawn candidate parity"
	var site_heights: Array[float] = [0.0, 0.0, 8.0, 2.0, -5.0]
	var from_native: Array[Vector2] = RaidReinforcements.spread_sites(
		candidates, threats, Vector2.ZERO, 2, 4.0, true,
		[], 0.0, site_heights, 0.0, 2.0)
	var from_script: Array[Vector2] = RaidReinforcements.spread_sites(
		candidates, threats, Vector2.ZERO, 2, 4.0, false,
		[], 0.0, site_heights, 0.0, 2.0)
	t.eq(from_native, from_script, "native and fallback height filters agree")
	t.eq(from_script, [Vector2(16, 1), Vector2(8, 1)],
		"elevated/deep shelf sites are excluded before spreading")
	t.eq(RaidReinforcements.spread_sites(
		candidates, threats, Vector2.ZERO, 2, 4.0, true,
		[], 0.0, [0.0], 0.0, 2.0), [], "truncated heights fail closed")
	t.eq(RaidReinforcements.spread_sites(
		candidates, threats, Vector2.ZERO, 2, 4.0, true,
		[], 0.0, site_heights, NAN, 2.0), [], "nonfinite origin elevation rejected")
	t.eq(RaidReinforcements.spread_sites(
		candidates, threats, Vector2.ZERO, 2, 4.0, true,
		[], 0.0, site_heights, 0.0, INF), [], "nonfinite height limit rejected")

	t.current = "native occupancy contexts exclude all living infected without bypassing guards"
	var blocked: Array[Vector2] = [Vector2(25, 0)]
	var script_filtered: Array[Vector2] = RaidReinforcements.spread_sites(
		candidates, threats, Vector2.ZERO, 2, 4.0, false, blocked, 4.0)
	var native_filtered: Array[Vector2] = RaidReinforcements.spread_sites(
		candidates, threats, Vector2.ZERO, 2, 4.0, true, blocked, 4.0)
	t.eq(native_filtered, script_filtered, "occupied site filtering agrees on stock Godot and Cgame")
	t.eq(script_filtered.size(), 2, "two legal reinforcement positions remain after occupancy filtering")
	t.check(not script_filtered.has(blocked[0]),
		"occupied highest-scoring site is rejected before reinforcement selection")
	if script_filtered.size() == 2:
		t.check(script_filtered[0].distance_to(script_filtered[1]) >= 4.0,
			"occupied-site filtering preserves minimum separation")
	t.eq(RaidReinforcements.spread_sites(
		candidates, threats, Vector2.ZERO, 2, 4.0, true, blocked, INF),
		[], "nonfinite exclusion radius cannot return server-owned spawn sites")
	var many_occupied: Array[Vector2] = []
	for i in 128:
		many_occupied.append(Vector2(1000.0 + float(i), 0.0))
	many_occupied.append(Vector2(25, 0)) # The 129th context must never be truncated.
	t.eq(RaidReinforcements.spread_sites(
		candidates, threats, Vector2.ZERO, 2, 4.0, true, many_occupied, 4.0),
		script_filtered, "large exclusion lists check the final infected through fallback")

	t.current = "server only, genuine infected, safe coordinates"
	var world := FlatWorld.new()
	var server := GameServer.new(world, 721)
	var fighter = server.add_player(301, "Frontline")
	var ally = server.add_player(302, "Archer")
	fighter.position = at(200.0, 200.0)
	ally.position = at(202.0, 202.0)
	var boss_id: int = server.new_id()
	var boss := Zombie.new(boss_id, "brute", at(215.0, 200.0), -1)
	RaidEncounter.empower(boss)
	boss.target_id = fighter.id
	server.zombies[boss_id] = boss
	server.raid_boss_id = boss_id
	server.raid_started_at = 100.0
	server.raid_next_slam_at = 1000.0
	server.time = 120.0
	t.eq(RaidReinforcements.sites(world, server.players, server.zombies,
		at(50.0, 200.0), 1, 2).size(), 0, "safe hub blocks adds")
	var sites := RaidReinforcements.sites(world, server.players,
		server.zombies, boss.position, 1, 2)
	t.eq(sites.size(), 2, "clear dangerous terrain permits two adds")
	# Second phase augments the old donut with a real forward cone, while
	# retaining the exact same zone, terrain and occupancy validation.
	world.queried_sites.clear()
	var phase_two_sites := RaidReinforcements.sites(
		world, server.players, server.zombies, boss.position, 2, 2)
	t.eq(phase_two_sites.size(), 2, "forward-sector wave still finds two safe spawn sites")
	var closest_player_axis := Vector2(ally.position.x - boss.position.x,
		ally.position.z - boss.position.z)
	var cone_wave_points := RaidReinforcements.candidate_cone_points(
		Vector2(boss.position.x, boss.position.z), closest_player_axis)
	var cone_visited := false
	for sample in cone_wave_points:
		for checked in world.queried_sites:
			if checked.distance_to(sample) <= 0.001:
				cone_visited = true
				break
		if cone_visited:
			break
	t.check(cone_visited,
		"second raid phase actually submits native/fallback cone candidates to server terrain validation")
	for site in phase_two_sites:
		t.check(site.distance_to(Vector2(fighter.position.x, fighter.position.z)) >=
			RaidReinforcements.MIN_PLAYER_DISTANCE,
			"forward sector does not permit spawning on the frontline player")
		t.check(site.distance_to(Vector2(ally.position.x, ally.position.z)) >=
			RaidReinforcements.MIN_PLAYER_DISTANCE,
			"forward sector does not permit spawning on the closest ally")

	var ridge := RidgeWorld.new()
	var ridge_sites: Array[Vector2] = RaidReinforcements.sites(
		ridge, server.players, server.zombies, boss.position, 1, 2)
	t.check(not ridge_sites.is_empty(), "raid sites remain available on low ground")
	for site in ridge_sites:
		t.check(absf(ridge.height_at(site.x, site.y) - boss.position.y) <=
			RaidReinforcements.MAX_RAID_HEIGHT_DIFFERENCE,
			"high shelves never receive server-owned raid adds")
	if sites.size() >= 2:
		t.check(sites[0].distance_to(sites[1]) >= RaidReinforcements.MIN_BETWEEN_ADDS,
			"live raid wave positions maintain separation")
	for site in sites:
		t.eq(world.zone_at(site.x, site.y), 2, "adds stay in encounter zone")
		t.check(site.distance_to(Vector2(fighter.position.x, fighter.position.z))
			>= RaidReinforcements.MIN_PLAYER_DISTANCE, "adds cannot spawn onto players")
		t.check(site.distance_to(Vector2(boss.position.x, boss.position.z))
			>= RaidReinforcements.MIN_INFECTED_DISTANCE,
			"native or fallback occupancy filter prevents spawn inside the living boss")
	boss.health = 390.0
	server._tick_raid_encounter()
	t.eq(server.raid_wave, 1, "server starts phase 1 from actual boss health")
	t.eq(server.raid_minions.size(), 2, "first phase creates exactly two minions")
	t.eq(server.zombies.size(), 3, "boss remains active with reinforcements")
	server._tick_raid_encounter()
	t.eq(server.raid_minions.size(), 2, "repeat tick cannot farm additional spawns")
	var alerts: Array = server.events.filter(func(event: Dictionary) -> bool:
		return str(event.get("type", "")) == "raid_reinforcements")
	t.eq(alerts.size(), 1, "phase notification appears once")
	var conn := Net.new()
	conn.role = "server"
	conn.sim = server
	t.check(conn._event_visible_to(alerts[0], fighter.id), "nearby group sees event")
	var remote = server.add_player(303, "Remote")
	remote.position = at(0, 0)
	t.check(not conn._event_visible_to(alerts[0], remote.id),
		"remote players do not receive raid locations")
	conn.free()
	boss.health = 180.0
	server._tick_raid_encounter()
	t.eq(server.raid_wave, 2, "final phase starts at low HP")
	t.eq(server.raid_minions.size(), 4, "only four minions total")
	var has_brute := false
	for id in server.raid_minions:
		if server.zombies[id].type == "brute":
			has_brute = true
	t.check(has_brute, "second wave adds a brute")
	var old_minions: Array = server.raid_minions.duplicate()
	server._damage_target(fighter, {"kind": "zombie", "id": boss_id}, 2000.0)
	t.eq(server.raid_boss_id, -1, "victory releases encounter")
	t.eq(server.raid_wave, 0, "phase state resets")
	t.eq(server.raid_minions.size(), 0, "minion identities cleared")
	for id in old_minions:
		t.check(not server.zombies.has(id), "raid adds disappear on victory")
	var bag_count: int = server.bags.size()
	server._damage_target(fighter, {"kind": "zombie", "id": boss_id}, 2000.0)
	t.eq(server.bags.size(), bag_count, "dead boss never grants repeat loot")

	t.current = "server population cap and expiration"
	var next_id: int = server.new_id()
	var second := Zombie.new(next_id, "brute", at(215.0, 200.0), -1)
	RaidEncounter.empower(second)
	server.zombies[next_id] = second
	server.raid_boss_id = next_id
	server.raid_started_at = server.time - RaidEncounter.MAX_ENCOUNTER_SECONDS - 1.0
	server._tick_raid_encounter()
	t.eq(server.raid_boss_id, -1, "expired boss disappears")
	t.check(not server.zombies.has(next_id), "expired boss removed from world")
	t.eq(server.raid_minions.size(), 0, "no lingering adds after timeout")
