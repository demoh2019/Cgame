/**************************************************************************/
/*  physics_rotating_frame_3d.h                                           */
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

// Translation of a rigid-body COM, represented in a prescribed rotating
// coordinate system (NOT a rigid-body attitude / frame transformation).
//
// Rotating-frame acceleration from Newtonian inertial motion:
//   a_rot = a_physical - 2*omega×v - omega×(omega×r) - alpha×r,
// with r = position - frame_origin, alpha = d(omega)/dt.
//
// Centrifugal and Euler accelerations are frozen at the current COM for the
// duration of the step and kicked in two equal halves. The Coriolis ODE
// dv/dt = -2*omega×v is integrated by the Boris/Cayley rotation:
//
//   t = omega*dt; s = 2*t/(1+dot(t,t))
//   v_minus = v + 0.5*dt*(a_centrifugal+a_euler)
//   v_prime = v_minus + cross(v_minus,t)
//   v_plus = v_minus + cross(v_prime,s)
//   v_new = v_plus + 0.5*dt*(a_centrifugal+a_euler)
//
// For alpha=0 and r=0 this conserves |v| exactly up to floating error,
// including large omega*dt, unlike explicit Euler Coriolis integration.
// The translational fictitious forces scale per unit mass; caller applies
// this to COM velocity AFTER usual physical forces / damping.
// No allocations and no coordinate-system metadata stored in bodies.
// Invalid/overflowed inputs leave r_velocity UNMODIFIED.
_FORCE_INLINE_ static bool godot_physics_rotating_frame_step_3d(
		Vector3 &r_velocity, const Vector3 &p_world_com,
		const Vector3 &p_frame_origin, const Vector3 &p_omega,
		const Vector3 &p_angular_acceleration, real_t p_delta) {
	if (!r_velocity.is_finite() || !p_world_com.is_finite() ||
			!p_frame_origin.is_finite() || !p_omega.is_finite() ||
			!p_angular_acceleration.is_finite() ||
			!Math::is_finite(p_delta) || p_delta < 0.0) {
		return false;
	}
	if (p_delta == 0.0 ||
			(p_omega == Vector3() && p_angular_acceleration == Vector3())) {
		return true;
	}

	const double dt = double(p_delta);
	const double omega[3] = {
		double(p_omega.x), double(p_omega.y), double(p_omega.z)
	};
	const double alpha[3] = {
		double(p_angular_acceleration.x),
		double(p_angular_acceleration.y),
		double(p_angular_acceleration.z)
	};
	const double offset[3] = {
		double(p_world_com.x) - double(p_frame_origin.x),
		double(p_world_com.y) - double(p_frame_origin.y),
		double(p_world_com.z) - double(p_frame_origin.z)
	};
	const double velocity[3] = {
		double(r_velocity.x), double(r_velocity.y), double(r_velocity.z)
	};
	const double omega_sq = omega[0] * omega[0] +
			omega[1] * omega[1] + omega[2] * omega[2];
	const double omega_dot_r = omega[0] * offset[0] +
			omega[1] * offset[1] + omega[2] * offset[2];

	// a_centrifugal = -omega×(omega×r)
	//                = |omega|^2*r - dot(omega,r)*omega.
	// a_euler = -alpha×r.
	const double euler_cross[3] = {
		alpha[1] * offset[2] - alpha[2] * offset[1],
		alpha[2] * offset[0] - alpha[0] * offset[2],
		alpha[0] * offset[1] - alpha[1] * offset[0]
	};
	double before[3];
	double t[3];
	for (int i = 0; i < 3; ++i) {
		const double acceleration =
				omega_sq * offset[i] - omega_dot_r * omega[i] - euler_cross[i];
		before[i] = velocity[i] + 0.5 * dt * acceleration;
		t[i] = omega[i] * dt;
		if (!Math::is_finite(before[i]) || !Math::is_finite(t[i])) {
			return false;
		}
	}
	const double t_sq = t[0] * t[0] + t[1] * t[1] + t[2] * t[2];
	if (!Math::is_finite(t_sq)) {
		return false;
	}
	const double s_factor = 2.0 / (1.0 + t_sq);
	const double s[3] = {
		t[0] * s_factor, t[1] * s_factor, t[2] * s_factor
	};

	// Standard Boris rotation for the right-handed cross-product form
	// -2*omega×v = 2*v×omega, preserving speed for pure Coriolis motion.
	const double prime[3] = {
		before[0] + before[1] * t[2] - before[2] * t[1],
		before[1] + before[2] * t[0] - before[0] * t[2],
		before[2] + before[0] * t[1] - before[1] * t[0]
	};
	double result[3];
	const double rotate[3] = {
		prime[1] * s[2] - prime[2] * s[1],
		prime[2] * s[0] - prime[0] * s[2],
		prime[0] * s[1] - prime[1] * s[0]
	};
	const double max_real = double(std::numeric_limits<real_t>::max());
	for (int i = 0; i < 3; ++i) {
		// Correct for the first half kick: before[i]-velocity[i].
		result[i] = before[i] + rotate[i] + (before[i] - velocity[i]);
		if (!Math::is_finite(result[i]) ||
				Math::abs(result[i]) > max_real) {
			return false;
		}
	}
	const Vector3 next_velocity = Vector3(
			real_t(result[0]), real_t(result[1]), real_t(result[2]));
	if (!next_velocity.is_finite()) {
		return false;
	}
	r_velocity = next_velocity;
	return true;
}
