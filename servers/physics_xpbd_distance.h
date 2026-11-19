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

	const double inv_mass_a = double(p_inv_mass_a);
	const double inv_mass_b = double(p_inv_mass_b);
	const double inv_mass_sum = inv_mass_a + inv_mass_b;
	if (!(inv_mass_sum > 0.0)) {
		return false; // Pinned vertices cannot be moved.
	}

	// The old float32 distance_squared overflowed for perfectly finite
	// separations (~1e20), while tiny links were wrongly rejected by a
	// fixed epsilon. Calculate the length in double and only reject zero.
	// Subtract coordinates in double before forming the difference.
	const double dx = double(r_b.x) - double(r_a.x);
	const double dy = double(r_b.y) - double(r_a.y);
	const double dz = double(r_b.z) - double(r_a.z);
	const double distance_squared = dx * dx + dy * dy + dz * dz;
	if (!(distance_squared > 0.0) || !Math::is_finite(distance_squared)) {
		return false;
	}
	const double distance = Math::sqrt(distance_squared);
	const double denominator = inv_mass_sum + double(p_alpha);
	if (!(denominator > 0.0) || !Math::is_finite(denominator)) {
		return false;
	}

	const double delta_lambda = (double(p_rest_length) - distance - double(p_alpha) * double(r_lambda)) / denominator;
	const double next_lambda_double = double(r_lambda) + delta_lambda;
	if (!Math::is_finite(delta_lambda) || !Math::is_finite(next_lambda_double)) {
		return false;
	}
	const real_t next_lambda = real_t(next_lambda_double);
	if (!Math::is_finite(next_lambda)) {
		return false;
	}

	// Component-wise double projection avoids an underflowed real_t scale
	// and a temporary correction vector that may overflow before addition.
	const double scale_a = -inv_mass_a * delta_lambda / distance;
	const double scale_b = inv_mass_b * delta_lambda / distance;
	const Vector3 next_a(real_t(double(r_a.x) + dx * scale_a),
			real_t(double(r_a.y) + dy * scale_a), real_t(double(r_a.z) + dz * scale_a));
	const Vector3 next_b(real_t(double(r_b.x) + dx * scale_b),
			real_t(double(r_b.y) + dy * scale_b), real_t(double(r_b.z) + dz * scale_b));
	if (!next_a.is_finite() || !next_b.is_finite()) {
		return false;
	}

	r_a = next_a;
	r_b = next_b;
	r_lambda = next_lambda;
	return true;
}
