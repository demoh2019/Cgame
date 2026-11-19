/**************************************************************************/
/*  physics_speculative_capsule_pair_contact.h                            */
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

#include "core/math/geometry_2d.h"
#include "core/math/geometry_3d.h"
#include "servers/physics_ccd_capsule_pair_toi.h"

// Closest points are computed only for candidates admitted by broadphase.
// The existing engine geometry helpers avoid duplicating segment algorithms.
_FORCE_INLINE_ void physics_speculative_capsule_closest_points(
		const Vector2 &p_a0, const Vector2 &p_a1,
		const Vector2 &p_b0, const Vector2 &p_b1,
		Vector2 &r_a, Vector2 &r_b) {
	Geometry2D::get_closest_points_between_segments(p_a0, p_a1, p_b0, p_b1, r_a, r_b);
}

_FORCE_INLINE_ void physics_speculative_capsule_closest_points(
		const Vector3 &p_a0, const Vector3 &p_a1,
		const Vector3 &p_b0, const Vector3 &p_b1,
		Vector3 &r_a, Vector3 &r_b) {
	Geometry3D::get_closest_points_between_segments(p_a0, p_a1, p_b0, p_b1, r_a, r_b);
}

// Generates separated contact anchors on actual capsule surfaces.
// Input axes can be skew, and the sphere-capsule Minkowski approximation
// is deliberately NOT used for general skew capsules. Instead use the
// capsule-pair iterative TOI already verified by CCD.
// Only nonrotating, uniform-scale capsule pairs may call this helper.
template <typename Vector>
_FORCE_INLINE_ bool physics_speculative_capsule_pair_contact(
		const Vector &p_center_a, const Vector &p_center_b,
		const Vector &p_axis_a, const Vector &p_axis_b,
		real_t p_half_a, real_t p_half_b,
		real_t p_radius_a, real_t p_radius_b,
		const Vector &p_relative_motion, real_t p_max_gap,
		Vector &r_point_a, Vector &r_point_b, Vector &r_normal) {
	if (!p_center_a.is_finite() || !p_center_b.is_finite() ||
			!p_axis_a.is_finite() || !p_axis_b.is_finite() ||
			!p_relative_motion.is_finite() ||
			!Math::is_finite(p_half_a) || !Math::is_finite(p_half_b) ||
			!Math::is_finite(p_radius_a) || !Math::is_finite(p_radius_b) ||
			!Math::is_finite(p_max_gap) ||
			p_half_a < 0.0 || p_half_b < 0.0 ||
			p_radius_a <= 0.0 || p_radius_b <= 0.0 || p_max_gap <= 0.0) {
		return false;
	}
	const real_t axis_length_a = p_axis_a.length();
	const real_t axis_length_b = p_axis_b.length();
	if (!(axis_length_a > 0.0 && axis_length_b > 0.0) ||
			!Math::is_finite(axis_length_a) || !Math::is_finite(axis_length_b)) {
		return false;
	}
	const Vector segment_a = p_axis_a * (p_half_a / axis_length_a);
	const Vector segment_b = p_axis_b * (p_half_b / axis_length_b);
	Vector centerline_a, centerline_b;
	physics_speculative_capsule_closest_points(
			p_center_a - segment_a, p_center_a + segment_a,
			p_center_b - segment_b, p_center_b + segment_b,
			centerline_a, centerline_b);
	const Vector delta = centerline_b - centerline_a;
	const real_t length_squared = delta.length_squared();
	if (!(length_squared > 0.0) || !Math::is_finite(length_squared)) {
		return false;
	}
	const real_t distance = Math::sqrt(length_squared);
	const double gap = double(distance) - double(p_radius_a) - double(p_radius_b);
	if (!(gap > 0.0 && gap <= double(p_max_gap))) {
		return false;
	}
	const Vector normal = delta / distance;
	// The closest initial separating plane gives a necessary condition
	// for linear impact. Avoid expensive TOI on slowly approaching pairs.
	const real_t travel = p_relative_motion.dot(normal);
	if (Math::is_finite(travel)) {
		const double slack = double(CMP_EPSILON) * MAX(1.0, Math::abs(double(travel)));
		if (double(travel) + slack < gap) {
			return false;
		}
	}
	double fraction = 0.0;
	if (physics_ccd_capsule_pair_toi(p_center_a - p_center_b, p_relative_motion,
			p_axis_a, p_axis_b, p_half_a, p_half_b,
			double(p_radius_a) + double(p_radius_b), fraction) != PhysicsCCDCapsulePairTOIResult::HIT) {
		return false;
	}
	const Vector point_a = centerline_a + normal * p_radius_a;
	const Vector point_b = centerline_b - normal * p_radius_b;
	if (!point_a.is_finite() || !point_b.is_finite() || !normal.is_finite()) {
		return false;
	}
	r_point_a = point_a;
	r_point_b = point_b;
	r_normal = normal;
	return true;
}
