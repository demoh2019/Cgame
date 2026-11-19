/**************************************************************************/
/*  physics_joint_fatigue.h                                              */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include <cmath>

// Simple engineering fatigue damage accumulation for rigid constraints.
// This is NOT a cycle-counting S–N / rainflow model. It models progressive
// structural weakening by sustained or repeated high constraint loads.
//
// Let f = |reaction_force| / break_force, t = |reaction_torque| /
// break_torque for nonzero break thresholds (missing channels are zero).
// Combined normalized demand u = sqrt(f² + t²). Below yield_ratio, no
// fatigue; above, D += dt * fatigue_rate * (u-yield_ratio)².
//
// Breaking occurs when D >= 1 (in addition to existing instantaneous
// break thresholds). The damage law is linear-in-time at constant demand,
// so it is independent of timestep subdivision. No healing; nonfinite or
// invalid parameters are rejected WITHOUT modifying damage.
//
// Returns true only when a positive damage increment was applied.
inline static bool physics_joint_accumulate_fatigue_damage(
		double p_force, double p_torque, double p_break_force,
		double p_break_torque, double p_yield_ratio, double p_rate,
		double p_delta, double &r_damage) {
	if (!std::isfinite(p_force) || p_force < 0.0 ||
			!std::isfinite(p_torque) || p_torque < 0.0 ||
			!std::isfinite(p_break_force) || p_break_force < 0.0 ||
			!std::isfinite(p_break_torque) || p_break_torque < 0.0 ||
			!std::isfinite(p_yield_ratio) || p_yield_ratio < 0.0 ||
			p_yield_ratio > 0.99 || !std::isfinite(p_rate) || p_rate <= 0.0 ||
			!std::isfinite(p_delta) || p_delta <= 0.0 ||
			!std::isfinite(r_damage) || r_damage < 0.0 ||
			r_damage >= 1.0 || (p_break_force <= 0.0 && p_break_torque <= 0.0)) {
		return false;
	}
	const double normalized_force = p_break_force > 0.0 ? p_force / p_break_force : 0.0;
	const double normalized_torque = p_break_torque > 0.0 ? p_torque / p_break_torque : 0.0;
	const double utilization = std::hypot(normalized_force, normalized_torque);
	if (!(utilization > p_yield_ratio)) {
		return false;
	}
	const double excess = utilization - p_yield_ratio;
	const double increment = p_rate * p_delta * excess * excess;
	if (!(increment > 0.0)) {
		return false;
	}
	// Infinite overflow from otherwise finite extreme input means failure,
	// never NaN propagation. No overflow can escape the capped update.
	const double next = increment >= 1.0 - r_damage ?
			1.0 : r_damage + increment;
	if (!std::isfinite(next) || next <= r_damage) {
		return false;
	}
	r_damage = next;
	return true;
}
