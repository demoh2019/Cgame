/**************************************************************************/
/*  physics_xpbd_soft_ccd.h                                               */
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

#include "servers/physics_xpbd_self_collision.h"

// Swept vertex against a LINEARLY moving triangle. The oriented plane
// determinant is a cubic polynomial in t. Splitting [0,1] at its quadratic
// derivative's stationary points makes every interval monotone; bracketing
// and bisection cannot miss a transversal plane crossing just because the
// moving face changes orientation or the endpoints lie on the same side.
// Barycentric containment at the first crossing disallows infinite-plane
// contacts. This is continuous vertex/face detection, not edge/edge CCD.
struct PhysicsXPBDSoftCCDSweepHit {
	Vector3 barycentric;
	Vector3 separating_normal;
	real_t time = 1.0;
};

_FORCE_INLINE_ bool physics_xpbd_swept_vertex_triangle(
		const Vector3 &p_prev_vertex, const Vector3 &p_curr_vertex,
		const Vector3 &p_prev_a, const Vector3 &p_curr_a,
		const Vector3 &p_prev_b, const Vector3 &p_curr_b,
		const Vector3 &p_prev_c, const Vector3 &p_curr_c,
		PhysicsXPBDSoftCCDSweepHit &r_hit) {
	if (!p_prev_vertex.is_finite() || !p_curr_vertex.is_finite() ||
			!p_prev_a.is_finite() || !p_curr_a.is_finite() ||
			!p_prev_b.is_finite() || !p_curr_b.is_finite() ||
			!p_prev_c.is_finite() || !p_curr_c.is_finite()) {
		return false;
	}

	const Vector3 p0 = p_prev_vertex - p_prev_a;
	const Vector3 dp = (p_curr_vertex - p_prev_vertex) - (p_curr_a - p_prev_a);
	const Vector3 u0 = p_prev_b - p_prev_a;
	const Vector3 du = (p_curr_b - p_prev_b) - (p_curr_a - p_prev_a);
	const Vector3 v0 = p_prev_c - p_prev_a;
	const Vector3 dv = (p_curr_c - p_prev_c) - (p_curr_a - p_prev_a);
	const Vector3 cross0 = u0.cross(v0);
	const Vector3 cross1 = du.cross(v0) + u0.cross(dv);
	const Vector3 cross2 = du.cross(dv);
	const double raw_c[4] = {
		double(p0.dot(cross0)),
		double(dp.dot(cross0)) + double(p0.dot(cross1)),
		double(dp.dot(cross1)) + double(p0.dot(cross2)),
		double(dp.dot(cross2)),
	};
	const real_t start_normal_squared = cross0.length_squared();
	if (!(start_normal_squared > CMP_EPSILON * CMP_EPSILON) ||
			!Math::is_finite(start_normal_squared)) {
		return false;
	}
	const real_t signed_start = p0.dot(cross0) / Math::sqrt(start_normal_squared);
	if (!Math::is_finite(signed_start) || Math::abs(signed_start) <= CMP_EPSILON) {
		return false;
	}
	double scale = 0.0;
	for (double coefficient : raw_c) {
		if (!Math::is_finite(coefficient)) {
			return false;
		}
		scale = MAX(scale, Math::abs(coefficient));
	}
	if (!(scale > 0.0)) {
		return false;
	}
	const double c0 = raw_c[0] / scale;
	const double c1 = raw_c[1] / scale;
	const double c2 = raw_c[2] / scale;
	const double c3 = raw_c[3] / scale;
	const auto evaluate = [&](double t) -> double {
		return ((c3 * t + c2) * t + c1) * t + c0;
	};

	// Quadratic derivative 3*c3*t^2 + 2*c2*t + c1.
	// There are at most two interior turning points and three root intervals.
	double cuts[4] = { 0.0, 1.0, 1.0, 1.0 };
	int count = 1;
	if (Math::abs(c3) > 1e-12) {
		const double discriminant = c2 * c2 - 3.0 * c3 * c1;
		if (discriminant > 0.0 && Math::is_finite(discriminant)) {
			const double root = Math::sqrt(discriminant);
			const double t0 = (-c2 - root) / (3.0 * c3);
			const double t1 = (-c2 + root) / (3.0 * c3);
			if (t0 > 0.0 && t0 < 1.0) {
				cuts[count++] = t0;
			}
			if (t1 > 0.0 && t1 < 1.0) {
				cuts[count++] = t1;
			}
		}
	} else if (Math::abs(c2) > 1e-12) {
		const double t = -c1 / (2.0 * c2);
		if (t > 0.0 && t < 1.0) {
			cuts[count++] = t;
		}
	}
	if (count == 3 && cuts[1] > cuts[2]) {
		SWAP(cuts[1], cuts[2]);
	}
	cuts[count++] = 1.0;

	const int side = signed_start >= 0.0 ? 1 : -1;
	for (int interval = 0; interval < count - 1; ++interval) {
		double lo = cuts[interval];
		double hi = cuts[interval + 1];
		const double v0 = evaluate(lo);
		const double v1 = evaluate(hi);
		// Tangential plane touches (even-multiplicity roots) are not crossings.
		if (!Math::is_finite(v0) || !Math::is_finite(v1) ||
				!((v0 < 0.0 && v1 > 0.0) || (v0 > 0.0 && v1 < 0.0))) {
			continue;
		}
		const bool left_positive = v0 > 0.0;
		for (int j = 0; j < 24; ++j) {
			const double mid = (lo + hi) * 0.5;
			const double vmid = evaluate(mid);
			if ((vmid > 0.0) == left_positive) {
				lo = mid;
			} else {
				hi = mid;
			}
		}
		const real_t t = real_t((lo + hi) * 0.5);
		const Vector3 vertex = p_prev_vertex.lerp(p_curr_vertex, t);
		const Vector3 a = p_prev_a.lerp(p_curr_a, t);
		const Vector3 b = p_prev_b.lerp(p_curr_b, t);
		const Vector3 c = p_prev_c.lerp(p_curr_c, t);
		Vector3 normal;
		Vector3 barycentric;
		real_t distance = 0.0;
		if (!physics_xpbd_self_collision_face_projection(
					vertex, a, b, c, normal, barycentric, distance)) {
			continue;
		}
		r_hit.barycentric = barycentric;
		r_hit.separating_normal = normal * real_t(side);
		r_hit.time = t;
		return true;
	}
	return false;
}

