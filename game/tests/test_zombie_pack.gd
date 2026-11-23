extends RefCounted
## Pack-alert integration with the authoritative survival server.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const PackNeighborSelection = preload("res://scripts/shared/pack_neighbor_selection.gd")
const ZombieWallAttackGrid = preload("res://scripts/shared/zombie_wall_attack_grid.gd")
const HousePieces = preload("res://scripts/shared/house_pieces.gd")


## Deliberately mirrors the old server-wide scan for exact parity testing.
static func _brute_wall_targets(barricades: Dictionary, here: Vector2,
		toward: Vector2, reach: float) -> Array[int]:
	var ids: Array[int] = []
	for wall_id in barricades:
		var wall: Dictionary = barricades[wall_id]
		if str(wall.get("piece", "")) != "" and not HousePieces.blocks(str(wall["piece"])):
			continue
		var offset := Vector2(float(wall["x"]), float(wall["z"])) - here
		if offset.length() <= reach and offset.dot(toward) > 0.0:
			ids.append(int(wall_id))
	return ids


func run(t) -> void:
	t.current = "proximity pack alert"
	var world := WorldGen.new(22)
	var server := GameServer.new(world, 31)
	var survivor = server.add_player(70, "Loud Survivor")
	# Teleport in a test only. All production AI target positions originate on server.
	survivor.position = Vector3(210, world.height_at(210, 210), 210)
	var source = Zombie.new(server.new_id(), "walker", Vector3(220, world.height_at(220, 210), 210))
	var helper = Zombie.new(server.new_id(), "walker", Vector3(236, world.height_at(236, 210), 210))
	var far = Zombie.new(server.new_id(), "walker", Vector3(251, world.height_at(251, 210), 210))
	server.zombies[source.id] = source
	server.zombies[helper.id] = helper
	server.zombies[far.id] = far
	# An unaided helper 26 m from a quiet survivor does not notice them.
	t.eq(helper.target_id, -1, "helper starts without a target")
	server.tick_count = 0
	server._tick_zombies(0.05)
	t.eq(source.target_id, 70, "scout independently finds survivor")
	t.eq(helper.target_id, 70, "neighboring infected receives peer target")
	t.eq(helper.state, Zombie.State.CHASE, "helper joins pursuit")
	t.eq(far.target_id, -1, "distant infected does not hear pack communication")

	t.current = "native pack broadphase matches unchanged server radius rules"
	var native_grid_available: bool = ClassDB.class_exists("AIProximityGrid2D")
	if native_grid_available:
		var grid: Object = ClassDB.instantiate("AIProximityGrid2D")
		var sites := PackedVector2Array([
			Vector2(-18.0, 0.0), Vector2(-0.1, 0.0),
			Vector2(0.1, 0.0), Vector2(-18.0, 18.0),
			Vector2(-36.0, 0.0), Vector2(-37.0, 0.0)])
		var sources := PackedInt32Array([0, 0, 3])
		var batches: Array = grid.query_radius_batch(sites, sources, 18.0, 18.0)
		t.eq(batches.size(), sources.size(), "one neighbor list for every source")
		for source_index in range(sources.size()):
			var expected := PackedInt32Array()
			for index in range(sites.size()):
				if index != sources[source_index] and sites[index].distance_squared_to(
						sites[sources[source_index]]) <= 18.0 * 18.0:
					expected.append(index)
			t.eq(batches[source_index], expected,
				"native broadphase matches brute force radius and original order")
		t.eq(batches[0], batches[1], "repeated source index remains deterministic")
		t.check(grid.query_radius_batch(sites, sources, 19.0, 18.0).is_empty(),
			"invalid cell size rejects entire batch")

	# The exact server logic is unchanged on old binaries and stock Godot:
	# a source wakes the neighbor within 18m, not one at 18.1m, and a
	# newly awakened neighbor cannot propagate the alert until next pass.
	var pack := GameServer.new(WorldGen.new(22), 22)
	var scout := Zombie.new(pack.new_id(), "walker", Vector3(-18, 0, 0))
	var near := Zombie.new(pack.new_id(), "walker", Vector3(-0.1, 0, 0))
	var outside := Zombie.new(pack.new_id(), "walker", Vector3(0.1, 0, 0))
	var tail := Zombie.new(pack.new_id(), "walker", Vector3(17.7, 0, 0))
	scout.target_id = 88
	scout.state = Zombie.State.CHASE
	pack.zombies[scout.id] = scout
	pack.zombies[near.id] = near
	pack.zombies[outside.id] = outside
	pack.zombies[tail.id] = tail
	var authorized := {88: {"position": Vector3(-15, 0, 0), "alive": true, "safe": false}}
	pack._alert_infected_pack(authorized)
	t.eq(near.target_id, 88, "adjacent cell receiver joins pack")
	t.eq(outside.target_id, -1, "candidate outside source radius remains asleep")
	t.eq(tail.target_id, -1, "newly recruited zombie never chain-wakes its neighbors")
	var nearest_native: bool = native_grid_available and ClassDB.class_has_method("AIProximityGrid2D", "query_nearest_batch")
	t.eq(bool(pack.last_pack_query_stats.get("native", false)), nearest_native,
		"native closest-K broadphase only runs on compatible engine builds")
	t.eq(int(pack.last_pack_query_stats.get("population", 0)), 4,
		"server diagnostic covers authoritative infected cohort")
	var fallback_pack := GameServer.new(WorldGen.new(22), 22)
	fallback_pack._pack_spatial_grid = RefCounted.new() # Simulate older fork.
	var old_scout := Zombie.new(fallback_pack.new_id(), "walker", Vector3(-18, 0, 0))
	var old_near := Zombie.new(fallback_pack.new_id(), "walker", Vector3(-0.1, 0, 0))
	var old_outside := Zombie.new(fallback_pack.new_id(), "walker", Vector3(0.1, 0, 0))
	old_scout.target_id = 88
	old_scout.state = Zombie.State.CHASE
	fallback_pack.zombies[old_scout.id] = old_scout
	fallback_pack.zombies[old_near.id] = old_near
	fallback_pack.zombies[old_outside.id] = old_outside
	fallback_pack._alert_infected_pack(authorized)
	t.eq(old_near.target_id, near.target_id, "script fallback wakes the same candidate")
	t.eq(old_outside.target_id, outside.target_id, "script fallback excludes the same distant actor")
	t.check(not bool(fallback_pack.last_pack_query_stats.get("native", false)),
		"old engine safely falls back to script broadphase")

	t.current = "nearest-K pack selection and dense crowd fanout"
	var sample := PackedVector2Array([
		Vector2.ZERO, Vector2(5, 0), Vector2(-5, 0),
		Vector2(1, 0), Vector2(2, 0), Vector2(3, 0), Vector2(-1, 0)])
	var candidate_ids: Array[int] = [5, 1, 6, 2, 4, 3]
	var chosen: PackedInt32Array = PackNeighborSelection.choose(sample, 0, candidate_ids, 18.0, 2)
	t.eq(chosen, PackedInt32Array([3, 6]), "script selects closest neighbors, independent of candidate order")
	t.eq(PackNeighborSelection.choose(sample, 0, candidate_ids, 18.0, 1),
		PackedInt32Array([3]), "equal-distance ties favor first input index")
	t.check(PackNeighborSelection.choose(sample, 0, candidate_ids, 18.0, 0).is_empty(),
		"invalid neighbor cap is rejected")
	if nearest_native:
		var query: Object = ClassDB.instantiate("AIProximityGrid2D")
		var source_ids := PackedInt32Array([0])
		var native_chosen: Array = query.query_nearest_batch(sample, source_ids, 18.0, 18.0, 2)
		t.eq(native_chosen[0], chosen, "native nearest neighbors equal script ranking")

	var dense := GameServer.new(WorldGen.new(22), 45)
	var leader := Zombie.new(dense.new_id(), "walker", Vector3(220, 0, 210))
	leader.target_id = 88
	leader.state = Zombie.State.CHASE
	dense.zombies[leader.id] = leader
	var followers: Dictionary = {}
	for distance in range(18, 0, -1): # Deliberately register farthest first.
		var npc := Zombie.new(dense.new_id(), "walker", Vector3(220.0 + distance, 0, 210))
		dense.zombies[npc.id] = npc
		followers[distance] = npc
	var authorized_dense := {88: {"position": Vector3(220, 0, 210), "alive": true, "safe": false}}
	dense._alert_infected_pack(authorized_dense)
	t.eq(int(dense.last_pack_query_stats.get("max_alerts", -1)),
		GameServer.ZOMBIE_PACK_MAX_ALERTS, "server enforces documented per-source cap")
	t.eq(int(dense.last_pack_query_stats.get("alerts_sent", -1)),
		GameServer.ZOMBIE_PACK_MAX_ALERTS, "at most nearest twelve NPCs are recruited")
	for distance in range(1, 19):
		t.eq(followers[distance].target_id,
			88 if distance <= GameServer.ZOMBIE_PACK_MAX_ALERTS else -1,
			"only closest allies awaken at distance %d" % distance)
	t.eq(bool(dense.last_pack_query_stats.get("native", false)), nearest_native,
		"engine/fallback paths report correct execution mode")

	var dense_fallback := GameServer.new(WorldGen.new(22), 45)
	dense_fallback._pack_spatial_grid = RefCounted.new() # Older engine without nearest query.
	var old_leader := Zombie.new(dense_fallback.new_id(), "walker", Vector3(220, 0, 210))
	old_leader.target_id = 88
	old_leader.state = Zombie.State.CHASE
	dense_fallback.zombies[old_leader.id] = old_leader
	var old_followers: Dictionary = {}
	for distance in range(18, 0, -1):
		var npc := Zombie.new(dense_fallback.new_id(), "walker", Vector3(220.0 + distance, 0, 210))
		dense_fallback.zombies[npc.id] = npc
		old_followers[distance] = npc
	dense_fallback._alert_infected_pack(authorized_dense)
	for distance in range(1, 19):
		t.eq(old_followers[distance].target_id, followers[distance].target_id,
			"old binary retains identical dense-pack targeting at distance %d" % distance)
	t.eq(dense_fallback.last_pack_query_stats["alerts_sent"],
		dense.last_pack_query_stats["alerts_sent"], "native and stock paths produce equal fanout")

	t.current = "safe hub and expired target"
	var protected = server.add_player(71, "Safe")
	protected.position = Vector3(0, world.height_at(0, 0), 0)
	var guard = Zombie.new(server.new_id(), "walker", Vector3(8, world.height_at(8, 0), 0))
	var wing = Zombie.new(server.new_id(), "walker", Vector3(19, world.height_at(19, 0), 0))
	server.zombies[guard.id] = guard
	server.zombies[wing.id] = wing
	server._tick_zombies(0.05)
	t.eq(guard.target_id, -1, "infected cannot recruit against survivor in safe hub")
	t.eq(wing.target_id, -1, "pack alert cannot bypass hub protection")
	survivor.survival.hurt(1000.0)
	server._tick_zombies(0.05)
	t.check(helper.target_id == -1 or helper.state == Zombie.State.IDLE, "dead target is dropped by recruited infected")

	t.current = "stuck infected wall target spatial grid"
	var walls: Dictionary = {
		12: {"x": 1.0, "z": 0.0, "piece": "wall"},
		14: {"x": 0.75, "z": 0.0, "piece": "wall"},
		15: {"x": -1.0, "z": 0.0, "piece": "wall"},
		16: {"x": 1.0, "z": 0.0, "piece": "floor"},
		17: {"x": 0.0, "z": 1.0, "piece": "roof"},
		18: {"x": 2.0, "z": 0.0, "piece": "door"},
	}
	var wall_index: Dictionary = ZombieWallAttackGrid.build(walls)
	var toward_wall := Vector2.RIGHT
	t.eq(ZombieWallAttackGrid.candidates(wall_index, Vector2.ZERO,
		toward_wall, 1.75), [12, 14],
		"closest attackers preserve wall insertion order, not distance ranking")
	t.eq(ZombieWallAttackGrid.candidates(wall_index, Vector2.ZERO,
		toward_wall, 2.0), [12, 14, 18],
		"targets exactly at the melee reach boundary remain eligible")
	t.eq(ZombieWallAttackGrid.candidates(wall_index, Vector2.ZERO,
		Vector2.LEFT, 1.75), [15], "no wall behind an infected is attacked")
	t.check(ZombieWallAttackGrid.candidates(wall_index, Vector2.ZERO,
		Vector2.ZERO, 1.75).is_empty(), "zero pursuit direction never damages walls")
	t.check(ZombieWallAttackGrid.candidates(wall_index, Vector2.ZERO,
		toward_wall, NAN).is_empty(), "bad query radius is rejected")
	t.check(ZombieWallAttackGrid.candidates(wall_index, Vector2(INF, 0.0),
		toward_wall, 1.75).is_empty(), "nonfinite infected coordinates cannot hit walls")
	# A wall can break after the grid is prepared; later infected must
	# skip its stale ID without accidentally attacking a dead object.
	walls.erase(12)
	var first_surviving_wall: int = -1
	for candidate_id in ZombieWallAttackGrid.candidates(
			wall_index, Vector2.ZERO, toward_wall, 1.75):
		if walls.has(candidate_id):
			first_surviving_wall = candidate_id
			break
	t.eq(first_surviving_wall, 14,
		"same-tick demolished walls are skipped while preserving survivor order")

	t.current = "dense wall targets match the legacy full scan"
	var random := RandomNumberGenerator.new()
	random.seed = 902741
	var packed_walls: Dictionary = {}
	for n in 220:
		var kind: String = "floor" if n % 17 == 0 else (
			"door" if n % 11 == 0 else "wall")
		packed_walls[1000 + n] = {
			"x": random.randf_range(-120.0, 120.0),
			"z": random.randf_range(-120.0, 120.0), "piece": kind}
	var indexed: Dictionary = ZombieWallAttackGrid.build(packed_walls)
	t.check((indexed["ids"] as Array).size() < packed_walls.size(),
		"nonblocking flooring is skipped before building the lookup table")
	for sample_index in 90:
		var at := Vector2(random.randf_range(-125.0, 125.0),
			random.randf_range(-125.0, 125.0))
		var direction := Vector2.from_angle(random.randf_range(0.0, TAU)) * 20.0
		var attack_reach: float = 1.75 if sample_index % 2 == 0 else 8.5
		t.eq(ZombieWallAttackGrid.candidates(indexed, at, direction, attack_reach),
			_brute_wall_targets(packed_walls, at, direction, attack_reach),
			"indexed attack %d keeps same targets and winner as old scan" % sample_index)
	packed_walls.erase(1000)
	var still_indexed: Array[int] = ZombieWallAttackGrid.candidates(
		indexed, Vector2.ZERO, Vector2.RIGHT, 80.0)
	for target_id in still_indexed:
		if not packed_walls.has(target_id):
			t.eq(target_id, 1000,
				"stale candidate IDs can only refer to already deleted walls")
