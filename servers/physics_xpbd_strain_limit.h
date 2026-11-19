/**************************************************************************/
/*  physics_xpbd_strain_limit.h                                           */
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

// Per-link unilateral XPBD limits for cloth/rope/deformable meshes:
//     minimum_ratio * rest_length <= |b-a| <= maximum_ratio * rest_length.
// Each ratio is independently optional (0 disables that bound). This is a
// safety limiter layered over the ordinary elastic/PBD solver, not another
// rest-length spring. The two nonpositive multipliers provide complementary
// contact-style constraints without applying forces to slack links.
//
// Keep multipliers across iterations of ONE physics step; reset each step.
// p_alpha = compliance / (dt * dt), with zero allowed for hard constraints.
// Double intermediates prevent squared-distance overflow and support very
// different spatial scales; the normal is undefined at zero separation.
struct PhysicsXPBDStrainLimitLambdas {
	double stretch = 0.0;
	double compression = 0.0;
};

// Returns true only when a correction is committed. No heap allocations.
// Invalid input, coincident nodes or unsatisfiable pinned links leave both
// positions AND both multipliers unchanged. The function makes all changes
// to temporary copies, then commits them together.
_FORCE_INLINE_ bool physics_xpbd_solve_strain_limits(
		Vector3 &r_a, Vector3 &r_b, real_t p_inv_a, real_t p_inv_b,
		real_t p_rest_length, real_t p_min_ratio, real_t p_max_ratio,
		double p_alpha, PhysicsXPBDStrainLimitLambdas &r_lambdas) {
	if (!r_a.is_finite() || !r_b.is_finite() ||
			!Math::is_finite(p_inv_a) || !Math::is_finite(p_inv_b) ||
			!Math::is_finite(p_rest_length) || !Math::is_finite(p_min_ratio) ||
			!Math::is_finite(p_max_ratio) || !Math::is_finite(p_alpha) ||
			!Math::is_finite(r_lambdas.stretch) || !Math::is_finite(r_lambdas.compression) ||
			p_inv_a < 0.0 || p_inv_b < 0.0 || p_rest_length <= 0.0 ||
			p_min_ratio < 0.0 || p_min_ratio > 1.0 ||
			p_max_ratio < 0.0 || (p_max_ratio > 0.0 && p_max_ratio < 1.0) ||
			(p_max_ratio > 0.0 && p_min_ratio > p_max_ratio) ||
			(p_min_ratio == 0.0 && p_max_ratio == 0.0) ||
			p_alpha < 0.0 || r_lambdas.stretch > 0.0 || r_lambdas.compression > 0.0) {
		return false;
	}

	const double inv_a = double(p_inv_a);
	const double inv_b = double(p_inv_b);
	const double denominator = inv_a + inv_b + p_alpha;
	if (!(inv_a + inv_b > 0.0) || !Math::is_finite(denominator) || !(denominator > 0.0)) {
		return false;
	}

	Vector3 next_a = r_a;
	Vector3 next_b = r_b;
	PhysicsXPBDStrainLimitLambdas next_lambdas = r_lambdas;
	bool changed = false;

	// Process stretch and compression independently, allowing multipliers
	// from one active bound to relax when other material constraints move
	// the link back into the admissible interval.
	for (int bound_index = 0; bound_index < 2; ++bound_index) {
		const bool upper = bound_index == 0;
		const real_t ratio = upper ? p_max_ratio : p_min_ratio;
		if (ratio == 0.0) {
			continue;
		}
		double &lambda = upper ? next_lambdas.stretch : next_lambdas.compression;
		const double dx = double(next_b.x) - double(next_a.x);
		const double dy = double(next_b.y) - double(next_a.y);
		const double dz = double(next_b.z) - double(next_a.z);
		const double distance = Math::sqrt(dx * dx + dy * dy + dz * dz);
		if (!(distance > 0.0) || !Math::is_finite(distance)) {
			return false;
		}

		const double length_limit = double(p_rest_length) * double(ratio);
		const double constraint = upper ? distance - length_limit : length_limit - distance;
		if (!Math::is_finite(constraint)) {
			return false;
		}
		if (constraint <= 0.0 && lambda == 0.0) {
			continue;
		}

		const double next_lambda = MIN(0.0, lambda -
				(constraint + p_alpha * lambda) / denominator);
		if (!Math::is_finite(next_lambda)) {
			return false;
		}
		const double delta_lambda = next_lambda - lambda;
		if (delta_lambda == 0.0) {
			continue;
		}

		// dC/db is +/- normalized(b-a); the opposite force acts on a.
		// For stretch the sign is +1, for compression it is -1.
		const double signed_scale = (upper ? 1.0 : -1.0) * delta_lambda / distance;
		const double scale_a = -inv_a * signed_scale;
		const double scale_b = inv_b * signed_scale;
		const Vector3 projected_a{
			real_t(double(next_a.x) + dx * scale_a),
			real_t(double(next_a.y) + dy * scale_a),
			real_t(double(next_a.z) + dz * scale_a)
		};
		const Vector3 projected_b{
			real_t(double(next_b.x) + dx * scale_b),
			real_t(double(next_b.y) + dy * scale_b),
			real_t(double(next_b.z) + dz * scale_b)
		};
		if (!projected_a.is_finite() || !projected_b.is_finite()) {
			return false;
		}
		next_a = projected_a;
		next_b = projected_b;
		lambda = next_lambda;
		changed = true;
	}

	if (!changed) {
		return false;
	}
	r_a = next_a;
	r_b = next_b;
	r_lambdas = next_lambdas;
	return true;
}
