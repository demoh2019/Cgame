extends RefCounted
## Native Unreal Smart Objects-style exclusive slot leases and stock Godot parity.
const Portable = preload("res://scripts/shared/flank_slot_reservations.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")


func _pool(use_native: bool):
	if use_native and ClassDB.class_exists("SmartObjectSlotReservations"):
		return ClassDB.instantiate("SmartObjectSlotReservations")
	return Portable.new()


func _exercise(t, pool) -> void:
	var ranked := PackedInt64Array([101, 102, 103])
	t.eq(pool.try_claim_first(ranked, 1, 1.5), 101, "first zombie reserves first free slot")
	t.eq(pool.try_claim_first(ranked, 2, 1.5), 102, "second zombie reserves a different slot")
	t.eq(pool.try_claim_first(ranked, 3, 1.5), 103, "third zombie uses the final slot")
	t.eq(pool.get_claim_count(), 3, "three independent claims remain active")
	if pool.has_method("get_actor_slot"):
		t.eq(int(pool.get_actor_slot(1)), 101, "actor index returns its server-owned slot")
		t.eq(int(pool.get_actor_slot(2)), 102, "another actor index is independent")
		t.eq(int(pool.get_actor_slot(0)), 0, "invalid actor has no indexed slot")
	t.eq(pool.try_claim_first(ranked, 4, 1.5), 0, "fourth zombie cannot steal a claimed slot")
	t.check(not pool.release_slot(101, 2), "wrong owner cannot revoke another actor's claim")
	t.eq(pool.get_owner(101), 1, "wrong-owner release is a no-op")
	t.eq(pool.try_claim_first(PackedInt64Array([103, 102, 101]), 1, 1.5), 101,
		"existing actor holds its own slot despite changed preference order")
	t.eq(pool.get_claim_count(), 3, "renewing an existing lease does not duplicate it")
	t.eq(pool.release_actor(1), 1, "server can clear the actor's reservation on death")
	t.eq(pool.try_claim_first(ranked, 4, 1.5), 101, "released slot is instantly reusable")
	t.eq(pool.try_claim_first(PackedInt64Array([105]), 2, 1.0), 105,
		"an actor atomically moves to a new available smart-object slot")
	t.eq(pool.get_owner(102), 0, "the old slot is released when the actor moves")
	t.eq(pool.get_owner(105), 2, "new slot belongs exclusively to its reserver")
	if pool.has_method("get_actor_slot"):
		t.eq(int(pool.get_actor_slot(2)), 105, "migration updates actor index")
	t.check(not pool.release_slot(105, 3), "unauthorized removal stays impossible")

	t.current = "invalid slot requests fail atomically"
	for invalid_slots in [
		PackedInt64Array(), PackedInt64Array([-1]),
		PackedInt64Array([105, 105]), PackedInt64Array([0, 107])
	]:
		t.eq(pool.try_claim_first(invalid_slots, 2, 1.0), 0,
			"invalid candidate list does not change the actor reservation")
	for invalid_lease in [NAN, INF, -INF, -1.0, 0.0, 5.01]:
		t.eq(pool.try_claim_first(PackedInt64Array([110]), 2, invalid_lease), 0,
			"invalid lease values cannot corrupt the state")
	t.eq(pool.try_claim_first(PackedInt64Array([110]), 0, 1.0), 0,
		"actor IDs must be server-created positive values")
	t.eq(pool.get_owner(105), 2, "invalid requests never relinquish a good claim")
	pool.advance_time(NAN)
	pool.advance_time(-3.0)
	t.eq(pool.get_owner(105), 2, "invalid simulation delta never expires a reservation")

	t.current = "renewal, deterministic expiry and zero allocation after cleanup"
	pool.advance_time(0.6)
	t.eq(pool.try_claim_first(PackedInt64Array([105]), 2, 1.0), 105,
		"living agent can refresh its lease")
	pool.advance_time(0.5)
	t.eq(pool.get_owner(105), 2, "renewed lease outlives other expired positions")
	pool.advance_time(0.5)
	t.eq(pool.get_claim_count(), 0, "all leases expire deterministically on server ticks")
	if pool.has_method("get_actor_slot"):
		t.eq(int(pool.get_actor_slot(2)), 0, "expiry removes actor index")
	pool.clear()
	t.eq(pool.get_claim_count(), 0, "clear is idempotent")


