/**************************************************************************/
/*  physics_softbody_thermal_material.h                                   */
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

#include "core/math/vector3.h"

#include <limits>

// Symmetric graph-edge thermal conduction with equal nodal heat capacity.
// Solves the two-node heat equation exactly over a timestep:
//   d(Ta-Tb)/dt = -2*k*(Ta-Tb)
//   q = 0.5*(1-exp(-2*k*dt))
//   Ta' = Ta + q*(Tb-Ta), Tb' = Tb - q*(Tb-Ta).
// This preserves the pair's average/sum (within float rounding), bounds
// temperatures between the old endpoints and remains stable for any dt>=0.
// The caller visits each structural link ONCE per physics step. Sequential
// edge exchange is a graph-Gauss-Seidel heat model; it does not conserve
// physical heat for unequal node heat capacities, which are not represented.
// No allocations. Invalid inputs leave both temperatures unchanged.
_FORCE_INLINE_ static bool physics_softbody_thermal_exchange_pair(
		real_t &r_a, real_t &r_b, real_t p_rate, real_t p_dt) {
	if (!Math::is_finite(r_a) || !Math::is_finite(r_b) ||
			!Math::is_finite(p_rate) || p_rate < 0.0 ||
			!Math::is_finite(p_dt) || p_dt < 0.0) {
		return false;
	}
	if (p_rate == 0.0 || p_dt == 0.0 || r_a == r_b) {
		return true;
	}
	const double exponent = -2.0 * double(p_rate) * double(p_dt);
	const double fraction = 0.5 * (1.0 - Math::exp(exponent));
	const double flux = fraction * (double(r_b) - double(r_a));
	const real_t next_a = real_t(double(r_a) + flux);
	const real_t next_b = real_t(double(r_b) - flux);
	if (!Math::is_finite(next_a) || !Math::is_finite(next_b)) {
		return false;
	}
	r_a = next_a;
	r_b = next_b;
	return true;
}

// First-order ambient heat exchange / local heater or cooler relaxation.
// Identical rates integrated in smaller steps produce the same endpoint,
// as long as the bath/source temperature stays unchanged.
_FORCE_INLINE_ static bool physics_softbody_thermal_relax(
		real_t &r_temperature, real_t p_target, real_t p_rate, real_t p_dt) {
	if (!Math::is_finite(r_temperature) || !Math::is_finite(p_target) ||
			!Math::is_finite(p_rate) || p_rate < 0.0 ||
			!Math::is_finite(p_dt) || p_dt < 0.0) {
		return false;
	}
	if (p_rate == 0.0 || p_dt == 0.0 || r_temperature == p_target) {
		return true;
	}
	const double fraction = 1.0 - Math::exp(-double(p_rate) * double(p_dt));
	const real_t next = real_t(double(r_temperature) +
			(double(p_target) - double(r_temperature)) * fraction);
	if (!Math::is_finite(next)) {
		return false;
	}
	r_temperature = next;
	return true;
}

// Local thermal expansion of an XPBD link relative to its CURRENT plastic
// rest length. The resting length itself is never mutated, so cooling is
// reversible, unlike plastic creep. The reference temperature is the
// configured ambient. Both pin and unpin remain collision agnostic.
//
// L(T) = L_plastic * clamp(1 + coefficient * (0.5*(Ta+Tb)-Tref),
//                         0.25, 4.0).
// The bounds prevent negative/singular constraints and huge expansions.
// This only changes edge XPBD/stretch limits, not surface-area, bending,
// FEM volume or collision geometry/rest parameters. All values computed in
// double, but the returned value must fit real_t; invalid outputs are atomic.
_FORCE_INLINE_ static bool physics_softbody_thermal_expanded_rest_length(
		real_t p_plastic_rest, real_t p_temp_a, real_t p_temp_b,
		real_t p_reference_temp, real_t p_coefficient,
		real_t &r_rest) {
	if (!Math::is_finite(p_plastic_rest) || !(p_plastic_rest > 0.0) ||
			!Math::is_finite(p_temp_a) || !Math::is_finite(p_temp_b) ||
			!Math::is_finite(p_reference_temp) ||
			!Math::is_finite(p_coefficient)) {
		return false;
	}
	const double mean_temp = 0.5 * (double(p_temp_a) + double(p_temp_b));
	const double raw_factor = 1.0 + double(p_coefficient) *
			(mean_temp - double(p_reference_temp));
	if (!Math::is_finite(raw_factor)) {
		return false;
	}
	const double factor = CLAMP(raw_factor, 0.25, 4.0);
	const double length = double(p_plastic_rest) * factor;
	if (!(length > 0.0) || !Math::is_finite(length) ||
			length > double(std::numeric_limits<real_t>::max())) {
		return false;
	}
	const real_t candidate = real_t(length);
	if (!(candidate > 0.0) || !Math::is_finite(candidate)) {
		return false;
	}
	r_rest = candidate;
	return true;
}

// Heat-source eligibility: closed ball in WORLD space, distance evaluated
// in double after subtracting to avoid float32 arithmetic overflow.
_FORCE_INLINE_ static bool physics_softbody_thermal_in_source(
		const Vector3 &p_position, const Vector3 &p_source, real_t p_radius) {
	if (!p_position.is_finite() || !p_source.is_finite() ||
			!Math::is_finite(p_radius) || !(p_radius > 0.0)) {
		return false;
	}
	const double dx = double(p_position.x) - double(p_source.x);
	const double dy = double(p_position.y) - double(p_source.y);
	const double dz = double(p_position.z) - double(p_source.z);
	const double sq = dx * dx + dy * dy + dz * dz;
	const double radius_sq = double(p_radius) * double(p_radius);
	return Math::is_finite(sq) && sq <= radius_sq;
}
