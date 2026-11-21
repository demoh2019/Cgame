/**************************************************************************/
/*  smart_object_slot_reservations.h                                       */
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#pragma once

#include "core/object/ref_counted.h"
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
	};
	Vector<Claim> claims;

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
	// A release with a wrong actor ID cannot steal another actor's claim.
	bool release_slot(int64_t p_slot_id, int64_t p_actor_id);
	int release_actor(int64_t p_actor_id);
	void advance_time(double p_delta);
	void clear();
	int64_t get_owner(int64_t p_slot_id) const;
	int get_claim_count() const { return claims.size(); }
};