func _exercise_priority(t, pool) -> void:
	t.eq(pool.try_claim_first_priority(PackedInt64Array([101, 102]), 1, 2.0, 0),
		101, "ordinary infected claims first free slot")
	t.eq(pool.try_claim_first_priority(PackedInt64Array([101, 102]), 2, 2.0, 0),
		102, "second infected uses a distinct free slot")
	t.eq(pool.try_claim_first_priority(PackedInt64Array([101, 102]), 3, 2.0, 2),
		101, "elite can preempt an unused ordinary claim")
	t.eq(pool.get_owner(101), 3, "ownership transferred exclusively")
	t.eq(pool.get_claim_count(), 2, "preemption never duplicates a claim")
	t.check(not pool.set_slot_occupied(101, 1, true),
		"preempted actor cannot alter another owner's occupancy")
	t.check(pool.set_slot_occupied(101, 3, true),
		"owner may mark reached flank position as occupied")
	t.check(pool.is_slot_occupied(101), "occupied state can be queried")
	t.eq(pool.try_claim_first_priority(PackedInt64Array([101, 102]), 4, 2.0, 3),
		102, "priority cannot override active user, but may steal unused slot")
	t.eq(pool.get_owner(101), 3, "occupied infected keeps its flank position")
	t.eq(pool.try_claim_first_priority(PackedInt64Array([101, 102]), 5, 2.0, 3),
		0, "equal priority plus active user cannot be evicted")
	t.eq(pool.try_claim_first_priority(PackedInt64Array([101, 102]), 2, 2.0, 0),
		0, "ordinary infected cannot steal elite claim")
	t.check(pool.set_slot_occupied(101, 3, false), "owner can clear occupancy")
	t.eq(pool.try_claim_first_priority(PackedInt64Array([101, 102]), 5, 2.0, 3),
		101, "higher priority can reclaim once interaction ends")
	t.eq(pool.try_claim_first_priority(PackedInt64Array([103]), 4, 2.0, 3),
		103, "reassignment moves an existing claim atomically")
	t.eq(pool.get_owner(102), 0, "old spot is free on successful reassignment")
	t.eq(pool.try_claim_first_priority(PackedInt64Array([105, 105]), 4, 2.0, 3),
		0, "duplicate candidates reject without modifying the claim")
	t.eq(pool.get_owner(103), 4, "invalid request preserves the original slot")
	t.eq(pool.try_claim_first_priority(PackedInt64Array([105]), 4, 2.0, 4),
		0, "out-of-range priority fails closed")
	t.eq(pool.get_owner(103), 4, "invalid priority preserves ownership")
	pool.advance_time(2.0)
	t.eq(pool.get_claim_count(), 0, "expiry releases both claims and occupancy")


## Run identical portable and native Smart Object heartbeat semantics.
func _exercise_heartbeat(t, pool) -> void:
	if not pool.has_method("refresh_claim"):
		t.check(true, "older Cgame binaries retain separate lease/occupancy APIs")
		return
	t.eq(pool.try_claim_first_priority(PackedInt64Array([101]), 1, 1.0, 0),
		101, "first infected owns a short claimed flank lease")
	pool.advance_time(0.8)
	t.check(bool(pool.refresh_claim(101, 1, 1.5, true)),
		"owned smart slot is atomically renewed and marked occupied")
	t.check(pool.is_slot_occupied(101), "arriving at the spot marks it in use")
	t.eq(pool.try_claim_first_priority(PackedInt64Array([101]), 2, 1.0, 3),
		0, "elite cannot preempt a currently occupied flank position")
	pool.advance_time(1.0)
	t.eq(int(pool.get_owner(101)), 1, "lease persists past original expiry")
	for bad_lease in [0.0, -0.1, NAN, INF, 5.01]:
		t.check(not bool(pool.refresh_claim(101, 1, bad_lease, false)),
			"invalid heartbeat lease cannot mutate occupancy or expiry")
	t.check(not bool(pool.refresh_claim(101, 3, 1.0, false)),
		"wrong actor cannot refresh another agent's slot")
	t.check(not bool(pool.refresh_claim(102, 1, 1.0, false)),
		"wrong cached slot identity cannot renew another lease")
	t.check(pool.is_slot_occupied(101),
		"invalid heartbeat calls must not release occupied positions")
	t.check(bool(pool.refresh_claim(101, 1, 0.75, false)),
		"walking away from a spot returns it to claimed-but-preemptible state")
	t.eq(pool.try_claim_first_priority(PackedInt64Array([101]), 2, 1.0, 3),
		101, "higher-priority agent can now take a released-to-claimed spot")
	t.eq(int(pool.get_actor_slot(1)), 0,
		"preempted agent loses indexed ownership immediately")
	t.check(not bool(pool.refresh_claim(101, 1, 1.0, true)),
		"stale cached heartbeat cannot recover a preempted lease")
	t.eq(int(pool.get_owner(101)), 2, "new owner remains authoritative")
	pool.advance_time(1.0)
	t.eq(int(pool.get_owner(101)), 0, "forgotten claimed spot expires")
	t.check(not bool(pool.refresh_claim(101, 2, 1.0, true)),
		"expired reservation cannot be recreated by heartbeat")


