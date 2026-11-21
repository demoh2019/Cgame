/**************************************************************************/
/*  ai_threat_table_2d.cpp                                                    */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "ai_threat_table_2d.h"

#include "core/math/math_funcs.h"
#include "core/math/vector3.h"
#include "core/object/class_db.h"
#include "core/variant/array.h"

bool AIThreatTable2D::_valid_threat(const Variant &p_amount, double &r_value) {
	const Variant::Type type = p_amount.get_type();
	if (type != Variant::FLOAT && type != Variant::INT) {
		return false;
	}
	r_value = static_cast<double>(p_amount);
	return Math::is_finite(r_value) && r_value > 0.0;
}

bool AIThreatTable2D::record(Dictionary p_entries, int64_t p_peer_id, double p_damage) const {
	if (p_peer_id <= 0 || !Math::is_finite(p_damage) || p_damage <= 0.0) {
		return false;
	}
	const double earned = MIN(MAX_VALUE, p_damage);
	if (!p_entries.has(p_peer_id) && p_entries.size() >= MAX_TARGETS) {
		// Stable lowest-ID tie breaking: independent of packet / Dictionary order.
		// A weak incidental hit cannot evict an established participant.
		int64_t smallest_id = -1;
		double smallest = INF;
		const Array keys = p_entries.keys();
		for (int i = 0; i < keys.size(); ++i) {
			const Variant key = keys[i];
			if (key.get_type() != Variant::INT) {
				continue;
			}
			const int64_t id = static_cast<int64_t>(key);
			double amount = 0.0;
			if (!_valid_threat(p_entries[key], amount)) {
				amount = 0.0;
			}
			if (amount < smallest || (amount == smallest && (smallest_id == -1 || id < smallest_id))) {
				smallest_id = id;
				smallest = amount;
			}
		}
		if (smallest_id == -1 || earned <= smallest) {
			return false;
		}
		p_entries.erase(smallest_id);
	}
	double prior = 0.0;
	if (p_entries.has(p_peer_id)) {
		// Damaged/NaN entries cannot poison arithmetic or leak infinity.
		_valid_threat(p_entries[p_peer_id], prior);
	}
	p_entries[p_peer_id] = MIN(MAX_VALUE, prior + earned);
	return true;
}

bool AIThreatTable2D::scale(Dictionary p_entries, int64_t p_peer_id, double p_factor) const {
	// Invalid requests never change the caller-owned combat state.
	if (p_peer_id <= 0 || !Math::is_finite(p_factor) || p_factor < 0.0 || p_factor > 1.0 || !p_entries.has(p_peer_id)) {
		return false;
	}
	double amount = 0.0;
	if (!_valid_threat(p_entries[p_peer_id], amount)) {
		// Repair a malformed entry without touching other combatants.
		p_entries.erase(p_peer_id);
		return false;
	}
	const double remaining = MIN(MAX_VALUE, amount * p_factor);
	if (remaining <= 0.0) {
		p_entries.erase(p_peer_id);
	} else {
		p_entries[p_peer_id] = remaining;
	}
	return true;
}

void AIThreatTable2D::decay(Dictionary p_entries, double p_delta) const {
	if (!Math::is_finite(p_delta) || p_delta <= 0.0) {
		return;
	}
	const Array keys = p_entries.keys();
	for (int i = 0; i < keys.size(); ++i) {
		const Variant key = keys[i];
		double amount = 0.0;
		if (!_valid_threat(p_entries[key], amount)) {
			p_entries.erase(key);
			continue;
		}
		const double remaining = amount - DECAY_PER_SECOND * p_delta;
		if (!Math::is_finite(remaining) || remaining <= 0.0) {
			p_entries.erase(key);
		} else {
			p_entries[key] = remaining;
		}
	}
}

int64_t AIThreatTable2D::pick(Dictionary p_entries, const Dictionary &p_players, const Vector2 &p_origin, double p_leash, int64_t p_current_target) const {
	if (!p_origin.is_finite() || !Math::is_finite(p_leash) || p_leash <= 0.0) {
		return -1;
	}
	int64_t best_id = -1;
	double best_threat = 0.0;
	double current_threat = 0.0;
	const Array keys = p_entries.keys();
	for (int i = 0; i < keys.size(); ++i) {
		const Variant key = keys[i];
		const Variant target = p_players.get(key, Variant());
		if (key.get_type() != Variant::INT || target.get_type() != Variant::DICTIONARY) {
			p_entries.erase(key);
			continue;
		}
		const int64_t id = static_cast<int64_t>(key);
		const Dictionary data = target;
		if (id <= 0 || !static_cast<bool>(data.get("alive", false)) || static_cast<bool>(data.get("safe", true))) {
			p_entries.erase(key);
			continue;
		}
		const Variant position_variant = data.get("position", Variant());
		if (position_variant.get_type() != Variant::VECTOR3) {
			p_entries.erase(key);
			continue;
		}
		const Vector3 at = position_variant;
		if (!at.is_finite()) {
			p_entries.erase(key);
			continue;
		}
		const double distance = p_origin.distance_to(Vector2(at.x, at.z));
		if (!Math::is_finite(distance) || distance > p_leash) {
			p_entries.erase(key);
			continue;
		}
		double amount = 0.0;
		if (!_valid_threat(p_entries[key], amount)) {
			p_entries.erase(key);
			continue;
		}
		if (id == p_current_target) {
			current_threat = amount;
		}
		// Deterministic tie resolution independent of insertion order.
		if (amount > best_threat || (amount == best_threat && (best_id == -1 || id < best_id))) {
			best_id = id;
			best_threat = amount;
		}
	}
	if (current_threat > 0.0 && best_id != p_current_target && best_threat < current_threat * SWITCH_MARGIN) {
		return p_current_target;
	}
	return best_id;
}

void AIThreatTable2D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("record", "entries", "peer_id", "damage"), &AIThreatTable2D::record);
	ClassDB::bind_method(D_METHOD("scale", "entries", "peer_id", "factor"), &AIThreatTable2D::scale);
	ClassDB::bind_method(D_METHOD("decay", "entries", "delta"), &AIThreatTable2D::decay);
	ClassDB::bind_method(D_METHOD("pick", "entries", "players", "origin", "leash", "current_target"), &AIThreatTable2D::pick, DEFVAL(-1));
}
