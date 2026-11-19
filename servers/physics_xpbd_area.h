/**************************************************************************/
/*  physics_xpbd_area.h                                                   */
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
/* MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/vector3.h"

// XPBD triangle-area constraint for cloth and thin deformable surfaces.
// Uses A = 0.5 * |(b-a) x (c-a)|, with gradients:
//   dA/da = 0.5 * (b-c) x n
//   dA/db = 0.5 * (c-a) x n
//   dA/dc = 0.5 * n x (b-a)
// n is the current unit normal. Lambda persists across iterations in one
// time step only. Pinned vertices (inverse mass zero) never move.
// False means degenerate geometry/invalid input, with no positions changed.
_FORCE_INLINE_ bool physics_xpbd_solve_triangle_area(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c,
		real_t p_inv_mass_a, real_t p_inv_mass_b, real_t p_inv_mass_c,
		real_t p_rest_area, real_t p_alpha, real_t &r_lambda) {
	if (!r_a.is_finite() || !r_b.is_finite() || !r_c.is_finite() ||
			!Math::is_finite(p_inv_mass_a) || !Math::is_finite(p_inv_mass_b) ||
			!Math::is_finite(p_inv_mass_c) || !Math::is_finite(p_rest_area) ||
			!Math::is_finite(p_alpha) || !Math::is_finite(r_lambda) ||
			p_inv_mass_a < 0.0 || p_inv_mass_b < 0.0 || p_inv_mass_c < 0.0 ||
			p_rest_area < 0.0 || p_alpha < 0.0) {
		return false;
	}
	if (p_inv_mass_a + p_inv_mass_b + p_inv_mass_c <= 0.0) {
		return false;
	}

	const Vector3 ab = r_b - r_a;
	const Vector3 ac = r_c - r_a;
	const Vector3 cross = ab.cross(ac);
	const real_t twice_area = cross.length();
	if (!(twice_area > CMP_EPSILON) || !Math::is_finite(twice_area)) {
		// A collapsed triangle has no defined normal or area gradient.
		return false;
	}
	const Vector3 n = cross / twice_area;
	const Vector3 grad_a = (r_b - r_c).cross(n) * real_t(0.5);
	const Vector3 grad_b = ac.cross(n) * real_t(0.5);
	const Vector3 grad_c = n.cross(ab) * real_t(0.5);
	const real_t weighted_gradient =
			p_inv_mass_a * grad_a.length_squared() +
			p_inv_mass_b * grad_b.length_squared() +
			p_inv_mass_c * grad_c.length_squared();
	const double denominator = double(weighted_gradient) + double(p_alpha);
	if (!grad_a.is_finite() || !grad_b.is_finite() || !grad_c.is_finite() ||
			!(weighted_gradient > 0.0) || !Math::is_finite(weighted_gradient) ||
			!(denominator > 0.0) || !Math::is_finite(denominator)) {
		return false;
	}

	const double area_error = double(twice_area) * 0.5 - double(p_rest_area);
	const double delta_lambda = (-area_error - double(p_alpha) * double(r_lambda)) / denominator;
	const double lambda = double(r_lambda) + delta_lambda;
	if (!Math::is_finite(delta_lambda) || !Math::is_finite(lambda)) {
		return false;
	}
	const real_t new_lambda = real_t(lambda);
	if (!Math::is_finite(new_lambda)) {
		return false;
	}

	const Vector3 next_a = r_a + grad_a * real_t(double(p_inv_mass_a) * delta_lambda);
	const Vector3 next_b = r_b + grad_b * real_t(double(p_inv_mass_b) * delta_lambda);
	const Vector3 next_c = r_c + grad_c * real_t(double(p_inv_mass_c) * delta_lambda);
	if (!next_a.is_finite() || !next_b.is_finite() || !next_c.is_finite()) {
		return false;
	}
	r_a = next_a;
	r_b = next_b;
	r_c = next_c;
	r_lambda = new_lambda;
	return true;
}
