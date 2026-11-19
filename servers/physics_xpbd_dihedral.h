/**************************************************************************/
/*  physics_xpbd_dihedral.h                                               */
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

// Signed dihedral angle around edge (a,b), joining oriented faces
// (a,b,c) and (b,a,d). Flat, consistently oriented cloth has angle zero.
// atan2 preserves the fold direction and supports non-flat rest meshes.
_FORCE_INLINE_ bool physics_xpbd_dihedral_angle(
		const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c,
		const Vector3 &p_d, real_t &r_angle) {
	if (!p_a.is_finite() || !p_b.is_finite() || !p_c.is_finite() || !p_d.is_finite()) {
		return false;
	}
	const Vector3 edge = p_b - p_a;
	const Vector3 normal_c = edge.cross(p_c - p_a);
	const Vector3 normal_d = (p_d - p_a).cross(edge);
	const real_t edge_squared = edge.length_squared();
	const real_t nc_squared = normal_c.length_squared();
	const real_t nd_squared = normal_d.length_squared();
	if (!(edge_squared > CMP_EPSILON * CMP_EPSILON) ||
			!(nc_squared > CMP_EPSILON * CMP_EPSILON) ||
			!(nd_squared > CMP_EPSILON * CMP_EPSILON) ||
			!Math::is_finite(edge_squared) || !Math::is_finite(nc_squared) ||
			!Math::is_finite(nd_squared)) {
		return false;
	}
	const real_t edge_length = Math::sqrt(edge_squared);
	const Vector3 n_c = normal_c / Math::sqrt(nc_squared);
	const Vector3 n_d = normal_d / Math::sqrt(nd_squared);
	const real_t sine = (edge / edge_length).dot(n_c.cross(n_d));
	const real_t cosine = n_c.dot(n_d);
	if (!Math::is_finite(sine) || !Math::is_finite(cosine)) {
		return false;
	}
	r_angle = Math::atan2(sine, cosine);
	return Math::is_finite(r_angle);
}

// One XPBD hinge projection. The analytical gradients are the derivatives
// of the signed atan2 dihedral angle, verified against finite differences.
// A constraint has four particles; zero inverse masses are exact pins.
// The signed angle error is wrapped to [-PI, PI] to avoid discontinuities
// when the hinge moves across the angular branch cut.
//
// Accumulated lambda must be reset once per physics step, but retained
// between the solver's inner iterations. No heap allocation occurs here.
_FORCE_INLINE_ bool physics_xpbd_solve_dihedral(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c, real_t p_inv_d,
		real_t p_rest_angle, real_t p_alpha, real_t &r_lambda) {
	if (!Math::is_finite(p_inv_a) || !Math::is_finite(p_inv_b) ||
			!Math::is_finite(p_inv_c) || !Math::is_finite(p_inv_d) ||
			p_inv_a < 0.0 || p_inv_b < 0.0 || p_inv_c < 0.0 || p_inv_d < 0.0 ||
			!Math::is_finite(p_rest_angle) || !Math::is_finite(p_alpha) ||
			!Math::is_finite(r_lambda) || p_alpha < 0.0) {
		return false;
	}
	real_t angle;
	if (!physics_xpbd_dihedral_angle(r_a, r_b, r_c, r_d, angle)) {
		return false;
	}
	const Vector3 edge = r_b - r_a;
	const Vector3 normal_c = edge.cross(r_c - r_a);
	const Vector3 normal_d = (r_d - r_a).cross(edge);
	const real_t edge_sq = edge.length_squared();
	const real_t edge_length = Math::sqrt(edge_sq);
	const real_t nc_sq = normal_c.length_squared();
	const real_t nd_sq = normal_d.length_squared();
	if (!(nc_sq > 0.0) || !(nd_sq > 0.0)) {
		return false;
	}

	// d(phi)/d(c,d) = -|e| * normal_(c,d) / |normal_(c,d)|^2.
	// Edge gradients distribute the opposite-vertex corrections so their
	// sum is zero: rigid translations cannot change the hinge angle.
	const Vector3 grad_c = normal_c * (-edge_length / nc_sq);
	const Vector3 grad_d = normal_d * (-edge_length / nd_sq);
	const Vector3 grad_a = grad_c * ((r_c - r_b).dot(edge) / edge_sq) +
			grad_d * ((r_d - r_b).dot(edge) / edge_sq);
	const Vector3 grad_b = grad_c * ((r_a - r_c).dot(edge) / edge_sq) +
			grad_d * ((r_a - r_d).dot(edge) / edge_sq);
	if (!grad_a.is_finite() || !grad_b.is_finite() ||
			!grad_c.is_finite() || !grad_d.is_finite()) {
		return false;
	}
	const double weighted_gradient =
			double(p_inv_a) * double(grad_a.length_squared()) +
			double(p_inv_b) * double(grad_b.length_squared()) +
			double(p_inv_c) * double(grad_c.length_squared()) +
			double(p_inv_d) * double(grad_d.length_squared());
	const double denominator = weighted_gradient + double(p_alpha);
	if (!(weighted_gradient > 0.0) || !Math::is_finite(weighted_gradient) ||
			!(denominator > 0.0) || !Math::is_finite(denominator)) {
		return false;
	}

	real_t angular_error = angle - p_rest_angle;
	if (angular_error > Math::PI) {
		angular_error -= real_t(2.0 * Math::PI);
	} else if (angular_error < -Math::PI) {
		angular_error += real_t(2.0 * Math::PI);
	}
	const double delta_lambda = -(double(angular_error) +
			double(p_alpha) * double(r_lambda)) / denominator;
	const double next_lambda_double = double(r_lambda) + delta_lambda;
	if (!Math::is_finite(delta_lambda) || !Math::is_finite(next_lambda_double)) {
		return false;
	}
	const real_t next_lambda = real_t(next_lambda_double);
	if (!Math::is_finite(next_lambda)) {
		return false;
	}

	const Vector3 next_a(
			real_t(double(r_a.x) + double(p_inv_a) * delta_lambda * double(grad_a.x)),
			real_t(double(r_a.y) + double(p_inv_a) * delta_lambda * double(grad_a.y)),
			real_t(double(r_a.z) + double(p_inv_a) * delta_lambda * double(grad_a.z)));
	const Vector3 next_b(
			real_t(double(r_b.x) + double(p_inv_b) * delta_lambda * double(grad_b.x)),
			real_t(double(r_b.y) + double(p_inv_b) * delta_lambda * double(grad_b.y)),
			real_t(double(r_b.z) + double(p_inv_b) * delta_lambda * double(grad_b.z)));
	const Vector3 next_c(
			real_t(double(r_c.x) + double(p_inv_c) * delta_lambda * double(grad_c.x)),
			real_t(double(r_c.y) + double(p_inv_c) * delta_lambda * double(grad_c.y)),
			real_t(double(r_c.z) + double(p_inv_c) * delta_lambda * double(grad_c.z)));
	const Vector3 next_d(
			real_t(double(r_d.x) + double(p_inv_d) * delta_lambda * double(grad_d.x)),
			real_t(double(r_d.y) + double(p_inv_d) * delta_lambda * double(grad_d.y)),
			real_t(double(r_d.z) + double(p_inv_d) * delta_lambda * double(grad_d.z)));
	if (!next_a.is_finite() || !next_b.is_finite() ||
			!next_c.is_finite() || !next_d.is_finite()) {
		return false;
	}
	r_a = next_a;
	r_b = next_b;
	r_c = next_c;
	r_d = next_d;
	r_lambda = next_lambda;
	return true;
}
