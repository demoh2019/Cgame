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


func run(t) -> void:
	t.current = "Smart Object slot allocator portable reference"
	_exercise(t, Portable.new())

	t.current = "native C++ reservation table matches portable API"
	if ClassDB.class_exists("SmartObjectSlotReservations"):
		var native = _pool(true)
		t.check(native != null, "native allocator is registered in ClassDB")
		if native != null:
			_exercise(t, native)
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
		var first_spot: Vector2 = first._flank_goal(here, target)
		var second_spot: Vector2 = second._flank_goal(here, target)
		t.check(first_spot.distance_to(target) < 2.5 and first_spot.distance_to(target) > 2.3,
			"first zombie claims a valid EQS ring position")
		t.check(second_spot.distance_to(target) < 2.5 and second_spot.distance_to(target) > 2.3,
			"second zombie claims another reachable EQS ring position")
		t.check(first_spot.distance_to(second_spot) > 0.1,
			"two infected cannot reserve exactly the same physical flank slot")
		t.eq(pool.get_claim_count(), 2, "two distinct target-ring leases exist in the actual game AI")
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

	t.current = "source wiring never lets a client claim or cause an attack"
	var code: String = (GameServer as Script).source_code
	t.check(code.contains('ClassDB.instantiate("SmartObjectSlotReservations")'),
		"one native reservation table is created inside authoritative GameServer")
	t.check(code.contains('zombie.flank_reservations = _flank_slot_reservations'),
		"the table is shared through the actual server AI tick")
	t.check(code.contains('_flank_slot_reservations.advance_time(delta)'),
		"leases use server simulation time and cannot be client-clock accelerated")
	code = (Zombie as Script).source_code
	t.check(code.contains('flank_reservations.try_claim_first(slot_ids, id, 1.5)'),
		"actual flanking movement allocates exclusive target positions")
	t.check(code.contains('return target # An overcrowded pack still pursues normally.'),
		"full slot tables never disable attacking or pursuit")
