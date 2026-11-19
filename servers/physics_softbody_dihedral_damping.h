/**************************************************************************/
/*  physics_softbody_dihedral_damping.h                                   */
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
/* MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/math_funcs.h"
#include "core/math/vector3.h"

// Mass-weighted Kelvin-Voigt-style angular damping for a cloth hinge.
// (a,b,c) and (b,a,d) must be consistently oriented triangles. The
// velocity impulse acts along the XPBD signed-dihedral Jacobian and removes
// a fraction of the relative bending rate, not rigid translation/rotation.
// The same Jacobian is used by physics_xpbd_solve_dihedral().
//
// p_fraction = 1 - exp(-damping_rate * dt), evaluated once per physics tick.
// Zero inverse mass is an exact pin. No heap allocations or persistent
// multipliers are needed. Validation is transactional: a failure preserves
// ALL four velocities, including when a correction overflows real_t.
_FORCE_INLINE_ static bool physics_softbody_damp_dihedral(
		const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c, const Vector3 &p_d,
		Vector3 &r_v_a, Vector3 &r_v_b, Vector3 &r_v_c, Vector3 &r_v_d,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c, real_t p_inv_d,
		double p_fraction) {
	if (!(p_fraction > 0.0 && p_fraction <= 1.0) || !Math::is_finite(p_fraction) ||
			!p_a.is_finite() || !p_b.is_finite() || !p_c.is_finite() || !p_d.is_finite() ||
			!r_v_a.is_finite() || !r_v_b.is_finite() || !r_v_c.is_finite() || !r_v_d.is_finite() ||
			!Math::is_finite(p_inv_a) || !Math::is_finite(p_inv_b) ||
			!Math::is_finite(p_inv_c) || !Math::is_finite(p_inv_d) ||
			p_inv_a < 0.0 || p_inv_b < 0.0 || p_inv_c < 0.0 || p_inv_d < 0.0) {
		return false;
	}

	const Vector3 edge = p_b - p_a;
	const Vector3 normal_c = edge.cross(p_c - p_a);
	const Vector3 normal_d = (p_d - p_a).cross(edge);
	const real_t edge_sq = edge.length_squared();
	const real_t nc_sq = normal_c.length_squared();
	const real_t nd_sq = normal_d.length_squared();
	if (!(edge_sq > CMP_EPSILON * CMP_EPSILON) ||
			!(nc_sq > CMP_EPSILON * CMP_EPSILON) ||
			!(nd_sq > CMP_EPSILON * CMP_EPSILON) ||
			!Math::is_finite(edge_sq) || !Math::is_finite(nc_sq) || !Math::is_finite(nd_sq)) {
		return false;
	}

	const real_t edge_length = Math::sqrt(edge_sq);
	const Vector3 grad_c = normal_c * (-edge_length / nc_sq);
	const Vector3 grad_d = normal_d * (-edge_length / nd_sq);
	const Vector3 grad_a = grad_c * ((p_c - p_b).dot(edge) / edge_sq) +
			grad_d * ((p_d - p_b).dot(edge) / edge_sq);
	const Vector3 grad_b = grad_c * ((p_a - p_c).dot(edge) / edge_sq) +
			grad_d * ((p_a - p_d).dot(edge) / edge_sq);
	if (!grad_a.is_finite() || !grad_b.is_finite() ||
			!grad_c.is_finite() || !grad_d.is_finite()) {
		return false;
	}

	const Vector3 gradients[4] = { grad_a, grad_b, grad_c, grad_d };
	const real_t inverse_masses[4] = { p_inv_a, p_inv_b, p_inv_c, p_inv_d };
	Vector3 *velocities[4] = { &r_v_a, &r_v_b, &r_v_c, &r_v_d };
	double angular_rate = 0.0;
	double inverse_effective_mass = 0.0;
	for (int i = 0; i < 4; i++) {
		const Vector3 &g = gradients[i];
		const Vector3 &v = *velocities[i];
		const double gx = double(g.x);
		const double gy = double(g.y);
		const double gz = double(g.z);
		angular_rate += gx * double(v.x) + gy * double(v.y) + gz * double(v.z);
		inverse_effective_mass += double(inverse_masses[i]) *
				(gx * gx + gy * gy + gz * gz);
	}
	if (!(inverse_effective_mass > 0.0) || !Math::is_finite(inverse_effective_mass) ||
			!Math::is_finite(angular_rate)) {
		return false;
	}
	const double impulse = -p_fraction * angular_rate / inverse_effective_mass;
	if (!Math::is_finite(impulse)) {
		return false;
	}

	Vector3 next[4];
	for (int i = 0; i < 4; i++) {
		const double dv = double(inverse_masses[i]) * impulse;
		const Vector3 &g = gradients[i];
		const Vector3 &v = *velocities[i];
		next[i] = Vector3(
				real_t(double(v.x) + double(g.x) * dv),
				real_t(double(v.y) + double(g.y) * dv),
				real_t(double(v.z) + double(g.z) * dv));
		if (!next[i].is_finite()) {
			return false;
		}
	}
	for (int i = 0; i < 4; i++) {
		*velocities[i] = next[i];
	}
	return true;
}
