/**************************************************************************/
/*  physics_softbody_ccd.h                                                */
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

#include "servers/physics_softbody_self_collision.h"

// Conservative advancement of a *distance* constraint along piecewise
// linear particle trajectories. The Lipschitz bound is the greatest relative
// endpoint displacement, hence distance cannot decrease faster than this
// bound over one normalized physical step. Advance by 90% of the safe step
// toward contact instead of blindly sampling times at fixed intervals.
//
// This is bounded approximate CCD, NOT exact root isolation. After 48
// iterations a very narrow/high-speed grazing contact may still be missed.
// Return false when already overlapping at t=0: the regular discrete solver
// handles persistent contacts. r_t is changed only for a fresh swept hit.
template <typename DistanceAtTime>
_FORCE_INLINE_ bool physics_softbody_ccd_conservative_advance(
		DistanceAtTime p_distance_at_time, real_t p_motion_bound,
		real_t p_thickness, real_t &r_t) {
	if (!(p_thickness > 0.0) || !(p_motion_bound > CMP_EPSILON) ||
			!Math::is_finite(p_thickness) || !Math::is_finite(p_motion_bound)) {
		return false;
	}
	const double bound = double(p_motion_bound);
	const double thickness = double(p_thickness);
	const double tolerance = MAX(1e-6, thickness * 1e-4);
	double t = 0.0;
	for (int iteration = 0; iteration < 48; ++iteration) {
		real_t distance = 0.0;
		if (!p_distance_at_time(real_t(t), distance) ||
				!Math::is_finite(distance) || distance < 0.0) {
			return false; // Degenerate geometry at an intermediate time.
		}
		if (iteration == 0 && double(distance) <= thickness) {
			return false; // Already touching: let the discrete solver act.
		}
		const double gap = double(distance) - thickness;
		if (gap <= tolerance) {
			r_t = real_t(t);
			return true;
		}
		if (t >= 1.0) {
			return false;
		}
		const double advance = 0.9 * gap / bound;
		if (!(advance > 0.0) || !Math::is_finite(advance)) {
			return false;
		}
		const double next_t = MIN(1.0, t + advance);
		if (next_t <= t) {
			return false;
		}
		t = next_t;
	}
	return false;
}

// A moving vertex against a linearly deforming triangle. Each instantaneous
// point-to-triangle distance is computed from the actual triangle at time t,
// not from a frozen face normal. max relative endpoint motion is a valid
// upper bound for the rate of decrease of that minimum distance.
_FORCE_INLINE_ bool physics_softbody_ccd_point_triangle(
		const Vector3 &p_old_point, const Vector3 &p_new_point,
		const Vector3 &p_old_a, const Vector3 &p_new_a,
		const Vector3 &p_old_b, const Vector3 &p_new_b,
		const Vector3 &p_old_c, const Vector3 &p_new_c,
		real_t p_thickness, real_t &r_t) {
	if (!p_old_point.is_finite() || !p_new_point.is_finite() ||
			!p_old_a.is_finite() || !p_new_a.is_finite() ||
			!p_old_b.is_finite() || !p_new_b.is_finite() ||
			!p_old_c.is_finite() || !p_new_c.is_finite()) {
		return false;
	}
	const Vector3 point_motion = p_new_point - p_old_point;
	const real_t bound = MAX(
			(point_motion - (p_new_a - p_old_a)).length(),
			MAX((point_motion - (p_new_b - p_old_b)).length(),
					(point_motion - (p_new_c - p_old_c)).length()));
	const auto distance_at_time = [&](real_t t, real_t &r_distance) -> bool {
		const Vector3 point = p_old_point.lerp(p_new_point, t);
		const Vector3 a = p_old_a.lerp(p_new_a, t);
		const Vector3 b = p_old_b.lerp(p_new_b, t);
		const Vector3 c = p_old_c.lerp(p_new_c, t);
		Vector3 closest, barycentric;
		if (!physics_softbody_closest_triangle_point(point, a, b, c, closest, barycentric)) {
			return false;
		}
		r_distance = point.distance_to(closest);
		return Math::is_finite(r_distance);
	};
	return physics_softbody_ccd_conservative_advance(distance_at_time, bound, p_thickness, r_t);
}

// Two moving edges; closest points are recomputed at every conservative
// advancement sample, so moving/skew/parallel finite segments are supported.
_FORCE_INLINE_ bool physics_softbody_ccd_edge_edge(
		const Vector3 &p_old_a, const Vector3 &p_new_a,
		const Vector3 &p_old_b, const Vector3 &p_new_b,
		const Vector3 &p_old_c, const Vector3 &p_new_c,
		const Vector3 &p_old_d, const Vector3 &p_new_d,
		real_t p_thickness, real_t &r_t) {
	if (!p_old_a.is_finite() || !p_new_a.is_finite() ||
			!p_old_b.is_finite() || !p_new_b.is_finite() ||
			!p_old_c.is_finite() || !p_new_c.is_finite() ||
			!p_old_d.is_finite() || !p_new_d.is_finite()) {
		return false;
	}
	const Vector3 va = p_new_a - p_old_a;
	const Vector3 vb = p_new_b - p_old_b;
	const Vector3 vc = p_new_c - p_old_c;
	const Vector3 vd = p_new_d - p_old_d;
	const real_t bound = MAX(MAX((va - vc).length(), (va - vd).length()),
			MAX((vb - vc).length(), (vb - vd).length()));
	const auto distance_at_time = [&](real_t t, real_t &r_distance) -> bool {
		const Vector3 a = p_old_a.lerp(p_new_a, t);
		const Vector3 b = p_old_b.lerp(p_new_b, t);
		const Vector3 c = p_old_c.lerp(p_new_c, t);
		const Vector3 d = p_old_d.lerp(p_new_d, t);
		Vector3 on_ab, on_cd;
		real_t s, u;
		if (!physics_softbody_closest_segment_points(a, b, c, d, on_ab, on_cd, s, u)) {
			return false;
		}
		r_distance = on_ab.distance_to(on_cd);
		return Math::is_finite(r_distance);
	};
	return physics_softbody_ccd_conservative_advance(distance_at_time, bound, p_thickness, r_t);
}
