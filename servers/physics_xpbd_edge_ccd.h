/**************************************************************************/
/*  physics_xpbd_edge_ccd.h                                               */
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

#include "servers/physics_xpbd_edge_collision.h"

// Two linearly moving, non-parallel open edges can cross even if they are
// far apart at BOTH step endpoints. Their coplanarity determinant is cubic:
//    dot(d(t) - a(t), cross(b(t) - a(t), c(t) - a(t))) = 0.
// Bracket roots on every monotone interval (the cubic derivative is
// quadratic), then validate that the two FINITE segments overlap at the
// candidate instant. This detects transversal crossings without temporal
// sampling or allocations. Tangencies, persistent coplanarity and edge
// endpoints are intentionally outside this narrowphase's scope.
struct PhysicsXPBDEdgeCCDHit {
	real_t time = 1.0;
	real_t s = 0.0;
	real_t t = 0.0;
	Vector3 normal;
};

_FORCE_INLINE_ bool physics_xpbd_swept_edge_edge(
		const Vector3 &p_prev_a, const Vector3 &p_curr_a,
		const Vector3 &p_prev_b, const Vector3 &p_curr_b,
		const Vector3 &p_prev_c, const Vector3 &p_curr_c,
		const Vector3 &p_prev_d, const Vector3 &p_curr_d,
		PhysicsXPBDEdgeCCDHit &r_hit) {
	if (!p_prev_a.is_finite() || !p_curr_a.is_finite() ||
			!p_prev_b.is_finite() || !p_curr_b.is_finite() ||
			!p_prev_c.is_finite() || !p_curr_c.is_finite() ||
			!p_prev_d.is_finite() || !p_curr_d.is_finite()) {
		return false;
	}
	const Vector3 u0 = p_prev_b - p_prev_a;
	const Vector3 v0 = p_prev_c - p_prev_a;
	const Vector3 w0 = p_prev_d - p_prev_a;
	const Vector3 du = (p_curr_b - p_prev_b) - (p_curr_a - p_prev_a);
	const Vector3 dv = (p_curr_c - p_prev_c) - (p_curr_a - p_prev_a);
	const Vector3 dw = (p_curr_d - p_prev_d) - (p_curr_a - p_prev_a);

	const Vector3 cross0 = u0.cross(v0);
	const Vector3 cross1 = du.cross(v0) + u0.cross(dv);
	const Vector3 cross2 = du.cross(dv);
	const double raw[4] = {
		double(w0.dot(cross0)),
		double(dw.dot(cross0)) + double(w0.dot(cross1)),
		double(dw.dot(cross1)) + double(w0.dot(cross2)),
		double(dw.dot(cross2)),
	};
	// Completely coplanar starts are deliberately delegated to discrete
	// collisions. A near-zero polynomial is also not a reliable direction.
	double scale = 0.0;
	for (double coefficient : raw) {
		if (!Math::is_finite(coefficient)) {
			return false;
		}
		scale = MAX(scale, Math::abs(coefficient));
	}
	if (!(scale > 0.0) || Math::abs(raw[0]) <= scale * 1e-10) {
		return false;
	}
	const double c0 = raw[0] / scale;
	const double c1 = raw[1] / scale;
	const double c2 = raw[2] / scale;
	const double c3 = raw[3] / scale;
	const auto evaluate = [&](double p_t) -> double {
		return ((c3 * p_t + c2) * p_t + c1) * p_t + c0;
	};
	double cut[4] = { 0.0, 1.0, 1.0, 1.0 };
	int count = 1;
	if (Math::abs(c3) > 1e-12) {
		const double discriminant = c2 * c2 - 3.0 * c3 * c1;
		if (discriminant > 0.0 && Math::is_finite(discriminant)) {
			const double root = Math::sqrt(discriminant);
			const double t0 = (-c2 - root) / (3.0 * c3);
			const double t1 = (-c2 + root) / (3.0 * c3);
			if (t0 > 0.0 && t0 < 1.0) {
				cut[count++] = t0;
			}
			if (t1 > 0.0 && t1 < 1.0) {
				cut[count++] = t1;
			}
		}
	} else if (Math::abs(c2) > 1e-12) {
		const double t = -c1 / (2.0 * c2);
		if (t > 0.0 && t < 1.0) {
			cut[count++] = t;
		}
	}
	if (count == 3 && cut[1] > cut[2]) {
		SWAP(cut[1], cut[2]);
	}
	cut[count++] = 1.0;

	for (int interval = 0; interval < count - 1; ++interval) {
		double lo = cut[interval];
		double hi = cut[interval + 1];
		const double low = evaluate(lo);
		const double high = evaluate(hi);
		if (!Math::is_finite(low) || !Math::is_finite(high) ||
				!((low < 0.0 && high > 0.0) || (low > 0.0 && high < 0.0))) {
			continue;
		}
		const bool positive = low > 0.0;
		for (int j = 0; j < 28; ++j) {
			const double mid = 0.5 * (lo + hi);
			if ((evaluate(mid) > 0.0) == positive) {
				lo = mid;
			} else {
				hi = mid;
			}
		}
		const real_t time = real_t(0.5 * (lo + hi));
		const Vector3 a = p_prev_a.lerp(p_curr_a, time);
		const Vector3 b = p_prev_b.lerp(p_curr_b, time);
		const Vector3 c = p_prev_c.lerp(p_curr_c, time);
		const Vector3 d = p_prev_d.lerp(p_curr_d, time);
		real_t s, t, distance;
		Vector3 ignored_normal;
		// The existing narrowphase requires two non-parallel edges and
		// strictly interior closest points. This avoids interpreting
		// infinitely extended line crossings as segment collisions.
		if (!physics_xpbd_closest_edges(a, b, c, d, s, t, ignored_normal, distance)) {
			continue;
		}
		const Vector3 ab = b - a;
		const Vector3 cd = d - c;
		const real_t edge_scale = MAX(ab.length(), cd.length());
		if (!Math::is_finite(edge_scale) ||
				distance > MAX(real_t(1e-5), edge_scale * real_t(1e-5))) {
			continue;
		}
		const Vector3 normal = ab.cross(cd).normalized();
		if (!normal.is_finite() || normal.length_squared() < real_t(0.5)) {
			continue;
		}
		r_hit.time = time;
		r_hit.s = s;
		r_hit.t = t;
		r_hit.normal = raw[0] >= 0.0 ? normal : -normal;
		return true; // Earliest valid interior root in chronological order.
	}
	return false;
}

