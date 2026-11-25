/**************************************************************************/
/*  cgame_lag_compensation.cpp                                            */
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

#include "cgame_lag_compensation.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void CgameLagCompensation::record(int p_id, double p_now, const Vector3 &p_position) {
	if (!Math::is_finite(p_now) || !p_position.is_finite()) {
		return;
	}
	Vector<Sample> &samples = history[p_id];
	if (!samples.is_empty()) {
		const int last = samples.size() - 1;
		if (p_now < samples[last].time) {
			return;
		}
		if (p_now == samples[last].time) {
			samples.write[last].position = p_position;
			return;
		}
	}
	Sample s;
	s.time = p_now;
	s.position = p_position;
	samples.push_back(s);
	// Bound storage even when a caller records at a much higher frequency
	// than the game's authoritative tick rate.
	while (samples.size() > 128 || (samples.size() > 2 && p_now - samples[0].time > HISTORY_SECONDS)) {
		samples.remove_at(0);
	}
}

void CgameLagCompensation::forget(int p_id) {
	history.erase(p_id);
}

void CgameLagCompensation::prune(const Dictionary &p_alive_ids) {
	Vector<int> stale;
	for (const KeyValue<int, Vector<Sample>> &kv : history) {
		if (!p_alive_ids.has(kv.key)) {
			stale.push_back(kv.key);
		}
	}
	for (int id : stale) {
		history.erase(id);
	}
}

int CgameLagCompensation::sample_count(int p_id) const {
	const Vector<Sample> *samples = history.getptr(p_id);
	return samples ? samples->size() : 0;
}

// How far back to judge an attacker with this round-trip time (seconds).
double CgameLagCompensation::rewind_for(double p_round_trip) {
	if (!Math::is_finite(p_round_trip) || p_round_trip <= 0.0) {
		return 0.0;
	}
	return CLAMP(p_round_trip * 0.5 + CLIENT_INTERPOLATION, 0.0, MAX_REWIND);
}

// Interpolated position at the given time; the fallback when no usable history exists.
Vector3 CgameLagCompensation::position_at(int p_id, double p_at, const Vector3 &p_fallback) const {
	const Vector<Sample> *found = history.getptr(p_id);
	if (!found || found->is_empty() || !Math::is_finite(p_at)) {
		return p_fallback;
	}
	const Vector<Sample> &samples = *found;
	if (p_at >= samples[samples.size() - 1].time) {
		return p_fallback;
	}
	if (p_at <= samples[0].time) {
		return samples[0].position;
	}
	for (int i = samples.size() - 1; i > 0; i--) {
		const double t0 = samples[i - 1].time;
		const double t1 = samples[i].time;
		if (p_at >= t0) {
			const double k = t1 <= t0 ? 0.0 : (p_at - t0) / (t1 - t0);
			return samples[i - 1].position.lerp(samples[i].position, k);
		}
	}
	return p_fallback;
}

void CgameLagCompensation::_bind_methods() {
	ClassDB::bind_method(D_METHOD("record", "id", "now", "position"), &CgameLagCompensation::record);
	ClassDB::bind_method(D_METHOD("forget", "id"), &CgameLagCompensation::forget);
	ClassDB::bind_method(D_METHOD("prune", "alive_ids"), &CgameLagCompensation::prune);
	ClassDB::bind_method(D_METHOD("sample_count", "id"), &CgameLagCompensation::sample_count);
	ClassDB::bind_static_method("CgameLagCompensation", D_METHOD("rewind_for", "round_trip"), &CgameLagCompensation::rewind_for);
	ClassDB::bind_method(D_METHOD("position_at", "id", "at", "fallback"), &CgameLagCompensation::position_at);
	ClassDB::bind_static_method("CgameLagCompensation", D_METHOD("get_history_seconds"), &CgameLagCompensation::get_history_seconds);
	ClassDB::bind_static_method("CgameLagCompensation", D_METHOD("get_max_rewind"), &CgameLagCompensation::get_max_rewind);
	ClassDB::bind_static_method("CgameLagCompensation", D_METHOD("get_client_interpolation"), &CgameLagCompensation::get_client_interpolation);
}
