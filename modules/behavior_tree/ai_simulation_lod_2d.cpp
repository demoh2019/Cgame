/**************************************************************************/
/*  ai_simulation_lod_2d.cpp                                                  */
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

#include "ai_simulation_lod_2d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

bool AISimulationLOD2D::configure_intervals(real_t p_near, real_t p_medium, real_t p_far) {
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_near) || !Math::is_finite(p_medium) || !Math::is_finite(p_far) ||
			p_near <= 0.0 || p_medium < p_near || p_far < p_medium || p_far > 2.0, false,
			"AI simulation intervals must satisfy 0 < near <= medium <= far <= 2 seconds.");
	near_interval = p_near;
	medium_interval = p_medium;
	far_interval = p_far;
	return true;
}

real_t AISimulationLOD2D::get_near_interval() const {
	return near_interval;
}

real_t AISimulationLOD2D::get_medium_interval() const {
	return medium_interval;
}

real_t AISimulationLOD2D::get_far_interval() const {
	return far_interval;
}

real_t AISimulationLOD2D::get_interval(real_t p_distance, real_t p_near_distance, real_t p_far_distance, bool p_urgent) const {
	if (p_urgent || !Math::is_finite(p_near_distance) || !Math::is_finite(p_far_distance) ||
			p_near_distance < 0.0 || p_far_distance <= p_near_distance ||
			(!Math::is_finite(p_distance) && p_distance <= 0.0) ||
			p_distance < 0.0) {
		return near_interval;
	}
	// Positive infinity is an intentional "no eligible viewers" sentinel.
	if (!Math::is_finite(p_distance)) {
		return p_distance > 0.0 ? far_interval : near_interval;
	}
	if (p_distance <= p_near_distance) {
		return near_interval;
	}
	if (p_distance <= p_far_distance) {
		return medium_interval;
	}
	return far_interval;
}

real_t AISimulationLOD2D::get_hysteretic_interval(real_t p_distance, real_t p_near_distance, real_t p_far_distance,
		real_t p_previous_interval, real_t p_hysteresis, bool p_urgent) const {
	const real_t nominal = get_interval(p_distance, p_near_distance, p_far_distance, p_urgent);
	// Invalid or uninitialized previous states use the normal policy. Reject
	// overlapping bands so transitions remain deterministic at every boundary.
	if (p_urgent || nominal == near_interval || !Math::is_finite(p_distance) ||
			!Math::is_finite(p_near_distance) || !Math::is_finite(p_far_distance) ||
			p_near_distance < 0.0 || p_far_distance <= p_near_distance ||
			!Math::is_finite(p_hysteresis) || p_hysteresis <= 0.0 ||
			p_hysteresis > 256.0 || p_hysteresis * 2.0 > p_far_distance - p_near_distance ||
			!Math::is_finite(p_previous_interval)) {
		return nominal;
	}
	const bool was_near = Math::is_equal_approx(p_previous_interval, near_interval);
	const bool was_medium = Math::is_equal_approx(p_previous_interval, medium_interval);
	const bool was_far = Math::is_equal_approx(p_previous_interval, far_interval);
	if (!was_near && !was_medium && !was_far) {
		return nominal;
	}
	// Never delay a scan once an eligible viewer enters the exact game-owned
	// near threshold (p_distance <= p_near_distance is handled above).
	if (was_near && p_distance <= p_near_distance + p_hysteresis) {
		return near_interval;
	}
	if (was_medium && p_distance <= p_far_distance + p_hysteresis) {
		return medium_interval;
	}
	if (was_far && p_distance > p_far_distance - p_hysteresis) {
		return far_interval;
	}
	return nominal;
}

Vector2 AISimulationLOD2D::plan_passive_scan(int64_t p_agent_id, real_t p_distance,
		real_t p_near_distance, real_t p_far_distance, real_t p_previous_interval,
		real_t p_hysteresis, bool p_already_staggered, bool p_urgent) const {
	// Preserve the original one-shot schedule: store the *unphased* tier as
	// previous interval even when this tick's delay is ID-staggered.
	// Threat/urgent work must run at the near cadence without phase delay.
	const real_t base = get_interval(p_distance, p_near_distance, p_far_distance, p_urgent);
	if (!p_already_staggered && p_distance > p_near_distance && !p_urgent) {
		const real_t phased = get_staggered_interval(p_agent_id,
				p_distance, p_near_distance, p_far_distance, false);
		return Vector2(base, phased);
	}
	const real_t nominal = get_hysteretic_interval(p_distance, p_near_distance,
			p_far_distance, p_previous_interval, p_hysteresis, p_urgent);
	return Vector2(nominal, nominal);
}

real_t AISimulationLOD2D::get_staggered_interval(int64_t p_agent_id, real_t p_distance, real_t p_near_distance, real_t p_far_distance, bool p_urgent) const {
	const real_t interval = get_interval(p_distance, p_near_distance, p_far_distance, p_urgent);
	// Never stagger urgent/near AI; invalid identifiers must not throttle AI.
	if (p_agent_id < 0 || interval <= near_interval) {
		return near_interval;
	}
	// IDs are stable across runs and distribute consecutive spawns evenly.
	// Bins are 1/16 to 16/16 of the selected tick interval; no zero-delay loop.
	return interval * real_t((p_agent_id % 16) + 1) / real_t(16.0);
}

void AISimulationLOD2D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure_intervals", "near_seconds", "medium_seconds", "far_seconds"), &AISimulationLOD2D::configure_intervals);
	ClassDB::bind_method(D_METHOD("get_near_interval"), &AISimulationLOD2D::get_near_interval);
	ClassDB::bind_method(D_METHOD("get_medium_interval"), &AISimulationLOD2D::get_medium_interval);
	ClassDB::bind_method(D_METHOD("get_far_interval"), &AISimulationLOD2D::get_far_interval);
	ClassDB::bind_method(D_METHOD("get_interval", "distance", "near_distance", "far_distance", "urgent"), &AISimulationLOD2D::get_interval, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("get_hysteretic_interval", "distance", "near_distance", "far_distance", "previous_interval", "hysteresis", "urgent"), &AISimulationLOD2D::get_hysteretic_interval, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("get_staggered_interval", "agent_id", "distance", "near_distance", "far_distance", "urgent"), &AISimulationLOD2D::get_staggered_interval, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("plan_passive_scan", "agent_id", "distance", "near_distance", "far_distance", "previous_interval", "hysteresis", "already_staggered", "urgent"), &AISimulationLOD2D::plan_passive_scan, DEFVAL(false));
}