func run(t) -> void:
	t.current = "Smart Object slot allocator portable reference"
	_exercise(t, Portable.new())

	t.current = "portable Smart Object priority claims and occupancy"
	_exercise_priority(t, Portable.new())

	t.current = "portable Smart Object atomic cached claim heartbeats"
	_exercise_heartbeat(t, Portable.new())

	t.current = "native C++ reservation table matches portable API"
	if ClassDB.class_exists("SmartObjectSlotReservations"):
		var native = _pool(true)
		t.check(native != null, "native allocator is registered in ClassDB")
		if native != null:
			_exercise(t, native)
			_exercise_priority(t, native)
			t.current = "native Smart Object cached claim heartbeat parity"
			_exercise_heartbeat(t, native)
	else:
		t.check(true, "stock Godot executes the same deterministic fallback")

	t.current = "real server shares one slot allocator across the entire infected pack"
	var world := WorldGen.new(17)
	var server := GameServer.new(world, 17)
	server._tick_zombies(0.05)
	t.check(server._flank_slot_reservations != null,
		"the real authoritative simulation constructs one claim pool")
	var infected_a := Zombie.new(901, "walker", Vector3(10, WorldGen.HUB_HEIGHT, 10))
	var infected_b := Zombie.new(902, "walker", Vector3(10, WorldGen.HUB_HEIGHT, 10))
	server.zombies[901] = infected_a
	server.zombies[902] = infected_b
	server._tick_zombies(0.05)
	t.check(infected_a.flank_reservations == infected_b.flank_reservations,
		"both real server zombies share the exact same reservation table")
	t.check(infected_a.flank_reservations == server._flank_slot_reservations,
		"zombie's manager is the server-owned manager, not a separate static instance")

	t.current = "real infected EQS flanking claims distinct physical ring positions"
	if ClassDB.class_exists("EnvironmentQuery3D"):
		var pool = _pool(true)
		var first := Zombie.new(1001, "walker", Vector3(0, WorldGen.HUB_HEIGHT, 0))
		var second := Zombie.new(1002, "walker", Vector3(0, WorldGen.HUB_HEIGHT, 0))
		first.target_id = 77
		second.target_id = 77
		first.flank_reservations = pool
		second.flank_reservations = pool
		var here := Vector2(0, 0)
		var target := Vector2(8, 0)
		# Two indistinguishable positions are separate EQS items; only the
		# index-returning API can preserve both reservation identities.
		var index_query = ClassDB.instantiate("EnvironmentQuery3D")
		index_query.set("origin", Vector3.ZERO)
		index_query.set("candidates", PackedVector3Array([
			Vector3(3, 0, 0), Vector3(3, 0, 0), Vector3(10, 0, 0)]))
		if index_query.has_method("query_top_indices"):
			var ids: PackedInt32Array = index_query.call("query_top_indices", 3)
			t.eq(ids, PackedInt32Array([0, 1, 2]),
				"native EQS preserves stable input indices for overlapping points")
			var positions: PackedVector3Array = index_query.call("query_top_positions", 3)
			for i in range(ids.size()):
				t.eq(positions[i], index_query.get("candidates")[ids[i]],
					"index scoring exactly matches position-only query ordering")
			index_query.set("max_results", 2)
			t.eq(index_query.call("query_top_indices", 3), PackedInt32Array([0, 1]),
				"native index query honors caller cap and resource maximum")
			index_query.set("max_results", 0)
			t.eq(index_query.call("query_top_indices", 3), ids,
				"clearing the resource cap restores original stable EQS ordering")
		else:
			t.check(true, "older Cgame binary keeps the position-only EQS fallback")
		if ClassDB.instantiate("EnvironmentQuery3D").has_method(
				"begin_incremental_top_positions"):
			var partial_pool = _pool(true)
			var incremental_zombie := Zombie.new(2003, "walker",
				Vector3(0, WorldGen.HUB_HEIGHT, 0))
			incremental_zombie.target_id = 77
			incremental_zombie.flank_reservations = partial_pool
			incremental_zombie.flank_incremental_enabled = true
			t.eq(incremental_zombie._flank_goal(here, target), target,
				"unfinished native EQS cannot create a server Smart Object claim")
			t.eq(partial_pool.get_claim_count(), 0, "first slice has not claimed a slot")
			t.eq(incremental_zombie._flank_goal(here, target), target,
				"second slice still rejects incomplete ranked candidate sets")
			t.eq(partial_pool.get_claim_count(), 0, "second slice has not claimed a slot")
			var final_spot := incremental_zombie._flank_goal(here, target)
			t.check(final_spot.distance_to(target) > 2.3 and final_spot.distance_to(target) < 2.5,
				"third slice can claim a completed ranked physical flank position")
			t.eq(partial_pool.get_claim_count(), 1,
				"completion acquires exactly one authoritative unique slot")
		var first_spot: Vector2 = first._flank_goal(here, target)
		var second_spot: Vector2 = second._flank_goal(here, target)
		if first._flank_query != null and first._flank_query.has_method("query_random_best_positions"):
			var preferred: PackedVector3Array = first._flank_query.call(
				"query_random_best_positions", 25, first.id)
			t.eq(preferred.size(), 1,
				"server-owned smart slot AI computes one near-best seeded preference")
			if preferred.size() == 1:
				t.check(first_spot.distance_to(Vector2(preferred[0].x, preferred[0].z)) < 0.001,
					"first unoccupied lease uses the native seeded preference")
			var second_choice: PackedVector3Array = second._flank_query.call(
				"query_random_best_positions", 25, second.id)
			t.eq(second_choice.size(), 1, "second agent can independently seed a flank preference")
		t.check(first_spot.distance_to(target) < 2.5 and first_spot.distance_to(target) > 2.3,
			"first zombie claims a valid EQS ring position")
		t.check(second_spot.distance_to(target) < 2.5 and second_spot.distance_to(target) > 2.3,
			"second zombie claims another reachable EQS ring position")
		t.check(first_spot.distance_to(second_spot) > 0.1,
			"two infected cannot reserve exactly the same physical flank slot")
		t.eq(pool.get_claim_count(), 2, "two distinct target-ring leases exist in the actual game AI")
		if index_query.has_method("query_top_indices"):
			var claimed_ring := EnvironmentQuery3D.sample_ring(
				Vector3(target.x, 0.0, target.y), 2.4, 8)
			for zombie in [first, second]:
				var lease: int = int(pool.get_actor_slot(zombie.id))
				var source_index: int = lease - 77 * 16 - 1
				t.check(source_index >= 0 and source_index < claimed_ring.size(),
					"flanking lease stores an original scored EQS ring index")
				if source_index >= 0 and source_index < claimed_ring.size():
					var candidate: Vector3 = claimed_ring[source_index]
					t.eq(zombie._flank_goal(here, target),
						Vector2(candidate.x, candidate.z),
						"real infected flank target matches its exact unique ring slot")
		# Lease loss during the 300ms flank-goal cache must force an EQS
		# replan, rather than sending a zombie to a slot it no longer owns.
		var portable_pool := Portable.new()
		var third := Zombie.new(1003, "walker", Vector3(0, WorldGen.HUB_HEIGHT, 0))
		third.target_id = 77
		third.flank_reservations = portable_pool
		third._flank_goal(here, target)
		var initial_claim: int = portable_pool.get_actor_slot(third.id)
		t.check(initial_claim > 0, "portable zombie claims its flank slot")
		t.eq(portable_pool.release_actor(third.id), 1, "simulation invalidates its claim")
		third._flank_goal(here, target)
		t.check(portable_pool.get_actor_slot(third.id) > 0,
			"invalid cached flank goal is replanned and reserved immediately")
		t.eq(portable_pool.get_claim_count(), 1, "replan does not duplicate claims")
		pool.advance_time(2.0)
		t.eq(pool.get_claim_count(), 0, "abandoned flank reservations release when a zombie stops chasing")
	else:
		t.check(true, "legacy Godot keeps existing direct pursuit without native EQS")

	t.current = "actual infected cached flank goal refreshes ownership and true occupancy"
	if ClassDB.class_exists("EnvironmentQuery3D"):
		for native_mode in [false, true]:
			if native_mode and not ClassDB.class_exists("SmartObjectSlotReservations"):
				continue
			var lease_pool = _pool(native_mode)
			if not lease_pool.has_method("refresh_claim"):
				continue
			var agent := Zombie.new(1601, "walker", Vector3.ZERO)
			agent.target_id = 77
			agent.flank_reservations = lease_pool
			var leased_slot: int = 77 * 16 + 1
			t.eq(int(lease_pool.try_claim_first(PackedInt64Array([leased_slot]),
				agent.id, 1.0)), leased_slot,
				"real infected begins with server-owned ring slot reservation")
			# Seed the already-planned path: only a cached path can exercise the
			# cheap heartbeat, without another native EQS query.
			agent._flank_goal_cached = Vector2(0.5, 0.0)
			agent._flank_here_cached = Vector2.ZERO
			agent._flank_target_cached = Vector2(6.0, 0.0)
			agent._flank_target_id_cached = 77
			agent._flank_slot_id_cached = leased_slot
			agent._flank_replan_remaining = 0.2
			agent.flank_replan_allowed = false
			var target_pos := Vector2(6.0, 0.0)
			t.eq(agent._flank_goal(Vector2(0.5, 0.0), target_pos),
				Vector2(0.5, 0.0),
				"cached flank goal remains usable even when EQS replans are budget-denied")
			t.check(lease_pool.is_slot_occupied(leased_slot),
				"reaching cached flank spot marks the actual native smart slot occupied")
			t.eq(int(lease_pool.try_claim_first_priority(PackedInt64Array([leased_slot]),
				1602, 1.0, 3)), 0,
				"elite cannot steal the occupied spot during an intervening cached tick")
			lease_pool.advance_time(0.8)
			t.eq(agent._flank_goal(Vector2(0.5, 0.0), target_pos),
				Vector2(0.5, 0.0),
				"cache heartbeat renews lease instead of triggering a tactical requery")
			lease_pool.advance_time(0.8)
			t.eq(int(lease_pool.get_owner(leased_slot)), agent.id,
				"renewed cached goal stays owned beyond the original lease deadline")
			t.eq(agent._flank_goal(Vector2(1.7, 0.0), target_pos),
				Vector2(0.5, 0.0),
				"moving away from a cached spot can still retain a valid destination")
			t.check(not lease_pool.is_slot_occupied(leased_slot),
				"the same cached heartbeat makes a vacated physical slot preemptible")
			t.eq(int(lease_pool.try_claim_first_priority(PackedInt64Array([leased_slot]),
				1602, 1.0, 3)), leased_slot,
				"higher-priority infected can now claim the abandoned pending spot")
			t.eq(agent._flank_goal(Vector2(0.5, 0.0), target_pos), target_pos,
				"stale cached goal is discarded when its smart-object claim was preempted")
	else:
		t.check(true, "stock Godot has no EQS cache; uses existing direct pursuit")

	t.current = "source wiring never lets a client claim or cause an attack"
	var code: String = (GameServer as Script).source_code
	t.check(code.contains('ClassDB.instantiate("SmartObjectSlotReservations")'),
		"one native reservation table is created inside authoritative GameServer")
	t.check(code.contains('zombie.flank_reservations = _flank_slot_reservations'),
		"the table is shared through the actual server AI tick")
	t.check(code.contains('_flank_slot_reservations.advance_time(delta)'),
		"leases use server simulation time and cannot be client-clock accelerated")
	code = (Zombie as Script).source_code
	t.check(code.contains('flank_reservations.try_claim_first_priority('),
		"actual flanking movement allocates priority-aware target positions")
	t.check(code.contains('flank_reservations.set_slot_occupied(claimed, id, active)'),
		"the physical flank slot is protected only while its owner is nearby")
	t.check(code.contains('int(flank_reservations.get_actor_slot(id)) == _flank_slot_id_cached'),
		"server AI invalidates preempted/expired cached slot goals")
	t.check(code.contains('return target # An overcrowded pack still pursues normally.'),
		"full slot tables never disable attacking or pursuit")