// Resolve a swept crossing against the CURRENT face location using the
// impact-time barycentric witness and oriented impact normal. This preserves
// the original side even when the vertex finishes far past the triangle.
// The contact is unilateral; no attraction if geometry is already separated.
// The XPBD multiplier is retained across iterations but reset each step.
// All proposed positions must be finite before any write.
_FORCE_INLINE_ bool physics_xpbd_solve_swept_vertex_face(
		Vector3 &r_vertex, Vector3 &r_a, Vector3 &r_b, Vector3 &r_c,
		real_t p_inv_vertex, real_t p_inv_a, real_t p_inv_b, real_t p_inv_c,
		real_t p_thickness, real_t p_alpha,
		const PhysicsXPBDSoftCCDSweepHit &p_hit, real_t &r_lambda) {
	if (!(p_thickness > 0.0) || !Math::is_finite(p_thickness) ||
			p_inv_vertex < 0.0 || p_inv_a < 0.0 || p_inv_b < 0.0 || p_inv_c < 0.0 ||
			!Math::is_finite(p_inv_vertex) || !Math::is_finite(p_inv_a) ||
			!Math::is_finite(p_inv_b) || !Math::is_finite(p_inv_c) ||
			!Math::is_finite(p_alpha) || p_alpha < 0.0 ||
			!Math::is_finite(r_lambda) || r_lambda < 0.0 ||
			!p_hit.barycentric.is_finite() || !p_hit.separating_normal.is_finite() ||
			!r_vertex.is_finite() || !r_a.is_finite() || !r_b.is_finite() || !r_c.is_finite()) {
		return false;
	}
	const Vector3 normal = p_hit.separating_normal;
	const double normal_squared = double(normal.length_squared());
	if (!(normal_squared > 0.5 && normal_squared < 1.5)) {
		return false;
	}
	const double wa = double(p_hit.barycentric.x);
	const double wb = double(p_hit.barycentric.y);
	const double wc = double(p_hit.barycentric.z);
	if (wa < 0.0 || wb < 0.0 || wc < 0.0 ||
			wa > 1.0 || wb > 1.0 || wc > 1.0) {
		return false;
	}
	const Vector3 face_point = r_a * real_t(wa) + r_b * real_t(wb) + r_c * real_t(wc);
	const double separation = double((r_vertex - face_point).dot(normal));
	const double w_sum = double(p_inv_vertex) +
			wa * wa * double(p_inv_a) + wb * wb * double(p_inv_b) +
			wc * wc * double(p_inv_c);
	const double denominator = w_sum * normal_squared + double(p_alpha);
	if (!(w_sum > 0.0) || !(denominator > 0.0) ||
			!Math::is_finite(separation) || !Math::is_finite(denominator)) {
		return false;
	}
	const double delta_lambda = (double(p_thickness) - separation -
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
				real_t(double(p_position.x) + double(normal.x) * impulse * p_mass_weight),
				real_t(double(p_position.y) + double(normal.y) * impulse * p_mass_weight),
				real_t(double(p_position.z) + double(normal.z) * impulse * p_mass_weight));
	};
	const Vector3 next_vertex = corrected(r_vertex, double(p_inv_vertex));
	const Vector3 next_a = corrected(r_a, -wa * double(p_inv_a));
	const Vector3 next_b = corrected(r_b, -wb * double(p_inv_b));
	const Vector3 next_c = corrected(r_c, -wc * double(p_inv_c));
	if (!next_vertex.is_finite() || !next_a.is_finite() ||
			!next_b.is_finite() || !next_c.is_finite()) {
		return false;
	}
	r_vertex = next_vertex;
	r_a = next_a;
	r_b = next_b;
	r_c = next_c;
	r_lambda = next_lambda;
	return true;
}
