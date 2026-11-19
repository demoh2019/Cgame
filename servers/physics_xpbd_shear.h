/**************************************************************************/
/*  physics_xpbd_shear.h                                                  */
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

// A rotation-invariant triangle shear constraint for cloth and deformable
// surfaces: C = cos(angle(b-a, c-a)) - cos(rest_angle).
// Unlike an unnormalized dot constraint, C is independent of edge scale.
// The compliance is divided by dt^2 by the caller. The accumulated XPBD
// lambda must be reset once per physics tick, not per solver iteration.
// All calculations use double intermediates to support small/large meshes.
namespace PhysicsXPBDShearInternal {

struct Geometry {
	double ab[3];
	double ac[3];
	double ab_squared;
	double ac_squared;
	double inv_length_product;
	double cosine;
};

_FORCE_INLINE_ bool calculate_geometry(const Vector3 &p_a, const Vector3 &p_b,
		const Vector3 &p_c, Geometry &r_geometry) {
	if (!p_a.is_finite() || !p_b.is_finite() || !p_c.is_finite()) {
		return false;
	}
	Geometry g;
	g.ab[0] = double(p_b.x) - double(p_a.x);
	g.ab[1] = double(p_b.y) - double(p_a.y);
	g.ab[2] = double(p_b.z) - double(p_a.z);
	g.ac[0] = double(p_c.x) - double(p_a.x);
	g.ac[1] = double(p_c.y) - double(p_a.y);
	g.ac[2] = double(p_c.z) - double(p_a.z);
	g.ab_squared = g.ab[0] * g.ab[0] + g.ab[1] * g.ab[1] + g.ab[2] * g.ab[2];
	g.ac_squared = g.ac[0] * g.ac[0] + g.ac[1] * g.ac[1] + g.ac[2] * g.ac[2];
	const double product = g.ab_squared * g.ac_squared;
	if (!(product > 0.0) || !Math::is_finite(product)) {
		return false;
	}
	const double cx = g.ab[1] * g.ac[2] - g.ab[2] * g.ac[1];
	const double cy = g.ab[2] * g.ac[0] - g.ab[0] * g.ac[2];
	const double cz = g.ab[0] * g.ac[1] - g.ab[1] * g.ac[0];
	const double cross_squared = cx * cx + cy * cy + cz * cz;
	// Reject near-zero angle gradients using a relative, scale-free test.
	if (!Math::is_finite(cross_squared) || !(cross_squared > product * 1e-20)) {
		return false;
	}
	const double dot = g.ab[0] * g.ac[0] + g.ab[1] * g.ac[1] + g.ab[2] * g.ac[2];
	g.inv_length_product = 1.0 / Math::sqrt(product);
	g.cosine = CLAMP(dot * g.inv_length_product, -1.0, 1.0);
	if (!Math::is_finite(g.cosine) || !Math::is_finite(g.inv_length_product)) {
		return false;
	}
	r_geometry = g;
	return true;
}

} // namespace PhysicsXPBDShearInternal

// Computes the rest angle from the undeformed mesh. On failure, output is
// unchanged, so callers can mark a degenerate face and skip it at runtime.
_FORCE_INLINE_ bool physics_xpbd_triangle_shear_rest_cosine(const Vector3 &p_a,
		const Vector3 &p_b, const Vector3 &p_c, real_t &r_cosine) {
	PhysicsXPBDShearInternal::Geometry geometry;
	if (!PhysicsXPBDShearInternal::calculate_geometry(p_a, p_b, p_c, geometry)) {
		return false;
	}
	const real_t cosine = real_t(geometry.cosine);
	if (!Math::is_finite(cosine)) {
		return false;
	}
	r_cosine = cosine;
	return true;
}

// One XPBD triangle shear projection. Fixed/pinned vertices have inverse
// mass 0. Positions and lambda are committed atomically, without allocations.
_FORCE_INLINE_ bool physics_xpbd_solve_triangle_shear(Vector3 &r_a, Vector3 &r_b,
		Vector3 &r_c, real_t p_inv_a, real_t p_inv_b, real_t p_inv_c,
		real_t p_rest_cosine, real_t p_alpha, double &r_lambda) {
	if (!Math::is_finite(p_inv_a) || !Math::is_finite(p_inv_b) ||
			!Math::is_finite(p_inv_c) || p_inv_a < 0.0 || p_inv_b < 0.0 ||
			p_inv_c < 0.0 || !Math::is_finite(p_rest_cosine) ||
			p_rest_cosine < -1.0 || p_rest_cosine > 1.0 ||
			!Math::is_finite(p_alpha) || p_alpha < 0.0 || !Math::is_finite(r_lambda)) {
		return false;
	}

	PhysicsXPBDShearInternal::Geometry g;
	if (!PhysicsXPBDShearInternal::calculate_geometry(r_a, r_b, r_c, g)) {
		return false;
	}
	double grad_a[3];
	double grad_b[3];
	double grad_c[3];
	double grad_a_squared = 0.0;
	double grad_b_squared = 0.0;
	double grad_c_squared = 0.0;
	for (int i = 0; i < 3; ++i) {
		// Analytic derivative of the normalized edge dot product.
		grad_b[i] = g.ac[i] * g.inv_length_product -
				g.cosine * g.ab[i] / g.ab_squared;
		grad_c[i] = g.ab[i] * g.inv_length_product -
				g.cosine * g.ac[i] / g.ac_squared;
		grad_a[i] = -grad_b[i] - grad_c[i];
		grad_a_squared += grad_a[i] * grad_a[i];
		grad_b_squared += grad_b[i] * grad_b[i];
		grad_c_squared += grad_c[i] * grad_c[i];
	}
	const double weighted_gradient = double(p_inv_a) * grad_a_squared +
			double(p_inv_b) * grad_b_squared + double(p_inv_c) * grad_c_squared;
	const double denominator = weighted_gradient + double(p_alpha);
	if (!(weighted_gradient > 0.0) || !Math::is_finite(weighted_gradient) ||
			!(denominator > 0.0) || !Math::is_finite(denominator)) {
		return false;
	}
	const double delta_lambda = -(g.cosine - double(p_rest_cosine) +
			double(p_alpha) * double(r_lambda)) / denominator;
	const double next_lambda_double = double(r_lambda) + delta_lambda;
	if (!Math::is_finite(delta_lambda) || !Math::is_finite(next_lambda_double)) {
		return false;
	}
	

	const Vector3 next_a(real_t(double(r_a.x) + double(p_inv_a) * delta_lambda * grad_a[0]),
			real_t(double(r_a.y) + double(p_inv_a) * delta_lambda * grad_a[1]),
			real_t(double(r_a.z) + double(p_inv_a) * delta_lambda * grad_a[2]));
	const Vector3 next_b(real_t(double(r_b.x) + double(p_inv_b) * delta_lambda * grad_b[0]),
			real_t(double(r_b.y) + double(p_inv_b) * delta_lambda * grad_b[1]),
			real_t(double(r_b.z) + double(p_inv_b) * delta_lambda * grad_b[2]));
	const Vector3 next_c(real_t(double(r_c.x) + double(p_inv_c) * delta_lambda * grad_c[0]),
			real_t(double(r_c.y) + double(p_inv_c) * delta_lambda * grad_c[1]),
			real_t(double(r_c.z) + double(p_inv_c) * delta_lambda * grad_c[2]));
	if (!next_a.is_finite() || !next_b.is_finite() || !next_c.is_finite()) {
		return false;
	}
	r_a = next_a;
	r_b = next_b;
	r_c = next_c;
	r_lambda = next_lambda_double;
	return true;
}
