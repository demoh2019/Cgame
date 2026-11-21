/**************************************************************************/
/*  smart_object_slot_reservations.h                                       */
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#pragma once

#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/templates/vector.h"
#include "core/variant/variant.h"

// Reusable slot claim and lease lifetime manager, inspired by Unreal Smart
// Objects. The server derives valid slot IDs, positions and actor IDs. The
// native allocator intentionally does not move actors, query physics, or
// choose authoritative actions. It only enforces exclusive slot claims.
class SmartObjectSlotReservations : public RefCounted {
	GDCLASS(SmartObjectSlotReservations, RefCounted);

public:
	static constexpr int MAX_ACTIVE_CLAIMS = 2048;
	static constexpr int MAX_CANDIDATES = 16;
	static constexpr double MAX_LEASE_SECONDS = 5.0;

private:
	struct Claim {
		int64_t slot_id = 0;
		int64_t actor_id = 0;
		double remaining = 0.0;
		int priority = 0;
		bool occupied = false;
	};
	Vector<Claim> claims;
	// Native server hot path: indexed slot and actor lookup. Both indices
	// follow swap-removals; at most MAX_ACTIVE_CLAIMS entries are stored.
	HashMap<int64_t, int> slot_indices;
	HashMap<int64_t, int> actor_indices;

	void _erase_claim(int p_index);
	int _find_slot(int64_t p_slot_id) const;
	int _find_actor(int64_t p_actor_id) const;

protected:
	static void _bind_methods();

public:
	// Attempts the existing actor-owned candidate first; otherwise takes the
	// first free candidate in the supplied deterministic order. Reassigning
	// an actor atomically relinquishes its old slot only after a free candidate
	// is found. Zero signals no available slot or invalid input.
	int64_t try_claim_first(const PackedInt64Array &p_slot_ids, int64_t p_actor_id, double p_lease_seconds);
	// Higher-priority (0..3) agents can preempt only claimed-but-not-occupied
	// lower-priority slots when no free candidate exists.
	int64_t try_claim_first_priority(const PackedInt64Array &p_slot_ids,
			int64_t p_actor_id, double p_lease_seconds, int p_priority);
	bool set_slot_occupied(int64_t p_slot_id, int64_t p_actor_id, bool p_occupied);
	bool is_slot_occupied(int64_t p_slot_id) const;
	// A release with a wrong actor ID cannot steal another actor's claim.
	bool release_slot(int64_t p_slot_id, int64_t p_actor_id);
	int release_actor(int64_t p_actor_id);
	void advance_time(double p_delta);
	void clear();
	int64_t get_owner(int64_t p_slot_id) const;
	// 0 if absent, otherwise the slot currently leased by this actor.
	int64_t get_actor_slot(int64_t p_actor_id) const;
	int get_claim_count() const { return claims.size(); }
};
