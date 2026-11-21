/**************************************************************************/
/*  test_smart_object_slot_reservations.h                                   */
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#pragma once

#include "../smart_object_slot_reservations.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestSmartObjectSlotReservations {

TEST_CASE("[SmartObjects] independent agents cannot occupy the same claimed slot") {
	Ref<SmartObjectSlotReservations> pool;
	pool.instantiate();
	const PackedInt64Array ids = { 101, 102, 103 };
	CHECK(pool->try_claim_first(ids, 1, 1.5) == 101);
	CHECK(pool->try_claim_first(ids, 2, 1.5) == 102);
	CHECK(pool->try_claim_first(ids, 3, 1.5) == 103);
	CHECK(pool->get_claim_count() == 3);
	CHECK(pool->try_claim_first(ids, 4, 1.5) == 0); // All requested slots occupied.
	CHECK(pool->get_owner(101) == 1);
	CHECK(pool->get_owner(102) == 2);
	CHECK_FALSE(pool->release_slot(101, 2)); // Another actor cannot steal it.
	CHECK(pool->get_owner(101) == 1);
	CHECK(pool->try_claim_first({ 103, 102, 101 }, 1, 1.5) == 101);
	CHECK(pool->get_claim_count() == 3); // Existing actor keeps its own slot.
	CHECK(pool->release_actor(1) == 1);
	CHECK(pool->try_claim_first(ids, 4, 1.5) == 101);
	CHECK(pool->release_slot(101, 4));
	CHECK(pool->get_owner(101) == 0);
}

TEST_CASE("[SmartObjects] moves an actor atomically, and reuses expired leases") {
	Ref<SmartObjectSlotReservations> pool;
	pool.instantiate();
	CHECK(pool->try_claim_first({ 10 }, 2, 1.0) == 10);
	CHECK(pool->try_claim_first({ 10 }, 3, 1.0) == 0);
	CHECK(pool->try_claim_first({ 11 }, 2, 1.0) == 11);
	CHECK(pool->get_owner(10) == 0);
	CHECK(pool->get_owner(11) == 2);
	CHECK(pool->try_claim_first({ 10 }, 3, 1.0) == 10);
	CHECK(pool->try_claim_first({ 10 }, 2, 1.0) == 0); // Losing actor keeps 11.
	CHECK(pool->get_owner(11) == 2);
	pool->advance_time(0.6);
	CHECK(pool->try_claim_first({ 11 }, 2, 1.0) == 11); // Renews.
	pool->advance_time(0.5);
	CHECK(pool->get_owner(10) == 0);
	CHECK(pool->get_owner(11) == 2);
	pool->advance_time(0.5);
	CHECK(pool->get_claim_count() == 0);
}

TEST_CASE("[SmartObjects] invalid arguments fail without partial reservation changes") {
	Ref<SmartObjectSlotReservations> pool;
	pool.instantiate();
	CHECK(pool->try_claim_first({ 7 }, 12, 1.0) == 7);
	CHECK(pool->try_claim_first({ 8, 8 }, 12, 1.0) == 0);
	CHECK(pool->try_claim_first({ 8, -1 }, 12, 1.0) == 0);
	CHECK(pool->try_claim_first({ 8 }, 0, 1.0) == 0);
	CHECK(pool->try_claim_first({ 8 }, 12, Math::NaN) == 0);
	CHECK(pool->try_claim_first({ 8 }, 12, Math::INF) == 0);
	CHECK(pool->try_claim_first({ 8 }, 12, 0.0) == 0);
	CHECK(pool->try_claim_first({ 8 }, 12, 5.1) == 0);
	CHECK(pool->get_owner(7) == 12);
	CHECK(pool->get_owner(8) == 0);
	pool->advance_time(Math::NaN);
	pool->advance_time(-1.0);
	CHECK(pool->get_owner(7) == 12);
	CHECK(pool->get_claim_count() == 1);
	pool->clear();
	CHECK(pool->get_claim_count() == 0);
}

