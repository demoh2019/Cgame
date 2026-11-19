/**************************************************************************/
/*  physics_softbody_link_damping.h                                       */
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

#include "core/math/math_funcs.h"
#include "core/math/vector3.h"

// Exact exponential relaxation of longitudinal relative velocity in a
// two-particle link. This is a mass-weighted, momentum-conserving viscous
// dashpot; it does not change tangential velocity or particle positions.
//
// p_fraction = 1 - exp(-rate * physics_dt) is evaluated ONCE per soft-body
// physics step, outside the link loop. A pinned particle has zero inverse
// mass and never moves. The caller may apply this to stretch and bend links.
// All intermediate calculations use double, and BOTH output velocities are
// validated before committing any change.
_FORCE_INLINE_ static bool physics_softbody_damp_link(
		const Vector3 &p_position_a, const Vector3 &p_position_b,
		Vector3 &r_velocity_a, Vector3 &r_velocity_b,
		real_t p_inverse_mass_a, real_t p_inverse_mass_b,
		double p_fraction) {
	if (!(p_fraction > 0.0 && p_fraction <= 1.0) ||
			!Math::is_finite(p_fraction) || !p_position_a.is_finite() ||
			!p_position_b.is_finite() || !r_velocity_a.is_finite() ||
			!r_velocity_b.is_finite() || !Math::is_finite(p_inverse_mass_a) ||
			!Math::is_finite(p_inverse_mass_b) || p_inverse_mass_a < 0.0 ||
			p_inverse_mass_b < 0.0) {
		return false;
	}

	const double wa = double(p_inverse_mass_a);
	const double wb = double(p_inverse_mass_b);
	const double inv_mass_sum = wa + wb;
	if (!(inv_mass_sum > 0.0) || !Math::is_finite(inv_mass_sum)) {
		return false;
	}

	const double dx = double(p_position_b.x) - double(p_position_a.x);
	const double dy = double(p_position_b.y) - double(p_position_a.y);
	const double dz = double(p_position_b.z) - double(p_position_a.z);
	const double separation_squared = dx * dx + dy * dy + dz * dz;
	if (!(separation_squared > 0.0) || !Math::is_finite(separation_squared)) {
		return false; // Coincident positions have no link direction.
	}
	const double inv_distance = 1.0 / Math::sqrt(separation_squared);
	const double nx = dx * inv_distance;
	const double ny = dy * inv_distance;
	const double nz = dz * inv_distance;
	const double relative_normal_velocity =
			(double(r_velocity_b.x) - double(r_velocity_a.x)) * nx +
			(double(r_velocity_b.y) - double(r_velocity_a.y)) * ny +
			(double(r_velocity_b.z) - double(r_velocity_a.z)) * nz;
	if (!Math::is_finite(relative_normal_velocity)) {
		return false;
	}

	const double impulse = -(p_fraction * relative_normal_velocity) / inv_mass_sum;
	if (!Math::is_finite(impulse)) {
		return false;
	}
	const double dv_a = -wa * impulse;
	const double dv_b = wb * impulse;
	const Vector3 next_a(real_t(double(r_velocity_a.x) + nx * dv_a),
			real_t(double(r_velocity_a.y) + ny * dv_a),
			real_t(double(r_velocity_a.z) + nz * dv_a));
	const Vector3 next_b(real_t(double(r_velocity_b.x) + nx * dv_b),
			real_t(double(r_velocity_b.y) + ny * dv_b),
			real_t(double(r_velocity_b.z) + nz * dv_b));
	if (!next_a.is_finite() || !next_b.is_finite()) {
		return false;
	}
	r_velocity_a = next_a;
	r_velocity_b = next_b;
	return true;
}
