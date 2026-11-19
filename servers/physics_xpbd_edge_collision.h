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

	// Wide coordinate differences are essential BEFORE calculating any dot
	// products. In float32 the squared length of a finite 1e20 edge overflows,
	// while an edge shorter than CMP_EPSILON can still represent a valid
	// piece of cloth at a smaller world scale.
	const double ab_x = double(p_b.x) - double(p_a.x);
	const double ab_y = double(p_b.y) - double(p_a.y);
	const double ab_z = double(p_b.z) - double(p_a.z);
	const double cd_x = double(p_d.x) - double(p_c.x);
	const double cd_y = double(p_d.y) - double(p_c.y);
	const double cd_z = double(p_d.z) - double(p_c.z);
	const double r_x = double(p_a.x) - double(p_c.x);
	const double r_y = double(p_a.y) - double(p_c.y);
	const double r_z = double(p_a.z) - double(p_c.z);

	const double aa = ab_x * ab_x + ab_y * ab_y + ab_z * ab_z;
	const double bb = ab_x * cd_x + ab_y * cd_y + ab_z * cd_z;
	const double cc = cd_x * cd_x + cd_y * cd_y + cd_z * cd_z;
	const double dd = ab_x * r_x + ab_y * r_y + ab_z * r_z;
	const double ee = cd_x * r_x + cd_y * r_y + cd_z * r_z;

	const double cross_x = ab_y * cd_z - ab_z * cd_y;
	const double cross_y = ab_z * cd_x - ab_x * cd_z;
	const double cross_z = ab_x * cd_y - ab_y * cd_x;
	const double cross_squared = cross_x * cross_x + cross_y * cross_y + cross_z * cross_z;
	const double edge_scale = aa * cc;
	// |ab x cd|² is the Gram determinant aa*cc-bb², but without
	// catastrophic subtraction near parallel edges. The angular test
	// preserves the old CMP_EPSILON parallel exclusion while allowing
	// extremely small yet nondegenerate structural edges.
	if (!(aa > 0.0) || !(cc > 0.0) || !Math::is_finite(edge_scale) ||
			!Math::is_finite(cross_squared) ||
			!(cross_squared > double(CMP_EPSILON) * edge_scale)) {
		return false;
	}

	const double s = (bb * ee - cc * dd) / cross_squared;
	const double t = (aa * ee - bb * dd) / cross_squared;
	// Endpoint and parallel contacts belong to other constraint types.
	if (!Math::is_finite(s) || !Math::is_finite(t) ||
			s <= 0.001 || s >= 0.999 || t <= 0.001 || t >= 0.999) {
		return false;
	}

	// Compute the two closest points in double, not in real_t, and never
	// square their real_t separation: that still overflows for large meshes.
	const double dx = (double(p_a.x) + ab_x * s) - (double(p_c.x) + cd_x * t);
	const double dy = (double(p_a.y) + ab_y * s) - (double(p_c.y) + cd_y * t);
	const double dz = (double(p_a.z) + ab_z * s) - (double(p_c.z) + cd_z * t);
	const double distance_squared = dx * dx + dy * dy + dz * dz;
	if (!Math::is_finite(distance_squared)) {
		return false;
	}
	const double distance = Math::sqrt(distance_squared);
	// Select the actual separating direction for close but nonzero contacts.
	// Only use the edge cross product for a true/near intersection, with a
	// scale-relative tolerance instead of a fixed world-unit epsilon.
	const bool separated = distance_squared > MAX(aa, cc) * 1.0e-24;
	const double inv_length = 1.0 / Math::sqrt(separated ? distance_squared : cross_squared);
	const double nx = (separated ? dx : cross_x) * inv_length;
	const double ny = (separated ? dy : cross_y) * inv_length;
	const double nz = (separated ? dz : cross_z) * inv_length;
	const Vector3 next_normal{ real_t(nx), real_t(ny), real_t(nz) };
	const real_t next_distance = real_t(distance);
	if (!next_normal.is_finite() || !(next_normal.length_squared() > real_t(0.0)) ||
			!Math::is_finite(next_distance)) {
		return false;
	}

	// Atomic outputs: a rejected edge pair cannot leak partial s/t or
	// modified contact normal into the caller's candidate state.
	r_s = real_t(s);
	r_t = real_t(t);
	r_normal = next_normal;
	r_distance = next_distance;
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
	// The closest-edge narrowphase uses double for large/tiny meshes.
	// Keep that precision while computing the normal XPBD constraint:
	// rounding two interpolated world points back to float32 before their
	// subtraction can turn a tiny real gap into thousands of world units.
	const double pa_x = double(r_a.x) + (double(r_b.x) - double(r_a.x)) * double(s);
	const double pa_y = double(r_a.y) + (double(r_b.y) - double(r_a.y)) * double(s);
	const double pa_z = double(r_a.z) + (double(r_b.z) - double(r_a.z)) * double(s);
	const double pb_x = double(r_c.x) + (double(r_d.x) - double(r_c.x)) * double(t);
	const double pb_y = double(r_c.y) + (double(r_d.y) - double(r_c.y)) * double(t);
	const double pb_z = double(r_c.z) + (double(r_d.z) - double(r_c.z)) * double(t);
	const double signed_separation = (pa_x - pb_x) * double(p_normal.x) +
			(pa_y - pb_y) * double(p_normal.y) +
			(pa_z - pb_z) * double(p_normal.z);
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