TEST_CASE("[SmartObjects] atomic heartbeat renews a cached claim and protects occupied flanks") {
	Ref<SmartObjectSlotReservations> pool;
	pool.instantiate();
	CHECK(pool->try_claim_first_priority({ 101 }, 1, 1.0, 0) == 101);
	pool->advance_time(0.8);
	CHECK(pool->refresh_claim(101, 1, 1.5, true));
	CHECK(pool->get_owner(101) == 1);
	CHECK(pool->is_slot_occupied(101));
	CHECK(pool->try_claim_first_priority({ 101 }, 2, 1.5, 3) == 0); // Occupied cannot be stolen.
	pool->advance_time(1.0);
	CHECK(pool->get_owner(101) == 1); // Heartbeat extends the original 1s lease.
	CHECK_FALSE(pool->refresh_claim(101, 2, 1.0, false)); // Wrong actor cannot unlock it.
	CHECK(pool->is_slot_occupied(101));
	CHECK_FALSE(pool->refresh_claim(102, 1, 1.0, false)); // Incorrect slot is not a handle.
	CHECK(pool->refresh_claim(101, 1, 0.75, false)); // Moved away from position.
	CHECK_FALSE(pool->is_slot_occupied(101));
	CHECK(pool->try_claim_first_priority({ 101 }, 2, 1.5, 3) == 101);
	CHECK(pool->get_actor_slot(1) == 0);
	CHECK(pool->get_actor_slot(2) == 101);
	CHECK_FALSE(pool->refresh_claim(101, 1, 1.5, true)); // Old owner may not revive stolen slot.
	CHECK(pool->get_owner(101) == 2);
	CHECK_FALSE(pool->is_slot_occupied(101));
	CHECK(pool->refresh_claim(101, 2, 1.0, true));
	CHECK(pool->is_slot_occupied(101));
	pool->advance_time(1.0);
	CHECK(pool->get_owner(101) == 0); // Expired even if last state was occupied.
	CHECK_FALSE(pool->refresh_claim(101, 2, 1.0, true));
	CHECK(pool->get_claim_count() == 0);
}

TEST_CASE("[SmartObjects] heartbeat invalid requests never renew or mutate a live claim") {
	Ref<SmartObjectSlotReservations> pool;
	pool.instantiate();
	CHECK(pool->try_claim_first({ 55 }, 5, 0.5) == 55);
	CHECK_FALSE(pool->refresh_claim(0, 5, 1.0, true));
	CHECK_FALSE(pool->refresh_claim(-1, 5, 1.0, true));
	CHECK_FALSE(pool->refresh_claim(55, 0, 1.0, true));
	CHECK_FALSE(pool->refresh_claim(55, -1, 1.0, true));
	CHECK_FALSE(pool->refresh_claim(55, 5, 0.0, true));
	CHECK_FALSE(pool->refresh_claim(55, 5, -1.0, true));
	CHECK_FALSE(pool->refresh_claim(55, 5, Math::NaN, true));
	CHECK_FALSE(pool->refresh_claim(55, 5, Math::INF, true));
	CHECK_FALSE(pool->refresh_claim(55, 5, 5.001, true));
	CHECK(pool->get_claim_count() == 1);
	CHECK_FALSE(pool->is_slot_occupied(55));
	pool->advance_time(0.5);
	CHECK(pool->get_owner(55) == 0); // Invalid heartbeat did not prolong lease.
	CHECK_FALSE(pool->refresh_claim(55, 5, 1.0, true));
	CHECK(pool->try_claim_first({ 55 }, 6, 0.5) == 55);
	CHECK_FALSE(pool->refresh_claim(55, 5, 1.0, true));
	CHECK(pool->release_actor(6) == 1);
	CHECK_FALSE(pool->refresh_claim(55, 6, 1.0, false));
}

TEST_CASE("[SmartObjects] bounded table rejects overflow and retains atomic reclaims") {
	Ref<SmartObjectSlotReservations> pool;
	pool.instantiate();
	for (int i = 1; i <= SmartObjectSlotReservations::MAX_ACTIVE_CLAIMS; ++i) {
		PackedInt64Array ids;
		ids.push_back(i);
		REQUIRE(pool->try_claim_first(ids, i, 1.0) == i);
	}
	CHECK(pool->get_claim_count() == SmartObjectSlotReservations::MAX_ACTIVE_CLAIMS);
	CHECK(pool->try_claim_first({ 99999 }, 99999, 1.0) == 0);
	CHECK(pool->try_claim_first({ 20000 }, 100, 1.0) == 20000);
	CHECK(pool->get_claim_count() == SmartObjectSlotReservations::MAX_ACTIVE_CLAIMS);
	CHECK(pool->get_owner(100) == 0);
	CHECK(pool->get_owner(20000) == 100);
	pool->advance_time(1.0);
	CHECK(pool->get_claim_count() == 0);
}


