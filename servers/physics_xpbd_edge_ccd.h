/**************************************************************************/
/*  physics_xpbd_edge_ccd.h                                               */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "servers/physics_xpbd_edge_collision.h"

// A witness for an interior edge/edge intersection at a time in [0, 1].
// Only linearly interpolated endpoints and transversal (sign-changing)
// coplanarity roots are supported. Coplanar sliding, tangential touches,
// parallel edges and shared-topology contacts are handled elsewhere or
// deliberately rejected by this experimental narrowphase.
struct PhysicsXPBDEdgeCCDHit {
	real_t first_weight = 0.5;
	real_t second_weight = 0.5;
	real_t time = 1.0;
	Vector3 separating_normal;
};

// For moving segments AB, CD the scalar triple product
// (A-C).dot((B-A).cross(D-C)) is cubic in time. Splitting its roots at
// derivative extrema finds *all transversal plane crossings*, even if the
// start and end determinants have the same sign. Only actual interior
// segment intersections qualify; an infinite-plane crossing is not enough.
// No heap allocation: maximum two derivative roots and three intervals.
_FORCE_INLINE_ bool physics_xpbd_swept_edges(
		const Vector3 &p_prev_a, const Vector3 &p_curr_a,
		const Vector3 &p_prev_b, const Vector3 &p_curr_b,
		const Vector3 &p_prev_c, const Vector3 &p_curr_c,
		const Vector3 &p_prev_d, const Vector3 &p_curr_d,
		real_t p_thickness, PhysicsXPBDEdgeCCDHit &r_hit) {
	if (!(p_thickness > real_t(0.0)) || !Math::is_finite(p_thickness) ||
			!p_prev_a.is_finite() || !p_curr_a.is_finite() ||
			!p_prev_b.is_finite() || !p_curr_b.is_finite() ||
			!p_prev_c.is_finite() || !p_curr_c.is_finite() ||
			!p_prev_d.is_finite() || !p_curr_d.is_finite()) {
		return false;
	}
	const Vector3 u0 = p_prev_b - p_prev_a;
	const Vector3 du = (p_curr_b - p_prev_b) - (p_curr_a - p_prev_a);
	const Vector3 v0 = p_prev_d - p_prev_c;
	const Vector3 dv = (p_curr_d - p_prev_d) - (p_curr_c - p_prev_c);
	const Vector3 w0 = p_prev_a - p_prev_c;
	const Vector3 dw = (p_curr_a - p_prev_a) - (p_curr_c - p_prev_c);
	if (!u0.is_finite() || !du.is_finite() || !v0.is_finite() ||
			!dv.is_finite() || !w0.is_finite() || !dw.is_finite()) {
		return false;
	}

	const Vector3 cross0 = u0.cross(v0);
	const Vector3 cross1 = du.cross(v0) + u0.cross(dv);
	const Vector3 cross2 = du.cross(dv);
	if (!cross0.is_finite() || !cross1.is_finite() || !cross2.is_finite()) {
		return false;
	}
	const double raw[4] = {
		double(w0.dot(cross0)),
		double(dw.dot(cross0)) + double(w0.dot(cross1)),
		double(dw.dot(cross1)) + double(w0.dot(cross2)),
		double(dw.dot(cross2)),
	};
	double scale = 0.0;
	for (double coefficient : raw) {
		if (!Math::is_finite(coefficient)) {
			return false;
		}
		scale = MAX(scale, Math::abs(coefficient));
	}
	if (!(scale > 0.0)) {
		return false; // Permanently coplanar segments: not a transversal hit.
	}
	const double c0 = raw[0] / scale;
	const double c1 = raw[1] / scale;
	const double c2 = raw[2] / scale;
	const double c3 = raw[3] / scale;
	const auto evaluate = [&](double p_time) -> double {
		return ((c3 * p_time + c2) * p_time + c1) * p_time + c0;
	};

	double cuts[4] = { 0.0, 1.0, 1.0, 1.0 };
	int cut_count = 1;
	if (Math::abs(c3) > 1e-12) {
		const double discriminant = c2 * c2 - 3.0 * c3 * c1;
		if (discriminant > 0.0 && Math::is_finite(discriminant)) {
			const double root = Math::sqrt(discriminant);
			const double t0 = (-c2 - root) / (3.0 * c3);
			const double t1 = (-c2 + root) / (3.0 * c3);
			if (t0 > 0.0 && t0 < 1.0) {
				cuts[cut_count++] = t0;
			}
			if (t1 > 0.0 && t1 < 1.0) {
				cuts[cut_count++] = t1;
			}
		}
	} else if (Math::abs(c2) > 1e-12) {
		const double t = -c1 / (2.0 * c2);
		if (t > 0.0 && t < 1.0) {
			cuts[cut_count++] = t;
		}
	}
	if (cut_count == 3 && cuts[1] > cuts[2]) {
		SWAP(cuts[1], cuts[2]);
	}
	cuts[cut_count++] = 1.0;

	for (int interval = 0; interval < cut_count - 1; ++interval) {
		double lo = cuts[interval];
		double hi = cuts[interval + 1];
		const double f_lo = evaluate(lo);
		const double f_hi = evaluate(hi);
		if (!Math::is_finite(f_lo) || !Math::is_finite(f_hi) ||
				!((f_lo < 0.0 && f_hi > 0.0) || (f_lo > 0.0 && f_hi < 0.0))) {
			continue;
		}
		const bool left_positive = f_lo > 0.0;
		for (int step = 0; step < 32; ++step) {
			const double mid = (lo + hi) * 0.5;
			const double f_mid = evaluate(mid);
			if ((f_mid > 0.0) == left_positive) {
				lo = mid;
			} else {
				hi = mid;
			}
		}
		const real_t t = real_t((lo + hi) * 0.5);
		const Vector3 a = p_prev_a.lerp(p_curr_a, t);
		const Vector3 b = p_prev_b.lerp(p_curr_b, t);
		const Vector3 c = p_prev_c.lerp(p_curr_c, t);
		const Vector3 d = p_prev_d.lerp(p_curr_d, t);
		real_t s = 0.0;
		real_t u = 0.0;
		real_t distance = 0.0;
		Vector3 closest_normal;
		if (!physics_xpbd_closest_edges(a, b, c, d, s, u, closest_normal, distance) ||
				double(distance) > MAX(1e-5, double(p_thickness) * 0.25)) {
			continue;
		}
		const Vector3 raw_normal = (b - a).cross(d - c);
		const real_t length_squared = raw_normal.length_squared();
		if (!(length_squared > CMP_EPSILON * CMP_EPSILON) ||
				!Math::is_finite(length_squared)) {
			continue;
		}
		Vector3 normal = raw_normal / Math::sqrt(length_squared);
		// Orient toward the ORIGINAL side of the closest-point pair.
		const Vector3 previous_first = p_prev_a + (p_prev_b - p_prev_a) * s;
		const Vector3 previous_second = p_prev_c + (p_prev_d - p_prev_c) * u;
		const double previous_side = double((previous_first - previous_second).dot(normal));
		if (!Math::is_finite(previous_side) || Math::abs(previous_side) <= 1e-8) {
			continue;
		}
		if (previous_side < 0.0) {
			normal = -normal;
		}
		PhysicsXPBDEdgeCCDHit hit;
		hit.first_weight = s;
		hit.second_weight = u;
		hit.time = t;
		hit.separating_normal = normal;
		r_hit = hit;
		return true;
	}
	return false;
}

