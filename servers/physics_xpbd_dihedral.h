/**************************************************************************/
/*  physics_xpbd_dihedral.h                                               */
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

// XPBD dihedral bending between two consistently oriented triangles
// (a,b,c) and (b,a,d). The hinge edge is (a,b), opposing vertices c,d.
// Unlike graph-distance bending springs, this resists changes in the angle
// between adjacent faces independently of their edge lengths.
//
// The signed angle uses atan2 instead of acos: its derivative remains
// well-defined at a flat rest fold (angle zero). Input geometry must have
// nonzero shared edge length and nondegenerate incident triangles.
// Analytical gradients are the derivatives of the signed angle in radians;
// tests compare them with central finite differences.
_FORCE_INLINE_ bool physics_xpbd_dihedral_angle_gradients(
		const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c, const Vector3 &p_d,
		real_t &r_angle, Vector3 r_gradient[4]) {
	if (!p_a.is_finite() || !p_b.is_finite() || !p_c.is_finite() || !p_d.is_finite()) {
		return false;
	}

	const Vector3 edge = p_b - p_a;
	const real_t edge_sq = edge.length_squared();
	if (!(edge_sq > CMP_EPSILON * CMP_EPSILON) || !Math::is_finite(edge_sq)) {
		return false;
	}
	const real_t edge_len = Math::sqrt(edge_sq);
	const Vector3 normal_a = edge.cross(p_c - p_a);
	const Vector3 normal_b = (p_d - p_a).cross(edge);
	const real_t normal_a_sq = normal_a.length_squared();
	const real_t normal_b_sq = normal_b.length_squared();
	if (!(normal_a_sq > CMP_EPSILON * CMP_EPSILON) ||
			!(normal_b_sq > CMP_EPSILON * CMP_EPSILON) ||
			!Math::is_finite(normal_a_sq) || !Math::is_finite(normal_b_sq)) {
		return false;
	}
	const Vector3 n_a = normal_a / Math::sqrt(normal_a_sq);
	const Vector3 n_b = normal_b / Math::sqrt(normal_b_sq);
	const real_t sine = (edge / edge_len).dot(n_a.cross(n_b));
	const real_t cosine = CLAMP(n_a.dot(n_b), real_t(-1.0), real_t(1.0));
	const real_t angle = Math::atan2(sine, cosine);
	if (!Math::is_finite(angle)) {
		return false;
	}

	const Vector3 grad_c = normal_a * (-edge_len / normal_a_sq);
	const Vector3 grad_d = normal_b * (-edge_len / normal_b_sq);
	const real_t along_c = (p_c - p_a).dot(edge) / edge_sq;
	const real_t along_d = (p_d - p_a).dot(edge) / edge_sq;
	const Vector3 grad_b = -grad_c * along_c - grad_d * along_d;
	const Vector3 grad_a = -grad_b - grad_c - grad_d;
	if (!grad_a.is_finite() || !grad_b.is_finite() ||
			!grad_c.is_finite() || !grad_d.is_finite()) {
		return false;
	}
	r_angle = angle;
	r_gradient[0] = grad_a;
	r_gradient[1] = grad_b;
	r_gradient[2] = grad_c;
	r_gradient[3] = grad_d;
	return true;
}

// Compliance = 0 is a rigid bend constraint; callers use a *separate*
// default-zero project setting to decide whether bending runs at all.
// p_alpha_tilde is compliance / dt^2. Lambda resets each step and persists
// across iterations. Pinned nodes (inverse mass zero) receive no correction.
_FORCE_INLINE_ bool physics_xpbd_solve_dihedral(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d,
		real_t p_inv_mass_a, real_t p_inv_mass_b, real_t p_inv_mass_c, real_t p_inv_mass_d,
		real_t p_rest_angle, real_t p_alpha_tilde, real_t &r_lambda) {
	if (!Math::is_finite(p_inv_mass_a) || !Math::is_finite(p_inv_mass_b) ||
			!Math::is_finite(p_inv_mass_c) || !Math::is_finite(p_inv_mass_d) ||
			!Math::is_finite(p_rest_angle) || !Math::is_finite(p_alpha_tilde) ||
			!Math::is_finite(r_lambda) ||
			p_inv_mass_a < 0.0 || p_inv_mass_b < 0.0 ||
			p_inv_mass_c < 0.0 || p_inv_mass_d < 0.0 || p_alpha_tilde < 0.0) {
		return false;
	}
	if (!(p_inv_mass_a + p_inv_mass_b + p_inv_mass_c + p_inv_mass_d > 0.0)) {
		return false;
	}

	real_t angle;
	Vector3 grad[4];
	if (!physics_xpbd_dihedral_angle_gradients(r_a, r_b, r_c, r_d, angle, grad)) {
		return false;
	}
	real_t error = angle - p_rest_angle;
	if (error > Math::PI) {
		error -= Math::TAU;
	} else if (error < -Math::PI) {
		error += Math::TAU;
	}

	const double weighted_gradient =
			double(p_inv_mass_a) * grad[0].length_squared() +
			double(p_inv_mass_b) * grad[1].length_squared() +
			double(p_inv_mass_c) * grad[2].length_squared() +
			double(p_inv_mass_d) * grad[3].length_squared();
	const double denominator = weighted_gradient + double(p_alpha_tilde);
	if (!(weighted_gradient > 0.0) || !(denominator > 0.0) ||
			!Math::is_finite(denominator)) {
		return false;
	}
	const double delta_lambda = (-double(error) - double(p_alpha_tilde) * double(r_lambda)) / denominator;
	const real_t next_lambda = real_t(double(r_lambda) + delta_lambda);
	if (!Math::is_finite(delta_lambda) || !Math::is_finite(next_lambda)) {
		return false;
	}
	const Vector3 next_a = r_a + grad[0] * real_t(delta_lambda * p_inv_mass_a);
	const Vector3 next_b = r_b + grad[1] * real_t(delta_lambda * p_inv_mass_b);
	const Vector3 next_c = r_c + grad[2] * real_t(delta_lambda * p_inv_mass_c);
	const Vector3 next_d = r_d + grad[3] * real_t(delta_lambda * p_inv_mass_d);
	if (!next_a.is_finite() || !next_b.is_finite() || !next_c.is_finite() || !next_d.is_finite()) {
		return false;
	}
	r_a = next_a;
	r_b = next_b;
	r_c = next_c;
	r_d = next_d;
	r_lambda = next_lambda;
	return true;
}
