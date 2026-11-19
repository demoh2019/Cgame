/**************************************************************************/
/*  physics_softbody_aerodynamic_drag.h                                   */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/vector3.h"

// Force on EACH of the three face vertices. Normal pressure drag and an
// optional in-plane quadratic skin drag use the same face-averaged velocity.
// For a mean velocity component u, the equation du/dt = -k u |u| has the
// analytic solution u(t+dt) = u(t) / (1 + k |u(t)| dt).
// This force realizes that step exactly for the face mean, avoiding velocity
// reversal and energy injection at high Cd, speed, or frame duration.
// k = (Cd * area / 6) * (sum_inverse_mass / 3).
//
// The face normal is expected to be unit length (soft-body normals are
// cached); minor deviations are normalized. No allocation is performed.
// Pinned particles are represented by zero inverse mass. On invalid input
// the output is preserved, and a zero-drag valid input writes a zero vector.
_FORCE_INLINE_ static bool physics_softbody_quadratic_aerodynamic_force(
		const Vector3 &p_normal, const Vector3 &p_velocity,
		real_t p_drag_coefficient, real_t p_tangential_ratio,
		real_t p_area, real_t p_delta, real_t p_sum_inverse_mass,
		Vector3 &r_force_per_vertex) {
	if (!p_normal.is_finite() || !p_velocity.is_finite() ||
			!Math::is_finite(p_drag_coefficient) || !Math::is_finite(p_tangential_ratio) ||
			!Math::is_finite(p_area) || !Math::is_finite(p_delta) ||
			!Math::is_finite(p_sum_inverse_mass) ||
			p_drag_coefficient < 0.0 || p_tangential_ratio < 0.0 ||
			p_area < 0.0 || !(p_delta > 0.0) || p_sum_inverse_mass < 0.0) {
		return false;
	}

	const double normal_squared = double(p_normal.x) * double(p_normal.x) +
			double(p_normal.y) * double(p_normal.y) + double(p_normal.z) * double(p_normal.z);
	if (!(normal_squared > 0.0) || !Math::is_finite(normal_squared)) {
		return false;
	}
	if (p_drag_coefficient == 0.0 || p_area == 0.0 || p_sum_inverse_mass == 0.0) {
		r_force_per_vertex = Vector3();
		return true;
	}

	// Avoid sqrt for the common, already-normalized cached face normal.
	const double normal_scale = Math::abs(normal_squared - 1.0) > 1e-5 ? 1.0 / Math::sqrt(normal_squared) : 1.0;
	const double nx = double(p_normal.x) * normal_scale;
	const double ny = double(p_normal.y) * normal_scale;
	const double nz = double(p_normal.z) * normal_scale;
	const double vx = double(p_velocity.x);
	const double vy = double(p_velocity.y);
	const double vz = double(p_velocity.z);
	const double vn = vx * nx + vy * ny + vz * nz;
	const double strength = double(p_drag_coefficient) * double(p_area) / 6.0;
	const double effective_mass = double(p_sum_inverse_mass) / 3.0;
	const double dt = double(p_delta);

	const double normal_denom = 1.0 + effective_mass * strength * Math::abs(vn) * dt;
	const double normal_force = -strength * vn * Math::abs(vn) / normal_denom;
	double fx = normal_force * nx;
	double fy = normal_force * ny;
	double fz = normal_force * nz;

	// The in-plane response is independent of the face normal and remains
	// disabled by default. Both components dissipate, never add, energy.
	if (p_tangential_ratio > 0.0) {
		const double tx = vx - vn * nx;
		const double ty = vy - vn * ny;
		const double tz = vz - vn * nz;
		const double tangent_speed = Math::sqrt(tx * tx + ty * ty + tz * tz);
		if (tangent_speed > 0.0) {
			const double tangent_strength = strength * double(p_tangential_ratio);
			const double tangent_denom = 1.0 + effective_mass * tangent_strength * tangent_speed * dt;
			const double tangent_scale = -tangent_strength * tangent_speed / tangent_denom;
			fx += tx * tangent_scale;
			fy += ty * tangent_scale;
			fz += tz * tangent_scale;
		}
	}

	if (!Math::is_finite(fx) || !Math::is_finite(fy) || !Math::is_finite(fz)) {
		return false;
	}
	const Vector3 force = Vector3(real_t(fx), real_t(fy), real_t(fz));
	if (!force.is_finite()) {
		return false;
	}
	r_force_per_vertex = force;
	return true;
}