// Positional XPBD response using the contact weights frozen at impact time.
// Unlike the DISCRETE edge/edge row, this does not require the CURRENT
// closest pair to remain within the collision margin, so a fast crossing
// that ends on the wrong side is still corrected. No attraction, no changes
// to pins, no partial writes on invalid values.
_FORCE_INLINE_ bool physics_xpbd_solve_swept_edges(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c, real_t p_inv_d,
		real_t p_thickness, real_t p_alpha,
		const PhysicsXPBDEdgeCCDHit &p_hit, real_t &r_lambda) {
	if (!(p_thickness > real_t(0.0)) || !Math::is_finite(p_thickness) ||
			!Math::is_finite(p_alpha) || p_alpha < real_t(0.0) ||
			!Math::is_finite(r_lambda) || r_lambda < real_t(0.0) ||
			!Math::is_finite(p_inv_a) || !Math::is_finite(p_inv_b) ||
			!Math::is_finite(p_inv_c) || !Math::is_finite(p_inv_d) ||
			p_inv_a < real_t(0.0) || p_inv_b < real_t(0.0) ||
			p_inv_c < real_t(0.0) || p_inv_d < real_t(0.0) ||
			!Math::is_finite(p_hit.first_weight) ||
			!Math::is_finite(p_hit.second_weight) ||
			!p_hit.separating_normal.is_finite() ||
			!r_a.is_finite() || !r_b.is_finite() ||
			!r_c.is_finite() || !r_d.is_finite()) {
		return false;
	}
	const double s = double(p_hit.first_weight);
	const double t = double(p_hit.second_weight);
	if (!(s > 0.0 && s < 1.0 && t > 0.0 && t < 1.0)) {
		return false;
	}
	const Vector3 &normal = p_hit.separating_normal;
	const double n2 = double(normal.length_squared());
	if (!(n2 > 0.99 && n2 < 1.01)) {
		return false;
	}
	const double wa = 1.0 - s;
	const double wb = s;
	const double wc = 1.0 - t;
	const double wd = t;
	const double mass = wa * wa * double(p_inv_a) + wb * wb * double(p_inv_b) +
			wc * wc * double(p_inv_c) + wd * wd * double(p_inv_d);
	const double denom = mass * n2 + double(p_alpha);
	if (!(mass > 0.0) || !Math::is_finite(denom) || !(denom > 0.0)) {
		return false;
	}
	// Wide accumulation of weighted relative separation at the end of step.
	// Translate the weighted pair to the same origin before taking the
	// contact gap. This avoids subtracting four huge world-space sums.
	const double sx = wa * (double(r_a.x) - double(r_c.x)) +
			wb * (double(r_b.x) - double(r_c.x)) -
			wd * (double(r_d.x) - double(r_c.x));
	const double sy = wa * (double(r_a.y) - double(r_c.y)) +
			wb * (double(r_b.y) - double(r_c.y)) -
			wd * (double(r_d.y) - double(r_c.y));
	const double sz = wa * (double(r_a.z) - double(r_c.z)) +
			wb * (double(r_b.z) - double(r_c.z)) -
			wd * (double(r_d.z) - double(r_c.z));
	const double gap = sx * double(normal.x) + sy * double(normal.y) +
			sz * double(normal.z);
	const double dlambda = (double(p_thickness) - gap -
			double(p_alpha) * double(r_lambda)) / denom;
	if (!Math::is_finite(dlambda)) {
		return false;
	}
	const double next_double = MAX(0.0, double(r_lambda) + dlambda);
	const real_t next_lambda = real_t(next_double);
	if (!Math::is_finite(next_lambda)) {
		return false;
	}
	const double impulse = next_double - double(r_lambda);
	const auto corrected = [&](const Vector3 &p, double p_factor) -> Vector3 {
		return Vector3(real_t(double(p.x) + double(normal.x) * impulse * p_factor),
				real_t(double(p.y) + double(normal.y) * impulse * p_factor),
				real_t(double(p.z) + double(normal.z) * impulse * p_factor));
	};
	const Vector3 na = corrected(r_a, double(p_inv_a) * wa);
	const Vector3 nb = corrected(r_b, double(p_inv_b) * wb);
	const Vector3 nc = corrected(r_c, -double(p_inv_c) * wc);
	const Vector3 nd = corrected(r_d, -double(p_inv_d) * wd);
	if (!na.is_finite() || !nb.is_finite() ||
			!nc.is_finite() || !nd.is_finite()) {
		return false;
	}
	r_a = na;
	r_b = nb;
	r_c = nc;
	r_d = nd;
	r_lambda = next_lambda;
	return true;
}
