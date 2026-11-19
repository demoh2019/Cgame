/**************************************************************************/
/*  physics_xpbd_distance.h                                               */
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

// Extended Position-Based Dynamics (XPBD) distance constraint.
// p_alpha = compliance / (step * step), accumulated lambda is persistent
// across solver iterations within ONE step and must be reset next step.
// No heap allocations, and zero inverse mass pins a particle exactly.
// Returns false for degenerate or nonfinite inputs, preserving positions.
_FORCE_INLINE_ bool physics_xpbd_solve_distance(
		Vector3 &r_a, Vector3 &r_b, real_t p_inv_mass_a, real_t p_inv_mass_b,
		real_t p_rest_length, real_t p_alpha, real_t &r_lambda) {
	if (!r_a.is_finite() || !r_b.is_finite() ||
			!Math::is_finite(p_inv_mass_a) || !Math::is_finite(p_inv_mass_b) ||
			!Math::is_finite(p_rest_length) || !Math::is_finite(p_alpha) ||
			!Math::is_finite(r_lambda) || p_inv_mass_a < 0.0 || p_inv_mass_b < 0.0 ||
			p_rest_length < 0.0 || p_alpha < 0.0) {
		return false;
	}
	const real_t inv_mass_sum = p_inv_mass_a + p_inv_mass_b;
	if (!(inv_mass_sum > 0.0) || !Math::is_finite(inv_mass_sum)) {
		return false;
	}
	const Vector3 delta = r_b - r_a;
	const real_t len_squared = delta.length_squared();
	if (!(len_squared > CMP_EPSILON * CMP_EPSILON) || !Math::is_finite(len_squared)) {
		return false;
	}
	const real_t length = Math::sqrt(len_squared);
	const real_t denominator = inv_mass_sum + p_alpha;
	if (!(denominator > 0.0) || !Math::is_finite(denominator)) {
		return false;
	}
	const real_t delta_lambda = (p_rest_length - length - p_alpha * r_lambda) / denominator;
	if (!Math::is_finite(delta_lambda)) {
		return false;
	}
	const Vector3 correction = delta * (delta_lambda / length);
	const Vector3 next_a = r_a - correction * p_inv_mass_a;
	const Vector3 next_b = r_b + correction * p_inv_mass_b;
	if (!next_a.is_finite() || !next_b.is_finite()) {
		return false;
	}
	r_a = next_a;
	r_b = next_b;
	r_lambda += delta_lambda;
	return true;
}
