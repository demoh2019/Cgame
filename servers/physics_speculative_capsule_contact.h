/**************************************************************************/
/*  physics_speculative_capsule_contact.h                                 */
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

#include "servers/physics_ccd_capsule_toi.h"

// Both centers, the motion, and the returned anchors use capsule-local space.
// The capsule's centerline is the Y segment [-half_segment, half_segment].
// r_normal points from the sphere/circle towards the capsule. The points
// belong to the actual surfaces, giving a negative solver depth while apart.
// This is an allocation-free opt-in narrowphase path for nonrotating objects.
// The caller must use an orthogonal, uniform-scale capsule transform.
template <typename Vector>
_FORCE_INLINE_ bool physics_speculative_sphere_capsule_contact(
		const Vector &p_sphere_center, real_t p_sphere_radius, real_t p_capsule_radius,
		real_t p_half_segment, const Vector &p_relative_motion, real_t p_max_gap,
		Vector &r_sphere_point, Vector &r_capsule_point, Vector &r_normal) {
	if (!p_sphere_center.is_finite() || !p_relative_motion.is_finite() ||
			!Math::is_finite(p_sphere_radius) || !Math::is_finite(p_capsule_radius) ||
			!Math::is_finite(p_half_segment) || !Math::is_finite(p_max_gap) ||
			p_sphere_radius <= 0.0 || p_capsule_radius <= 0.0 ||
			p_half_segment < 0.0 || p_max_gap <= 0.0) {
		return false;
	}

	Vector centerline_point;
	centerline_point.y = CLAMP(p_sphere_center.y, -p_half_segment, p_half_segment);
	const Vector towards_capsule = centerline_point - p_sphere_center;
	const real_t distance_squared = towards_capsule.length_squared();
	if (!Math::is_finite(distance_squared) || !(distance_squared > 0.0)) {
		return false;
	}
	const real_t distance = Math::sqrt(distance_squared);
	const real_t gap = distance - (p_sphere_radius + p_capsule_radius);
	if (!(gap > 0.0 && gap <= p_max_gap)) {
		return false;
	}

	// A capsule is convex. The supporting plane through its closest
	// surface point must be reached before a linear sweep can hit it.
	// Reject slow/receding motion before the more expensive TOI evaluation.
	// A tolerance keeps almost-tangent boundary contacts eligible.
	const Vector normal = towards_capsule / distance;
	const real_t radial_travel = p_relative_motion.dot(normal);
	if (Math::is_finite(radial_travel)) {
		const double travel = double(radial_travel);
		const double slack = double(CMP_EPSILON) * MAX(1.0, Math::abs(travel));
		if (travel + slack < double(gap)) {
			return false;
		}
	}

	// A radial approach may miss a capsule cap when moving sideways.
	// Reuse the exact linear CCD test, not an approximate closing-speed test.
	double impact_fraction = 0.0;
	if (!physics_ccd_capsule_toi(p_sphere_center, p_relative_motion,
				double(p_sphere_radius) + double(p_capsule_radius),
				double(p_half_segment), impact_fraction)) {
		return false;
	}

	const Vector sphere_point = p_sphere_center + normal * p_sphere_radius;
	const Vector capsule_point = centerline_point - normal * p_capsule_radius;
	if (!sphere_point.is_finite() || !capsule_point.is_finite()) {
		return false;
	}
	r_sphere_point = sphere_point;
	r_capsule_point = capsule_point;
	r_normal = normal;
	return true;
}