TEST_CASE("[SmartObjects] hashed claim indices survive swap removal, migration and expiry") {
	Ref<SmartObjectSlotReservations> pool;
	pool.instantiate();
	for (int64_t actor = 1; actor <= 256; ++actor) {
		CHECK(pool->try_claim_first({ 10000 + actor }, actor, 1.0) == 10000 + actor);
	}
	CHECK(pool->get_claim_count() == 256);
	CHECK(pool->get_actor_slot(0) == 0);
	CHECK(pool->get_actor_slot(257) == 0);
	// Swap-delete every third reservation; moved-back claims must update BOTH maps.
	for (int64_t actor = 1; actor <= 256; actor += 3) {
		CHECK(pool->release_actor(actor) == 1);
		CHECK(pool->get_owner(10000 + actor) == 0);
		CHECK(pool->get_actor_slot(actor) == 0);
	}
	for (int64_t actor = 1; actor <= 256; ++actor) {
		if ((actor - 1) % 3 == 0) {
			continue;
		}
		CHECK(pool->get_actor_slot(actor) == 10000 + actor);
		CHECK(pool->get_owner(10000 + actor) == actor);
	}
	// An already indexed actor switches slots without changing claim count.
	const int before = pool->get_claim_count();
	CHECK(pool->try_claim_first({ 100000 }, 2, 0.9) == 100000);
	CHECK(pool->get_actor_slot(2) == 100000);
	CHECK(pool->get_owner(10002) == 0);
	CHECK(pool->get_owner(100000) == 2);
	CHECK(pool->get_claim_count() == before);
	CHECK(pool->try_claim_first({ 100001, 100000 }, 2, 1.0) == 100000); // Retain owned.
	CHECK(pool->release_slot(100000, 2));
	CHECK(pool->get_actor_slot(2) == 0);
	// Expiry removes arbitrary positions after swaps and leaves no stale map keys.
	pool->advance_time(1.0);
	CHECK(pool->get_claim_count() == 0);
	for (int64_t actor = 1; actor <= 256; ++actor) {
		CHECK(pool->get_actor_slot(actor) == 0);
		CHECK(pool->get_owner(10000 + actor) == 0);
	}
	CHECK(pool->try_claim_first({ 10005 }, 500, 1.0) == 10005);
	pool->clear();
	CHECK(pool->get_actor_slot(500) == 0);
	CHECK(pool->get_owner(10005) == 0);
	CHECK(pool->get_claim_count() == 0);
}

TEST_CASE("[SmartObjects] priority preempts pending slots, but never active interaction") {
	Ref<SmartObjectSlotReservations> pool;
	pool.instantiate();
	CHECK(pool->try_claim_first_priority({ 100, 101 }, 1, 2.0, 0) == 100);
	CHECK(pool->try_claim_first_priority({ 100, 101 }, 2, 2.0, 0) == 101);
	CHECK(pool->try_claim_first_priority({ 100, 101 }, 3, 2.0, 2) == 100);
	CHECK(pool->get_owner(100) == 3);
	CHECK(pool->get_actor_slot(3) == 100);
	CHECK(pool->get_actor_slot(1) == 0);
	CHECK(pool->get_owner(101) == 2);
	CHECK(pool->get_claim_count() == 2);
	CHECK(pool->try_claim_first({ 100, 101 }, 1, 2.0) == 0); // Legacy cannot steal.
	CHECK(pool->set_slot_occupied(100, 3, true));
	CHECK(pool->is_slot_occupied(100));
	CHECK_FALSE(pool->set_slot_occupied(100, 1, false)); // Owner only.
	CHECK(pool->try_claim_first_priority({ 100, 101 }, 4, 2.0, 3) == 101);
	CHECK(pool->get_owner(100) == 3); // Occupied is protected.
	CHECK(pool->get_owner(101) == 4);
	CHECK(pool->try_claim_first_priority({ 100, 101 }, 5, 2.0, 3) == 0);
	CHECK(pool->set_slot_occupied(100, 3, false));
	CHECK(pool->try_claim_first_priority({ 100, 101 }, 5, 2.0, 3) == 100);
	CHECK_FALSE(pool->is_slot_occupied(100));
	CHECK_FALSE(pool->is_slot_occupied(9999));
}

TEST_CASE("[SmartObjects] priority transfer and invalid input are atomic") {
	Ref<SmartObjectSlotReservations> pool;
	pool.instantiate();
	CHECK(pool->try_claim_first_priority({ 10 }, 1, 2.0, 2) == 10);
	CHECK(pool->try_claim_first_priority({ 20 }, 2, 2.0, 0) == 20);
	CHECK(pool->set_slot_occupied(10, 1, true));
	CHECK(pool->try_claim_first_priority({ 10 }, 2, 2.0, 3) == 0);
	CHECK(pool->get_owner(20) == 2);
	CHECK(pool->try_claim_first_priority({ 20 }, 2, 2.0, 4) == 0);
	CHECK(pool->try_claim_first_priority({ 20, 20 }, 2, 2.0, 3) == 0);
	CHECK(pool->try_claim_first_priority({ 10, -3 }, 2, 2.0, 3) == 0);
	CHECK(pool->get_owner(20) == 2);
	CHECK(pool->try_claim_first_priority({ 20 }, 2, 2.0, 1) == 20);
	CHECK(pool->try_claim_first_priority({ 20 }, 3, 2.0, 0) == 0);
	CHECK(pool->set_slot_occupied(10, 1, false));
	CHECK(pool->try_claim_first_priority({ 10 }, 2, 2.0, 3) == 10);
	CHECK(pool->get_owner(20) == 0); // Own old claim relinquished only on success.
	CHECK(pool->get_claim_count() == 1);
	pool->advance_time(2.0);
	CHECK(pool->get_claim_count() == 0);
}

} // namespace TestSmartObjectSlotReservations
