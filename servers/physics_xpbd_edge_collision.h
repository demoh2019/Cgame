/**************************************************************************/
/*  physics_xpbd_edge_collision.h                                         */
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

// Narrowphase for TWO nonparallel structural mesh edges. Only an interior
// closest-point pair is handled: endpoint contacts belong to the existing
// vertex/triangle solver. Parallel/degenerate/invalid edges are rejected.
// Returns a unit separating normal pointing from edge CD toward edge AB.
// When the edges cross exactly, the cross product gives a stable fallback.
_FORCE_INLINE_ bool physics_xpbd_closest_edges(
		const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c, const Vector3 &p_d,
		real_t &r_s, real_t &r_t, Vector3 &r_normal, real_t &r_distance) {
	if (!p_a.is_finite() || !p_b.is_finite() || !p_c.is_finite() || !p_d.is_finite()) {
		return false;
	}
	const Vector3 ab = p_b - p_a;
	const Vector3 cd = p_d - p_c;
	const Vector3 r = p_a - p_c;
	const double aa = double(ab.dot(ab));
	const double bb = double(ab.dot(cd));
	const double cc = double(cd.dot(cd));
	const double dd = double(ab.dot(r));
	const double ee = double(cd.dot(r));
	const double denominator = aa * cc - bb * bb;
	if (!(aa > double(CMP_EPSILON) * CMP_EPSILON) ||
			!(cc > double(CMP_EPSILON) * CMP_EPSILON) ||
			!(denominator > double(CMP_EPSILON) * aa * cc) ||
			!Math::is_finite(denominator)) {
		return false;
	}
	const double s = (bb * ee - cc * dd) / denominator;
	const double t = (aa * ee - bb * dd) / denominator;
	// Exclude endpoints: they are not genuine edge/edge interior contacts.
	if (!Math::is_finite(s) || !Math::is_finite(t) ||
			s <= 0.001 || s >= 0.999 || t <= 0.001 || t >= 0.999) {
		return false;
	}
	const Vector3 p = p_a + ab * real_t(s);
	const Vector3 q = p_c + cd * real_t(t);
	const Vector3 separation = p - q;
	const real_t distance_squared = separation.length_squared();
	if (!Math::is_finite(distance_squared)) {
		return false;
	}
	r_distance = Math::sqrt(distance_squared);
	if (r_distance > CMP_EPSILON) {
		r_normal = separation / r_distance;
	} else {
		r_normal = ab.cross(cd).normalized();
	}
	if (!r_normal.is_finite() || !(r_normal.length_squared() > 0.0)) {
		return false;
	}
	r_s = real_t(s);
	r_t = real_t(t);
	return true;
}

// One unilateral XPBD edge/edge distance row. The contact normal is kept
// FIXED across iterations and chosen from previous geometry when possible,
// so the solver does not flip its correction when two edges cross.
// p_alpha=compliance/(dt*dt), lambda is nonnegative and accumulates only
// inside the current step. Four inverse masses preserve exact pins.
// All proposed vertex positions are checked before committing anything.
_FORCE_INLINE_ bool physics_xpbd_solve_edge_collision(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c, real_t p_inv_d,
		real_t p_thickness, real_t p_alpha, const Vector3 &p_normal, real_t &r_lambda) {
	if (!(p_thickness > 0.0) || !Math::is_finite(p_thickness) ||
			!Math::is_finite(p_alpha) || p_alpha < 0.0 || !Math::is_finite(r_lambda) ||
			r_lambda < 0.0 || !p_normal.is_finite() ||
			!Math::is_finite(p_inv_a) || !Math::is_finite(p_inv_b) ||
			!Math::is_finite(p_inv_c) || !Math::is_finite(p_inv_d) ||
			p_inv_a < 0.0 || p_inv_b < 0.0 || p_inv_c < 0.0 || p_inv_d < 0.0) {
		return false;
	}
	real_t s, t, distance;
	Vector3 computed_normal;
	if (!physics_xpbd_closest_edges(r_a, r_b, r_c, r_d, s, t, computed_normal, distance) ||
			Math::abs(distance) > p_thickness * real_t(2.0)) {
		return false;
	}
	const Vector3 ab = r_b - r_a;
	const Vector3 cd = r_d - r_c;
	const Vector3 pa = r_a + ab * s;
	const Vector3 pb = r_c + cd * t;
	const real_t signed_separation = (pa - pb).dot(p_normal);
	if (!Math::is_finite(signed_separation)) {
		return false;
	}
	const double wa = 1.0 - double(s);
	const double wb = double(s);
	const double wc = 1.0 - double(t);
	const double wd = double(t);
	const double weighted_mass =
			double(p_inv_a) * wa * wa + double(p_inv_b) * wb * wb +
			double(p_inv_c) * wc * wc + double(p_inv_d) * wd * wd;
	const double denominator = weighted_mass + double(p_alpha);
	if (!(weighted_mass > 0.0) || !(denominator > 0.0) || !Math::is_finite(denominator)) {
		return false;
	}
	const double delta_lambda = (double(p_thickness) - double(signed_separation) -
			double(p_alpha) * double(r_lambda)) / denominator;
	if (!Math::is_finite(delta_lambda)) {
		return false;
	}
	const double next_lambda_double = MAX(0.0, double(r_lambda) + delta_lambda);
	const real_t next_lambda = real_t(next_lambda_double);
	if (!Math::is_finite(next_lambda)) {
		return false;
	}
	const double impulse = next_lambda_double - double(r_lambda);
	const auto corrected = [&](const Vector3 &p_position, double p_mass_weight) -> Vector3 {
		return Vector3(
				real_t(double(p_position.x) + double(p_normal.x) * p_mass_weight * impulse),
				real_t(double(p_position.y) + double(p_normal.y) * p_mass_weight * impulse),
				real_t(double(p_position.z) + double(p_normal.z) * p_mass_weight * impulse));
	};
	const Vector3 next_a = corrected(r_a, double(p_inv_a) * wa);
	const Vector3 next_b = corrected(r_b, double(p_inv_b) * wb);
	const Vector3 next_c = corrected(r_c, -double(p_inv_c) * wc);
	const Vector3 next_d = corrected(r_d, -double(p_inv_d) * wd);
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
