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

} // namespace TestSmartObjectSlotReservations
