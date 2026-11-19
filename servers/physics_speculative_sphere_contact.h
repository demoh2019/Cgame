/**************************************************************************/
/*  physics_speculative_sphere_contact.h                                  */
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

#include "core/math/vector2.h"
#include "core/math/vector3.h"
#include "servers/physics_ccd_sphere_toi.h"

// Keep the common float32 hot path, but recover large finite separations
// without squaring a float32 vector into infinity. This also works in double
// precision builds and introduces no state or heap allocation.
_FORCE_INLINE_ static double physics_speculative_sphere_length_squared_wide(const Vector2 &p_delta) {
	return double(p_delta.x) * p_delta.x + double(p_delta.y) * p_delta.y;
}

_FORCE_INLINE_ static double physics_speculative_sphere_length_squared_wide(const Vector3 &p_delta) {
	return double(p_delta.x) * p_delta.x + double(p_delta.y) * p_delta.y + double(p_delta.z) * p_delta.z;
}

_FORCE_INLINE_ static Vector2 physics_speculative_sphere_normal_wide(const Vector2 &p_delta, double p_distance) {
	return Vector2(real_t(double(p_delta.x) / p_distance), real_t(double(p_delta.y) / p_distance));
}

_FORCE_INLINE_ static Vector3 physics_speculative_sphere_normal_wide(const Vector3 &p_delta, double p_distance) {
	return Vector3(real_t(double(p_delta.x) / p_distance), real_t(double(p_delta.y) / p_distance),
			real_t(double(p_delta.z) / p_distance));
}

// Return an unpenetrated contact for an approaching pair of actual circles
// or spheres, not the inflated points from a shape-margin SAT query.
// Normals point from A to B; depth = dot(pointA - pointB, normal) is negative.
// This is conservative in scope: broadphase must already own the pair,
// both shapes must retain spherical geometry, and neither may rotate.
template <typename Vector>
_FORCE_INLINE_ bool physics_speculative_sphere_contact(
		const Vector &p_center_a, real_t p_radius_a, const Vector &p_center_b, real_t p_radius_b,
		const Vector &p_velocity_a, const Vector &p_velocity_b,
		real_t p_step, real_t p_max_gap,
		Vector &r_point_a, Vector &r_point_b, Vector &r_normal) {
	if (!p_center_a.is_finite() || !p_center_b.is_finite() ||
			!p_velocity_a.is_finite() || !p_velocity_b.is_finite() ||
			!Math::is_finite(p_radius_a) || !Math::is_finite(p_radius_b) ||
			!Math::is_finite(p_step) || !Math::is_finite(p_max_gap) ||
			p_radius_a <= 0.0 || p_radius_b <= 0.0 || p_step <= 0.0 || p_max_gap <= 0.0) {
		return false;
	}

	const Vector center_delta = p_center_b - p_center_a;
	const real_t distance_squared = center_delta.length_squared();
	double distance;
	Vector normal;
	if (Math::is_finite(distance_squared) && distance_squared > real_t(0.0)) {
		// Preserve the original fast path and rounding for ordinary scenes.
		const real_t short_distance = Math::sqrt(distance_squared);
		distance = short_distance;
		normal = center_delta / short_distance;
	} else {
		// A finite center delta may have an infinite float32 squared length.
		// Calculate in double and normalize each component before narrowing.
		const double wide_squared = physics_speculative_sphere_length_squared_wide(center_delta);
		if (!Math::is_finite(wide_squared) || wide_squared <= 0.0) {
			return false;
		}
		distance = Math::sqrt(wide_squared);
		normal = physics_speculative_sphere_normal_wide(center_delta, distance);
	}
	const double gap = distance - (double(p_radius_a) + double(p_radius_b));
	if (!(gap > 0.0 && gap <= double(p_max_gap))) {
		return false;
	}
	// Radial closing speed alone produces ghost contacts for glancing paths
	// with large tangential motion. Use the exact linear sphere TOI instead:
	// the pair must actually reach its Minkowski contact surface this step.
	Vector relative_motion = (p_velocity_a - p_velocity_b) * p_step;
	if (!relative_motion.is_finite()) {
		// Opposing finite float32 velocities can overflow on subtraction,
		// although their displacement during a short step is representable.
		relative_motion = p_velocity_a * p_step - p_velocity_b * p_step;
	}
	if (!relative_motion.is_finite()) {
		return false;
	}
	// Necessary condition for a sphere hit: even the projected motion along
	// the initial separation normal must close the gap by the end of this
	// step. Near-stationary pairs can skip the costlier exact TOI query.
	// Use a conservative floating-point slack for boundary contacts.
	const real_t radial_travel = relative_motion.dot(normal);
	if (Math::is_finite(radial_travel)) {
		const double travel = double(radial_travel);
		const double slack = double(CMP_EPSILON) * MAX(1.0, Math::abs(travel));
		if (travel + slack < gap) {
			return false;
		}
	}
	double impact_fraction = 0.0;
	if (!physics_ccd_sphere_toi(-center_delta, relative_motion,
				double(p_radius_a) + double(p_radius_b), impact_fraction)) {
		return false;
	}
	const Vector point_a = p_center_a + normal * p_radius_a;
	const Vector point_b = p_center_b - normal * p_radius_b;
	if (!point_a.is_finite() || !point_b.is_finite()) {
		return false;
	}
	r_point_a = point_a;
	r_point_b = point_b;
	r_normal = normal;
	return true;
}
