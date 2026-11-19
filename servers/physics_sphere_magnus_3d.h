/**************************************************************************/
/*  physics_sphere_magnus_3d.h                                            */
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

#pragma once

#include "core/math/vector3.h"

#include <limits>

// Phenomenological aerodynamic / hydrodynamic sphere Magnus lift:
//    u = velocity_at_sphere_center - medium_velocity
//    F = 0.5 * rho * pi * r^2 * C_M * r * (omega x u).
//
// The local spin factor C_L = C_M * r * |omega x u| / |u|^2 is bounded
// by p_max_lift_coefficient to keep extreme spin and low-speed values
// finite. This is NOT a Reynolds-dependent sphere aerodynamic model.
//
// F is perpendicular to relative flow u and to omega, so the ideal
// continuous force does zero work on the sphere center. Reversing spin
// reverses lift, and Galilean translation of both body and medium does
// not change it. The physical force scales with medium density and
// sphere area; mass normalization belongs in the rigid-body integrator.
//
// Uses double intermediates throughout, and commits the result only if
// finite/representable as real_t. No heap allocation and no side effects.
// Returns true with zero force for zero spin/relative flow or disabled
// coefficients; false on invalid data without changing r_force.
_FORCE_INLINE_ static bool godot_physics_sphere_magnus_force_3d(
		const Vector3 &p_velocity, const Vector3 &p_angular_velocity,
		const Vector3 &p_medium_velocity, real_t p_world_radius,
		real_t p_density, real_t p_spin_lift_coefficient,
		real_t p_max_lift_coefficient, Vector3 &r_force) {
	if (!p_velocity.is_finite() || !p_angular_velocity.is_finite() ||
			!p_medium_velocity.is_finite() || !Math::is_finite(p_world_radius) ||
			!Math::is_finite(p_density) || !Math::is_finite(p_spin_lift_coefficient) ||
			!Math::is_finite(p_max_lift_coefficient) ||
			!(p_world_radius > 0.0) || p_density < 0.0 ||
			p_spin_lift_coefficient < 0.0 || p_max_lift_coefficient < 0.0) {
		return false;
	}
	if (p_density == 0.0 || p_spin_lift_coefficient == 0.0 ||
			p_max_lift_coefficient == 0.0 || p_angular_velocity == Vector3()) {
		r_force = Vector3();
		return true;
	}

	// Do not subtract in float32: e.g. v=-2e38 and flow=+2e38
	// are both finite float32 even though the difference is not.
	const double u[3] = {
		double(p_velocity.x) - double(p_medium_velocity.x),
		double(p_velocity.y) - double(p_medium_velocity.y),
		double(p_velocity.z) - double(p_medium_velocity.z),
	};
	const double w[3] = {
		double(p_angular_velocity.x), double(p_angular_velocity.y),
		double(p_angular_velocity.z),
	};
	const double speed_sq = u[0] * u[0] + u[1] * u[1] + u[2] * u[2];
	if (speed_sq == 0.0) {
		r_force = Vector3();
		return true;
	}
	if (!(speed_sq > 0.0) || !Math::is_finite(speed_sq)) {
		return false;
	}
	const double cross[3] = {
		w[1] * u[2] - w[2] * u[1],
		w[2] * u[0] - w[0] * u[2],
		w[0] * u[1] - w[1] * u[0],
	};
	const double cross_sq = cross[0] * cross[0] +
			cross[1] * cross[1] + cross[2] * cross[2];
	if (cross_sq == 0.0) {
		r_force = Vector3();
		return true;
	}
	if (!(cross_sq > 0.0) || !Math::is_finite(cross_sq)) {
		return false;
	}
	const double cross_length = Math::sqrt(cross_sq);
	const double radius = double(p_world_radius);
	const double uncapped_factor = double(p_spin_lift_coefficient) * radius;
	const double capped_factor = double(p_max_lift_coefficient) *
			speed_sq / cross_length;
	const double spin_factor = MIN(uncapped_factor, capped_factor);
	const double factor = 0.5 * double(p_density) * Math::PI *
			radius * radius * spin_factor;
	if (!(factor >= 0.0) || !Math::is_finite(factor)) {
		return false;
	}
	const double max_real = double(std::numeric_limits<real_t>::max());
	double components[3];
	for (int i = 0; i < 3; ++i) {
		components[i] = cross[i] * factor;
		if (!Math::is_finite(components[i]) ||
				Math::abs(components[i]) > max_real) {
			return false;
		}
	}
	const Vector3 force(real_t(components[0]),
			real_t(components[1]), real_t(components[2]));
	if (!force.is_finite()) {
		return false;
	}
	r_force = force;
	return true;
}
