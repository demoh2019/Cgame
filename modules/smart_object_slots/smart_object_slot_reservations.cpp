/**************************************************************************/
/*  smart_object_slot_reservations.cpp                                     */
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#include "smart_object_slot_reservations.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

int SmartObjectSlotReservations::_find_slot(int64_t p_slot_id) const {
	for (int i = 0; i < claims.size(); ++i) {
		if (claims[i].slot_id == p_slot_id) {
			return i;
		}
	}
	return -1;
}

int SmartObjectSlotReservations::_find_actor(int64_t p_actor_id) const {
	for (int i = 0; i < claims.size(); ++i) {
		if (claims[i].actor_id == p_actor_id) {
			return i;
		}
	}
	return -1;
}

int64_t SmartObjectSlotReservations::try_claim_first(const PackedInt64Array &p_slot_ids,
		int64_t p_actor_id, double p_lease_seconds) {
	if (p_actor_id <= 0 || p_slot_ids.is_empty() ||
			p_slot_ids.size() > MAX_CANDIDATES ||
			!Math::is_finite(p_lease_seconds) ||
			p_lease_seconds <= 0.0 || p_lease_seconds > MAX_LEASE_SECONDS) {
		return 0;
	}
	// Validate the complete preference list before changing anything. Actor
	// must provide server-created positive IDs; malformed requests fail closed.
	for (int i = 0; i < p_slot_ids.size(); ++i) {
		if (p_slot_ids[i] <= 0) {
			return 0;
		}
		for (int j = 0; j < i; ++j) {
			if (p_slot_ids[j] == p_slot_ids[i]) {
				return 0;
			}
		}
	}
	const int owned = _find_actor(p_actor_id);
	// Preserve a valid reservation if it is still among the actor's requested
	// positions: avoids thundering-herd churn on every AI replan.
	if (owned >= 0) {
		for (int i = 0; i < p_slot_ids.size(); ++i) {
			if (claims[owned].slot_id == p_slot_ids[i]) {
				claims.write[owned].remaining = p_lease_seconds;
				return claims[owned].slot_id;
			}
		}
	}
	for (int i = 0; i < p_slot_ids.size(); ++i) {
		const int64_t slot = p_slot_ids[i];
		if (_find_slot(slot) >= 0) {
			continue;
		}
		if (owned >= 0) {
			Claim &existing = claims.write[owned];
			existing.slot_id = slot;
			existing.remaining = p_lease_seconds;
			return slot;
		}
		if (claims.size() >= MAX_ACTIVE_CLAIMS) {
			return 0;
		}
		Claim claim;
		claim.slot_id = slot;
		claim.actor_id = p_actor_id;
		claim.remaining = p_lease_seconds;
		claims.push_back(claim);
		return slot;
	}
	return 0; // Fully occupied: the caller may take a default AI action.
}

bool SmartObjectSlotReservations::release_slot(int64_t p_slot_id, int64_t p_actor_id) {
	if (p_slot_id <= 0 || p_actor_id <= 0) {
		return false;
	}
	const int index = _find_slot(p_slot_id);
	if (index < 0 || claims[index].actor_id != p_actor_id) {
		return false;
	}
	claims.remove_at(index);
	return true;
}

int SmartObjectSlotReservations::release_actor(int64_t p_actor_id) {
	if (p_actor_id <= 0) {
		return 0;
	}
	int count = 0;
	for (int i = claims.size() - 1; i >= 0; --i) {
		if (claims[i].actor_id == p_actor_id) {
			claims.remove_at(i);
			++count;
		}
	}
	return count;
}

void SmartObjectSlotReservations::advance_time(double p_delta) {
	if (!Math::is_finite(p_delta) || p_delta <= 0.0) {
		return;
	}
	for (int i = claims.size() - 1; i >= 0; --i) {
		if (claims[i].remaining <= p_delta) {
			claims.remove_at(i);
		} else {
			claims.write[i].remaining -= p_delta;
		}
	}
}

void SmartObjectSlotReservations::clear() {
	claims.clear();
}

int64_t SmartObjectSlotReservations::get_owner(int64_t p_slot_id) const {
	const int index = _find_slot(p_slot_id);
	return index < 0 ? 0 : claims[index].actor_id;
}

void SmartObjectSlotReservations::_bind_methods() {
	ClassDB::bind_method(D_METHOD("try_claim_first", "slot_ids", "actor_id", "lease_seconds"),
			&SmartObjectSlotReservations::try_claim_first);
	ClassDB::bind_method(D_METHOD("release_slot", "slot_id", "actor_id"),
			&SmartObjectSlotReservations::release_slot);
	ClassDB::bind_method(D_METHOD("release_actor", "actor_id"),
			&SmartObjectSlotReservations::release_actor);
	ClassDB::bind_method(D_METHOD("advance_time", "delta"),
			&SmartObjectSlotReservations::advance_time);
	ClassDB::bind_method(D_METHOD("clear"), &SmartObjectSlotReservations::clear);
	ClassDB::bind_method(D_METHOD("get_owner", "slot_id"),
			&SmartObjectSlotReservations::get_owner);
	ClassDB::bind_method(D_METHOD("get_claim_count"),
			&SmartObjectSlotReservations::get_claim_count);
}