// A swept collision witness has fixed barycentric coordinates and impact
// normal; recomputing end-position closest points would miss a pair that
// finished on the other side. This row is unilateral and mass-weighted.
// It is solved AFTER pre-impact rewinds of movable particles; all proposed
// positions and multipliers are checked before committing.
_FORCE_INLINE_ bool physics_xpbd_solve_swept_edge_edge(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c, real_t p_inv_d,
		real_t p_thickness, real_t p_alpha, const PhysicsXPBDEdgeCCDHit &p_hit,
		real_t &r_lambda) {
	if (!(p_thickness > 0.0) || !Math::is_finite(p_thickness) ||
			!Math::is_finite(p_alpha) || p_alpha < 0.0 ||
			!Math::is_finite(r_lambda) || r_lambda < 0.0 ||
			!Math::is_finite(p_inv_a) || !Math::is_finite(p_inv_b) ||
			!Math::is_finite(p_inv_c) || !Math::is_finite(p_inv_d) ||
			p_inv_a < 0.0 || p_inv_b < 0.0 || p_inv_c < 0.0 || p_inv_d < 0.0 ||
			!Math::is_finite(p_hit.s) || !Math::is_finite(p_hit.t) ||
			p_hit.s < 0.0 || p_hit.s > 1.0 || p_hit.t < 0.0 || p_hit.t > 1.0 ||
			!p_hit.normal.is_finite()) {
		return false;
	}
	const double wa = 1.0 - double(p_hit.s);
	const double wb = double(p_hit.s);
	const double wc = 1.0 - double(p_hit.t);
	const double wd = double(p_hit.t);
	const double weighted_mass = double(p_inv_a) * wa * wa + double(p_inv_b) * wb * wb +
			double(p_inv_c) * wc * wc + double(p_inv_d) * wd * wd;
	const double normal_sq = double(p_hit.normal.length_squared());
	const double denom = weighted_mass * normal_sq + double(p_alpha);
	if (!(weighted_mass > 0.0) || !(normal_sq > 0.5 && normal_sq < 1.5) ||
			!(denom > 0.0) || !Math::is_finite(denom)) {
		return false;
	}
	const Vector3 first = r_a * real_t(wa) + r_b * real_t(wb);
	const Vector3 second = r_c * real_t(wc) + r_d * real_t(wd);
	const double separation = double((first - second).dot(p_hit.normal));
	const double delta_lambda = (double(p_thickness) - separation -
			double(p_alpha) * double(r_lambda)) / denom;
	if (!Math::is_finite(separation) || !Math::is_finite(delta_lambda)) {
		return false;
	}
	const double next_lambda_double = MAX(0.0, double(r_lambda) + delta_lambda);
	const real_t next_lambda = real_t(next_lambda_double);
	if (!Math::is_finite(next_lambda)) {
		return false;
	}
	const double impulse = next_lambda_double - double(r_lambda);
	const auto corrected = [&](const Vector3 &p_position, double p_weight) -> Vector3 {
		return Vector3(
				real_t(double(p_position.x) + double(p_hit.normal.x) * p_weight * impulse),
				real_t(double(p_position.y) + double(p_hit.normal.y) * p_weight * impulse),
				real_t(double(p_position.z) + double(p_hit.normal.z) * p_weight * impulse));
	};
	const Vector3 next_a = corrected(r_a, double(p_inv_a) * wa);
	const Vector3 next_b = corrected(r_b, double(p_inv_b) * wb);
	const Vector3 next_c = corrected(r_c, -double(p_inv_c) * wc);
	const Vector3 next_d = corrected(r_d, -double(p_inv_d) * wd);
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
